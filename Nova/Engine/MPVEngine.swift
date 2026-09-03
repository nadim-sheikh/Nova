import AppKit
import CoreMedia
import Libmpv
import UniformTypeIdentifiers

/// `PlaybackEngine` backed by libmpv, which decodes every container and codec ffmpeg knows
/// (MKV, WebM, AVI, WMV, FLV, DNxHD, VP9, AV1 and so on). Video is drawn by `MPVRenderLayer`
/// the UI layer supplies the transport controls. The mpv core is only started on first use.
///
/// Reverse playback is not delegated to mpv: its backward mode drops frames whenever a GOP
/// outgrows its reversal buffer and is documented as unsafe with hardware decoding. Instead the
/// engine keeps mpv paused and issues exact backward seeks paced by the wall clock, which stays
/// frame-exact for any codec at the cost of silent audio while reversing.
@MainActor
final class MPVEngine: PlaybackEngine {
    private nonisolated static let timescale: CMTimeScale = 600_000
    private static let loadTimeoutNanoseconds: UInt64 = 10_000_000_000

    private var client: MPVClient?
    private var hostView: MPVRenderView?
    /// Kept separately so `deinit` can free the render context without touching view state.
    private var renderLayer: MPVRenderLayer?
    private var isFileLoaded = false
    private var timePosition: Double = 0
    /// Timestamp of the first video frame. Containers such as WMV and FLV start their video a
    /// frame or so after the audio, and frame 0 must be the first picture, not the first sound.
    private var timeOrigin: Double = 0
    private var restartsSinceLoad = 0
    /// mpv keeps the previous file's `dwidth`/`dheight` until it configures video output for the
    /// new one, so the size is only trusted after this file's first reconfiguration.
    private var reconfigsSinceLoad = 0
    private var restartContinuation: CheckedContinuation<Void, Error>?
    private var pendingSeekSeconds: Double?
    private var isPaused = true
    private var speed: Double = 1
    private var isAtEnd = false
    private var isReversing = false
    private var reverseTimer: Timer?
    private var reverseLastTick = Date()
    private var reverseSeekInFlight = false
    private var storedVolume: Float = 1
    private var frameDuration: CMTime = .invalid
    private var loadContinuation: CheckedContinuation<Void, Error>?
    private var videoSizeContinuation: CheckedContinuation<CGSize, Error>?
    private var loadTimeout: Task<Void, Never>?

    private(set) var frameRate: Double = 0
    private(set) var naturalSize: CGSize = .zero
    private(set) var duration: CMTime = .invalid
    var onTimeUpdate: ((CMTime) -> Void)?
    var onStateChange: (() -> Void)?

    /// Containers ffmpeg demuxes. Extensions without a declared system type get a dynamic type
    /// that still conforms to `.movie`, so the open dialog and drag-and-drop accept them.
    nonisolated static let videoContentTypes: [UTType] = {
        var seen = Set<String>()
        return fileExtensions
            .compactMap { UTType(filenameExtension: $0, conformingTo: .movie) }
            .filter { seen.insert($0.identifier).inserted }
    }()

    private nonisolated static let fileExtensions = [
        "mkv", "mk3d", "webm", "avi", "divx", "wmv", "asf", "flv", "f4v", "ogv", "ogm", "rm", "rmvb",
        "mp4", "m4v", "mov", "qt", "3gp", "3g2", "mpg", "mpeg", "mpe", "m1v", "m2v", "vob",
        "ts", "m2ts", "mts", "m2t", "tp", "trp", "mxf", "dv", "y4m", "nut", "amv", "dvr-ms", "wtv",
        "h264", "264", "h265", "265", "hevc", "ivf", "av1", "obu", "mjpg", "mjpeg", "gxf",
    ]

