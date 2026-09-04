import AppKit
import CoreMedia

// Exercises Nova's engines and the timecode copy/paste flow in a real window, reading the
// burned-in frame numbers back with Vision OCR to confirm frame accuracy.

var failures = 0
var passes = 0
func check(_ condition: Bool, _ name: String, _ detail: @autoclosure () -> String = "") {
    if condition { passes += 1; print("PASS \(name) \(detail())") } else { failures += 1; print("FAIL \(name) \(detail())") }
}

/// Reads the 10-bit frame counter the test clips carry as a strip of white/black boxes
/// (box k at x = 20 + 70k, y = 15, 60x60 in a 1280-wide source). Works on any scaled copy.
func decodeFrameNumber(_ image: CGImage, videoRect: CGRect, sourceWidth: CGFloat) -> Int? {
    let width = image.width, height = image.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    let scale = videoRect.width / sourceWidth
    func brightness(_ x: Int, _ y: Int) -> Int {
        guard x >= 0, y >= 0, x < width, y < height else { return -1 }
        let i = (y * width + x) * 4
        return (Int(pixels[i]) + Int(pixels[i + 1]) + Int(pixels[i + 2])) / 3
    }
    var value = 0
    for bit in 0..<10 {
        // Bitmap context memory is top-down, matching the image's own orientation.
        let cx = Int(videoRect.minX + (20 + CGFloat(bit) * 70 + 30) * scale)
        let cy = Int(videoRect.minY + 45 * scale)
        var sum = 0, count = 0
        for dx in -2...2 { for dy in -2...2 {
            let b = brightness(cx + dx, cy + dy)
            if b >= 0 { sum += b; count += 1 }
        } }
        guard count > 0 else { return nil }
        let average = sum / count
        if average > 160 { value |= 1 << bit } else if average > 90 { return nil }
    }
    return value
}

/// Decodes a full-resolution capture from the engine.
func captureFrameNumber(_ image: CGImage) -> String {
    decodeFrameNumber(image, videoRect: CGRect(x: 0, y: 0, width: image.width, height: image.height),
                      sourceWidth: CGFloat(image.width)).map(String.init) ?? "decode-failed"
}

func windowScreenshot(_ window: NSWindow) -> CGImage? {
    let path = FileManager.default.temporaryDirectory.appendingPathComponent("harness-shot.png").path
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    task.arguments = ["-x", "-o", "-l", String(window.windowNumber), path]
    try? task.run()
    task.waitUntilExit()
    guard let image = NSImage(contentsOfFile: path) else { return nil }
    return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
}

/// The window is 16:9 and the video fills its content area below the title bar.
func onScreenFrameNumber(_ window: NSWindow, sourceWidth: CGFloat) -> String {
    guard let shot = windowScreenshot(window) else { return "no-shot" }
    let width = CGFloat(shot.width)
    let videoHeight = width * 9 / 16
    let rect = CGRect(x: 0, y: CGFloat(shot.height) - videoHeight, width: width, height: videoHeight)
    return decodeFrameNumber(shot, videoRect: rect, sourceWidth: sourceWidth).map(String.init) ?? "decode-failed"
}

func sleep(_ seconds: Double) async {
    try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
}

@MainActor
func frameIndex(_ engine: any PlaybackEngine) -> Int {
    Timecode.frameCount(seconds: engine.currentTime.seconds, frameRate: engine.frameRate)
}

@MainActor
var captureFailures = 0
@MainActor
func captureNumber(_ engine: any PlaybackEngine) async -> String {
    do {
        let image = try await engine.captureCurrentFrame()
        let result = captureFrameNumber(image)
        if result == "decode-failed", captureFailures < 2 {
            captureFailures += 1
            let rep = NSBitmapImageRep(cgImage: image)
            if let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: "shots/capture-failed-\(captureFailures).png"))
            }
            print("     capture image \(image.width)x\(image.height) bytesPerRow=\(image.bytesPerRow) saved")
        }
        return result
    } catch {
        return "capture-failed(\(error.localizedDescription))"
    }
}
@MainActor
func onScreenNumber(_ window: NSWindow, _ engine: any PlaybackEngine) -> String {
    onScreenFrameNumber(window, sourceWidth: engine.naturalSize.width)
}

/// Window captures can hand back the previously composited surface, so the reading is polled
/// until it agrees with the engine. The time taken is reported: a window that never settles is
/// a real fault, one that settles in a frame or two is the capture lagging.
@MainActor
func onScreenNumber(_ window: NSWindow, _ engine: any PlaybackEngine, expecting expected: String) async -> (value: String, seconds: Double) {
    // A covered window stops being redrawn, so bring it to the front before reading it.
    NSApp.activate(ignoringOtherApps: true)
    window.orderFrontRegardless()
    let start = Date()
    var value = onScreenNumber(window, engine)
    while value != expected, Date().timeIntervalSince(start) < 1.5 {
        await sleep(0.2)
        value = onScreenNumber(window, engine)
    }
    return (value, Date().timeIntervalSince(start))
}
func saveShot(_ label: String) {
    let source = FileManager.default.temporaryDirectory.appendingPathComponent("harness-shot.png")
    let target = URL(fileURLWithPath: "shots/\(label).png")
    try? FileManager.default.removeItem(at: target)
    try? FileManager.default.copyItem(at: source, to: target)
}

