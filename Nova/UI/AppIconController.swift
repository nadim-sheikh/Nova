import AppKit

/// Keeps the Dock icon in step with the active theme. Nova ships a light-mode and a dark-mode
/// icon; the matching one is installed whenever the theme changes, whether that came from the
/// Appearance setting or from macOS switching Light/Dark while Nova runs.
@MainActor
final class AppIconController {
    nonisolated static let lightIconName = "AppIconLight"
    nonisolated static let darkIconName = "AppIconDark"

    private var appearanceObservation: NSKeyValueObservation?
    private var systemThemeObserver: NSObjectProtocol?
    private var installedIconName: String?

    init() {
        apply()
        appearanceObservation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.apply() }
        }
        // Belt and braces: the system posts this when macOS Light/Dark changes, which covers the
        // case where the app's effective appearance is refreshed without a KVO notification.
        systemThemeObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.apply() }
        }
    }

    deinit {
        if let systemThemeObserver {
            DistributedNotificationCenter.default().removeObserver(systemThemeObserver)
        }
    }

    func apply() {
        let name = AppIconController.iconName(for: NSApp.effectiveAppearance)
        guard name != installedIconName, let image = NSImage(named: name) else { return }
        NSApp.applicationIconImage = image
        installedIconName = name
    }

    /// Pure mapping from an appearance to an icon name; safe to call from anywhere.
    nonisolated static func iconName(for appearance: NSAppearance) -> String {
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? darkIconName : lightIconName
    }

    /// The icon for a given appearance, falling back to whatever icon the app is currently showing.
    static func icon(for appearance: NSAppearance) -> NSImage? {
        NSImage(named: iconName(for: appearance)) ?? NSApp.applicationIconImage
    }
}
