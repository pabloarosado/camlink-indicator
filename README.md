# Cam Link Indicator

A small macOS menu-bar reminder that your HDMI camera is still sending video through an **Elgato Cam Link 4K revision 3**. Useful if you finish a call and forget to switch the camera off.

| Indicator | Meaning |
| --- | --- |
| Large, gently pulsing red dot | HDMI signal present |
| Gray dot | No HDMI signal |
| Amber question mark | Status unavailable or a query failed |

The app checks every **5 seconds**, and when the Mac wakes. Click the dot for signal details, the last-check time, a manual refresh, and Quit. Uncheck **Pulse when camera is on** for a steady red dot; your preference is saved. The pulse is a two-second brightness cycle, and the red dot always stays visible.

**This detects HDMI signal, not the camera's power switch.** A powered camera that is sleeping, has stopped HDMI output, or has a disconnected cable can produce no signal.

## Compatibility

- **Cam Link 4K revision 3, USB ID `0fd9:00a1` only.** The app deliberately matches this ID. Check the vendor/product IDs in macOS System Information → USB.
- Tested on Apple Silicon with macOS 26, a Sony A7 III over HDMI, and Google Meet. OBS has not been separately tested.
- The protocol is about the Cam Link's HDMI input, with no Sony-specific commands. Other HDMI cameras may work with the same capture-device revision, but have not been tested.
- First-generation Cam Link 4K, MK.2, USB 2.0 mode, and other capture devices are **not supported** by this implementation. More than one matching device produces an unknown status.
- The build targets macOS 13 or later and the current Mac's architecture. Older macOS versions and Intel Macs have not been verified.

Elgato has sold different hardware under the same Cam Link 4K name. Changing a USB ID in the source does not establish compatibility with another revision.

## Build and install

Requires Apple's Command Line Tools (`xcode-select --install` if needed). No Homebrew packages, SwiftBar, Python, Xcode project, or running Camera Hub are required.

```sh
git clone https://github.com/pabloarosado/camlink-indicator.git
cd camlink-indicator
./install.sh
```

To also start automatically at login:

```sh
./install.sh --login
```

Quit an existing copy from its menu before installing an update. The installer builds and validates the app, copies it to `~/Applications/Cam Link Indicator.app`, and opens it. No `sudo` is needed. The app is locally ad-hoc signed; it is not notarized for distribution. No prebuilt binary is included.

To build without installing:

```sh
./build.sh
open 'build/Cam Link Indicator.app'
```

To change login startup after installation:

```sh
./login-item.sh enable
./login-item.sh disable
```

The login helper generates a per-user LaunchAgent using the current home directory. It opens the app once at login; it does not continually relaunch it after Quit.

## How it works

The Cam Link exposes a vendor HID control interface separately from its UVC video interface. The app opens the HID device in shared mode, requests the input status block, reads the signal flag, and closes the interface. It does not capture video or audio, seize the video interface, change camera settings, reset USB, or update firmware.

Requests run off the main thread and do not overlap. An error or unexpected reply becomes an unknown status. The pulse uses Core Animation and makes no extra USB requests.

The protocol was traced from the signal-status functions in Camera Hub 2.3.0 and checked with a physical camera switched on and off. This is an independent implementation of an undocumented protocol; it is not affiliated with Elgato, and future firmware changes may need an update. See [protocol notes](docs/PROTOCOL.md) for the exact request, reply layout, and validation evidence.

## Diagnostics and checks

Read the current status without starting another menu-bar instance:

```sh
"$HOME/Applications/Cam Link Indicator.app/Contents/MacOS/CamLinkIndicator" --status
```

This prints JSON with `state` (`signal`, `no-signal`, or `unknown`) and `detail`. Exit status is 0 for a valid reading and 2 for unknown. It accesses the physical device.

The build script runs hardware-independent parser checks. They can also be run directly:

```sh
'build/Cam Link Indicator.app/Contents/MacOS/CamLinkIndicator' --self-test
```

To validate a new setup, keep the Cam Link connected, switch the camera on and off, and check that the indicator follows. Also check normal video operation in your usual call/recording app. No-signal results alone cannot prove that the camera is switched off.

## Privacy

No network connections, telemetry, image/audio capture, credentials, or device serial numbers. Device matching uses the model's USB IDs, which are shared by every unit of that model. The only saved app preference is whether to pulse. Personal installation paths are generated locally and are not part of the repository. Build output is ignored by Git.

## Remove

1. Quit from the dot's menu.
2. Run `./login-item.sh disable` if you enabled login startup.
3. Move `~/Applications/Cam Link Indicator.app` to Trash.

Optionally remove the saved pulse preference:

```sh
defaults delete local.camlink.signal-indicator
```

## License

[MIT](LICENSE). No Elgato binaries, firmware, or source code are distributed here.
