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
