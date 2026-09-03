import AppKit

/// Applies the saved appearance choice to the whole app and re-applies it whenever the choice
/// changes. `.system` installs no appearance of its own, so the app follows the macOS Light/Dark
/// setting live, including when the user switches it while Nova is running.
@MainActor
final class AppearanceController {
    private let settings: AppSettings
    private var changeObserver: NSObjectProtocol?

    init(settings: AppSettings = .shared) {
        self.settings = settings
        apply()
        changeObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.apply() }
        }
    }

    deinit {
        if let changeObserver {
            NotificationCenter.default.removeObserver(changeObserver)
        }
    }

    func apply() {
        NSApp.appearance = AppearanceController.appearance(for: settings.appearanceMode)
    }

    static func appearance(for mode: AppSettings.AppearanceMode) -> NSAppearance? {
        switch mode {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}
