import AppKit

/// The timecode readout inside the timeline: shows the current SMPTE timecode, and becomes a
/// text field when clicked so a timecode can be typed and jumped to with Return. Escape puts
/// the live value back. Text can be selected and copied like any field.
final class TimecodeField: NSTextField, NSTextFieldDelegate {
    /// Called with the typed text when the user presses Return.
    var onCommit: ((String) -> Void)?

    private var liveValue = ""

    init() {
        super.init(frame: .zero)
        font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        textColor = .white
        backgroundColor = NSColor.black.withAlphaComponent(0.35)
        drawsBackground = true
        isBezeled = false
        isBordered = false
        isEditable = true
        isSelectable = true
        focusRingType = .none
        usesSingleLineMode = true
        lineBreakMode = .byClipping
        alignment = .center
        toolTip = "Click to type a timecode, then press Return to jump to it"
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
    func show(_ timecode: String) {
        liveValue = timecode
        guard !isEditing else { return }
        stringValue = timecode
    }

    /// Hands the typed text on and ends editing.
    func commit() {
        let typed = stringValue
        endEditing()
        onCommit?(typed)
    }

    func cancel() {
        stringValue = liveValue
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
        var size = super.intrinsicContentSize
        size.width = max(size.width, 108) + 16
        size.height = 24
        return size
    }

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
