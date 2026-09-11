// Renders candidate app icons.
//
// Drawn as real geometry rather than stock symbols composited together: one
// idea per mark, a single stroke weight throughout, and generous margins.
// Stacking a battery glyph, an antenna glyph and a label produces a collage,
// not an icon — the shapes have to be one thing.
//
// Run: swiftc -O -framework AppKit -o /tmp/mkicons tools/make-icons.swift
//      /tmp/mkicons build/icons

import AppKit
import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())
let outputDirectory = arguments.first ?? "build/icons"
/// When given a mark name, also writes a full .iconset for it.
let iconsetMark = arguments.count > 1 ? arguments[1] : nil

func color(_ hex: UInt32) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: 1
    )
}

struct Mark {
    let name: String
    let label: String
    let top: NSColor
    let bottom: NSColor
    /// Draws the white mark inside a unit square, given the stroke width to use.
    let draw: (_ side: CGFloat, _ stroke: CGFloat) -> Void
}

// MARK: - Drawing helpers

/// A rounded capsule outline: the battery body every mark is built from.
func batteryBody(_ rect: NSRect, stroke: CGFloat) -> NSBezierPath {
    let path = NSBezierPath(roundedRect: rect, xRadius: rect.height * 0.34, yRadius: rect.height * 0.34)
    path.lineWidth = stroke
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    return path
}

/// The terminal nub, drawn as a stubby rounded bar so it shares the body's radius.
func terminal(after rect: NSRect, stroke: CGFloat) -> NSBezierPath {
    let height = rect.height * 0.40
    let width = stroke * 1.05
    let nub = NSRect(
        x: rect.maxX + stroke * 0.75,
        y: rect.midY - height / 2,
        width: width,
        height: height
    )
    return NSBezierPath(roundedRect: nub, xRadius: width / 2, yRadius: width / 2)
}

/// One arc of a broadcast fan, centred on `origin`, opening to the right.
/// `spread` is in degrees either side of horizontal — AppKit's appendArc takes
/// degrees, and feeding it radians silently collapses the arc into a dot.
func arc(origin: NSPoint, radius: CGFloat, spread: CGFloat, stroke: CGFloat) -> NSBezierPath {
    let path = NSBezierPath()
    path.appendArc(withCenter: origin, radius: radius, startAngle: -spread, endAngle: spread)
    path.lineWidth = stroke
    path.lineCapStyle = .round
    return path
}

// MARK: - The marks

