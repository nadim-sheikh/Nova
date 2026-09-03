import AppKit

extension KeyCombo {
    init(event: NSEvent) {
        self.init(
            keyCode: event.keyCode,
            modifiers: Modifiers(flags: event.modifierFlags),
            keyLabel: KeyCombo.label(for: event)
        )
    }

    private static func label(for event: NSEvent) -> String {
        if let standard = standardLabel(forKeyCode: event.keyCode) {
            return standard
        }
        let characters = event.charactersIgnoringModifiers ?? ""
        return characters.isEmpty ? "Key \(event.keyCode)" : characters.uppercased()
    }
}

extension KeyCombo.Modifiers {
    /// Keeps only the four real modifier keys; arrows and function keys carry extra flags AppKit adds.
    init(flags: NSEvent.ModifierFlags) {
        var modifiers: KeyCombo.Modifiers = []
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.command) { modifiers.insert(.command) }
        self = modifiers
    }
}
