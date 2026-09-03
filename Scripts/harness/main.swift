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
    let onScreen100 = onScreenNumber(window, engine)
    check(onScreen100 == "100", "\(name) on-screen frame after seek", "ocr=\(onScreen100)")
    if onScreen100 != "100" {
        saveShot("\(name)-seek100")
        await sleep(1.0)
        print("     retry after 1s: on-screen=\(onScreenNumber(window, engine)) capture=\(await captureNumber(engine))")
        engine.videoView.needsDisplay = true
        await sleep(0.5)
        print("     after needsDisplay: on-screen=\(onScreenNumber(window, engine))")
    }

    engine.play(); await sleep(1.0)
    check(engine.isPlaying && engine.rate == 1, "\(name) playing", "rate=\(engine.rate)")
    check(frameIndex(engine) > 100, "\(name) time advances", "index=\(frameIndex(engine))")
    engine.pause(); await sleep(0.5)
    check(!engine.isPlaying, "\(name) paused")
    let pausedIndex = frameIndex(engine)
    let pausedCapture = await captureNumber(engine)
    check(pausedCapture == String(pausedIndex), "\(name) paused capture matches index", "index=\(pausedIndex) ocr=\(pausedCapture)")
    let onScreenPaused = onScreenNumber(window, engine)
    check(onScreenPaused == String(pausedIndex), "\(name) paused on-screen matches index", "index=\(pausedIndex) ocr=\(onScreenPaused)")
    if onScreenPaused != String(pausedIndex) { saveShot("\(name)-paused\(pausedIndex)") }
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
func testControlBar(_ controller: PlayerWindowController, engine: any PlaybackEngine, url: URL) async {
    let name = url.lastPathComponent
    print("=== transport bar with \(name)")
    let vc = controller.playerViewController
    guard let window = controller.window else { check(false, "window"); return }
    engine.unload(); await sleep(0.2)
    vc.open(url)
    for _ in 0..<40 where !engine.isPlaying { await sleep(0.25) }
    check(vc.hasMedia, "\(name) opened")
    guard let bar = vc.view.subviews.compactMap({ $0 as? PlayerControlBar }).first else {
        check(false, "\(name) control bar exists"); return
    }
    // It fades out on its own; moving the pointer over the video must bring it back.
    await sleep(3.5)
    check(bar.alphaValue < 0.1, "\(name) bar fades when idle", String(format: "alpha %.2f", bar.alphaValue))
    moveMouse(in: window)
    await sleep(0.6)
    check(bar.alphaValue > 0.9, "\(name) bar returns on mouse move", String(format: "alpha %.2f", bar.alphaValue))
    _ = windowScreenshot(window); saveShot("bar-\(name)")

    let buttons = bar.subviews.compactMap { $0 as? NSStackView }.flatMap(\.arrangedSubviews).compactMap { $0 as? NSButton }
    check(buttons.contains { $0.toolTip == "Expand Timeline" || $0.toolTip == "Collapse Timeline" }, "\(name) bar has the timeline button")
    check(buttons.contains { $0.toolTip == "Full Screen" }, "\(name) bar has a full screen button")
    let wasPlaying = engine.isPlaying
    buttons.first { $0.toolTip == "Play" || $0.toolTip == "Pause" }?.performClick(nil); await sleep(0.5)
    check(engine.isPlaying != wasPlaying, "\(name) play button toggles playback")
    let sliders = bar.subviews.compactMap { $0 as? NSStackView }.flatMap(\.arrangedSubviews).compactMap { $0 as? NSSlider }
    check(sliders.count == 2, "\(name) bar has scrubber and volume sliders", "\(sliders.count)")
    if let volume = sliders.last {
        volume.doubleValue = 0.4
        volume.sendAction(volume.action, to: volume.target); await sleep(0.3)
        check(abs(engine.volume - 0.4) < 0.01, "\(name) volume slider sets the volume", "\(engine.volume)")
        engine.volume = 1
    }
    if !engine.isPlaying { engine.play() }
    await sleep(0.3)
    engine.pause()
}

