/// Map spoken basedpl glyph names (plus, rho, up-arrow, …) to glyphs for PC typing.

import Foundation

enum GlyphTranscript {
    /// Locale used for speech recognition.
    static let locale = Locale(identifier: "en-US")

    /// basedpl English name → glyph (same names as iverson `glyph_table.json` `ename`).
    static let nameToGlyph: [String: String] = [
        "plus": "+", "minus": "-", "times": "×", "obelus": "÷",
        "downstile": "⌊", "upstile": "⌈", "stile": "|", "star": "*",
        "circle-star": "⍟", "circle": "○", "pi": "π", "radical": "√",
        "exclamation": "!", "stile-tilde": "⍭", "circle-divide": "⨸",
        "quad-jot": "⌻", "inverted-question": "¿", "vee": "∨", "wedge": "∧",
        "wedge-bar": "⊼", "vee-bar": "⊽", "tilde": "~", "equals": "=",
        "not-equals": "≠", "less-than": "<", "less-than-or-equal": "≤",
        "greater-than": ">", "greater-than-or-equal": "≥",
        "equal-underbar": "≡", "equal-underbar-slash": "≢",
        "rho": "⍴", "comma": ",", "comma-bar": "⍪", "circle-stile": "⌽",
        "circle-bar": "⊖", "circle-backslash": "⍉",
        "up-arrow": "↑", "down-arrow": "↓", "up-down-arrow": "↕",
        "left-shoe": "⊂", "left-shoe-underbar": "⊆", "right-shoe": "⊃",
        "squad": "⌷", "iota": "⍳", "right-arrow-from-bar": "↦",
        "colon": ":", "iota-underbar": "⍸", "epsilon": "∊",
        "down-shoe": "∪", "up-shoe": "∩", "epsilon-underbar": "⍷",
        "delta-stile": "⍋", "del-stile": "⍒", "hash": "#",
        "down-tack": "⊤", "up-tack": "⊥", "domino": "⌹",
        "left-tack": "⊣", "right-tack": "⊢", "hydrant": "⍎", "thorn": "⍕",
        "slash": "/", "slash-bar": "⌿", "backslash": "\\", "backslash-bar": "⍀",
        "diaeresis": "¨", "superscript-b": "ᵇ", "tilde-diaeresis": "⍨",
        "circle-times": "⊗", "quad-equal": "⌸", "right-left-arrows": "⇄",
        "partial": "∂",
        "right-tail-arrow": "↣", "left-tail-arrow": "↢", "jot-diaeresis": "⍤",
        "jot": "∘", "quad-colon": "⍠", "circle-diaeresis": "⍥", "dot": ".",
        "star-diaeresis": "⍣", "circle-slash": "⊘", "diamond-underbar": "⍚",
        "at": "@", "quad-diamond": "⌺",
        "left-arrow": "←", "alpha": "⍺", "omega": "⍵",
        "alpha-underbar": "⍶", "omega-underbar": "⍹",
        "del": "∇", "del-diaeresis": "⍢", "question": "?",
        "error-guard": "::", "diamond": "⋄", "tricolon": "⁝",
        "lamp": "⍝", "quad": "⎕←", "bullet": "•", "zilde": "⍬",
        "overbar": "¯", "infinity": "∞",
        "true": "$t", "false": "$f", "nan": "$n", "caught-error": "$e",
    ]

    /// Speech forms: hyphens become spaces ("up arrow", "less than").
    private static let phrases: [(words: [String], glyph: String)] = {
        nameToGlyph
            .map { name, glyph in
                (name.split(separator: "-").map(String.init), glyph)
            }
            .sorted { $0.0.count > $1.0.count }
    }()

    /// Turn a spoken phrase into the glyphs to type on the PC.
    static func resolve(_ raw: String) -> String {
        let cleaned = raw
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: ",", with: " ")
            .lowercased()

        let tokens = cleaned
            .split { !$0.isLetter && !$0.isNumber }
            .map { String($0).trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty }

        guard !tokens.isEmpty else { return "" }

        var out = ""
        var i = 0
        while i < tokens.count {
            if let (len, glyph) = match(from: tokens, at: i) {
                out.append(glyph)
                i += len
            } else {
                // Skip unknown words (articles, fillers).
                i += 1
            }
        }
        return out
    }

    private static func match(from tokens: [String], at i: Int) -> (Int, String)? {
        for (words, glyph) in phrases {
            let end = i + words.count
            guard end <= tokens.count else { continue }
            if Array(tokens[i..<end]) == words {
                return (words.count, glyph)
            }
        }
        // Also accept the hyphenated name said as one token if STT joins it.
        let joined = tokens[i]
        if let glyph = nameToGlyph[joined] {
            return (1, glyph)
        }
        return nil
    }
}
