// mac-24ghz-battery — part of https://github.com/usamarashid94/mac-24ghz-battery
// Copyright (C) 2026 usamarashid94. Licensed under GPL-3.0; see LICENSE.

import Foundation
import IOKit
import IOKit.hid

// MARK: - Collection

func collectReadings(includeBluetooth: Bool) -> [DeviceReading] {
    includeBluetoothDevices = includeBluetooth

    var readings: [DeviceReading] = []
    var seen = Set<String>()

    for device in allDevices() {
        // First driver to claim the device handles it, so vendor protocols get
        // first refusal and the generic reader acts as the backstop.
        guard let driver = drivers.first(where: { $0.matches(device) }) else { continue }

        for reading in driver.read(device) {
            // One physical device can front several HID collections.
            guard seen.insert(reading.key).inserted else { continue }
            readings.append(reading)
        }
    }

    let merged = mergeSameAccessory(applyCache(to: readings))
    return merged.sorted { $0.name < $1.name }
}

// MARK: - Same-accessory merge

/// Whether duplicate rows for the same accessory are merged into one.
/// Default on; set to "0" for the rare case of owning two identical devices,
/// where merging would (correctly, if regrettably) hide one of them.
let mergeDuplicateAccessories: Bool =
    ProcessInfo.processInfo.environment["WIRELESS_BATTERY_MERGE_DUPLICATES"] != "0"

/// Words that describe how a device is connected or who makes it, rather than
/// which physical unit it is. Stripping them is what lets "Logitech G502 X
/// LIGHTSPEED" (read over its wireless receiver) and "G502 X" (read from the
/// same mouse's own USB descriptor once it's plugged in to charge) match.
private let accessoryNameFillerWords: Set<String> = [
    "logitech", "steelseries", "keychron",
    "lightspeed", "wireless", "receiver", "dongle", "wired",
    "2", "4", "ghz", "g",
]

/// Reduces a display name to the tokens that actually identify the product,
/// so two names for the same physical accessory compare equal even when one
/// source dresses the name up and another gives it plain.
func normalizedAccessoryName(_ name: String) -> String {
    name
        .lowercased()
        .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        .map(String.init)
        .filter { !accessoryNameFillerWords.contains($0) }
        .joined(separator: " ")
}

/// Collapses readings that are the same physical accessory seen more than
/// once into a single row.
///
/// The same device can enumerate twice under genuinely different keys: a
/// mouse read over its wireless receiver has one product ID and, once
/// plugged in over USB to charge, its own wired interface is a *different*
/// USB device with a different product ID — sometimes picked up by a
/// different driver entirely, with a plainer name that doesn't even say
/// "Logitech". Key-based dedup in `collectReadings` cannot catch that, because
/// the keys are, correctly, different things. This is a display-layer repair:
/// two rows whose *names* normalize to the same product are always a
/// duplicate worth collapsing, never two useful pieces of information.
///
/// The one real cost, made an explicit trade-off rather than a silent bug:
/// owning two identical accessories of the same model means only one shows.
/// `WIRELESS_BATTERY_MERGE_DUPLICATES=0` restores the old, unmerged behaviour.
func mergeSameAccessory(
    _ readings: [DeviceReading],
    forceMerge: Bool? = nil
) -> [DeviceReading] {
    guard forceMerge ?? mergeDuplicateAccessories else { return readings }

    var order: [String] = []
    var bestByNormalizedName: [String: DeviceReading] = [:]

    for reading in readings {
        let normalized = normalizedAccessoryName(reading.name)
        guard let existing = bestByNormalizedName[normalized] else {
            order.append(normalized)
            bestByNormalizedName[normalized] = reading
            continue
        }
        if isMoreCurrent(reading, than: existing) {
            bestByNormalizedName[normalized] = reading
        }
    }

    return order.compactMap { bestByNormalizedName[$0] }
}

/// Picks the more informative of two readings for the same accessory.
///
/// Charging outranks percent-having outranks merely-online: the scenario this
/// exists for is exactly "the device is now charging over its wired
/// interface", and that is the more relevant status to show, not whichever
/// reading happens to carry a higher or lower number.
private func isMoreCurrent(_ candidate: DeviceReading, than incumbent: DeviceReading) -> Bool {
    if candidate.online != incumbent.online { return candidate.online }
    if candidate.charging != incumbent.charging { return candidate.charging }
    if (candidate.percent != nil) != (incumbent.percent != nil) { return candidate.percent != nil }
    let candidateSeen = candidate.lastSeen ?? .distantPast
    let incumbentSeen = incumbent.lastSeen ?? .distantPast
    return candidateSeen > incumbentSeen
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
