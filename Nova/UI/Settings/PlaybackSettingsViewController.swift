import AppKit

final class PlaybackSettingsViewController: NSViewController {
    override func loadView() {
        view = SettingsForm.page(rows: [
            ("Opening", SettingsForm.checkbox("Start playing when a file opens", key: .autoplayOnOpen)),
            ("", SettingsForm.checkbox("Loop playback", key: .loopPlayback)),
            ("Arrow keys seek by", SettingsForm.popUp([
                ("1 second", 1), ("2 seconds", 2), ("5 seconds", 5), ("10 seconds", 10), ("30 seconds", 30),
            ], key: .seekStepSeconds)),
            ("Frame step", SettingsForm.popUp([
                ("1 frame", 1), ("2 frames", 2), ("5 frames", 5), ("10 frames", 10),
            ], key: .frameStepCount)),
            ("", SettingsForm.note("Shift + ← / → moves by this many frames. Change the keys in the Keyboard tab.")),
            ("Volume step", SettingsForm.popUp([
                ("1%", 1), ("2%", 2), ("5%", 5), ("10%", 10),
            ], key: .volumeStepPercent)),
            ("Shuttle top speed", SettingsForm.popUp([
                ("4×", 4), ("8×", 8), ("16×", 16), ("32×", 32),
            ], key: .shuttleMaxSpeed)),
            ("", SettingsForm.note("Tap L or J repeatedly to ramp from 1× up to this speed.")),
            ("Slow motion", SettingsForm.popUp([
                ("¼× (0.25)", 25), ("½× (0.5)", 50),
            ], key: .slowMotionPercent)),
            ("", SettingsForm.note("Hold K and press L or J to play slowly in either direction.")),
        ])
    }
}
