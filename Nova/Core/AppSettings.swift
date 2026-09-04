import Foundation

/// Typed access to user preferences. Backed by UserDefaults so the Settings window can bind
/// its controls straight to the same keys through `NSUserDefaultsController`.
final class AppSettings {
    enum Key: String {
        case appearanceMode
        case fitWindowToVideo
        case lockAspectRatio
        case autoplayOnOpen
        case loopPlayback
        case seekStepSeconds
        case frameStepCount
        case volumeStepPercent
        case shuttleMaxSpeed
        case slowMotionPercent
        case showTimecodeInTitle
        case showFrameNumber
        case showShuttleSpeed
        case showFileName
        case frameNumberBase
        case floatOnTop
        case timelineStyle
        case defaultPlayhead

        /// Key path used by Cocoa bindings against `NSUserDefaultsController.shared`.
        var bindingKeyPath: String { "values.\(rawValue)" }
    }

    enum AppearanceMode: Int {
        case system = 0
        case light = 1
        case dark = 2
    }

    static let shared = AppSettings()

    static let defaultValues: [String: Any] = [
        Key.appearanceMode.rawValue: AppearanceMode.system.rawValue,
        Key.fitWindowToVideo.rawValue: true,
        Key.lockAspectRatio.rawValue: true,
        Key.autoplayOnOpen.rawValue: true,
        Key.loopPlayback.rawValue: false,
        Key.seekStepSeconds.rawValue: 5,
        Key.frameStepCount.rawValue: 1,
        Key.volumeStepPercent.rawValue: 5,
        Key.shuttleMaxSpeed.rawValue: 8,
        Key.slowMotionPercent.rawValue: 25,
        Key.showTimecodeInTitle.rawValue: false,
        Key.showFrameNumber.rawValue: false,
        Key.showShuttleSpeed.rawValue: true,
        Key.showFileName.rawValue: true,
        Key.frameNumberBase.rawValue: 0,
        Key.floatOnTop.rawValue: false,
        Key.timelineStyle.rawValue: 1,
        Key.defaultPlayhead.rawValue: 0,
    ]

    private static let shuttleSpeedLadder: [Float] = [1, 2, 4, 8, 16, 32]

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: AppSettings.defaultValues)
    }

    var appearanceMode: AppearanceMode {
        AppearanceMode(rawValue: defaults.integer(forKey: Key.appearanceMode.rawValue)) ?? .system
    }

    var fitWindowToVideo: Bool { defaults.bool(forKey: Key.fitWindowToVideo.rawValue) }
    var lockAspectRatio: Bool { defaults.bool(forKey: Key.lockAspectRatio.rawValue) }
    var autoplayOnOpen: Bool { defaults.bool(forKey: Key.autoplayOnOpen.rawValue) }
    var loopPlayback: Bool { defaults.bool(forKey: Key.loopPlayback.rawValue) }
    /// The panel already shows timecode and frame, so the title bar carries them only on request.
    var showTimecodeInTitle: Bool { defaults.bool(forKey: Key.showTimecodeInTitle.rawValue) }
    var showFrameNumber: Bool { defaults.bool(forKey: Key.showFrameNumber.rawValue) }
    var showShuttleSpeed: Bool { defaults.bool(forKey: Key.showShuttleSpeed.rawValue) }
    var showFileName: Bool { defaults.bool(forKey: Key.showFileName.rawValue) }

    /// Keeps the player window above every other app's windows.
    var floatOnTop: Bool {
        get { defaults.bool(forKey: Key.floatOnTop.rawValue) }
        set { defaults.set(newValue, forKey: Key.floatOnTop.rawValue) }
    }

    /// Whether the expanded timeline opens at full size (1) or compact (0); the timeline's own
    /// size button writes back here so the choice sticks.
    var timelineIsFull: Bool {
        get { defaults.integer(forKey: Key.timelineStyle.rawValue) != 0 }
        set { defaults.set(newValue ? 1 : 0, forKey: Key.timelineStyle.rawValue) }
    }

    /// Which playhead a file opens with: the normal slider (0) or the timecode timeline (1).
    var opensWithTimecodePlayhead: Bool {
        defaults.integer(forKey: Key.defaultPlayhead.rawValue) == 1
    }

    var seekStepSeconds: Double {
        max(0.1, defaults.double(forKey: Key.seekStepSeconds.rawValue))
    }

    /// Frames moved per step-key press.
    var frameStepCount: Int {
        max(1, defaults.integer(forKey: Key.frameStepCount.rawValue))
    }

    /// Volume change per arrow-key press, 0...1.
    var volumeStep: Float {
        Float(max(1, defaults.integer(forKey: Key.volumeStepPercent.rawValue))) / 100
    }

    /// J/L ramp, capped at the chosen top speed.
    var shuttleRampSteps: [Float] {
        let cap = Float(defaults.integer(forKey: Key.shuttleMaxSpeed.rawValue))
        let steps = AppSettings.shuttleSpeedLadder.filter { $0 <= cap }
        return steps.isEmpty ? [1] : steps
    }

    var slowMotionRate: Float {
        Float(max(1, defaults.integer(forKey: Key.slowMotionPercent.rawValue))) / 100
    }

    /// 0 or 1: the number shown for the first frame of a file.
    var frameNumberBase: Int {
        defaults.integer(forKey: Key.frameNumberBase.rawValue) == 1 ? 1 : 0
    }
}