    /// Applied before the core starts. Options for components missing from this libmpv build are skipped.
    private static let startupOptions: [(String, String)] = [
        ("vo", "libmpv"),
        // Zero-copy hardware decoding: frames stay on the GPU and reach OpenGL as IOSurfaces.
        // Frame captures read them back through the renderer, so no copy mode is needed.
        ("hwdec", "auto-safe"),
        ("idle", "yes"),
        ("keep-open", "yes"),
        ("pause", "yes"),
        ("config", "no"),
        ("terminal", "no"),
        ("msg-level", "all=no"),
        // No Lua at all: mpv's built-in scripts (stats, console, select...) run on LuaJIT, whose
        // JIT pages are killed under the hardened runtime, and Nova draws its own controls anyway.
        ("load-scripts", "no"),
        ("load-stats-overlay", "no"),
        ("load-osd-console", "no"),
        ("load-auto-profiles", "no"),
        ("load-select", "no"),
        ("load-positioning", "no"),
        ("load-commands", "no"),
        ("load-console", "no"),
        ("load-context-menu", "no"),
        ("ytdl", "no"),
        ("osc", "no"),
        ("osd-level", "0"),
        ("input-default-bindings", "no"),
        ("input-vo-keyboard", "no"),
        ("cursor-autohide", "no"),
        ("audio-display", "no"),
        ("sid", "no"),
        ("sub-auto", "no"),
        // Only reached when the renderer can't capture; software conversion avoids mpv's GL
        // screenshot path, which asserts on hardware frames.
        ("screenshot-sw", "yes"),
        ("volume", "100"),
        ("volume-max", "100"),
        ("loop-file", "no"),
        ("audio-client-name", "Nova"),
    ]

    private static let observedProperties: [(String, mpv_format)] = [
        ("time-pos", MPV_FORMAT_DOUBLE),
        ("pause", MPV_FORMAT_FLAG),
        ("speed", MPV_FORMAT_DOUBLE),
        ("eof-reached", MPV_FORMAT_FLAG),
        ("duration", MPV_FORMAT_DOUBLE),
        ("dwidth", MPV_FORMAT_INT64),
        ("dheight", MPV_FORMAT_INT64),
    ]

    init() {}

    deinit {
        renderLayer?.detachRenderContext()
        client?.destroy()
    }

    // MARK: - PlaybackEngine state

    var supportedContentTypes: [UTType] { MPVEngine.videoContentTypes }
    var videoView: NSView { view }
    var isPlaying: Bool { isFileLoaded && (!isPaused || isReversing) }

    var rate: Float {
        guard isPlaying else { return 0 }
        return isReversing ? -Float(speed) : Float(speed)
    }

    var currentTime: CMTime {
        guard isFileLoaded else { return .zero }
        if let pendingSeekSeconds {
            return CMTime(seconds: pendingSeekSeconds, preferredTimescale: Self.timescale)
        }
        return frameAlignedTime(timePosition - timeOrigin)
    }

    var volume: Float {
        get { storedVolume }
        set {
            storedVolume = min(max(newValue, 0), 1)
            set("volume", double: Double(storedVolume) * 100)
        }
    }

    var isLooping = false {
        didSet { set("loop-file", string: isLooping ? "inf" : "no") }
    }

    private var view: MPVRenderView {
        if let hostView { return hostView }
        let view = MPVRenderView()
        hostView = view
        renderLayer = view.renderLayer
        return view
    }

    // MARK: - Core lifecycle

    private func ensureClient() throws -> MPVClient {
        if let client { return client }
        let client = try MPVClient()
        do {
            for (name, value) in Self.startupOptions {
                try client.setOption(name, value)
            }
            try client.initialize()
            for (name, format) in Self.observedProperties {
                client.observe(name, format: format)
            }
            // mpv discards video that has no render context to go to, so attach before any file loads.
            try view.renderLayer.attachRenderContext(to: client)
        } catch {
            client.destroy()
            throw error
        }
        client.onEvent = { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }
        self.client = client
        set("volume", double: Double(storedVolume) * 100)
        set("loop-file", string: isLooping ? "inf" : "no")
        return client
    }

    // MARK: - Loading