@MainActor
func testEngine(_ engine: any PlaybackEngine, window: NSWindow, url: URL, expectRotated: Bool) async {
    let name = url.lastPathComponent
    print("=== \(name)")
    let start = Date()
    do {
        try await engine.load(url: url)
    } catch {
        check(false, "\(name) load", error.localizedDescription)
        return
    }
    let loadTime = Date().timeIntervalSince(start)
    check(loadTime < 3, "\(name) load time", String(format: "%.2fs fps=%.3f size=%@ duration=%.2f", loadTime, engine.frameRate, NSStringFromSize(engine.naturalSize), engine.duration.seconds))
    // Each clip's real size, so a stale size carried over from the previous file is caught.
    let expected: CGSize = name.contains("rot90") ? CGSize(width: 720, height: 1280)
        : name.contains("1080p") ? CGSize(width: 1920, height: 1080)
        : CGSize(width: 1280, height: 720)
    check(engine.naturalSize == expected, "\(name) reports its own video size", "\(engine.naturalSize) expected \(expected)")
    if expectRotated {
        check(engine.naturalSize.width < engine.naturalSize.height, "\(name) rotated size", "\(engine.naturalSize)")
    }
    await sleep(0.5)
    check(!engine.isPlaying, "\(name) starts paused")
    check(frameIndex(engine) == 0, "\(name) frame 0 after load", "index=\(frameIndex(engine))")
    if expectRotated { return }
    let first = await captureNumber(engine)
    check(first == "0", "\(name) capture frame 0", "ocr=\(first)")

    engine.stepFrames(1); await sleep(0.5)
    check(frameIndex(engine) == 1, "\(name) step +1", "index=\(frameIndex(engine))")
    let n1 = await captureNumber(engine)
    check(n1 == "1", "\(name) capture after step +1", "ocr=\(n1)")

    engine.stepFrames(5); await sleep(0.7)
    check(frameIndex(engine) == 6, "\(name) step +5", "index=\(frameIndex(engine))")
    let n6 = await captureNumber(engine)
    check(n6 == "6", "\(name) capture after step +5", "ocr=\(n6)")

    engine.stepFrames(-1); await sleep(0.7)
    check(frameIndex(engine) == 5, "\(name) step -1", "index=\(frameIndex(engine))")
    let n5 = await captureNumber(engine)
    check(n5 == "5", "\(name) capture after step -1", "ocr=\(n5)")

    engine.stepFrames(-3); await sleep(0.7)
    check(frameIndex(engine) == 2, "\(name) step -3", "index=\(frameIndex(engine))")
    let n2 = await captureNumber(engine)
    check(n2 == "2", "\(name) capture after step -3", "ocr=\(n2)")

    let target = Timecode.midFrameSeconds(frameCount: 100, frameRate: engine.frameRate)
    engine.seek(to: CMTime(seconds: target, preferredTimescale: 600_000)); await sleep(0.7)
    check(frameIndex(engine) == 100, "\(name) seek to frame 100", "index=\(frameIndex(engine))")
    let n100 = await captureNumber(engine)
    check(n100 == "100", "\(name) capture after seek", "ocr=\(n100)")
    let onScreen100 = await onScreenNumber(window, engine, expecting: "100")
    check(onScreen100.value == "100", "\(name) on-screen frame after seek", String(format: "read %@ after %.1fs", onScreen100.value, onScreen100.seconds))
    if onScreen100.value != "100" { saveShot("\(name)-seek100") }

    engine.play(); await sleep(1.0)
    check(engine.isPlaying && engine.rate == 1, "\(name) playing", "rate=\(engine.rate)")
    check(frameIndex(engine) > 100, "\(name) time advances", "index=\(frameIndex(engine))")
    engine.pause(); await sleep(0.5)
    check(!engine.isPlaying, "\(name) paused")
    let pausedIndex = frameIndex(engine)
    let pausedCapture = await captureNumber(engine)
    check(pausedCapture == String(pausedIndex), "\(name) paused capture matches index", "index=\(pausedIndex) ocr=\(pausedCapture)")
    let onScreenPaused = await onScreenNumber(window, engine, expecting: String(pausedIndex))
    check(onScreenPaused.value == String(pausedIndex), "\(name) paused on-screen matches index",
          String(format: "index=%d read %@ after %.1fs", pausedIndex, onScreenPaused.value, onScreenPaused.seconds))
    if onScreenPaused.value != String(pausedIndex) { saveShot("\(name)-paused\(pausedIndex)") }
    let timecode = Timecode(frameCount: pausedIndex, frameRate: engine.frameRate)
    print("     timecode at pause: \(timecode.smpteString)")

    do {
        try engine.setRate(-1); await sleep(1.2)
        let reversed = frameIndex(engine)
        check(engine.rate == -1, "\(name) reverse rate", "rate=\(engine.rate)")
        check(reversed < pausedIndex, "\(name) reverse moves back", "from=\(pausedIndex) to=\(reversed)")
        engine.pause(); await sleep(0.4)
        let reverseCapture = await captureNumber(engine)
        check(reverseCapture == String(frameIndex(engine)), "\(name) capture after reverse", "index=\(frameIndex(engine)) ocr=\(reverseCapture)")
        try engine.setRate(2); await sleep(0.6)
        check(engine.rate == 2 && engine.isPlaying, "\(name) 2x rate", "rate=\(engine.rate)")
        engine.pause(); await sleep(0.3)
    } catch {
        check(false, "\(name) setRate", error.localizedDescription)
    }
    engine.volume = 0.5
    check(abs(engine.volume - 0.5) < 0.001, "\(name) volume")
}

