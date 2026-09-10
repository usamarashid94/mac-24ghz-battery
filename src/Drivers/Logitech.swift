// mac-24ghz-battery — part of https://github.com/usamarashid94/mac-24ghz-battery
// Copyright (C) 2026 usamarashid94. Licensed under GPL-3.0; see LICENSE.

import Foundation
import IOKit
import IOKit.hid

// MARK: - Logitech HID++ 2.0

/// Logitech Lightspeed and Unifying receivers speak HID++ 2.0 over a vendor HID
/// interface. Battery is not a fixed register: you ask the root feature (index 0)
/// for the index of a battery feature, then call that feature.
///
/// Request layout (short report, 7 bytes):
///   [0x10, deviceIndex, featureIndex, (function << 4) | softwareID, p0, p1, p2]
/// Replies arrive as short (0x10) or long (0x11) reports; an error reply is
/// marked by 0xFF in the feature-index slot.
enum Logitech {
    static let vendorID = 0x046D
    static let usagePage = 0xFF00

    static let shortReportID: UInt8 = 0x10
    static let longReportID: UInt8 = 0x11
    static let shortLength = 7
    static let softwareID: UInt8 = 0x08
    static let rootFeatureIndex: UInt8 = 0x00
    /// HID++ 2.0 marks errors with 0xFF in the feature slot; HID++ 1.0 uses the
    /// 0x8F "error message" sub-ID there instead. Receivers emit both.
    static let error20Marker: UInt8 = 0xFF
    static let error10Marker: UInt8 = 0x8F
    /// HID++ 1.0 error code for a pairing slot with nothing in it.
    static let errorUnknownDevice: UInt8 = 0x08

    static let featureUnifiedBattery: UInt16 = 0x1004
    static let featureBatteryLevelStatus: UInt16 = 0x1000
    /// Older gaming mice report millivolts instead of a percentage.
    static let featureBatteryVoltage: UInt16 = 0x1001
    static let featureDeviceName: UInt16 = 0x0005

    /// Paired-device slots to probe. Lightspeed receivers use slot 1; Unifying
    /// receivers pair up to six.
    static let deviceIndices: [UInt8] = [1, 2, 3, 4, 5, 6]
    static let replyTimeout: CFTimeInterval = 0.25

    static func matches(_ device: IOHIDDevice) -> Bool {
        guard intProperty(device, kIOHIDVendorIDKey) == vendorID else { return false }
        return intProperty(device, kIOHIDPrimaryUsagePageKey) == usagePage
    }

    /// Sends one HID++ request and returns the matching reply, error replies included.
    static func request(
        session: HIDSession,
        deviceIndex: UInt8,
        featureIndex: UInt8,
        function: UInt8,
        params: [UInt8] = []
    ) -> [UInt8]? {
        let header: UInt8 = (function << 4) | softwareID
        var payload: [UInt8] = [shortReportID, deviceIndex, featureIndex, header]
        payload.append(contentsOf: params)
        while payload.count < shortLength { payload.append(0) }

        return session.exchange(
            reportID: shortReportID,
            request: payload,
            timeout: replyTimeout,
            accept: { reply in
                guard reply.count >= 5 else { return false }
                guard reply[0] == shortReportID || reply[0] == longReportID else { return false }
                guard reply[1] == deviceIndex else { return false }
                // Both error forms echo the feature and function we sent, in the
                // slot just after the marker.
                if reply[2] == error20Marker || reply[2] == error10Marker {
                    return reply[3] == featureIndex && reply[4] == header
                }
                return reply[2] == featureIndex && reply[3] == header
            }
        )
    }

    static func isError(_ reply: [UInt8]) -> Bool {
        reply.count >= 3 && (reply[2] == error20Marker || reply[2] == error10Marker)
    }

    /// True when the receiver says the slot holds no paired device.
    static func isUnknownDevice(_ reply: [UInt8]) -> Bool {
        reply.count >= 6 && reply[2] == error10Marker && reply[5] == errorUnknownDevice
    }

    /// An empty slot answers with "unknown device"; a paired but sleeping device
    /// says nothing at all. Those mean very different things to the display.
    enum FeatureLookup {
        case index(UInt8)
        case unsupported
        case emptySlot
        case noReply
    }

