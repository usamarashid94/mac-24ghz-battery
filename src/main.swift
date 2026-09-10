// mac-24ghz-battery — battery for 2.4 GHz (USB dongle) wireless devices on macOS.
// Copyright (C) 2026 usamarashid94
//
// Licensed under the GNU General Public License v3.0. See LICENSE.
// The SteelSeries Nova wire format was derived from HeadsetControl (GPL-3.0)
// by Sapd: https://github.com/Sapd/HeadsetControl

import Foundation

// MARK: - Entry point

let arguments = Set(CommandLine.arguments.dropFirst())

if arguments.contains("--help") || arguments.contains("-h") {
    print("""
    wireless-battery — battery for 2.4 GHz dongle devices

    Usage: wireless-battery [--json | --swiftbar | --probe | --devices] [--all]

      --json       machine-readable output
      --swiftbar   SwiftBar plugin format
      --probe      read-only diagnostics for every USB HID device, to report
                   hardware that isn't supported yet
      --devices    list the devices this build knows about
      --all        also include Bluetooth devices that report battery
      --debug      dump HID traffic to stderr
      --help       this message
    """)
    exit(0)
}

debugEnabled = arguments.contains("--debug")

if arguments.contains("--probe") {
    Probe.run(includeAll: arguments.contains("--all"))
    exit(0)
}

if arguments.contains("--devices") {
    print("Drivers:")
    for driver in drivers {
        print("  \(driver.id.padding(toLength: 20, withPad: " ", startingAt: 0)) \(driver.displayName)")
    }
    print("\nKnown devices (✓ = confirmed against the physical device):")
    for entry in DeviceTable.entries.sorted(by: { $0.name < $1.name }) {
        let mark = entry.isVerified ? "✓" : " "
        print(String(
            format: "  %@ 0x%04X:0x%04X  %@",
            mark, entry.vendorID, entry.productID, entry.name
        ))
    }
    exit(0)
}

// Simulates a long-running host, such as a menu bar app, doing many refresh
// cycles in one process. Retained session state must stay bounded.
if let flagIndex = CommandLine.arguments.firstIndex(of: "--stress") {
    let cycles = CommandLine.arguments.dropFirst(flagIndex + 1).first.flatMap(Int.init) ?? 50
    print("running \(cycles) refresh cycles in one process…")
    for cycle in 1...cycles {
        // Each cycle in its own pool, mirroring how a dispatch block drains one
        // per refresh. Without it, CoreFoundation temporaries pile up until exit
        // and look like a leak.
        autoreleasepool {
            _ = collectReadings(includeBluetooth: false)
        }
        if cycle % 10 == 0 || cycle == cycles {
            print("  cycle \(cycle): retained session buffers = \(RetainedSessionState.shared.count)")
        }
    }
    print("done — retained count must stay at or below the cap, not grow with cycles")
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
