import AppKit
import AVFoundation
import AVKit
import UniformTypeIdentifiers

/// `PlaybackEngine` backed by AVPlayer, rendering through AVPlayerView's own Metal path.
/// Transport controls live in the UI layer, not here.
@MainActor
final class AVFoundationEngine: PlaybackEngine {
    private let player = AVPlayer()
    private let playerView = AVPlayerView()
    private var timeObserverToken: Any?
    private var rateObservation: NSKeyValueObservation?
    private var readinessObservation: NSKeyValueObservation?
    private var endOfItemObserver: NSObjectProtocol?
    private var currentAsset: AVURLAsset?
    private var loadedDuration: CMTime = .invalid
    private var frameDuration: CMTime = .invalid

    private(set) var frameRate: Double = 0
    private(set) var naturalSize: CGSize = .zero
    var onTimeUpdate: ((CMTime) -> Void)?
    var onStateChange: (() -> Void)?

    /// Asked of macOS rather than hardcoded, so it reflects what this OS version can decode.
    nonisolated static let videoContentTypes: [UTType] = {
        AVURLAsset.audiovisualTypes()
            .compactMap { UTType($0.rawValue) }
            .filter { ($0.conforms(to: .movie) || $0.conforms(to: .video)) && !$0.conforms(to: .audio) }
    }()

    var supportedContentTypes: [UTType] { AVFoundationEngine.videoContentTypes }
    var videoView: NSView { playerView }
    var currentTime: CMTime { player.currentTime() }
    var duration: CMTime { loadedDuration }
    var isPlaying: Bool { player.rate != 0 }
    var rate: Float { player.rate }

    var isLooping = false {
        didSet { player.actionAtItemEnd = isLooping ? .none : .pause }
    }

    var volume: Float {
        get { player.volume }
        set { player.volume = min(max(newValue, 0), 1) }
    }

