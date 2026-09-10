// mac-24ghz-battery — part of https://github.com/usamarashid94/mac-24ghz-battery
// Copyright (C) 2026 usamarashid94. Licensed under GPL-3.0; see LICENSE.

import Foundation
import IOKit
import IOKit.hid

/// One vendor's way of answering "how much battery is left".
///
/// There is no standard to lean on. A scan of every HID collection on a typical
/// Mac found none declaring the HID Battery System usage page (0x85) or Generic
/// Device Controls' Battery Strength — 2.4 GHz peripherals answer over
/// proprietary channels or not at all. So coverage is per-vendor by nature, and
/// this protocol exists to keep each vendor's quirks in one file.
///
/// Rules for new drivers:
///
///  1. `matches` must be cheap: property reads only, no device I/O.
///  2. Never write to a device you cannot positively identify. A stray vendor
///     command can rewrite settings or drop a keyboard into its bootloader.
///  3. Return a reading for a device that is present but unreachable, with
///     `online: false` and a `note`, rather than returning nothing — the display
///     layer fills the level in from cache.
protocol BatteryDriver {
    /// Stable identifier, also written to JSON output as `source`.
    var id: String { get }

    /// Human-readable name of the protocol, for `--probe` and docs.
    var displayName: String { get }

    /// Whether this driver handles the given HID collection.
    func matches(_ device: IOHIDDevice) -> Bool

    /// Query the device. One collection can front several physical devices, as
    /// a Logitech receiver does, hence an array.
    func read(_ device: IOHIDDevice) -> [DeviceReading]
}

/// Drivers in priority order: a device is offered to the first one that matches,
/// so vendor protocols get first refusal and the generic reader is the backstop.
let drivers: [BatteryDriver] = [
    SteelSeriesDriver(),
    LogitechDriver(),
    GenericHIDDriver(),
]

/// The generic driver only fires when a device publishes a battery level to
/// macOS, which depends on a runtime flag, so it is handled separately.
protocol ConfigurableDriver {
    func read(_ device: IOHIDDevice, includeBluetooth: Bool) -> [DeviceReading]
}
