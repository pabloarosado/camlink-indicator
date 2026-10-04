#import <AppKit/AppKit.h>
#import <IOKit/hid/IOHIDManager.h>
#import <QuartzCore/QuartzCore.h>

// Cam Link 4K revision 3 (0fd9:00a1). Protocol traced from Camera Hub 2.3.0.
// Only a read request for the input status block is sent. No video APIs are used.
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
static NSDictionary *query(void) {
    IOHIDManagerRef manager=IOHIDManagerCreate(kCFAllocatorDefault,kIOHIDOptionsTypeNone);
    if(!manager) return result(@"unknown", @"Cannot create HID manager");
    NSDictionary *matching=@{@kIOHIDVendorIDKey:@0x0fd9, @kIOHIDProductIDKey:@0x00a1,
                             @kIOHIDPrimaryUsagePageKey:@0xffa0, @kIOHIDPrimaryUsageKey:@1};
    IOHIDManagerSetDeviceMatching(manager,(__bridge CFDictionaryRef)matching);
    CFSetRef devices=IOHIDManagerCopyDevices(manager);
    NSDictionary *answer;
    CFIndex count=devices ? CFSetGetCount(devices):0;
    if(count != 1) {
        answer=result(@"unknown", count ? @"Multiple Cam Links connected" : @"Revision 3 Cam Link unavailable");
    } else {
        IOHIDDeviceRef device;
        CFSetGetValues(devices,(const void **)&device);
        // Shared access; never seize the device or its UVC video interface.
        IOReturn code=IOHIDDeviceOpen(device,kIOHIDOptionsTypeNone);
        if(code) answer=failure(@"HID access",code);
        else {
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
            IOHIDDeviceClose(device,kIOHIDOptionsTypeNone);
        }
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
            puts("Status parser checks passed"); return 0;
        }
        NSApplication *app=NSApplication.sharedApplication;
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        Indicator *delegate=[Indicator new]; app.delegate=delegate;
        [app run];
    }
    return 0;
}
