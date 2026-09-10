// mac-24ghz-battery — part of https://github.com/usamarashid94/mac-24ghz-battery
// Copyright (C) 2026 usamarashid94. Licensed under GPL-3.0; see LICENSE.

import AppKit

/// Menu bar glyphs.
///
/// The app draws SF Symbols rather than the emoji the command line prints:
/// as template images they take the menu bar's own colour, follow the system
/// font weight, and sit on the text baseline — none of which emoji do. The CLI
/// keeps emoji because its output is plain text.
enum Symbols {
    static func name(for reading: DeviceReading) -> String {
        let lowercased = reading.name.lowercased()
        if lowercased.contains("arctis") || lowercased.contains("headset")
            || lowercased.contains("headphone") {
            return "headphones"
        }
        // Logitech reports marketing names like "G502 X", with no word for the
        // form factor, so a model-number pattern stands in for one.
        if lowercased.contains("mouse") || lowercased.contains("mx ")
            || lowercased.range(of: #"\bg\d{3}"#, options: .regularExpression) != nil {
            return "computermouse.fill"
        }
        if lowercased.contains("keyboard") || lowercased.contains("keychron")
            || lowercased.contains("keys") {
            return "keyboard.fill"
        }
        return "antenna.radiowaves.left.and.right"
    }

    /// A template image, so the menu bar tints it like every other item.
    static func image(for reading: DeviceReading, pointSize: CGFloat = 13) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        guard let image = NSImage(
            systemSymbolName: name(for: reading),
            accessibilityDescription: reading.name
        )?.withSymbolConfiguration(configuration) else {
            return nil
        }
        image.isTemplate = true
        return image
    }

    /// One "<glyph> 53%" run, with the glyph as an inline attachment.
    static func attributedSegment(
        for reading: DeviceReading,
        pointSize: CGFloat = 13,
        color: NSColor? = nil
    ) -> NSAttributedString {
        let line = NSMutableAttributedString()

        if let image = image(for: reading, pointSize: pointSize) {
            let attachment = NSTextAttachment()
            attachment.image = image
            // Nudge onto the text baseline: an attachment otherwise sits low.
            let glyph = NSMutableAttributedString(attachment: attachment)
            glyph.addAttribute(
                .baselineOffset,
                value: -1.0,
                range: NSRange(location: 0, length: glyph.length)
            )
            line.append(glyph)
            line.append(NSAttributedString(string: " "))
        } else {
            // No symbol on this OS version: fall back to the CLI's emoji.
            line.append(NSAttributedString(string: "\(icon(for: reading)) "))
        }

        var attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: pointSize, weight: .regular)
        ]
        if let color { attributes[.foregroundColor] = color }
        line.append(NSAttributedString(string: menuBarLevel(for: reading), attributes: attributes))
        return line
    }
}
