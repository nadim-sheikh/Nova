import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: PlayerWindowController?
    private lazy var settingsWindowController = SettingsWindowController()
    private var appearanceController: AppearanceController?
    private var appIconController: AppIconController?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSUserDefaultsController.shared.initialValues = AppSettings.defaultValues
        appearanceController = AppearanceController()
        // After the appearance controller, so the first icon matches the theme being applied.
        appIconController = AppIconController()
        NSApp.mainMenu = MainMenu.build()
        // AVFoundation handles what macOS decodes natively; libmpv takes every other container and codec.
        let engine = HybridPlaybackEngine(primary: AVFoundationEngine(), fallback: MPVEngine())
        let controller = PlayerWindowController(engine: engine)
        windowController = controller
        controller.showWindow(nil)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
        if let url = LaunchArguments.fileURL(from: CommandLine.arguments) {
            windowController?.playerViewController.open(url)
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        windowController?.playerViewController.open(url)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    // MARK: - Menu actions

    @objc func openDocument(_ sender: Any?) {
        windowController?.playerViewController.promptForFile()
    }

    @objc func showSettings(_ sender: Any?) {
        settingsWindowController.showWindow(nil)
        settingsWindowController.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func showAbout(_ sender: Any?) {
        AboutPanel.show()
    }

    @objc func openDeveloperLink(_ sender: Any?) {
        guard let url = DeveloperCredits.xProfileURL else { return }
        NSWorkspace.shared.open(url)
    }
}
