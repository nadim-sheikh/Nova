import Foundation

/// User-editable shortcut map, persisted as JSON in UserDefaults. Actions without a saved
/// binding fall back to their factory default.
final class KeyBindings {
    enum AssignmentResult: Equatable {
        case assigned
        case conflict(PlayerAction)
    }

    static let shared = KeyBindings()
    static let storageKey = "keyBindings"

    private let defaults: UserDefaults
    private var overrides: [PlayerAction: KeyCombo] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    func combo(for action: PlayerAction) -> KeyCombo {
        overrides[action] ?? action.defaultCombo
    }

    func action(matching combo: KeyCombo) -> PlayerAction? {
        PlayerAction.allCases.first { self.combo(for: $0).matches(combo) }
    }

    /// Shuttle keys are tracked on key-up as well, where modifier state may already have changed,
    /// so they match on the physical key alone.
    func shuttleAction(forKeyCode keyCode: UInt16) -> PlayerAction? {
        PlayerAction.allCases.first { $0.isShuttle && combo(for: $0).keyCode == keyCode }
    }

    func assign(_ combo: KeyCombo, to action: PlayerAction) -> AssignmentResult {
        if let owner = self.action(matching: combo), owner != action {
            return .conflict(owner)
        }
        overrides[action] = combo
        save()
        return .assigned
    }

    func reset(_ action: PlayerAction) {
        overrides[action] = nil
        save()
    }

    func resetAll() {
        overrides = [:]
        save()
    }

    private func load() {
        guard let data = defaults.data(forKey: KeyBindings.storageKey),
              let stored = try? JSONDecoder().decode([String: KeyCombo].self, from: data) else { return }
        for (name, combo) in stored {
            if let action = PlayerAction(rawValue: name) {
                overrides[action] = combo
            }
        }
    }

    private func save() {
        let stored = Dictionary(uniqueKeysWithValues: overrides.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(stored) {
            defaults.set(data, forKey: KeyBindings.storageKey)
        }
    }
}
