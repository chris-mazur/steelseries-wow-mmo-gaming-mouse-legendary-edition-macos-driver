// SteelSeries WoW MMO Mouse (Maelstrom Edition) - macOS driver
//
// Listens on the mouse's vendor-defined HID interface (usage page 0xFF00),
// which carries the 6 extra buttons that standard HID tools (Mac Mouse Fix,
// etc.) can't see because they only understand the standard Button usage
// page. On press/release, looks up the button's action in a JSON config
// file and either synthesizes a keystroke or runs a shell command.
//
// Config file: ~/Library/Application Support/SteelSeriesWowMouseDriver/config.json
// Re-read on every button press, so edits take effect immediately.

import Foundation
import IOKit.hid
import Carbon.HIToolbox

setvbuf(stdout, nil, _IONBF, 0)

let vendorID = 0x1038
let productID = 0x1310
let vendorUsagePage = 0xFF00
let vendorUsage = 1

// MARK: - Button bit table (reverse-engineered against the physical device)

enum Interface: Equatable {
    case vendor    // usage page 0xFF00 usage 1 - buttons invisible to standard HID tools
    case standard  // usage page 0x1 usage 2 - ordinary mouse interface
}

struct ButtonBit {
    let name: String
    let interface: Interface
    let byteIndex: Int
    let bitIndex: Int
}

let buttons: [ButtonBit] = [
    // Vendor-only buttons (not visible to Mac Mouse Fix / standard HID tools)
    ButtonBit(name: "thumbDown", interface: .vendor, byteIndex: 0, bitIndex: 2),
    ButtonBit(name: "thumbUp", interface: .vendor, byteIndex: 0, bitIndex: 3),
    ButtonBit(name: "pinky", interface: .vendor, byteIndex: 0, bitIndex: 4),
    ButtonBit(name: "leftOfWheel", interface: .vendor, byteIndex: 0, bitIndex: 6),
    ButtonBit(name: "rightOfWheel", interface: .vendor, byteIndex: 0, bitIndex: 7),
    ButtonBit(name: "behindWheel", interface: .vendor, byteIndex: 1, bitIndex: 0),
    // Standard-interface extras - macOS sees these as generic buttons already,
    // but most apps don't bind them to anything, so they're configurable here too.
    ButtonBit(name: "wheelClick", interface: .standard, byteIndex: 0, bitIndex: 2),
    ButtonBit(name: "thumbBackward", interface: .standard, byteIndex: 0, bitIndex: 3),
    ButtonBit(name: "thumbForward", interface: .standard, byteIndex: 0, bitIndex: 4),
]

// MARK: - Config

struct ButtonAction: Codable {
    var key: String?       // e.g. "1", "f13", "cmd+c"
    var shell: String?     // shell command, run via /bin/zsh -c
}

typealias Config = [String: ButtonAction]

let appSupportDir = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/SteelSeriesWowMouseDriver")
let configURL = appSupportDir.appendingPathComponent("config.json")

let defaultConfig: Config = [
    "thumbDown": ButtonAction(key: "1", shell: nil),
    "thumbUp": ButtonAction(key: "2", shell: nil),
    "pinky": ButtonAction(key: "3", shell: nil),
    "leftOfWheel": ButtonAction(key: "4", shell: nil),
    "rightOfWheel": ButtonAction(key: "5", shell: nil),
    "behindWheel": ButtonAction(key: "6", shell: nil),
    // No action by default - these already exist as ordinary mouse buttons in
    // macOS (usually inert unless an app binds them). Set a "key" or "shell"
    // here to remap them too.
    "wheelClick": ButtonAction(key: nil, shell: nil),
    "thumbBackward": ButtonAction(key: nil, shell: nil),
    "thumbForward": ButtonAction(key: nil, shell: nil),
]

func ensureConfigExists() {
    let fm = FileManager.default
    if !fm.fileExists(atPath: appSupportDir.path) {
        try? fm.createDirectory(at: appSupportDir, withIntermediateDirectories: true)
    }
    if !fm.fileExists(atPath: configURL.path) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(defaultConfig) {
            try? data.write(to: configURL)
            print("Wrote default config to \(configURL.path)")
        }
    }
}

