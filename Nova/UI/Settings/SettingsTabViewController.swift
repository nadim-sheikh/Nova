import AppKit

/// Toolbar-style tab controller hosting each settings page. Sizes the window to the selected
/// page, keeping the window's top edge in place; the user can still shrink it and the page scrolls.
final class SettingsTabViewController: NSTabViewController {
    override init(nibName nibNameOrNil: NSNib.Name?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        tabStyle = .toolbar
        transitionOptions = []
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        addTab(GeneralSettingsViewController(), label: "General", symbol: "gearshape")
        addTab(PlaybackSettingsViewController(), label: "Playback", symbol: "play.circle")
        addTab(TimecodeSettingsViewController(), label: "Timecode", symbol: "timer")
        addTab(KeyboardSettingsViewController(), label: "Keyboard", symbol: "keyboard")
        addTab(AboutSettingsViewController(), label: "About", symbol: "info.circle")
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        fitWindow(to: tabViewItems[selectedTabViewItemIndex], animate: false)
    }

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        if let tabViewItem {
            fitWindow(to: tabViewItem, animate: true)
        }
    }

    private func addTab(_ controller: NSViewController, label: String, symbol: String) {
        // In toolbar style the window title follows the selected child controller's title.
        controller.title = label
        let item = NSTabViewItem(viewController: controller)
        item.label = label
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        addTabViewItem(item)
    }

    private func fitWindow(to item: NSTabViewItem, animate: Bool) {
        guard let window = view.window, let page = item.viewController else { return }
        let size = SettingsForm.preferredSize(for: page.view)
        let currentContent = window.contentRect(forFrameRect: window.frame)
        let content = NSRect(x: 0, y: 0, width: max(size.width, currentContent.width), height: size.height)
        var frame = window.frameRect(forContentRect: content)
        frame.origin = NSPoint(x: window.frame.minX, y: window.frame.maxY - frame.height)
        frame = window.constrainFrameRect(frame, to: window.screen)
        window.setFrame(frame, display: true, animate: animate)
    }
}
