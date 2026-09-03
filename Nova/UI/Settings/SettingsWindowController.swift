import AppKit

/// The Settings window: resizable so a tall page can be shrunk on a small display, with the
/// content scrolling inside each tab.
final class SettingsWindowController: NSWindowController {
    init() {
        let tabs = SettingsTabViewController()
        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable, .resizable]
        window.toolbarStyle = .preference
        window.title = "General"
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: SettingsForm.pageWidth, height: 200)
        window.setFrameAutosaveName("SettingsWindow")
        window.isRestorable = false
        super.init(window: window)
        window.center()
    }

    required init?(coder: NSCoder) {
        nil
    }
}
