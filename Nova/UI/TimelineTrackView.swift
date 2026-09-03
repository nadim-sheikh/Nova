import AppKit

/// The scrubber inside the expanded timeline: a thick track with the played range, a playhead
/// you can grab anywhere along the strip, tick marks, and a readout that follows the pointer.
/// Positions are frame indices, so every seek lands on an exact frame.
final class TimelineTrackView: NSView {
    /// Called with the frame the pointer is on, whenever it changes during a click or drag.
    var onScrub: ((Int) -> Void)?
    private(set) var isScrubbing = false

    /// Full-size timelines show tick labels on a taller track.
    var showsDetail = true {
        didSet { needsDisplay = true }
    }

    private var frameIndex = 0
    private var frameCount = 0
    private var frameRate: Double = 0
    private var hoverFrame: Int?
    private var lastSentFrame: Int?
    private var trackingArea: NSTrackingArea?

    private static let inset: CGFloat = 20
    private static let labelFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
    private static let tickIntervals: [Double] = [1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 1800, 3600]

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    func update(frameIndex: Int, frameCount: Int, frameRate: Double) {
        self.frameIndex = frameIndex
        self.frameCount = frameCount
        self.frameRate = frameRate
        needsDisplay = true
    }

    // MARK: - Geometry

    private var trackHeight: CGFloat { showsDetail ? 12 : 10 }

    /// Sits a little above the middle so the hover readout and tick labels have room.
    private var trackRect: NSRect {
        let y = showsDetail ? bounds.height * 0.42 : bounds.height * 0.45
        return NSRect(x: Self.inset, y: y - trackHeight / 2, width: max(1, bounds.width - 2 * Self.inset), height: trackHeight)
    }

    private func x(forFrame frame: Int) -> CGFloat {
        let track = trackRect
        guard frameCount > 1 else { return track.minX }
        return track.minX + track.width * CGFloat(frame) / CGFloat(frameCount - 1)
    }

    private func frame(atX x: CGFloat) -> Int {
        let track = trackRect
        guard frameCount > 1 else { return 0 }
        let fraction = min(max((x - track.minX) / track.width, 0), 1)
        return Int((fraction * CGFloat(frameCount - 1)).rounded())
    }

    // MARK: - Mouse

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
        hoverFrame = frame(atX: convert(event.locationInWindow, from: nil).x)
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hoverFrame = nil
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        guard frameCount > 0 else { return }
        isScrubbing = true
        lastSentFrame = nil
        scrub(to: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isScrubbing else { return }
        scrub(to: event)
    }

    override func mouseUp(with event: NSEvent) {
        isScrubbing = false
        needsDisplay = true
    }

    private func scrub(to event: NSEvent) {
        let frame = self.frame(atX: convert(event.locationInWindow, from: nil).x)
        frameIndex = frame
        hoverFrame = frame
        needsDisplay = true
        guard frame != lastSentFrame else { return }
        lastSentFrame = frame
        onScrub?(frame)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        let track = trackRect
        let accent = NSColor.controlAccentColor

        NSColor.white.withAlphaComponent(0.22).setFill()
        NSBezierPath(roundedRect: track, xRadius: track.height / 2, yRadius: track.height / 2).fill()

        let playheadX = x(forFrame: frameIndex)
        if playheadX > track.minX {
            let played = NSRect(x: track.minX, y: track.minY, width: playheadX - track.minX, height: track.height)
            accent.setFill()
            NSBezierPath(roundedRect: played, xRadius: track.height / 2, yRadius: track.height / 2).fill()
        }

        drawTicks(track: track)

        // Playhead: a line across the strip with a handle on the track.
        accent.setStroke()
        let line = NSBezierPath()
        line.lineWidth = 2
        line.move(to: NSPoint(x: playheadX, y: track.minY - 14))
        line.line(to: NSPoint(x: playheadX, y: track.maxY + 14))
        line.stroke()
        let handle = NSRect(x: playheadX - 7, y: track.midY - 7, width: 14, height: 14)
        NSColor.white.setFill()
        NSBezierPath(ovalIn: handle).fill()
        accent.setStroke()
        let ring = NSBezierPath(ovalIn: handle.insetBy(dx: 1, dy: 1))
        ring.lineWidth = 2
        ring.stroke()

        drawReadouts(track: track, playheadX: playheadX)
    }

    /// Tick marks spaced at a round number of seconds so they never crowd together.
    private func drawTicks(track: NSRect) {
        guard frameRate > 0, frameCount > 1 else { return }
        let duration = Double(frameCount) / frameRate
        let pointsPerSecond = track.width / CGFloat(duration)
        guard let interval = Self.tickIntervals.first(where: { CGFloat($0) * pointsPerSecond >= 48 }) ?? Self.tickIntervals.last else { return }
        NSColor.white.withAlphaComponent(0.45).setStroke()
        var seconds = 0.0
        var index = 0
        while seconds <= duration {
            let tickX = track.minX + track.width * CGFloat(seconds / duration)
            let isMajor = index % 5 == 0
            let tick = NSBezierPath()
            tick.lineWidth = 1
            tick.move(to: NSPoint(x: tickX, y: track.minY - (isMajor ? 12 : 6)))
            tick.line(to: NSPoint(x: tickX, y: track.minY - 2))
            tick.stroke()
            if showsDetail, isMajor, index > 0, CGFloat(interval) * pointsPerSecond * 5 >= 70 {
                draw(Self.clock(seconds), at: NSPoint(x: tickX, y: track.maxY + 8), anchor: .center, dim: true)
            }
            seconds += interval
            index += 1
        }
    }

    /// Pointer readout, so you can see which frame a click would land on before clicking.
    private func drawReadouts(track: NSRect, playheadX: CGFloat) {
        guard frameRate > 0 else { return }
        if let hoverFrame, !isScrubbing, hoverFrame != frameIndex {
            let hoverX = x(forFrame: hoverFrame)
            NSColor.white.withAlphaComponent(0.6).setStroke()
            let line = NSBezierPath()
            line.lineWidth = 1
            line.move(to: NSPoint(x: hoverX, y: track.minY - 14))
            line.line(to: NSPoint(x: hoverX, y: track.maxY + 14))
            line.stroke()
            let text = Timecode(frameCount: hoverFrame, frameRate: frameRate).smpteString
            let clampedX = min(max(hoverX, track.minX + 50), track.maxX - 50)
            draw(text, at: NSPoint(x: clampedX, y: max(4, track.minY - 34)), anchor: .center, dim: false, boxed: true)
        }
    }

    private enum Anchor { case leading, center, trailing }

    private func draw(_ text: String, at point: NSPoint, anchor: Anchor, dim: Bool, boxed: Bool = false) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: Self.labelFont,
            .foregroundColor: NSColor.white.withAlphaComponent(dim ? 0.6 : 0.95),
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        var origin = point
        switch anchor {
        case .leading: break
        case .center: origin.x -= size.width / 2
        case .trailing: origin.x -= size.width
        }
        if boxed {
            let box = NSRect(x: origin.x - 6, y: origin.y - 3, width: size.width + 12, height: size.height + 6)
            NSColor.black.withAlphaComponent(0.7).setFill()
            NSBezierPath(roundedRect: box, xRadius: 5, yRadius: 5).fill()
        }
        (text as NSString).draw(at: origin, withAttributes: attributes)
    }

    private static func clock(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total / 60) % 60
        let remainder = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, remainder) : String(format: "%d:%02d", minutes, remainder)
    }
}
