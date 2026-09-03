import AppKit

final class GeneralSettingsViewController: NSViewController {
    override func loadView() {
        let reset = NSButton(title: "Reset to Defaults", target: self, action: #selector(resetToDefaults(_:)))
        view = SettingsForm.page(rows: [
            ("Appearance", SettingsForm.segmented([("System", 0), ("Light", 1), ("Dark", 2)], key: .appearanceMode)),
            ("", SettingsForm.note("System follows the macOS Light or Dark setting and changes with it. Your choice is remembered.")),
            ("Window", SettingsForm.checkbox("Resize to the video's size when a file opens", key: .fitWindowToVideo)),
            ("", SettingsForm.checkbox("Keep the video's aspect ratio while resizing", key: .lockAspectRatio)),
            ("", SettingsForm.checkbox("Float on top of other apps", key: .floatOnTop)),
            ("Timeline", SettingsForm.popUp([("Full size", 1), ("Compact", 0)], key: .timelineStyle)),
            ("", SettingsForm.note("Press T or click the timeline button in the playback controls to open it inside them. Its timecode can be typed into, and the button beside it switches between the two sizes.")),
        ], footer: reset)
    }

    @objc private func resetToDefaults(_ sender: Any?) {
        NSUserDefaultsController.shared.revertToInitialValues(sender)
    }
}
