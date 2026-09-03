import AppKit

final class TimecodeSettingsViewController: NSViewController {
    override func loadView() {
        view = SettingsForm.page(rows: [
            ("Title bar shows", SettingsForm.checkbox("Frame number", key: .showFrameNumber)),
            ("", SettingsForm.checkbox("Shuttle speed when not at 1×", key: .showShuttleSpeed)),
            ("", SettingsForm.checkbox("File name", key: .showFileName)),
            ("First frame is numbered", SettingsForm.popUp([("0", 0), ("1", 1)], key: .frameNumberBase)),
            ("", SettingsForm.note("Timecode always comes from the file's own frame rate. 29.97 and 59.94 fps use drop-frame counting, shown with a semicolon before the frames.")),
        ])
    }
}
