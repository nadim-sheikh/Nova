import AppKit

/// A small translucent confirmation that fades in over the video and disappears on its own.
final class ToastView: NSVisualEffectView {
    private let label = NSTextField(labelWithString: "")
    private var hideTask: Task<Void, Never>?

    init() {
        super.init(frame: .zero)
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true
        alphaValue = 0

        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    func show(_ text: String) {
        label.stringValue = text
        hideTask?.cancel()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            animator().alphaValue = 1
        }
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            guard !Task.isCancelled else { return }
            self?.fadeOut()
        }
    }

    private func fadeOut() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            animator().alphaValue = 0
        }
    }
}
