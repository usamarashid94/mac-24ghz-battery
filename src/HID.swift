// mac-24ghz-battery — part of https://github.com/usamarashid94/mac-24ghz-battery
// Copyright (C) 2026 usamarashid94. Licensed under GPL-3.0; see LICENSE.

import Foundation
import IOKit
import IOKit.hid

// MARK: - HID helpers

func property(_ device: IOHIDDevice, _ key: String) -> Any? {
    IOHIDDeviceGetProperty(device, key as CFString)
}

func intProperty(_ device: IOHIDDevice, _ key: String) -> Int? {
    property(device, key) as? Int
}

func stringProperty(_ device: IOHIDDevice, _ key: String) -> String? {
    property(device, key) as? String
}

func allDevices() -> [IOHIDDevice] {
    let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    IOHIDManagerSetDeviceMatching(manager, nil)
    guard let set = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return [] }
    return Array(set)
}

// MARK: - Input report plumbing

var debugEnabled = false

func debugLog(_ message: @autoclosure () -> String) {
    guard debugEnabled else { return }
    FileHandle.standardError.write(Data(("[debug] " + message() + "\n").utf8))
}

func hex(_ bytes: [UInt8]) -> String {
    bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
}

/// Collects input reports delivered on the run loop while we wait for a reply.
/// A device can emit unrelated reports mid-exchange, so the caller supplies a
/// predicate that recognizes the reply it asked for.
final class ReportSink {
    var report: [UInt8]?
    var accept: ([UInt8]) -> Bool

    init() {
        self.accept = { _ in false }
    }

    func expect(_ accept: @escaping ([UInt8]) -> Bool) {
        self.report = nil
        self.accept = accept
    }
}

/// An active device is chatty: a mouse in use streams input reports on the same
/// vendor interface we're querying. Those can land while a session is being torn
/// down, so a session's callback context and buffer outlive the session itself.
///
/// They are not kept forever. Holding them for the life of the process is fine
/// for a 70 ms CLI, but a menu bar app refreshing every 30 seconds would retain
/// thousands of them a day — a real leak. Instead the last `capacity` are kept
/// and older ones released: by the time that many sessions have come and gone,
/// any in-flight report for the oldest is long delivered.
final class RetainedSessionState {
    private struct Entry {
        let sink: ReportSink
        let buffer: UnsafeMutablePointer<UInt8>
        let size: Int
    }

    static let shared = RetainedSessionState()

    private let capacity = 32
    private var entries: [Entry] = []
    private let lock = NSLock()

    func retain(sink: ReportSink, buffer: UnsafeMutablePointer<UInt8>, size: Int) {
        lock.lock()
        defer { lock.unlock() }

        entries.append(Entry(sink: sink, buffer: buffer, size: size))
        while entries.count > capacity {
            let oldest = entries.removeFirst()
            oldest.buffer.deinitialize(count: oldest.size)
            oldest.buffer.deallocate()
        }
    }

    /// Number currently held. Used by tests to prove the cap holds.
    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return entries.count
    }
}

private let inputReportCallback: IOHIDReportCallback = { context, _, _, _, reportID, report, reportLength in
    guard let context, reportLength > 0 else { return }
    let sink = Unmanaged<ReportSink>.fromOpaque(context).takeUnretainedValue()
    guard sink.report == nil else { return }

    var bytes = Array(UnsafeBufferPointer(start: report, count: reportLength))
    // IOKit may hand back the payload with or without the leading report ID.
    // Normalize to "report ID included" so parsers can use fixed offsets.
    let id = UInt8(truncatingIfNeeded: reportID)
    if id != 0 && bytes.first != id {
        bytes.insert(id, at: 0)
    }

    debugLog("input report id=0x\(String(format: "%02x", id)) len=\(bytes.count): \(hex(bytes))")

    guard sink.accept(bytes) else { return }
    sink.report = bytes
    CFRunLoopStop(CFRunLoopGetCurrent())
}

/// One open device, held for as many request/reply round trips as the caller
/// needs. Opening per request meant tearing the callback down repeatedly while
/// the device was still sending, which crashed intermittently.
final class HIDSession {
    private let device: IOHIDDevice
    private let buffer: UnsafeMutablePointer<UInt8>
    private let bufferSize: Int
    private let sink: ReportSink

    init?(device: IOHIDDevice, bufferSize: Int) {
        guard IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            debugLog("open failed")
            return nil
        }

        self.device = device
        self.bufferSize = bufferSize
        self.buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        self.buffer.initialize(repeating: 0, count: bufferSize)
        self.sink = ReportSink()

        RetainedSessionState.shared.retain(sink: sink, buffer: buffer, size: bufferSize)

        let context = Unmanaged.passUnretained(sink).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(device, buffer, bufferSize, inputReportCallback, context)
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
    }

    /// Writes `request` and waits for the first reply the predicate accepts.
    func exchange(
        reportID: UInt8,
        request: [UInt8],
        timeout: CFTimeInterval,
        accept: @escaping ([UInt8]) -> Bool
    ) -> [UInt8]? {
        sink.expect(accept)

        debugLog("write report id=0x\(String(format: "%02x", reportID)): \(hex(request))")

        // A numbered report carries its ID as the first payload byte; report 0 does not.
        let sent = IOHIDDeviceSetReport(
            device,
            kIOHIDReportTypeOutput,
            CFIndex(reportID),
            request,
            request.count
        )
        guard sent == kIOReturnSuccess else {
            debugLog("SetReport failed: 0x\(String(format: "%08x", sent))")
            return nil
        }

        let deadline = CFAbsoluteTimeGetCurrent() + timeout
        while sink.report == nil && CFAbsoluteTimeGetCurrent() < deadline {
            CFRunLoopRunInMode(.defaultMode, 0.02, true)
        }
        return sink.report
    }

    /// Detaches from the run loop. The buffer and sink stay alive on purpose.
    func close() {
        IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDDeviceRegisterInputReportCallback(device, buffer, bufferSize, nil, nil)
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
    }
}
