import AppKit

/// Shows an action's shortcut. Click it, press a key combination, and the binding is stored.
/// Esc cancels; Delete restores the factory default.
final class ShortcutRecorderButton: NSButton {
    private let playerAction: PlayerAction
    private let bindings = KeyBindings.shared
    private var changeObserver: NSObjectProtocol?
    private var isRecording = false {
        didSet { refreshTitle() }
    }

    init(playerAction: PlayerAction) {
        self.playerAction = playerAction
        super.init(frame: .zero)
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(beginRecording(_:))
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 160).isActive = true
        refreshTitle()
        changeObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshTitle() }
        }
    }

    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        if let changeObserver {
            NotificationCenter.default.removeObserver(changeObserver)
        }
    }

    override var acceptsFirstResponder: Bool { true }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        return super.resignFirstResponder()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording, window?.firstResponder === self else {
            return super.performKeyEquivalent(with: event)
        }
        handle(event)
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        handle(event)
    }

    @objc private func beginRecording(_ sender: Any?) {
        isRecording = true
        window?.makeFirstResponder(self)
    }

    private func handle(_ event: NSEvent) {
        switch event.keyCode {
        case 53:
            finishRecording()
        case 51, 117:
            bindings.reset(playerAction)
            finishRecording()
        default:
            let combo = KeyCombo(event: event)
            if combo.modifiers.contains(.command) {
                explain("Shortcuts with ⌘ are reserved for the menu bar. Choose a key without ⌘.")
                return
            }
            switch bindings.assign(combo, to: playerAction) {
            case .assigned:
                finishRecording()
            case .conflict(let owner):
                explain("\(combo.displayString) is already used by “\(owner.title)”. Change that shortcut first, or pick another key.")
            }
        }
    }

    private func finishRecording() {
        isRecording = false
        window?.makeFirstResponder(nil)
    }

    private func explain(_ message: String) {
        NSSound.beep()
        finishRecording()
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Shortcut not changed"
        alert.informativeText = message
        if let window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    private func refreshTitle() {
        title = isRecording ? "Type shortcut…" : bindings.combo(for: playerAction).displayString
    }
}