func loadConfig() -> Config {
    guard let data = try? Data(contentsOf: configURL),
          let config = try? JSONDecoder().decode(Config.self, from: data) else {
        return defaultConfig
    }
    return config
}

// MARK: - Key name -> CGKeyCode

let keyCodeTable: [String: CGKeyCode] = [
    "a": CGKeyCode(kVK_ANSI_A), "b": CGKeyCode(kVK_ANSI_B), "c": CGKeyCode(kVK_ANSI_C),
    "d": CGKeyCode(kVK_ANSI_D), "e": CGKeyCode(kVK_ANSI_E), "f": CGKeyCode(kVK_ANSI_F),
    "g": CGKeyCode(kVK_ANSI_G), "h": CGKeyCode(kVK_ANSI_H), "i": CGKeyCode(kVK_ANSI_I),
    "j": CGKeyCode(kVK_ANSI_J), "k": CGKeyCode(kVK_ANSI_K), "l": CGKeyCode(kVK_ANSI_L),
    "m": CGKeyCode(kVK_ANSI_M), "n": CGKeyCode(kVK_ANSI_N), "o": CGKeyCode(kVK_ANSI_O),
    "p": CGKeyCode(kVK_ANSI_P), "q": CGKeyCode(kVK_ANSI_Q), "r": CGKeyCode(kVK_ANSI_R),
    "s": CGKeyCode(kVK_ANSI_S), "t": CGKeyCode(kVK_ANSI_T), "u": CGKeyCode(kVK_ANSI_U),
    "v": CGKeyCode(kVK_ANSI_V), "w": CGKeyCode(kVK_ANSI_W), "x": CGKeyCode(kVK_ANSI_X),
    "y": CGKeyCode(kVK_ANSI_Y), "z": CGKeyCode(kVK_ANSI_Z),
    "0": CGKeyCode(kVK_ANSI_0), "1": CGKeyCode(kVK_ANSI_1), "2": CGKeyCode(kVK_ANSI_2),
    "3": CGKeyCode(kVK_ANSI_3), "4": CGKeyCode(kVK_ANSI_4), "5": CGKeyCode(kVK_ANSI_5),
    "6": CGKeyCode(kVK_ANSI_6), "7": CGKeyCode(kVK_ANSI_7), "8": CGKeyCode(kVK_ANSI_8),
    "9": CGKeyCode(kVK_ANSI_9),
    "f1": CGKeyCode(kVK_F1), "f2": CGKeyCode(kVK_F2), "f3": CGKeyCode(kVK_F3),
    "f4": CGKeyCode(kVK_F4), "f5": CGKeyCode(kVK_F5), "f6": CGKeyCode(kVK_F6),
    "f7": CGKeyCode(kVK_F7), "f8": CGKeyCode(kVK_F8), "f9": CGKeyCode(kVK_F9),
    "f10": CGKeyCode(kVK_F10), "f11": CGKeyCode(kVK_F11), "f12": CGKeyCode(kVK_F12),
    "f13": CGKeyCode(kVK_F13), "f14": CGKeyCode(kVK_F14), "f15": CGKeyCode(kVK_F15),
    "f16": CGKeyCode(kVK_F16), "f17": CGKeyCode(kVK_F17), "f18": CGKeyCode(kVK_F18),
    "f19": CGKeyCode(kVK_F19),
    "space": CGKeyCode(kVK_Space), "tab": CGKeyCode(kVK_Tab), "escape": CGKeyCode(kVK_Escape),
    "return": CGKeyCode(kVK_Return), "delete": CGKeyCode(kVK_Delete),
    "up": CGKeyCode(kVK_UpArrow), "down": CGKeyCode(kVK_DownArrow),
    "left": CGKeyCode(kVK_LeftArrow), "right": CGKeyCode(kVK_RightArrow),
    "minus": CGKeyCode(kVK_ANSI_Minus), "equal": CGKeyCode(kVK_ANSI_Equal),
    "grave": CGKeyCode(kVK_ANSI_Grave),
]

