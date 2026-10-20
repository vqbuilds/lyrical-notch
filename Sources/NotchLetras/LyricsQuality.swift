import Foundation

struct LyricsReview {
    var lines: [LyricLine]
    var notes: [String]
    var suspicious: Bool
}
enum LyricsQuality {
    static func hasHan(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x3400...0x9fff).contains($0.value) || (0x20000...0x323af).contains($0.value) }
    }
    private static func compact(_ text: String) -> String {
        text.filter { !$0.isWhitespace }.lowercased()
    }
    private static func latinCount(_ text: String) -> Int {
        text.unicodeScalars.filter { (65...90).contains($0.value) || (97...122).contains($0.value) }.count
    }
    static func glued(_ line: LyricLine) -> Bool {
        let text = line.text
        let letters = latinCount(text)
        guard letters >= 16 else { return false }
        let tokens = text.split(whereSeparator: { $0.isWhitespace })
        return tokens.count == 1 && (line.words.count >= 3 || letters >= 28)
    }
    // Only restore whitespace when an independent line has identical characters.
    // Never invent word boundaries or divide a syllable into guessed word timings.
    static func restoreSpacing(_ line: LyricLine, from reference: String) -> LyricLine? {
        guard compact(line.text) == compact(reference), line.text != reference else { return nil }
        if line.words.isEmpty { return LyricLine(time: line.time, text: reference, end: line.end) }
        var boundaries = Set<Int>(), count = 0
        for char in reference {
            if char.isWhitespace { boundaries.insert(count) } else { count += 1 }
        }
        var words = line.words, cursor = 0
        for index in words.indices {
            let chars = Array(words[index].text.filter { !$0.isWhitespace })
            let end = cursor + chars.count
            // A separator inside one segment would fake a word timestamp.
            if boundaries.contains(where: { $0 > cursor && $0 < end }) { return nil }
            words[index].text = String(chars) + (boundaries.contains(end) && end < count ? " " : "")
            cursor = end
        }
        guard cursor == count else { return nil }
        let visible = words.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
        return LyricLine(time: line.time, text: visible, end: line.end, words: words)
    }
    static func review(_ input: [LyricLine], reference: [LyricLine] = [], filterHan: Bool = true) -> LyricsReview {
        var refs: [String: String] = [:]
        for line in reference where !glued(line) && !line.text.isEmpty {
            refs[compact(line.text)] = line.text
        }
        var removed = 0, repaired = 0
        let lines = input.compactMap { line -> LyricLine? in
            if filterHan && hasHan(line.text) { removed += 1; return nil }
            if let text = refs[compact(line.text)], let spaced = restoreSpacing(line, from: text) {
                repaired += 1; return spaced
            }
            return line
        }
        let gluedCount = lines.filter(glued).count
        var notes: [String] = []
        if removed > 0 { notes.append("\(removed) líneas con caracteres han excluidas") }
        if repaired > 0 { notes.append("Espacios recuperados en \(repaired) líneas mediante texto coincidente") }
        if gluedCount > 0 { notes.append("\(gluedCount) líneas con posibles palabras pegadas") }
        return LyricsReview(lines: lines, notes: notes, suspicious: gluedCount > 0 || (!input.isEmpty && lines.isEmpty))
    }
    static func reviewPlain(_ text: String, reference: [LyricLine] = [], filterHan: Bool = true) -> LyricsReview {
        review(text.components(separatedBy: .newlines).map { LyricLine(time: 0, text: $0) }, reference: reference, filterHan: filterHan)
    }
    static func accepted(_ result: WordLyricsResult, reference: [LyricLine], filterHan: Bool = true) -> WordLyricsResult? {
        let review = review(result.lines, reference: reference, filterHan: filterHan)
        guard !review.suspicious, validSyncedLines(review.lines, duration: result.duration) else { return nil }
        var cleaned = result; cleaned.lines = review.lines
        if !validWordLines(cleaned.lines, duration: result.duration) {
            cleaned.lines = cleaned.lines.map { LyricLine(time: $0.time, text: $0.text, end: $0.end) }
        }
        return cleaned
    }
}

func verifyLyricsQuality() {
    let glued = LyricLine(time: 1, text: "Theseareoriginaltestwords", end: 5, words: [
        WordTiming(text: "These", start: 1, end: 1.5), WordTiming(text: "are", start: 2, end: 2.4),
        WordTiming(text: "original", start: 3, end: 3.4), WordTiming(text: "test", start: 4, end: 4.4), WordTiming(text: "words", start: 4.5, end: 5)])
    let ref = LyricLine(time: 1, text: "These are original test words")
    let fixed = LyricsQuality.review([glued], reference: [ref])
    precondition(!fixed.suspicious && fixed.lines[0].text == ref.text && fixed.lines[0].hasWords)
    precondition(fixed.lines[0].words.map(\.start) == glued.words.map(\.start))
    precondition(LyricsQuality.review([glued]).suspicious)
    precondition(LyricsQuality.restoreSpacing(glued, from: "These are different test words") == nil)
    let credit = LyricLine(time: 0, text: "作词：测试")
    precondition(LyricsQuality.review([credit, ref]).lines == [ref])
    precondition(LyricsQuality.review([credit], filterHan: false).lines == [credit])
    precondition(!LyricsQuality.review([LyricLine(time: 1, text: "Extraordinary" )]).suspicious)
    precondition(LyricsQuality.reviewPlain(String(repeating: "word", count: 9)).suspicious)
    print("Lyric quality checks passed: Han filter, glued-word detection, exact-reference spacing and unchanged timestamps.")
}
