// mac-24ghz-battery — battery for 2.4 GHz (USB dongle) wireless devices on macOS.
// Copyright (C) 2026 usamarashid94
//
// Licensed under the GNU General Public License v3.0. See LICENSE.
// The SteelSeries Nova wire format was derived from HeadsetControl (GPL-3.0)
// by Sapd: https://github.com/Sapd/HeadsetControl
//
// Two sources of truth, in order:
//   1. Vendor protocol for SteelSeries Arctis Nova base stations, which do not
//      publish a battery level to macOS at all. Wire format per HeadsetControl:
//      write a 1-byte 0xB0 status request to the 0xFFC0 vendor HID interface,
//      then read the status report back (byte 1 = link state, byte 3 = percent,
//      byte 4 = charging).
//   2. Any HID device that publishes the standard BatteryPercent property, which
//      needs no per-device code and picks up new hardware automatically.

import Foundation
import IOKit
import IOKit.hid

// MARK: - Model

struct DeviceReading {
    /// Stable identity across runs, so a sleeping device can be matched to its
    /// last known reading. Not the display name: a sleeping device won't tell
    /// us its name.
    var key: String
    var name: String
    var percent: Int?
    var charging: Bool
    var online: Bool
    var transport: String
    var source: String
    /// State word shown when the device is unreachable: "asleep", "off", etc.
    var note: String?
    /// True when percent/name came from cache rather than the device.
    var stale: Bool = false
    var lastSeen: Date?
}

// MARK: - Last-known state

/// A wireless device that has gone to sleep is the normal case, not an error,
/// and dropping it from the display is the wrong answer — its battery level is
/// still roughly what it was. Remember the last good reading and show it, aged.
enum Cache {
    struct Entry: Codable {
        var name: String
        var percent: Int?
        var charging: Bool
        var timestamp: Date
    }

