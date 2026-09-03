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
            ("Default playhead", SettingsForm.popUp([("Normal", 0), ("Timecode", 1)], key: .defaultPlayhead)),
            ("", SettingsForm.note("Normal opens a file with the slider and clock times. Timecode opens the timeline, with an editable SMPTE timecode and a frame-accurate track.")),
            ("Timeline size", SettingsForm.popUp([("Full size", 1), ("Compact", 0)], key: .timelineStyle)),
            ("", SettingsForm.note("Both apply to the file playing now as well as the next one. Press T or click the timeline button in the playback controls to switch playheads at any time.")),
        ], footer: reset)
    }

    @objc private func resetToDefaults(_ sender: Any?) {
        NSUserDefaultsController.shared.revertToInitialValues(sender)
    }
}
