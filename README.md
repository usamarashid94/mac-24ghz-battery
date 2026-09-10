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

**SteelSeries Arctis headsets** over their vendor HID interface — the Nova 5, Nova 7, Arctis 7/Pro, Arctis 1 and Arctis 9 families. Each family parses its own reply layout; see [Protocol](#protocol) below.

**Logitech Lightspeed and Unifying receivers** over HID++ 2.0, covering all three battery features these devices use — unified battery (`0x1004`), battery level status (`0x1000`), and raw voltage (`0x1001`) converted through a discharge curve for older gaming mice that report millivolts. Device names come from the hardware, so a G502 X reports as "Logitech G502 X LIGHTSPEED" rather than "USB Receiver".

**Keychron wireless mice** over their dongle's vendor protocol. Note this does *not* extend to Keychron keyboards — see [QMK/VIA keyboards](#qmkvia-keyboards-on-a-24-ghz-dongle) for why.

**Any HID device that publishes a standard `BatteryPercent`** to macOS. No per-device code, so conforming hardware is picked up automatically when you plug it in.

Devices on a USB transport are treated as 2.4 GHz. Pass `--all` to include Bluetooth devices too, which macOS already reports elsewhere.

### Supported devices

Generated from the device table by `tools/update-readme-devices.sh`, and checked by `qa.sh`, so this list cannot drift from the code. `wireless-battery --devices` prints the same thing.

**Logitech devices are not listed here.** They are discovered at runtime over HID++ rather than by product ID, so any Lightspeed or Unifying device that implements a battery feature works without being named — the receiver is asked what it has.

"Confirmed on hardware" means somebody checked the reading against the physical device. Everything else is ported from another project's source and tested only against crafted frames; see [Status](#status).

<!-- BEGIN DEVICES -->

#### SteelSeries Arctis (vendor HID)

| Device | Product ID | Reply layout | Confirmed on hardware |
|---|---|---|---|
| SteelSeries Arctis 1 | `0x12B3` | `arctis1` | not yet |
| SteelSeries Arctis 1 Xbox | `0x12B6` | `arctis1` | not yet |
| SteelSeries Arctis 7 | `0x1260` | `legacyArctis7` | not yet |
| SteelSeries Arctis 7 2019 | `0x12AD` | `legacyArctis7` | not yet |
| SteelSeries Arctis 7X | `0x12D7` | `arctis1` | not yet |
| SteelSeries Arctis 9 | `0x12C2` | `arctis9` | not yet |
| SteelSeries Arctis Nova 5 | `0x2232` | `nova5` | yes |
| SteelSeries Arctis Nova 5X | `0x2253` | `nova5` | not yet |
| SteelSeries Arctis Nova 7 | `0x2202` | `nova7Discrete` | not yet |
| SteelSeries Arctis Nova 7 | `0x22A1` | `nova7Percent` | not yet |
| SteelSeries Arctis Nova 7 Diablo IV | `0x223A` | `nova7Discrete` | not yet |
| SteelSeries Arctis Nova 7 Diablo IV | `0x22A9` | `nova7Percent` | not yet |
| SteelSeries Arctis Nova 7 Gen 2 | `0x227E` | `nova7Percent` | not yet |
| SteelSeries Arctis Nova 7 WoW Edition | `0x227A` | `nova7Discrete` | not yet |
| SteelSeries Arctis Nova 7X | `0x2206` | `nova7Discrete` | not yet |
| SteelSeries Arctis Nova 7X | `0x22A4` | `nova7Discrete` | not yet |
| SteelSeries Arctis Nova 7X | `0x22A5` | `nova7Percent` | not yet |
| SteelSeries Arctis Nova 7X v2 | `0x2258` | `nova7Percent` | not yet |
| SteelSeries Arctis Nova 7X v2 | `0x229E` | `nova7Percent` | not yet |
| SteelSeries Arctis Nova 7X v2 | `0x22AD` | `nova7Percent` | not yet |
| SteelSeries Arctis Pro 2019 | `0x1252` | `legacyArctis7` | not yet |
| SteelSeries Arctis Pro GameDAC | `0x1280` | `legacyArctis7` | not yet |

#### Keychron mouse (0xB3 status request)

| Device | Product ID | Reply layout | Confirmed on hardware |
|---|---|---|---|
| Keychron M3 | `0xD037` | `status` | not yet |
| Keychron M5 | `0xD048` | `status` | not yet |
| Keychron mouse receiver | `0xD028` | `status` | not yet |

<!-- END DEVICES -->

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
wireless-battery --probe      # read-only diagnostics for unsupported hardware
wireless-battery --devices    # what this build knows about
wireless-battery --selftest   # run the parser and formatting tests
```

The menu bar shows up to three devices side by side and the dropdown lists them all. When more devices than that are connected, the lowest batteries take the slots, since those are the ones worth knowing about:

```bash
WIRELESS_BATTERY_MENUBAR_MAX=1 wireless-battery --swiftbar   # just the lowest
```

Set that variable in the plugin script to change the cap.

## Menu bar app

A native menu bar app, if you'd rather not run SwiftBar.

**[Download the latest .dmg](https://github.com/usamarashid94/mac-24ghz-battery/releases/latest)** — universal, Apple Silicon and Intel.

macOS will refuse to open it the first time: the app is ad-hoc signed but **not notarized**, because notarizing requires a paid Apple Developer account. Either right-click the app and choose Open, or clear the quarantine flag:

```bash
xattr -dr com.apple.quarantine "/Applications/Wireless Battery.app"
```

If you would rather not trust a binary — reasonable, and the reason the source is here — build it yourself:

```bash
./build-app.sh
open "build/Wireless Battery.app"
```

It shows the same line in the menu bar, with a dropdown listing every device, colour-coded by level, plus the time of the last reading, a manual refresh and an "Open at Login" toggle. It builds with the Command Line Tools alone — no Xcode, no signing identity — and is ad-hoc signed. Move it to `/Applications` if you want the login item to stick, since that needs a stable location.

Reads happen on a background queue, never the main thread: an unreachable device costs a 1.5 second timeout, which would otherwise freeze the menu bar for that long. Refreshes run every 30 seconds and whenever the menu opens.

### Why not a WidgetKit widget?

A desktop or Notification Center widget needs Xcode, a signing identity, and an App Group container, because a widget extension is sandboxed and can't do IOKit HID work itself — the reading has to happen elsewhere and be handed over as a snapshot. More to the point, WidgetKit budgets timeline reloads to a few dozen a day, so a widget would update roughly every 15 minutes. That is *less* live than the menu bar, for more moving parts.

## Disconnected devices

Only devices that answer right now are shown. A headset switched off, a mouse gone to sleep, or an unplugged dongle drops out of the display, and comes back on its own as soon as it answers again — within the refresh interval, or immediately when the menu is opened.

The last good reading is still cached, so if you would rather see departed devices with their remembered level and its age:

```bash
WIRELESS_BATTERY_SHOW_OFFLINE=1 wireless-battery
# 🖱 Logitech G502 X LIGHTSPEED   54% · asleep 7m
# 🎧 SteelSeries Arctis Nova 5    70% · off or out of range 49m
```

`--json` always reports every device it found, connected or not, with `online` and `stale` flags. The cache lives in `~/Library/Caches/mac-24ghz-battery.json` and is safe to delete.

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

The families share that request but **not** the reply layout, which is why the model is looked up per product ID rather than assumed:

| Nova 5 / 5X | Meaning |
|------|---------|
| byte 1 | `0x02` = headset powered off or out of range |
| byte 3 | battery percentage, already 0–100 |
| byte 4 | `0x01` = charging |

| Nova 7 family | Meaning |
|------|---------|
| byte 3 | `0x00` = off or out of range; `0x01`/`0x02` = charging |
| byte 2 | battery level — a 0–4 step on original firmware, a 0–100 percentage after the January 2026 update |

Getting that wrong doesn't fail loudly: parsing a Nova 7 with the Nova 5 layout reports a status byte as a battery percentage. Product IDs and layouts follow HeadsetControl.

No Input Monitoring permission is needed, because vendor usage pages aren't subject to the consent prompt that keyboards and pointing devices are. A read takes about 10 ms.

### Input collections are never opened

`HIDSession` refuses to open any collection on HID usage page `0x01` (Generic Desktop), `0x07` (Keyboard/Keypad) or `0x0C` (Consumer). Opening one streams the user's keystrokes and cursor movement into the process. Battery always lives on a vendor page, so refusing these costs nothing — and the refusal is enforced in the single function that opens devices, rather than left to each driver to remember.

## Testing

Most supported devices cannot be tested here, because nobody owns all of them. What *can* be tested is the part that actually goes wrong — reply parsing. A wrong byte offset or a missing range check doesn't fail loudly on real hardware; it reports a status byte as a battery percentage, which is exactly the bug that shipped once. So every protocol variant is exercised against crafted frames with known answers, including frames that must be *rejected*:

```bash
./wireless-battery --selftest   # parsers, voltage curve, formatting, guards, table integrity
./qa.sh                         # the above plus builds, stability, memory, hardware smoke test
```

The suite is checked with mutation testing — deliberately breaking a byte offset, the voltage curve, or the input-page guard, and confirming the tests catch it. A test that never fails isn't testing anything.

## Adding devices

There is no battery standard to lean on: a scan of every HID collection on a typical Mac finds none declaring the HID Battery System usage page (`0x85`) or Generic Device Controls' Battery Strength. Coverage is therefore per-vendor, and grows one device at a time.

Drivers conform to `BatteryDriver` and look their hardware up in a shared device table, so adding a known device is a data change rather than a code change. You can try one without rebuilding by dropping JSON at `~/.config/wireless-battery/devices.json` (format in [docs/devices.example.json](docs/devices.example.json)).

If you have hardware that isn't supported, `wireless-battery --probe` prints everything needed to add it, without sending the device anything. See [CONTRIBUTING.md](CONTRIBUTING.md), which also covers the safety rules for talking to unknown hardware.

## Credits

The Nova wire format was derived from [HeadsetControl](https://github.com/Sapd/HeadsetControl) by Sapd, which supports far more hardware across more platforms. If you want breadth — sidetone, EQ, chatmix, dozens of headsets — use that instead. This project exists only to put a number in the macOS menu bar with no dependencies.

## License

GPL-3.0, matching HeadsetControl, since the protocol details were learned from reading its source. See [LICENSE](LICENSE).

## Status

Verified against real hardware: the Arctis Nova 5 read and its offline branch, and the Logitech HID++ path (G502 X Lightspeed, including the name lookup).

Everything else is ported from another project's source and marked unverified — `wireless-battery --devices` shows which is which, with `✓` meaning someone confirmed it against the physical device. Unverified does not mean untested: every protocol variant is exercised against crafted frames by `--selftest`, including frames it must reject, so a wrong offset surfaces as an unreadable reply rather than a confident wrong number. What cannot be checked without the hardware is whether the frames themselves are right.

Confirming a device is a two-minute job — compare the reading with the vendor's own software, check it moves as the battery drains, then flip `verified` in the table and send a pull request.

Not implemented: Razer HyperSpeed and Corsair Slipstream. Both are documented in GPL projects (OpenRazer, ckb-next) and would be welcome. Razer needs care: its control interface often sits on a Generic Desktop page, which `HIDSession` refuses to open, so it needs a feature-report-only path that never registers an input callback.

### QMK/VIA keyboards on a 2.4 GHz dongle

Tested against a Keychron V3 Max on its Keychron Link dongle, without success. The dongle exposes a QMK raw HID interface (usage page `0xFF60`, usage `0x61`, 32-byte reports) and accepts writes to it, but answers nothing at all — not even VIA `0x01`, get protocol version, which every VIA firmware answers. Two seconds of passive listening yields no reports either, and the dongle's other interface (usage page `0x8C`) returns no readable feature report.

This matches Keychron's own documentation: the Keychron Launcher — which is that same VIA raw-HID channel — [only detects the keyboard over a wired connection](https://keychronsupport.zendesk.com/hc/en-us/articles/22776472488855-My-keyboard-is-not-recognized-by-Keychron-Launcher-what-should-I-do), not over 2.4 GHz or Bluetooth. The dongle forwards keystrokes and nothing else, so there is no configuration channel behind it to ask for a battery level.

Battery on these boards is instead published over Bluetooth, through the standard [BLE Battery Service](https://pmortensen.eu/world2/2024/11/04/the-battery-state-of-a-keychron-qmk-based-keyboard-can-be-displayed-in-the-operating-system/). Run the keyboard over Bluetooth and the generic `BatteryPercent` path should pick it up with no extra code; over the 2.4 GHz dongle it cannot be read at all without custom firmware.
