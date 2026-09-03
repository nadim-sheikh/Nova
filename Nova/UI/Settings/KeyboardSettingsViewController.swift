import AppKit

final class KeyboardSettingsViewController: NSViewController {
    override func loadView() {
        var rows: [(label: String, control: NSView)] = PlayerAction.allCases.map { action in
            (label: action.title, control: ShortcutRecorderButton(playerAction: action))
        }
        rows.append((label: "", control: SettingsForm.note(
            "Click a shortcut and press the new keys. Esc cancels and Delete restores the default. "
            + "Shortcuts with ⌘ belong to the menu bar (Open ⌘O, Copy Frame ⌘C / ⇧⌘C, Settings ⌘,)."
        )))
        let reset = NSButton(title: "Reset Shortcuts", target: self, action: #selector(resetShortcuts(_:)))
        view = SettingsForm.page(rows: rows, footer: reset)
    }

    @objc private func resetShortcuts(_ sender: Any?) {
        KeyBindings.shared.resetAll()
    }
}