    static var url: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("mac-24ghz-battery.json")
    }

    static func load() -> [String: Entry] {
        guard let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([String: Entry].self, from: data)
        else { return [:] }
        return entries
    }

    static func save(_ entries: [String: Entry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

/// "3m", "2h", "4d" — deliberately coarse; a battery level doesn't need seconds.
func shortAge(_ interval: TimeInterval) -> String {
    let seconds = Int(max(0, interval))
    if seconds < 60 { return "\(seconds)s" }
    if seconds < 3600 { return "\(seconds / 60)m" }
    if seconds < 86400 { return "\(seconds / 3600)h" }
    return "\(seconds / 86400)d"
}

// MARK: - HID helpers

func property(_ device: IOHIDDevice, _ key: String) -> Any? {
    IOHIDDeviceGetProperty(device, key as CFString)
}

func intProperty(_ device: IOHIDDevice, _ key: String) -> Int? {
    property(device, key) as? Int
}

func stringProperty(_ device: IOHIDDevice, _ key: String) -> String? {
    property(device, key) as? String
}

func allDevices() -> [IOHIDDevice] {
    let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    IOHIDManagerSetDeviceMatching(manager, nil)
    guard let set = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return [] }
    return Array(set)
}

// MARK: - Input report plumbing

var debugEnabled = false

func debugLog(_ message: @autoclosure () -> String) {
    guard debugEnabled else { return }
    FileHandle.standardError.write(Data(("[debug] " + message() + "\n").utf8))
}

func hex(_ bytes: [UInt8]) -> String {
    bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
}

/// Collects input reports delivered on the run loop while we wait for a reply.
/// A device can emit unrelated reports mid-exchange, so the caller supplies a
/// predicate that recognizes the reply it asked for.
final class ReportSink {
    var report: [UInt8]?
    var accept: ([UInt8]) -> Bool

    init() {
        self.accept = { _ in false }
    }

    func expect(_ accept: @escaping ([UInt8]) -> Bool) {
        self.report = nil
        self.accept = accept
    }
}

/// An active device is chatty: a mouse in use streams input reports on the same
/// vendor interface we're querying. Those can land while a session is being torn
/// down, so the callback context and its buffer are retained for the life of the
/// process rather than freed — this is a short-lived CLI, and a few hundred bytes
/// held to the end is the cheapest way to make late reports harmless.
var retainedSinks: [ReportSink] = []
var retainedBuffers: [UnsafeMutablePointer<UInt8>] = []

private let inputReportCallback: IOHIDReportCallback = { context, _, _, _, reportID, report, reportLength in
    guard let context, reportLength > 0 else { return }
    let sink = Unmanaged<ReportSink>.fromOpaque(context).takeUnretainedValue()
    guard sink.report == nil else { return }

    var bytes = Array(UnsafeBufferPointer(start: report, count: reportLength))
    // IOKit may hand back the payload with or without the leading report ID.
    // Normalize to "report ID included" so parsers can use fixed offsets.
    let id = UInt8(truncatingIfNeeded: reportID)
    if id != 0 && bytes.first != id {
        bytes.insert(id, at: 0)
    }

    debugLog("input report id=0x\(String(format: "%02x", id)) len=\(bytes.count): \(hex(bytes))")

    guard sink.accept(bytes) else { return }
    sink.report = bytes
    CFRunLoopStop(CFRunLoopGetCurrent())
}

/// One open device, held for as many request/reply round trips as the caller
/// needs. Opening per request meant tearing the callback down repeatedly while
/// the device was still sending, which crashed intermittently.
final class HIDSession {
    private let device: IOHIDDevice
    private let buffer: UnsafeMutablePointer<UInt8>
    private let bufferSize: Int
    private let sink: ReportSink

    init?(device: IOHIDDevice, bufferSize: Int) {
        guard IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            debugLog("open failed")
            return nil
        }

        self.device = device
        self.bufferSize = bufferSize
        self.buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        self.buffer.initialize(repeating: 0, count: bufferSize)
        self.sink = ReportSink()

        retainedSinks.append(sink)
        retainedBuffers.append(buffer)

        let context = Unmanaged.passUnretained(sink).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(device, buffer, bufferSize, inputReportCallback, context)
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
    }

    /// Writes `request` and waits for the first reply the predicate accepts.
    func exchange(
        reportID: UInt8,
        request: [UInt8],
        timeout: CFTimeInterval,
        accept: @escaping ([UInt8]) -> Bool
    ) -> [UInt8]? {
        sink.expect(accept)

        debugLog("write report id=0x\(String(format: "%02x", reportID)): \(hex(request))")

        // A numbered report carries its ID as the first payload byte; report 0 does not.
        let sent = IOHIDDeviceSetReport(
            device,
            kIOHIDReportTypeOutput,
            CFIndex(reportID),
            request,
            request.count
        )
        guard sent == kIOReturnSuccess else {
            debugLog("SetReport failed: 0x\(String(format: "%08x", sent))")
            return nil
        }

        let deadline = CFAbsoluteTimeGetCurrent() + timeout
        while sink.report == nil && CFAbsoluteTimeGetCurrent() < deadline {
            CFRunLoopRunInMode(.defaultMode, 0.02, true)
        }
        return sink.report
    }

    /// Detaches from the run loop. The buffer and sink stay alive on purpose.
    func close() {
        IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDDeviceRegisterInputReportCallback(device, buffer, bufferSize, nil, nil)
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
    }
}

// MARK: - SteelSeries Arctis Nova

enum SteelSeries {
    static let vendorID = 0x1038
    static let vendorUsagePage = 0xFFC0
    static let vendorUsage = 0x1
    static let statusRequest: [UInt8] = [0xB0]
    static let statusBufferSize = 128
    static let statusMinimumLength = 16

    /// Nova base stations that speak the 0xB0 status protocol.
    static let productNames: [Int: String] = [
        0x2232: "Arctis Nova 5",
        0x2253: "Arctis Nova 5X",
        0x2202: "Arctis Nova 7",
        0x2206: "Arctis Nova 7X",
        0x220A: "Arctis Nova 7P",
        0x2258: "Arctis Nova 3 Wireless",
    ]

    static func matches(_ device: IOHIDDevice) -> Bool {
        guard intProperty(device, kIOHIDVendorIDKey) == vendorID else { return false }
        guard intProperty(device, kIOHIDPrimaryUsagePageKey) == vendorUsagePage else { return false }
        guard intProperty(device, kIOHIDPrimaryUsageKey) == vendorUsage else { return false }
        guard let productID = intProperty(device, kIOHIDProductIDKey) else { return false }
        return productNames[productID] != nil
    }

