import Foundation

/// A physical key plus modifiers. `keyLabel` is only for display; matching uses key code and modifiers.
struct KeyCombo: Codable, Hashable {
    struct Modifiers: OptionSet, Codable, Hashable {
        let rawValue: UInt8

        static let shift = Modifiers(rawValue: 1 << 0)
        static let control = Modifiers(rawValue: 1 << 1)
        static let option = Modifiers(rawValue: 1 << 2)
        static let command = Modifiers(rawValue: 1 << 3)
    }

    var keyCode: UInt16
    var modifiers: Modifiers
    var keyLabel: String

    init(keyCode: UInt16, modifiers: Modifiers = [], keyLabel: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyLabel = keyLabel
    }

    func matches(_ other: KeyCombo) -> Bool {
        keyCode == other.keyCode && modifiers == other.modifiers
    }

    /// Menu-style rendering such as "⇧→" or "⌥Space".
    var displayString: String {
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        return text + keyLabel
    }

    /// Labels for keys that don't produce a printable character.
    static func standardLabel(forKeyCode keyCode: UInt16) -> String? {
        switch keyCode {
        case 49: return "Space"
        case 36: return "↩"
        case 76: return "⌤"
        case 48: return "⇥"
        case 51: return "⌫"
        case 117: return "⌦"
        case 53: return "⎋"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        case 115: return "↖"
        case 119: return "↘"
        case 116: return "⇞"
        case 121: return "⇟"
        case 122: return "F1"
        case 120: return "F2"
        case 99: return "F3"
        case 118: return "F4"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 100: return "F8"
        case 101: return "F9"
        case 109: return "F10"
        case 103: return "F11"
        case 111: return "F12"
        default: return nil
        }
    }
}
