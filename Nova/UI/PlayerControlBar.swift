import AppKit

/// Nova's own transport bar, used for every engine so both look and behave the same. It spans the
/// window's width, so the scrubber is as wide as the video, and carries the button that opens the
/// precision timeline. Driven entirely by `PlayerViewController` through `PlaybackEngine`.
final class PlayerControlBar: NSVisualEffectView {
    static let height: CGFloat = 44

    var onPlayPause: (() -> Void)?
    /// Seconds the user dragged to. `isFinal` marks the release, where an exact seek is worth its cost.
    var onScrub: ((Double, Bool) -> Void)?
    var onVolume: ((Float) -> Void)?
    var onToggleTimeline: (() -> Void)?
    var onToggleFullScreen: (() -> Void)?

    private(set) var isScrubbing = false

    /// Tints the timeline button while the precision timeline is open.
    var isTimelineExpanded = false {
        didSet { updateTimelineButton() }
    }

    private let playButton = NSButton()
    private let elapsedLabel = NSTextField(labelWithString: "0:00")
    private let remainingLabel = NSTextField(labelWithString: "-0:00")
    private let scrubber = NSSlider()
    private let volumeButton = NSButton()
    private let volumeSlider = NSSlider()
    private let timelineButton = NSButton()
    private let fullScreenButton = NSButton()
    private var duration: Double = 0
    private var isPlaying = false

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
        configure(volumeButton, symbol: "speaker.wave.2.fill", description: "Volume", action: nil)
        configure(timelineButton, symbol: "timeline.selection", description: "Expand Timeline", action: #selector(timelineTapped(_:)))
        configure(fullScreenButton, symbol: "arrow.up.left.and.arrow.down.right", description: "Full Screen", action: #selector(fullScreenTapped(_:)))

        for label in [elapsedLabel, remainingLabel] {
            label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
            label.textColor = .labelColor
            label.alignment = .center
            label.setContentHuggingPriority(.required, for: .horizontal)
            label.setContentCompressionResistancePriority(.required, for: .horizontal)
        }

        configure(scrubber, action: #selector(scrubberMoved(_:)))
        scrubber.setContentHuggingPriority(.defaultLow, for: .horizontal)
        configure(volumeSlider, action: #selector(volumeMoved(_:)))
        volumeSlider.doubleValue = 1

        // One stack, centre-aligned, so every control shares a baseline whatever its own height is.
        let stack = NSStackView(views: [
            playButton, elapsedLabel, scrubber, remainingLabel, volumeButton, volumeSlider,
            timelineButton, fullScreenButton,
        ])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 10
        stack.setCustomSpacing(6, after: volumeButton)
        stack.setCustomSpacing(16, after: volumeSlider)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Self.height),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            playButton.widthAnchor.constraint(equalToConstant: 26),
            playButton.heightAnchor.constraint(equalToConstant: 26),
            volumeButton.widthAnchor.constraint(equalToConstant: 20),
            volumeButton.heightAnchor.constraint(equalToConstant: 20),
            timelineButton.widthAnchor.constraint(equalToConstant: 24),
            timelineButton.heightAnchor.constraint(equalToConstant: 24),
            fullScreenButton.widthAnchor.constraint(equalToConstant: 22),
            fullScreenButton.heightAnchor.constraint(equalToConstant: 22),
            volumeSlider.widthAnchor.constraint(equalToConstant: 64),
            elapsedLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 42),
            remainingLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 48),
        ])
        updatePlayButton()
        updateTimelineButton()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var mouseDownCanMoveWindow: Bool { false }

    // MARK: - State

    func update(time: Double, duration: Double, isPlaying: Bool, volume: Float) {
        self.duration = max(0, duration)
        if self.isPlaying != isPlaying {
            self.isPlaying = isPlaying
            updatePlayButton()
        }
        if !volumeSlider.isHighlighted {
            volumeSlider.doubleValue = Double(volume)
        }
        guard !isScrubbing else { return }
        scrubber.doubleValue = self.duration > 0 ? min(max(time / self.duration, 0), 1) : 0
        elapsedLabel.stringValue = Self.clock(time)
        remainingLabel.stringValue = "-" + Self.clock(max(self.duration - time, 0))
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
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold))
    }

    private func updatePlayButton() {
        let description = isPlaying ? "Pause" : "Play"
        playButton.image = Self.symbolImage(isPlaying ? "pause.fill" : "play.fill", description: description)
        playButton.toolTip = description
    }

    private func updateTimelineButton() {
        let description = isTimelineExpanded ? "Collapse Timeline" : "Expand Timeline"
        timelineButton.toolTip = description
        timelineButton.image = Self.symbolImage("timeline.selection", description: description)
        timelineButton.contentTintColor = isTimelineExpanded ? .controlAccentColor : .labelColor
    }

    // MARK: - Actions

    @objc private func playPauseTapped(_ sender: Any?) {
        onPlayPause?()
    }

    @objc private func timelineTapped(_ sender: Any?) {
        onToggleTimeline?()
    }

    @objc private func fullScreenTapped(_ sender: Any?) {
        onToggleFullScreen?()
    }

    @objc private func scrubberMoved(_ sender: Any?) {
        let eventType = NSApp.currentEvent?.type
        let isFinal = eventType != .leftMouseDown && eventType != .leftMouseDragged
        isScrubbing = !isFinal
        let seconds = scrubber.doubleValue * duration
        elapsedLabel.stringValue = Self.clock(seconds)
        remainingLabel.stringValue = "-" + Self.clock(max(duration - seconds, 0))
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
