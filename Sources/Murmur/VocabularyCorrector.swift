import Foundation

/// Deterministic post-STT correction of custom vocabulary — names, acronyms,
/// jargon that Whisper predictably mangles ("open f g a" → "OpenFGA",
/// "pria" → "Priya").
///
/// Strategy (inspired by speak2's DictionaryProcessor): slide a window of 1–N
/// words over the transcript, squash the candidate to letters+digits, and
/// compare against each dictionary entry three ways — exact squashed match
/// (fixes casing and spacing), small edit distance, or matching phonetic key
/// with a looser distance bound. Longer windows win over shorter ones.
/// Thresholds are conservative: a wrong non-correction is cheaper than a
/// wrong correction.
struct VocabularyCorrector {
    private struct Entry {
        let term: String       // canonical form as the user typed it
        let squashed: String   // lowercased letters+digits only
        let wordCount: Int
        let phoneticKey: String
    }

    private struct Token {
        let leading: String    // leading punctuation, e.g. "("
        var core: String       // the word itself
        let trailing: String   // trailing punctuation, e.g. ",", "."
    }

    private let entries: [Entry]
    private let maxWindow: Int

    init(terms: [String]) {
        entries = terms.compactMap { raw in
            let term = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let squashed = Self.squash(term)
            // Very short entries would false-positive on everything.
            guard squashed.count >= 3 else { return nil }
            return Entry(
                term: term,
                squashed: squashed,
                wordCount: max(1, term.split(separator: " ").count),
                phoneticKey: Self.phoneticKey(squashed)
            )
        }
        // A term spoken with letters spelled out spans more words than the
        // written form ("open f g a" = 4 words for 1-word "OpenFGA").
        maxWindow = min(5, (entries.map(\.wordCount).max() ?? 1) + 3)
    }

    func correct(_ text: String) -> String {
        guard !entries.isEmpty, !text.isEmpty else { return text }

        var tokens = Self.tokenize(text)
        var consumed = [Bool](repeating: false, count: tokens.count)

        // Two phases: exact squashed matches claim their tokens first so a
        // fuzzy multi-word window can't swallow a neighbor of an exact hit
        // ("to openfga" fuzzy-matching OpenFGA and eating the "to").
        for exactOnly in [true, false] {
            for window in stride(from: maxWindow, through: 1, by: -1) {
                guard window <= tokens.count else { continue }
                var start = 0
                while start + window <= tokens.count {
                    let range = start..<(start + window)
                    guard !range.contains(where: { consumed[$0] }) else {
                        start += 1
                        continue
                    }
                    let candidate = Self.squash(range.map { tokens[$0].core }.joined())
                    if let entry = bestMatch(for: candidate, exactOnly: exactOnly) {
                        // Collapse the window into one token carrying the
                        // entry's canonical form, keeping outer punctuation.
                        let merged = Token(
                            leading: tokens[range.lowerBound].leading,
                            core: entry.term,
                            trailing: tokens[range.upperBound - 1].trailing
                        )
                        tokens.replaceSubrange(range, with: [merged])
                        consumed.replaceSubrange(range, with: [true])
                    }
                    start += 1
                }
            }
        }

        return tokens.map { $0.leading + $0.core + $0.trailing }.joined(separator: " ")
    }

    private func bestMatch(for candidate: String, exactOnly: Bool) -> Entry? {
        guard candidate.count >= 3 else { return nil }
        var best: (entry: Entry, ratio: Double)?

        for entry in entries {
            if candidate == entry.squashed {
                return entry
            }
            guard !exactOnly else { continue }
            // Skip hopeless length mismatches before paying for Levenshtein.
            guard abs(candidate.count - entry.squashed.count) <= 3 else { continue }

            let distance = Self.levenshtein(candidate, entry.squashed)
            let ratio = Double(distance) / Double(max(candidate.count, entry.squashed.count))
            let phoneticEqual = Self.phoneticKey(candidate) == entry.phoneticKey
            let threshold = phoneticEqual ? 0.45 : 0.23

            if ratio <= threshold, distance <= 3 || phoneticEqual {
                if best == nil || ratio < best!.ratio {
                    best = (entry, ratio)
                }
            }
        }
        return best?.entry
    }

    // MARK: - Text helpers

    private static func tokenize(_ text: String) -> [Token] {
        text.split(whereSeparator: \.isWhitespace).map { word in
            var core = Substring(word)
            var leading = ""
            var trailing = ""
            while let first = core.first, !first.isLetter, !first.isNumber {
                leading.append(first)
                core = core.dropFirst()
            }
            while let last = core.last, !last.isLetter, !last.isNumber {
                trailing.insert(last, at: trailing.startIndex)
                core = core.dropLast()
            }
            return Token(leading: leading, core: String(core), trailing: trailing)
        }
    }

    static func squash(_ text: String) -> String {
        String(text.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    /// Metaphone-lite: reduce a squashed word to a coarse sound signature so
    /// "pria"/"priya" or "sonos"/"sonus" collide while unrelated words don't.
    static func phoneticKey(_ squashed: String) -> String {
        var str = squashed.uppercased().filter(\.isLetter)
        guard !str.isEmpty else { return "" }

        for (from, to) in [("PH", "F"), ("GH", "G"), ("CK", "K"), ("SH", "X"), ("CH", "X"), ("TH", "0"), ("QU", "K")] {
            str = str.replacingOccurrences(of: from, with: to)
        }

        let map: [Character: Character] = [
            "C": "K", "Q": "K", "X": "K", "Z": "S", "D": "T",
            "B": "P", "V": "F", "G": "K", "J": "X", "Y": "I", "W": "U",
        ]

        // Collapse only literal doubles ("LL", "SS") BEFORE dropping vowels —
        // collapsing after would merge consonants that were separated by a
        // vowel ("prior" → PRR must stay distinct from "priya" → PR).
        let chars = Array(str)
        var out: [Character] = []
        for (index, char) in chars.enumerated() {
            if index > 0, chars[index - 1] == char { continue }
            let mapped = map[char] ?? char
            if index > 0, "AEIOU".contains(mapped) { continue }  // drop non-initial vowels
            out.append(mapped)
        }
        return String(out)
    }

    static func levenshtein(_ a: String, _ b: String) -> Int {
        let s = Array(a), t = Array(b)
        if s.isEmpty { return t.count }
        if t.isEmpty { return s.count }

        var previous = Array(0...t.count)
        var current = [Int](repeating: 0, count: t.count + 1)

        for i in 1...s.count {
            current[0] = i
            for j in 1...t.count {
                let cost = s[i - 1] == t[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            swap(&previous, &current)
        }
        return previous[t.count]
    }
}
