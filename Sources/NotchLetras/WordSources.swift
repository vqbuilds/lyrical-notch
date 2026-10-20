import Foundation

struct WordLyricsResult: Codable {
    var source: String
    var title: String
    var artist: String
    var duration: Double
    var lines: [LyricLine]
    var wordCount: Int { lines.filter(\.hasWords).reduce(0) { $0 + $1.words.count } }
    var coverage: Double { Double(lines.filter(\.hasWords).count) / Double(max(1, lines.count)) }
}
func identityKey(_ text: String) -> String {
    text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        .unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined()
}
func recordingMatches(title: String, artists: [String], duration: Double, song: Track) -> Bool {
    guard identityKey(title) == identityKey(song.title), duration > 0, abs(duration - song.duration) <= 2.5 else { return false }
    let primary = song.artist.components(separatedBy: ",").first ?? song.artist
    return artists.contains { identityKey($0) == identityKey(primary) || identityKey($0) == identityKey(song.artist) }
}
func validWordLines(_ lines: [LyricLine], duration: Double) -> Bool {
    let timed = lines.filter(\.hasWords)
    let words = timed.flatMap(\.words)
    guard timed.count >= 2, words.count >= 8, Double(timed.count) / Double(max(lines.count, 1)) >= 0.6 else { return false }
    return words.allSatisfy { word in
        guard let end = word.end else { return false }
        return word.start >= 0 && word.start.isFinite && end.isFinite && end > word.start && end <= duration + 2.5
    } && Set(words.map { Int($0.start * 100) }).count >= 5
}
func parseYRC(_ text: String) -> [LyricLine] {
    let rowPattern = try! NSRegularExpression(pattern: #"^\[(\d+),(\d+)\]"#)
    let tokenPattern = try! NSRegularExpression(pattern: #"\((\d+),(\d+),\d+\)"#)
    return text.components(separatedBy: .newlines).compactMap { raw in
        let row = raw as NSString
        guard let header = rowPattern.firstMatch(in: raw, range: NSRange(location: 0, length: row.length)),
              let start = Double(row.substring(with: header.range(at: 1))), let duration = Double(row.substring(with: header.range(at: 2))) else { return nil }
        let tags = tokenPattern.matches(in: raw, range: NSRange(location: NSMaxRange(header.range), length: row.length - NSMaxRange(header.range)))
        let words = tags.enumerated().compactMap { index, tag -> WordTiming? in
            let lower = NSMaxRange(tag.range)
            let upper = index + 1 < tags.count ? tags[index + 1].range.location : row.length
            let content = row.substring(with: NSRange(location: lower, length: upper - lower))
            guard !content.isEmpty, let time = Double(row.substring(with: tag.range(at: 1))),
                  let length = Double(row.substring(with: tag.range(at: 2))), length > 0 else { return nil }
            return WordTiming(text: content, start: time / 1000, end: (time + length) / 1000)
        }
        guard !words.isEmpty else { return nil }
        return LyricLine(time: start / 1000, text: words.map(\.text).joined().trimmingCharacters(in: .whitespaces), end: (start + duration) / 1000, words: words)
    }.sorted { $0.time < $1.time }
}
func parseTTMLTime(_ value: String?) -> Double? {
    guard let value else { return nil }
    if value.hasSuffix("ms") { return Double(value.dropLast(2)).map { $0 / 1000 } }
    if value.hasSuffix("s") { return Double(value.dropLast()) }
    let parts = value.split(separator: ":").compactMap { Double($0) }
    guard !parts.isEmpty else { return nil }
    return parts.reduce(0) { $0 * 60 + $1 }
}
private final class WordTTMLParser: NSObject, XMLParserDelegate {
    var lines: [LyricLine] = []
    var depth = 0
    var pDepth: Int?
    var ignoredDepth: Int?
    var start: Double = 0
    var end: Double?
    var text = ""
    var words: [WordTiming] = []
    var currentWordDepth: Int?
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        depth += 1
        let local = name.split(separator: ":").last.map(String.init) ?? name
        if local == "p" {
            pDepth = depth; start = parseTTMLTime(attributes["begin"]) ?? 0; end = parseTTMLTime(attributes["end"])
            text = ""; words = []; currentWordDepth = nil
        }
        guard pDepth != nil, ignoredDepth == nil else { return }
        let role = attributes["ttm:role"] ?? attributes["role"] ?? ""
        if role.contains("translation") || role.contains("roman") || role == "x-bg" { ignoredDepth = depth; return }
        if local == "span", currentWordDepth == nil, let begin = parseTTMLTime(attributes["begin"]), let finish = parseTTMLTime(attributes["end"]), finish > begin {
            words.append(WordTiming(text: "", start: begin, end: finish)); currentWordDepth = depth
        }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard pDepth != nil, ignoredDepth == nil else { return }
        let content = string.replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: "\t", with: "")
        text += content
        if currentWordDepth != nil, !words.isEmpty { words[words.count - 1].text += content }
        else if !words.isEmpty && content.trimmingCharacters(in: .whitespaces).isEmpty { words[words.count - 1].text += content }
    }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if ignoredDepth == depth { ignoredDepth = nil }
        if currentWordDepth == depth { currentWordDepth = nil }
        if pDepth == depth {
            let visible = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !visible.isEmpty { lines.append(LyricLine(time: start, text: visible, end: end, words: words.filter { !$0.text.isEmpty })) }
            pDepth = nil
        }
        depth -= 1
    }
}
func parseWordTTML(_ data: Data) -> [LyricLine] {
    guard data.count < 2_000_000 else { return [] }
    let delegate = WordTTMLParser(); let parser = XMLParser(data: data)
    parser.shouldResolveExternalEntities = false; parser.delegate = delegate
    return parser.parse() ? delegate.lines.sorted { $0.time < $1.time } : []
}
enum WordSources {
    static func data(_ url: URL, netease: Bool = false) async throws -> Data {
        var request = URLRequest(url: url); request.timeoutInterval = 10
        request.setValue("NotchLetras/0.3", forHTTPHeaderField: "User-Agent")
        if netease { request.setValue("https://music.163.com/", forHTTPHeaderField: "Referer") }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count < 8_000_000 else { throw URLError(.badServerResponse) }
        return data
    }
    static func amll(_ song: Track) async -> WordLyricsResult? {
        guard !song.spotifyID.isEmpty, song.spotifyID.allSatisfy({ $0.isLetter || $0.isNumber }),
              let url = URL(string: "https://raw.githubusercontent.com/amll-dev/amll-ttml-db/main/spotify-lyrics/\(song.spotifyID).ttml"),
              let raw = try? await data(url) else { return nil }
        let lines = parseWordTTML(raw)
        guard validWordLines(lines, duration: song.duration) else { return nil }
        return WordLyricsResult(source: "AMLL · TTML (ID de Spotify)", title: song.title, artist: song.artist, duration: song.duration, lines: lines)
    }
    static func netease(_ song: Track) async -> WordLyricsResult? {
        var components = URLComponents(string: "https://music.163.com/api/cloudsearch/pc")!
        components.queryItems = [URLQueryItem(name: "s", value: "\(song.title) \(song.artist.components(separatedBy: ",").first ?? song.artist)"), URLQueryItem(name: "type", value: "1"), URLQueryItem(name: "limit", value: "10")]
        guard let raw = try? await data(components.url!, netease: true),
              let json = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
              let result = json["result"] as? [String: Any], let songs = result["songs"] as? [[String: Any]] else { return nil }
        let matches = songs.filter { candidate in
            let artists = (candidate["ar"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
            return recordingMatches(title: candidate["name"] as? String ?? "", artists: artists,
                duration: (candidate["dt"] as? Double ?? 0) / 1000, song: song)
        }.sorted { abs(($0["dt"] as? Double ?? 0) / 1000 - song.duration) < abs(($1["dt"] as? Double ?? 0) / 1000 - song.duration) }
        for candidate in matches.prefix(3) {
            guard !Task.isCancelled, let id = candidate["id"] as? Int,
                  let url = URL(string: "https://music.163.com/api/song/lyric/v1?id=\(id)&lv=0&kv=0&tv=0&rv=0&yv=0&ytv=0&yrv=0"),
                  let raw = try? await data(url, netease: true),
                  let lyric = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
                  let yrc = lyric["yrc"] as? [String: Any], let text = yrc["lyric"] as? String else { continue }
            let lines = parseYRC(text)
            guard validWordLines(lines, duration: song.duration) else { continue }
            return WordLyricsResult(source: "NetEase · YRC · \(id)", title: candidate["name"] as? String ?? song.title,
                artist: song.artist, duration: (candidate["dt"] as? Double ?? 0) / 1000, lines: lines)
        }
        return nil
    }
    static func lrcRed(_ song: Track) async -> WordLyricsResult? {
        var parts = URLComponents(string: "https://lrc.red/match.json")!
        parts.queryItems = [URLQueryItem(name: "title", value: song.title), URLQueryItem(name: "artist", value: song.artist), URLQueryItem(name: "album", value: song.album), URLQueryItem(name: "duration", value: String(Int(song.duration.rounded())))]
        guard let raw = try? await data(parts.url!), let json = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
              let hits = json["hits"] as? [[String: Any]] else { return nil }
        for hit in hits.prefix(5) {
            guard recordingMatches(title: hit["title"] as? String ?? "", artists: [hit["artist"] as? String ?? ""], duration: hit["duration"] as? Double ?? 0, song: song),
                  let code = hit["isrc"] as? String, code.count == 12, code.allSatisfy({ $0.isLetter || $0.isNumber }),
                  let url = URL(string: "https://lrc.red/s/\(code).ttml"), let body = try? await data(url) else { continue }
            let lines = parseWordTTML(body)
            guard validWordLines(lines, duration: song.duration) else { continue }
            return WordLyricsResult(source: "lrc.red · TTML · \(code)", title: hit["title"] as? String ?? song.title, artist: song.artist, duration: hit["duration"] as? Double ?? song.duration, lines: lines)
        }
        return nil
    }
    static func fetch(_ song: Track) async -> WordLyricsResult? {
        await withTaskGroup(of: WordLyricsResult?.self) { group in
            group.addTask { await amll(song) }
            group.addTask { await netease(song) }
            group.addTask { await lrcRed(song) }
            group.addTask { await qqMusic(song) }
            group.addTask { await kugou(song) }
            var best: WordLyricsResult?
            for await result in group {
                guard let result else { continue }
                if best == nil || result.coverage > best!.coverage { best = result }
                if result.coverage >= 0.9 { group.cancelAll(); return result }
            }
            return best
        }
    }
}

func verifyWordSources() {
    verifyAdditionalSources()
    let yrc = parseYRC("[1000,5000](1000,300,0)Hola (4000,500,0)mundo\n[7000,1000](7000,1000,0)Sí")
    precondition(yrc.count == 2 && yrc[0].hasWords)
    precondition(yrc[0].words[0].end == 1.3 && yrc[0].words[1].start == 4)
    // Hold the first word during the actual pause; never distribute it across the phrase.
    precondition(fillProgress(at: 2.5, start: yrc[0].words[1].start, end: yrc[0].words[1].end!) == 0)
    let xml = #"<tt><body><div><p begin="1s" end="5s"><span begin="1s" end="1.3s">Hola</span> <span begin="4s" end="4.5s">mundo</span><span ttm:role="x-translation">ignored</span></p></div></body></tt>"#
    let parsed = parseWordTTML(Data(xml.utf8))
    precondition(parsed.count == 1 && parsed[0].text == "Hola mundo" && parsed[0].hasWords)
    precondition(parsed[0].words[0].end == 1.3 && parsed[0].words[1].start == 4)
    let phrase = LyricLine(time: 1, text: "Whole phrase", end: 4, words: [WordTiming(text: "Whole phrase", start: 1, end: 4)])
    precondition(!phrase.hasWords) // A phrase timestamp cannot masquerade as word timing.
    precondition(parseYRC("broken").isEmpty)
    let song = Track(title: "Hysteria", artist: "Muse", album: "", duration: 227, position: 0, playing: false, player: "Spotify")
    precondition(recordingMatches(title: "Hysteria", artists: ["Muse"], duration: 227.08, song: song))
    precondition(!recordingMatches(title: "Hysteria (Live)", artists: ["Muse"], duration: 227, song: song))
    precondition(!recordingMatches(title: "Hysteria", artists: ["Cover Band"], duration: 227, song: song))
    precondition(!recordingMatches(title: "Hysteria", artists: ["Muse"], duration: 233, song: song))
    print("Word-source checks passed: YRC, TTML, vocal pauses, phrase rejection, artist/version/duration matching.")
}
