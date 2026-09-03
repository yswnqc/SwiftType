import AppKit
import InputMethodKit
import os

/// Buffer commit, candidate selection, and marked-text helpers.
extension InputController {
    // MARK: - Composition

    func commitCompositionBuffer(client: any IMKTextInput) {
        let text = state.compositionBuffer
        if text.isEmpty {
            // Nothing to commit — clear any lingering marked text and hide predictions.
            client.setMarkedText(
                "",
                selectionRange: NSRange(location: 0, length: 0),
                replacementRange: Constants.replacementNotFound,
            )
            cancelPredictions()
            return
        }
        Log.inputController.info("Committing buffer: \(text, privacy: .public)")
        state.appendToContext(text)
        client.insertText(text, replacementRange: Constants.replacementNotFound)
        state.compositionBuffer = ""
        cancelPredictions()
    }

    /// The `commitWord` trailing-space override for `trigger`: `nil` defers to `TypingRules`,
    /// `false` suppresses the space they would add.
    func insertsSpace(for trigger: CommitTrigger) -> Bool? {
        SettingsManager.shared.commitSpacing(for: trigger) == .withoutTrailingSpace ? false : nil
    }

    /// `insertsSpace` overrides the active `TypingRules` when non-nil. The committing keys
    /// pass their own setting through it.
    func commitWord(_ word: String, client: any IMKTextInput, insertsSpace: Bool? = nil) {
        let appendsSpace = insertsSpace ?? state.typingRules.insertsTrailingSpace
        let committed = appendsSpace ? word + " " : word
        client.insertText(committed, replacementRange: Constants.replacementNotFound)
        state.appendToContext(committed)
        state.compositionBuffer = ""
        state.didAutoInsertTrailingSpace = appendsSpace
        cancelPredictions()
    }

    // MARK: - Candidate Selection

    /// Commits the prediction at `index` in `state.currentPredictions`.
    /// Applies `preserveCapitalization` in composition mode; uses the prediction as-is in
    /// next-word mode (consistent with pre-existing behaviour for number-key commits).
    func selectCandidateByIndex(_ index: Int, client: any IMKTextInput) {
        guard index < state.currentPredictions.count else { return }

        let prediction = state.currentPredictions[index]
        let word = state.isNextWordMode
            ? prediction
            : state.typingRules.preserveCapitalization(
                original: state.compositionBuffer,
                suggested: prediction,
            )

        Log.inputController.info("Selected candidate \(index + 1, privacy: .public): \(word, privacy: .public) (nextWord=\(self.state.isNextWordMode ? 1 : 0, privacy: .public))")
        commitWord(word, client: client, insertsSpace: insertsSpace(for: .numberKey))
    }

    // MARK: - Marked Text

    func updateMarkedText(client: any IMKTextInput) {
        setMarkedText(state.compositionBuffer, client: client)
    }

    private func setMarkedText(_ text: String, client: any IMKTextInput) {
        let attrString = NSAttributedString(string: text, attributes: Self.markedTextAttributes)
        client.setMarkedText(
            attrString,
            selectionRange: NSRange(location: text.count, length: 0),
            replacementRange: Constants.replacementNotFound,
        )
    }
}
