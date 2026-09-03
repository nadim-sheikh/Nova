import AppKit
import CoreMedia
import UniformTypeIdentifiers

/// Abstraction over a media backend. View code talks only to this protocol so that a different
/// engine (for example libmpv) can replace AVFoundation without touching any UI code.
@MainActor
protocol PlaybackEngine: AnyObject {
    /// The engine's rendering surface. Transport controls are the UI layer's job.
    var videoView: NSView { get }
    /// Video formats this engine can decode, used to populate the open dialog.
    var supportedContentTypes: [UTType] { get }

    var currentTime: CMTime { get }
    /// `.invalid` until a file is loaded.
    var duration: CMTime { get }
    /// 0 until a file is loaded.
    var frameRate: Double { get }
    /// Display size of the video with any rotation applied; `.zero` until a file is loaded.
    var naturalSize: CGSize { get }
    /// 0...1. Setting clamps into range.
    var volume: Float { get set }
    var isPlaying: Bool { get }
    /// Signed playback rate: 1 is normal forward speed, negative is reverse, 0 is paused.
    var rate: Float { get }
    /// When true, reaching the end restarts from the beginning at the same rate.
    var isLooping: Bool { get set }

    /// Called on the main actor during playback and after every seek or frame step.
    var onTimeUpdate: ((CMTime) -> Void)? { get set }
    /// Called on the main actor whenever play/pause state or rate changes.
    var onStateChange: (() -> Void)? { get set }

    /// Replaces the current media. Throws `PlaybackError`; on failure the engine is left empty.
    func load(url: URL) async throws
    func unload()
    func play()
    func pause()
    /// Frame-accurate seek (zero tolerance), clamped to the media's duration.
    func seek(to time: CMTime)
    /// Pauses and moves exactly `count` frames (negative steps backward).
    func stepFrames(_ count: Int)
    /// Plays at a signed rate. Throws `PlaybackError.unsupportedRate` if the media can't play at that rate.
    func setRate(_ rate: Float) throws
    /// Decodes the frame currently displayed, at the media's full resolution.
    func captureCurrentFrame() async throws -> CGImage
}
