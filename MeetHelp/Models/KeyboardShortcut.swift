import AppKit
import Foundation

struct KeyboardShortcut: Equatable {
    let keyCode: UInt16
    let modifiers: NSEvent.ModifierFlags

    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection(.deviceIndependentFlagsMask)
    }

    init?(rawValue: String) {
        let parts = rawValue.split(separator: ":")
        guard parts.count == 2,
              let keyCode = UInt16(parts[0]),
              let rawModifiers = UInt(parts[1]) else {
            return nil
        }

        self.keyCode = keyCode
        self.modifiers = NSEvent.ModifierFlags(rawValue: rawModifiers).intersection(.deviceIndependentFlagsMask)
    }

    var rawValue: String {
        "\(keyCode):\(modifiers.rawValue)"
    }

    var displayText: String {
        let modifierText = [
            modifiers.contains(.control) ? "⌃" : "",
            modifiers.contains(.option) ? "⌥" : "",
            modifiers.contains(.shift) ? "⇧" : "",
            modifiers.contains(.command) ? "⌘" : ""
        ].joined()

        return modifierText + keyDisplayName
    }

    func matches(_ event: NSEvent) -> Bool {
        event.keyCode == keyCode &&
        event.modifierFlags.intersection(.deviceIndependentFlagsMask) == modifiers
    }

    private var keyDisplayName: String {
        KeyboardShortcut.keyNames[keyCode] ?? String(keyCode)
    }

    private static let keyNames: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
        8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
        16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
        23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
        30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "Return",
        37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",",
        44: "/", 45: "N", 46: "M", 47: ".", 48: "Tab", 49: "Space",
        50: "`", 51: "Delete", 53: "Esc", 65: ".", 67: "*", 69: "+",
        71: "Clear", 75: "/", 76: "Enter", 78: "-", 81: "=", 82: "0",
        83: "1", 84: "2", 85: "3", 86: "4", 87: "5", 88: "6", 89: "7",
        91: "8", 92: "9", 96: "F5", 97: "F6", 98: "F7", 99: "F3",
        100: "F8", 101: "F9", 103: "F11", 109: "F10", 111: "F12",
        115: "Home", 116: "Page Up", 117: "Forward Delete", 118: "F4",
        119: "End", 120: "F2", 121: "Page Down", 122: "F1", 123: "←",
        124: "→", 125: "↓", 126: "↑"
    ]
}

enum ShortcutAction: String, CaseIterable, Identifiable {
    case toggleOverlay
    case toggleListening
    case clearSession
    case toggleHistory
    case selectModel1
    case selectModel2
    case selectModel3
    case selectGemini

    var id: String { rawValue }

    var title: String {
        switch self {
        case .toggleOverlay:
            return "Hide / Show"
        case .toggleListening:
            return "Pause / Start Listening"
        case .clearSession:
            return "Delete Session"
        case .toggleHistory:
            return "Show / Hide History"
        case .selectModel1:
            return "Select OpenRouter Model 1"
        case .selectModel2:
            return "Select OpenRouter Model 2"
        case .selectModel3:
            return "Select OpenRouter Model 3"
        case .selectGemini:
            return "Select Gemini Backup"
        }
    }

    var defaultsKey: String {
        "shortcut.\(rawValue)"
    }

    var defaultShortcut: KeyboardShortcut {
        switch self {
        case .toggleOverlay:
            return KeyboardShortcut(keyCode: 4, modifiers: [.control, .option])
        case .toggleListening:
            return KeyboardShortcut(keyCode: 37, modifiers: [.control, .option])
        case .clearSession:
            return KeyboardShortcut(keyCode: 51, modifiers: [.control, .option])
        case .toggleHistory:
            return KeyboardShortcut(keyCode: 4, modifiers: [.control, .option, .shift])
        case .selectModel1:
            return KeyboardShortcut(keyCode: 18, modifiers: [.control, .option])
        case .selectModel2:
            return KeyboardShortcut(keyCode: 19, modifiers: [.control, .option])
        case .selectModel3:
            return KeyboardShortcut(keyCode: 20, modifiers: [.control, .option])
        case .selectGemini:
            return KeyboardShortcut(keyCode: 5, modifiers: [.control, .option])
        }
    }

    var shortcut: KeyboardShortcut {
        get {
            guard let rawValue = UserDefaults.standard.string(forKey: defaultsKey),
                  let shortcut = KeyboardShortcut(rawValue: rawValue) else {
                return defaultShortcut
            }
            return shortcut
        }
        nonmutating set {
            UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey)
        }
    }
}
