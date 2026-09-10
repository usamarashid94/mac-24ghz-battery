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
    var name: String
    var percent: Int?
    var charging: Bool
    var online: Bool
    var transport: String
    var source: String
    var note: String?
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

/// Collects input reports delivered on the run loop while we wait for a reply.
final class ReportSink {
    var report: [UInt8]?
    var minimumLength: Int

    init(minimumLength: Int) {
        self.minimumLength = minimumLength
    }
}

private let inputReportCallback: IOHIDReportCallback = { context, _, _, _, _, report, reportLength in
    guard let context else { return }
    let sink = Unmanaged<ReportSink>.fromOpaque(context).takeUnretainedValue()
    // The dongle can emit unrelated short reports; only a full status frame counts.
    guard reportLength >= sink.minimumLength, sink.report == nil else { return }
    sink.report = Array(UnsafeBufferPointer(start: report, count: reportLength))
    CFRunLoopStop(CFRunLoopGetCurrent())
}

/// Writes `request` as an output report and waits for the device's reply.
func exchange(
    device: IOHIDDevice,
    request: [UInt8],
    bufferSize: Int,
    minimumReplyLength: Int,
    timeout: CFTimeInterval
) -> [UInt8]? {
    guard IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
        return nil
    }
    defer { IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone)) }

    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
    buffer.initialize(repeating: 0, count: bufferSize)
    let sink = ReportSink(minimumLength: minimumReplyLength)
    let context = Unmanaged.passUnretained(sink).toOpaque()

    IOHIDDeviceRegisterInputReportCallback(device, buffer, bufferSize, inputReportCallback, context)
    IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

    let sent = IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0, request, request.count)
    if sent == kIOReturnSuccess {
        let deadline = CFAbsoluteTimeGetCurrent() + timeout
        while sink.report == nil && CFAbsoluteTimeGetCurrent() < deadline {
            CFRunLoopRunInMode(.defaultMode, 0.05, true)
        }
    }

    IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
    IOHIDDeviceRegisterInputReportCallback(device, buffer, bufferSize, nil, nil)
    buffer.deinitialize(count: bufferSize)
    buffer.deallocate()

    return sink.report
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
            name: name,
            percent: nil,
            charging: false,
            online: false,
            transport: "2.4GHz",
            source: "steelseries-nova",
            note: nil
        )

        guard let data = exchange(
            device: device,
            request: statusRequest,
            bufferSize: statusBufferSize,
            minimumReplyLength: statusMinimumLength,
            timeout: 1.5
        ) else {
            reading.note = "no response from base station"
            return reading
        }

        // Byte 1: 0x02 means the headset itself is powered off / out of range.
        if data[1] == 0x02 {
            reading.note = "headset off or out of range"
            return reading
        }

        reading.online = true
        reading.charging = data[4] == 0x01
        reading.percent = min(100, max(0, Int(data[3])))
        return reading
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
        if let reading = GenericBattery.read(device, includeBluetooth: includeBluetooth) {
            // One physical device can expose several HID interfaces.
            if seen.insert(reading.name).inserted {
                readings.append(reading)
            }
        }
    }

    return readings.sorted { $0.name < $1.name }
}

// MARK: - Output

func icon(for reading: DeviceReading) -> String {
    let lowercased = reading.name.lowercased()
    if lowercased.contains("arctis") || lowercased.contains("headset") { return "🎧" }
    if lowercased.contains("mouse") { return "🖱" }
    if lowercased.contains("keyboard") || lowercased.contains("keychron") { return "⌨️" }
    return "📶"
}

func statusText(for reading: DeviceReading) -> String {
    guard reading.online, let percent = reading.percent else {
        return reading.note ?? "offline"
    }
    return reading.charging ? "\(percent)% ⚡︎" : "\(percent)%"
}

func printJSON(_ readings: [DeviceReading]) {
    let payload: [[String: Any]] = readings.map { reading in
        var entry: [String: Any] = [
            "name": reading.name,
            "online": reading.online,
            "charging": reading.charging,
            "transport": reading.transport,
            "source": reading.source,
        ]
        entry["percent"] = reading.percent as Any? ?? NSNull()
        if let note = reading.note { entry["note"] = note }
        return entry
    }

    let root: [String: Any] = [
        "generated": ISO8601DateFormatter().string(from: Date()),
        "devices": payload,
    ]

    guard let data = try? JSONSerialization.data(
        withJSONObject: root,
        options: [.prettyPrinted, .sortedKeys]
    ) else {
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
    if let lowest = reporting.min(by: { ($0.percent ?? 100) < ($1.percent ?? 100) }) {
        print("\(icon(for: lowest)) \(statusText(for: lowest))")
    } else {
        print("\(icon(for: readings[0])) —")
    }

    print("---")
    for reading in readings {
        let color: String
        if !reading.online {
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
      --help       this message
    """)
    exit(0)
}

let readings = collectReadings(includeBluetooth: arguments.contains("--all"))

if arguments.contains("--json") {
    printJSON(readings)
} else if arguments.contains("--swiftbar") {
    printSwiftBar(readings)
} else {
    printPlain(readings)
}
