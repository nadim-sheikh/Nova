import AppKit

/// The menu shown by right-click, Control-click, or a two-finger trackpad click on the video.
/// Items either target the player (playback and frame copying) or travel the responder chain.
enum PlayerContextMenu {
    static func build(target: PlayerViewController) -> NSMenu {
        let menu = NSMenu(title: "Nova")
        menu.autoenablesItems = true
        menu.delegate = target

        let playPause = menu.addItem(withTitle: "Pause", action: #selector(PlayerViewController.playPauseFromMenu(_:)), keyEquivalent: "")
        playPause.target = target

        menu.addItem(.separator())

        let copyFrame = menu.addItem(withTitle: "Copy Frame", action: #selector(PlayerViewController.copyFrame(_:)), keyEquivalent: "c")
        copyFrame.keyEquivalentModifierMask = [.command, .shift]
        copyFrame.target = target

        let saveFrame = menu.addItem(withTitle: "Save Frame…", action: #selector(PlayerViewController.saveFrame(_:)), keyEquivalent: "s")
        saveFrame.keyEquivalentModifierMask = [.command, .shift]
        saveFrame.target = target

        menu.addItem(.separator())

        let copyTimecode = menu.addItem(withTitle: "Copy Timecode", action: #selector(PlayerViewController.copyTimecode(_:)), keyEquivalent: "c")
        copyTimecode.keyEquivalentModifierMask = [.command, .option]
        copyTimecode.target = target

        let pasteTimecode = menu.addItem(withTitle: "Paste Timecode", action: #selector(PlayerViewController.pasteTimecode(_:)), keyEquivalent: "v")
        pasteTimecode.keyEquivalentModifierMask = [.command, .option]
        pasteTimecode.target = target

        menu.addItem(.separator())

        let timeline = menu.addItem(withTitle: "Expand Timeline", action: #selector(PlayerViewController.toggleTimeline(_:)), keyEquivalent: "")
        timeline.target = target
        // No target: the window controller answers this one through the responder chain.
        menu.addItem(withTitle: "Float on Top", action: #selector(PlayerWindowController.toggleFloatOnTop(_:)), keyEquivalent: "t")

        menu.addItem(.separator())

        menu.addItem(withTitle: "Open…", action: #selector(AppDelegate.openDocument(_:)), keyEquivalent: "o")
        menu.addItem(withTitle: "Settings…", action: #selector(AppDelegate.showSettings(_:)), keyEquivalent: ",")

        return menu
    }
}
