// mac-24ghz-battery — part of https://github.com/usamarashid94/mac-24ghz-battery
// Copyright (C) 2026 usamarashid94. Licensed under GPL-3.0; see LICENSE.

import Foundation
import IOKit
import IOKit.hid

// MARK: - Generic HID battery

enum GenericBattery {
    /// Devices that publish a battery level to macOS the standard way.
    static func read(_ device: IOHIDDevice, includeBluetooth: Bool) -> DeviceReading? {
        guard let percent = intProperty(device, "BatteryPercent") else { return nil }

        let transport = stringProperty(device, kIOHIDTransportKey) ?? "Unknown"
        // A 2.4 GHz dongle presents as USB. Bluetooth already has a battery UI in macOS.
        if !includeBluetooth && transport.caseInsensitiveCompare("USB") != .orderedSame {
            return nil
        }

        let name = stringProperty(device, kIOHIDProductKey)
            ?? stringProperty(device, kIOHIDManufacturerKey)
            ?? "Unknown device"

        return DeviceReading(
            key: "hid-\(intProperty(device, kIOHIDVendorIDKey) ?? 0)-\(intProperty(device, kIOHIDProductIDKey) ?? 0)",
            name: name,
            percent: min(100, max(0, percent)),
            charging: false,
            online: true,
            transport: transport.caseInsensitiveCompare("USB") == .orderedSame ? "2.4GHz" : transport,
            source: "hid-battery",
            note: nil
        )
    }
}

/// Set from the command line before drivers run. The generic reader is the only
/// one whose behaviour depends on a flag, so it reads it from here rather than
/// widening the driver protocol for a single case.
var includeBluetoothDevices = false

struct GenericHIDDriver: BatteryDriver {
    let id = "hid-battery"
    let displayName = "Standard HID BatteryPercent"

    func matches(_ device: IOHIDDevice) -> Bool {
        // Cheap check only: whether it yields a reading is decided in read().
        property(device, "BatteryPercent") != nil
    }

    func read(_ device: IOHIDDevice) -> [DeviceReading] {
        GenericBattery.read(device, includeBluetooth: includeBluetoothDevices)
            .map { [$0] } ?? []
    }
}
