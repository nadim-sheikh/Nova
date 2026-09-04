import AppKit
import CoreMedia
import UniformTypeIdentifiers

/// Routes each file to the engine that can decode it: AVFoundation first, for its hardware path
/// and native controls, then libmpv for everything macOS can't play. View code sees one engine
/// and one video view; the active engine's surface is swapped inside it.
@MainActor
final class HybridPlaybackEngine: PlaybackEngine {
    private let primary: any PlaybackEngine
    private let fallback: any PlaybackEngine
    private var active: any PlaybackEngine
    private let container = NSView()

    var onTimeUpdate: ((CMTime) -> Void)?
    var onStateChange: (() -> Void)?

    init(primary: any PlaybackEngine, fallback: any PlaybackEngine) {
        self.primary = primary
        self.fallback = fallback
        active = primary
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor
        install(primary.videoView)
        forwardCallbacks(from: primary)
        forwardCallbacks(from: fallback)
    }

    // MARK: - Forwarding

    var videoView: NSView { container }
    var currentTime: CMTime { active.currentTime }
    var duration: CMTime { active.duration }
    var frameRate: Double { active.frameRate }
    var naturalSize: CGSize { active.naturalSize }
    var isPlaying: Bool { active.isPlaying }
    var rate: Float { active.rate }

    var supportedContentTypes: [UTType] {
        var seen = Set<String>()
        return (primary.supportedContentTypes + fallback.supportedContentTypes)
            .filter { seen.insert($0.identifier).inserted }
    }

    var volume: Float {
        get { active.volume }
        set {
            primary.volume = newValue
            fallback.volume = newValue
        }
    }

    var isLooping: Bool {
        get { active.isLooping }
        set {
            primary.isLooping = newValue
            fallback.isLooping = newValue
        }
    }

    func load(url: URL) async throws {
        do {
            try await primary.load(url: url)
            activate(primary)
        } catch {
            // AVFoundation declined the file; libmpv decodes whatever ffmpeg knows.
            try await fallback.load(url: url)
            activate(fallback)
        }
    }

    /// Unloads both engines: the inactive one can still hold a file from a load that was replaced.
    func unload() {
        primary.unload()
        fallback.unload()
    }
    func play() { active.play() }
    func pause() { active.pause() }
    func seek(to time: CMTime) { active.seek(to: time) }
    func stepFrames(_ count: Int) { active.stepFrames(count) }
    func setRate(_ rate: Float) throws { try active.setRate(rate) }
    func captureCurrentFrame() async throws -> CGImage { try await active.captureCurrentFrame() }

    // MARK: - Switching

    private func activate(_ engine: any PlaybackEngine) {
        let other = engine === primary ? fallback : primary
        other.unload()
        guard engine !== active else { return }
        active.videoView.removeFromSuperview()
        active = engine
        install(engine.videoView)
        onStateChange?()
    }

    private func install(_ view: NSView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            view.topAnchor.constraint(equalTo: container.topAnchor),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }

    /// Only the active engine's callbacks reach the view layer.
    private func forwardCallbacks(from engine: any PlaybackEngine) {
        engine.onTimeUpdate = { [weak self, weak engine] time in
            guard let self, let engine, engine === self.active else { return }
            self.onTimeUpdate?(time)
        }
        engine.onStateChange = { [weak self, weak engine] in
            guard let self, let engine, engine === self.active else { return }
            self.onStateChange?()
        }
    }
}
