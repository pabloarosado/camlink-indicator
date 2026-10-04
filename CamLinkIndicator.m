#import <AppKit/AppKit.h>
#import <IOKit/hid/IOHIDManager.h>
#import <IOKit/IOKitLib.h>
#import <QuartzCore/QuartzCore.h>

// Revision 3: protocol traced from Camera Hub 2.3.0 and tested on hardware.
// First generation: experimental port of the published GET_REPORT 0x13 protocol.
// No video APIs are used. See docs/PROTOCOL.md for sources and test coverage.
typedef NS_ENUM(NSInteger, StatusProtocol) { Unsupported, Revision3, FirstGeneration };
static StatusProtocol protocolForModel(unsigned vendor, unsigned product) {
    if(vendor != 0x0fd9) return Unsupported;
    if(product == 0x00a1) return Revision3;
    if(product == 0x0066 || product == 0x0067) return FirstGeneration;
    return Unsupported;
}
static NSDictionary *result(NSString *state, NSString *detail) {
    return @{ @"state":state, @"detail":detail };
}
static NSDictionary *failure(NSString *operation, IOReturn code) {
    return result(@"unknown", [NSString stringWithFormat:@"%@ failed (0x%08x)",operation,code]);
}
static NSDictionary *decode(const uint8_t *bytes, CFIndex length) {
    // Response: success byte (0), then 8 bytes of input status.
    if(length != 9 || bytes[0] != 0)
        return result(@"unknown", @"Unexpected status response");
    const uint8_t *status=bytes+1;
    if(!(status[6] & 4)) return result(@"no-signal", @"No HDMI signal detected");
    unsigned width=status[1] | (status[2]<<8);
    unsigned height=status[3] | (status[4]<<8);
    if(!width || !height || !status[5]) return result(@"unknown", @"Incomplete HDMI status");
    double fps=status[5];
    if(status[6] & 2) fps/=1.001;
    return result(@"signal", [NSString stringWithFormat:@"HDMI signal: %u × %u at %.2f fps",width,height,fps]);
}
static NSDictionary *decodeFirstGeneration(const uint8_t *bytes, CFIndex length) {
    // Unlike revision 3, these six bytes have no status or report-ID prefix.
    if(length != 6 || bytes[5] > 1)
        return result(@"unknown", @"Unexpected first-generation status response");
    if(!bytes[5]) return result(@"no-signal", @"No HDMI signal detected");
    unsigned width=bytes[0] | (bytes[1]<<8), height=bytes[2] | (bytes[3]<<8);
    if(!width || !height || !bytes[4]) return result(@"unknown", @"Incomplete HDMI status");
    return result(@"signal", [NSString stringWithFormat:@"HDMI signal: %u × %u at %u fps",width,height,bytes[4]]);
}

