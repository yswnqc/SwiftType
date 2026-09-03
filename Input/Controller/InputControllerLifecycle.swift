import AppKit
import InputMethodKit
import os

/// IMKInputController activation, deactivation, and document-seeding helper.
extension InputController {
    // MARK: - IMKInputController Overrides

    override func activateServer(_ sender: Any!) {
        let client = sender as? (any IMKTextInput)
        MainActor.assumeIsolated {
            Log.inputController.info("activateServer — sender: \(client?.bundleIdentifier() ?? "nil", privacy: .public)")
            if let bundleId = client?.bundleIdentifier() {
                InputSourceSwitcher.shared?.handleAppActivation(bundleId: bundleId)
            }
            resetState()
            refreshRules()
            if let client { seedContextFromDocument(client: client) }
        }
    }

    override func deactivateServer(_ sender: Any!) {
        let client = sender as? (any IMKTextInput)
        MainActor.assumeIsolated {
            Log.inputController.info("deactivateServer — sender: \(client?.bundleIdentifier() ?? "nil", privacy: .public)")
            if let client {
                commitCompositionBuffer(client: client)
            }
            CandidateWindow.shared.hide()
        }
    }

    override func composedString(_: Any!) -> Any! {
        state.compositionBuffer
    }

    override func originalString(_: Any!) -> NSAttributedString! {
        NSAttributedString(string: state.compositionBuffer)
    }

    override func commitComposition(_ sender: Any!) {
        let client = sender as? (any IMKTextInput)
        MainActor.assumeIsolated {
            Log.inputController.info("commitComposition called by system")
            if let client {
                commitCompositionBuffer(client: client)
            }
        }
    }

    // MARK: - Document Seeding

    /// Seeds `typingContext` from the document text preceding the cursor to provide
    /// context for spell-checking and predictions when switching to SwiftType mid-document.
    /// Falls back gracefully when the app does not support text queries.
    private func seedContextFromDocument(client: any IMKTextInput) {
        let cursorPos = client.selectedRange().location
        guard cursorPos != NSNotFound, cursorPos > 0 else { return }
        let fetchLength = min(cursorPos, InputState.maxContextLength)
        let range = NSRange(location: cursorPos - fetchLength, length: fetchLength)
        guard let text = client.attributedSubstring(from: range)?.string, !text.isEmpty else { return }
        state.typingContext = text
        Log.inputController.info("seedContextFromDocument — seeded \(text.count, privacy: .public) chars")
    }
}

// MARK: - Text Input Menu

/// The menu shown under the input source in the menu bar. IMK calls `menu()` every time it
/// draws, so the items are rebuilt from current state rather than kept in sync by hand.
extension InputController {
    override func menu() -> NSMenu! {
        let menu = NSMenu()

        let selected = LanguageManager.shared.selectedCode
        let systemBase = NSSpellChecker.shared.language().baseLanguageCode
        let effectiveCode = selected.isEmpty
            ? (LanguageManager.shared.addedCodes.contains(systemBase) ? systemBase : "")
            : selected

        for descriptor in LanguageManager.shared.addedDescriptors {
            let item = NSMenuItem(title: descriptor.displayName,
                                  action: #selector(selectLanguageFromMenu(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = descriptor.code
            item.state = descriptor.code == effectiveCode ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let settings = SettingsManager.shared
        let spacing = NSMenuItem(title: "Commit Without Trailing Space  (\(settings.commitSpacingHotkey.label))",
                                 action: #selector(toggleTrailingSpaceFromMenu),
                                 keyEquivalent: "")
        spacing.target = self
        spacing.state = settings.isTrailingSpaceSuppressed ? .on : .off
        menu.addItem(spacing)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings…",
                                      action: #selector(openSettingsFromMenu),
                                      keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)

        return menu
    }

    @objc private func selectLanguageFromMenu(_ sender: NSMenuItem) {
        LanguageManager.shared.selectLanguage(code: sender.representedObject as? String ?? "")
    }

    @objc private func toggleTrailingSpaceFromMenu() {
        SettingsManager.shared.toggleTrailingSpaceSuppression()
    }

    @objc private func openSettingsFromMenu() {
        SettingsWindowController.shared.showWindow()
    }
}