    func load(url: URL) async throws {
        let client: MPVClient
        do {
            client = try ensureClient()
        } catch {
            throw PlaybackError.loadFailed(underlying: error)
        }
        unload()
        do {
            restartsSinceLoad = 0
            reconfigsSinceLoad = 0
            try client.command(["loadfile", url.path, "replace"])
            try await waitForFileLoaded()
            guard let track = client.string("vid"), track != "no" else {
                throw videoTrackError(client)
            }
            let size = try await waitForVideoSize()
            let fps = client.double("container-fps") ?? client.double("estimated-vf-fps") ?? 0
            guard fps > 0 else { throw PlaybackError.unknownFrameRate }
            // Once playback has settled on the first picture, its timestamp is the frame-0 origin.
            try await waitForPlaybackRestart()

            frameRate = fps
            frameDuration = Self.frameDuration(for: fps)
            naturalSize = size
            timeOrigin = max(0, client.double("time-pos") ?? 0)
            duration = CMTime(seconds: max(0, (client.double("duration") ?? 0) - timeOrigin), preferredTimescale: Self.timescale)
            timePosition = client.double("time-pos") ?? 0
            isPaused = client.flag("pause") ?? true
            isAtEnd = false
            isFileLoaded = true
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
        failPendingLoad(with: PlaybackError.noMediaLoaded)
        if let client {
            client.run(["stop"])
            // `pause` persists across files, so a file opened after playback would otherwise autoplay.
            _ = try? client.setProperty("pause", flag: true)
        }
        stopReverse()
        isFileLoaded = false
        timePosition = 0
        timeOrigin = 0
        pendingSeekSeconds = nil
        isPaused = true
        speed = 1
        isAtEnd = false
        frameRate = 0
        naturalSize = .zero
        duration = .invalid
        frameDuration = .invalid
    }

    private func waitForFileLoaded() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            loadContinuation = continuation
            startLoadTimeout()
        }
    }

    /// The display size only becomes known once mpv has configured video output for this file.
    private func waitForVideoSize() async throws -> CGSize {
        if reconfigsSinceLoad > 0, let size = currentVideoSize() {
            loadTimeout?.cancel()
            return size
        }
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CGSize, Error>) in
            videoSizeContinuation = continuation
            startLoadTimeout()
        }
    }

    /// Resolves immediately if the restart already happened while the earlier waits were running.
    private func waitForPlaybackRestart() async throws {
        if restartsSinceLoad > 0 {
            loadTimeout?.cancel()
            return
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            restartContinuation = continuation
            startLoadTimeout()
        }
    }

    /// Distinguishes "no video at all" from "video mpv has no decoder for" using the track list.
    private func videoTrackError(_ client: MPVClient) -> PlaybackError {
        let count = Int(client.int("track-list/count") ?? 0)
        for index in 0..<count where client.string("track-list/\(index)/type") == "video" {
            return .unsupportedCodec(client.string("track-list/\(index)/codec") ?? "unknown")
        }
        return .noVideoTrack
    }

    private func startLoadTimeout() {
        loadTimeout?.cancel()
        loadTimeout = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: MPVEngine.loadTimeoutNanoseconds)
            guard !Task.isCancelled else { return }
            self?.failPendingLoad(with: PlaybackError.loadTimedOut)
        }
    }

    private func failPendingLoad(with error: Error) {
        loadTimeout?.cancel()
        loadTimeout = nil
        loadContinuation?.resume(throwing: error)
        loadContinuation = nil
        videoSizeContinuation?.resume(throwing: error)
        videoSizeContinuation = nil
        restartContinuation?.resume(throwing: error)
        restartContinuation = nil
    }

    private func resumeVideoSizeIfKnown() {
        guard videoSizeContinuation != nil, reconfigsSinceLoad > 0, let size = currentVideoSize() else { return }
        loadTimeout?.cancel()
        videoSizeContinuation?.resume(returning: size)
        videoSizeContinuation = nil
    }

    private func currentVideoSize() -> CGSize? {
        guard let client,
              let width = client.int("dwidth"), let height = client.int("dheight"),
              width > 0, height > 0 else { return nil }
        // mpv normally applies a file's rotation in its filter chain, so dwidth/dheight already
        // describe the rotated picture. Only a rotation left for the renderer still needs a swap.
        let rotation = client.int("video-out-params/rotate") ?? 0
        let size = CGSize(width: CGFloat(width), height: CGFloat(height))
        return rotation % 180 == 90 ? CGSize(width: size.height, height: size.width) : size
    }

    // MARK: - Events

    private func handle(_ event: MPVClient.Event) {
        switch event {
        case .fileLoaded:
            loadContinuation?.resume()
            loadContinuation = nil
        case .endOfFile(let error):
            guard let error else { return }
            failPendingLoad(with: PlaybackError.loadFailed(underlying: MPVError(code: error, operation: "Opening the file")))
        case .videoReconfigured:
            reconfigsSinceLoad += 1
            resumeVideoSizeIfKnown()
        case .playbackRestarted:
            restartsSinceLoad += 1
            restartContinuation?.resume()
            restartContinuation = nil
            loadTimeout?.cancel()
            pendingSeekSeconds = nil
            reverseSeekInFlight = false
            if isFileLoaded {
                onTimeUpdate?(currentTime)
            }
        case .propertyChanged(let name, let value):
            handlePropertyChange(name, value)
        case .shutdown:
            isFileLoaded = false
        }
    }

    private func handlePropertyChange(_ name: String, _ value: MPVClient.PropertyValue) {
        switch (name, value) {
        case ("time-pos", .double(let seconds)):
            timePosition = seconds
            pendingSeekSeconds = nil
            if isFileLoaded {
                onTimeUpdate?(currentTime)
            }
        case ("pause", .flag(let paused)):
            isPaused = paused
            if isFileLoaded {
                onStateChange?()
            }
        case ("speed", .double(let newSpeed)):
            speed = newSpeed
            if isFileLoaded { onStateChange?() }
        case ("eof-reached", .flag(let atEnd)):
            isAtEnd = atEnd
        case ("duration", .double(let seconds)):
            if isFileLoaded {
                duration = CMTime(seconds: max(0, seconds - timeOrigin), preferredTimescale: Self.timescale)
                onStateChange?()
            }
        case ("dwidth", _), ("dheight", _):
            resumeVideoSizeIfKnown()
        default:
            break
        }
    }

    // MARK: - Transport

    func play() {
        guard isFileLoaded else { return }
        stopReverse()
        if isAtEnd || (duration.isNumeric && currentTime >= duration) {
            seek(to: .zero)
        }
        speed = 1
        set("speed", double: 1)
        set("pause", flag: false)
    }

    func pause() {
        guard isFileLoaded else { return }
        let wasReversing = isReversing
        stopReverse()
        set("pause", flag: true)
        if wasReversing {
            onStateChange?()
        }
    }

    /// Lands on the frame that is on screen at `time`, matching AVFoundation's zero-tolerance seek.
    /// mpv's exact seek instead shows the first frame *at or after* the target (within 5 ms), so
    /// the request is snapped to that frame's own timestamp before it is sent.
    func seek(to time: CMTime) {
        guard isFileLoaded, time.isNumeric, frameRate > 0 else { return }
        let frameIndex = Timecode.frameCount(seconds: time.seconds, frameRate: frameRate)
        seek(toSeconds: Timecode.seconds(frameCount: frameIndex, frameRate: frameRate), exact: true)
    }

    /// Keyframe seeks are used while the scrubber is dragged; the release lands exactly.
    private func seek(toSeconds seconds: Double, exact: Bool) {
        guard isFileLoaded else { return }
        var target = max(0, seconds)
        if duration.isNumeric {
            target = min(target, duration.seconds)
        }
        pendingSeekSeconds = target
        client?.run(["seek", String(target + timeOrigin), exact ? "absolute+exact" : "absolute+keyframes"])
        onTimeUpdate?(currentTime)
    }

    func stepFrames(_ count: Int) {
        guard isFileLoaded, count != 0, let client else { return }
        stopReverse()
        set("pause", flag: true)
        // Forward steps play the frames out (silently); mpv can only step backwards with an exact seek.
        client.run(count > 0 ? ["frame-step", String(count), "mute"] : ["frame-step", String(count), "seek"])
    }

    func setRate(_ rate: Float) throws {
        guard isFileLoaded else { return }
        if rate == 0 {
            pause()
            return
        }
        let magnitude = Double(abs(rate))
        guard magnitude >= 0.01, magnitude <= 100 else { throw PlaybackError.unsupportedRate(rate) }
        speed = magnitude
        if rate < 0 {
            startReverse()
        } else {
            stopReverse()
            set("speed", double: magnitude)
            set("pause", flag: false)
        }
        onStateChange?()
    }

    // MARK: - Reverse shuttle

    private func startReverse() {
        set("pause", flag: true)
        isReversing = true
        reverseSeekInFlight = false
        reverseLastTick = Date()
        reverseTimer?.invalidate()
        // Ticks are cheap; the seek pacing below decides how far each one moves.
        let interval = max(1 / 120, 1 / (frameRate * speed))
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.reverseTick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        reverseTimer = timer
    }

    private func stopReverse() {
        reverseTimer?.invalidate()
        reverseTimer = nil
        isReversing = false
        reverseSeekInFlight = false
    }

    /// Seeks back by however many frames the wall clock says are owed since the last seek, so a
    /// slow decode skips frames rather than falling behind the requested speed.
    private func reverseTick() {
        guard isReversing, isFileLoaded, frameRate > 0 else { return }
        let now = Date()
        if reverseSeekInFlight {
            // A stuck seek should never freeze the shuttle.
            guard now.timeIntervalSince(reverseLastTick) > 2 else { return }
            reverseSeekInFlight = false
        }
        let owedFrames = now.timeIntervalSince(reverseLastTick) * frameRate * speed
        guard owedFrames >= 1 else { return }
        let frames = Int(owedFrames)
        reverseLastTick = now
        let current = Timecode.frameCount(seconds: currentTime.seconds, frameRate: frameRate)
        let target = max(0, current - frames)
        reverseSeekInFlight = true
        seek(toSeconds: Timecode.seconds(frameCount: target, frameRate: frameRate), exact: true)
        if target == 0 {
            pause()
        }
    }

    // MARK: - Frame capture

    func captureCurrentFrame() async throws -> CGImage {
        guard isFileLoaded, let client else { throw PlaybackError.noMediaLoaded }
        if let image = renderLayer?.captureFrame(width: Int(naturalSize.width), height: Int(naturalSize.height)) {
            return image
        }
        do {
            let frame = try await Task.detached(priority: .userInitiated) { try client.rawScreenshot() }.value
            guard let image = Self.image(from: frame) else {
                throw PlaybackError.frameCaptureFailed(underlying: nil)
            }
            return image
        } catch let error as PlaybackError {
            throw error
        } catch {
            throw PlaybackError.frameCaptureFailed(underlying: error)
        }
    }

    private nonisolated static func image(from frame: MPVClient.RawFrame) -> CGImage? {
        let alpha: CGImageAlphaInfo
        let byteOrder: CGBitmapInfo
        switch frame.format {
        case "bgr0", "bgra":
            (alpha, byteOrder) = (.noneSkipFirst, .byteOrder32Little)
        case "rgba", "rgb0":
            (alpha, byteOrder) = (.noneSkipLast, .byteOrder32Big)
        default:
            return nil
        }
        guard let provider = CGDataProvider(data: frame.data as CFData) else { return nil }
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        return CGImage(
            width: frame.width, height: frame.height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: frame.stride, space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: alpha.rawValue | byteOrder.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )
    }

    // MARK: - Time

    /// mpv reports the displayed frame's own timestamp, which Matroska and friends store at
    /// millisecond precision. Rounding to the nearest frame recovers the exact frame index.
    private func frameAlignedTime(_ seconds: Double) -> CMTime {
        guard frameRate > 0, frameDuration.isNumeric else {
            return CMTime(seconds: max(0, seconds), preferredTimescale: Self.timescale)
        }
        let frameIndex = (seconds * frameRate).rounded()
        guard frameIndex >= 0, frameIndex < Double(Int32.max) else {
            return CMTime(seconds: max(0, seconds), preferredTimescale: Self.timescale)
        }
        return CMTimeMultiply(frameDuration, multiplier: Int32(frameIndex))
    }

    /// Integer and NTSC rates are exact multiples of 1/1001 s (25 → 1001/25025, 29.97 → 1001/30000),
    /// so those frame durations carry no rounding error at all.
    private nonisolated static func frameDuration(for frameRate: Double) -> CMTime {
        let scaled = frameRate * 1001
        if abs(scaled - scaled.rounded()) < 0.01, scaled.rounded() < Double(Int32.max) {
            return CMTime(value: 1001, timescale: CMTimeScale(scaled.rounded()))
        }
        return CMTime(value: CMTimeValue((Double(timescale) / frameRate).rounded()), timescale: timescale)
    }

    // MARK: - Property helpers

    /// Property writes on a live core only fail for names that are fixed at compile time.
    private func set(_ name: String, double value: Double) {
        _ = try? client?.setProperty(name, double: value)
    }

    private func set(_ name: String, flag value: Bool) {
        _ = try? client?.setProperty(name, flag: value)
    }

    private func set(_ name: String, string value: String) {
        _ = try? client?.setProperty(name, string: value)
    }
}
