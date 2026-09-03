import AppKit

/// A full-width precision scrubber that slides over the bottom of the video when expanded, so the
/// playhead can be placed accurately. Its header is one aligned row: an editable timecode with
/// copy and paste buttons, an editable frame number, the clip's end, and the size toggle.
/// Comes in two sizes: compact (readouts and track) and full (adds tick labels and a taller track).
final class TimelineOverlayView: NSVisualEffectView {
    static let compactHeight: CGFloat = 64
    static let fullHeight: CGFloat = 112

    var onScrub: ((Int) -> Void)? {
        get { track.onScrub }
        set { track.onScrub = newValue }
    }
    var onCopyTimecode: (() -> Void)?
    var onPasteTimecode: (() -> Void)?
    var onEnterTimecode: ((String) -> Void)?
    var onEnterFrame: ((String) -> Void)?
    var onToggleSize: (() -> Void)?

    var isScrubbing: Bool { track.isScrubbing }
    var isEditingReadout: Bool { timecodeField.isEditing || frameField.isEditing }

    /// Full shows tick labels on a taller track; compact keeps just the essentials.
    var isFull = true {
        didSet {
            guard isFull != oldValue else { return }
            applySize()
        }
    }

    private let track = TimelineTrackView()
    private let timecodeField = ReadoutField(minimumWidth: 108, description: "Type a timecode and press Return to jump to it")
    private let frameField = ReadoutField(minimumWidth: 62, description: "Type a frame number and press Return to jump to it")
    private let frameLabel = NSTextField(labelWithString: "Frame")
    private let endLabel = NSTextField(labelWithString: "")
    private let copyButton = NSButton()
    private let pasteButton = NSButton()
    private let sizeButton = NSButton()
    private var heightConstraint: NSLayoutConstraint?

    init() {
        super.init(frame: .zero)
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        isHidden = true
        alphaValue = 0

        timecodeField.onCommit = { [weak self] text in self?.onEnterTimecode?(text) }
        frameField.onCommit = { [weak self] text in self?.onEnterFrame?(text) }
        configure(copyButton, symbol: "doc.on.doc", description: "Copy Timecode", action: #selector(copyTapped(_:)))
        configure(pasteButton, symbol: "doc.on.clipboard", description: "Paste Timecode", action: #selector(pasteTapped(_:)))
        configure(sizeButton, symbol: "rectangle.compress.vertical", description: "Compact Timeline", action: #selector(sizeTapped(_:)))
        for label in [frameLabel, endLabel] {
            label.font = .systemFont(ofSize: 11, weight: .medium)
            label.textColor = NSColor.white.withAlphaComponent(0.6)
            label.setContentCompressionResistancePriority(.required, for: .horizontal)
            label.setContentHuggingPriority(.required, for: .horizontal)
        }
        endLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)

        // A spacer with no hugging pushes everything after it to the right edge.
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        // One centre-aligned row, so the fields, icons and labels share a middle line exactly.
        let header = NSStackView(views: [
            timecodeField, copyButton, pasteButton, frameLabel, frameField, spacer, endLabel, sizeButton,
        ])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 6
        header.setCustomSpacing(16, after: pasteButton)
        header.setCustomSpacing(12, after: spacer)
        header.setCustomSpacing(14, after: endLabel)

        for view in [header, track] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        let height = heightAnchor.constraint(equalToConstant: Self.fullHeight)
        heightConstraint = height
        NSLayoutConstraint.activate([
            height,
            header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            header.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            header.topAnchor.constraint(equalTo: topAnchor, constant: 9),
            header.heightAnchor.constraint(equalToConstant: 24),
            track.leadingAnchor.constraint(equalTo: leadingAnchor),
            track.trailingAnchor.constraint(equalTo: trailingAnchor),
            track.topAnchor.constraint(equalTo: header.bottomAnchor),
            track.bottomAnchor.constraint(equalTo: bottomAnchor),
            copyButton.widthAnchor.constraint(equalToConstant: 20),
            copyButton.heightAnchor.constraint(equalToConstant: 20),
            pasteButton.widthAnchor.constraint(equalToConstant: 20),
            pasteButton.heightAnchor.constraint(equalToConstant: 20),
            sizeButton.widthAnchor.constraint(equalToConstant: 20),
            sizeButton.heightAnchor.constraint(equalToConstant: 20),
        ])
        applySize()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var mouseDownCanMoveWindow: Bool { false }

    var height: CGFloat { isFull ? Self.fullHeight : Self.compactHeight }

    func update(frameIndex: Int, frameCount: Int, frameRate: Double, frameNumberBase: Int) {
        track.update(frameIndex: frameIndex, frameCount: frameCount, frameRate: frameRate)
        guard frameRate > 0 else { return }
        timecodeField.show(Timecode(frameCount: frameIndex, frameRate: frameRate).smpteString)
        frameField.show(String(frameIndex + frameNumberBase))
        endLabel.stringValue = frameCount > 0 ? Timecode(frameCount: frameCount - 1, frameRate: frameRate).smpteString : ""
    }

    func setExpanded(_ expanded: Bool) {
        if expanded {
            isHidden = false
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                animator().alphaValue = 1
            }
        } else {
            if isEditingReadout {
                timecodeField.cancel()
                frameField.cancel()
            }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.2
                animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                guard let self, self.alphaValue == 0 else { return }
                self.isHidden = true
            })
        }
    }

    private func applySize() {
        heightConstraint?.constant = height
        track.showsDetail = isFull
        let symbol = isFull ? "rectangle.compress.vertical" : "rectangle.expand.vertical"
        let description = isFull ? "Compact Timeline" : "Full-Size Timeline"
        sizeButton.image = Self.symbolImage(symbol, description: description)
        sizeButton.toolTip = description
    }

    private func configure(_ button: NSButton, symbol: String, description: String, action: Selector) {
        button.isBordered = false
        button.image = Self.symbolImage(symbol, description: description)
        button.imageScaling = .scaleProportionallyDown
        button.contentTintColor = NSColor.white.withAlphaComponent(0.85)
        button.refusesFirstResponder = true
        button.toolTip = description
        button.target = self
        button.action = action
    }

    private static func symbolImage(_ name: String, description: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: description)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold))
    }

    @objc private func copyTapped(_ sender: Any?) {
        onCopyTimecode?()
    }

    @objc private func pasteTapped(_ sender: Any?) {
        onPasteTimecode?()
    }

    @objc private func sizeTapped(_ sender: Any?) {
        onToggleSize?()
    }
}