func parseKeySpec(_ spec: String) -> (CGKeyCode, CGEventFlags)? {
    let parts = spec.lowercased().split(separator: "+").map(String.init)
    guard let keyName = parts.last, let code = keyCodeTable[keyName] else {
        print("Unknown key name: \(spec)")
        return nil
    }
    var flags: CGEventFlags = []
    for modifier in parts.dropLast() {
        switch modifier {
        case "cmd", "command": flags.insert(.maskCommand)
        case "shift": flags.insert(.maskShift)
        case "opt", "option", "alt": flags.insert(.maskAlternate)
        case "ctrl", "control": flags.insert(.maskControl)
        default: print("Unknown modifier: \(modifier)")
        }
    }
    return (code, flags)
}

func performAction(_ action: ButtonAction, pressed: Bool) {
    if let keySpec = action.key {
        guard let (code, flags) = parseKeySpec(keySpec) else { return }
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: pressed) else { return }
        event.flags = flags
        event.post(tap: .cghidEventTap)
    } else if let shell = action.shell, pressed {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        task.arguments = ["-c", shell]
        try? task.run()
    }
}

// MARK: - HID handling

final class DeviceContext {
    let interface: Interface
    var buffer: [UInt8]
    var lastReport: [UInt8]?
    init(interface: Interface, bufferSize: Int) {
        self.interface = interface
        self.buffer = [UInt8](repeating: 0, count: max(bufferSize, 16))
    }
}

var contexts: [DeviceContext] = []

func bit(_ report: [UInt8], _ button: ButtonBit) -> Bool {
    guard button.byteIndex < report.count else { return false }
    return (report[button.byteIndex] & (1 << button.bitIndex)) != 0
}

let reportCallback: IOHIDReportCallback = { context, result, sender, type, reportID, report, reportLength in
    guard let context = context else { return }
    let ctx = Unmanaged<DeviceContext>.fromOpaque(context).takeUnretainedValue()
    let bytes = Array(UnsafeBufferPointer(start: report, count: reportLength))

    let old = ctx.lastReport
    ctx.lastReport = bytes

    let config = loadConfig()
    for button in buttons where button.interface == ctx.interface {
        let wasPressed = old.map { bit($0, button) } ?? false
        let isPressed = bit(bytes, button)
        if wasPressed != isPressed {
            guard let action = config[button.name] else { continue }
            performAction(action, pressed: isPressed)
            print("\(button.name) \(isPressed ? "down" : "up")")
        }
    }
}

let deviceAddedCallback: IOHIDDeviceCallback = { context, result, sender, device in
    let maxInputReportSize = IOHIDDeviceGetProperty(device, kIOHIDMaxInputReportSizeKey as CFString) as? Int ?? 16
    let usagePage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? Int ?? -1
    let interface: Interface = (usagePage == vendorUsagePage) ? .vendor : .standard
    let ctx = DeviceContext(interface: interface, bufferSize: maxInputReportSize)
    contexts.append(ctx)
    let unmanaged = Unmanaged.passUnretained(ctx).toOpaque()
    ctx.buffer.withUnsafeMutableBufferPointer { buf in
        IOHIDDeviceRegisterInputReportCallback(device, buf.baseAddress!, buf.count, reportCallback, unmanaged)
    }
    let openResult = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
    if openResult != kIOReturnSuccess {
        print("Failed to open device: \(openResult)")
    } else {
        print("Opened \(interface == .vendor ? "vendor" : "standard") HID interface, watching for button presses.")
    }
}

ensureConfigExists()
print("Config: \(configURL.path)")

let vendorMatchDict: [String: Any] = [
    kIOHIDVendorIDKey: vendorID,
    kIOHIDProductIDKey: productID,
    kIOHIDDeviceUsagePageKey: vendorUsagePage,
    kIOHIDDeviceUsageKey: vendorUsage,
]
let standardMatchDict: [String: Any] = [
    kIOHIDVendorIDKey: vendorID,
    kIOHIDProductIDKey: productID,
    kIOHIDDeviceUsagePageKey: 0x1,
    kIOHIDDeviceUsageKey: 0x2,
]

let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
IOHIDManagerSetDeviceMatchingMultiple(manager, [vendorMatchDict, standardMatchDict] as CFArray)
IOHIDManagerRegisterDeviceMatchingCallback(manager, deviceAddedCallback, nil)
IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
if openResult != kIOReturnSuccess {
    print("Failed to open HID manager: \(openResult)")
    exit(1)
}

CFRunLoopRun()
