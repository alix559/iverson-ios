/// Turn spoken English number words into Arabic digits for numeral input.
//Sound Names codes are three digits (e.g. 001); digits accumulate until a full code is ready.

import Foundation

enum NumeralTranscript {
    /// Locale used for speech recognition (English works best for digit dictation here).
    static let locale = Locale(identifier: "en-US")

    /// Sound Names codes are always this many digits.
    static let codeLength = 3

    private static let ones: [String: Int] = [
        "zero": 0, "oh": 0, "o": 0, "nought": 0,
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
        "six": 6, "seven": 7, "eight": 8, "nine": 9,
        "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14,
        "fifteen": 15, "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19
    ]

    private static let tens: [String: Int] = [
        "twenty": 20, "thirty": 30, "forty": 40, "fourty": 40,
        "fifty": 50, "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90
    ]

    private static let scales: [String: Int] = [
        "hundred": 100,
        "thousand": 1_000,
        "million": 1_000_000,
        "billion": 1_000_000_000
    ]

    /// Prefer digits for PC typing: convert number words, keep existing digits.
    static func digitize(_ raw: String) -> String {
        let cleaned = raw
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: ",", with: "")
            .lowercased()

        // Strip punctuation so STT tails like "two." still match "two".
        let tokens = cleaned
            .split { !$0.isLetter && !$0.isNumber && $0 != "." }
            .map { String($0).trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty }

        guard !tokens.isEmpty else { return raw.trimmingCharacters(in: .whitespacesAndNewlines) }

        // Already mostly digits / decimal — pass through (no spaces between pure integers).
        if tokens.allSatisfy({ Double($0) != nil }) {
            if tokens.allSatisfy({ $0.allSatisfy(\.isNumber) && !$0.contains(".") }) {
                return tokens.joined()
            }
            return tokens.joined(separator: " ")
        }

        // Spoken digit sequence: "one two three" → "123"
        if tokens.allSatisfy({ ones[$0] != nil && ones[$0]! < 10 }) {
            return tokens.map { String(ones[$0]!) }.joined()
        }

        if let value = parseNumberPhrase(tokens) {
            return String(value)
        }

        // Mixed phrase: convert runs of number words, leave the rest.
        var out: [String] = []
        var i = 0
        while i < tokens.count {
            if Double(tokens[i]) != nil {
                out.append(tokens[i])
                i += 1
                continue
            }
            var j = i
            while j < tokens.count, isNumberWord(tokens[j]) { j += 1 }
            if j > i, let value = parseNumberPhrase(Array(tokens[i..<j])) {
                out.append(String(value))
                i = j
            } else {
                out.append(tokens[i])
                i += 1
            }
        }
        return out.joined(separator: " ")
    }

    /// True when digitize produced only numeric tokens (ready for Sound Names lookup).
    static func isNumericPayload(_ text: String) -> Bool {
        let compact = text.filter { !$0.isWhitespace }
        return !compact.isEmpty && compact.allSatisfy(\.isNumber)
    }

    /// Pull every decimal digit from a digitized phrase, in order.
    static func extractDigits(_ text: String) -> [Character] {
        text.filter(\.isNumber).map { $0 }
    }

    /// Zero-pad / trim a code to `codeLength` digits when possible.
    static func normalizeCode(_ text: String) -> String? {
        let digits = String(extractDigits(text))
        guard !digits.isEmpty, digits.count <= codeLength else { return nil }
        let pad = String(repeating: "0", count: codeLength - digits.count)
        return pad + digits
    }

    private static func isNumberWord(_ token: String) -> Bool {
        token == "and" || ones[token] != nil || tens[token] != nil || scales[token] != nil
    }

    private static func parseNumberPhrase(_ tokens: [String]) -> Int? {
        let filtered = tokens.filter { $0 != "and" }
        guard !filtered.isEmpty,
              filtered.allSatisfy({ ones[$0] != nil || tens[$0] != nil || scales[$0] != nil }) else {
            return nil
        }

        var total = 0
        var current = 0
        var saw = false

        for word in filtered {
            if let n = ones[word] {
                current += n
                saw = true
            } else if let n = tens[word] {
                current += n
                saw = true
            } else if let scale = scales[word] {
                if scale == 100 {
                    current = max(current, 1) * scale
                } else {
                    current = max(current, 1) * scale
                    total += current
                    current = 0
                }
                saw = true
            }
        }
        guard saw else { return nil }
        return total + current
    }
}

/// Collects spoken digits until a full 3-digit Sound Names code is ready to send.
@Observable
final class DigitCodeBuffer {
    private(set) var digits: [Character] = []

    var pendingDisplay: String {
        let have = String(digits)
        let need = NumeralTranscript.codeLength - digits.count
        guard need > 0 else { return have }
        return have + String(repeating: "•", count: need)
    }

    var isEmpty: Bool { digits.isEmpty }

    func clear() {
        digits.removeAll()
    }

    /// Ingest digitized text; returns completed 3-digit codes to transmit.
    @discardableResult
    func ingest(_ digitized: String) -> [String] {
        var codes: [String] = []
        for ch in NumeralTranscript.extractDigits(digitized) {
            digits.append(ch)
            while digits.count >= NumeralTranscript.codeLength {
                codes.append(String(digits.prefix(NumeralTranscript.codeLength)))
                digits.removeFirst(NumeralTranscript.codeLength)
            }
        }
        return codes
    }
}
