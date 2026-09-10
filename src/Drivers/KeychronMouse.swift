// mac-24ghz-battery — part of https://github.com/usamarashid94/mac-24ghz-battery
// Copyright (C) 2026 usamarashid94. Licensed under GPL-3.0; see LICENSE.

import Foundation
import IOKit
import IOKit.hid

/// Keychron wireless mice, over their own 2.4 GHz dongle.
///
/// Protocol per keychron-battery-dkms (GPL-2.0):
///   send a feature report, ID 0xB3, payload [0xB3, 0x06, 0...]
///   the reply arrives as an input report [0xB4, 0x06, ...] with the
///   percentage at byte 20.
///
/// Note this does *not* work for Keychron keyboards. Their firmware has no
/// battery command at all — `keychron_raw_hid.c` handles 0xA0-0xAB and none of
/// them is battery — and the Keychron Link keyboard dongle relays no raw HID.
/// Verified on a V3 Max: the dongle accepts the feature write and never
/// answers. Keyboard battery is published over Bluetooth's BLE service instead.
enum KeychronMouse {
    static let vendorID = 0x3434
    /// Keychron's dongles carry this vendor protocol on HID page 0x8C.
    static let vendorUsagePage = 0x8C

    static let commandReportID: UInt8 = 0xB3
    static let responseReportID: UInt8 = 0xB4
    static let statusCommand: UInt8 = 0x06
    static let batteryOffset = 20
    static let reportSize = 64

    static func entry(forProductID productID: Int) -> DeviceEntry? {
        guard let entry = DeviceTable.entry(vendorID: vendorID, productID: productID),
              entry.driver == "keychron-mouse"
        else { return nil }
        return entry
    }

    static func matches(_ device: IOHIDDevice) -> Bool {
        guard intProperty(device, kIOHIDVendorIDKey) == vendorID else { return false }
        guard intProperty(device, kIOHIDPrimaryUsagePageKey) == vendorUsagePage else { return false }
        guard let productID = intProperty(device, kIOHIDProductIDKey) else { return false }
        // Table-gated: the Keychron Link keyboard dongle also sits on page 0x8C
        // and never answers, so it must not be probed on every refresh.
        return entry(forProductID: productID) != nil
    }

    static func read(_ device: IOHIDDevice) -> DeviceReading {
        let productID = intProperty(device, kIOHIDProductIDKey) ?? 0
        let name = entry(forProductID: productID)?.name
            ?? stringProperty(device, kIOHIDProductKey)
            ?? "Keychron mouse"

        var reading = DeviceReading(
            key: "keychron-\(productID)",
            name: name,
            percent: nil,
            charging: false,
            online: false,
            transport: "2.4GHz",
            source: "keychron-mouse",
            note: nil
        )

        guard let session = HIDSession(device: device, bufferSize: reportSize) else {
            reading.note = "busy"
            return reading
        }
        defer { session.close() }

        var request = [UInt8](repeating: 0, count: reportSize)
        request[0] = commandReportID
        request[1] = statusCommand

        guard let data = session.exchange(
            reportID: commandReportID,
            request: request,
            reportType: kIOHIDReportTypeFeature,
            timeout: 0.6,
            accept: { reply in
                reply.count > batteryOffset
                    && reply[0] == responseReportID
                    && reply[1] == statusCommand
            }
        ) else {
            reading.note = "not responding"
            return reading
        }

        let percent = Int(data[batteryOffset])
        guard (0...100).contains(percent) else {
            debugLog("keychron battery byte out of range: \(percent)")
            reading.note = "unreadable reply"
            return reading
        }

        reading.online = true
        reading.percent = percent
        return reading
    }
}

struct KeychronMouseDriver: BatteryDriver {
    let id = "keychron-mouse"
    let displayName = "Keychron mouse (0xB3 status request)"

    func matches(_ device: IOHIDDevice) -> Bool {
        KeychronMouse.matches(device)
    }

    func read(_ device: IOHIDDevice) -> [DeviceReading] {
        [KeychronMouse.read(device)]
    }
}
