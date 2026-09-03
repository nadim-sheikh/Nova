import AppKit
import CoreMedia

/// Hosts the engine's video view, owns file opening, keyboard transport, frame copying, the
/// expandable timeline, and the title-bar readout. Talks to the engine only through `PlaybackEngine`.
final class PlayerViewController: NSViewController, NSMenuItemValidation, NSMenuDelegate {
    private let engine: any PlaybackEngine
    private let settings = AppSettings.shared
    private let keyBindings = KeyBindings.shared
    private var shuttle = ShuttleController()
    private let dropView = DropTargetView(frame: NSRect(x: 0, y: 0, width: 960, height: 540))
    private let toast = ToastView()
    private let panel = PlayerControlPanel()
    private var isTimelineExpanded = false
    /// Last seen values of the two playhead settings, so a change can be shown as it is made.
    private var lastTimelineIsFull = AppSettings.shared.timelineIsFull
    private var lastPlayheadIsTimecode = AppSettings.shared.opensWithTimecodePlayhead
    private var controlsHideTask: Task<Void, Never>?
    private var currentFileName: String?
    private var eventMonitors: [Any] = []
    private var settingsObserver: NSObjectProtocol?

    var hasMedia: Bool { currentFileName != nil }

    init(engine: any PlaybackEngine) {
        self.engine = engine
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        eventMonitors.forEach { NSEvent.removeMonitor($0) }
        if let settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
        }
    }

    // MARK: - View lifecycle

    override func loadView() {
        view = dropView

        let videoView = engine.videoView
        videoView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(videoView)
        panel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(panel)
        toast.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(toast)

        NSLayoutConstraint.activate([
            videoView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            videoView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            videoView.topAnchor.constraint(equalTo: view.topAnchor),
            videoView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            panel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            panel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            panel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),
            toast.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            toast.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            // Keeps the confirmation inside even a very small window; the text truncates instead.
            toast.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 12),
            toast.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -12),
        ])

        let contextMenu = PlayerContextMenu.build(target: self)
        // Set on both views: a right-click lands on one of AVPlayerView's internal subviews and
        // walks up until a view supplies a menu.
        videoView.menu = contextMenu
        view.menu = contextMenu
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        dropView.onDropURL = { [weak self] url in self?.open(url) }
        dropView.onMouseMoved = { [weak self] in self?.revealControls() }
        panel.onPlayPause = { [weak self] in self?.togglePlayPause() }
        panel.onScrub = { [weak self] seconds, isFinal in self?.scrub(toSeconds: seconds, isFinal: isFinal) }
        panel.onVolume = { [weak self] volume in self?.engine.volume = volume }
        panel.onToggleTimeline = { [weak self] in self?.toggleTimeline() }
        panel.onToggleFullScreen = { [weak self] in self?.view.window?.toggleFullScreen(nil) }
        panel.onTimelineScrub = { [weak self] frame in self?.seek(toFrame: frame) }
        panel.onCopyTimecode = { [weak self] in self?.copyCurrentTimecode() }
        panel.onPasteTimecode = { [weak self] in self?.jumpToPastedTimecode() }
        panel.onEnterTimecode = { [weak self] text in self?.jump(toTimecodeText: text) }
        panel.onToggleSize = { [weak self] in self?.settings.timelineIsFull.toggle() }
        panel.isFull = settings.timelineIsFull
        engine.onTimeUpdate = { [weak self] _ in
            self?.updateTitle()
            self?.updateReadouts()
        }
        engine.onStateChange = { [weak self] in
            self?.updateTitle()
            self?.updateReadouts()
        }
        installEventMonitors()
        settingsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.applySettings() }
        }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        updateTitle()
    }

    // MARK: - Opening files

    func promptForFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = engine.supportedContentTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        let finish: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.open(url)
        }
        if let window = view.window {
            panel.beginSheetModal(for: window, completionHandler: finish)
        } else {
            finish(panel.runModal())
        }
    }

    func open(_ url: URL) {
        do {
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw PlaybackError.fileNotFound(url)
            }
            guard SupportedVideoTypes.isVideoFile(url, acceptedTypes: engine.supportedContentTypes) else {
                throw PlaybackError.notAVideoFile(url.pathExtension)
            }
        } catch {
            presentError(error, title: "Couldn't open “\(url.lastPathComponent)”")
            return
        }

        Task { @MainActor in
            do {
                try await engine.load(url: url)
                currentFileName = url.lastPathComponent
                engine.isLooping = settings.loopPlayback
                if settings.fitWindowToVideo {
                    fitWindow(to: engine.naturalSize)
                }
                applyAspectLock()
                if settings.autoplayOnOpen {
                    engine.play()
                }
            } catch {
                currentFileName = nil
                presentError(error, title: "Couldn't open “\(url.lastPathComponent)”")
            }
            updateTitle()
            updateReadouts()
            revealControls()
            // Each file opens with the playhead chosen in Settings; T still switches at any time.
            let wantsTimeline = hasMedia && settings.opensWithTimecodePlayhead
            lastPlayheadIsTimecode = settings.opensWithTimecodePlayhead
            if wantsTimeline != isTimelineExpanded {
                toggleTimeline()
            }
        }
    }

    // MARK: - Expanded timeline

    /// Slides the full-width scrubber over the video, or puts it away again.
    func toggleTimeline() {
        guard hasMedia || isTimelineExpanded else { return }
        isTimelineExpanded.toggle()
        updateReadouts()
        panel.setTimelineExpanded(isTimelineExpanded)
        revealControls()
    }

    @objc func toggleTimeline(_ sender: Any?) {
        toggleTimeline()
    }

    /// Refreshes the transport bar and, when it is open, the timeline.
    private func updateReadouts() {
        let time = engine.currentTime
        let duration = engine.duration
        panel.updateTransport(
            time: time.isNumeric ? time.seconds : 0,
            duration: duration.isNumeric ? duration.seconds : 0,
            isPlaying: engine.isPlaying,
            volume: engine.volume
        )
        guard isTimelineExpanded, hasMedia, engine.frameRate > 0 else { return }
        let frameCount = duration.isNumeric ? Timecode.frameCount(seconds: duration.seconds, frameRate: engine.frameRate) : 0
        panel.updateTimeline(frameIndex: currentFrameIndex(), frameCount: frameCount, frameRate: engine.frameRate)
    }

    /// Coarse seeking from the transport bar: keyframes while dragging, exact on release.
    private func scrub(toSeconds seconds: Double, isFinal: Bool) {
        guard hasMedia, engine.frameRate > 0 else { return }
        seek(toFrame: Timecode.frameCount(seconds: seconds, frameRate: engine.frameRate))
    }

    /// Frame-exact seek; lands mid-frame so rounding can't slip to the frame before.
    private func seek(toFrame frame: Int) {
        guard engine.frameRate > 0 else { return }
        let seconds = Timecode.midFrameSeconds(frameCount: frame, frameRate: engine.frameRate)
        engine.seek(to: CMTime(seconds: seconds, preferredTimescale: 600_000))
    }

    /// Shows the transport bar for a moment after the pointer moves, unless it is being used.
    private func revealControls() {
        guard hasMedia else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 1
        }
        controlsHideTask?.cancel()
        controlsHideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled, let self else { return }
            if self.isPointerOverControls || self.panel.isScrubbing || self.panel.isEditingTimecode {
                self.revealControls()
                return
            }
            self.hideControls()
        }
    }

    private func hideControls() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            panel.animator().alphaValue = 0
        }
    }

    private var isPointerOverControls: Bool {
        guard let window = view.window else { return false }
        let point = view.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        return panel.frame.insetBy(dx: 0, dy: -8).contains(point)
    }

    // MARK: - Frame copying

    /// Puts the exact frame on screen onto the clipboard as PNG and TIFF, at full resolution.
    func copyCurrentFrame() {
        guard hasMedia else { return }
        Task { @MainActor in
            do {
                let cgImage = try await engine.captureCurrentFrame()
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                let bitmap = NSBitmapImageRep(cgImage: cgImage)
                pasteboard.declareTypes([.png, .tiff], owner: nil)
                if let png = bitmap.representation(using: .png, properties: [:]) {
                    pasteboard.setData(png, forType: .png)
                }
                pasteboard.setData(bitmap.tiffRepresentation, forType: .tiff)
                toast.show("Frame copied")
            } catch {
                presentError(error, title: "Couldn't copy the frame")
            }
        }
    }

    @objc func copy(_ sender: Any?) {
        copyCurrentFrame()
    }

    @objc func copyFrame(_ sender: Any?) {
        copyCurrentFrame()
    }

    @objc func playPauseFromMenu(_ sender: Any?) {
        togglePlayPause()
    }

    // MARK: - Timecode copying

    /// Puts the current SMPTE timecode on the clipboard as plain text.
    func copyCurrentTimecode() {
        guard let timecode = currentTimecode() else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(timecode.smpteString, forType: .string)
        toast.show("Timecode copied: \(timecode.smpteString)")
    }

    /// Reads a timecode from the clipboard and jumps to that frame, keeping the play state.
    func jumpToPastedTimecode() {
        guard hasMedia, engine.frameRate > 0 else { return }
        guard let text = NSPasteboard.general.string(forType: .string) else {
            presentError(PlaybackError.noTimecodeOnClipboard, title: "Couldn't paste a timecode")
            return
        }
        jump(toTimecodeText: text, failureTitle: "Couldn't paste a timecode")
    }

    /// Parses typed or pasted text as a timecode and jumps to that frame.
    func jump(toTimecodeText text: String, failureTitle: String = "Couldn't read that timecode") {
        guard hasMedia, engine.frameRate > 0 else { return }
        guard let timecode = TimecodeParser.parse(text, frameRate: engine.frameRate) else {
            let shown = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
            presentError(PlaybackError.invalidTimecode(shown), title: failureTitle)
            return
        }
        seek(toFrame: timecode.frameCount(frameRate: engine.frameRate))
        toast.show("Jumped to \(timecode.smpteString)")
    }

    @objc func copyTimecode(_ sender: Any?) {
        copyCurrentTimecode()
    }

    @objc func pasteTimecode(_ sender: Any?) {
        jumpToPastedTimecode()
    }

    // MARK: - Saving a frame

    /// Captures the frame on screen, then asks where to save it.
    func saveCurrentFrame() {
        guard hasMedia else { return }
        let fileName = FrameExporter.suggestedFileName(
            videoName: currentFileName, frameNumber: currentFrameIndex() + settings.frameNumberBase
        )
        Task { @MainActor in
            do {
                let image = try await engine.captureCurrentFrame()
                presentSavePanel(for: image, suggesting: fileName)
            } catch {
                presentError(error, title: "Couldn't save the frame")
            }
        }
    }

    @objc func saveFrame(_ sender: Any?) {
        saveCurrentFrame()
    }

    private func presentSavePanel(for image: CGImage, suggesting fileName: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = FrameExporter.contentTypes
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = fileName
        panel.message = "Choose where to save this frame."
        // No directoryURL is set, so the panel reopens wherever the last frame was saved.
        let finish: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.write(image, to: url)
        }
        if let window = view.window {
            panel.beginSheetModal(for: window, completionHandler: finish)
        } else {
            finish(panel.runModal())
        }
    }

    private func write(_ image: CGImage, to url: URL) {
        guard let data = FrameExporter.data(for: image, fileExtension: url.pathExtension) else {
            presentError(PlaybackError.frameSaveFailed(underlying: nil), title: "Couldn't save the frame")
            return
        }
        do {
            try data.write(to: url)
            toast.show("Frame saved")
        } catch {
            presentError(PlaybackError.frameSaveFailed(underlying: error), title: "Couldn't save the frame")
        }
    }

    private func presentError(_ error: Error, title: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        if let window = view.window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    // MARK: - Settings

    private func applySettings() {
        engine.isLooping = settings.loopPlayback
        panel.isFull = settings.timelineIsFull
        // A playhead setting is about what the player looks like, so show the result at once
        // rather than waiting for the next file.
        if settings.timelineIsFull != lastTimelineIsFull {
            lastTimelineIsFull = settings.timelineIsFull
            if hasMedia, !isTimelineExpanded {
                toggleTimeline()
            } else {
                revealControls()
            }
        }
        if settings.opensWithTimecodePlayhead != lastPlayheadIsTimecode {
            lastPlayheadIsTimecode = settings.opensWithTimecodePlayhead
            if hasMedia, settings.opensWithTimecodePlayhead != isTimelineExpanded {
                toggleTimeline()
            }
        }
        updateReadouts()
        applyAspectLock()
        updateTitle()
    }

    // MARK: - Window sizing

    /// Locks the window's content to the video's aspect ratio, or lifts the lock when disabled,
    /// and keeps the minimum window size in proportion so portrait clips can shrink too.
    private func applyAspectLock() {
        guard let window = view.window else { return }
        let size = engine.naturalSize
        if settings.lockAspectRatio, size.width > 0, size.height > 0 {
            window.contentAspectRatio = size
            window.contentMinSize = Self.minimumContentSize(forAspectOf: size)
        } else {
            // Setting resize increments is AppKit's way of clearing an aspect-ratio constraint.
            window.contentResizeIncrements = NSSize(width: 1, height: 1)
            window.contentMinSize = NSSize(width: Self.minimumWidth, height: Self.minimumHeight)
        }
    }

    private static let minimumWidth: CGFloat = 280
    private static let minimumHeight: CGFloat = 160

    /// The smallest size matching the video's shape that still satisfies both minimums.
    private static func minimumContentSize(forAspectOf size: CGSize) -> NSSize {
        let scale = max(minimumWidth / size.width, minimumHeight / size.height)
        return NSSize(width: (size.width * scale).rounded(.up), height: (size.height * scale).rounded(.up))
    }

    /// Resizes the window to the video's natural size, scaled down to fit the screen.
    private func fitWindow(to size: CGSize) {
        guard let window = view.window, size.width > 0, size.height > 0 else { return }

        let available = (window.screen ?? NSScreen.main)?.visibleFrame.size ?? CGSize(width: 1920, height: 1080)
        let scale = min(1, (available.width * 0.9) / size.width, (available.height * 0.9) / size.height)
        let contentSize = CGSize(width: (size.width * scale).rounded(.down), height: (size.height * scale).rounded(.down))

        let frameSize = window.frameRect(forContentRect: NSRect(origin: .zero, size: contentSize)).size
        var frame = window.frame
        frame.origin.x = window.frame.midX - frameSize.width / 2
        frame.origin.y = window.frame.midY - frameSize.height / 2
        frame.size = frameSize
        frame = window.constrainFrameRect(frame, to: window.screen)
        window.setFrame(frame, display: true, animate: true)
    }

    // MARK: - Title bar

    private func updateTitle() {
        guard let window = view.window else { return }
        guard let fileName = currentFileName, let timecode = currentTimecode() else {
            window.title = "Nova"
            return
        }
        let frameIndex = currentFrameIndex()

        var parts = [timecode.smpteString]
        if settings.showFrameNumber {
            parts.append("Frame \(frameIndex + settings.frameNumberBase)")
        }
        if settings.showShuttleSpeed, let speed = ShuttleController.speedLabel(for: engine.rate) {
            parts.append(speed)
        }
        if settings.showFileName {
            parts.append(fileName)
        }
        window.title = Self.fittedTitle(from: parts, availableWidth: Self.titleWidth(in: window))
    }

    /// A title bar can't scroll or wrap, so on a narrow window drop the least important parts
    /// (file name first, then speed, then the frame number) until the text fits.
    private static func fittedTitle(from parts: [String], availableWidth: CGFloat) -> String {
        var parts = parts
        while parts.count > 1 {
            let candidate = parts.joined(separator: titleSeparator)
            if textWidth(candidate) <= availableWidth { return candidate }
            parts.removeLast()
        }
        return parts.first ?? "Nova"
    }

    private static let titleSeparator = "   ·   "
    private static let titleFont = NSFont.titleBarFont(ofSize: NSFont.systemFontSize)

    private static func textWidth(_ text: String) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: titleFont]).width
    }

    /// Room for the title, leaving space for the window buttons and the standard side padding.
    private static func titleWidth(in window: NSWindow) -> CGFloat {
        max(80, window.frame.width - 180)
    }

    private func currentFrameIndex() -> Int {
        let time = engine.currentTime
        let seconds = time.isNumeric ? time.seconds : 0
        return Timecode.frameCount(seconds: seconds, frameRate: engine.frameRate)
    }

    private func currentTimecode() -> Timecode? {
        guard hasMedia, engine.frameRate > 0 else { return nil }
        return Timecode(frameCount: currentFrameIndex(), frameRate: engine.frameRate)
    }

    // MARK: - Keyboard

    /// Local monitors see key events before AVPlayerView does, so consumed keys never double-trigger
    /// the control bar's own shortcuts. Events for other windows (e.g. the open panel) pass through.
    private func installEventMonitors() {
        let keyDown = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let consumed = MainActor.assumeIsolated { () -> Bool in
                guard let self, event.window === self.view.window, self.hasMedia else { return false }
                return self.handleKeyDown(event)
            }
            return consumed ? nil : event
        }
        // Second path to the same reveal: tracking areas can be disabled while another app is
        // frontmost, and this keeps the bar reachable in every case.
        let mouseMoved = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, event.window === self.view.window else { return }
                self.revealControls()
            }
            return event
        }
        let keyUp = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
            let consumed = MainActor.assumeIsolated { () -> Bool in
                guard let self, event.window === self.view.window, self.hasMedia else { return false }
                return self.handleKeyUp(event)
            }
            return consumed ? nil : event
        }
        eventMonitors = [keyDown, keyUp, mouseMoved].compactMap { $0 }
    }

    /// True while the timecode field owns the keyboard; shortcuts stand aside so letters reach it.
    private var isTypingInField: Bool {
        (view.window?.firstResponder as? NSTextView)?.isFieldEditor == true
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        guard !isTypingInField else { return false }
        // Escape puts the timeline away; otherwise it keeps its usual meaning (leaving full screen).
        if event.keyCode == 53, isTimelineExpanded {
            toggleTimeline()
            return true
        }
        guard let action = keyBindings.action(matching: KeyCombo(event: event)) else { return false }
        perform(action, event: event)
        return true
    }

    private func handleKeyUp(_ event: NSEvent) -> Bool {
        guard !isTypingInField,
              let action = keyBindings.shuttleAction(forKeyCode: event.keyCode),
              let key = shuttleKey(for: action) else { return false }
        apply(shuttle.keyUp(key))
        return true
    }

    private func perform(_ action: PlayerAction, event: NSEvent) {
        // Any transport key also brings the bar back, so it is never out of reach.
        revealControls()
        switch action {
        case .playPause:
            if !event.isARepeat { togglePlayPause() }
        case .seekBackward:
            seek(bySeconds: -settings.seekStepSeconds)
        case .seekForward:
            seek(bySeconds: settings.seekStepSeconds)
        case .stepBackward:
            engine.stepFrames(-settings.frameStepCount)
        case .stepForward:
            engine.stepFrames(settings.frameStepCount)
        case .volumeUp:
            adjustVolume(by: settings.volumeStep)
        case .volumeDown:
            adjustVolume(by: -settings.volumeStep)
        case .toggleTimeline:
            if !event.isARepeat { toggleTimeline() }
        case .shuttleReverse, .shuttlePause, .shuttleForward:
            guard let key = shuttleKey(for: action) else { return }
            shuttle.rampSteps = settings.shuttleRampSteps
            shuttle.slowRate = settings.slowMotionRate
            apply(shuttle.keyDown(key, isRepeat: event.isARepeat, currentRate: engine.rate))
        }
    }

    private func shuttleKey(for action: PlayerAction) -> ShuttleController.Key? {
        switch action {
        case .shuttleReverse: return .j
        case .shuttlePause: return .k
        case .shuttleForward: return .l
        default: return nil
        }
    }

    // MARK: - Transport

    private func togglePlayPause() {
        if engine.isPlaying {
            engine.pause()
        } else {
            engine.play()
        }
    }

    private func seek(bySeconds delta: Double) {
        let current = engine.currentTime
        guard current.isNumeric else { return }
        let offset = CMTime(seconds: delta, preferredTimescale: max(current.timescale, 600))
        engine.seek(to: CMTimeAdd(current, offset))
    }

    private func adjustVolume(by delta: Float) {
        engine.volume = ((engine.volume + delta) * 100).rounded() / 100
        updateReadouts()
        revealControls()
    }

    // MARK: - Menus

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(copy(_:)), #selector(copyFrame(_:)), #selector(saveFrame(_:)),
             #selector(playPauseFromMenu(_:)), #selector(copyTimecode(_:)):
            return hasMedia
        case #selector(pasteTimecode(_:)):
            return hasMedia && NSPasteboard.general.canReadObject(forClasses: [NSString.self], options: nil)
        case #selector(toggleTimeline(_:)):
            menuItem.title = isTimelineExpanded ? "Collapse Timeline" : "Expand Timeline"
            return hasMedia || isTimelineExpanded
        default:
            return true
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        for item in menu.items where item.action == #selector(playPauseFromMenu(_:)) {
            item.title = engine.isPlaying ? "Pause" : "Play"
        }
    }

    private func apply(_ command: ShuttleController.Command?) {
        guard let command else { return }
        switch command {
        case .pause:
            engine.pause()
        case .setRate(let rate):
            do {
                try engine.setRate(rate)
            } catch {
                presentError(error, title: "Playback speed not available")
            }
        }
    }
}
