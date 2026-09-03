import AppKit

/// A small translucent round button that floats over the video and fades out when the pointer rests.
final class HUDButton: NSVisualEffectView {
    var onClick: (() -> Void)?

    /// Tints the symbol with the accent colour while the feature it controls is active.
    var isOn = false {
        didSet { updateTint() }
    }

    private let button = NSButton()
    private static let diameter: CGFloat = 32

    init(symbolName: String, description: String) {
        super.init(frame: .zero)
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = Self.diameter / 2
        layer?.masksToBounds = true

        button.isBordered = false
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: description)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold))
        button.imageScaling = .scaleProportionallyDown
        button.refusesFirstResponder = true
        button.toolTip = description
        button.target = self
        button.action = #selector(clicked(_:))
        button.translatesAutoresizingMaskIntoConstraints = false
        addSubview(button)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.diameter),
            heightAnchor.constraint(equalToConstant: Self.diameter),
            button.leadingAnchor.constraint(equalTo: leadingAnchor),
            button.trailingAnchor.constraint(equalTo: trailingAnchor),
            button.topAnchor.constraint(equalTo: topAnchor),
            button.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        updateTint()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var mouseDownCanMoveWindow: Bool { false }

    var toolTipText: String? {
        get { button.toolTip }
        set { button.toolTip = newValue }
    }

    private func updateTint() {
        button.contentTintColor = isOn ? .controlAccentColor : .labelColor
    }

    @objc private func clicked(_ sender: Any?) {
        onClick?()
    }
}
