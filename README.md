# mac-24ghz-battery

Battery level for 2.4 GHz wireless devices — the ones on a USB dongle — in the macOS menu bar, via [SwiftBar](https://github.com/swiftbar/SwiftBar).

macOS shows battery for Bluetooth accessories, but devices on a proprietary 2.4 GHz dongle usually publish nothing at all. A SteelSeries Arctis Nova base station, for example, has no `BatteryPercent` anywhere in the IORegistry. This asks the hardware directly.

```
🎧 69%
───────────────────────────
🎧 SteelSeries Arctis Nova 5  69%
```

## What it reads

**SteelSeries Arctis Nova base stations** (Nova 3 / 5 / 5X / 7 / 7X / 7P) over their vendor HID interface — see [Protocol](#protocol) below.

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
```

The menu bar shows the lowest battery of any connected device; the dropdown lists them all.

## Protocol

The Nova base station speaks a simple request/response protocol on its vendor HID interface (usage page `0xFFC0`, usage `0x1`):

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

The Nova 5 path is tested against real hardware. Two paths are implemented from the protocol but **not yet verified**: the offline/out-of-range branch, and the generic `BatteryPercent` fallback (no device on hand publishes one). Reports welcome.

Other vendors — Logitech HID++, Razer HyperSpeed, Corsair Slipstream — are not implemented. Each needs its own protocol.