@MainActor
func measure(_ controller: PlayerWindowController, engine: any PlaybackEngine, url: URL) async {
    let vc = controller.playerViewController
    guard let window = controller.window else { exit(3) }
    vc.open(url)
    for _ in 0..<40 where !engine.isPlaying { await sleep(0.25) }
    engine.isLooping = true
    print("PHASE play-large \(Int(window.frame.width))x\(Int(window.frame.height)) pts")
    await sleep(Double(ProcessInfo.processInfo.environment["NOVA_MEASURE_SECONDS"] ?? "8") ?? 8)
    window.setContentSize(NSSize(width: 960, height: 540))
    print("PHASE play-small 960x540 pts")
    await sleep(8)
    engine.pause()
    print("PHASE paused")
    await sleep(3)
    exit(0)
}

@MainActor
func testMenus(_ controller: PlayerWindowController, engine: any PlaybackEngine) {
    print("=== menus")
    let edit = MainMenu.build().items.first { $0.title == "Edit" }?.submenu
    let copy = edit?.items.first { $0.title == "Copy Timecode" }
    let paste = edit?.items.first { $0.title == "Paste Timecode" }
    check(copy?.keyEquivalent == "c" && copy?.keyEquivalentModifierMask == [.command, .option], "Edit > Copy Timecode is ⌥⌘C")
    check(paste?.keyEquivalent == "v" && paste?.keyEquivalentModifierMask == [.command, .option], "Edit > Paste Timecode is ⌥⌘V")
    let context = PlayerContextMenu.build(target: controller.playerViewController)
    let titles = context.items.map(\.title)
    check(titles.contains("Copy Timecode") && titles.contains("Paste Timecode"), "context menu has timecode items", "\(titles)")
    let vc = controller.playerViewController
    let copyItem = NSMenuItem(title: "Copy Timecode", action: #selector(PlayerViewController.copyTimecode(_:)), keyEquivalent: "")
    check(vc.validateMenuItem(copyItem) == vc.hasMedia, "Copy Timecode validation follows hasMedia")
    let viewMenu = MainMenu.build().items.first { $0.title == "View" }?.submenu
    let float = viewMenu?.items.first { $0.title == "Float on Top" }
    check(float?.keyEquivalent == "t" && float?.keyEquivalentModifierMask == [.command], "View > Float on Top is ⌘T")
    check(viewMenu?.items.contains { $0.title == "Expand Timeline" } == true, "View menu has Expand Timeline")
    check(titles.contains("Expand Timeline") && titles.contains("Float on Top"), "context menu has timeline and float items")
    let extensions = Set(engine.supportedContentTypes.flatMap { $0.tags[.filenameExtension] ?? [] })
    check(["mkv", "webm", "avi", "wmv", "flv", "mxf", "mp4", "mov"].allSatisfy(extensions.contains), "open dialog accepts every container", "\(extensions.count) extensions")
}

/// Posts a mouse-moved event into the window, the same way a real pointer movement arrives:
/// AppKit dispatches it to tracking areas and to local event monitors.
@MainActor
func moveMouse(in window: NSWindow) {
    let point = NSPoint(x: window.frame.width / 2, y: window.frame.height / 2)
    guard let event = NSEvent.mouseEvent(
        with: .mouseMoved, location: point, modifierFlags: [],
        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
        context: nil, eventNumber: 0, clickCount: 0, pressure: 0
    ) else { return }
    NSApp.postEvent(event, atStart: false)
}

@MainActor
func panelOf(_ vc: PlayerViewController) -> PlayerControlPanel? {
    vc.view.subviews.compactMap { $0 as? PlayerControlPanel }.first
}

@MainActor
func panelParts(_ panel: PlayerControlPanel) -> (row: NSStackView?, buttons: [NSButton], sliders: [NSSlider], fields: [ReadoutField], track: TimelineTrackView?) {
    let row = panel.subviews.compactMap { $0 as? NSStackView }.first
    let items = row?.arrangedSubviews ?? []
    return (
        row,
        items.compactMap { $0 as? NSButton },
        items.compactMap { $0 as? NSSlider },
        items.compactMap { $0 as? ReadoutField },
        panel.subviews.compactMap { $0 as? TimelineTrackView }.first
    )
}

@MainActor
func testControlPanel(_ controller: PlayerWindowController, engine: any PlaybackEngine, url: URL) async {
    let name = url.lastPathComponent
    print("=== player panel with \(name)")
    let vc = controller.playerViewController
    guard let window = controller.window else { check(false, "window"); return }
    engine.unload(); await sleep(0.2)
    vc.open(url)
    for _ in 0..<40 where !engine.isPlaying { await sleep(0.25) }
    check(vc.hasMedia, "\(name) opened")
    guard let panel = panelOf(vc) else { check(false, "\(name) player panel exists"); return }
    check(panel.frame.width == vc.view.frame.width - 32, "\(name) panel fills the window width", "\(panel.frame.width) vs \(vc.view.frame.width - 32)")

    // It fades out on its own; moving the pointer over the video must bring it back.
    await sleep(3.5)
    check(panel.alphaValue < 0.1, "\(name) panel fades when idle", String(format: "alpha %.2f", panel.alphaValue))
    moveMouse(in: window)
    await sleep(0.6)
    check(panel.alphaValue > 0.9, "\(name) panel returns on mouse move", String(format: "alpha %.2f", panel.alphaValue))
    _ = windowScreenshot(window); saveShot("panel-\(name)")

    let parts = panelParts(panel)
    check(parts.buttons.contains { $0.toolTip == "Expand Timeline" }, "\(name) panel has the timeline button")
    check(parts.buttons.contains { $0.toolTip == "Full Screen" }, "\(name) panel has a full screen button")
    check(parts.sliders.count == 2, "\(name) collapsed panel shows scrubber and volume", "\(parts.sliders.count)")
    let wasPlaying = engine.isPlaying
    parts.buttons.first { $0.toolTip == "Play" || $0.toolTip == "Pause" }?.performClick(nil); await sleep(0.5)
    check(engine.isPlaying != wasPlaying, "\(name) play button toggles playback")
    if let volume = parts.sliders.last {
        volume.doubleValue = 0.4
        volume.sendAction(volume.action, to: volume.target); await sleep(0.3)
        check(abs(engine.volume - 0.4) < 0.01, "\(name) volume slider sets the volume", "\(engine.volume)")
        engine.volume = 1
    }
    engine.pause(); await sleep(0.3)
}

/// Settings > General decides whether a file opens with the normal slider or the timecode timeline.
/// Finder can deliver two open events at once, and a running app gets one per file. Overlapping
/// loads used to leave one engine playing audio while the other's blank view was on screen.
@MainActor
func testConcurrentOpens(_ controller: PlayerWindowController, engine: any PlaybackEngine, first: URL, second: URL) async {
    print("=== two files opened at once")
    let vc = controller.playerViewController
    guard let window = controller.window else { check(false, "window"); return }
    for attempt in 1...3 {
        engine.unload(); await sleep(0.3)
        vc.open(first)
        if attempt == 3 { await sleep(0.12) }   // also try a second open mid-load
        vc.open(second)
        for _ in 0..<40 where !engine.isPlaying { await sleep(0.25) }
        await sleep(1.2)
        check(vc.hasMedia, "attempt \(attempt): a file is loaded")
        // The two clips run at different rates, so the rate says which one won.
        check(abs(engine.frameRate - 29.97) < 0.1, "attempt \(attempt): the last file opened wins",
              String(format: "fps %.2f", engine.frameRate))
        check(engine.naturalSize == CGSize(width: 1280, height: 720), "attempt \(attempt): its size is used", "\(engine.naturalSize)")
        engine.pause(); await sleep(0.5)
        let shown = await captureNumber(engine)
        check(Int(shown) != nil, "attempt \(attempt): video renders", "read \(shown)")
        let onScreen = await onScreenNumber(window, engine, expecting: shown)
        check(onScreen.value == shown, "attempt \(attempt): the window shows that frame",
              String(format: "read %@ want %@ after %.1fs", onScreen.value, shown, onScreen.seconds))
        if onScreen.value != shown { saveShot("concurrent-\(attempt)") }
    }
}

/// The title bar names the file and nothing else unless the Timecode settings add more.
@MainActor
func testTitleBar(_ controller: PlayerWindowController, engine: any PlaybackEngine, url: URL) async {
    print("=== title bar")
    let vc = controller.playerViewController
    let defaults = UserDefaults.standard
    let saved = ["showTimecodeInTitle", "showFrameNumber", "showShuttleSpeed", "showFileName"].map { ($0, defaults.object(forKey: $0)) }
    for (key, _) in saved { defaults.removeObject(forKey: key) }
    engine.unload(); await sleep(0.2)
    vc.open(url)
    for _ in 0..<40 where !engine.isPlaying { await sleep(0.25) }
    engine.pause(); await sleep(0.5)
    check(controller.window?.title == url.lastPathComponent, "title is the file name alone", controller.window?.title ?? "nil")
    defaults.set(true, forKey: "showTimecodeInTitle"); await sleep(0.4)
    let withTimecode = controller.window?.title ?? ""
    check(withTimecode.hasPrefix(url.lastPathComponent) && withTimecode.contains(":"), "timecode can be added after the name", withTimecode)
    defaults.set(true, forKey: "showFrameNumber"); await sleep(0.4)
    check(controller.window?.title.contains("Frame") == true, "frame number can be added too", controller.window?.title ?? "")
    for (key, value) in saved {
        if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
    }
    await sleep(0.3)
    check(controller.window?.title == url.lastPathComponent, "title returns to the file name", controller.window?.title ?? "nil")

    let page = TimecodeSettingsViewController()
    _ = page.view
    func checkboxes(in view: NSView) -> [String] {
        view.subviews.flatMap { checkboxes(in: $0) } + view.subviews.compactMap { ($0 as? NSButton)?.title }.filter { !$0.isEmpty }
    }
    let titles = checkboxes(in: page.view)
    check(["File name", "Timecode", "Frame number"].allSatisfy(titles.contains), "Timecode settings offer file name, timecode and frame number", "\(titles)")
}

@MainActor
func testDefaultPlayhead(_ controller: PlayerWindowController, engine: any PlaybackEngine, url: URL) async {
    print("=== default playhead setting")
    let vc = controller.playerViewController
    guard let panel = panelOf(vc) else { check(false, "player panel"); return }
    let defaults = UserDefaults.standard
    let original = defaults.integer(forKey: "defaultPlayhead")

    defaults.set(1, forKey: "defaultPlayhead")
    engine.unload(); await sleep(0.2)
    vc.open(url)
    for _ in 0..<40 where !engine.isPlaying { await sleep(0.25) }
    await sleep(0.8)
    check(panel.isTimelineExpanded, "timecode playhead opens the timeline with the file")
    engine.pause(); await sleep(0.2)

    defaults.set(0, forKey: "defaultPlayhead")
    engine.unload(); await sleep(0.2)
    vc.open(url)
    for _ in 0..<40 where !engine.isPlaying { await sleep(0.25) }
    await sleep(0.8)
    check(!panel.isTimelineExpanded, "normal playhead opens with the slider")
    check(panelParts(panel).sliders.filter { !$0.isHidden }.count == 2, "normal playhead shows the scrubber")
    engine.pause(); await sleep(0.2)

    defaults.set(original, forKey: "defaultPlayhead")
}

/// Drives the real Settings window: does choosing a timeline size reach the player?
@MainActor
func testSettingsWindow(_ controller: PlayerWindowController, engine: any PlaybackEngine, url: URL) async {
    print("=== settings window")
    let vc = controller.playerViewController
    guard let panel = panelOf(vc) else { check(false, "player panel"); return }
    let defaults = UserDefaults.standard
    let originalStyle = defaults.integer(forKey: "timelineStyle")
    defaults.set(1, forKey: "timelineStyle")
    engine.unload(); await sleep(0.2)
    vc.open(url)
    for _ in 0..<40 where !engine.isPlaying { await sleep(0.25) }
    engine.pause(); await sleep(0.3)
    if !panel.isTimelineExpanded { vc.toggleTimeline() }
    await sleep(0.6)
    let fullHeight = panel.frame.height
    check(panel.isFull, "panel starts full size")

    let settings = SettingsWindowController()
    settings.showWindow(nil)
    await sleep(0.6)
    guard let tabs = settings.window?.contentViewController as? NSTabViewController else {
        check(false, "settings tabs"); return
    }
    let general = tabs.tabViewItems.first?.viewController
    _ = general?.view
    func popUps(in view: NSView) -> [NSPopUpButton] {
        view.subviews.flatMap { popUps(in: $0) } + view.subviews.compactMap { $0 as? NSPopUpButton }
    }
    let allPopUps = general.map { popUps(in: $0.view) } ?? []
    guard let sizePopUp = allPopUps.first(where: { $0.itemTitles.contains("Full size") }) else {
        check(false, "timeline size popup found", "\(allPopUps.map { $0.itemTitles })"); return
    }
    check(sizePopUp.infoForBinding(.selectedTag) != nil, "size popup is bound to the setting")
    check(sizePopUp.selectedTag() == 1, "popup shows the current value", "tag \(sizePopUp.selectedTag())")

    // Choose Compact the way a click would: select the item, then send the control's action.
    sizePopUp.selectItem(withTitle: "Compact")
    sizePopUp.sendAction(sizePopUp.action, to: sizePopUp.target)
    await sleep(0.8)
    check(defaults.integer(forKey: "timelineStyle") == 0, "choosing Compact writes the setting",
          "stored \(defaults.integer(forKey: "timelineStyle"))")
    check(!panel.isFull, "player switches to the compact timeline")
    check(panel.frame.height < fullHeight - 20, "panel shrinks", "\(fullHeight) -> \(panel.frame.height)")

    sizePopUp.selectItem(withTitle: "Full size")
    sizePopUp.sendAction(sizePopUp.action, to: sizePopUp.target)
    await sleep(0.8)
    check(defaults.integer(forKey: "timelineStyle") == 1, "choosing Full size writes the setting")
    check(panel.isFull && abs(panel.frame.height - fullHeight) < 1, "player switches back to full size", "\(panel.frame.height)")

    // Changing the size with the timeline closed must show the result, not wait for the next file.
    vc.toggleTimeline(); await sleep(0.6)
    check(!panel.isTimelineExpanded, "timeline closed for the next check")
    sizePopUp.selectItem(withTitle: "Compact")
    sizePopUp.sendAction(sizePopUp.action, to: sizePopUp.target)
    await sleep(0.9)
    check(!panel.isFull, "size setting applies while the timeline is closed")
    check(panel.isTimelineExpanded, "changing the size opens the timeline so the change is visible")
    check(panel.frame.height < fullHeight - 20, "and it opens at the compact size", "\(panel.frame.height)")

    // The playhead choice switches the player that is already open.
    guard let playheadPopUp = allPopUps.first(where: { $0.itemTitles.contains("Timecode") }) else {
        check(false, "playhead popup found"); return
    }
    let originalPlayhead = defaults.integer(forKey: "defaultPlayhead")
    func choosePlayhead(_ title: String) async {
        playheadPopUp.selectItem(withTitle: title)
        playheadPopUp.sendAction(playheadPopUp.action, to: playheadPopUp.target)
        await sleep(0.9)
    }
    // Timecode while the timeline is already open: the setting changes, the player stays put.
    await choosePlayhead("Timecode")
    check(defaults.integer(forKey: "defaultPlayhead") == 1, "choosing Timecode writes the setting")
    check(panel.isTimelineExpanded, "Timecode keeps the timeline open")
    // Switching to Normal closes it on the file already playing.
    await choosePlayhead("Normal")
    check(defaults.integer(forKey: "defaultPlayhead") == 0, "choosing Normal writes the setting")
    check(!panel.isTimelineExpanded, "Normal switches the open player back to the slider")
    // And back again opens it, without waiting for the next file.
    await choosePlayhead("Timecode")
    check(panel.isTimelineExpanded, "Timecode switches the open player to the timeline")
    defaults.set(originalPlayhead, forKey: "defaultPlayhead")
    await sleep(0.5)

    settings.close()
    defaults.set(originalStyle, forKey: "timelineStyle")
    await sleep(0.3)
}

@MainActor
func testTimelineAndFloat(_ controller: PlayerWindowController, engine: any PlaybackEngine, url: URL) async {
    print("=== timeline inside the panel, and float on top")
    let vc = controller.playerViewController
    guard let window = controller.window else { check(false, "window"); return }
    engine.unload(); await sleep(0.2)
    vc.open(url)
    for _ in 0..<40 where !engine.isPlaying { await sleep(0.25) }
    check(vc.hasMedia && engine.isPlaying, "opened for timeline test")
    engine.pause(); await sleep(0.4)
    guard let panel = panelOf(vc) else { check(false, "player panel exists"); return }
    let collapsedHeight = panel.frame.height
    check(!panel.isTimelineExpanded, "timeline starts closed")

    let item = NSMenuItem(title: "", action: #selector(PlayerViewController.toggleTimeline(_:)), keyEquivalent: "")
    _ = vc.validateMenuItem(item)
    check(item.title == "Expand Timeline", "menu offers Expand Timeline", item.title)
    // Sample the panel while it opens: a morph moves through intermediate heights.
    vc.toggleTimeline()
    var heights: [CGFloat] = []
    for _ in 0..<9 {
        await sleep(0.045)
        heights.append(panel.frame.height)
    }
    let intermediates = heights.filter { $0 > collapsedHeight + 1 && $0 < heights.last! - 1 }
    print("     panel heights while opening: " + heights.map { String(format: "%.0f", $0) }.joined(separator: " "))
    check(!intermediates.isEmpty, "panel animates through intermediate heights", "\(intermediates.count) samples between \(Int(collapsedHeight)) and \(Int(heights.last ?? 0))")
    await sleep(0.5)
    _ = vc.validateMenuItem(item)
    check(item.title == "Collapse Timeline", "menu offers Collapse Timeline after toggle", item.title)
    check(panel.isTimelineExpanded, "panel reports the timeline open")
    check(panel.frame.height > collapsedHeight + 20, "the one panel grows for the timeline", "\(collapsedHeight) -> \(panel.frame.height)")

    var parts = panelParts(panel)
    check(parts.track?.isHidden == false, "precision track is inside the panel")
    check(parts.fields.count == 1, "panel has one editable timecode field and no frame readout", "\(parts.fields.count)")
    let visibleSliders = parts.sliders.filter { !$0.isHidden }
    check(visibleSliders.count == 1, "coarse scrubber gives way to the track", "\(visibleSliders.count) visible sliders")
    // Every visible control in the row shares one centre line.
    let centres = (parts.row?.arrangedSubviews ?? []).filter { !$0.isHidden && $0.frame.width > 1 }.map { $0.frame.midY }
    let spread = (centres.max() ?? 0) - (centres.min() ?? 0)
    check(spread < 0.6, "panel row controls are aligned", String(format: "spread %.2f pt across %d controls", spread, centres.count))
    _ = windowScreenshot(window); saveShot("panel-timeline-full")

    // The morph must settle: nothing left part-faded, and the right controls hidden.
    let visible = (parts.row?.arrangedSubviews ?? []).filter { !$0.isHidden }
    check(visible.allSatisfy { $0.alphaValue > 0.99 }, "every visible control finished fading in",
          visible.map { String(format: "%.2f", $0.alphaValue) }.joined(separator: " "))
    check(parts.track?.alphaValue ?? 0 > 0.99, "track finished fading in", String(format: "%.2f", parts.track?.alphaValue ?? 0))

    // Toggling twice in quick succession must still settle correctly.
    vc.toggleTimeline(); await sleep(0.05); vc.toggleTimeline(); await sleep(1.0)
    check(panel.isTimelineExpanded, "fast double toggle leaves the timeline open")
    let afterDouble = panelParts(panel)
    let visibleAfter = (afterDouble.row?.arrangedSubviews ?? []).filter { !$0.isHidden }
    check(visibleAfter.allSatisfy { $0.alphaValue > 0.99 }, "fast double toggle settles every control",
          visibleAfter.map { String(format: "%.2f", $0.alphaValue) }.joined(separator: " "))
    check(afterDouble.fields.first?.isHidden == false && afterDouble.sliders.filter { !$0.isHidden }.count == 1,
          "fast double toggle keeps the timeline layout")

    // The field takes digits and separators only, so a word can never be typed into it.
    if let field = parts.fields.first {
        check(field.formatter is TimecodeInputFormatter, "timecode field has the digits-only formatter")
        for text in ["1", "00:", "00:01:23;12", "00.01.23.12", "12315"] {
            check(TimecodeInputFormatter.isValid(text), "accepts “\(text)”")
        }
        for text in ["a", "00:0a", "hello", "00:01:23:12x", "-1", "00:00:00:00:00:0"] {
            check(!TimecodeInputFormatter.isValid(text), "refuses “\(text)”")
        }
        // Typing a letter into the live field must leave the text untouched.
        window.makeFirstResponder(field)
        await sleep(0.2)
        let before = field.stringValue
        field.currentEditor()?.insertText("a")
        await sleep(0.2)
        check(field.stringValue == before, "typing a letter is rejected by the field", "“\(field.stringValue)”")
        field.currentEditor()?.insertText("5")
        await sleep(0.2)
        check(field.stringValue != before, "typing a digit is accepted", "“\(field.stringValue)”")
        field.cancel()
        await sleep(0.2)
    }

    // The timecode text sits in the middle of its pill.
    if let field = parts.fields.first, let cell = field.cell {
        let title = cell.titleRect(forBounds: field.bounds)
        check(abs(title.midY - field.bounds.midY) < 0.6, "timecode text is vertically centred",
              String(format: "text midY %.2f vs field midY %.2f", title.midY, field.bounds.midY))
        check(field.frame.height == ReadoutField.height, "timecode field keeps its height", "\(field.frame.height)")
    }

    // Clicking the track a quarter of the way along seeks to that frame.
    if let track = parts.track {
        let total = Timecode.frameCount(seconds: engine.duration.seconds, frameRate: engine.frameRate)
        let inset: CGFloat = 20
        let fraction: CGFloat = 0.25
        let xInTrack = inset + (track.bounds.width - 2 * inset) * fraction
        let pointInWindow = track.convert(NSPoint(x: xInTrack, y: track.bounds.midY), to: nil)
        let expected = Int((fraction * CGFloat(total - 1)).rounded())
        if let down = NSEvent.mouseEvent(with: .leftMouseDown, location: pointInWindow, modifierFlags: [], timestamp: 0,
                                         windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1),
           let up = NSEvent.mouseEvent(with: .leftMouseUp, location: pointInWindow, modifierFlags: [], timestamp: 0,
                                       windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 0) {
            track.mouseDown(with: down)
            track.mouseUp(with: up)
            await sleep(0.8)
            check(frameIndex(engine) == expected, "track click seeks to the clicked frame", "index=\(frameIndex(engine)) expected=\(expected)")
            let shown = await captureNumber(engine)
            check(shown == String(expected), "frame after track click", "ocr=\(shown)")
        } else {
            check(false, "synthetic mouse event")
        }
    } else {
        check(false, "track view found")
    }

    // Typing a timecode, and the copy and paste buttons.
    if let field = parts.fields.first {
        check(field.stringValue == Timecode(frameCount: frameIndex(engine), frameRate: engine.frameRate).smpteString,
              "timecode field shows the current timecode", field.stringValue)
        field.stringValue = "00:00:02:00"
        field.commit(); await sleep(0.8)
        let typed = TimecodeParser.parse("00:00:02:00", frameRate: engine.frameRate)?.frameCount(frameRate: engine.frameRate) ?? -1
        check(frameIndex(engine) == typed, "typed timecode jumps to that frame", "index=\(frameIndex(engine)) expected=\(typed)")
        let ocrTyped = await captureNumber(engine)
        check(ocrTyped == String(typed), "frame after typed timecode", "ocr=\(ocrTyped)")
        NSPasteboard.general.clearContents()
        parts.buttons.first { $0.toolTip == "Copy Timecode" }?.performClick(nil); await sleep(0.2)
        check(NSPasteboard.general.string(forType: .string) == field.stringValue, "copy button copies the timecode",
              NSPasteboard.general.string(forType: .string) ?? "nil")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("00:00:01:00", forType: .string)
        parts.buttons.first { $0.toolTip == "Paste Timecode" }?.performClick(nil); await sleep(0.8)
        let pasted = TimecodeParser.parse("00:00:01:00", frameRate: engine.frameRate)?.frameCount(frameRate: engine.frameRate) ?? -1
        check(frameIndex(engine) == pasted, "paste button jumps", "index=\(frameIndex(engine)) expected=\(pasted)")
    } else {
        check(false, "timecode field found")
    }

    // The size button switches the timeline between full and compact, and remembers the choice.
    let settings = AppSettings.shared
    let initialFull = settings.timelineIsFull
    check(panel.isFull == initialFull, "timeline size follows the setting")
    let fullHeight = panel.frame.height
    parts = panelParts(panel)
    parts.buttons.first { $0.toolTip == "Compact Timeline" || $0.toolTip == "Full-Size Timeline" }?.performClick(nil)
    await sleep(0.6)
    check(settings.timelineIsFull == !initialFull && panel.isFull == !initialFull, "size button flips the setting and the panel")
    check(panel.frame.height != fullHeight, "panel height changes with the size", "\(fullHeight) -> \(panel.frame.height)")
    _ = windowScreenshot(window); saveShot("panel-timeline-compact")
    settings.timelineIsFull = initialFull; await sleep(0.4)
    check(panel.isFull == initialFull, "timeline size restored from the setting")

    vc.toggleTimeline(); await sleep(0.5)
    check(!panel.isTimelineExpanded, "timeline closed again")
    check(abs(panel.frame.height - collapsedHeight) < 1, "panel returns to its collapsed height", "\(panel.frame.height)")

    let before = settings.floatOnTop
    controller.toggleFloatOnTop(nil); await sleep(0.2)
    check(settings.floatOnTop == !before && window.level == (before ? .normal : .floating), "float on top toggles window level", "level=\(window.level.rawValue)")
    let floatItem = NSMenuItem(title: "Float on Top", action: #selector(PlayerWindowController.toggleFloatOnTop(_:)), keyEquivalent: "")
    _ = controller.validateMenuItem(floatItem)
    check(floatItem.state == (settings.floatOnTop ? .on : .off), "Float on Top menu item shows a checkmark")
    controller.toggleFloatOnTop(nil); await sleep(0.2)
    check(settings.floatOnTop == before && window.level == (before ? .floating : .normal), "float on top restores level")
    check(window.isRestorable == false, "player window opts out of state restoration")
}

@MainActor
func testTimecodeClipboard(_ controller: PlayerWindowController, engine: any PlaybackEngine, url: URL) async {
    print("=== timecode copy/paste with \(url.lastPathComponent)")
    let vc = controller.playerViewController
    vc.open(url)
    for _ in 0..<40 where !vc.hasMedia { await sleep(0.25) }
    check(vc.hasMedia, "vc opened file")
    engine.pause(); await sleep(0.3)
    let target = Timecode.midFrameSeconds(frameCount: 45, frameRate: engine.frameRate)
    engine.seek(to: CMTime(seconds: target, preferredTimescale: 600_000)); await sleep(0.6)
    vc.copyCurrentTimecode()
    let copied = NSPasteboard.general.string(forType: .string) ?? "nil"
    let expected = Timecode(frameCount: 45, frameRate: engine.frameRate).smpteString
    check(copied == expected, "copy timecode", "clipboard=\(copied) expected=\(expected)")

    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString("00:00:03:10", forType: .string)
    vc.jumpToPastedTimecode(); await sleep(0.8)
    let index = frameIndex(engine)
    let expectedIndex = TimecodeParser.parse("00:00:03:10", frameRate: engine.frameRate)?.frameCount(frameRate: engine.frameRate) ?? -1
    check(index == expectedIndex, "paste timecode jumps", "index=\(index) expected=\(expectedIndex)")
    let ocr = await captureNumber(engine)
    check(ocr == String(expectedIndex), "paste timecode frame on screen", "ocr=\(ocr)")

    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString("garbage", forType: .string)
    vc.jumpToPastedTimecode(); await sleep(0.5)
    check(frameIndex(engine) == expectedIndex, "invalid paste leaves position", "index=\(frameIndex(engine))")
    // Dismiss the alert sheet the invalid paste produced.
    if let sheet = controller.window?.attachedSheet { controller.window?.endSheet(sheet) }
}

@MainActor
func start() {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let mpv = MPVEngine()
    let av = AVFoundationEngine()
    let engine = HybridPlaybackEngine(primary: av, fallback: mpv)
    let controller = PlayerWindowController(engine: engine)
    controller.showWindow(nil)
    controller.window?.makeKeyAndOrderFront(nil)
    app.activate(ignoringOtherApps: true)

    let arguments = Array(CommandLine.arguments.dropFirst())
    Task { @MainActor in
        await sleep(0.5)
        guard let window = controller.window else { exit(3) }
        if let measured = ProcessInfo.processInfo.environment["NOVA_MEASURE"] {
            await measure(controller, engine: engine, url: URL(fileURLWithPath: measured))
        }
        let clips = arguments.filter { !$0.hasSuffix("rot90.mp4") }.map { URL(fileURLWithPath: $0) }
        for url in clips {
            await testEngine(engine, window: window, url: url, expectRotated: false)
        }
        if let rotated = arguments.first(where: { $0.hasSuffix("rot90.mp4") }) {
            await testEngine(engine, window: window, url: URL(fileURLWithPath: rotated), expectRotated: true)
        }
        if let first = clips.first {
            await testTimecodeClipboard(controller, engine: engine, url: first)
        }
        testMenus(controller, engine: engine)
        if let first = clips.first { await testTimelineAndFloat(controller, engine: engine, url: first) }
        for url in clips.prefix(2) { await testControlPanel(controller, engine: engine, url: url) }
        if clips.count >= 2 {
            await testConcurrentOpens(controller, engine: engine, first: clips[1], second: clips[0])
        }
        if let first = clips.first { await testTitleBar(controller, engine: engine, url: first) }
        if let first = clips.first { await testDefaultPlayhead(controller, engine: engine, url: first) }
        if let first = clips.first { await testSettingsWindow(controller, engine: engine, url: first) }
        print("=== \(passes) passed, \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
    app.run()
}

setvbuf(stdout, nil, _IONBF, 0)
MainActor.assumeIsolated { start() }