    init() {
        playerView.player = player
        // Nova draws its own transport bar for both engines, so AVKit's floating controls stay off.
        playerView.controlsStyle = .none
        // Live Text analysis of paused frames costs memory and CPU for no benefit here.
        playerView.allowsVideoFrameAnalysis = false
        player.actionAtItemEnd = .pause

        rateObservation = player.observe(\.rate, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.onStateChange?() }
        }
    }

    // MARK: - Loading

    func load(url: URL) async throws {
        unload()
        let asset = AVURLAsset(url: url)
        do {
            let (isPlayable, assetDuration) = try await asset.load(.isPlayable, .duration)
            guard isPlayable else { throw PlaybackError.notPlayable }

            guard let track = try await asset.loadTracks(withMediaType: .video).first else {
                throw PlaybackError.noVideoTrack
            }
            let (nominalFrameRate, minFrameDuration, size, transform) = try await track.load(
                .nominalFrameRate, .minFrameDuration, .naturalSize, .preferredTransform
            )
            guard nominalFrameRate > 0 else { throw PlaybackError.unknownFrameRate }

            let item = AVPlayerItem(asset: asset)
            player.replaceCurrentItem(with: item)
            try await waitUntilReady(item)
            endOfItemObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.handleEndOfItem() }
            }

            currentAsset = asset
            frameRate = Self.preciseFrameRate(nominal: nominalFrameRate, minFrameDuration: minFrameDuration)
            frameDuration = CMTime(seconds: 1 / frameRate, preferredTimescale: 600_000)
            if minFrameDuration.isNumeric, abs(minFrameDuration.seconds * frameRate - 1) < 0.001 {
                frameDuration = minFrameDuration
            }
            naturalSize = Self.displaySize(natural: size, transform: transform)
            loadedDuration = assetDuration
            installTimeObserver()
            onTimeUpdate?(currentTime)
            onStateChange?()
        } catch let error as PlaybackError {
            unload()
            throw error
        } catch {
            unload()
            throw PlaybackError.loadFailed(underlying: error)
        }
    }

    func unload() {
        if let token = timeObserverToken {
            player.removeTimeObserver(token)
            timeObserverToken = nil
        }
        if let observer = endOfItemObserver {
            NotificationCenter.default.removeObserver(observer)
            endOfItemObserver = nil
        }
        player.pause()
        player.replaceCurrentItem(with: nil)
        currentAsset = nil
        frameRate = 0
        naturalSize = .zero
        loadedDuration = .invalid
        frameDuration = .invalid
    }

    /// Suspends until the item reports `.readyToPlay`, or throws if it reports `.failed`.
    private func handleEndOfItem() {
        guard isLooping else { return }
        // actionAtItemEnd is .none while looping, so the rate survives and playback resumes after the seek.
        player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func waitUntilReady(_ item: AVPlayerItem) async throws {
        readinessObservation?.invalidate()
        defer {
            readinessObservation?.invalidate()
            readinessObservation = nil
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            // `.initial` can fire synchronously inside `observe`, and status can only settle once,
            // but guard anyway so the continuation is never resumed twice.
            var hasResumed = false
            readinessObservation = item.observe(\.status, options: [.initial, .new]) { item, _ in
                guard !hasResumed else { return }
                switch item.status {
                case .readyToPlay:
                    hasResumed = true
                    continuation.resume()
                case .failed:
                    hasResumed = true
                    continuation.resume(throwing: PlaybackError.loadFailed(underlying: item.error))
                case .unknown:
                    break
                @unknown default:
                    break
                }
            }
        }
    }

    /// `nominalFrameRate` is a Float, and its rounding error (29.97003 vs 30000/1001) accumulates to a
    /// full frame after about ten minutes. When the track's exact frame duration agrees with the
    /// nominal rate, derive the rate from that rational value instead. Variable-frame-rate content,
    /// where the two disagree, keeps the nominal rate.
    private static func preciseFrameRate(nominal: Float, minFrameDuration: CMTime) -> Double {
        let nominalRate = Double(nominal)
        guard minFrameDuration.isNumeric, minFrameDuration.seconds > 0 else { return nominalRate }
        let exactRate = 1 / minFrameDuration.seconds
        let agreement = abs(exactRate - nominalRate) / nominalRate
        return agreement < 0.005 ? exactRate : nominalRate
    }

    private static func displaySize(natural: CGSize, transform: CGAffineTransform) -> CGSize {
        let transformed = natural.applying(transform)
        return CGSize(width: abs(transformed.width), height: abs(transformed.height))
    }

    private func installTimeObserver() {
        let interval = CMTime(value: 1, timescale: CMTimeScale(Timecode.nominalRate(frameRate: frameRate)))
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.onTimeUpdate?(time) }
        }
    }

    // MARK: - Transport

    func play() {
        guard player.currentItem != nil else { return }
        if loadedDuration.isNumeric, currentTime >= loadedDuration {
            seek(to: .zero)
        }
        player.play()
    }

    func pause() {
        player.pause()
    }

    func seek(to time: CMTime) {
        guard player.currentItem != nil else { return }
        var target = time
        if loadedDuration.isNumeric {
            target = CMTimeClampToRange(time, range: CMTimeRange(start: .zero, duration: loadedDuration))
        }
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.onTimeUpdate?(self.currentTime)
            }
        }
    }

    func stepFrames(_ count: Int) {
        guard let item = player.currentItem else { return }
        player.pause()
        // When paused mid-frame AVPlayer displays the frame at or before the clock, but
        // `step(byCount:)` measures from the frame after it and skips one. Snap the clock to the
        // displayed frame's exact boundary first so every step moves exactly one frame.
        guard let boundary = displayedFrameBoundary() else {
            item.step(byCount: count)
            onTimeUpdate?(currentTime)
            return
        }
        player.seek(to: boundary, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                item.step(byCount: count)
                self.onTimeUpdate?(self.currentTime)
            }
        }
    }

    func captureCurrentFrame() async throws -> CGImage {
        guard let asset = currentAsset else { throw PlaybackError.noMediaLoaded }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let time = displayedFrameBoundary() ?? currentTime
        do {
            return try await generator.image(at: time).image
        } catch {
            throw PlaybackError.frameCaptureFailed(underlying: error)
        }
    }

    /// Exact time of the frame currently displayed, or nil when the clock already sits on a frame boundary.
    private func displayedFrameBoundary() -> CMTime? {
        let time = currentTime
        guard frameRate > 0, frameDuration.isNumeric, time.isNumeric else { return nil }
        let exactFrames = time.seconds * frameRate
        let frameIndex = (exactFrames + 1e-6).rounded(.down)
        guard exactFrames - frameIndex > 0.001, frameIndex < Double(Int32.max) else { return nil }
        return CMTimeMultiply(frameDuration, multiplier: Int32(frameIndex))
    }

    func setRate(_ rate: Float) throws {
        guard let item = player.currentItem else { return }
        let supported: Bool
        switch rate {
        case 0, 1:
            supported = true
        case let r where r > 1:
            supported = item.canPlayFastForward
        case let r where r > 0:
            supported = item.canPlaySlowForward
        case -1:
            supported = item.canPlayReverse
        case let r where r < -1:
            supported = item.canPlayFastReverse
        default:
            supported = item.canPlaySlowReverse
        }
        guard supported else { throw PlaybackError.unsupportedRate(rate) }
        player.rate = rate
    }
}
