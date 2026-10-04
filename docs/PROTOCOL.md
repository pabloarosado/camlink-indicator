# Cam Link 4K revision 3 signal status

Applies only to **USB `0fd9:00a1`**, vendor HID usage page `0xffa0`, usage `1`.

These notes record an independent implementation based on inspection of the locally installed Camera Hub **2.3.0.7295 arm64** signal-status functions and hardware checks. No vendor code or firmware is included. Treat this as an observed protocol, not an official SDK contract.

## Request

Camera Hub's `CCamLinkSupport::GetSignalState` requests eight bytes from virtual I2C address `0x55`, register `0`, through `ReadI2cData`.

The revision 3 path constructs payload `06 07 55 01 00 08`. Its HID writer prefixes report ID `06` and calls `IOHIDDeviceSetReport` with type **Output**, report ID **6**. The complete buffer is:

```text
06 06 07 55 01 00 08
```

Although sent with `SetReport`, this command selects a status register for **reading**, rather than changing camera settings.

The next operation is `IOHIDDeviceGetReport`, type **Input**, report ID **5**. The implementation mirrors Camera Hub's requested length of `0x7ff`, using an allocation of 4097 bytes.

## Response

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

## Hardware checks

Camera on, sending 3840 × 2160 at 25 fps:

```text
00 00 00 0f 70 08 19 54 00
```

The signal flag is set. After the camera was switched off, leaving the Cam Link connected by USB:

```text
00 00 00 00 00 00 00 00 00
```

The signal flag is clear. A Google Meet preview was also confirmed to work normally while the indicator was running. This does not establish compatibility with every firmware version or capture application.

## Other revisions

The first-generation Cam Link 4K (`0fd9:0066`) has a different HID layout. Its report `0x13` recipe must not be substituted for this implementation.

For background on the hardware families, see the independent [Cam Link firmware reverse-engineering project's revision notes](https://github.com/schlarpc/elgato-cam-link-4k-firmware-re/blob/main/docs/09-other-revisions.md). That project's first-generation tool is not the implementation used here.