// USB enumeration only: no device open, control requests, video, or serial numbers.
static int checkCompatibility(void) {
    io_iterator_t iterator=0;
    kern_return_t code=IOServiceGetMatchingServices(kIOMainPortDefault,IOServiceMatching("IOUSBHostDevice"),&iterator);
    if(code) { fprintf(stderr,"Cannot inspect USB devices (0x%08x).\n",code); return 2; }
    unsigned found=0;
    io_service_t device;
    while((device=IOIteratorNext(iterator))) {
        NSNumber *vendor=CFBridgingRelease(IORegistryEntryCreateCFProperty(device,CFSTR("idVendor"),NULL,0));
        NSNumber *product=CFBridgingRelease(IORegistryEntryCreateCFProperty(device,CFSTR("idProduct"),NULL,0));
        if(vendor.unsignedIntValue==0x0fd9) {
            unsigned pid=product.unsignedIntValue;
            NSString *description;
            switch(protocolForModel(vendor.unsignedIntValue,pid)) {
                case Revision3: description=@"Cam Link 4K revision 3 — supported; hardware-tested on one setup."; break;
                case FirstGeneration: description=@"First-generation Cam Link 4K — experimental; needs macOS hardware testing."; break;
                default:
                    if(pid==0x7b || pid==0x85) description=@"Cam Link 4K MK.2 — not supported yet.";
                    else if(pid==0xa2) description=@"Cam Link 4K revision 3 in USB 2.0 mode — not supported; try a USB 3 port/cable.";
                    else description=@"Elgato device — this model is not supported.";
            }
            printf("%s\nUSB model ID: 0fd9:%04x\n\n",description.UTF8String,pid);
            found++;
        }
        IOObjectRelease(device);
    }
    IOObjectRelease(iterator);
    if(!found) puts("No Elgato USB device found. Connect your Cam Link and try again. Other capture-card brands are not supported.");
    return 0;
}
static NSDictionary *query(void) {
    IOHIDManagerRef manager=IOHIDManagerCreate(kCFAllocatorDefault,kIOHIDOptionsTypeNone);
    if(!manager) return result(@"unknown", @"Cannot create HID manager");
    NSArray *matching=@[
        @{@kIOHIDVendorIDKey:@0x0fd9, @kIOHIDProductIDKey:@0x00a1,
          @kIOHIDPrimaryUsagePageKey:@0xffa0, @kIOHIDPrimaryUsageKey:@1},
        @{@kIOHIDVendorIDKey:@0x0fd9, @kIOHIDProductIDKey:@0x0066, @kIOHIDPrimaryUsagePageKey:@0xff00},
        @{@kIOHIDVendorIDKey:@0x0fd9, @kIOHIDProductIDKey:@0x0067, @kIOHIDPrimaryUsagePageKey:@0xff00}
    ];
    IOHIDManagerSetDeviceMatchingMultiple(manager,(__bridge CFArrayRef)matching);
    CFSetRef devices=IOHIDManagerCopyDevices(manager);
    NSDictionary *answer;
    CFIndex count=devices ? CFSetGetCount(devices):0;
    if(count != 1) {
        answer=result(@"unknown", count ? @"Connect one supported Cam Link at a time" : @"No supported Cam Link detected; run check-device.sh for details");
    } else {
        IOHIDDeviceRef device;
        CFSetGetValues(devices,(const void **)&device);
        NSNumber *vendor=(__bridge NSNumber *)IOHIDDeviceGetProperty(device,CFSTR(kIOHIDVendorIDKey));
        NSNumber *product=(__bridge NSNumber *)IOHIDDeviceGetProperty(device,CFSTR(kIOHIDProductIDKey));
        StatusProtocol protocol=protocolForModel(vendor.unsignedIntValue,product.unsignedIntValue);
        // Shared access; never seize the device or its UVC video interface.
        IOReturn code=IOHIDDeviceOpen(device,kIOHIDOptionsTypeNone);
        BOOL opened=(code==kIOReturnSuccess);
        if(code) answer=failure(@"HID access",code);
        else if(protocol==Revision3) {
            // Output report 6; payload 06 07 55 01 00 08 = read 8 bytes from
            // virtual I2C address 0x55, register 0. First 06 is the report ID.
            const uint8_t request[]={6,6,7,0x55,1,0,8};
            code=IOHIDDeviceSetReport(device,kIOHIDReportTypeOutput,6,request,sizeof(request));
            if(code) answer=failure(@"Status request",code);
            else {
                uint8_t response[4097]={5};
                CFIndex length=0x7ff;
                code=IOHIDDeviceGetReport(device,kIOHIDReportTypeInput,5,response,&length);
                answer=code ? failure(@"Status response",code) : decode(response,length);
            }
        } else if(protocol==FirstGeneration) {
            // Read only; never send revision 3's Output report 6 to this model.
            uint8_t response[6]={0x13}; CFIndex length=sizeof(response);
            code=IOHIDDeviceGetReport(device,kIOHIDReportTypeInput,0x13,response,&length);
            answer=code ? failure(@"First-generation status read",code) : decodeFirstGeneration(response,length);
            answer=result(answer[@"state"], [@"Experimental: " stringByAppendingString:answer[@"detail"]]);
        } else {
            answer=result(@"unknown",@"Unsupported Cam Link model");
        }
        // Close only if the open succeeded, regardless of subsequent read errors.
        if(opened) IOHIDDeviceClose(device,kIOHIDOptionsTypeNone);
    }
    if(devices) CFRelease(devices);
    CFRelease(manager);
    return answer;
}

@interface Indicator : NSObject <NSApplicationDelegate>
@property NSStatusItem *item;
@property NSMenuItem *statusLine;
@property NSMenuItem *detailLine;
@property NSMenuItem *checkedLine;
@property NSMenuItem *pulseMenu;
@property NSTimer *timer;
@property BOOL busy;
@property BOOL signalPresent;
@property BOOL pulseEnabled;
@property NSUInteger generation;
@end

