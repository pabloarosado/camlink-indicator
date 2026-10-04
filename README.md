# Cam Link Indicator

**See when your camera is on.**

Cam Link Indicator puts a visible red dot in your Mac's menu bar while your camera is sending video—even outside a video call. It helps you notice when your camera is active, for privacy and to avoid leaving it running and heating up.

It is for people who use a camera as a webcam with this setup:

**Camera → HDMI cable → Elgato Cam Link → USB → Mac**

The camera's brand is not hard-coded. The capture adapter matters: the app currently works with specific Cam Link 4K versions, described below.

I made this for my own setup and share it in case it's useful. It is not a maintained product: I may fix trivial things, but I won't debug other setups or add support for more models. Feel free to fork it.

## What you'll see

- 🔴 **Red:** the camera is sending an HDMI video signal. The dot gently pulses to catch your attention.
- ⚪ **Gray:** no HDMI signal detected.
- 🟠 **Amber ?:** the app couldn't determine the status.

The indicator checks every **5 seconds**. Click it to see the signal details, refresh immediately, turn pulsing off, or quit. It reads the adapter's status without opening a video stream; Google Meet has been tested alongside it. OBS has not yet been separately tested.

The indicator watches the camera's HDMI signal. It does not tell you whether an app is viewing or recording the video, and it does not measure temperature. A gray dot is not proof that the power switch is off: a sleeping camera or disconnected HDMI cable also produces no signal.

## Try it

You need macOS 13 or later and Apple's Command Line Tools. If those tools aren't installed, run `xcode-select --install` and finish the installation first. Hardware testing so far has been on Apple Silicon with macOS 26.

```sh
git clone https://github.com/pabloarosado/camlink-indicator.git
cd camlink-indicator
./check-device.sh
```

**The check tells you which Elgato adapter is connected and whether this app supports it.** You don't need to know its hardware revision or decode a USB ID. It builds a local executable and reads USB model information; it does not install the app or start video capture.

If your model is supported—or you want to try the experimental first-generation support—install with:

```sh
./install.sh --login
```

This builds the app, puts it in `~/Applications`, opens it, and enables startup at login. Leave off `--login` if you prefer to open it yourself. Quit an existing copy from its menu before installing an update.

No `sudo`, Homebrew packages, or running Camera Hub are needed. The app is built and signed locally; there is no notarized download yet.

## Will it work with my setup?

| Capture adapter | Current status |
| --- | --- |
| Cam Link 4K, revision 3 | **Tested** with a Sony A7 III and Google Meet on an Apple Silicon Mac |
| First-generation Cam Link 4K | **Experimental**, including its USB 2.0 identity. Implemented from published protocol information; not yet tested with this app on physical hardware |
| Cam Link 4K MK.2, original non-4K Cam Link, other brands | Not supported yet |

Revision 3 must connect in USB 3 mode. The app currently handles one supported adapter at a time. Other HDMI cameras using a supported adapter are expected to work, but only the Sony setup above has been verified. Intel Macs and older supported macOS versions also need testing.

Elgato has used the name “Cam Link 4K” for several different internal designs. That's why the compatibility check identifies the version automatically. [Exact USB IDs and protocol details](docs/PROTOCOL.md) are documented for anyone who wants to extend a fork.

If you try a new setup, check that the dot follows the camera's on/off state while the Cam Link remains plugged in, then check that video still works in your usual app.

## Privacy and how it works

The app queries the Cam Link's separate control interface. It does not record video or audio, make network connections, or change camera settings. It saves only your pulse preference.

This is an independent tool using an undocumented device protocol, not an Elgato product. The tested implementation and experimental implementation are described in the [protocol notes](docs/PROTOCOL.md).

## Settings and removal

Click the dot and uncheck **Pulse when camera is on** for a steady red light. Your choice is remembered.

```sh
./login-item.sh enable   # Start at login
./login-item.sh disable  # Stop starting at login
```

To uninstall, quit the app, disable login startup, and move `~/Applications/Cam Link Indicator.app` to Trash.

## Development

`./build.sh` builds the app and runs hardware-independent parser and model-routing checks. Build output is ignored by Git. For a one-off JSON status reading, use:

```sh
'build/Cam Link Indicator.app/Contents/MacOS/CamLinkIndicator' --status
```

The states are `signal`, `no-signal`, and `unknown`; exit status is 2 for unknown and 0 for a valid reading. `--check` lists connected Elgato models without opening a control interface; `--self-test` runs the checks without accessing hardware.

[MIT license](LICENSE). No Elgato software or firmware is included.
