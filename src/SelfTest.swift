// mac-24ghz-battery — part of https://github.com/usamarashid94/mac-24ghz-battery
// Copyright (C) 2026 usamarashid94. Licensed under GPL-3.0; see LICENSE.

import Foundation

/// Deterministic tests for everything that can be checked without hardware.
///
/// Most supported devices cannot be tested here, because nobody has all of them.
/// What *can* be tested is the part that actually goes wrong: reply parsing. A
/// wrong offset or a missing range check does not fail loudly on real hardware —
/// it reports a status byte as a battery percentage. So each protocol variant is
/// exercised against crafted frames with known answers, including frames that
/// must be rejected.
enum SelfTest {
    nonisolated(unsafe) static var failures: [String] = []
    nonisolated(unsafe) static var checks = 0

    static func check(_ condition: Bool, _ label: String) {
        checks += 1
        if !condition { failures.append(label) }
    }

    static func equal<T: Equatable>(_ actual: T, _ expected: T, _ label: String) {
        checks += 1
        if actual != expected {
            failures.append("\(label): expected \(expected), got \(actual)")
        }
    }

    /// Builds a reply buffer of `length` with specific bytes set.
    static func frame(_ length: Int, _ bytes: [Int: UInt8]) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: length)
        for (index, value) in bytes where index < length { data[index] = value }
        return data
    }

    // MARK: - SteelSeries reply parsing

    static func testSteelSeries() {
        // Nova 5: percentage at byte 3, offline flag at byte 1, charging at 4.
        if case let .online(percent, charging) =
            SteelSeries.parse(frame(16, [1: 0x00, 3: 70, 4: 0]), as: .nova5) {
            equal(percent, 70, "nova5 percent")
            equal(charging, false, "nova5 not charging")
        } else {
            failures.append("nova5 should have parsed as online")
        }

        if case .offline = SteelSeries.parse(frame(16, [1: 0x02]), as: .nova5) {} else {
            failures.append("nova5 byte1 == 0x02 should be offline")
        }

        if case let .online(_, charging) =
            SteelSeries.parse(frame(16, [1: 0x00, 3: 50, 4: 0x01]), as: .nova5) {
            equal(charging, true, "nova5 charging flag")
        } else {
            failures.append("nova5 charging frame should parse")
        }

        // A level above 100 means the layout is wrong and must be rejected.
        if case .unreadable = SteelSeries.parse(frame(16, [1: 0x00, 3: 200]), as: .nova5) {} else {
            failures.append("nova5 must reject an out-of-range level")
        }

        // Too-short frames must never be indexed into.
        if case .unreadable = SteelSeries.parse(frame(4, [:]), as: .nova5) {} else {
            failures.append("nova5 must reject a short frame")
        }

        // Nova 7 original firmware: a 0-4 step at byte 2, status at byte 3.
        if case let .online(percent, _) =
            SteelSeries.parse(frame(8, [2: 2, 3: 0x03]), as: .nova7Discrete) {
            equal(percent, 50, "nova7 discrete step 2 -> 50%")
        } else {
            failures.append("nova7Discrete should parse")
        }
        if case let .online(percent, _) =
            SteelSeries.parse(frame(8, [2: 4, 3: 0x03]), as: .nova7Discrete) {
            equal(percent, 100, "nova7 discrete step 4 -> 100%")
        } else {
            failures.append("nova7Discrete full should parse")
        }
        if case .offline = SteelSeries.parse(frame(8, [3: 0x00]), as: .nova7Discrete) {} else {
            failures.append("nova7 byte3 == 0 should be offline")
        }
        if case let .online(percent, charging) =
            SteelSeries.parse(frame(8, [2: 85, 3: 0x01]), as: .nova7Percent) {
            equal(percent, 85, "nova7 percent")
            equal(charging, true, "nova7 charging")
        } else {
            failures.append("nova7Percent should parse")
        }

        // The families must not be interchangeable: a Nova 7 frame read as a
        // Nova 5 must not yield a plausible-looking level. This is the exact
        // mistake that shipped once.
        let nova7Frame = frame(16, [2: 85, 3: 0x01])
        if case let .online(percent, _) = SteelSeries.parse(nova7Frame, as: .nova5) {
            check(percent != 85, "nova5 parser must not read a nova7 frame as 85%")
        }

        // Arctis 7 / Pro: level at byte 2, no status byte.
        if case let .online(percent, _) =
            SteelSeries.parse(frame(8, [2: 55]), as: .legacyArctis7) {
            equal(percent, 55, "legacyArctis7 percent")
        } else {
            failures.append("legacyArctis7 should parse")
        }

        // Arctis 1: status at byte 2, level at byte 3.
        if case .offline = SteelSeries.parse(frame(8, [2: 0x01]), as: .arctis1) {} else {
            failures.append("arctis1 byte2 == 0x01 should be offline")
        }
        if case let .online(percent, _) =
            SteelSeries.parse(frame(8, [2: 0x00, 3: 42]), as: .arctis1) {
            equal(percent, 42, "arctis1 percent")
        } else {
            failures.append("arctis1 should parse")
        }

        // Arctis 9: raw 0x64...0x9A maps onto 0-100.
        if case let .online(percent, _) =
            SteelSeries.parse(frame(8, [3: 0x9A]), as: .arctis9) {
            equal(percent, 100, "arctis9 full")
        } else {
            failures.append("arctis9 full should parse")
        }
        if case let .online(percent, _) =
            SteelSeries.parse(frame(8, [3: 0x64]), as: .arctis9) {
            equal(percent, 0, "arctis9 empty")
        } else {
            failures.append("arctis9 empty should parse")
        }
        if case let .online(percent, _) =
            SteelSeries.parse(frame(8, [3: 0x7F]), as: .arctis9) {
            check((45...55).contains(percent), "arctis9 midpoint ~50, got \(percent)")
        } else {
            failures.append("arctis9 midpoint should parse")
        }
        // Outside the documented raw range: reject rather than invent a level.
        if case .unreadable = SteelSeries.parse(frame(8, [3: 0x20]), as: .arctis9) {} else {
            failures.append("arctis9 must reject a raw value below its range")
        }
    }

    // MARK: - Logitech voltage curve

    static func testLogitechVoltage() {
        equal(Logitech.percentage(forMillivolts: 4186), 100, "voltage curve top")
        equal(Logitech.percentage(forMillivolts: 4300), 100, "voltage above top clamps")
        equal(Logitech.percentage(forMillivolts: 3500), 0, "voltage curve bottom")
        equal(Logitech.percentage(forMillivolts: 3000), 0, "voltage below bottom clamps")
        equal(Logitech.percentage(forMillivolts: 3811), 50, "voltage curve midpoint")
        equal(Logitech.percentage(forMillivolts: 3671), 10, "voltage curve 10%")

        // Interpolation between 3778 (40%) and 3811 (50%).
        let interpolated = Logitech.percentage(forMillivolts: 3800)
        check((44...49).contains(interpolated), "voltage interpolation ~47, got \(interpolated)")

        // Monotonic: more volts must never mean less battery.
        var previous = -1
        for millivolts in stride(from: 3400, through: 4300, by: 25) {
            let percent = Logitech.percentage(forMillivolts: millivolts)
            check(percent >= previous, "voltage curve must be monotonic at \(millivolts) mV")
            previous = percent
        }
    }

    // MARK: - HID++ error handling

    static func testLogitechErrors() {
        // HID++ 1.0 error, code 0x08 = unknown device = empty pairing slot.
        let emptySlot: [UInt8] = [0x10, 0x02, 0x8F, 0x00, 0x08, 0x08, 0x00]
        check(Logitech.isError(emptySlot), "0x8F must be recognized as an error")
        check(Logitech.isUnknownDevice(emptySlot), "error code 0x08 must mean empty slot")

        // HID++ 2.0 error.
        let error20: [UInt8] = [0x10, 0x01, 0xFF, 0x06, 0x18, 0x01, 0x00]
        check(Logitech.isError(error20), "0xFF must be recognized as an error")
        check(!Logitech.isUnknownDevice(error20), "a 2.0 error is not an empty slot")

        // A normal reply is not an error.
        let ok: [UInt8] = [0x10, 0x01, 0x06, 0x18, 0x64, 0x00, 0x00]
        check(!Logitech.isError(ok), "a normal reply must not read as an error")
    }

    // MARK: - Display and formatting

    static func testDisplay() {
        equal(shortAge(30), "30s", "age seconds")
        equal(shortAge(90), "1m", "age minutes")
        equal(shortAge(3700), "1h", "age hours")
        equal(shortAge(90000), "1d", "age days")

        func reading(_ name: String, _ percent: Int?, online: Bool) -> DeviceReading {
            DeviceReading(key: name, name: name, percent: percent, charging: false,
                          online: online, transport: "2.4GHz", source: "test", note: "off")
        }

        let mixed = [
            reading("A", 80, online: true),
            reading("B", nil, online: false),
            reading("C", 20, online: true),
        ]
        equal(visibleReadings(mixed).count, 2, "a device never seen answering is hidden")

        // These devices flap: a mouse sleeps in seconds, a base station misses
        // a poll. Hiding on the first miss makes the menu bar flicker, and can
        // empty it entirely, which reads as the app having died.
        func lapsed(_ name: String, secondsAgo: TimeInterval) -> DeviceReading {
            var r = reading(name, 55, online: false)
            r.stale = true
            r.lastSeen = Date().addingTimeInterval(-secondsAgo)
            return r
        }

        let now = Date()
        equal(visibleReadings([lapsed("recent", secondsAgo: 5)], now: now).count, 1,
              "a device that just missed a poll keeps its place")
        equal(visibleReadings([lapsed("borderline", secondsAgo: offlineGraceSeconds - 5)], now: now).count, 1,
              "a device inside the grace window stays visible")
        equal(visibleReadings([lapsed("gone", secondsAgo: offlineGraceSeconds + 60)], now: now).count, 0,
              "a device gone longer than the grace window drops out")

        // The menu bar keeps the lowest levels when more devices than fit.
        let many = [
            reading("A", 90, online: true), reading("B", 10, online: true),
            reading("C", 50, online: true), reading("D", 30, online: true),
        ]
        let title = menuBarTitle(for: many)
        check(title.contains("10%"), "menu bar must keep the lowest level")
        check(!title.contains("90%"), "menu bar must drop the highest when over the cap")

        // The nil-percent JSON crash: must produce valid JSON, not trap.
        let json = jsonString(for: [reading("B", nil, online: false)])
        check(json.contains("null"), "a device with no level serializes as null")
        let parsed = try? JSONSerialization.jsonObject(
            with: Data(json.utf8), options: []
        ) as? [String: Any]
        check(parsed != nil, "JSON output must parse")
    }

    // MARK: - Single instance

    static func testInstancePolicy() {
        let now = Date()
        func inst(_ pid: Int32, _ offset: TimeInterval?) -> InstancePolicy.Instance {
            .init(pid: pid, launched: offset.map { now.addingTimeInterval($0) })
        }

        // Nothing else running: just take the menu bar.
        equal(InstancePolicy.decide(me: inst(10, 0), others: []),
              .proceed(terminating: []), "a lone instance proceeds")

        // Newest wins, so a freshly opened copy replaces the running one.
        equal(InstancePolicy.decide(me: inst(20, 0), others: [inst(10, -60)]),
              .proceed(terminating: [10]), "a newer instance replaces an older one")

        // ...and an older one defers rather than fighting back.
        equal(InstancePolicy.decide(me: inst(10, -60), others: [inst(20, 0)]),
              .standDown, "an older instance stands down for a newer one")

        // The race that matters: two started at the same instant. Exactly one
        // must yield, or they kill each other and the menu bar ends up empty.
        let a = inst(100, 0), b = inst(200, 0)
        let aDecision = InstancePolicy.decide(me: a, others: [b])
        let bDecision = InstancePolicy.decide(me: b, others: [a])
        let survivors = [aDecision, bDecision].filter { $0 != .standDown }.count
        equal(survivors, 1, "a simultaneous launch leaves exactly one survivor")

        // Several older copies are all replaced at once.
        equal(InstancePolicy.decide(me: inst(50, 0), others: [inst(10, -90), inst(20, -30)]),
              .proceed(terminating: [10, 20]), "all older copies are replaced")

        // An unknown launch date must never beat a known one.
        equal(InstancePolicy.decide(me: inst(30, 0), others: [inst(40, nil)]),
              .proceed(terminating: [40]), "an instance with no launch date counts as oldest")
        equal(InstancePolicy.decide(me: inst(40, nil), others: [inst(30, 0)]),
              .standDown, "an instance with no launch date yields to a dated one")
    }

    // MARK: - Safety guards

    static func testGuards() {
        // The input-page exclusion is the promise that keystrokes are never read.
        for page in [0x01, 0x07, 0x0C] {
            check(HIDSession.isForbiddenPage(page), "page 0x\(String(page, radix: 16)) must be refused")
        }
        for page in [0xFF00, 0xFFC0, 0x8C] {
            check(!HIDSession.isForbiddenPage(page), "vendor page 0x\(String(page, radix: 16)) must be allowed")
        }
    }

    // MARK: - Device table

    static func testDeviceTable() {
        check(!DeviceTable.entries.isEmpty, "device table must not be empty")

        // Every entry must name a driver that exists and a variant that driver
        // understands; a typo here silently disables a device.
        let driverIDs = Set(drivers.map(\.id))
        for entry in DeviceTable.entries {
            check(driverIDs.contains(entry.driver),
                  "\(entry.name): unknown driver \"\(entry.driver)\"")
            if entry.driver == "steelseries" {
                check(SteelSeries.Variant(rawValue: entry.variant ?? "") != nil,
                      "\(entry.name): unknown steelseries variant \"\(entry.variant ?? "nil")\"")
            }
        }

        // Duplicate product IDs would make behaviour depend on table order.
        var seen = Set<Int>()
        for entry in DeviceTable.entries {
            let key = entry.vendorID << 16 | entry.productID
            check(seen.insert(key).inserted,
                  String(format: "duplicate entry for 0x%04X:0x%04X", entry.vendorID, entry.productID))
        }
    }

    // MARK: - Runner

    static func run() -> Int32 {
        failures = []
        checks = 0

        testSteelSeries()
        testLogitechVoltage()
        testLogitechErrors()
        testDisplay()
        testInstancePolicy()
        testGuards()
        testDeviceTable()

        if failures.isEmpty {
            print("selftest: \(checks) checks passed")
            return 0
        }
        print("selftest: \(failures.count) of \(checks) checks FAILED")
        for failure in failures { print("  ✗ \(failure)") }
        return 1
    }
}
