// mac-24ghz-battery — part of https://github.com/usamarashid94/mac-24ghz-battery
// Copyright (C) 2026 usamarashid94. Licensed under GPL-3.0; see LICENSE.

import Foundation

/// One known device. Adding hardware should be a data change, not a code change,
/// so drivers look their devices up here rather than carrying their own lists.
struct DeviceEntry: Codable {
    var vendorID: Int
    var productID: Int
    var name: String
    /// `BatteryDriver.id` of the driver that handles it.
    var driver: String
    /// Protocol dialect within that driver. Devices in one product family often
    /// share a request but not a reply layout.
    var variant: String?
    /// True only when someone has confirmed it against the physical device.
    /// Everything else is a careful reading of a datasheet or of another
    /// project's source, and may be wrong.
    var verified: Bool?

    var isVerified: Bool { verified ?? false }
}

enum DeviceTable {
    /// Devices compiled in. Product IDs and reply layouts for the SteelSeries
    /// entries follow HeadsetControl (GPL-3.0).
    ///
    /// Deliberately absent: Arctis Nova 3 (0x2269, 0x226d) and Nova 7P (0x220a,
    /// 0x22a7, 0x2298). HeadsetControl gives those their own device classes, so
    /// assuming they share a reply layout with the models below would be a
    /// guess, and a wrong offset reports a status byte as a battery level.
    static let builtin: [DeviceEntry] = [
        // Nova 5 family: percentage at byte 3, offline flag at byte 1.
        DeviceEntry(vendorID: 0x1038, productID: 0x2232, name: "SteelSeries Arctis Nova 5",
                    driver: "steelseries", variant: "nova5", verified: true),
        DeviceEntry(vendorID: 0x1038, productID: 0x2253, name: "SteelSeries Arctis Nova 5X",
                    driver: "steelseries", variant: "nova5", verified: false),

        // Nova 7 family, original firmware: discrete 0-4 level at byte 2.
        DeviceEntry(vendorID: 0x1038, productID: 0x2202, name: "SteelSeries Arctis Nova 7",
                    driver: "steelseries", variant: "nova7Discrete", verified: false),
        DeviceEntry(vendorID: 0x1038, productID: 0x2206, name: "SteelSeries Arctis Nova 7X",
                    driver: "steelseries", variant: "nova7Discrete", verified: false),
        DeviceEntry(vendorID: 0x1038, productID: 0x223A, name: "SteelSeries Arctis Nova 7 Diablo IV",
                    driver: "steelseries", variant: "nova7Discrete", verified: false),
        DeviceEntry(vendorID: 0x1038, productID: 0x227A, name: "SteelSeries Arctis Nova 7 WoW Edition",
                    driver: "steelseries", variant: "nova7Discrete", verified: false),
        DeviceEntry(vendorID: 0x1038, productID: 0x22A4, name: "SteelSeries Arctis Nova 7X",
                    driver: "steelseries", variant: "nova7Discrete", verified: false),

        // Nova 7 family, updated firmware: percentage at byte 2.
        DeviceEntry(vendorID: 0x1038, productID: 0x22A1, name: "SteelSeries Arctis Nova 7",
                    driver: "steelseries", variant: "nova7Percent", verified: false),
        DeviceEntry(vendorID: 0x1038, productID: 0x227E, name: "SteelSeries Arctis Nova 7 Gen 2",
                    driver: "steelseries", variant: "nova7Percent", verified: false),
        DeviceEntry(vendorID: 0x1038, productID: 0x2258, name: "SteelSeries Arctis Nova 7X v2",
                    driver: "steelseries", variant: "nova7Percent", verified: false),
        DeviceEntry(vendorID: 0x1038, productID: 0x229E, name: "SteelSeries Arctis Nova 7X v2",
                    driver: "steelseries", variant: "nova7Percent", verified: false),
        DeviceEntry(vendorID: 0x1038, productID: 0x22AD, name: "SteelSeries Arctis Nova 7X v2",
                    driver: "steelseries", variant: "nova7Percent", verified: false),
        DeviceEntry(vendorID: 0x1038, productID: 0x22A9, name: "SteelSeries Arctis Nova 7 Diablo IV",
                    driver: "steelseries", variant: "nova7Percent", verified: false),
        DeviceEntry(vendorID: 0x1038, productID: 0x22A5, name: "SteelSeries Arctis Nova 7X",
                    driver: "steelseries", variant: "nova7Percent", verified: false),

        // Arctis 7 / Pro: level at byte 2, no status byte.
        DeviceEntry(vendorID: 0x1038, productID: 0x1260, name: "SteelSeries Arctis 7",
                    driver: "steelseries", variant: "legacyArctis7", verified: false),
        DeviceEntry(vendorID: 0x1038, productID: 0x12AD, name: "SteelSeries Arctis 7 2019",
                    driver: "steelseries", variant: "legacyArctis7", verified: false),
        DeviceEntry(vendorID: 0x1038, productID: 0x1252, name: "SteelSeries Arctis Pro 2019",
                    driver: "steelseries", variant: "legacyArctis7", verified: false),
        DeviceEntry(vendorID: 0x1038, productID: 0x1280, name: "SteelSeries Arctis Pro GameDAC",
                    driver: "steelseries", variant: "legacyArctis7", verified: false),

        // Arctis 1 family: level at byte 3, status at byte 2.
        DeviceEntry(vendorID: 0x1038, productID: 0x12B3, name: "SteelSeries Arctis 1",
                    driver: "steelseries", variant: "arctis1", verified: false),
        DeviceEntry(vendorID: 0x1038, productID: 0x12B6, name: "SteelSeries Arctis 1 Xbox",
                    driver: "steelseries", variant: "arctis1", verified: false),
        DeviceEntry(vendorID: 0x1038, productID: 0x12D7, name: "SteelSeries Arctis 7X",
                    driver: "steelseries", variant: "arctis1", verified: false),

        // Arctis 9: raw level 0x64-0x9A rather than a percentage.
        DeviceEntry(vendorID: 0x1038, productID: 0x12C2, name: "SteelSeries Arctis 9",
                    driver: "steelseries", variant: "arctis9", verified: false),

        // Keychron wireless mice, via their own dongle.
        DeviceEntry(vendorID: 0x3434, productID: 0xD048, name: "Keychron M5",
                    driver: "keychron-mouse", variant: "status", verified: false),
        DeviceEntry(vendorID: 0x3434, productID: 0xD028, name: "Keychron mouse receiver",
                    driver: "keychron-mouse", variant: "status", verified: false),
        DeviceEntry(vendorID: 0x3434, productID: 0xD037, name: "Keychron M3",
                    driver: "keychron-mouse", variant: "status", verified: false),
    ]

