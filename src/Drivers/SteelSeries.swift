// mac-24ghz-battery — part of https://github.com/usamarashid94/mac-24ghz-battery
// Copyright (C) 2026 usamarashid94. Licensed under GPL-3.0; see LICENSE.

import Foundation
import IOKit
import IOKit.hid

/// SteelSeries wireless headsets.
///
/// Several product families share the vendor-HID transport but agree on almost
/// nothing else: the request bytes, the reply length, which byte holds the
/// level, whether there is a status byte, and whether the level is a percentage
/// at all all vary. Each family therefore parses its own reply explicitly rather
/// than sharing offsets — using one family's offsets on another doesn't fail
/// loudly, it reports a status byte as a battery percentage.
///
/// Product IDs and reply layouts follow HeadsetControl (GPL-3.0).
enum SteelSeries {
    static let vendorID = 0x1038
    static let statusBufferSize = 128

    enum Variant: String {
        /// Arctis Nova 5 / 5X base stations.
        case nova5
        /// Arctis Nova 7 family, original firmware: a 0-4 step.
        case nova7Discrete
        /// Arctis Nova 7 family, updated firmware: a percentage.
        case nova7Percent
        /// Arctis 7 and Arctis Pro.
        case legacyArctis7
        /// Arctis 1 family, including the 7X.
        case arctis1
        /// Arctis 9, whose raw level runs 0x64...0x9A rather than 0-100.
        case arctis9

        /// Report ID the request is sent under. Zero means an unnumbered report.
        var reportID: UInt8 {
            switch self {
            case .nova5, .nova7Discrete, .nova7Percent, .arctis9: return 0x00
            case .legacyArctis7, .arctis1: return 0x06
            }
        }

        /// Full request buffer, including the report ID byte when numbered.
        var request: [UInt8] {
            switch self {
            case .nova5, .nova7Discrete, .nova7Percent: return [0xB0]
            case .legacyArctis7: return [0x06, 0x18]
            case .arctis1: return [0x06, 0x12]
            case .arctis9: return [0x20]
            }
        }

        /// Shortest reply this layout can be read from.
        var minimumLength: Int {
            switch self {
            case .nova5: return 16
            case .nova7Discrete, .nova7Percent: return 4
            case .legacyArctis7: return 3
            case .arctis1: return 4
            case .arctis9: return 5
            }
        }
    }

    /// Outcome of parsing a reply. `unreadable` keeps a bad parse from being
    /// mistaken for a real level.
    enum Parsed {
        case online(percent: Int, charging: Bool)
        case offline(String)
        case unreadable
    }

    static func parse(_ data: [UInt8], as variant: Variant) -> Parsed {
        guard data.count >= variant.minimumLength else { return .unreadable }

        switch variant {
        case .nova5:
            // Byte 1: 0x02 means the headset is powered off or out of range.
            if data[1] == 0x02 { return .offline("off or out of range") }
            return validated(Int(data[3]), charging: data[4] == 0x01)

        case .nova7Discrete, .nova7Percent:
            if data[3] == 0x00 { return .offline("off or out of range") }
            let charging = data[3] == 0x01 || data[3] == 0x02
            let raw = Int(data[2])
            // Original firmware reports a 0-4 step instead of a percentage.
            return validated(variant == .nova7Discrete ? raw * 25 : raw, charging: charging)

        case .legacyArctis7:
            // No status byte on this family: the level is all there is.
            return validated(Int(data[2]), charging: false)

        case .arctis1:
            if data[2] == 0x01 { return .offline("off or out of range") }
            return validated(Int(data[3]), charging: false)

        case .arctis9:
            // Raw level runs 0x64 (empty) to 0x9A (full).
            let raw = Int(data[3])
            guard raw >= 0x64, raw <= 0x9A else { return .unreadable }
            let percent = Int((Double(raw - 0x64) / Double(0x9A - 0x64) * 100).rounded())
            return validated(percent, charging: data[4] == 0x01)
        }
    }

    /// A level outside 0-100 means the layout is wrong; say so rather than
    /// clamping a nonsense value into a plausible-looking number.
    static func validated(_ percent: Int, charging: Bool) -> Parsed {
        guard (0...100).contains(percent) else { return .unreadable }
        return .online(percent: percent, charging: charging)
    }

    static func entry(forProductID productID: Int) -> DeviceEntry? {
        guard let entry = DeviceTable.entry(vendorID: vendorID, productID: productID),
              entry.driver == "steelseries"
        else { return nil }
        return entry
    }

    /// Vendor-defined pages only. Which vendor interface carries the protocol
    /// varies by model and macOS exposes no interface numbers, so every vendor
    /// collection is offered the request and the first plausible reply wins.
    static func isVendorPage(_ page: Int) -> Bool {
        page >= 0xFF00 && page <= 0xFFFF
    }

    static func matches(_ device: IOHIDDevice) -> Bool {
        guard intProperty(device, kIOHIDVendorIDKey) == vendorID else { return false }
        guard let page = intProperty(device, kIOHIDPrimaryUsagePageKey), isVendorPage(page) else {
            return false
        }
        guard let productID = intProperty(device, kIOHIDProductIDKey) else { return false }
        return entry(forProductID: productID) != nil
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
            source: "steelseries",
            note: nil
        )

        guard let variant = tableEntry.flatMap({ Variant(rawValue: $0.variant ?? "") }) else {
            reading.note = "unrecognized model"
            return reading
        }

        guard let session = HIDSession(device: device, bufferSize: statusBufferSize) else {
            reading.note = "busy"
            return reading
        }
        defer { session.close() }

        guard let data = session.exchange(
            reportID: variant.reportID,
            request: variant.request,
            // A live headset answers in about 10 ms, so this is ~50x the margin
            // that matters. A base station whose headset is off may take over a
            // second to answer, or never answer — but both of those mean the
            // same thing to the display, so waiting for the distinction cost
            // 1.5s on every read and bought only a nicer note.
            timeout: 0.5,
            accept: { $0.count >= variant.minimumLength }
        ) else {
            reading.note = "not responding"
            return reading
        }

        switch parse(data, as: variant) {
        case let .online(percent, charging):
            reading.online = true
            reading.percent = percent
            reading.charging = charging
        case let .offline(note):
            reading.note = note
        case .unreadable:
            debugLog("unreadable \(variant.rawValue) reply: \(hex(data.prefix(12).map { $0 }))")
            reading.note = "unreadable reply"
        }

        return reading
    }
}

struct SteelSeriesDriver: BatteryDriver {
    let id = "steelseries"
    let displayName = "SteelSeries Arctis (vendor HID)"

    func matches(_ device: IOHIDDevice) -> Bool {
        SteelSeries.matches(device)
    }

    func read(_ device: IOHIDDevice) -> [DeviceReading] {
        [SteelSeries.read(device)]
    }
}
