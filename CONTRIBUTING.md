# Adding a device

Coverage here grows one device at a time, because 2.4 GHz peripherals have no battery standard to share. A scan of every HID collection on a typical Mac finds none declaring the HID Battery System usage page (`0x85`) or Generic Device Controls' Battery Strength — mice, headsets and keyboards on proprietary dongles all answer over vendor channels, or not at all. There is no generic reader that covers them, so each vendor needs its own code.

Nobody owns every peripheral, so the fastest way to help is to report what you have.

## Reporting hardware

```bash
wireless-battery --probe
```

That prints, for every USB HID device: vendor and product ID, usage page, report sizes, the raw report descriptor, and whether any driver claims it. It is strictly read-only — it reads IOKit properties and sends the device nothing. Paste the output into an issue.

If a device already publishes `BatteryPercent` to macOS, the probe says so, and it needs no new code at all.

## Safety rules

These are not stylistic preferences. A stray vendor command can rewrite a device's settings, wipe its onboard profile, or drop a keyboard into its bootloader.

1. **Never write to a device you cannot positively identify** by vendor and product ID. Matching on a vendor ID alone is not enough.
2. **Never send a command you cannot name.** Sweeping an unknown command space to see what answers is how hardware gets bricked. If you're working from another project's source, port the specific request, not a range.
3. **Reads before writes.** Report descriptors, IOKit properties and feature *reads* are safe and often sufficient. Prefer them.
4. **Assume a reply layout differs between models in the same family until shown otherwise.** SteelSeries Nova 5 and Nova 7 both answer the same `0xB0` request with completely different offsets; using one parser for both reports a status byte as a battery percentage.

## Trying a device without rebuilding

Drop a JSON file at `~/.config/wireless-battery/devices.json` to add or correct entries. It overrides the built-in table, so you can also fix a wrong entry locally:

```json
[
  {
    "vendorID": 4152,
    "productID": 8787,
    "name": "SteelSeries Arctis Nova 5X",
    "driver": "steelseries-nova",
    "variant": "nova5",
    "verified": true
  }
]
```

`vendorID` and `productID` are decimal. `driver` is one of the ids from `wireless-battery --devices`. `variant` selects the reply layout within that driver. Set `verified` to `true` only once you have confirmed the reading against the device itself — compare it with the vendor's own software, and check that it moves as the device discharges.

If it works, send a pull request adding the entry to `DeviceTable.builtin`.

## Writing a driver

A driver conforms to `BatteryDriver` in `src/Driver.swift`: `matches` decides whether it handles a HID collection, `read` returns one reading per physical device behind it. `HIDSession` handles opening the device and pairing requests with replies; open once and reuse it, since tearing a session down repeatedly while a device is sending crashes.

Return a reading with `online: false` and a `note` for a device that is present but unreachable, rather than returning nothing — a sleeping mouse should keep its place in the display with its last known level, not vanish.

Protocols for most vendors are already documented in GPL projects worth porting from rather than reverse-engineering: [HeadsetControl](https://github.com/Sapd/HeadsetControl) for headsets, [Solaar](https://github.com/pwr-Solaar/Solaar) for Logitech (including the voltage-to-percentage curves older devices need), [OpenRazer](https://github.com/openrazer/openrazer) for Razer, [ckb-next](https://github.com/ckb-next/ckb-next) for Corsair. This project is GPL-3.0, so ports from them are license-clean — credit the source in a comment.

## What cannot be supported

QMK/VIA keyboards on a 2.4 GHz dongle, such as the Keychron Max series. The dongle forwards keystrokes without bridging the configuration channel, which matches Keychron's own documentation that the Launcher only detects the keyboard over a wired connection. There is nothing behind the dongle to ask. See the README for the full probe result.
