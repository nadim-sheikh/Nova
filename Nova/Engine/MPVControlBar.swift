import AppKit

/// Floating transport controls for the mpv engine: play/pause, a scrubber, and clock times,
/// styled after AVPlayerView's floating bar so both engines feel alike.
final class MPVControlBar: NSVisualEffectView {
    var onPlayPause: (() -> Void)?
    /// Seconds the user dragged to. `isFinal` marks the release, where an exact seek is worth its cost.
    var onScrub: ((Double, Bool) -> Void)?
    private(set) var isScrubbing = false

    private let playButton = NSButton()
    private let elapsedLabel = NSTextField(labelWithString: "0:00")
    private let remainingLabel = NSTextField(labelWithString: "-0:00")
    private let slider = NSSlider()
    private var duration: Double = 0
    private var isPlaying = false

    init() {
        super.init(frame: .zero)
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = true

        playButton.isBordered = false
        playButton.imageScaling = .scaleProportionallyDown
        playButton.refusesFirstResponder = true
        playButton.target = self
        playButton.action = #selector(togglePlayPause(_:))
        playButton.setContentHuggingPriority(.required, for: .horizontal)

        for label in [elapsedLabel, remainingLabel] {
            label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
            label.textColor = .labelColor
            label.setContentHuggingPriority(.required, for: .horizontal)
            label.setContentCompressionResistancePriority(.required, for: .horizontal)
        }
        elapsedLabel.alignment = .right
        remainingLabel.alignment = .left

        slider.minValue = 0
        slider.maxValue = 1
        slider.doubleValue = 0
        slider.isContinuous = true
        slider.controlSize = .small
        slider.refusesFirstResponder = true
        slider.target = self
        slider.action = #selector(sliderMoved(_:))

        let stack = NSStackView(views: [playButton, elapsedLabel, slider, remainingLabel])
        stack.orientation = .horizontal
        stack.spacing = 10
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            playButton.widthAnchor.constraint(equalToConstant: 24),
            playButton.heightAnchor.constraint(equalToConstant: 24),
            elapsedLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 44),
            remainingLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 50),
        ])
        updatePlayButton()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var mouseDownCanMoveWindow: Bool { false }

    func update(time: Double, duration: Double, isPlaying: Bool) {
        self.duration = max(0, duration)
        if self.isPlaying != isPlaying {
            self.isPlaying = isPlaying
            updatePlayButton()
        }
        guard !isScrubbing else { return }
        slider.doubleValue = self.duration > 0 ? min(max(time / self.duration, 0), 1) : 0
        showTimes(elapsed: time)
    }

    private func showTimes(elapsed: Double) {
        elapsedLabel.stringValue = Self.clock(elapsed)
        remainingLabel.stringValue = "-" + Self.clock(max(duration - elapsed, 0))
    }

    private func updatePlayButton() {
        let name = isPlaying ? "pause.fill" : "play.fill"
        let description = isPlaying ? "Pause" : "Play"
        playButton.image = NSImage(systemSymbolName: name, accessibilityDescription: description)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold))
        playButton.contentTintColor = .labelColor
    }

    @objc private func togglePlayPause(_ sender: Any?) {
        onPlayPause?()
    }

    @objc private func sliderMoved(_ sender: Any?) {
        let eventType = NSApp.currentEvent?.type
        let isFinal = eventType != .leftMouseDown && eventType != .leftMouseDragged
        isScrubbing = !isFinal
        let seconds = slider.doubleValue * duration
        showTimes(elapsed: seconds)
        onScrub?(seconds, isFinal)
    }

    /// `H:MM:SS` past an hour, otherwise `M:SS`, like AVPlayerView.
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
