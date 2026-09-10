// mac-24ghz-battery — part of https://github.com/usamarashid94/mac-24ghz-battery
// Copyright (C) 2026 usamarashid94. Licensed under GPL-3.0; see LICENSE.

import Foundation

// MARK: - Output

/// Devices worth putting on screen.
///
/// A device that has gone away — dongle unplugged, headset switched off, mouse
/// asleep — is dropped rather than lingering with a remembered level, so the
/// display reflects what is actually connected right now. It reappears on its
/// own as soon as it answers again.
///
/// Set WIRELESS_BATTERY_SHOW_OFFLINE=1 to keep showing them with their last
/// known level and its age instead.
let showOfflineDevices: Bool =
    ProcessInfo.processInfo.environment["WIRELESS_BATTERY_SHOW_OFFLINE"] == "1"

func visibleReadings(_ readings: [DeviceReading]) -> [DeviceReading] {
    showOfflineDevices ? readings : readings.filter(\.online)
}

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
    print(jsonString(for: readings))
}

/// Separated from printing so tests can assert on it.
func jsonString(for readings: [DeviceReading]) -> String {
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
        return "{\"devices\":[]}"
    }
    return String(decoding: data, as: UTF8.self)
}

func printPlain(_ allReadings: [DeviceReading]) {
    let readings = visibleReadings(allReadings)
    if readings.isEmpty {
        print("No 2.4 GHz devices connected.")
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

/// How many devices the menu bar shows at once. Menu bar space is scarce, so
/// this is capped; override with WIRELESS_BATTERY_MENUBAR_MAX.
let menuBarLimit: Int = {
    guard let raw = ProcessInfo.processInfo.environment["WIRELESS_BATTERY_MENUBAR_MAX"],
          let value = Int(raw), value > 0
    else { return 3 }
    return value
}()


/// The menu bar line, shared by the SwiftBar plugin and the menu bar app so the
/// two can't drift apart.
///
/// Up to `menuBarLimit` devices side by side. When more are connected than fit,
/// the lowest batteries win the slots, since those are the ones that need
/// attention — but they are then shown in the display's own order so the icons
/// don't reshuffle as levels drift.
func menuBarSelection(for readings: [DeviceReading]) -> [DeviceReading] {
    let byUrgency = readings.sorted { lhs, rhs in
        // A device with no level at all sorts last.
        (lhs.percent ?? Int.max) < (rhs.percent ?? Int.max)
    }
    let chosen = Set(byUrgency.prefix(menuBarLimit).map(\.key))
    return readings.filter { chosen.contains($0.key) }
}

/// The level text for one device, without its icon.
func menuBarLevel(for reading: DeviceReading) -> String {
    let level = reading.percent.map { "\($0)%" } ?? "—"
    let charge = reading.charging && reading.online ? "⚡︎" : ""
    // A trailing dot marks a level that's remembered rather than current.
    let staleMark = reading.stale ? "·" : ""
    return "\(level)\(charge)\(staleMark)"
}

func menuBarTitle(for readings: [DeviceReading]) -> String {
    let shown = menuBarSelection(for: readings)

    let segments = shown.map { reading -> String in
        return "\(icon(for: reading)) \(menuBarLevel(for: reading))"
    }
    return segments.joined(separator: "  ")
}

func printSwiftBar(_ allReadings: [DeviceReading]) {
    let readings = visibleReadings(allReadings)
    if readings.isEmpty {
        print("🔌")
        print("---")
        print("No 2.4 GHz devices connected | color=\(Palette.dim)")
        return
    }

    print(menuBarTitle(for: readings))

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
