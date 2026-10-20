import Foundation
import Yams
import SwiftUI

struct WordTiming: Codable, Equatable {
    var text: String
    var start: Double
    var end: Double?
}
struct LyricLine: Codable, Equatable {
    let time: Double
    let text: String
    var end: Double? = nil
    var words: [WordTiming] = []
    var hasWords: Bool {
        !words.isEmpty && words.allSatisfy { $0.text.split(whereSeparator: { $0.isWhitespace }).count <= 1 } && words.map(\.text).joined().trimmingCharacters(in: .whitespaces) == text &&
        zip(words, words.dropFirst()).allSatisfy { $0.start <= $1.start }
    }
}
private func timestamp(_ match: NSTextCheckingResult, in text: NSString) -> Double {
    let fraction = match.range(at: 3).location == NSNotFound ? "" : text.substring(with: match.range(at: 3))
    return (Double(text.substring(with: match.range(at: 1))) ?? 0) * 60 + (Double(text.substring(with: match.range(at: 2))) ?? 0) + (Double("0." + fraction) ?? 0)
}
func parseLRC(_ text: String) -> [LyricLine] {
    let lineRE = try! NSRegularExpression(pattern: #"\[(\d+):(\d{2})(?:[\.:](\d{1,3}))?\]"#)
    let wordRE = try! NSRegularExpression(pattern: #"<(\d+):(\d{2})(?:[\.:](\d{1,3}))?>"#)
    let offsetRE = try! NSRegularExpression(pattern: #"(?i)\[offset:([+-]?\d+)\]"#)
    let whole = text as NSString
    let offset = offsetRE.firstMatch(in: text, range: NSRange(location: 0, length: whole.length)).flatMap { Double(whole.substring(with: $0.range(at: 1))) }.map { $0 / 1000 } ?? 0
    return text.components(separatedBy: .newlines).flatMap { row -> [LyricLine] in
        let ns = row as NSString
        let tags = lineRE.matches(in: row, range: NSRange(location: 0, length: ns.length))
        guard let last = tags.last else { return [] }
        let content = ns.substring(from: NSMaxRange(last.range))
        let body = content as NSString
        let wordTags = wordRE.matches(in: content, range: NSRange(location: 0, length: body.length))
        let visible = wordRE.stringByReplacingMatches(in: content, range: NSRange(location: 0, length: body.length), withTemplate: "").trimmingCharacters(in: .whitespaces)
        var words: [WordTiming] = []
        for (index, tag) in wordTags.enumerated() {
            let next = index + 1 < wordTags.count ? wordTags[index + 1] : nil
            let start = NSMaxRange(tag.range)
            let end = next?.range.location ?? body.length
            let segment = body.substring(with: NSRange(location: start, length: end - start))
            if !segment.isEmpty {
                words.append(WordTiming(text: segment, start: timestamp(tag, in: body) - offset, end: next.map { timestamp($0, in: body) - offset }))
            }
        }
        return tags.map { tag in
            let delta = timestamp(tag, in: ns) - timestamp(tags[0], in: ns)
            return LyricLine(time: timestamp(tag, in: ns) - offset, text: visible,
                end: wordTags.last.flatMap { NSMaxRange($0.range) == body.length ? timestamp($0, in: body) - offset + delta : nil },
                words: words.map { WordTiming(text: $0.text, start: $0.start + delta, end: $0.end.map { $0 + delta }) })
        }
    }.sorted { $0.time < $1.time }
}
private struct LyricsDocument: Decodable {
    var lines: [Line]?
    struct Line: Decodable {
        var text: String
        var start_ms: Double?
        var end_ms: Double?
        var words: [Word]?
    }
    struct Word: Decodable { var text: String; var start_ms: Double; var end_ms: Double? }
}
func parseLyricsfile(_ text: String) -> [LyricLine] {
    guard text.utf8.count < 2_000_000, let doc = try? YAMLDecoder().decode(LyricsDocument.self, from: text) else { return [] }
    return (doc.lines ?? []).compactMap { row in
        guard let start = row.start_ms, start.isFinite else { return nil }
        let words = (row.words ?? []).filter { $0.start_ms.isFinite && ($0.end_ms == nil || $0.end_ms! > $0.start_ms) }.map { WordTiming(text: $0.text, start: $0.start_ms / 1000, end: $0.end_ms.map { $0 / 1000 }) }
        return LyricLine(time: start / 1000, text: row.text.trimmingCharacters(in: .whitespaces), end: row.end_ms.map { $0 / 1000 }, words: words)
    }.sorted { $0.time < $1.time }
}
func fillProgress(at time: Double, start: Double, end: Double) -> Double {
    guard end > start else { return time >= start ? 1 : 0 }
    return max(0, min(1, (time - start) / (end - start)))
}
struct SungSpan: TextAttribute { var start: Double; var end: Double }
@available(macOS 15.0, *)
struct KaraokeRenderer: TextRenderer {
    var position: Double
    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for line in layout {
            for run in line {
                guard let timing = run[SungSpan.self] else { context.draw(run); continue }
                var muted = context; muted.opacity = 0.34; muted.draw(run)
                let amount = fillProgress(at: position, start: timing.start, end: timing.end) * Double(run.count)
                for (index, glyph) in run.enumerated() {
                    let fraction = max(0, min(1, amount - Double(index)))
                    guard fraction > 0 else { continue }
                    var highlight = context
                    var rect = glyph.typographicBounds.rect
                    if run.layoutDirection == .rightToLeft { rect.origin.x += rect.width * (1 - fraction) }
                    rect.size.width *= fraction
                    rect.origin.y -= 3; rect.size.height += 6
                    highlight.clip(to: Path(rect))
                    highlight.draw(glyph)
                }
            }
        }
    }
}
struct KaraokeText: View {
    let line: LyricLine
    let nextTime: Double?
    let position: Double
    var enabled = true
    var tint: Color = .white
    var timedText: Text {
        if line.hasWords {
            return line.words.reduce(Text("")) { result, word in
                let end = word.end ?? word.start
                return result + Text(word.text).customAttribute(SungSpan(start: word.start, end: end))
            }
        }
        return Text(line.text)
    }
    var body: some View {
        Group {
            if #available(macOS 15.0, *), enabled, !line.text.isEmpty {
                timedText.textRenderer(KaraokeRenderer(position: position))
            } else { Text(line.text.isEmpty ? "♪" : line.text) }
        }.foregroundStyle(tint).accessibilityLabel(line.text)
    }
}

func verifyKaraoke() {
    let enhanced = parseLRC("[offset:200]\n[00:10.00]<00:10.00>Hola <00:10.50>mundo<00:11.50>\n[00:12.00]Otra frase")
    precondition(enhanced.count == 2 && enhanced[0].text == "Hola mundo")
    precondition(enhanced[0].hasWords && enhanced[0].words.count == 2)
    precondition(abs(enhanced[0].time - 9.8) < 0.0001)
    precondition(abs((enhanced[0].end ?? 0) - 11.3) < 0.0001)
    precondition(fillProgress(at: 9, start: 10, end: 11) == 0)
    precondition(fillProgress(at: 10.5, start: 10, end: 11) == 0.5)
    precondition(fillProgress(at: 12, start: 10, end: 11) == 1)
    precondition(fillProgress(at: 10, start: 10, end: 10) == 1)
    precondition(!parseLRC("[00:01]Sin tiempos por palabra")[0].hasWords)
    let yaml = """
    version: '1.0'
    lines:
      - text: 'Hola mundo'
        start_ms: 1000
        end_ms: 2500
        words:
          - text: 'Hola '
            start_ms: 1000
            end_ms: 1500
          - text: 'mundo'
            start_ms: 1600
            end_ms: 2500
      - text: 'Siguiente'
        start_ms: 4000
        end_ms: 5000
    """
    let parsed = parseLyricsfile(yaml)
    precondition(parsed.count == 2 && parsed[0].hasWords)
    precondition(parsed[0].time == 1 && parsed[0].end == 2.5 && parsed[0].words[1].start == 1.6)
    precondition(!parsed[1].hasWords)
    precondition(parseLyricsfile("lines: [not valid").isEmpty)
    precondition(!LyricLine(time: 0, text: "Different", words: parsed[0].words).hasWords)
    precondition(!LyricLine(time: 0, text: "mundoHola", words: [WordTiming(text: "mundo", start: 2, end: 3), WordTiming(text: "Hola", start: 1, end: 2)]).hasWords)
    print("Karaoke checks passed: word timestamps, enhanced LRC, offset, Lyricsfile YAML, malformed input, phrase-only fallback, progress boundaries and seeking.")
}
