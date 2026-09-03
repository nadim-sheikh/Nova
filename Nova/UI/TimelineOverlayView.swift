import AppKit

/// A full-width precision scrubber that slides over the bottom of the video when expanded, so the
/// playhead can be placed accurately without hunting for the small slider in the control bar.
/// Comes in two sizes: compact (readouts and track) and full (adds tick labels and a taller track).
final class TimelineOverlayView: NSVisualEffectView {
    static let compactHeight: CGFloat = 68
    static let fullHeight: CGFloat = 116

    var onScrub: ((Int) -> Void)? {
        get { track.onScrub }
        set { track.onScrub = newValue }
    }
    var onCopyTimecode: (() -> Void)?
    var onEnterTimecode: ((String) -> Void)?
    var onToggleSize: (() -> Void)?

    var isScrubbing: Bool { track.isScrubbing }
    var isEditingTimecode: Bool { timecodeField.isEditing }

    /// Full shows tick labels on a taller track; compact keeps just the essentials.
    var isFull = true {
        didSet {
            guard isFull != oldValue else { return }
            applySize()
        }
    }

    private let track = TimelineTrackView()
    private let timecodeField = TimecodeField()
    private let copyButton = NSButton()
    private let frameLabel = NSTextField(labelWithString: "")
    private let endLabel = NSTextField(labelWithString: "")
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
        configure(copyButton, symbol: "doc.on.doc", description: "Copy Timecode", action: #selector(copyTapped(_:)))
        configure(sizeButton, symbol: "rectangle.compress.vertical", description: "Compact Timeline", action: #selector(sizeTapped(_:)))
        for label in [frameLabel, endLabel] {
            label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            label.textColor = NSColor.white.withAlphaComponent(0.85)
            label.setContentCompressionResistancePriority(.required, for: .horizontal)
        }
        endLabel.textColor = NSColor.white.withAlphaComponent(0.6)

        for view in [timecodeField, copyButton, frameLabel, endLabel, sizeButton, track] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        let height = heightAnchor.constraint(equalToConstant: Self.fullHeight)
        heightConstraint = height
        NSLayoutConstraint.activate([
            height,
            timecodeField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            timecodeField.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            copyButton.leadingAnchor.constraint(equalTo: timecodeField.trailingAnchor, constant: 6),
            copyButton.centerYAnchor.constraint(equalTo: timecodeField.centerYAnchor),
            copyButton.widthAnchor.constraint(equalToConstant: 24),
            copyButton.heightAnchor.constraint(equalToConstant: 24),
            frameLabel.leadingAnchor.constraint(equalTo: copyButton.trailingAnchor, constant: 12),
            frameLabel.centerYAnchor.constraint(equalTo: timecodeField.centerYAnchor),
            sizeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            sizeButton.centerYAnchor.constraint(equalTo: timecodeField.centerYAnchor),
            sizeButton.widthAnchor.constraint(equalToConstant: 24),
            sizeButton.heightAnchor.constraint(equalToConstant: 24),
            endLabel.trailingAnchor.constraint(equalTo: sizeButton.leadingAnchor, constant: -12),
            endLabel.centerYAnchor.constraint(equalTo: timecodeField.centerYAnchor),
            track.leadingAnchor.constraint(equalTo: leadingAnchor),
            track.trailingAnchor.constraint(equalTo: trailingAnchor),
            track.topAnchor.constraint(equalTo: timecodeField.bottomAnchor, constant: 4),
            track.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        applySize()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var mouseDownCanMoveWindow: Bool { false }

    func update(frameIndex: Int, frameCount: Int, frameRate: Double) {
        track.update(frameIndex: frameIndex, frameCount: frameCount, frameRate: frameRate)
        guard frameRate > 0 else { return }
        timecodeField.show(Timecode(frameCount: frameIndex, frameRate: frameRate).smpteString)
        frameLabel.stringValue = "Frame \(frameIndex)"
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
            if timecodeField.isEditing {
                timecodeField.cancel()
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
        heightConstraint?.constant = isFull ? Self.fullHeight : Self.compactHeight
        track.showsDetail = isFull
        let symbol = isFull ? "rectangle.compress.vertical" : "rectangle.expand.vertical"
        let description = isFull ? "Compact Timeline" : "Full-Size Timeline"
        sizeButton.image = Self.symbolImage(symbol, description: description)
        sizeButton.toolTip = description
        if let window, !isHidden {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                context.allowsImplicitAnimation = true
                window.layoutIfNeeded()
            }
        }
    }

    private func configure(_ button: NSButton, symbol: String, description: String, action: Selector) {
        button.isBordered = false
        button.image = Self.symbolImage(symbol, description: description)
        button.imageScaling = .scaleProportionallyDown
        button.contentTintColor = .white
        button.refusesFirstResponder = true
        button.toolTip = description
        button.target = self
        button.action = action
    }

    private static func symbolImage(_ name: String, description: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: description)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold))
    }

    @objc private func copyTapped(_ sender: Any?) {
        onCopyTimecode?()
    }

    @objc private func sizeTapped(_ sender: Any?) {
        onToggleSize?()
    }
}