    /// Resolves a feature ID to the index this particular device assigns it.
    static func featureIndex(
        session: HIDSession,
        deviceIndex: UInt8,
        feature: UInt16
    ) -> FeatureLookup {
        let params: [UInt8] = [UInt8(feature >> 8), UInt8(feature & 0xFF), 0x00]
        guard let reply = request(
            session: session,
            deviceIndex: deviceIndex,
            featureIndex: rootFeatureIndex,
            function: 0x00,
            params: params
        ) else { return .noReply }

        if isUnknownDevice(reply) { return .emptySlot }
        guard !isError(reply), reply.count >= 5 else { return .unsupported }
        // Index 0 means the device does not implement the feature.
        return reply[4] == 0 ? .unsupported : .index(reply[4])
    }

    /// Feature 0x1004: state of charge is already a percentage.
    static func unifiedBattery(
        session: HIDSession,
        deviceIndex: UInt8,
        index: UInt8
    ) -> (percent: Int, charging: Bool)? {
        guard let reply = request(
            session: session,
            deviceIndex: deviceIndex,
            featureIndex: index,
            function: 0x01
        ), !isError(reply), reply.count >= 7 else { return nil }

        let charging = reply[6] == 0x01 || reply[6] == 0x02 || reply[6] == 0x03
        return (Int(reply[4]), charging)
    }

    /// Feature 0x1000: older devices report a coarse discharge level instead.
    static func batteryLevelStatus(
        session: HIDSession,
        deviceIndex: UInt8,
        index: UInt8
    ) -> (percent: Int, charging: Bool)? {
        guard let reply = request(
            session: session,
            deviceIndex: deviceIndex,
            featureIndex: index,
            function: 0x00
        ), !isError(reply), reply.count >= 7 else { return nil }

        return (Int(reply[4]), reply[6] == 0x01)
    }


    /// Feature 0x1001: millivolts, not a percentage.
    ///
    /// Discharge is not linear, so a curve is needed. This one is Solaar's
    /// (GPL-2.0), interpolated linearly between points — the same mapping their
    /// users have validated against Logitech's own reporting.
    static let voltageCurve: [(millivolts: Int, percent: Int)] = [
        (4186, 100), (4067, 90), (3989, 80), (3922, 70), (3859, 60),
        (3811, 50), (3778, 40), (3751, 30), (3717, 20), (3671, 10),
        (3646, 5), (3579, 2), (3500, 0),
    ]

    static func percentage(forMillivolts millivolts: Int) -> Int {
        guard let first = voltageCurve.first, let last = voltageCurve.last else { return 0 }
        if millivolts >= first.millivolts { return first.percent }
        if millivolts <= last.millivolts { return last.percent }

        for index in 0..<(voltageCurve.count - 1) {
            let high = voltageCurve[index]
            let low = voltageCurve[index + 1]
            if millivolts >= low.millivolts && millivolts <= high.millivolts {
                let span = Double(high.millivolts - low.millivolts)
                guard span > 0 else { return low.percent }
                let ratio = Double(millivolts - low.millivolts) / span
                let percent = Double(low.percent) + Double(high.percent - low.percent) * ratio
                return Int(percent.rounded())
            }
        }
        return 0
    }

    static func batteryVoltage(
        session: HIDSession,
        deviceIndex: UInt8,
        index: UInt8
    ) -> (percent: Int, charging: Bool)? {
        guard let reply = request(
            session: session,
            deviceIndex: deviceIndex,
            featureIndex: index,
            function: 0x00
        ), !isError(reply), reply.count >= 7 else { return nil }

        let millivolts = Int(reply[4]) << 8 | Int(reply[5])
        // A plausible single-cell lithium reading. Anything else means the
        // layout is wrong, and a wrong layout must not become a battery level.
        guard (2500...5000).contains(millivolts) else {
            debugLog("implausible battery voltage \(millivolts) mV, ignoring")
            return nil
        }
        // Bit 7 of the status byte marks charging.
        let charging = (reply[6] & 0x80) != 0
        return (percentage(forMillivolts: millivolts), charging)
    }