let marks: [Mark] = [
    // The signal fan IS the gauge: inner arcs solid, outer ones faded, so a
    // wireless mark doubles as a charge level without drawing a battery at all.
    Mark(
        name: "A-signal-gauge",
        label: "A. Signal as gauge",
        top: color(0x30D158), bottom: color(0x0F8A3C)
    ) { side, stroke in
        let centre = NSPoint(x: side * 0.30, y: side / 2)
        let dot = stroke * 1.15
        NSColor.white.setFill()
        NSBezierPath(ovalIn: NSRect(x: centre.x - dot, y: centre.y - dot,
                                    width: dot * 2, height: dot * 2)).fill()

        // Four bars of signal; the last is dim, the way a meter shows headroom.
        let levels: [CGFloat] = [1.0, 1.0, 1.0, 0.28]
        for (index, alpha) in levels.enumerated() {
            NSColor.white.withAlphaComponent(alpha).setStroke()
            let radius = side * (0.115 + CGFloat(index) * 0.088)
            arc(origin: centre, radius: radius, spread: 58, stroke: stroke).stroke()
        }
    },

    // The dongle: the one object that says 2.4 GHz rather than Bluetooth.
    // Its charge shows as a filled band, and it is mid-transmission.
    Mark(
        name: "B-dongle",
        label: "B. Dongle, transmitting",
        top: color(0x0A84FF), bottom: color(0x0A3FA8)
    ) { side, stroke in
        NSColor.white.setStroke()
        NSColor.white.setFill()

        let bodyWidth = side * 0.20
        let bodyHeight = side * 0.34

        // Centre the whole composition — tab, body and the outermost wave —
        // rather than the body alone, which would leave the mark sitting left.
        let tabReach = stroke * 1.15
        let waveReach = stroke * 0.1 + side * (0.085 + 2 * 0.078)
        let totalWidth = tabReach + bodyWidth + waveReach
        // Round caps make the arcs' ink narrower than their radius, so the
        // geometric centre lands slightly right of the optical one. Measured
        // against the rendered pixels, not guessed.
        let opticalCorrection = side * 0.013
        let bodyX = (side - totalWidth) / 2 + tabReach - opticalCorrection

        let body = NSRect(x: bodyX, y: (side - bodyHeight) / 2,
                          width: bodyWidth, height: bodyHeight)
        let shape = NSBezierPath(roundedRect: body, xRadius: bodyWidth * 0.34, yRadius: bodyWidth * 0.34)
        shape.lineWidth = stroke
        shape.stroke()

        // The USB contact tab, pointing left into the Mac.
        let tabWidth = stroke * 1.0
        let tabHeight = bodyHeight * 0.42
        let tab = NSRect(x: body.minX - stroke * 1.15, y: body.midY - tabHeight / 2,
                         width: tabWidth, height: tabHeight)
        NSBezierPath(roundedRect: tab, xRadius: tabWidth / 2, yRadius: tabWidth / 2).fill()

        // Charge inside the dongle.
        let fill = body.insetBy(dx: stroke * 1.45, dy: stroke * 1.45)
        let level = NSRect(x: fill.minX, y: fill.minY, width: fill.width, height: fill.height * 0.62)
        NSBezierPath(roundedRect: level, xRadius: fill.width * 0.30, yRadius: fill.width * 0.30).fill()

        let origin = NSPoint(x: body.maxX + stroke * 0.1, y: body.midY)
        for index in 0..<3 {
            let radius = side * (0.085 + CGFloat(index) * 0.078)
            arc(origin: origin, radius: radius, spread: 50, stroke: stroke).stroke()
        }
    },

    // A monitor's dial. The gauge sweep is the charge; the needle's tip
    // broadcasts, so measuring and receiving are the same gesture.
    Mark(
        name: "C-dial",
        label: "C. Gauge dial",
        top: color(0x5E5CE6), bottom: color(0x312E9E)
    ) { side, stroke in
        let centre = NSPoint(x: side / 2, y: side * 0.46)
        let radius = side * 0.23

        // Empty track, then the charged portion over it.
        NSColor.white.withAlphaComponent(0.30).setStroke()
        var track = NSBezierPath()
        track.appendArc(withCenter: centre, radius: radius, startAngle: 200, endAngle: -20, clockwise: true)
        track.lineWidth = stroke
        track.lineCapStyle = .round
        track.stroke()

        NSColor.white.setStroke()
        let charged = NSBezierPath()
        charged.appendArc(withCenter: centre, radius: radius, startAngle: 200, endAngle: 48, clockwise: true)
        charged.lineWidth = stroke
        charged.lineCapStyle = .round
        charged.stroke()

        // Broadcast from the top of the dial.
        let origin = NSPoint(x: centre.x, y: centre.y + radius * 0.12)
        for index in 0..<2 {
            let r = side * (0.055 + CGFloat(index) * 0.055)
            let fan = NSBezierPath()
            fan.appendArc(withCenter: origin, radius: r, startAngle: 40, endAngle: 140)
            fan.lineWidth = stroke
            fan.lineCapStyle = .round
            fan.stroke()
        }
        NSColor.white.setFill()
        let dot = stroke * 0.9
        NSBezierPath(ovalIn: NSRect(x: origin.x - dot, y: origin.y - dot,
                                    width: dot * 2, height: dot * 2)).fill()
    },

    // Several accessories reporting in: three cells at different levels,
    // which is what a monitor for more than one device actually shows.
    Mark(
        name: "D-three-levels",
        label: "D. Three accessories",
        top: color(0xFF9F0A), bottom: color(0xBF5A08)
    ) { side, stroke in
        NSColor.white.setStroke()
        NSColor.white.setFill()

        let width = side * 0.145
        let height = side * 0.40
        let gap = side * 0.075
        let totalWidth = width * 3 + gap * 2
        let levels: [CGFloat] = [0.75, 0.45, 0.92]

        for (index, level) in levels.enumerated() {
            let x = (side - totalWidth) / 2 + CGFloat(index) * (width + gap)
            let body = NSRect(x: x, y: (side - height) / 2 - side * 0.015,
                              width: width, height: height)
            let shape = NSBezierPath(roundedRect: body, xRadius: width * 0.36, yRadius: width * 0.36)
            shape.lineWidth = stroke * 0.82
            shape.stroke()

            let cap = NSRect(x: body.midX - width * 0.24, y: body.maxY + stroke * 0.35,
                             width: width * 0.48, height: stroke * 0.72)
            NSBezierPath(roundedRect: cap, xRadius: cap.height / 2, yRadius: cap.height / 2).fill()

            let fill = body.insetBy(dx: stroke * 1.25, dy: stroke * 1.25)
            let charge = NSRect(x: fill.minX, y: fill.minY,
                                width: fill.width, height: fill.height * level)
            NSBezierPath(roundedRect: charge, xRadius: fill.width * 0.32,
                         yRadius: fill.width * 0.32).fill()
        }
    },

    // A cell whose charge is drawn as signal arcs: the two ideas occupy the
    // same space instead of sitting beside each other.
    Mark(
        name: "E-wave-cell",
        label: "E. Waves inside cell",
        top: color(0x2C2C2E), bottom: color(0x0D0D0F)
    ) { side, stroke in
        NSColor.white.setStroke()
        NSColor.white.setFill()

        let bodyWidth = side * 0.58
        let bodyHeight = side * 0.355
        let body = NSRect(x: (side - bodyWidth) / 2 - stroke * 0.8,
                          y: (side - bodyHeight) / 2,
                          width: bodyWidth, height: bodyHeight)
        batteryBody(body, stroke: stroke).stroke()
        terminal(after: body, stroke: stroke).fill()

        let origin = NSPoint(x: body.minX + bodyWidth * 0.20, y: body.midY)
        let dot = stroke * 0.85
        NSBezierPath(ovalIn: NSRect(x: origin.x - dot, y: origin.y - dot,
                                    width: dot * 2, height: dot * 2)).fill()
        for index in 0..<3 {
            let radius = bodyWidth * (0.17 + CGFloat(index) * 0.145)
            arc(origin: origin, radius: radius, spread: 55, stroke: stroke * 0.88).stroke()
        }
    },
]

