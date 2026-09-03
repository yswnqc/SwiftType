/// English-specific `TypingRules` conformance.
///
/// Supplies the three character sets that drive auto-space removal, composition-buffer
/// continuation (contractions), and sentence-boundary detection. Both protocol
/// methods (`preserveCapitalization`, `applyCapitalization`) are inherited from
/// the default implementations in `TypingRules`.
struct EnglishTypingRules: TypingRules, Sendable {
    static let shared = EnglishTypingRules()

    /// Punctuation that removes an auto-inserted trailing space when typed immediately
    /// after a committed word. Includes closing brackets/quotes and common sentence
    /// punctuation. Note: U+2019 (') is also in `compositionContinuationMarks`; the
    /// contraction check in `handleCharacterInput` runs first, so a mid-word apostrophe
    /// never reaches the auto-space-removal path.
    ///
    /// This set has **14 members**; `TypingRulesEdgeCaseTests.testEnglishAutoRemoveSpaceCharsExactCount` locks this in.
    let autoRemoveSpaceChars: Set<Character> = [
        ".", ",", "!", "?", ":", ";", ")", "]", "}", "%",
        "\u{201D}", "\u{2019}", "\u{00BB}", "\u{2026}",
    ]

    /// Characters that extend the composition buffer mid-word. U+0027 (') covers
    /// straight-apostrophe contractions ("don't"); U+2019 (') covers smart-quote
    /// contractions typed by macOS's auto-substitution.
    ///
    /// This set has **2 members**; `TypingRulesEdgeCaseTests.testEnglishCompositionContinuationMarksExactCount` locks this in.
    let compositionContinuationMarks: Set<Character> = ["'", "\u{2019}"]

    /// Characters that mark sentence boundaries — the standard English sentence-enders
    /// plus the Unicode ellipsis (U+2026) which macOS auto-substitutes from `...`.
    ///
    /// This set has **4 members**; `TypingRulesEdgeCaseTests.testEnglishSentenceEndingCharsExactCount` locks this in.
    let sentenceEndingChars: Set<Character> = [".", "!", "?", "\u{2026}"]

    /// The first-person pronoun and its contractions, which English capitalises anywhere in
    /// a sentence. Contractions need their own entries because an apostrophe is a
    /// `compositionContinuationMark`, so "i'm" arrives as a single word to commit.
    private static let alwaysCapitalized: [String: String] = [
        "i": "I", "i'm": "I'm", "i'll": "I'll", "i've": "I've", "i'd": "I'd",
        "i\u{2019}m": "I\u{2019}m", "i\u{2019}ll": "I\u{2019}ll",
        "i\u{2019}ve": "I\u{2019}ve", "i\u{2019}d": "I\u{2019}d",
    ]

    func autocapitalize(_ word: String) -> String {
        Self.alwaysCapitalized[word.lowercased()] ?? word
    }
}
