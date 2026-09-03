import Foundation

struct AppInputSourceMapping: Codable, Equatable, Sendable {
    var bundleId: String
    var inputSourceId: String
    var isEnabled: Bool

    init(bundleId: String, inputSourceId: String, isEnabled: Bool = true) {
        self.bundleId = bundleId
        self.inputSourceId = inputSourceId
        self.isEnabled = isEnabled
    }

    /// Custom decode so that JSON produced by older versions of SwiftType (which did not store
    /// isEnabled) is read back with the correct default of true rather than failing to decode.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bundleId = try c.decode(String.self, forKey: .bundleId)
        inputSourceId = try c.decode(String.self, forKey: .inputSourceId)
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
    }
}

/// Whether a commit appends the trailing space the active `TypingRules` ask for.
enum CommitSpacing: String, CaseIterable, Sendable {
    case withTrailingSpace
    case withoutTrailingSpace

    var title: String {
        switch self {
        case .withTrailingSpace: "With Trailing Space"
        case .withoutTrailingSpace: "Without Trailing Space"
        }
    }
}

/// The keys that commit a candidate. Each carries its own `CommitSpacing` setting so
/// Return, the number keys and Space can be configured independently.
enum CommitTrigger: String, CaseIterable, Sendable {
    case returnKey
    case numberKey
    case space

    var title: String {
        switch self {
        case .returnKey: "Return Key"
        case .numberKey: "Number Keys"
        case .space: "Space Key"
        }
    }

    var defaultsKey: String { "general.commitSpacing.\(rawValue)" }
}

@MainActor final class SettingsManager {
    static let shared = SettingsManager()

    private static let mappingsKey = "appInputSourceMappings"

