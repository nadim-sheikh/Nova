import AppKit

/// Builds the application's menu bar programmatically (the app has no storyboard).
enum MainMenu {
    static func build() -> NSMenu {
        let mainMenu = NSMenu()
        mainMenu.addItem(applicationMenuItem())
        mainMenu.addItem(fileMenuItem())
        mainMenu.addItem(editMenuItem())
        mainMenu.addItem(viewMenuItem())
        mainMenu.addItem(windowMenuItem())
        mainMenu.addItem(helpMenuItem())
        return mainMenu
    }

    private static func applicationMenuItem() -> NSMenuItem {
        let menu = NSMenu()
        menu.addItem(withTitle: "About Nova", action: #selector(AppDelegate.showAbout(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(AppDelegate.showSettings(_:)), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Hide Nova", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = menu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Nova", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return item(titled: "Nova", submenu: menu)
    }

    private static func fileMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: "File")
        menu.addItem(withTitle: "Open…", action: #selector(AppDelegate.openDocument(_:)), keyEquivalent: "o")
        menu.addItem(.separator())
        let saveFrame = menu.addItem(withTitle: "Save Frame…", action: #selector(PlayerViewController.saveFrame(_:)), keyEquivalent: "s")
        saveFrame.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(.separator())
        menu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        return item(titled: "File", submenu: menu)
    }

    private static func editMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: "Edit")
        menu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = menu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(.separator())
        menu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        let copyFrame = menu.addItem(withTitle: "Copy Frame", action: #selector(PlayerWindowController.copyFrame(_:)), keyEquivalent: "c")
        copyFrame.keyEquivalentModifierMask = [.command, .shift]
        let copyTimecode = menu.addItem(withTitle: "Copy Timecode", action: #selector(PlayerViewController.copyTimecode(_:)), keyEquivalent: "c")
        copyTimecode.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        let pasteTimecode = menu.addItem(withTitle: "Paste Timecode", action: #selector(PlayerViewController.pasteTimecode(_:)), keyEquivalent: "v")
        pasteTimecode.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        return item(titled: "Edit", submenu: menu)
    }

    private static func viewMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: "View")
        // The timeline's key (T by default) is a player shortcut and editable in Settings > Keyboard.
        menu.addItem(withTitle: "Expand Timeline", action: #selector(PlayerViewController.toggleTimeline(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Float on Top", action: #selector(PlayerWindowController.toggleFloatOnTop(_:)), keyEquivalent: "t")
        menu.addItem(.separator())
        let fullScreen = menu.addItem(withTitle: "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        fullScreen.keyEquivalentModifierMask = [.command, .control]
        return item(titled: "View", submenu: menu)
    }

    private static func windowMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: "Window")
        menu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        menu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        NSApp.windowsMenu = menu
        return item(titled: "Window", submenu: menu)
    }

    private static func helpMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: "Help")
        menu.addItem(withTitle: "Follow \(DeveloperCredits.xHandle) on X", action: #selector(AppDelegate.openDeveloperLink(_:)), keyEquivalent: "")
        NSApp.helpMenu = menu
        return item(titled: "Help", submenu: menu)
    }

    private static func item(titled title: String, submenu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }
}
