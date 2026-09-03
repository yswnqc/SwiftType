import AppKit

// MARK: - General Tab

extension SettingsWindowController {
    func makeGeneralTab() -> NSView {
        let container = NSView()

        let stack = makeContentStack()
        stack.addArrangedSubview(makeNextWordPredictionsRow())
        for trigger in CommitTrigger.allCases {
            stack.addArrangedSubview(makeCommitSpacingRow(for: trigger))
        }
        stack.addArrangedSubview(makeHotkeyRow())

        container.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: Layout.edgeInset),
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -Layout.edgeInset),
        ])

        return container
    }

    // MARK: - Row Builders

    private func makeNextWordPredictionsRow() -> NSView {
        let toggle = NSSwitch()
        toggle.target = self
        toggle.action = #selector(nextWordPredictionsToggleChanged(_:))
        toggle.state = SettingsManager.shared.isNextWordPredictionsEnabled ? .on : .off
        toggle.controlSize = .small
        toggle.translatesAutoresizingMaskIntoConstraints = false
        nextWordPredictionsToggle = toggle
        return makeSettingsRow(label: "Next Word Predictions (experimental)", control: toggle)
    }

    /// One row per committing key. `tag` carries the trigger so a single action handler
    /// can serve all three pop-ups.
    private func makeCommitSpacingRow(for trigger: CommitTrigger) -> NSView {
        let spacings = CommitSpacing.allCases
        let popUp = makePopUp(
            items: spacings.map(\.title),
            selectedIndex: spacings.firstIndex(of: SettingsManager.shared.commitSpacing(for: trigger)) ?? 0,
            action: #selector(commitSpacingChanged(_:)),
        )
        popUp.tag = CommitTrigger.allCases.firstIndex(of: trigger) ?? 0
        commitSpacingPopUps[trigger] = popUp
        return makeSettingsRow(label: trigger.title, control: popUp)
    }

    /// The shortcut flips Number Keys and Space Key together; Return keeps its own setting.
    private func makeHotkeyRow() -> NSView {
        let button = HotkeyRecorderButton(title: "", target: nil, action: nil)
        button.bezelStyle = .rounded
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: Layout.popUpWidth).isActive = true
        button.restingTitle = { SettingsManager.shared.commitSpacingHotkey.label }
        button.title = SettingsManager.shared.commitSpacingHotkey.label
        button.target = button
        button.action = #selector(HotkeyRecorderButton.startRecording)
        button.onCapture = { keyCode, modifiers, label in
            SettingsManager.shared.setCommitSpacingHotkey(keyCode: keyCode, modifiers: modifiers, label: label)
        }
        button.onReset = { SettingsManager.shared.resetCommitSpacingHotkey() }
        hotkeyButton = button
        return makeSettingsRow(label: "Toggle Shortcut", control: button)
    }

    // MARK: - Actions

    @objc private func nextWordPredictionsToggleChanged(_ sender: NSSwitch) {
        SettingsManager.shared.setNextWordPredictionsEnabled(sender.state == .on)
    }

    @objc private func commitSpacingChanged(_ sender: NSPopUpButton) {
        let triggers = CommitTrigger.allCases
        let spacings = CommitSpacing.allCases
        guard triggers.indices.contains(sender.tag),
              spacings.indices.contains(sender.indexOfSelectedItem) else { return }
        SettingsManager.shared.setCommitSpacing(spacings[sender.indexOfSelectedItem], for: triggers[sender.tag])
    }

    // MARK: - Sync

    func syncGeneralControls() {
        nextWordPredictionsToggle?.state = SettingsManager.shared.isNextWordPredictionsEnabled ? .on : .off
        hotkeyButton?.title = SettingsManager.shared.commitSpacingHotkey.label
        for (trigger, popUp) in commitSpacingPopUps {
            popUp.selectItem(at: CommitSpacing.allCases.firstIndex(of: SettingsManager.shared.commitSpacing(for: trigger)) ?? 0)
        }
    }
}

// MARK: - Hotkey Recorder

/// A button that records a key combination. Click it, then press the chord. Escape cancels,
/// Delete restores the default. A chord needs Command, Control or Option — Shift alone would
/// swallow ordinary typing.
@MainActor final class HotkeyRecorderButton: NSButton {
    var onCapture: ((UInt16, UInt, String) -> Void)?
    var onReset: (() -> Void)?
    /// Restores the resting title after recording ends, so the caller owns the wording.
    var restingTitle: () -> String = { "" }

    private var isRecording = false

    private static let modifierMask: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
    /// Shift alone is not enough to make a chord safe to intercept.
    private static let requiredMask: NSEvent.ModifierFlags = [.command, .control, .option]

    override var acceptsFirstResponder: Bool { true }

    @objc func startRecording() {
        isRecording = true
        title = "Type a shortcut…"
        window?.makeFirstResponder(self)
    }

    func stopRecording() {
        isRecording = false
        title = restingTitle()
        if window?.firstResponder === self { window?.makeFirstResponder(nil) }
    }

    override func resignFirstResponder() -> Bool {
        if isRecording { stopRecording() }
        return super.resignFirstResponder()
    }

    /// Claims chords like ⌘Q while recording so they configure the shortcut instead of
    /// firing their menu item.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording else { return super.performKeyEquivalent(with: event) }
        keyDown(with: event)
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { return super.keyDown(with: event) }

        switch KeyCode(rawValue: event.keyCode) {
        case .escape:
            stopRecording()
            return
        case .backspace:
            onReset?()
            stopRecording()
            return
        default:
            break
        }

        let modifiers = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .intersection(Self.modifierMask)

        guard !modifiers.intersection(Self.requiredMask).isEmpty else {
            NSSound.beep()
            return
        }

        onCapture?(event.keyCode, modifiers.rawValue, Self.label(for: event, modifiers: modifiers))
        stopRecording()
    }

    /// e.g. ⌥+` or ⌃+⇧+Space — modifier glyphs in the order macOS shows them.
    static func label(for event: NSEvent, modifiers: NSEvent.ModifierFlags) -> String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("⌃") }
        if modifiers.contains(.option) { parts.append("⌥") }
        if modifiers.contains(.shift) { parts.append("⇧") }
        if modifiers.contains(.command) { parts.append("⌘") }

        switch KeyCode(rawValue: event.keyCode) {
        case .space: parts.append("Space")
        case .returnKey: parts.append("Return")
        case .tab: parts.append("Tab")
        default:
            let char = event.charactersIgnoringModifiers ?? ""
            parts.append(char.isEmpty ? "Key \(event.keyCode)" : char.uppercased())
        }
        return parts.joined(separator: "+")
    }
}