    private(set) var mappings: [AppInputSourceMapping]
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        guard let data = defaults.data(forKey: Self.mappingsKey) else {
            mappings = []
            return
        }
        guard let decoded = try? JSONDecoder().decode([AppInputSourceMapping].self, from: data) else {
            Log.settingsManager.error("SettingsManager — failed to decode mappings; resetting to empty")
            mappings = []
            return
        }
        mappings = decoded
    }

    // MARK: - Queries

    func inputSourceID(for bundleId: String) -> String? {
        guard let mapping = mappings.first(where: { $0.bundleId == bundleId }),
              mapping.isEnabled,
              !mapping.inputSourceId.isEmpty else { return nil }
        return mapping.inputSourceId
    }

    func hasMapping(for bundleId: String) -> Bool {
        mappings.contains { $0.bundleId == bundleId }
    }

    // MARK: - Mutations

    func addMapping(_ mapping: AppInputSourceMapping) {
        guard !hasMapping(for: mapping.bundleId) else { return }
        mappings.append(mapping)
        save()
    }

    func removeMapping(at index: Int) {
        guard mappings.indices.contains(index) else { return }
        mappings.remove(at: index)
        save()
    }

    func moveMapping(from fromIndex: Int, to toIndex: Int) {
        guard fromIndex != toIndex,
              mappings.indices.contains(fromIndex),
              mappings.indices.contains(toIndex) else { return }
        let mapping = mappings.remove(at: fromIndex)
        mappings.insert(mapping, at: toIndex)
        // No notification — the table view animates the row move itself via moveRow(at:to:)
        persistMappings()
    }

    func updateMapping(at index: Int, bundleId: String? = nil,
                       inputSourceId: String? = nil, isEnabled: Bool? = nil)
    {
        guard mappings.indices.contains(index) else { return }
        if let bundleId { mappings[index].bundleId = bundleId }
        if let inputSourceId { mappings[index].inputSourceId = inputSourceId }
        if let isEnabled { mappings[index].isEnabled = isEnabled }
        save()
    }

    // MARK: - Next Word Predictions

    private static let nextWordPredictionsKey = "general.nextWordPredictionsEnabled"

    var isNextWordPredictionsEnabled: Bool {
        defaults.object(forKey: Self.nextWordPredictionsKey) == nil
            ? false
            : defaults.bool(forKey: Self.nextWordPredictionsKey)
    }

    func setNextWordPredictionsEnabled(_ enabled: Bool) {
        guard enabled != isNextWordPredictionsEnabled else { return }
        defaults.set(enabled, forKey: Self.nextWordPredictionsKey)
        NotificationCenter.default.post(name: .nextWordPredictionsSettingDidChange, object: nil)
    }

    // MARK: - Commit Spacing

    /// Defaults to `.withTrailingSpace` — an unset or unrecognised stored value falls back to it.
    func commitSpacing(for trigger: CommitTrigger) -> CommitSpacing {
        guard let raw = defaults.string(forKey: trigger.defaultsKey),
              let spacing = CommitSpacing(rawValue: raw) else { return .withTrailingSpace }
        return spacing
    }

    func setCommitSpacing(_ spacing: CommitSpacing, for trigger: CommitTrigger) {
        guard spacing != commitSpacing(for: trigger) else { return }
        defaults.set(spacing.rawValue, forKey: trigger.defaultsKey)
        NotificationCenter.default.post(name: .commitSpacingDidChange, object: nil)
    }

    /// Triggers flipped together by the ⌥+` shortcut. Return is deliberately left out so it
    /// keeps whatever the Settings pane says.
    static let shortcutTriggers: [CommitTrigger] = [.numberKey, .space]

    /// True when the shortcut-controlled triggers commit without a trailing space.
    /// `.numberKey` is the reference, so a half-applied pair reads as "on".
    var isTrailingSpaceSuppressed: Bool {
        commitSpacing(for: .numberKey) == .withoutTrailingSpace
    }

    /// Flips `shortcutTriggers` between the two spacings and returns the new value.
    @discardableResult
    func toggleTrailingSpaceSuppression() -> CommitSpacing {
        let next: CommitSpacing = isTrailingSpaceSuppressed ? .withTrailingSpace : .withoutTrailingSpace
        for trigger in Self.shortcutTriggers {
            setCommitSpacing(next, for: trigger)
        }
        return next
    }

    // MARK: - Commit Spacing Shortcut

    private static let hotkeyKeyCodeKey = "general.commitSpacingHotkey.keyCode"
    private static let hotkeyModifiersKey = "general.commitSpacingHotkey.modifiers"
    private static let hotkeyLabelKey = "general.commitSpacingHotkey.label"

    /// ⌥+` — grave (key code 50) with Option (`NSEvent.ModifierFlags.option.rawValue`).
    /// Stored as raw values so this file stays AppKit-free.
    static let defaultHotkey: (keyCode: UInt16, modifiers: UInt, label: String) =
        (keyCode: 50, modifiers: 1 << 19, label: "⌥+`")

    var commitSpacingHotkey: (keyCode: UInt16, modifiers: UInt, label: String) {
        guard defaults.object(forKey: Self.hotkeyKeyCodeKey) != nil else { return Self.defaultHotkey }
        return (
            keyCode: UInt16(defaults.integer(forKey: Self.hotkeyKeyCodeKey)),
            modifiers: UInt(defaults.integer(forKey: Self.hotkeyModifiersKey)),
            label: defaults.string(forKey: Self.hotkeyLabelKey) ?? Self.defaultHotkey.label
        )
    }

    func setCommitSpacingHotkey(keyCode: UInt16, modifiers: UInt, label: String) {
        defaults.set(Int(keyCode), forKey: Self.hotkeyKeyCodeKey)
        defaults.set(Int(modifiers), forKey: Self.hotkeyModifiersKey)
        defaults.set(label, forKey: Self.hotkeyLabelKey)
        NotificationCenter.default.post(name: .commitSpacingDidChange, object: nil)
    }

    func resetCommitSpacingHotkey() {
        defaults.removeObject(forKey: Self.hotkeyKeyCodeKey)
        defaults.removeObject(forKey: Self.hotkeyModifiersKey)
        defaults.removeObject(forKey: Self.hotkeyLabelKey)
        NotificationCenter.default.post(name: .commitSpacingDidChange, object: nil)
    }

    // MARK: - Private

    /// Persists the current mappings array to UserDefaults without posting a notification.
    /// Used directly by moveMapping (which suppresses the notification so the table view
    /// can animate the row move itself) and indirectly by save().
    private func persistMappings() {
        if let data = try? JSONEncoder().encode(mappings) {
            defaults.set(data, forKey: Self.mappingsKey)
        } else {
            Log.settingsManager.error("SettingsManager — failed to encode mappings")
        }
    }

    private func save() {
        persistMappings()
        NotificationCenter.default.post(name: .appMappingsDidChange, object: nil)
    }
}
