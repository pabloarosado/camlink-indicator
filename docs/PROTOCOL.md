# Cam Link signal-status protocols

| Device | USB IDs (vendor:product) | Status |
| --- | --- | --- |
| Cam Link 4K revision 3 | `0fd9:00a1` | Hardware-tested |
| First-generation Cam Link 4K | `0fd9:0066`, `0fd9:0067` | Experimental; not hardware-tested with this app |

These are model IDs shared by units of a model, not unique device identities.
Matching is restricted to the appropriate vendor HID interface: page `0xffa0`,
usage `1` for revision 3; page `0xff00` for the first generation. MK.2 and
revision 3 in USB 2.0 mode (`0fd9:00a2`) are not queried.

## Revision 3 (tested)

These notes record an independent implementation based on inspection of the locally installed Camera Hub **2.3.0.7295 arm64** signal-status functions and hardware checks. No vendor code or firmware is included. Treat this as an observed protocol, not an official SDK contract.

### Request

Camera Hub's `CCamLinkSupport::GetSignalState` requests eight bytes from virtual I2C address `0x55`, register `0`, through `ReadI2cData`.

The revision 3 path constructs payload `06 07 55 01 00 08`. Its HID writer prefixes report ID `06` and calls `IOHIDDeviceSetReport` with type **Output**, report ID **6**. The complete buffer is:

```text
06 06 07 55 01 00 08
```

Although sent with `SetReport`, this command selects a status register for **reading**, rather than changing camera settings.

The next operation is `IOHIDDeviceGetReport`, type **Input**, report ID **5**. The implementation mirrors Camera Hub's requested length of `0x7ff`, using an allocation of 4097 bytes.

### Response

Observed reply length: **9 bytes**. The first byte is `00`, followed by an eight-byte input-status block. Camera Hub strips the leading byte before interpretation. This app requires the observed length and leading `00`; anything else is unknown.

Offsets below are relative to the eight-byte block, excluding the leading response byte:

| Offset | Interpretation |
| --- | --- |
| 1–2 | Width, unsigned 16-bit little-endian |
| 3–4 | Height, unsigned 16-bit little-endian |
| 5 | Nominal frame rate |
| 6, bit 2 (`0x04`) | HDMI signal present, as used by `CamLink::SignalState::HasSignal` |
| 6, bit 1 (`0x02`) | Divide nominal frame rate by 1.001 |

The app uses only these fields. It does not infer power state from resolution or USB-device presence.

### Hardware checks

Camera on, sending 3840 × 2160 at 25 fps:

```text
00 00 00 0f 70 08 19 54 00
```

The signal flag is set. After the camera was switched off, leaving the Cam Link connected by USB:

```text
00 00 00 00 00 00 00 00 00
```

The signal flag is clear. A Google Meet preview was also confirmed to work normally while the indicator was running. This does not establish compatibility with every firmware version or capture application.

## First generation (experimental)

A separate path handles `0fd9:0066` (USB 3) and `0fd9:0067` (USB 2). It performs
only an Input `GET_REPORT` for ID `0x13`, requesting six bytes. It does not send
the revision 3 request or any `SET_REPORT` to these devices.

| Response offset | Meaning |
| --- | --- |
| 0–1 | Width, little-endian |
| 2–3 | Height, little-endian |
| 4 | Frame rate in Hz |
| 5 | Signal lock: 0 absent, 1 present |

The firmware omits the report ID from its response. The parser requires exactly
six bytes and a signal flag of 0 or 1. A malformed reply, short reply, or read
error becomes unknown. A device can return its maximum resolution when no signal
is present, so resolution alone is never interpreted as an active camera.

This path is based on the independent firmware reverse-engineering project's
[protocol description](https://github.com/schlarpc/elgato-cam-link-4k-firmware-re/blob/main/docs/03-vendor-hid-protocol.md)
and [USB interface description](https://github.com/schlarpc/elgato-cam-link-4k-firmware-re/blob/main/docs/02-usb-interfaces.md).
That work establishes the device protocol, not this macOS implementation's
compatibility. In particular, the device advertises a one-byte report but returns
six bytes; whether macOS accepts it needs a physical-device test. No fallback
commands are attempted if the read fails. The menu marks readings from this path
as experimental.

Parser checks cover on/off replies, retained resolution without a signal,
invalid flags, short responses, and incomplete timing information. Model-routing
checks keep the two protocols separate and exclude unimplemented models.

## Adding another model

`--check` reads USB model metadata without opening the device or sending control
requests. It can identify unsupported models for a compatibility report. It does
not read or print serial numbers.

Do not add a product ID without confirming its control interface and status
protocol. Each additional implementation needs camera-on, camera-off, and
simultaneous video-use checks on macOS. Test changes with the Cam Link left
connected by USB so that USB presence is not mistaken for camera activity.

See the [hardware revision notes](https://github.com/schlarpc/elgato-cam-link-4k-firmware-re/blob/main/docs/09-other-revisions.md)
for background on the different hardware families.
