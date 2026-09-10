// mac-24ghz-battery — part of https://github.com/usamarashid94/mac-24ghz-battery
// Copyright (C) 2026 usamarashid94. Licensed under GPL-3.0; see LICENSE.

import AppKit
import ServiceManagement

/// Menu bar app around the same drivers the CLI uses.
///
/// Reads happen on a serial background queue, never the main thread: an
/// unreachable device costs a 1.5 s timeout, and doing that on the main thread
/// would freeze the menu bar for the duration.
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private var timer: Timer?

    /// Serial on purpose: the retained-session state and the HID run loop calls
    /// expect one reader at a time.
    private let readerQueue = DispatchQueue(label: "dev.wireless-battery.reader", qos: .utility)

    private var readings: [DeviceReading] = []
    private var lastUpdate: Date?
    private var isReading = false

    private let logEnabled = ProcessInfo.processInfo.environment["WIRELESS_BATTERY_APP_LOG"] == "1"

    private var refreshInterval: TimeInterval {
        let stored = UserDefaults.standard.double(forKey: "refreshInterval")
        return stored > 0 ? stored : 30
    }

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "…"
        menu.delegate = self
        statusItem.menu = menu

        rebuildMenu()
        refresh()

        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        // Keep firing while a menu is open rather than stalling in event tracking.
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
    }

    /// A menu about to open is the moment freshness matters most.
    func menuWillOpen(_ menu: NSMenu) {
        refresh()
    }

    // MARK: - Reading

    @objc func refresh() {
        // Skip rather than queue up: a slow read shouldn't build a backlog.
        guard !isReading else { return }
        isReading = true

        readerQueue.async { [weak self] in
            // Drain CoreFoundation temporaries per refresh; without a pool they
            // accumulate for the life of the process and read as a slow leak.
            let readings = autoreleasepool { collectReadings(includeBluetooth: false) }
            DispatchQueue.main.async {
                guard let self else { return }
                self.isReading = false
                // Only what is actually connected right now; a device that has
                // gone away drops out and returns on its own when it answers.
                self.readings = visibleReadings(readings)
                self.lastUpdate = Date()
                self.updateStatusItem()
                self.rebuildMenu()
                self.log()
            }
        }
    }

    private func log() {
        guard logEnabled else { return }
        let title = statusItem.button?.attributedTitle.string ?? ""
        FileHandle.standardError.write(
            Data("[app] title: \(title)  (glyphs drawn as SF Symbols)\n".utf8)
        )
        for reading in readings {
            FileHandle.standardError.write(
                Data("[app] row: \(icon(for: reading)) \(reading.name) — \(statusText(for: reading))\n".utf8)
            )
        }
    }

    // MARK: - Display

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        guard !readings.isEmpty else {
            // A lone glyph is easy to mistake for the app having quit, so the
            // empty state carries text too.
            button.image = nil
            let empty = NSMutableAttributedString()
            if let plug = NSImage(
                systemSymbolName: "powerplug",
                accessibilityDescription: "No devices connected"
            ) {
                plug.isTemplate = true
                let attachment = NSTextAttachment()
                attachment.image = plug
                let glyph = NSMutableAttributedString(attachment: attachment)
                glyph.addAttribute(
                    .baselineOffset, value: -1.0,
                    range: NSRange(location: 0, length: glyph.length)
                )
                empty.append(glyph)
            }
            empty.append(NSAttributedString(
                string: " —",
                attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)]
            ))
            button.attributedTitle = empty
            return
        }

        // Drawn as an attributed string rather than an image plus title,
        // because several devices share one status item.
        button.image = nil
        let line = NSMutableAttributedString()
        for (index, reading) in menuBarSelection(for: readings).enumerated() {
            if index > 0 { line.append(NSAttributedString(string: "  ")) }
            line.append(Symbols.attributedSegment(for: reading))
        }
        button.attributedTitle = line
    }

    private func color(for reading: DeviceReading) -> NSColor {
        guard reading.online, let percent = reading.percent else {
            return .secondaryLabelColor
        }
        if percent <= 20 { return NSColor(named: "bad") ?? .systemRed }
        if percent <= 40 { return NSColor(named: "warn") ?? .systemOrange }
        return NSColor(named: "ok") ?? .systemGreen
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        if readings.isEmpty {
            let item = NSMenuItem(title: "No 2.4 GHz devices connected", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }

        for reading in readings {
            let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            item.isEnabled = false

            let line = NSMutableAttributedString()
            if let image = Symbols.image(for: reading, pointSize: 13) {
                let attachment = NSTextAttachment()
                attachment.image = image
                let glyph = NSMutableAttributedString(attachment: attachment)
                glyph.addAttribute(
                    .baselineOffset,
                    value: -1.0,
                    range: NSRange(location: 0, length: glyph.length)
                )
                line.append(glyph)
                line.append(NSAttributedString(string: "  "))
            }
            line.append(NSAttributedString(
                string: "\(reading.name)   ",
                attributes: [
                    .font: NSFont.menuFont(ofSize: 13),
                    .foregroundColor: NSColor.labelColor,
                ]
            ))
            line.append(NSAttributedString(
                string: statusText(for: reading),
                attributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium),
                    .foregroundColor: color(for: reading),
                ]
            ))
            item.attributedTitle = line
            menu.addItem(item)
        }

        menu.addItem(.separator())

        if let lastUpdate {
            let formatter = DateFormatter()
            formatter.timeStyle = .medium
            let item = NSMenuItem(
                title: "Updated \(formatter.string(from: lastUpdate))",
                action: nil,
                keyEquivalent: ""
            )
            item.isEnabled = false
            menu.addItem(item)
        }

        let refreshItem = NSMenuItem(title: "Refresh Now", action: #selector(refresh), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        let loginItem = NSMenuItem(
            title: "Open at Login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        loginItem.target = self
        loginItem.state = launchAtLoginEnabled ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)
    }

    // MARK: - Login item

    private var launchAtLoginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if launchAtLoginEnabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            // Registering needs the app to live somewhere stable and be signed;
            // an ad-hoc build run from a build directory can legitimately fail.
            let alert = NSAlert()
            alert.messageText = "Could not change the login item"
            alert.informativeText = """
                \(error.localizedDescription)

                This usually means the app needs to be in /Applications and \
                signed. Moving it there and reopening should fix it.
                """
            alert.runModal()
        }
        rebuildMenu()
    }
}