@implementation Indicator
- (void)updatePulse {
    CALayer *layer=self.item.button.layer;
    if(self.signalPresent && self.pulseEnabled) {
        if(![layer animationForKey:@"cameraPulse"]) {
            // A two-second brightness cycle. The dot always remains visible;
            // animation is local and does not trigger device queries.
            CABasicAnimation *pulse=[CABasicAnimation animationWithKeyPath:@"opacity"];
            pulse.fromValue=@1.0;
            pulse.toValue=@0.45;
            pulse.duration=1.0;
            pulse.autoreverses=YES;
            pulse.repeatCount=HUGE_VALF;
            pulse.timingFunction=[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
            [layer addAnimation:pulse forKey:@"cameraPulse"];
        }
    } else {
        [layer removeAnimationForKey:@"cameraPulse"];
    }
    self.pulseMenu.state=self.pulseEnabled ? NSControlStateValueOn : NSControlStateValueOff;
}
- (void)togglePulse:(id)sender {
    self.pulseEnabled=!self.pulseEnabled;
    [NSUserDefaults.standardUserDefaults setBool:self.pulseEnabled forKey:@"PulseWhenOn"];
    [self updatePulse];
}
- (void)show:(NSDictionary *)value {
    NSString *state=value[@"state"];
    BOOL on=[state isEqualToString:@"signal"], off=[state isEqualToString:@"no-signal"];
    NSColor *color=on ? NSColor.systemRedColor : off ? NSColor.secondaryLabelColor : NSColor.systemOrangeColor;
    NSString *title=on ? @"Camera HDMI signal detected" : off ? @"No HDMI signal" : @"Camera status unknown";
    self.signalPresent=on;
    NSImage *dot=[NSImage imageWithSize:NSMakeSize(20,20) flipped:NO drawingHandler:^BOOL(NSRect rect) {
        [color setFill];
        NSRect circle=on ? NSMakeRect(1,1,18,18) : NSMakeRect(4,4,12,12);
        [[NSBezierPath bezierPathWithOvalInRect:circle] fill];
        if(!on && !off) {
            [@"?" drawAtPoint:NSMakePoint(7,4) withAttributes:@{
                NSFontAttributeName:[NSFont boldSystemFontOfSize:10], NSForegroundColorAttributeName:NSColor.blackColor}];
        }
        return YES;
    }];
    dot.template=NO;
    self.item.button.image=dot;
    self.item.button.toolTip=[NSString stringWithFormat:@"%@: %@",title,value[@"detail"]];
    self.item.button.accessibilityLabel=title;
    self.statusLine.title=title;
    self.detailLine.title=value[@"detail"];
    [self updatePulse];
}
- (void)refresh:(id)sender {
    if(self.busy) return;
    self.busy=YES;
    NSUInteger generation=++self.generation;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0), ^{
        NSDictionary *value=query();
        dispatch_async(dispatch_get_main_queue(), ^{
            self.busy=NO;
            if(generation!=self.generation) { [self refresh:nil]; return; }
            [self show:value];
            self.checkedLine.title=[@"Checked: " stringByAppendingString:
                [NSDateFormatter localizedStringFromDate:NSDate.date dateStyle:NSDateFormatterNoStyle timeStyle:NSDateFormatterMediumStyle]];
        });
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,10*NSEC_PER_SEC),dispatch_get_main_queue(), ^{
        if(self.busy && generation==self.generation) {
            [self show:result(@"unknown",@"Status query timed out; waiting for device")];
        }
    });
}
- (void)sleep:(NSNotification *)notification {
    self.generation++;
    [self show:result(@"unknown",@"Mac is sleeping; status will refresh on wake")];
}
- (void)wake:(NSNotification *)notification {
    self.generation++;
    [self show:result(@"unknown",@"Refreshing after wake")];
    [self refresh:nil];
}
- (void)quit:(id)sender { [NSApp terminate:nil]; }
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    if([NSRunningApplication runningApplicationsWithBundleIdentifier:NSBundle.mainBundle.bundleIdentifier].count>1) {
        [NSApp terminate:nil]; return;
    }
    [NSUserDefaults.standardUserDefaults registerDefaults:@{@"PulseWhenOn":@YES}];
    self.pulseEnabled=[NSUserDefaults.standardUserDefaults boolForKey:@"PulseWhenOn"];
    self.item=[NSStatusBar.systemStatusBar statusItemWithLength:28];
    self.item.button.wantsLayer=YES;
    NSMenu *menu=[NSMenu new]; menu.autoenablesItems=NO;
    self.statusLine=[menu addItemWithTitle:@"Checking camera…" action:nil keyEquivalent:@""];
    self.detailLine=[menu addItemWithTitle:@"" action:nil keyEquivalent:@""];
    self.checkedLine=[menu addItemWithTitle:@"" action:nil keyEquivalent:@""];
    self.statusLine.enabled=NO; self.detailLine.enabled=NO; self.checkedLine.enabled=NO;
    [menu addItem:NSMenuItem.separatorItem];
    NSMenuItem *note=[menu addItemWithTitle:@"Checks HDMI signal every 5 seconds" action:nil keyEquivalent:@""];
    note.enabled=NO;
    note=[menu addItemWithTitle:@"No signal does not prove camera power is off" action:nil keyEquivalent:@""];
    note.enabled=NO;
    [menu addItem:NSMenuItem.separatorItem];
    self.pulseMenu=[menu addItemWithTitle:@"Pulse when camera is on" action:@selector(togglePulse:) keyEquivalent:@""];
    self.pulseMenu.target=self;
    [menu addItemWithTitle:@"Refresh now" action:@selector(refresh:) keyEquivalent:@"r"].target=self;
    [menu addItemWithTitle:@"Quit Cam Link Indicator" action:@selector(quit:) keyEquivalent:@"q"].target=self;
    self.item.menu=menu;
    [self show:result(@"unknown",@"Checking HDMI signal")];
    self.timer=[NSTimer timerWithTimeInterval:5 target:self selector:@selector(refresh:) userInfo:nil repeats:YES];
    self.timer.tolerance=0.25;
    [NSRunLoop.mainRunLoop addTimer:self.timer forMode:NSRunLoopCommonModes];
    [NSWorkspace.sharedWorkspace.notificationCenter addObserver:self selector:@selector(sleep:) name:NSWorkspaceWillSleepNotification object:nil];
    [NSWorkspace.sharedWorkspace.notificationCenter addObserver:self selector:@selector(wake:) name:NSWorkspaceDidWakeNotification object:nil];
    [self refresh:nil];
}
@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if(argc==2 && strcmp(argv[1],"--check")==0) return checkCompatibility();
        if(argc==2 && strcmp(argv[1],"--status")==0) {
            NSDictionary *value=query();
            NSData *json=[NSJSONSerialization dataWithJSONObject:value options:NSJSONWritingSortedKeys error:nil];
            puts([[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding].UTF8String);
            return [value[@"state"] isEqualToString:@"unknown"] ? 2:0;
        }
        if(argc==2 && strcmp(argv[1],"--self-test")==0) {
            uint8_t on[]={0,0,0,15,112,8,25,84,0};
            uint8_t off[]={0,0,0,15,112,8,25,80,0};
            uint8_t error[]={1,0,0,15,112,8,25,80,0};
            NSCAssert([decode(on,9)[@"state"] isEqual:@"signal"],@"On response");
            NSCAssert([decode(off,9)[@"state"] isEqual:@"no-signal"],@"Signal bit clear");
            NSCAssert([decode(error,9)[@"state"] isEqual:@"unknown"],@"Error is unknown");
            NSCAssert([decode(on,8)[@"state"] isEqual:@"unknown"],@"Short response is unknown");
            uint8_t legacyOn[]={0x80,0x07,0x38,0x04,60,1};
            uint8_t legacyOff[]={0x00,0x0f,0x70,0x08,30,0};
            uint8_t invalidFlag[]={0x80,0x07,0x38,0x04,60,2};
            uint8_t incomplete[]={0,0,0x38,0x04,60,1};
            NSCAssert([decodeFirstGeneration(legacyOn,6)[@"state"] isEqual:@"signal"],@"Legacy on");
            NSCAssert([decodeFirstGeneration(legacyOff,6)[@"state"] isEqual:@"no-signal"],@"Stored resolution is not a signal");
            NSCAssert([decodeFirstGeneration(legacyOn,5)[@"state"] isEqual:@"unknown"],@"Legacy short reply");
            NSCAssert([decodeFirstGeneration(invalidFlag,6)[@"state"] isEqual:@"unknown"],@"Legacy invalid flag");
            NSCAssert([decodeFirstGeneration(incomplete,6)[@"state"] isEqual:@"unknown"],@"Legacy incomplete timing");
            NSCAssert(protocolForModel(0x0fd9,0x00a1)==Revision3,@"Revision 3 route");
            NSCAssert(protocolForModel(0x0fd9,0x0066)==FirstGeneration,@"First-generation route");
            NSCAssert(protocolForModel(0x0fd9,0x0067)==FirstGeneration,@"First-generation USB 2 route");
            NSCAssert(protocolForModel(0x0fd9,0x007b)==Unsupported,@"Do not guess MK.2 protocol");
            NSCAssert(protocolForModel(0x0fd9,0x00a2)==Unsupported,@"Do not guess revision 3 USB 2 protocol");
            NSCAssert(protocolForModel(0x1234,0x00a1)==Unsupported,@"Do not address other vendors");
            puts("Status parser checks passed"); return 0;
        }
        NSApplication *app=NSApplication.sharedApplication;
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        Indicator *delegate=[Indicator new]; app.delegate=delegate;
        [app run];
    }
    return 0;
}
