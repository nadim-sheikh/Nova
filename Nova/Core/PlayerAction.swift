import Foundation

/// Every keyboard-driven player action, with its factory-default shortcut.
enum PlayerAction: String, CaseIterable, Codable {
    case playPause
    case seekBackward
    case seekForward
    case stepBackward
    case stepForward
    case volumeUp
    case volumeDown
    case shuttleReverse
    case shuttlePause
    case shuttleForward
    case toggleTimeline

    var title: String {
        switch self {
        case .playPause: return "Play or Pause"
        case .seekBackward: return "Seek Backward"
        case .seekForward: return "Seek Forward"
        case .stepBackward: return "Step Frames Backward"
        case .stepForward: return "Step Frames Forward"
        case .volumeUp: return "Volume Up"
        case .volumeDown: return "Volume Down"
        case .shuttleReverse: return "Shuttle Reverse (J)"
        case .shuttlePause: return "Shuttle Pause (K)"
        case .shuttleForward: return "Shuttle Forward (L)"
        case .toggleTimeline: return "Expand or Collapse Timeline"
        }
    }

    var isShuttle: Bool {
        switch self {
        case .shuttleReverse, .shuttlePause, .shuttleForward: return true
        default: return false
        }
    }

    var defaultCombo: KeyCombo {
        switch self {
        case .playPause: return KeyCombo(keyCode: 49, keyLabel: "Space")
        case .seekBackward: return KeyCombo(keyCode: 123, keyLabel: "←")
        case .seekForward: return KeyCombo(keyCode: 124, keyLabel: "→")
        case .stepBackward: return KeyCombo(keyCode: 123, modifiers: .shift, keyLabel: "←")
        case .stepForward: return KeyCombo(keyCode: 124, modifiers: .shift, keyLabel: "→")
        case .volumeUp: return KeyCombo(keyCode: 126, keyLabel: "↑")
        case .volumeDown: return KeyCombo(keyCode: 125, keyLabel: "↓")
        case .shuttleReverse: return KeyCombo(keyCode: 38, keyLabel: "J")
        case .shuttlePause: return KeyCombo(keyCode: 40, keyLabel: "K")
        case .shuttleForward: return KeyCombo(keyCode: 37, keyLabel: "L")
        case .toggleTimeline: return KeyCombo(keyCode: 17, keyLabel: "T")
        }
    }
}
