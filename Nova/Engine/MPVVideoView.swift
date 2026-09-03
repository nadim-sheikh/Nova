import AppKit

/// The mpv engine's rendering surface: video underneath, floating controls that appear on mouse
/// movement and fade out when the pointer rests, matching AVPlayerView's behaviour.
final class MPVVideoView: NSView {
    let renderView = MPVRenderView()
    let controlBar = MPVControlBar()

    private var trackingArea: NSTrackingArea?
    private var hideTask: Task<Void, Never>?
    private static let idleNanoseconds: UInt64 = 2_500_000_000

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor

        renderView.translatesAutoresizingMaskIntoConstraints = false
        controlBar.translatesAutoresizingMaskIntoConstraints = false
        controlBar.alphaValue = 0
        addSubview(renderView)
        addSubview(controlBar)
        NSLayoutConstraint.activate([
            renderView.leadingAnchor.constraint(equalTo: leadingAnchor),
            renderView.trailingAnchor.constraint(equalTo: trailingAnchor),
            renderView.topAnchor.constraint(equalTo: topAnchor),
            renderView.bottomAnchor.constraint(equalTo: bottomAnchor),
            controlBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            controlBar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            controlBar.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -24),
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var isOpaque: Bool { true }

    // MARK: - Mouse tracking

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self, userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        revealControls()
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        revealControls()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        scheduleHide()
    }

    func revealControls() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            controlBar.animator().alphaValue = 1
        }
        scheduleHide()
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: MPVVideoView.idleNanoseconds)
            guard !Task.isCancelled, let self else { return }
            // Resting on the bar or dragging its slider keeps it visible.
            if self.isMouseOverControls || self.controlBar.isScrubbing {
                self.scheduleHide()
                return
            }
            self.hideControls()
        }
    }

    private func hideControls() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            controlBar.animator().alphaValue = 0
        }
    }

    private var isMouseOverControls: Bool {
        guard let window else { return false }
        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        return controlBar.frame.contains(point)
    }
}
