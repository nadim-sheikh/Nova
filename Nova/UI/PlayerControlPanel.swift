import AppKit

/// Nova's player panel: one box across the bottom of the video holding the transport controls and,
/// when the timeline is expanded, the precision scrubber in the same box. Used by every engine, so
/// playback looks and behaves the same whichever one decoded the file.
///
/// Collapsed it shows play, clock times and a wide slider. Expanded it swaps those for an editable
/// timecode with copy and paste, the clip's end, and a frame-accurate track underneath.
final class PlayerControlPanel: NSVisualEffectView {
    var onPlayPause: (() -> Void)?
    /// Seconds the coarse slider was dragged to. `isFinal` marks the release.
    var onScrub: ((Double, Bool) -> Void)?
    var onVolume: ((Float) -> Void)?
    var onToggleTimeline: (() -> Void)?
    var onToggleFullScreen: (() -> Void)?
    /// Frame the precision track was clicked or dragged to.
    var onTimelineScrub: ((Int) -> Void)? {
        get { track.onScrub }
        set { track.onScrub = newValue }
    }
    var onCopyTimecode: (() -> Void)?
    var onPasteTimecode: (() -> Void)?
    var onEnterTimecode: ((String) -> Void)?
    var onToggleSize: (() -> Void)?

    var isScrubbing: Bool { isSliderScrubbing || track.isScrubbing }
    var isEditingTimecode: Bool { timecodeField.isEditing }

    /// Opens the precision timeline inside this panel, which grows upwards to fit it.
    private(set) var isTimelineExpanded = false

