# mac-24ghz-battery

Battery level for 2.4 GHz wireless devices — the ones on a USB dongle — in the macOS menu bar, via [SwiftBar](https://github.com/swiftbar/SwiftBar).

macOS shows battery for Bluetooth accessories, but devices on a proprietary 2.4 GHz dongle usually publish nothing at all. A SteelSeries Arctis Nova base station, for example, has no `BatteryPercent` anywhere in the IORegistry. This asks the hardware directly.

```
🖱 54%  🎧 70%
────────────────────────────────────
🖱 Logitech G502 X LIGHTSPEED   54%
🎧 SteelSeries Arctis Nova 5    69%
```

## What it reads

**SteelSeries Arctis Nova base stations** (Nova 3 / 5 / 5X / 7 / 7X / 7P) over their vendor HID interface — see [Protocol](#protocol) below.

**Logitech Lightspeed and Unifying receivers** over HID++ 2.0, including the device's own marketing name, so a G502 X reports as "Logitech G502 X LIGHTSPEED" rather than "USB Receiver".

**Any HID device that publishes a standard `BatteryPercent`** to macOS. No per-device code, so conforming hardware is picked up automatically when you plug it in.

Devices on a USB transport are treated as 2.4 GHz. Pass `--all` to include Bluetooth devices too, which macOS already reports elsewhere.

## Install

Requires only the Xcode Command Line Tools — no full Xcode, no code signing.

```bash
git clone https://github.com/usamarashid94/mac-24ghz-battery.git
cd mac-24ghz-battery
./build.sh
```

That compiles the reader and installs it to `~/.local/bin/wireless-battery`. Then drop the plugin into your SwiftBar plugin folder:

```bash
install -m 755 wireless-battery.60s.sh ~/.swiftbar-plugins/
```

The refresh interval is set by the filename — rename to `.30s.sh` for 30 seconds, `.5m.sh` for five minutes.

## Usage

```bash
wireless-battery              # 🎧 SteelSeries Arctis Nova 5: 69%
wireless-battery --json       # machine-readable
wireless-battery --swiftbar   # SwiftBar plugin format
wireless-battery --all        # include Bluetooth devices
wireless-battery --debug      # dump HID traffic to stderr
```

The menu bar shows up to three devices side by side and the dropdown lists them all. When more devices than that are connected, the lowest batteries take the slots, since those are the ones worth knowing about:

```bash
WIRELESS_BATTERY_MENUBAR_MAX=1 wireless-battery --swiftbar   # just the lowest
```

Set that variable in the plugin script to change the cap.

## Sleeping devices

A 2.4 GHz mouse or headset stops answering when it sleeps or powers off, which is exactly when you're most likely to look at a battery widget. Dropping it from the display would be the wrong answer, so the last good reading is cached and shown aged instead:

```
🖱 Logitech G502 X LIGHTSPEED   54% · asleep 7m
🎧 SteelSeries Arctis Nova 5    off or out of range
```

Remembered levels are dimmed, and the menu bar marks one with a trailing `·`. The cache lives in `~/Library/Caches/mac-24ghz-battery.json` and is safe to delete.

An empty Logitech pairing slot is told apart from a sleeping device by its reply: an empty slot answers with a HID++ 1.0 error (`0x8F`) carrying code `0x08`, "unknown device", while a paired-but-sleeping device says nothing at all.

## Protocol

### Logitech HID++ 2.0

Battery isn't at a fixed address. Each device assigns its own index to each feature, so you ask the root feature for the index first:

```
[0x10, deviceIndex, featureIndex, (function << 4) | softwareID, p0, p1, p2]
```

Ask root (index `0x00`) for feature `0x1004` (unified battery), falling back to `0x1000` (battery level status), then call the returned index. Replies come back as short (`0x10`) or long (`0x11`) reports, with `0xFF` in the feature slot marking an error.

Pairing slots 1–6 are probed. Errors come back in two flavours and both must be parsed: HID++ 2.0 marks them with `0xFF` in the feature slot, while receivers also emit HID++ 1.0 errors using the `0x8F` sub-ID. Recognizing the 1.0 form is what makes an empty slot cost one fast reply instead of a full timeout.

### SteelSeries Arctis Nova

The Nova base station speaks a simpler request/response protocol on its vendor HID interface (usage page `0xFFC0`, usage `0x1`):

1. Write a one-byte `0xB0` status request as an output report.
2. Read the status report back:

| Byte | Meaning |
|------|---------|
| 1    | `0x02` = headset powered off or out of range |
| 3    | battery percentage, already 0–100 |
| 4    | `0x01` = charging |

No Input Monitoring permission is needed, because vendor usage pages aren't subject to the consent prompt that keyboards and pointing devices are. A read takes about 10 ms.

## Credits

The Nova wire format was derived from [HeadsetControl](https://github.com/Sapd/HeadsetControl) by Sapd, which supports far more hardware across more platforms. If you want breadth — sidetone, EQ, chatmix, dozens of headsets — use that instead. This project exists only to put a number in the macOS menu bar with no dependencies.

## License

GPL-3.0, matching HeadsetControl, since the protocol details were learned from reading its source. See [LICENSE](LICENSE).

## Status

Verified against real hardware: the Nova 5 battery read, the Nova offline/out-of-range branch, and the Logitech HID++ path (G502 X Lightspeed, including the name lookup).

Not yet verified: the generic `BatteryPercent` fallback, since no device on hand publishes one. Reports welcome.

Not implemented: Razer HyperSpeed and Corsair Slipstream, which each need their own protocol.

### QMK/VIA keyboards on a 2.4 GHz dongle

Tested against a Keychron V3 Max on its Keychron Link dongle, without success. The dongle exposes a QMK raw HID interface (usage page `0xFF60`, usage `0x61`, 32-byte reports) and accepts writes to it, but answers nothing at all — not even VIA `0x01`, get protocol version, which every VIA firmware answers. Two seconds of passive listening yields no reports either, and the dongle's other interface (usage page `0x8C`) returns no readable feature report.

This matches Keychron's own documentation: the Keychron Launcher — which is that same VIA raw-HID channel — [only detects the keyboard over a wired connection](https://keychronsupport.zendesk.com/hc/en-us/articles/22776472488855-My-keyboard-is-not-recognized-by-Keychron-Launcher-what-should-I-do), not over 2.4 GHz or Bluetooth. The dongle forwards keystrokes and nothing else, so there is no configuration channel behind it to ask for a battery level.

Battery on these boards is instead published over Bluetooth, through the standard [BLE Battery Service](https://pmortensen.eu/world2/2024/11/04/the-battery-state-of-a-keychron-qmk-based-keyboard-can-be-displayed-in-the-operating-system/). Run the keyboard over Bluetooth and the generic `BatteryPercent` path should pick it up with no extra code; over the 2.4 GHz dongle it cannot be read at all without custom firmware.
