// mac-24ghz-battery — part of https://github.com/usamarashid94/mac-24ghz-battery
// Copyright (C) 2026 usamarashid94. Licensed under GPL-3.0; see LICENSE.

import Foundation

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