    static func read(_ device: IOHIDDevice) -> DeviceReading {
        let name = stringProperty(device, kIOHIDProductKey)
            ?? productNames[intProperty(device, kIOHIDProductIDKey) ?? 0]
            ?? "SteelSeries headset"

        var reading = DeviceReading(
            key: "steelseries-\(intProperty(device, kIOHIDProductIDKey) ?? 0)",
            name: name,
            percent: nil,
            charging: false,
            online: false,
            transport: "2.4GHz",
            source: "steelseries-nova",
            note: nil
        )

        guard let session = HIDSession(device: device, bufferSize: statusBufferSize) else {
            reading.note = "base station busy"
            return reading
        }
        defer { session.close() }

        guard let data = session.exchange(
            reportID: 0,
            request: statusRequest,
            timeout: 1.5,
            accept: { $0.count >= statusMinimumLength }
        ) else {
            reading.note = "base station not responding"
            return reading
        }

        // Byte 1: 0x02 means the headset itself is powered off / out of range.
        if data[1] == 0x02 {
            reading.note = "off or out of range"
            return reading
        }

        reading.online = true
        reading.charging = data[4] == 0x01
        reading.percent = min(100, max(0, Int(data[3])))
        return reading
    }
}

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

// MARK: - Collection

func collectReadings(includeBluetooth: Bool) -> [DeviceReading] {
    var readings: [DeviceReading] = []
    var seen = Set<String>()

    for device in allDevices() {
        if SteelSeries.matches(device) {
            let reading = SteelSeries.read(device)
            if seen.insert(reading.name).inserted {
                readings.append(reading)
            }
            continue
        }
        if Logitech.matches(device) {
            for reading in Logitech.read(device) where seen.insert(reading.name).inserted {
                readings.append(reading)
            }
            continue
        }
        if let reading = GenericBattery.read(device, includeBluetooth: includeBluetooth) {
            // One physical device can expose several HID interfaces.
            if seen.insert(reading.name).inserted {
                readings.append(reading)
            }
        }
    }

    return applyCache(to: readings).sorted { $0.name < $1.name }
}

/// Fills unreachable devices in from the last good reading, and records the
/// reachable ones for next time.
func applyCache(to readings: [DeviceReading]) -> [DeviceReading] {
    var entries = Cache.load()
    let now = Date()
    var resolved: [DeviceReading] = []

    for var reading in readings {
        if reading.online, reading.percent != nil {
            entries[reading.key] = Cache.Entry(
                name: reading.name,
                percent: reading.percent,
                charging: reading.charging,
                timestamp: now
            )
        } else if let entry = entries[reading.key] {
            // A sleeping device won't give its name either, so take that too
            // rather than showing "Logitech device 1".
            if reading.name.hasPrefix("Logitech device ") || reading.name.isEmpty {
                reading.name = entry.name
            }
            reading.percent = entry.percent
            reading.stale = entry.percent != nil
            reading.lastSeen = entry.timestamp
        }
        resolved.append(reading)
    }

    Cache.save(entries)
    return resolved
}

// MARK: - Output