// MARK: - Canvas

func render(_ mark: Mark, side: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: side, height: side))
    image.lockFocus()

    let inset = side * 0.085
    let rect = NSRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
    let squircle = NSBezierPath(roundedRect: rect, xRadius: side * 0.225, yRadius: side * 0.225)

    NSGradient(starting: mark.top, ending: mark.bottom)?.draw(in: squircle, angle: -90)

    NSGraphicsContext.saveGraphicsState()
    squircle.addClip()
    NSGradient(starting: NSColor(white: 1, alpha: 0.16), ending: NSColor(white: 1, alpha: 0))?
        .draw(in: NSRect(x: rect.minX, y: rect.midY, width: rect.width, height: rect.height / 2), angle: -90)

    // One stroke weight for every mark, so nothing looks bolted on.
    mark.draw(side, side * 0.052)
    NSGraphicsContext.restoreGraphicsState()

    image.unlockFocus()
    return image
}

func writePNG(_ image: NSImage, to path: String) {
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else { return }
    try? png.write(to: URL(fileURLWithPath: path))
}

try? FileManager.default.createDirectory(atPath: outputDirectory, withIntermediateDirectories: true)

for mark in marks {
    writePNG(render(mark, side: 1024), to: "\(outputDirectory)/\(mark.name).png")
}

// Comparison sheet, each mark shown large and at menu bar size, because an icon
// that only works at 512px is not finished.
let cell: CGFloat = 320
let labelHeight: CGFloat = 52
let columns = 3
let rows = (marks.count + columns - 1) / columns
let sheetSize = NSSize(width: CGFloat(columns) * cell, height: CGFloat(rows) * (cell + labelHeight))

let sheet = NSImage(size: sheetSize)
sheet.lockFocus()
NSColor(white: 0.96, alpha: 1).setFill()
NSRect(origin: .zero, size: sheetSize).fill()

for (index, mark) in marks.enumerated() {
    let x = CGFloat(index % columns) * cell
    let y = sheetSize.height - CGFloat(index / columns + 1) * (cell + labelHeight)

    let big = render(mark, side: cell * 0.70)
    big.draw(at: NSPoint(x: x + cell * 0.09, y: y + labelHeight + 8),
             from: .zero, operation: .sourceOver, fraction: 1)

    // 32pt beside it: the size that decides whether a design actually works.
    let small = render(mark, side: 32)
    small.draw(at: NSPoint(x: x + cell * 0.80, y: y + labelHeight + 20),
               from: .zero, operation: .sourceOver, fraction: 1)
    let smaller = render(mark, side: 16)
    smaller.draw(at: NSPoint(x: x + cell * 0.83, y: y + labelHeight + 70),
                 from: .zero, operation: .sourceOver, fraction: 1)

    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 20, weight: .medium),
        .foregroundColor: NSColor.black,
    ]
    let text = mark.label as NSString
    text.draw(at: NSPoint(x: x + cell * 0.09, y: y + 14), withAttributes: attributes)
}
sheet.unlockFocus()
writePNG(sheet, to: "\(outputDirectory)/all-candidates.png")

// The chosen mark, exported at every size macOS asks for.
if let wanted = iconsetMark {
    guard let mark = marks.first(where: { $0.name == wanted }) else {
        FileHandle.standardError.write(Data("no mark named \(wanted)\n".utf8))
        exit(1)
    }

    let iconset = "\(outputDirectory)/AppIcon.iconset"
    try? FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)

    // Each entry is drawn at its true pixel size rather than scaled from one
    // master, so the stroke stays crisp at 16pt instead of turning to mush.
    let sizes: [(point: Int, scale: Int)] = [
        (16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2),
        (256, 1), (256, 2), (512, 1), (512, 2),
    ]
    for entry in sizes {
        let pixels = entry.point * entry.scale
        let suffix = entry.scale == 1 ? "" : "@2x"
        let name = "icon_\(entry.point)x\(entry.point)\(suffix).png"
        writePNG(render(mark, side: CGFloat(pixels)), to: "\(iconset)/\(name)")
    }
    print("wrote \(iconset) for \(wanted)")
}

print("wrote \(marks.count) marks and a sheet to \(outputDirectory)")
