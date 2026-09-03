import AppKit

final class PlayerWindowController: NSWindowController, NSMenuItemValidation {
    let playerViewController: PlayerViewController
    private let settings = AppSettings.shared
    private var observers: [NSObjectProtocol] = []

    init(engine: any PlaybackEngine) {
        playerViewController = PlayerViewController(engine: engine)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 540),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Nova"
        window.backgroundColor = .black
        window.contentMinSize = NSSize(width: 280, height: 160)
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.isReleasedWhenClosed = false
        // Nova opens its own window, so macOS never needs to restore one (or ask to after a crash).
        window.isRestorable = false
        window.contentViewController = playerViewController
        window.center()
        super.init(window: window)
        applyWindowLevel()
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyWindowLevel() }
        })
        for name in [NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification] {
            observers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.applyWindowLevel() }
            })
        }
    }

    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    // MARK: - Float on top

    @objc func toggleFloatOnTop(_ sender: Any?) {
        settings.floatOnTop.toggle()
    }

    /// A floating window stays above every app's normal windows. Full screen needs the normal
    /// level, otherwise the window leaves its own Space, so the setting is applied on exit instead.
    private func applyWindowLevel() {
        guard let window else { return }
        let isFullScreen = window.styleMask.contains(.fullScreen)
        window.level = settings.floatOnTop && !isFullScreen ? .floating : .normal
    }

    /// Edit > Copy copies the current frame while the player window is active.
    @objc func copy(_ sender: Any?) {
        playerViewController.copyCurrentFrame()
    }

    @objc func copyFrame(_ sender: Any?) {
        playerViewController.copyCurrentFrame()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(copy(_:)), #selector(copyFrame(_:)):
            return playerViewController.hasMedia
        case #selector(toggleFloatOnTop(_:)):
            menuItem.state = settings.floatOnTop ? .on : .off
            return true
        default:
            return true
        }
    }
}