    /// Where a user can drop entries to try a device without rebuilding. Handy
    /// for testing a new product ID before sending a pull request.
    static var overridePaths: [URL] {
        var paths: [URL] = []
        if let custom = ProcessInfo.processInfo.environment["WIRELESS_BATTERY_DEVICES"] {
            paths.append(URL(fileURLWithPath: custom))
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        paths.append(home.appendingPathComponent(".config/wireless-battery/devices.json"))
        return paths
    }

    static func loadOverrides() -> [DeviceEntry] {
        for url in overridePaths {
            guard let data = try? Data(contentsOf: url) else { continue }
            guard let entries = try? JSONDecoder().decode([DeviceEntry].self, from: data) else {
                debugLog("device table at \(url.path) could not be parsed, ignoring")
                continue
            }
            debugLog("loaded \(entries.count) device entries from \(url.path)")
            return entries
        }
        return []
    }

    /// Overrides win, so a user can correct a wrong built-in entry locally.
    static let entries: [DeviceEntry] = {
        var byKey: [Int: DeviceEntry] = [:]
        for entry in builtin + loadOverrides() {
            byKey[entry.vendorID << 16 | entry.productID] = entry
        }
        return Array(byKey.values)
    }()

    static func entry(vendorID: Int, productID: Int) -> DeviceEntry? {
        entries.first { $0.vendorID == vendorID && $0.productID == productID }
    }

    static func entries(forDriver driver: String) -> [DeviceEntry] {
        entries.filter { $0.driver == driver }
    }
}
