import Foundation

private final class QRCContent: NSObject, XMLParserDelegate {
    var content: String?
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        if elementName == "Lyric_1", attributes["LyricType"] == "1" { content = attributes["LyricContent"] }
    }
}
func parseLegacyWords(_ text: String, qrc: Bool) -> [LyricLine] {
    guard text.utf8.count < 2_000_000 else { return [] }
    var content = text
    if qrc {
        let delegate = QRCContent(), parser = XMLParser(data: Data(text.utf8))
        parser.shouldResolveExternalEntities = false; parser.delegate = delegate
        guard parser.parse(), let value = delegate.content else { return [] }
        content = value
    }
    let rows = try! NSRegularExpression(pattern: #"\[(\d+),(\d+)\]"#)
    let tokens = try! NSRegularExpression(pattern: qrc ? #"(.*?)\((\d+),(\d+)\)"# : #"<(\d+),(\d+),\d+>([^<]*)"#, options: [.dotMatchesLineSeparators])
    let ns = content as NSString
    let headers = rows.matches(in: content, range: NSRange(location: 0, length: ns.length))
    return headers.enumerated().compactMap { index, header in
        guard let start = Double(ns.substring(with: header.range(at: 1))), let duration = Double(ns.substring(with: header.range(at: 2))), duration > 0 else { return nil }
        let lower = NSMaxRange(header.range)
        let upper = index + 1 < headers.count ? headers[index+1].range.location : ns.length
        let body = ns.substring(with: NSRange(location: lower, length: upper-lower)).trimmingCharacters(in: .newlines) as NSString
        let matches = tokens.matches(in: body as String, range: NSRange(location: 0, length: body.length))
        let words = matches.compactMap { match -> WordTiming? in
            let value = body.substring(with: match.range(at: qrc ? 1 : 3))
            guard let time = Double(body.substring(with: match.range(at: qrc ? 2 : 1))),
                  let length = Double(body.substring(with: match.range(at: qrc ? 3 : 2))), length > 0, !value.isEmpty else { return nil }
            let begin = (qrc ? time : start + time) / 1000
            return WordTiming(text: value, start: begin, end: begin + length/1000)
        }
        if words.isEmpty {
            let plain = body as String
            guard !plain.contains("<"), !plain.contains("("), !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return LyricLine(time: start/1000, text: plain.trimmingCharacters(in: .whitespacesAndNewlines), end: (start+duration)/1000)
        }
        return LyricLine(time: start/1000, text: words.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines), end: (start+duration)/1000, words: words)
    }.sorted { $0.time < $1.time }
}

extension WordSources {
    private static func serviceJSON(_ base: String, _ params: [String: String], qq: Bool = false) async -> [String: Any]? {
        guard !Task.isCancelled else { return nil }
        var url = URLComponents(string: base)!
        url.queryItems = params.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: url.url!); request.timeoutInterval = 10
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        if qq { request.setValue("https://y.qq.com/", forHTTPHeaderField: "Referer") }
        guard let (data, response) = try? await URLSession.shared.data(for: request), !Task.isCancelled,
              (response as? HTTPURLResponse)?.statusCode == 200, data.count < 8_000_000 else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
    private static func qqCall(_ module: String, _ method: String, _ params: [String: Any]) async -> [String: Any]? {
        let payload: [String: Any] = ["comm": ["ct": 19, "cv": 1859, "uin": 0], "req": ["module": module, "method": method, "param": params]]
        guard let encoded = try? JSONSerialization.data(withJSONObject: payload), let body = String(data: encoded, encoding: .utf8),
              let json = await serviceJSON("https://u.y.qq.com/cgi-bin/musicu.fcg", ["data": body], qq: true),
              let response = json["req"] as? [String: Any], response["code"] as? Int == 0 else { return nil }
        return response["data"] as? [String: Any]
    }
    static func qqMusic(_ song: Track) async -> WordLyricsResult? {
        guard let search = await qqCall("music.search.SearchCgiService", "DoSearchForQQMusicDesktop", ["query": "\(song.title) \(song.artist)", "num_per_page": 10, "page_num": 1, "search_type": 0]),
              let body = search["body"] as? [String: Any], let result = body["song"] as? [String: Any], let list = result["list"] as? [[String: Any]] else { return nil }
        let candidates = list.flatMap { [$0] + ($0["grp"] as? [[String: Any]] ?? []) }.filter {
            recordingMatches(title: $0["title"] as? String ?? "", artists: ($0["singer"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }, duration: $0["interval"] as? Double ?? 0, song: song)
        }.sorted { abs(($0["interval"] as? Double ?? 0)-song.duration) < abs(($1["interval"] as? Double ?? 0)-song.duration) }
        for candidate in candidates.prefix(3) {
            guard !Task.isCancelled, let id = candidate["id"] as? Int else { continue }
            let album = (candidate["album"] as? [String: Any])?["name"] as? String ?? ""
            let encode: (String) -> String = { Data($0.utf8).base64EncodedString() }
            let params: [String: Any] = ["songID": id, "songName": encode(song.title), "singerName": encode(song.artist), "albumName": encode(album), "interval": candidate["interval"] ?? 0, "crypt": 1, "qrc": 1, "qrc_t": 0, "lrc_t": 0, "trans": 0, "roma": 0, "type": 0, "ct": 19, "cv": 2111]
            guard let response = await qqCall("music.musichallSong.PlayLyricInfo", "GetPlayLyricInfo", params), let hex = response["lyric"] as? String,
                  let decoded = LegacyLyricsCodec.qrc(hex) else { continue }
            let lines = parseLegacyWords(decoded, qrc: true)
            guard validSyncedLines(lines, duration: song.duration) else { continue }
            return WordLyricsResult(source: "QQ Music · QRC · \(id)", title: song.title, artist: song.artist, duration: candidate["interval"] as? Double ?? song.duration, lines: lines)
        }
        return nil
    }
    static func kugou(_ song: Track) async -> WordLyricsResult? {
        guard let search = await serviceJSON("https://lyrics.kugou.com/search", ["ver": "1", "man": "yes", "client": "pc", "keyword": "\(song.artist) \(song.title)", "duration": String(Int(song.duration*1000))]),
              let candidates = search["candidates"] as? [[String: Any]] else { return nil }
        let matches = candidates.filter {
            recordingMatches(title: $0["song"] as? String ?? "", artists: ($0["singer"] as? String ?? "").components(separatedBy: "、"), duration: ($0["duration"] as? Double ?? 0)/1000, song: song)
        }.sorted { abs(($0["duration"] as? Double ?? 0)/1000-song.duration) < abs(($1["duration"] as? Double ?? 0)/1000-song.duration) }
        for candidate in matches.prefix(3) {
            guard !Task.isCancelled, let id = candidate["id"] as? String, let key = candidate["accesskey"] as? String,
                  let response = await serviceJSON("https://lyrics.kugou.com/download", ["id": id, "accesskey": key, "fmt": "krc", "charset": "utf8", "client": "pc", "ver": "1"]),
                  let content = response["content"] as? String, let bytes = Data(base64Encoded: content), let decoded = LegacyLyricsCodec.krc(bytes) else { continue }
            let lines = parseLegacyWords(decoded, qrc: false)
            guard validSyncedLines(lines, duration: song.duration) else { continue }
            return WordLyricsResult(source: "Kugou · KRC · \(id)", title: song.title, artist: song.artist, duration: (candidate["duration"] as? Double ?? 0)/1000, lines: lines)
        }
        return nil
    }
}

func verifyAdditionalSources() {
    // Original text fixtures; encrypted independently of the production decoder.
    let qrcHex = "ee7befb746f93831d42dcdf2e21f0d5d833c044042289012e0c11abf870c7dfb9c809065c5235ff1cf6f94cef240c69af0b143408ee750cb0a389cd583efc7c39d8bc22fbe3387c46bfbe96cb2abbaf8a703119cff3f60efd3b71c5d9aa2bf742e405703b6c533a16fbfc7afc536e04e7d1d136b2d93a00e30b39757e4753a3aed9ea0c85c67f9e96c05be6122328593"
    let krcBase64 = "a3JjMTjb6kFqAkSXYDcjnPjUVK8A8eDqIWzexVxu7SUC/UemF/dQda8ThmJIc5ht2xRmfCm+xDIC4xLfF49Uu29IO/UZxgMhL1gtLU+8aIRXO3dMQM/wU8w="
    let qrc = parseLegacyWords(LegacyLyricsCodec.qrc(qrcHex) ?? "", qrc: true)
    let krc = parseLegacyWords(LegacyLyricsCodec.krc(Data(base64Encoded: krcBase64)!) ?? "", qrc: false)
    precondition(qrc.count == 2 && krc.count == 2)
    precondition(qrc[0].text == "One two three four" && krc[0].text == qrc[0].text)
    precondition(qrc[1].words[0].start == 6 && krc[1].words[0].start == 6)
    precondition(qrc[0].words[0].end == 1.3 && krc[0].words[1].start == 2)
    precondition(validWordLines(qrc, duration: 12) && validWordLines(krc, duration: 12))
    precondition(LegacyLyricsCodec.qrc("no hex") == nil)
    precondition(LegacyLyricsCodec.qrc(String(repeating: "0", count: 16)) == nil)
    precondition(LegacyLyricsCodec.krc(Data("invalid".utf8)) == nil)
    precondition(parseLegacyWords("<broken", qrc: true).isEmpty)
    precondition(parseLegacyWords("[1000,500]whole phrase(1000,500)", qrc: false).isEmpty)
    print("Additional source checks passed: QRC/KRC decoding, absolute/relative timestamps, vocal gaps and malformed input.")
}