@MainActor
func testTimelineAndFloat(_ controller: PlayerWindowController, engine: any PlaybackEngine, url: URL) async {
    print("=== timeline and float on top with \(url.lastPathComponent)")
    let vc = controller.playerViewController
    guard let window = controller.window else { check(false, "window"); return }
    // hasMedia may still be true from the previous file, so wait for this load to finish playing.
    engine.unload(); await sleep(0.2)
    vc.open(url)
    for _ in 0..<40 where !engine.isPlaying { await sleep(0.25) }
    check(vc.hasMedia && engine.isPlaying, "opened for timeline test")
    engine.pause(); await sleep(0.4)
    check(!engine.isPlaying, "paused before timeline test")

    let item = NSMenuItem(title: "", action: #selector(PlayerViewController.toggleTimeline(_:)), keyEquivalent: "")
    _ = vc.validateMenuItem(item)
    check(item.title == "Expand Timeline", "menu offers Expand Timeline", item.title)
    vc.toggleTimeline(); await sleep(0.4)
    _ = vc.validateMenuItem(item)
    check(item.title == "Collapse Timeline", "menu offers Collapse Timeline after toggle", item.title)
    let overlay = vc.view.subviews.compactMap { $0 as? TimelineOverlayView }.first
    check(overlay != nil && overlay?.isHidden == false && (overlay?.alphaValue ?? 0) > 0.99, "timeline overlay visible")
    check(overlay?.frame.width == vc.view.frame.width, "timeline spans the full window width", "\(overlay?.frame.width ?? 0) vs \(vc.view.frame.width)")
    let bar = vc.view.subviews.compactMap { $0 as? PlayerControlBar }.first
    check(bar != nil, "player control bar present")
    check(bar?.isTimelineExpanded == true, "control bar shows the timeline as active")
    if let bar {
        check(abs(bar.frame.width - (vc.view.frame.width - 32)) < 1, "control bar fills the window width", "\(bar.frame.width) vs \(vc.view.frame.width - 32)")
        // The player view is not flipped, so "above" means a higher y.
        check(bar.frame.minY >= (overlay?.frame.maxY ?? 0) - 1, "control bar sits above the open timeline", "bar=\(bar.frame.minY) timeline=\(overlay?.frame.maxY ?? 0)")
    }
    _ = windowScreenshot(window); saveShot("timeline-expanded")

    // Click on the track a quarter of the way along and check the engine lands on that frame.
    if let overlay, let track = overlay.subviews.compactMap({ $0 as? TimelineTrackView }).first {
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
            check(frameIndex(engine) == expected, "timeline click seeks to the clicked frame", "index=\(frameIndex(engine)) expected=\(expected)")
            let shown = await captureNumber(engine)
            check(shown == String(expected), "frame after timeline click", "ocr=\(shown)")
        } else {
            check(false, "synthetic mouse event")
        }
    } else {
        check(false, "timeline track view found")
    }
    // Typed timecode, the copy button, and the size toggle.
    // Every header control shares one centre line.
    if let overlay, let header = overlay.subviews.compactMap({ $0 as? NSStackView }).first {
        let centres = header.arrangedSubviews.filter { $0.frame.width > 1 }.map { $0.frame.midY }
        let spread = (centres.max() ?? 0) - (centres.min() ?? 0)
        check(spread < 0.6, "timeline header controls are aligned", String(format: "spread %.2f pt across %d controls", spread, centres.count))
        check(header.alignment == .centerY, "header stack is centre-aligned")
    } else {
        check(false, "timeline header found")
    }
    let fields = overlay.map { o in o.subviews.compactMap { $0 as? NSStackView }.flatMap(\.arrangedSubviews).compactMap { $0 as? ReadoutField } } ?? []
    check(fields.count == 2, "timeline has editable timecode and frame fields", "\(fields.count)")
    if let overlay, let field = fields.first {
        let shown = Timecode(frameCount: frameIndex(engine), frameRate: engine.frameRate).smpteString
        check(field.stringValue == shown, "timecode field shows the current timecode", "\(field.stringValue) vs \(shown)")
        field.stringValue = "00:00:02:00"
        field.commit(); await sleep(0.8)
        let typed = TimecodeParser.parse("00:00:02:00", frameRate: engine.frameRate)?.frameCount(frameRate: engine.frameRate) ?? -1
        check(frameIndex(engine) == typed, "typed timecode jumps to that frame", "index=\(frameIndex(engine)) expected=\(typed)")
        check(field.stringValue == Timecode(frameCount: typed, frameRate: engine.frameRate).smpteString, "field shows the new position", field.stringValue)
        let ocrTyped = await captureNumber(engine)
        check(ocrTyped == String(typed), "frame after typed timecode", "ocr=\(ocrTyped)")
        NSPasteboard.general.clearContents()
        let buttons = overlay.subviews.compactMap { $0 as? NSStackView }.flatMap(\.arrangedSubviews).compactMap { $0 as? NSButton }
        let copyButton = buttons.first { $0.toolTip == "Copy Timecode" }
        copyButton?.performClick(nil); await sleep(0.2)
        let copied = NSPasteboard.general.string(forType: .string)
        check(copied == field.stringValue, "timeline copy button copies the timecode", copied ?? "nil")

        // The frame field is editable too, and honours the first-frame-number setting.
        if let frameField = fields.last {
            let base = AppSettings.shared.frameNumberBase
            check(frameField.stringValue == String(frameIndex(engine) + base), "frame field shows the current frame", frameField.stringValue)
            frameField.stringValue = String(150 + base)
            frameField.commit(); await sleep(0.8)
            check(frameIndex(engine) == 150, "typed frame number jumps to that frame", "index=\(frameIndex(engine))")
            let ocrFrame = await captureNumber(engine)
            check(ocrFrame == "150", "frame after typed frame number", "ocr=\(ocrFrame)")
        }

        // Paste button reads the clipboard, like ⌥⌘V.
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("00:00:01:00", forType: .string)
        buttons.first { $0.toolTip == "Paste Timecode" }?.performClick(nil); await sleep(0.8)
        let pasted = TimecodeParser.parse("00:00:01:00", frameRate: engine.frameRate)?.frameCount(frameRate: engine.frameRate) ?? -1
        check(frameIndex(engine) == pasted, "timeline paste button jumps", "index=\(frameIndex(engine)) expected=\(pasted)")
    } else {
        check(false, "timecode field found")
    }
    let sizeSettings = AppSettings.shared
    let initialFull = sizeSettings.timelineIsFull
    check(overlay?.isFull == initialFull, "timeline size follows the setting")
    let sizeButton = overlay?.subviews.compactMap { $0 as? NSStackView }.flatMap(\.arrangedSubviews).compactMap { $0 as? NSButton }.first { $0.toolTip == "Compact Timeline" || $0.toolTip == "Full-Size Timeline" }
    sizeButton?.performClick(nil); await sleep(0.5)
    check(sizeSettings.timelineIsFull == !initialFull && overlay?.isFull == !initialFull, "size button flips the setting and the timeline")
    let expectedHeight = initialFull ? TimelineOverlayView.compactHeight : TimelineOverlayView.fullHeight
    check(abs((overlay?.frame.height ?? 0) - expectedHeight) < 1, "timeline height changes with size", "\(overlay?.frame.height ?? 0) vs \(expectedHeight)")
    _ = windowScreenshot(window); saveShot("timeline-\(initialFull ? "compact" : "full")")
    sizeSettings.timelineIsFull = initialFull; await sleep(0.5)
    _ = windowScreenshot(window); saveShot("timeline-\(initialFull ? "full" : "compact")")
    sizeSettings.timelineIsFull = initialFull; await sleep(0.3)
    check(overlay?.isFull == initialFull, "timeline size restored from the setting")
    vc.toggleTimeline(); await sleep(0.4)
    check(overlay?.isHidden == true, "timeline hidden after collapse")

    let settings = AppSettings.shared
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
        for url in clips.prefix(2) { await testControlBar(controller, engine: engine, url: url) }
        print("=== \(passes) passed, \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
    app.run()
}

setvbuf(stdout, nil, _IONBF, 0)
MainActor.assumeIsolated { start() }
