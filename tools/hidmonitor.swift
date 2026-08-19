// hidmonitor.swift
//
// Diagnostic tool: opens the SteelSeries WoW MMO / Maelstrom mouse's HID
// interfaces and dumps raw input reports as they arrive, with a diff against
// the previous report on the same interface so button presses/releases are
// easy to spot. Mouse-move-only reports are suppressed by default.
//
// Usage: swift hidmonitor.swift [usagePage] [usage]
//   With no args, matches ALL interfaces on the device (vendor ID 0x1038 /
//   product ID 0x1310).
//   Pass usagePage/usage (decimal or 0x-hex) to match only one interface,
//   e.g.: ./hidmonitor 0xFF00 1
//
// Press Ctrl-C to stop.

import Foundation
import IOKit.hid

setvbuf(stdout, nil, _IONBF, 0)

let vendorID = 0x1038
let productID = 0x1310

var matchDict: [String: Any] = [
    kIOHIDVendorIDKey: vendorID,
    kIOHIDProductIDKey: productID,
]

func parseArgInt(_ s: String) -> Int? {
    if s.lowercased().hasPrefix("0x") {
        return Int(s.dropFirst(2), radix: 16)
    }
    return Int(s)
}

let args = CommandLine.arguments
if args.count >= 3, let up = parseArgInt(args[1]), let u = parseArgInt(args[2]) {
    matchDict[kIOHIDDeviceUsagePageKey] = up
    matchDict[kIOHIDDeviceUsageKey] = u
    print("Matching usagePage=\(up) (0x\(String(up, radix: 16))) usage=\(u)")
} else {
    print("Matching all interfaces on VID 0x\(String(vendorID, radix: 16)) PID 0x\(String(productID, radix: 16))")
}

func hex(_ bytes: [UInt8]) -> String {
    bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
}

func diffDescription(old: [UInt8]?, new: [UInt8]) -> String {
    guard let old = old, old.count == new.count else { return "" }
    var parts: [String] = []
    for i in 0..<new.count {
        if old[i] != new[i] {
            let changed = old[i] ^ new[i]
            var bits: [Int] = []
            for b in 0..<8 {
                if (changed & (1 << b)) != 0 { bits.append(b) }
            }
            parts.append("byte[\(i)] \(String(format: "0x%02X", old[i]))->\(String(format: "0x%02X", new[i])) bit\(bits.count == 1 ? "" : "s")\(bits)")
        }
    }
    return parts.isEmpty ? "" : "  DIFF: " + parts.joined(separator: ", ")
}

final class DeviceContext {
    let device: IOHIDDevice
    let usagePage: Int
    let usage: Int
    var buffer: [UInt8]
    var lastReport: [UInt8]?

    init(device: IOHIDDevice, usagePage: Int, usage: Int, bufferSize: Int) {
        self.device = device
        self.usagePage = usagePage
        self.usage = usage
        self.buffer = [UInt8](repeating: 0, count: max(bufferSize, 16))
    }
}

var contexts: [DeviceContext] = []

let reportCallback: IOHIDReportCallback = { context, result, sender, type, reportID, report, reportLength in
    guard let context = context else { return }
    let ctx = Unmanaged<DeviceContext>.fromOpaque(context).takeUnretainedValue()
    let bytes = Array(UnsafeBufferPointer(start: report, count: reportLength))

    let diff = diffDescription(old: ctx.lastReport, new: bytes)
    ctx.lastReport = bytes

    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss.SSS"
    print("[\(formatter.string(from: Date()))] up=0x\(String(ctx.usagePage, radix: 16)) u=\(ctx.usage) reportID=\(reportID) len=\(reportLength) raw=[\(hex(bytes))]\(diff)")
}

let deviceAddedCallback: IOHIDDeviceCallback = { context, result, sender, device in
    let usagePage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? Int ?? -1
    let usage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsageKey as CFString) as? Int ?? -1
    let maxInputReportSize = IOHIDDeviceGetProperty(device, kIOHIDMaxInputReportSizeKey as CFString) as? Int ?? 16

    print("Device matched: usagePage=0x\(String(usagePage, radix: 16)) usage=\(usage) maxInputReportSize=\(maxInputReportSize)")

    let ctx = DeviceContext(device: device, usagePage: usagePage, usage: usage, bufferSize: maxInputReportSize)
    contexts.append(ctx)

    let unmanaged = Unmanaged.passUnretained(ctx).toOpaque()
    ctx.buffer.withUnsafeMutableBufferPointer { buf in
        IOHIDDeviceRegisterInputReportCallback(device, buf.baseAddress!, buf.count, reportCallback, unmanaged)
    }

    let openResult = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
    if openResult != kIOReturnSuccess {
        print("  Failed to open device: \(openResult)")
    }
}

let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
IOHIDManagerSetDeviceMatching(manager, matchDict as CFDictionary)
IOHIDManagerRegisterDeviceMatchingCallback(manager, deviceAddedCallback, nil)
IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
if openResult != kIOReturnSuccess {
    print("Failed to open HID manager: \(openResult)")
    exit(1)
}

print("Listening for HID reports. Press mouse buttons now. Ctrl-C to quit.\n")
CFRunLoopRun()
