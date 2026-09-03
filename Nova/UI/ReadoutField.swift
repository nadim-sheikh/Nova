import AppKit

/// A readout in the timeline that can be typed into: it shows a live value, and clicking it starts
/// an edit that Return commits and Escape cancels. Text can be selected and copied like any field.
final class ReadoutField: NSTextField, NSTextFieldDelegate {
    /// Called with the typed text when the user presses Return.
    var onCommit: ((String) -> Void)?

    private var liveValue = ""
    private let minimumWidth: CGFloat

    init(minimumWidth: CGFloat, description: String) {
        self.minimumWidth = minimumWidth
        super.init(frame: .zero)
        // A centring cell, so the text sits in the middle of the pill instead of against its top.
        cell = CenteredTextFieldCell(textCell: "")
        font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        textColor = .white
        backgroundColor = NSColor.white.withAlphaComponent(0.14)
        drawsBackground = true
        isBezeled = false
        isBordered = false
        isEditable = true
        isSelectable = true
        focusRingType = .none
        usesSingleLineMode = true
        lineBreakMode = .byClipping
        alignment = .center
        toolTip = description
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.masksToBounds = true
        delegate = self
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    required init?(coder: NSCoder) {
        nil
    }

    var isEditing: Bool { currentEditor() != nil }

    /// Updates the readout unless the user is typing in it.
    func show(_ value: String) {
        liveValue = value
        guard !isEditing else { return }
        stringValue = value
    }

    /// Hands the typed text on and ends editing.
    func commit() {
        let typed = stringValue
        endEditing()
        onCommit?(typed)
    }

    func cancel() {
        endEditing()
    }

    private func endEditing() {
        window?.makeFirstResponder(nil)
        stringValue = liveValue
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted {
            currentEditor()?.selectAll(nil)
        }
        return accepted
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: max(super.intrinsicContentSize.width + 16, minimumWidth), height: ReadoutField.height)
    }

    static let height: CGFloat = 22

    // MARK: - NSTextFieldDelegate

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            commit()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            cancel()
            return true
        default:
            return false
        }
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        // Clicking elsewhere abandons the edit rather than jumping somewhere unexpected.
        stringValue = liveValue
    }
}
