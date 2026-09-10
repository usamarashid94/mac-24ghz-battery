// mac-24ghz-battery — part of https://github.com/usamarashid94/mac-24ghz-battery
// Copyright (C) 2026 usamarashid94. Licensed under GPL-3.0; see LICENSE.

import Foundation
import IOKit
import IOKit.hid

/// SteelSeries Arctis Nova base stations.
///
/// All of them answer the same one-byte 0xB0 status request on the vendor HID
/// interface, but the reply layout differs by product family — which is why the
/// family is looked up per product ID rather than assumed. Getting this wrong
/// doesn't fail loudly; it reports a status byte as a battery percentage.
enum SteelSeries {
    static let vendorID = 0x1038
    static let vendorUsagePage = 0xFFC0
    static let vendorUsage = 0x1
    static let statusRequest: [UInt8] = [0xB0]
    static let statusBufferSize = 128

    enum Variant: String {
        /// Offline flag at byte 1, percentage at byte 3, charging at byte 4.
        case nova5
        /// Status at byte 3 (0x00 offline, 0x01/0x02 charging), level 0-4 at byte 2.
        case nova7Discrete
        /// Same as above, but byte 2 is already a percentage.
        case nova7Percent

        /// Shortest reply this layout can be read from.
        var minimumLength: Int {
            switch self {
            case .nova5: return 16
            case .nova7Discrete, .nova7Percent: return 4
            }
        }
    }

    static func matches(_ device: IOHIDDevice) -> Bool {
        guard intProperty(device, kIOHIDVendorIDKey) == vendorID else { return false }
        guard intProperty(device, kIOHIDPrimaryUsagePageKey) == vendorUsagePage else { return false }
        guard intProperty(device, kIOHIDPrimaryUsageKey) == vendorUsage else { return false }
        guard let productID = intProperty(device, kIOHIDProductIDKey) else { return false }
        return entry(forProductID: productID) != nil
    }

    static func entry(forProductID productID: Int) -> DeviceEntry? {
        guard let entry = DeviceTable.entry(vendorID: vendorID, productID: productID),
              entry.driver == "steelseries-nova"
        else { return nil }
        return entry
    }

    static func read(_ device: IOHIDDevice) -> DeviceReading {
        let productID = intProperty(device, kIOHIDProductIDKey) ?? 0
        let tableEntry = entry(forProductID: productID)
        let name = tableEntry?.name
            ?? stringProperty(device, kIOHIDProductKey)
            ?? "SteelSeries headset"

        var reading = DeviceReading(
            key: "steelseries-\(productID)",
            name: name,
            percent: nil,
            charging: false,
            online: false,
            transport: "2.4GHz",
            source: "steelseries-nova",
            note: nil
        )

        guard let variant = tableEntry.flatMap({ Variant(rawValue: $0.variant ?? "") }) else {
            reading.note = "unrecognized model"
            return reading
        }

        guard let session = HIDSession(device: device, bufferSize: statusBufferSize) else {
            reading.note = "base station busy"
            return reading
        }
        defer { session.close() }

        guard let data = session.exchange(
            reportID: 0,
            request: statusRequest,
            timeout: 1.5,
            accept: { $0.count >= variant.minimumLength }
        ) else {
            reading.note = "base station not responding"
            return reading
        }

        switch variant {
        case .nova5:
            // Byte 1: 0x02 means the headset itself is powered off / out of range.
            if data[1] == 0x02 {
                reading.note = "off or out of range"
                return reading
            }
            reading.online = true
            reading.charging = data[4] == 0x01
            reading.percent = clampPercent(Int(data[3]))

        case .nova7Discrete, .nova7Percent:
            if data[3] == 0x00 {
                reading.note = "off or out of range"
                return reading
            }
            reading.online = true
            reading.charging = data[3] == 0x01 || data[3] == 0x02
            // Older firmware reports 0-4 rather than a percentage.
            let raw = Int(data[2])
            reading.percent = variant == .nova7Discrete
                ? clampPercent(raw * 25)
                : clampPercent(raw)
        }

        return reading
    }

    static func clampPercent(_ value: Int) -> Int {
        min(100, max(0, value))
    }
}

struct SteelSeriesDriver: BatteryDriver {
    let id = "steelseries-nova"
    let displayName = "SteelSeries Arctis Nova (0xB0 status request)"

    func matches(_ device: IOHIDDevice) -> Bool {
        SteelSeries.matches(device)
    }

    func read(_ device: IOHIDDevice) -> [DeviceReading] {
        [SteelSeries.read(device)]
    }
}
