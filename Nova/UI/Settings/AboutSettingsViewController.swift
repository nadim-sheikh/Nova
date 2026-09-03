import AppKit

final class AboutSettingsViewController: NSViewController {
    private let iconView = NSImageView()
    private var appearanceObservation: NSKeyValueObservation?

    override func loadView() {
        let icon = iconView
        icon.image = AppIconController.icon(for: NSApp.effectiveAppearance)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 96).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 96).isActive = true

        let name = NSTextField(labelWithString: "Nova")
        name.font = .systemFont(ofSize: 26, weight: .bold)

        let info = Bundle.main.infoDictionary ?? [:]
        let shortVersion = info["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info["CFBundleVersion"] as? String ?? "1"
        let version = NSTextField(labelWithString: "Version \(shortVersion) (\(build))")
        version.textColor = .secondaryLabelColor

        let tagline = NSTextField(labelWithString: "Frame-accurate video player for macOS")
        tagline.textColor = .secondaryLabelColor

        let credit = NSTextField(labelWithString: "Developed by \(DeveloperCredits.developerName)")
        credit.font = .systemFont(ofSize: 13, weight: .medium)

        let link = NSButton(title: "Follow \(DeveloperCredits.xHandle) on X", target: self, action: #selector(openDeveloperLink(_:)))
        link.bezelStyle = .rounded
        link.controlSize = .large

        let stack = NSStackView(views: [icon, name, version, tagline, credit, link])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 6
        stack.setCustomSpacing(14, after: icon)
        stack.setCustomSpacing(18, after: tagline)
        stack.setCustomSpacing(12, after: credit)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = FlippedView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 28),
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            container.bottomAnchor.constraint(equalTo: stack.bottomAnchor, constant: 28),
        ])
        view = SettingsForm.scrollable(container)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        appearanceObservation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.iconView.image = AppIconController.icon(for: NSApp.effectiveAppearance)
            }
        }
    }

    @objc private func openDeveloperLink(_ sender: Any?) {
        guard let url = DeveloperCredits.xProfileURL else { return }
        NSWorkspace.shared.open(url)
    }
}
