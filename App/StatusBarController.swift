import AppKit

@MainActor final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private var trailingSpaceItem: NSMenuItem?

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        if let button = statusItem.button {
            button.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        }
        statusItem.menu = buildMenu()

        updateStatusTitle()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateStatusTitle),
            name: .activePredictionLanguageDidChange,
            object: nil,
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateStatusTitle),
            name: NSTextInputContext.keyboardSelectionDidChangeNotification,
            object: nil,
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateStatusTitle),
            name: .commitSpacingDidChange,
            object: nil,
        )
    }

    // MARK: - Status Title

    /// The language code, with a dot appended while commits are suppressing the trailing
    /// space — the only at-a-glance indicator that the shortcut is engaged.
    @objc private func updateStatusTitle() {
        let code = LanguageManager.shared.effectiveBaseCode.uppercased()
        statusItem.button?.title = SettingsManager.shared.isTrailingSpaceSuppressed ? code + "·" : code
    }

    // MARK: - Menu

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        menu.addItem(.separator())

        let spacingItem = NSMenuItem(title: "",
                                     action: #selector(toggleTrailingSpace),
                                     keyEquivalent: "")
        spacingItem.target = self
        menu.addItem(spacingItem)
        trailingSpaceItem = spacingItem

        let settingsItem = NSMenuItem(title: "Settings", action: #selector(openSettings), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)
        return menu
    }

    @objc private func toggleTrailingSpace() {
        SettingsManager.shared.toggleTrailingSpaceSuppression()
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.showWindow()
    }

    @objc private func languageItemClicked(_ sender: NSMenuItem) {
        let code = sender.representedObject as? String ?? ""
        LanguageManager.shared.selectLanguage(code: code)
    }
}

// MARK: - NSMenuDelegate

extension StatusBarController: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        // The chord is shown in the title rather than as a key equivalent, which would go
        // stale as soon as the shortcut is reconfigured.
        let settings = SettingsManager.shared
        let action = settings.isTrailingSpaceSuppressed
            ? "Commit With Trailing Space"
            : "Commit Without Trailing Space"
        trailingSpaceItem?.title = "\(action)  (\(settings.commitSpacingHotkey.label))"

        while let first = menu.items.first, !first.isSeparatorItem {
            menu.removeItem(at: 0)
        }
        // Compute which language is currently active: pinned code, or system keyboard if unpinned.
        let selected = LanguageManager.shared.selectedCode
        let systemBase = NSSpellChecker.shared.language().baseLanguageCode
        let effectiveCode = selected.isEmpty
            ? (LanguageManager.shared.addedCodes.contains(systemBase) ? systemBase : "")
            : selected

        for (index, descriptor) in LanguageManager.shared.addedDescriptors.enumerated() {
            let item = NSMenuItem(title: descriptor.displayName,
                                  action: #selector(languageItemClicked(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = descriptor.code
            item.state = descriptor.code == effectiveCode ? .on : .off
            menu.insertItem(item, at: index)
        }
    }
}
