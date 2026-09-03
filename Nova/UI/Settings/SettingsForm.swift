import AppKit

/// Shared building blocks for the settings pages: a label/control grid with standard macOS
/// spacing, controls bound directly to user defaults so changes apply immediately, and a
/// scrolling wrapper so a tall page still works on a short screen.
enum SettingsForm {
    static let pageWidth: CGFloat = 540
    private static let margin: CGFloat = 24
    private static let labelColumnWidth: CGFloat = 190
    /// Space a settings window needs for its title bar, tab toolbar, and a margin from the screen edge.
    private static let windowChrome: CGFloat = 150
    private static let minimumPageHeight: CGFloat = 260

    static func checkbox(_ title: String, key: AppSettings.Key) -> NSButton {
        let button = NSButton(checkboxWithTitle: title, target: nil, action: nil)
        button.bind(.value, to: NSUserDefaultsController.shared, withKeyPath: key.bindingKeyPath, options: nil)
        return button
    }

    static func popUp(_ choices: [(title: String, tag: Int)], key: AppSettings.Key) -> NSPopUpButton {
        let popUp = NSPopUpButton(frame: .zero, pullsDown: false)
        for choice in choices {
            popUp.addItem(withTitle: choice.title)
            popUp.lastItem?.tag = choice.tag
        }
        popUp.bind(.selectedTag, to: NSUserDefaultsController.shared, withKeyPath: key.bindingKeyPath, options: nil)
        popUp.widthAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true
        return popUp
    }

    /// A one-click picker for a small set of choices, bound to a user default.
    static func segmented(_ choices: [(title: String, tag: Int)], key: AppSettings.Key) -> NSSegmentedControl {
        let control = NSSegmentedControl(
            labels: choices.map(\.title), trackingMode: .selectOne, target: nil, action: nil
        )
        for (index, choice) in choices.enumerated() {
            control.setTag(choice.tag, forSegment: index)
        }
        control.segmentDistribution = .fillEqually
        control.bind(.selectedTag, to: NSUserDefaultsController.shared, withKeyPath: key.bindingKeyPath, options: nil)
        return control
    }

    static func note(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .secondaryLabelColor
        label.preferredMaxLayoutWidth = pageWidth - margin * 2 - labelColumnWidth - 12
        return label
    }

    /// Builds a page from rows of (label, control). Use an empty label to continue the group above.
    static func page(rows: [(label: String, control: NSView)], footer: NSView? = nil) -> NSView {
        let grid = NSGridView(views: rows.map { [rowLabel($0.label), $0.control] })
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.rowSpacing = 10
        grid.columnSpacing = 12
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 0).width = labelColumnWidth
        grid.column(at: 1).xPlacement = .leading
        grid.rowAlignment = .firstBaseline

        let container = FlippedView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: container.topAnchor, constant: margin),
            grid.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: margin),
            grid.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -margin),
        ])

        var lastBottom = grid.bottomAnchor
        if let footer {
            footer.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(footer)
            NSLayoutConstraint.activate([
                footer.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: 20),
                footer.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -margin),
            ])
            lastBottom = footer.bottomAnchor
        }
        container.bottomAnchor.constraint(equalTo: lastBottom, constant: margin).isActive = true
        return scrollable(container)
    }

    /// Wraps a page's content so it scrolls vertically when the window is shorter than the content.
    static func scrollable(_ content: NSView) -> NSScrollView {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: pageWidth, height: 400))
        // The tab view controller positions each page by frame, so the scroll view must resize with
        // it; only the content inside uses constraints. Without this the page keeps its full height
        // and never scrolls in a short window.
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.documentView = content
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            content.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            content.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
        ])
        scrollView.layoutSubtreeIfNeeded()
        return scrollView
    }

    /// The size a page wants: its natural height, capped so the window always fits the screen.
    static func preferredSize(for view: NSView) -> NSSize {
        view.layoutSubtreeIfNeeded()
        let contentHeight: CGFloat
        if let scrollView = view as? NSScrollView, let document = scrollView.documentView {
            contentHeight = document.fittingSize.height
        } else {
            contentHeight = view.fittingSize.height
        }
        let screenLimit = ((NSScreen.main?.visibleFrame.height ?? 900) - windowChrome)
        return NSSize(width: pageWidth, height: min(contentHeight, max(minimumPageHeight, screenLimit)))
    }

    private static func rowLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text.isEmpty ? "" : "\(text):")
        label.alignment = .right
        return label
    }
}