func icon(for reading: DeviceReading) -> String {
    let lowercased = reading.name.lowercased()
    if lowercased.contains("arctis") || lowercased.contains("headset") { return "🎧" }
    // Logitech reports marketing names like "G502 X", with no word for the form factor.
    if lowercased.contains("mouse") || lowercased.contains("mx ")
        || lowercased.range(of: #"\bg\d{3}"#, options: .regularExpression) != nil { return "🖱" }
    if lowercased.contains("keyboard") || lowercased.contains("keychron")
        || lowercased.contains("keys") { return "⌨️" }
    return "📶"
}

func statusText(for reading: DeviceReading) -> String {
    if reading.online, let percent = reading.percent {
        return reading.charging ? "\(percent)% ⚡︎" : "\(percent)%"
    }

    let state = reading.note ?? "offline"
    // A stale level is still worth showing, as long as it's labelled as old.
    guard let percent = reading.percent, let lastSeen = reading.lastSeen else {
        return state
    }
    return "\(percent)% · \(state) \(shortAge(Date().timeIntervalSince(lastSeen)))"
}

func printJSON(_ readings: [DeviceReading]) {
    let payload: [[String: Any]] = readings.map { reading in
        var entry: [String: Any] = [
            "name": reading.name,
            "online": reading.online,
            "charging": reading.charging,
            "transport": reading.transport,
            "source": reading.source,
            "stale": reading.stale,
        ]
        if let lastSeen = reading.lastSeen {
            entry["lastSeen"] = ISO8601DateFormatter().string(from: lastSeen)
        }
        // Must branch explicitly: `percent as Any?` would wrap a nil Int inside a
        // non-nil Any, which slips past ?? and makes JSONSerialization throw an
        // Objective-C exception that try? cannot catch.
        if let percent = reading.percent {
            entry["percent"] = percent
        } else {
            entry["percent"] = NSNull()
        }
        if let note = reading.note { entry["note"] = note }
        return entry
    }

    let root: [String: Any] = [
        "generated": ISO8601DateFormatter().string(from: Date()),
        "devices": payload,
    ]

    guard JSONSerialization.isValidJSONObject(root),
          let data = try? JSONSerialization.data(
              withJSONObject: root,
              options: [.prettyPrinted, .sortedKeys]
          )
    else {
        print("{\"devices\":[]}")
        return
    }
    print(String(decoding: data, as: UTF8.self))
}

func printPlain(_ readings: [DeviceReading]) {
    if readings.isEmpty {
        print("No 2.4 GHz devices found.")
        return
    }
    for reading in readings {
        print("\(icon(for: reading)) \(reading.name): \(statusText(for: reading))")
    }
}

/// SwiftBar plugin output: first line is the menu bar, everything after "---" is the dropdown.
/// Palette matches the existing goldbot-vitals plugin so the menu bar reads as one system.
enum Palette {
    static let ok = "#43C59E"
    static let warn = "#E5B567"
    static let bad = "#E06C5F"
    static let dim = "#8A97A5"
}

func printSwiftBar(_ readings: [DeviceReading]) {
    let reporting = readings.filter { $0.online && $0.percent != nil }

    if readings.isEmpty {
        print("🔌")
        print("---")
        print("No 2.4 GHz dongles connected | color=\(Palette.dim)")
        return
    }

    // Menu bar: the lowest battery, since that's the one that needs attention.
    // Prefer a live reading, but a stale one beats showing nothing.
    let candidates = reporting.isEmpty ? readings.filter { $0.percent != nil } : reporting
    if let lowest = candidates.min(by: { ($0.percent ?? 100) < ($1.percent ?? 100) }) {
        let level = lowest.percent.map { "\($0)%" } ?? "—"
        let charge = lowest.charging && lowest.online ? " ⚡︎" : ""
        // A trailing dot marks a level that's remembered rather than current.
        let staleMark = lowest.stale ? " ·" : ""
        print("\(icon(for: lowest)) \(level)\(charge)\(staleMark)")
    } else {
        print("\(icon(for: readings[0])) —")
    }

    print("---")
    for reading in readings {
        let color: String
        if !reading.online {
            // Dim whether or not we have a remembered level: it isn't current.
            color = Palette.dim
        } else if let percent = reading.percent, percent <= 20 {
            color = Palette.bad
        } else if let percent = reading.percent, percent <= 40 {
            color = Palette.warn
        } else {
            color = Palette.ok
        }
        print("\(icon(for: reading)) \(reading.name)  \(statusText(for: reading)) | color=\(color)")
    }
    print("---")
    print("Refresh | refresh=true")
}

// MARK: - Entry point

let arguments = Set(CommandLine.arguments.dropFirst())

if arguments.contains("--help") || arguments.contains("-h") {
    print("""
    wireless-battery — battery for 2.4 GHz dongle devices

    Usage: wireless-battery [--json | --swiftbar] [--all]

      --json       machine-readable output
      --swiftbar   SwiftBar plugin format
      --all        also include Bluetooth devices that report battery
      --debug      dump HID traffic to stderr
      --help       this message
    """)
    exit(0)
}

debugEnabled = arguments.contains("--debug")

let readings = collectReadings(includeBluetooth: arguments.contains("--all"))

if arguments.contains("--json") {
    printJSON(readings)
} else if arguments.contains("--swiftbar") {
    printSwiftBar(readings)
} else {
    printPlain(readings)
}