    /// Full gives the track tick labels and more room; compact keeps the panel small.
    var isFull = true {
        didSet {
            guard isFull != oldValue else { return }
            updateButtonsForState()
            guard isTimelineExpanded, window != nil else { return }
            track.showsDetail = isFull
            let height = isFull ? Self.fullTrackHeight : Self.compactTrackHeight
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.24
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                context.allowsImplicitAnimation = true
                trackHeight?.animator().constant = height
                superview?.layoutSubtreeIfNeeded()
            }
        }
    }

    private let playButton = NSButton()
    private let elapsedLabel = NSTextField(labelWithString: "0:00")
    private let remainingLabel = NSTextField(labelWithString: "-0:00")
    private let scrubber = NSSlider()
    private let timecodeField = ReadoutField(minimumWidth: 108, description: "Type a timecode and press Return to jump to it")
    private let copyButton = NSButton()
    private let pasteButton = NSButton()
    private let spacer = NSView()
    private let endLabel = NSTextField(labelWithString: "")
    private let volumeButton = NSButton()
    private let volumeSlider = NSSlider()
    private let timelineButton = NSButton()
    private let sizeButton = NSButton()
    private let fullScreenButton = NSButton()
    private let track = TimelineTrackView()

    private var trackHeight: NSLayoutConstraint?
    private var trackSpacing: NSLayoutConstraint?
    private var isSliderScrubbing = false
    private var layoutGeneration = 0
    private var duration: Double = 0
    private var isPlaying = false

    private static let rowHeight: CGFloat = 24
    private static let verticalPadding: CGFloat = 10
    private static let compactTrackHeight: CGFloat = 38
    private static let fullTrackHeight: CGFloat = 72

    init() {
        super.init(frame: .zero)
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.masksToBounds = true
        alphaValue = 0

        configure(playButton, symbol: "play.fill", description: "Play", action: #selector(playPauseTapped(_:)))
        configure(copyButton, symbol: "doc.on.doc", description: "Copy Timecode", action: #selector(copyTapped(_:)))
        configure(pasteButton, symbol: "doc.on.clipboard", description: "Paste Timecode", action: #selector(pasteTapped(_:)))
        configure(volumeButton, symbol: "speaker.wave.2.fill", description: "Volume", action: nil)
        configure(timelineButton, symbol: "timeline.selection", description: "Expand Timeline", action: #selector(timelineTapped(_:)))
        configure(sizeButton, symbol: "rectangle.compress.vertical", description: "Compact Timeline", action: #selector(sizeTapped(_:)))
        configure(fullScreenButton, symbol: "arrow.up.left.and.arrow.down.right", description: "Full Screen", action: #selector(fullScreenTapped(_:)))

        for label in [elapsedLabel, remainingLabel, endLabel] {
            label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
            label.textColor = .labelColor
            label.setContentHuggingPriority(.required, for: .horizontal)
            label.setContentCompressionResistancePriority(.required, for: .horizontal)
        }
        endLabel.textColor = NSColor.labelColor.withAlphaComponent(0.65)
        elapsedLabel.alignment = .center
        remainingLabel.alignment = .center

        configure(scrubber, action: #selector(scrubberMoved(_:)))
        scrubber.setContentHuggingPriority(.defaultLow, for: .horizontal)
        configure(volumeSlider, action: #selector(volumeMoved(_:)))
        volumeSlider.doubleValue = 1
        // Digits and separators only: a timecode field should never accept a word.
        timecodeField.formatter = TimecodeInputFormatter()
        timecodeField.onCommit = { [weak self] text in self?.onEnterTimecode?(text) }
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        // One centre-aligned row: which of its controls apply depends on whether the timeline is open.
        let row = NSStackView(views: [
            playButton, elapsedLabel, scrubber, remainingLabel,
            timecodeField, copyButton, pasteButton, spacer, endLabel,
            volumeButton, volumeSlider, timelineButton, sizeButton, fullScreenButton,
        ])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.setCustomSpacing(6, after: timecodeField)
        row.setCustomSpacing(6, after: copyButton)
        row.setCustomSpacing(6, after: volumeButton)
        row.setCustomSpacing(16, after: volumeSlider)
        row.setCustomSpacing(6, after: timelineButton)

        for view in [row, track] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        let trackHeight = track.heightAnchor.constraint(equalToConstant: 0)
        let trackSpacing = track.topAnchor.constraint(equalTo: row.bottomAnchor, constant: 0)
        self.trackHeight = trackHeight
        self.trackSpacing = trackSpacing
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            row.topAnchor.constraint(equalTo: topAnchor, constant: Self.verticalPadding),
            row.heightAnchor.constraint(equalToConstant: Self.rowHeight),
            trackSpacing,
            trackHeight,
            track.leadingAnchor.constraint(equalTo: leadingAnchor),
            track.trailingAnchor.constraint(equalTo: trailingAnchor),
            // The panel's own height follows from its contents, so it grows when the timeline opens.
            track.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.verticalPadding),
            playButton.widthAnchor.constraint(equalToConstant: 26),
            playButton.heightAnchor.constraint(equalToConstant: 26),
            volumeButton.widthAnchor.constraint(equalToConstant: 20),
            volumeButton.heightAnchor.constraint(equalToConstant: 20),
            volumeSlider.widthAnchor.constraint(equalToConstant: 64),
            timelineButton.widthAnchor.constraint(equalToConstant: 24),
            timelineButton.heightAnchor.constraint(equalToConstant: 24),
            sizeButton.widthAnchor.constraint(equalToConstant: 20),
            sizeButton.heightAnchor.constraint(equalToConstant: 20),
            fullScreenButton.widthAnchor.constraint(equalToConstant: 22),
            fullScreenButton.heightAnchor.constraint(equalToConstant: 22),
            copyButton.widthAnchor.constraint(equalToConstant: 20),
            copyButton.heightAnchor.constraint(equalToConstant: 20),
            pasteButton.widthAnchor.constraint(equalToConstant: 20),
            pasteButton.heightAnchor.constraint(equalToConstant: 20),
            elapsedLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 42),
            remainingLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 48),
        ])
        applyLayout(animated: false)
        updatePlayButton()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var mouseDownCanMoveWindow: Bool { false }

    // MARK: - Sections

    func setTimelineExpanded(_ expanded: Bool) {
        guard expanded != isTimelineExpanded else { return }
        isTimelineExpanded = expanded
        if !expanded, timecodeField.isEditing {
            timecodeField.cancel()
        }
        applyLayout(animated: true)
    }

    /// Controls that belong to each state. The panel morphs between the two sets.
    private var transportOnlyViews: [NSView] { [elapsedLabel, scrubber, remainingLabel] }
    private var timelineOnlyViews: [NSView] { [timecodeField, copyButton, pasteButton, endLabel, sizeButton, track] }

    /// Cross-fades between the transport and timeline states while the panel resizes, so the
    /// change reads as one movement instead of controls popping in and out.
    private func applyLayout(animated: Bool) {
        layoutGeneration += 1
        let generation = layoutGeneration
        updateButtonsForState()
        guard animated, window != nil else {
            settleLayout(animated: false)
            return
        }
        let leaving = isTimelineExpanded ? transportOnlyViews : timelineOnlyViews
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.11
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            leaving.filter { !$0.isHidden }.forEach { $0.animator().alphaValue = 0 }
        }, completionHandler: { [weak self] in
            // A second toggle during the fade supersedes this one and settles the panel itself.
            guard let self, self.layoutGeneration == generation else { return }
            self.settleLayout(animated: true)
        })
    }

    /// Puts every control into the state's final arrangement, fading in whatever now applies.
    private func settleLayout(animated: Bool) {
        let expanded = isTimelineExpanded
        let leaving = expanded ? transportOnlyViews : timelineOnlyViews
        let arriving = expanded ? timelineOnlyViews : transportOnlyViews
        for view in leaving {
            view.isHidden = true
            view.alphaValue = 1
        }
        spacer.isHidden = !expanded
        for view in arriving {
            view.alphaValue = animated ? 0 : 1
            view.isHidden = false
        }
        track.showsDetail = isFull
        let height = expanded ? (isFull ? Self.fullTrackHeight : Self.compactTrackHeight) : 0
        let spacing: CGFloat = expanded ? 6 : 0
        guard animated else {
            trackHeight?.constant = height
            trackSpacing?.constant = spacing
            superview?.layoutSubtreeIfNeeded()
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.26
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true
            // Animating the constraints themselves: implicit animation alone leaves the panel's
            // height to snap, because Auto Layout applies the new size in one pass.
            trackHeight?.animator().constant = height
            trackSpacing?.animator().constant = spacing
            arriving.forEach { $0.animator().alphaValue = 1 }
            superview?.layoutSubtreeIfNeeded()
        }
    }

    private func updateButtonsForState() {
        let symbol = isFull ? "rectangle.compress.vertical" : "rectangle.expand.vertical"
        let sizeDescription = isFull ? "Compact Timeline" : "Full-Size Timeline"
        sizeButton.image = Self.symbolImage(symbol, description: sizeDescription)
        sizeButton.toolTip = sizeDescription
        let timelineDescription = isTimelineExpanded ? "Collapse Timeline" : "Expand Timeline"
        timelineButton.toolTip = timelineDescription
        timelineButton.contentTintColor = isTimelineExpanded ? .controlAccentColor : .labelColor
    }

    // MARK: - State

    func updateTransport(time: Double, duration: Double, isPlaying: Bool, volume: Float) {
        self.duration = max(0, duration)
        if self.isPlaying != isPlaying {
            self.isPlaying = isPlaying
            updatePlayButton()
        }
        if !volumeSlider.isHighlighted {
            volumeSlider.doubleValue = Double(volume)
        }
        guard !isSliderScrubbing else { return }
        scrubber.doubleValue = self.duration > 0 ? min(max(time / self.duration, 0), 1) : 0
        showClocks(elapsed: time)
    }

    func updateTimeline(frameIndex: Int, frameCount: Int, frameRate: Double) {
        track.update(frameIndex: frameIndex, frameCount: frameCount, frameRate: frameRate)
        guard frameRate > 0 else { return }
        timecodeField.show(Timecode(frameCount: frameIndex, frameRate: frameRate).smpteString)
        endLabel.stringValue = frameCount > 0 ? Timecode(frameCount: frameCount - 1, frameRate: frameRate).smpteString : ""
    }

    private func showClocks(elapsed: Double) {
        elapsedLabel.stringValue = Self.clock(elapsed)
        remainingLabel.stringValue = "-" + Self.clock(max(duration - elapsed, 0))
    }

    // MARK: - Appearance

    private func configure(_ button: NSButton, symbol: String, description: String, action: Selector?) {
        button.isBordered = false
        button.imageScaling = .scaleProportionallyDown
        button.image = Self.symbolImage(symbol, description: description)
        button.contentTintColor = .labelColor
        button.toolTip = description
        button.refusesFirstResponder = true
        button.isEnabled = action != nil
        button.target = self
        button.action = action
    }

    private func configure(_ slider: NSSlider, action: Selector) {
        slider.minValue = 0
        slider.maxValue = 1
        slider.doubleValue = 0
        slider.isContinuous = true
        slider.controlSize = .small
        slider.refusesFirstResponder = true
        slider.target = self
        slider.action = action
    }

    private static func symbolImage(_ name: String, description: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: description)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold))
    }

    private func updatePlayButton() {
        let description = isPlaying ? "Pause" : "Play"
        playButton.image = Self.symbolImage(isPlaying ? "pause.fill" : "play.fill", description: description)
        playButton.toolTip = description
    }

    // MARK: - Actions

    @objc private func playPauseTapped(_ sender: Any?) {
        onPlayPause?()
    }

    @objc private func timelineTapped(_ sender: Any?) {
        onToggleTimeline?()
    }

    @objc private func sizeTapped(_ sender: Any?) {
        onToggleSize?()
    }

    @objc private func fullScreenTapped(_ sender: Any?) {
        onToggleFullScreen?()
    }

    @objc private func copyTapped(_ sender: Any?) {
        onCopyTimecode?()
    }

    @objc private func pasteTapped(_ sender: Any?) {
        onPasteTimecode?()
    }

    @objc private func scrubberMoved(_ sender: Any?) {
        let eventType = NSApp.currentEvent?.type
        let isFinal = eventType != .leftMouseDown && eventType != .leftMouseDragged
        isSliderScrubbing = !isFinal
        let seconds = scrubber.doubleValue * duration
        showClocks(elapsed: seconds)
        onScrub?(seconds, isFinal)
    }

    @objc private func volumeMoved(_ sender: Any?) {
        onVolume?(Float(volumeSlider.doubleValue))
    }

    /// `H:MM:SS` past an hour, otherwise `M:SS`.
    static func clock(_ seconds: Double) -> String {
        let total = Int(max(0, seconds).rounded(.down))
        let hours = total / 3600
        let minutes = (total / 60) % 60
        let remainder = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainder)
        }
        return String(format: "%d:%02d", minutes, remainder)
    }
}
