// mac-24ghz-battery — part of https://github.com/usamarashid94/mac-24ghz-battery
// Copyright (C) 2026 usamarashid94. Licensed under GPL-3.0; see LICENSE.

import Foundation
import IOKit
import IOKit.hid

/// Diagnostics for a device nobody has written a driver for yet.
///
/// Strictly read-only: it reads IOKit properties and the report descriptor and
/// sends the device nothing at all. Writing speculative vendor commands to
/// unknown hardware can rewrite settings or drop a keyboard into its bootloader,
/// so identifying a device and talking to it are kept firmly apart.
enum Probe {
    /// The two standard ways a device can declare battery in its report
    /// descriptor. Worth checking first: a device using either needs no driver.
    static func batteryUsages(in descriptor: [UInt8]) -> [String] {
        var found: Set<String> = []
        var index = 0
        while index + 1 < descriptor.count {
            // 0x05 = Usage Page (1 byte). 0x85 = Battery System page.
            if descriptor[index] == 0x05 && descriptor[index + 1] == 0x85 {
                found.insert("Battery System (page 0x85)")
            }
            // Generic Device Controls page, then Usage 0x20 = Battery Strength.
            if descriptor[index] == 0x05 && descriptor[index + 1] == 0x06 {
                var scan = index + 2
                while scan + 1 < descriptor.count && scan < index + 24 {
                    if descriptor[scan] == 0x09 && descriptor[scan + 1] == 0x20 {
                        found.insert("Battery Strength (page 0x06, usage 0x20)")
                    }
                    scan += 2
                }
            }
            index += 1
        }
        return found.sorted()
    }

    static func run(includeAll: Bool) {
        let devices = allDevices()
        print("wireless-battery probe")
        print("Paste this into an issue at:")
        print("https://github.com/usamarashid94/mac-24ghz-battery/issues\n")

        var shown = 0
        for device in devices.sorted(by: {
            (stringProperty($0, kIOHIDProductKey) ?? "") < (stringProperty($1, kIOHIDProductKey) ?? "")
        }) {
            let vendorID = intProperty(device, kIOHIDVendorIDKey) ?? 0
            let productID = intProperty(device, kIOHIDProductIDKey) ?? 0
            let transport = stringProperty(device, kIOHIDTransportKey) ?? "?"

            // Built-in trackpads and the like are noise here.
            let isUSB = transport.caseInsensitiveCompare("USB") == .orderedSame
            let claimed = drivers.first(where: { $0.matches(device) })
            if !includeAll && !isUSB { continue }

            shown += 1
            let name = stringProperty(device, kIOHIDProductKey) ?? "(unnamed)"
            let manufacturer = stringProperty(device, kIOHIDManufacturerKey) ?? "?"

            print("── \(name)")
            print("   manufacturer : \(manufacturer)")
            print(String(
                format: "   vid/pid      : 0x%04X / 0x%04X",
                vendorID, productID
            ))
            print("   transport    : \(transport)")
            print(String(
                format: "   usage        : page 0x%02X usage 0x%02X",
                intProperty(device, kIOHIDPrimaryUsagePageKey) ?? 0,
                intProperty(device, kIOHIDPrimaryUsageKey) ?? 0
            ))
            print("   reports      : in \(intProperty(device, kIOHIDMaxInputReportSizeKey) ?? 0)"
                + ", out \(intProperty(device, kIOHIDMaxOutputReportSizeKey) ?? 0)"
                + ", feature \(intProperty(device, kIOHIDMaxFeatureReportSizeKey) ?? 0)")

            if let known = DeviceTable.entry(vendorID: vendorID, productID: productID) {
                let state = known.isVerified ? "verified" : "implemented, unverified"
                print("   known as     : \(known.name) [\(known.driver), \(state)]")
            }

            if let claimed {
                print("   driver       : \(claimed.displayName)")
            } else {
                print("   driver       : none — this is what a new driver would handle")
            }

            if property(device, "BatteryPercent") != nil {
                print("   BatteryPercent: published to macOS (no driver needed)")
            }

            if let data = property(device, kIOHIDReportDescriptorKey) as? Data {
                let bytes = [UInt8](data)
                let usages = batteryUsages(in: bytes)
                print("   descriptor   : \(bytes.count) bytes")
                if usages.isEmpty {
                    print("   battery usage: none declared")
                } else {
                    print("   battery usage: \(usages.joined(separator: ", "))")
                }
                print("   descriptor hex:")
                for chunk in stride(from: 0, to: bytes.count, by: 16) {
                    let slice = Array(bytes[chunk..<min(chunk + 16, bytes.count)])
                    print("     \(hex(slice))")
                }
            } else {
                print("   descriptor   : unavailable")
            }
            print("")
        }

        if shown == 0 {
            print("No USB HID devices found. Pass --all to include every transport.")
        }
    }
}