    /// Feature 0x0005: the marketing name, e.g. "G502 X". Falls back to nil.
    static func deviceName(session: HIDSession, deviceIndex: UInt8) -> String? {
        guard case let .index(nameIndex) = featureIndex(
            session: session,
            deviceIndex: deviceIndex,
            feature: featureDeviceName
        ) else { return nil }

        guard let countReply = request(
            session: session,
            deviceIndex: deviceIndex,
            featureIndex: nameIndex,
            function: 0x00
        ), !isError(countReply), countReply.count >= 5 else { return nil }

        let total = Int(countReply[4])
        guard total > 0 else { return nil }

        var characters: [UInt8] = []
        while characters.count < total {
            guard let chunk = request(
                session: session,
                deviceIndex: deviceIndex,
                featureIndex: nameIndex,
                function: 0x01,
                params: [UInt8(characters.count)]
            ), !isError(chunk), chunk.count > 4 else { break }

            let payload = chunk[4...].prefix(while: { $0 != 0 })
            if payload.isEmpty { break }
            characters.append(contentsOf: payload)
        }

        guard !characters.isEmpty else { return nil }
        let name = String(decoding: characters.prefix(total), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    /// Probes each paired slot and returns a reading per device that answers.
    static func read(_ device: IOHIDDevice) -> [DeviceReading] {
        guard let session = HIDSession(device: device, bufferSize: 64) else { return [] }
        defer { session.close() }

        var readings: [DeviceReading] = []

        for deviceIndex in deviceIndices {
            var result: (percent: Int, charging: Bool)?
            let key = "logitech-slot-\(deviceIndex)"

            switch featureIndex(
                session: session,
                deviceIndex: deviceIndex,
                feature: featureUnifiedBattery
            ) {
            case .emptySlot:
                debugLog("slot \(deviceIndex): empty")
                continue
            case .noReply:
                // Paired but not answering — almost always asleep. Report it as
                // such so it keeps its place in the display with a stale level.
                debugLog("slot \(deviceIndex): no reply, treating as asleep")
                readings.append(DeviceReading(
                    key: key,
                    name: "Logitech device \(deviceIndex)",
                    percent: nil,
                    charging: false,
                    online: false,
                    transport: "2.4GHz",
                    source: "logitech-hid++",
                    note: "asleep"
                ))
                continue
            case let .index(index):
                result = unifiedBattery(session: session, deviceIndex: deviceIndex, index: index)
            case .unsupported:
                break
            }

            if result == nil, case let .index(index) = featureIndex(
                session: session,
                deviceIndex: deviceIndex,
                feature: featureBatteryLevelStatus
            ) {
                result = batteryLevelStatus(session: session, deviceIndex: deviceIndex, index: index)
            }

            // Older gaming mice implement neither of the above and report
            // millivolts, which need a discharge curve to become a percentage.
            if result == nil, case let .index(index) = featureIndex(
                session: session,
                deviceIndex: deviceIndex,
                feature: featureBatteryVoltage
            ) {
                result = batteryVoltage(session: session, deviceIndex: deviceIndex, index: index)
            }

            guard let result else {
                debugLog("slot \(deviceIndex): answered but reported no battery feature")
                continue
            }

            let name = deviceName(session: session, deviceIndex: deviceIndex)
                .map { $0.hasPrefix("Logitech") ? $0 : "Logitech \($0)" }
                ?? "Logitech device \(deviceIndex)"

            readings.append(DeviceReading(
                key: key,
                name: name,
                percent: min(100, max(0, result.percent)),
                charging: result.charging,
                online: true,
                transport: "2.4GHz",
                source: "logitech-hid++",
                note: nil
            ))
        }

        return readings
    }
}

struct LogitechDriver: BatteryDriver {
    let id = "logitech-hid++"
    let displayName = "Logitech HID++ 2.0 (Lightspeed / Unifying)"

    func matches(_ device: IOHIDDevice) -> Bool {
        Logitech.matches(device)
    }

    func read(_ device: IOHIDDevice) -> [DeviceReading] {
        Logitech.read(device)
    }
}
