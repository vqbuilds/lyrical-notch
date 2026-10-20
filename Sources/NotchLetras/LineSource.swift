import Foundation

// One shared lookup supplies both the visible fallback and whitespace references.
// Never require album spelling to match: provider editions can use different album names.
actor LineSource {
    static let shared = LineSource()
    private var running: [String: Task<LyricResponse?, Never>] = [:]
    private var cached: [String: (Date, LyricResponse?)] = [:]
    func get(_ song: Track, bypass: Bool = false) async -> LyricResponse? {
        if let task = running[song.key] { return await task.value }
        if !bypass, let entry = cached[song.key], Date().timeIntervalSince(entry.0) < (entry.1 == nil ? 20 : 300) { return entry.1 }
        let task = Task { await Self.lookup(song) }
        running[song.key] = task
        let result = await task.value
        running[song.key] = nil
        if cached.count >= 12, let oldest = cached.min(by: { $0.value.0 < $1.value.0 })?.key { cached[oldest] = nil }
        cached[song.key] = (Date(), result)
        return result
    }
    private static func lookup(_ song: Track) async -> LyricResponse? {
        var url = URLComponents(string: "https://lrclib.net/api/get")!
        url.queryItems = [URLQueryItem(name: "track_name", value: song.title), URLQueryItem(name: "artist_name", value: song.artist), URLQueryItem(name: "duration", value: String(Int(song.duration.rounded())))]
        if let raw = try? await WordSources.data(url.url!), let row = try? JSONDecoder().decode(LyricResponse.self, from: raw) { return row }
        url = URLComponents(string: "https://lrclib.net/api/search")!
        url.queryItems = [URLQueryItem(name: "track_name", value: song.title), URLQueryItem(name: "artist_name", value: song.artist.components(separatedBy: ",").first ?? song.artist)]
        guard let raw = try? await WordSources.data(url.url!), let rows = try? JSONDecoder().decode([LyricResponse].self, from: raw) else { return nil }
        return rows.filter { row in
            identityKey(row.trackName ?? "") == identityKey(song.title) &&
            identityKey(row.artistName ?? "").contains(identityKey(song.artist.components(separatedBy: ",").first ?? song.artist)) &&
            abs((row.duration ?? -100) - song.duration) <= 3
        }.sorted { left, right in
            let rank: (LyricResponse) -> Int = { $0.hasWordSync == true ? 2 : ($0.syncedLyrics?.isEmpty == false ? 1 : 0) }
            if rank(left) != rank(right) { return rank(left) > rank(right) }
            return abs((left.duration ?? 0)-song.duration) < abs((right.duration ?? 0)-song.duration)
        }.first
    }
}

func validSyncedLines(_ lines: [LyricLine], duration: Double) -> Bool {
    duration.isFinite && duration > 0 && !lines.isEmpty && lines.count < 10_000 &&
    lines.contains(where: { !$0.text.isEmpty }) &&
    lines.allSatisfy { $0.time.isFinite && $0.time >= 0 && $0.time <= duration + 2.5 } &&
    zip(lines, lines.dropFirst()).allSatisfy { $0.time <= $1.time }
}
func lyricRank(_ lines: [LyricLine], duration: Double) -> Int {
    validWordLines(lines, duration: duration) ? 2 : (validSyncedLines(lines, duration: duration) ? 1 : 0)
}
