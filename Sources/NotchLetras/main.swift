import AppKit
import SwiftUI
import UniformTypeIdentifiers
import CryptoKit
import Network

// Hover belongs to the window, not to SwiftUI content that changes size.
struct HoverState {
    var expanded = false
    var leftAt: TimeInterval?
    mutating func update(inside: Bool, now: TimeInterval) -> Bool {
        if inside { leftAt = nil; expanded = true }
        else if expanded {
            if let leftAt { if now - leftAt >= 0.25 { expanded = false; self.leftAt = nil } }
            else { leftAt = now }
        }
        return expanded
    }
}
func lyricSeekPosition(time: Double, offset: Double, duration: Double) -> Double? {
    guard time.isFinite, offset.isFinite, duration.isFinite, duration > 0 else { return nil }
    return min(duration, max(0, time - offset))
}
func nextLyric(in lines: [LyricLine], at time: Double) -> String? {
    lines.first { $0.time > time && !$0.text.isEmpty }?.text
}
struct Track: Equatable {
    var title: String
    var artist: String
    var album: String
    var duration: Double
    var position: Double
    var playing: Bool
    var player: String
    var artworkURL: String = ""
    var spotifyID: String = ""
    var key: String { "\(artist)|\(title)|\(Int(duration))" }
}
struct LyricResponse: Codable {
    var syncedLyrics: String?
    var plainLyrics: String?
    var instrumental: Bool?
    var trackName: String? = nil
    var artistName: String? = nil
    var duration: Double? = nil
    var lyricsfile: String? = nil
    var hasWordSync: Bool? = nil
}

@MainActor final class Model: ObservableObject {
    @Published var panelEnabled = UserDefaults.standard.object(forKey: "panelEnabled") as? Bool ?? true { didSet { save("panelEnabled", panelEnabled); layout?() } }
    @Published var lyricsEnabled = UserDefaults.standard.object(forKey: "lyricsEnabled") as? Bool ?? true { didSet { save("lyricsEnabled", lyricsEnabled); layout?() } }
    @Published var coverLyricsColor = UserDefaults.standard.bool(forKey: "coverLyricsColor") { didSet { save("coverLyricsColor", coverLyricsColor) } }
    @Published var expandedLyrics = UserDefaults.standard.object(forKey: "expandedLyrics") as? Bool ?? true { didSet { save("expandedLyrics", expandedLyrics); layout?() } }
    @Published var twoLines = UserDefaults.standard.bool(forKey: "twoLines") { didSet { save("twoLines", twoLines); layout?() } }
    @Published var songAnimation = UserDefaults.standard.object(forKey: "songAnimation") as? Bool ?? true { didSet { save("songAnimation", songAnimation); if !songAnimation { songNoticeTask?.cancel(); songNotice = false } } }
    @Published var pinned = false { didSet { pinChanged?() } }
    @Published var expandedHeight = UserDefaults.standard.object(forKey: "expandedHeight") as? Double ?? 420 { didSet { save("expandedHeight", expandedHeight); layout?() } }
    @Published var shortcut = UserDefaults.standard.string(forKey: "shortcut") ?? "cmdShiftL" { didSet { save("shortcut", shortcut); shortcutChanged?() } }
    @Published var shortcutStatus = ""
    @Published var connectionStatus = "Esperando reproductor"
    @Published var availablePanelHeight: Double = 700
    var pinChanged: (() -> Void)?
    var shortcutChanged: (() -> Void)?
    var showLyricChoices: (() -> Void)?
    var songPreferences = SongPreferences(defaults: .standard)
    var loadingOffset = false
    @Published var openOnHover = UserDefaults.standard.object(forKey: "openOnHover") as? Bool ?? true { didSet { save("openOnHover", openOnHover); if !pinned { expanded = false }; layout?() } }
    @Published var hideFullScreen = UserDefaults.standard.bool(forKey: "hideFullScreen") { didSet { save("hideFullScreen", hideFullScreen); layout?() } }
    @Published var screenID = UserDefaults.standard.string(forKey: "screenID") ?? "" { didSet { save("screenID", screenID); rebuild?() } }
    @Published var screens: [ScreenChoice] = []
    @Published var artworkColor: Color = .white
    @Published var wordStatus = "Sin tiempos por palabra cargados"
    @Published var wordSource = ""
    @Published var filterHanLyrics = UserDefaults.standard.object(forKey: "filterHanLyrics") as? Bool ?? true {
        didSet { providerRequest?.cancel(); providerToken = UUID(); providerChoices = [:]; choosingProvider = false; save("filterHanLyrics", filterHanLyrics); if let song = track, !demo { usingSelectedLyrics = false; wordSource = ""; fetch(song) } }
    }
    @Published var qualityStatus = ""
    @Published var lyricsLoading = false
    var lyricRequestToken = UUID()
    @Published var sourcePickerOpen = false
    @Published var choosingProvider = false
    @Published var providerMessage = ""
    var providerRequest: Task<Void, Never>?
    var providerToken = UUID()
    var providerChoices: [LyricProvider: LyricChoice] = [:]
    var wordRequest: Task<Void, Never>?
    @Published var songNotice = false
    var songNoticeTask: Task<Void, Never>?
    var rebuild: (() -> Void)?
    var toggleExpansion: (() -> Void)?
    @Published var karaokeEnabled = UserDefaults.standard.object(forKey: "karaoke") as? Bool ?? true { didSet { save("karaoke", karaokeEnabled) } }
    @Published var artwork: NSImage? { didSet { artworkColor = artwork.map(readableCoverColor) ?? .white } }
    @Published var hapticStyle = UserDefaults.standard.string(forKey: "hapticStyle") ?? "double" { didSet { save("hapticStyle", hapticStyle) } }
    @Published var hapticsEnabled = UserDefaults.standard.object(forKey: "haptics") as? Bool ?? true { didSet { save("haptics", hapticsEnabled) } }
    @Published var artworkEnabled = UserDefaults.standard.object(forKey: "artworkEnabled") as? Bool ?? true { didSet { save("artworkEnabled", artworkEnabled) } }
    @Published var artworkOpacity = UserDefaults.standard.object(forKey: "artworkOpacity") as? Double ?? 0.38 { didSet { save("artworkOpacity", artworkOpacity) } }
    @Published var track: Track?
    @Published var lines: [LyricLine] = [] { didSet { updateLyricIndex() } }
    @Published var plain = ""
    @Published var message = "Abre Spotify o Música y reproduce una canción"
    @Published var demo = false
    @Published var expanded = false
    var polling = false
    var position = 0.0 { didSet { if panelVisible || lyricsWindowVisible { updateLyricIndex() } } }
    @Published var currentIndex: Int?
    @Published var clockRevision = 0
    @Published var panelVisible = false { didSet { if panelVisible { position = playbackPosition(at: Date()) } } }
    @Published var lyricsWindowVisible = false { didSet { if lyricsWindowVisible { position = playbackPosition(at: Date()) } } }
    @Published var width: Double = UserDefaults.standard.object(forKey: "width") as? Double ?? 460 { didSet { save("width", width); layout?() } }
    @Published var compactHeight: Double = UserDefaults.standard.object(forKey: "compactHeight") as? Double ?? 34 { didSet { save("compactHeight", compactHeight); layout?() } }
    @Published var fontSize: Double = UserDefaults.standard.object(forKey: "font") as? Double ?? 17 { didSet { save("font", fontSize) } }
    @Published var offset = 0.0 { didSet { updateLyricIndex(); if !loadingOffset, !demo, let key = track?.key { songPreferences.setOffset(offset, for: key) } } }
    @Published var hidePaused = UserDefaults.standard.bool(forKey: "hidePaused") { didSet { save("hidePaused", hidePaused); layout?() } }
    @Published var accent: Double = UserDefaults.standard.object(forKey: "accent") as? Double ?? 0.48 { didSet { save("accent", accent) } }
    @Published var preferred = UserDefaults.standard.string(forKey: "preferred") ?? "Auto" { didSet { save("preferred", preferred) } }
    var updateHover: (() -> Void)?
    var layout: (() -> Void)?
    var showSettings: (() -> Void)?
    var showLyrics: (() -> Void)?
    var timer: Timer?
    var lastSample = Date()
    var sampledPosition = 0.0
    var suspended = false
    var playbackEpoch = 0
    var pollTask: Task<Void, Never>?
    var networkMonitor: NWPathMonitor?
    @Published var networkAvailable = true
    @Published var refreshingLyrics = false
    @Published var lyricsDiagnosticsOpen = false
    var refreshToken = UUID()
    var retryAfter = Date.distantFuture
    var retryDelay = 20.0
    var lyricRetryCount = 0
    var usingSelectedLyrics = false
    func loadSongOffset() {
        loadingOffset = true
        offset = track.map { songPreferences.offset(for: $0.key) } ?? 0
        loadingOffset = false
    }
    func prepareForSleep() {
        position = playbackPosition(at: Date()); sampledPosition = position
        suspended = true; track?.playing = false; playbackEpoch += 1
        timer?.invalidate()
        pollTask?.cancel(); polling = false
        request?.cancel(); wordRequest?.cancel(); artworkRequest?.cancel(); providerRequest?.cancel()
        providerToken = UUID(); choosingProvider = false
        pendingSeek = nil
        connectionStatus = "En reposo · reconectando al despertar"
    }
    func resumePlayback(reconnect: Bool = true) {
        suspended = false; playbackEpoch += 1
        pollTask?.cancel(); polling = false
        lastSample = Date()
        connectionStatus = "Reconectando con el reproductor…"
        if !usingSelectedLyrics && !lines.contains(where: \.hasWords) { retryAfter = .distantPast }
        if reconnect { startClock(); poll() }
    }
    func scheduleLyricsRetry() {
        guard !usingSelectedLyrics, !demo, lyricRetryCount < 3 else { retryAfter = .distantFuture; return }
        lyricRetryCount += 1
        retryAfter = Date().addingTimeInterval(retryDelay)
        retryDelay = min(120, retryDelay * 2)
    }
    @Published var playbackError: String?
    var seekGeneration = 0
    var seekRequest: Task<Void, Never>?
    var pendingSeek: (Track, Double)?
    var artworkRequest: Task<Void, Never>?
    let artworkCache = NSCache<NSString, NSImage>()
    var request: Task<Void, Never>?
    var cache: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("NotchLetras", isDirectory: true)
    func playbackPosition(at date: Date) -> Double {
        guard !suspended, track?.playing == true else { return sampledPosition }
        return min(track?.duration ?? .infinity, sampledPosition + max(0, date.timeIntervalSince(lastSample)))
    }
    var karaokeStatus: String {
        lines.contains(where: \.hasWords) ? "Karaoke con tiempos por palabra" : "Sin tiempos por palabra: se muestra la frase completa, sin barrido"
    }
    func updateLyricIndex() {
        let index = lines.lastIndex { $0.time <= position + offset }
        if index != currentIndex { currentIndex = index }
    }
    var currentText: String {
        if let i = currentIndex { return lines[i].text.isEmpty ? "♪" : lines[i].text }
        if !lines.isEmpty { return "♪  \(track?.title ?? "")" }
        return message
    }
    var lyricColor: Color { coverLyricsColor ? artworkColor : .white }
    var compactPanelHeight: Double {
        guard lyricsEnabled else { return compactHeight }
        let extra = (twoLines ? max(12, fontSize - 3) + 5 : 0)
        return max(compactHeight, fontSize + 12 + extra)
    }
    var maximumPanelHeight: Double { min(max(280, expandedHeight), availablePanelHeight) }
    var expandedPanelHeight: Double { expandedLyrics && lyricsEnabled ? maximumPanelHeight : min(240, maximumPanelHeight) }
    var visibleHeight: Double { expanded ? expandedPanelHeight : compactPanelHeight }
    func announceSong() {
        songNoticeTask?.cancel()
        guard songAnimation else { return }
        withAnimation(.easeInOut(duration: 0.22)) { songNotice = true }
        songNoticeTask = Task {
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.25)) { songNotice = false }
        }
    }
    var visibleWidth: Double { expanded ? max(width, 500) : width }
    var nextText: String? { nextLyric(in: lines, at: position + offset) }
    var tint: Color { Color(hue: accent, saturation: 0.55, brightness: 1) }
    func save(_ key: String, _ value: Any) { UserDefaults.standard.set(value, forKey: key) }
    func start() {
        try? FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        startClock()
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                let wasOffline = !self.networkAvailable
                self.networkAvailable = path.status == .satisfied
                if wasOffline && self.networkAvailable && !self.usingSelectedLyrics && !self.lines.contains(where: \.hasWords) {
                    self.lyricRetryCount = 0
                    self.retryAfter = .distantPast
                    self.retryDelay = 20
                }
            }
        }
        monitor.start(queue: DispatchQueue(label: "NotchLetras.network"))
        networkMonitor = monitor
        poll()
    }
    var nextPoll = Date.distantPast
    func startClock() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer?.tolerance = 0.03
    }
    func tick() {
        guard !suspended else { return }
        updateHover?()
        if !demo, networkAvailable, Date() >= retryAfter, let track {
            retryAfter = .distantFuture
            fetch(track, bypass: true)
        }
        if track?.playing == true { position = min(track?.duration ?? .infinity, sampledPosition + Date().timeIntervalSince(lastSample)) }
        if !demo, Date() >= nextPoll { poll() }
    }
    func poll() {
        guard !suspended, !demo, !polling, seekRequest == nil else { return }; polling = true
        nextPoll = Date().addingTimeInterval(track?.playing == true ? 1.05 : (track == nil ? 5 : 2))
        let pollGeneration = seekGeneration
        let epoch = playbackEpoch
        let selection = preferred
        pollTask = Task {
            let result = await Task.detached { () -> (Track?, String?) in
                let players = selection == "Auto" ? ["Spotify", "Music"] : [selection]
                var paused: Track?
                var errorMessage: String?
                for player in players {
                    let id = player == "Spotify" ? "com.spotify.client" : "com.apple.Music"
                    guard NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty == false else { continue }
                    let duration = player == "Spotify" ? "(duration of current track) / 1000" : "duration of current track"
                    let cover = player == "Spotify" ? "try\nset coverURL to artwork url of current track\nend try" : ""
                    let script = """
                    with timeout of 3 seconds
                    tell application "\(player)"
                        if player state is stopped then return ""
                        set coverURL to ""
                        set trackID to ""
                        \(cover)
                        \(player == "Spotify" ? "set trackID to id of current track" : "")
                        return {name of current track, artist of current track, album of current track, \(duration), player position, (player state is playing), coverURL, trackID}
                    end tell
                    end timeout
                    """
                    var error: NSDictionary?
                    guard let value = NSAppleScript(source: script)?.executeAndReturnError(&error), error == nil else {
                        errorMessage = "Permite el acceso a \(player) en Ajustes del Sistema → Privacidad y seguridad → Automatización"
                        continue
                    }
                    guard value.numberOfItems == 8 else { continue }
                    let t = Track(title: value.atIndex(1)?.stringValue ?? "", artist: value.atIndex(2)?.stringValue ?? "", album: value.atIndex(3)?.stringValue ?? "", duration: value.atIndex(4)?.doubleValue ?? 0, position: value.atIndex(5)?.doubleValue ?? 0, playing: value.atIndex(6)?.booleanValue ?? false, player: player, artworkURL: value.atIndex(7)?.stringValue ?? "", spotifyID: (value.atIndex(8)?.stringValue ?? "").components(separatedBy: ":").last ?? "")
                    if t.playing { return (t, nil) }; paused = t
                }
                return (paused, errorMessage)
            }.value
            guard !Task.isCancelled, epoch == playbackEpoch, !suspended, !demo else { return }
            polling = false
            guard pollGeneration == seekGeneration else { return }
            acceptPlayback(result.0, error: result.1, sampleIsCurrent: pollGeneration == seekGeneration)
        }
    }
    func acceptPlayback(_ incoming: Track?, error: String?, sampleIsCurrent: Bool = true) {
        let oldCover = track?.artworkURL
        let oldKey = track?.key
        // The interpolated clock is separate: a position sample must not invalidate every view.
        var comparable = incoming
        if let old = track { comparable?.position = old.position }
        if comparable != track { track = incoming }
        let status = incoming.map { "\($0.player == "Music" ? "Música" : $0.player) · \($0.playing ? "Reproduciendo" : "En pausa")" } ?? (error ?? "Sin reproductor conectado")
        if connectionStatus != status { connectionStatus = status }
        if oldCover != incoming?.artworkURL || oldKey != incoming?.key { loadArtwork() }
        if sampleIsCurrent {
            if let incoming, abs(playbackPosition(at: Date()) - incoming.position) > 0.3 { clockRevision += 1 }
            sampledPosition = incoming?.position ?? 0; position = sampledPosition; lastSample = Date()
        }
        if oldKey != incoming?.key {
            playbackError = nil; usingSelectedLyrics = false
            refreshToken = UUID(); refreshingLyrics = false
            lyricRequestToken = UUID(); lyricsLoading = false
            providerRequest?.cancel(); providerToken = UUID(); providerChoices = [:]; choosingProvider = false; providerMessage = ""; qualityStatus = ""
            retryAfter = .distantFuture; retryDelay = 20; lyricRetryCount = 0
            request?.cancel(); wordRequest?.cancel(); lines = []; plain = ""; wordSource = ""
            wordStatus = "Sin tiempos por palabra cargados"
            loadSongOffset()
            if let incoming {
                if !CommandLine.arguments.contains("--self-test") { fetch(incoming) }
                if oldKey != nil { announceSong() }
            }
        }
        if incoming == nil { message = error ?? "Abre Spotify o Música y reproduce una canción" }
        layout?()
    }
    func loadArtwork() {
        artworkRequest?.cancel()
        artwork = nil
        guard let song = track, let url = URL(string: song.artworkURL), url.scheme == "https" else { return }
        if let cached = artworkCache.object(forKey: song.artworkURL as NSString) { artwork = cached; return }
        artworkRequest = Task {
            do {
                var req = URLRequest(url: url); req.timeoutInterval = 12
                let (data, response) = try await URLSession.shared.data(for: req)
                guard !Task.isCancelled, track?.key == song.key, track?.artworkURL == song.artworkURL,
                      (response as? HTTPURLResponse)?.statusCode == 200,
                      data.count < 12_000_000, let image = NSImage(data: data) else { return }
                artworkCache.countLimit = 12
                artworkCache.setObject(image, forKey: song.artworkURL as NSString)
                artwork = image
            } catch { /* Cover failure must never interrupt lyrics or playback. */ }
        }
    }
    func cacheFile(_ key: String) -> URL {
        let name = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return cache.appendingPathComponent(name + ".json")
    }
    func cachedReference(_ song: Track) -> [LyricLine] {
        guard let raw = try? Data(contentsOf: cacheFile(song.key)), let row = try? JSONDecoder().decode(LyricResponse.self, from: raw) else { return [] }
        return parseLRC(row.syncedLyrics ?? "")
    }
    func mergeLyricsCandidate(_ candidate: WordLyricsResult) {
        guard !usingSelectedLyrics, let song = track else { return }
        let incoming = lyricRank(candidate.lines, duration: song.duration)
        let current = lyricRank(lines, duration: song.duration)
        guard incoming > 0, incoming >= current else { return }
        if incoming == current && !lines.isEmpty {
            let oldCoverage = Double(lines.filter(\.hasWords).count) / Double(max(1, lines.count))
            if candidate.coverage <= oldCoverage { return }
        }
        lines = candidate.lines; plain = candidate.lines.map(\.text).joined(separator: "\n"); wordSource = candidate.source
        message = incoming == 2 ? "Karaoke por palabra disponible" : "Letra sincronizada por frase disponible"
        wordStatus = incoming == 2 ? "\(candidate.source) · \(candidate.wordCount) palabras con tiempos reales" : "\(candidate.source) · sincronización por frase"
    }
    func finishLyricsSearch() {
        lyricsLoading = false
        if lines.isEmpty && plain.isEmpty {
            message = networkAvailable ? "Sin letra disponible en las fuentes consultadas" : "Sin conexión · no hay letra guardada para esta canción"
            wordStatus = "La búsqueda en todas las fuentes ha terminado"
            if !networkAvailable { scheduleLyricsRetry() } else { retryAfter = .distantFuture }
        } else {
            retryAfter = .distantFuture
            if lyricRank(lines, duration: track?.duration ?? 0) < 2 {
                wordStatus = lines.isEmpty ? "Letra sin tiempos disponible" : "Letra por frase · no se encontraron tiempos por palabra en las fuentes consultadas"
            }
        }
    }
    func fetch(_ song: Track, bypass: Bool = false) {
        if restoreSelectedLyrics(for: song) { return }
        request?.cancel(); wordRequest?.cancel()
        lyricRequestToken = UUID()
        let token = lyricRequestToken
        retryAfter = .distantFuture
        lyricsLoading = true
        if lines.isEmpty && plain.isEmpty { message = "Buscando letras en todas las fuentes…" }
        wordStatus = "Comprobando fuentes de letras…"
        let lineFile = cacheFile(song.key)
        let wordFile = lineFile.appendingPathExtension("words.json")
        if !bypass {
            if let raw = try? Data(contentsOf: lineFile), let row = try? JSONDecoder().decode(LyricResponse.self, from: raw) { apply(row) }
            if let raw = try? Data(contentsOf: wordFile), let cached = try? JSONDecoder().decode(WordLyricsResult.self, from: raw),
               let cleaned = LyricsQuality.accepted(cached, reference: cachedReference(song), filterHan: filterHanLyrics) {
                mergeLyricsCandidate(cleaned)
                if lyricRank(cleaned.lines, duration: song.duration) == 2 { lyricsLoading = false; return }
            }
        }
        let filter = filterHanLyrics
        let reference = cachedReference(song)
        request = Task { [self] in
            async let fallback = LineSource.shared.get(song, bypass: bypass)
            async let candidates = WordSources.fetch(song, filterHan: filter, reference: reference, onCandidate: { [weak self] candidate in
                guard let self, self.lyricRequestToken == token, self.track?.key == song.key, !self.usingSelectedLyrics else { return }
                self.mergeLyricsCandidate(candidate)
            })
            let row = await fallback
            guard !Task.isCancelled, lyricRequestToken == token, track?.key == song.key, !usingSelectedLyrics else { return }
            if let row {
                apply(row)
                if let raw = try? JSONEncoder().encode(row) { try? raw.write(to: lineFile, options: .atomic) }
            }
            let best = await candidates
            guard !Task.isCancelled, lyricRequestToken == token, track?.key == song.key, !usingSelectedLyrics else { return }
            if let best {
                mergeLyricsCandidate(best)
                if wordSource == best.source, lines == best.lines, let raw = try? JSONEncoder().encode(best) { try? raw.write(to: wordFile, options: .atomic) }
            }
            finishLyricsSearch()
        }
    }
    func apply(_ lyrics: LyricResponse) {
        guard !usingSelectedLyrics else { return }
        let rich = parseLyricsfile(lyrics.lyricsfile ?? "")
        let lrc = parseLRC(lyrics.syncedLyrics ?? "")
        let incoming = rich.contains(where: \.hasWords) ? rich : (lrc.contains(where: \.hasWords) ? lrc : (rich.isEmpty ? lrc : rich))
        // A slower line-only source must not replace a word-timed result.
        if !wordSource.isEmpty && lines.contains(where: \.hasWords) { return }
        let review = incoming.isEmpty ? LyricsQuality.reviewPlain(lyrics.plainLyrics ?? "", filterHan: filterHanLyrics) : LyricsQuality.review(incoming, filterHan: filterHanLyrics)
        qualityStatus = review.notes.joined(separator: " · ")
        guard !review.suspicious else { message = lyricsLoading ? "Buscando una letra legible en las demás fuentes…" : "Letra descartada por problemas de legibilidad · elige otra fuente"; return }
        lines = incoming.isEmpty ? [] : review.lines
        wordSource = "LRCLIB"
        if incoming.contains(where: \.hasWords) { wordStatus = "LRCLIB o archivo local · tiempos por palabra" }
        plain = lines.isEmpty ? (lyrics.plainLyrics ?? "").components(separatedBy: .newlines).filter { !filterHanLyrics || !LyricsQuality.hasHan($0) }.joined(separator: "\n") : lines.map(\.text).joined(separator: "\n")
        message = lyrics.instrumental == true ? "♪ Instrumental" : (!lines.isEmpty ? "Letra sincronizada disponible" : (plain.isEmpty ? (lyricsLoading ? "Buscando letras en todas las fuentes…" : "Sin letra disponible") : "Letra sin tiempos · ábrela con un clic"))
    }
    func control(_ command: String) {
        guard let player = track?.player, !demo else { return }
        Task.detached { var error: NSDictionary?; _ = NSAppleScript(source: "tell application \"\(player)\" to \(command)")?.executeAndReturnError(&error) }
    }
    func openPlayer() {
        guard !demo, let player = track?.player,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: player == "Spotify" ? "com.spotify.client" : "com.apple.Music") else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in }
    }
    func seek(toLyricTime time: Double) {
        guard let song = track, let target = lyricSeekPosition(time: time, offset: offset, duration: song.duration) else { return }
        seek(toPosition: target)
    }
    func seek(toPosition time: Double) {
        guard !suspended, let song = track, demo || ["Spotify", "Music"].contains(song.player), let target = lyricSeekPosition(time: time, offset: 0, duration: song.duration) else { return }
        seekGeneration += 1
        playbackError = nil
        sampledPosition = target; position = target; lastSample = Date()
        if demo { track?.position = target; return }
        pendingSeek = (song, target)
        guard seekRequest == nil else { return }
        seekRequest = Task {
            while let (song, target) = pendingSeek {
                pendingSeek = nil
                let generation = seekGeneration
                let seekEpoch = playbackEpoch
                let outcome = await Task.detached { () -> (Double?, String?) in
                    var error: NSDictionary?
                    // Player names are allowlisted; escape the title before guarding against a track change.
                    let title = song.title.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
                    let script = "with timeout of 3 seconds\ntell application \"\(song.player)\"\nif name of current track is not \"\(title)\" then error \"La canción ha cambiado; vuelve a pulsar la frase.\"\nset player position to \(target)\nreturn player position\nend tell\nend timeout"
                    let value = NSAppleScript(source: script)?.executeAndReturnError(&error)
                    return (error == nil ? value?.doubleValue : nil, error?[NSAppleScript.errorMessage] as? String)
                }.value
                guard seekEpoch == playbackEpoch, !suspended, track?.key == song.key, track?.player == song.player else { pendingSeek = nil; break }
                if generation == seekGeneration {
                    if let actual = outcome.0 {
                        sampledPosition = actual; position = actual; lastSample = Date(); track?.position = actual
                    } else {
                        playbackError = outcome.1 ?? "No se ha podido saltar a esa frase. Comprueba el permiso de Automatización."
                    }
                }
            }
            seekRequest = nil
            poll()
        }
    }
    func importLRC() {
        guard track != nil, !demo else { message = "Reproduce una canción antes de importar su letra"; return }
        let dialog = NSOpenPanel(); dialog.allowedContentTypes = [UTType(filenameExtension: "lrc") ?? .plainText, UTType(filenameExtension: "yaml") ?? .plainText, .plainText]
        NSApp.activate(ignoringOtherApps: true)
        guard dialog.runModal() == .OK, let url = dialog.url, let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        let rich = parseLyricsfile(text)
        let parsed = rich.isEmpty ? parseLRC(text) : rich
        guard !parsed.isEmpty else { message = "El archivo no contiene tiempos LRC válidos"; return }
        if let track { selectLyrics(LyricChoice(id: "local", source: "Archivo local", title: track.title, artist: track.artist, duration: track.duration, lines: parsed, plain: parsed.map(\.text).joined(separator: "\n"))) }

    }
    func toggleDemo() {
        playbackEpoch += 1; pollTask?.cancel(); polling = false
        usingSelectedLyrics = false; retryAfter = .distantFuture
        demo.toggle(); request?.cancel(); wordRequest?.cancel(); wordSource = ""; artworkRequest?.cancel(); artwork = nil; songNoticeTask?.cancel(); songNotice = false
        if demo {
            track = Track(title: "Tu música, a tu manera", artist: "Notch Letras · Demostración", album: "", duration: 180, position: 0, playing: true, player: "Demo")
            lines = (0..<30).map { index in
                let text = ["Tu música, a tu manera", "Las palabras encuentran su lugar", "Un pequeño espacio para cada canción", "Hazlo tuyo, a tu ritmo", "Todo empieza con una melodía"][index % 5]
                let words = text.split(separator: " ").map(String.init)
                let start = Double(index * 6)
                let span = 4.8 / Double(words.count)
                return LyricLine(time: start, text: text, end: start + 4.8, words: words.enumerated().map { i, word in
                    WordTiming(text: word + (i < words.count - 1 ? " " : ""), start: start + Double(i) * span, end: start + Double(i + 1) * span)
                })
            }
            loadSongOffset()
            wordStatus = "Demostración sintética: no verifica sincronización con audio"
            message = "Demostración · frases de muestra, sin audio"
            sampledPosition = 0; position = 0; lastSample = Date()
        } else { track = nil; lines = []; loadSongOffset(); poll() }
        layout?()
    }
}

struct LiveLyricsView: View {
    @ObservedObject var model: Model
    var body: some View {
        VStack(spacing: 5) {
            Group {
                if let index = model.currentIndex, model.lines.indices.contains(index) {
                    AnimatedLyricLine(model: model, line: model.lines[index], visible: model.panelVisible, centered: true)
                } else { Text(model.currentText).foregroundStyle(.white) }
            }
            .font(.system(size: model.fontSize, weight: .semibold, design: .rounded))
            .lineLimit(model.expanded ? 2 : 1).minimumScaleFactor(0.75)
            .multilineTextAlignment(.center)
            if model.expanded || model.twoLines, let next = model.nextText {
                Text(next).font(.system(size: max(12, model.fontSize - 3), weight: .medium, design: .rounded))
                    .foregroundStyle(model.lyricColor.opacity(0.4)).lineLimit(1).minimumScaleFactor(0.8)
                    .accessibilityLabel("Siguiente frase: \(next)")
            }
        }
    }
}
struct NotchView: View {
    @ObservedObject var model: Model
    let top: CGFloat
    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: top)
            if model.expanded {
                HStack {
                    Button { model.openPlayer() } label: {
                        Group {
                            if let artwork = model.artwork { Image(nsImage: artwork).resizable().scaledToFill() }
                            else { Image(systemName: "waveform").resizable().scaledToFit().padding(13).foregroundStyle(model.tint) }
                        }
                        .frame(width: 56, height: 56).clipShape(RoundedRectangle(cornerRadius: 11))
                    }
                    .disabled(model.track == nil || model.demo)
                    .help("Abrir \(model.track?.player == "Music" ? "Música" : "Spotify")")
                    .accessibilityLabel("Abrir reproductor desde la carátula")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.track?.title ?? "Notch Letras").font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        Text(model.track?.artist ?? "Tu música, a tu manera").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Button { model.pinned.toggle() } label: {
                        Image(systemName: model.pinned ? "pin.fill" : "pin")
                    }.help(model.pinned ? "Desfijar notch" : "Mantener abierto · Escape para cerrar")
                    .accessibilityLabel(model.pinned ? "Desfijar notch" : "Fijar notch")
                    Button { model.toggleExpansion?() } label: { Image(systemName: "chevron.up") }.help("Cerrar panel")
                    Button { model.showSettings?() } label: { Image(systemName: "slider.horizontal.3") }
                }.padding(.horizontal, 22).padding(.top, 10)
                    .transition(.opacity.combined(with: .offset(y: -6)))
            }
            Group {
                if model.lyricsEnabled {
                    if model.expanded && model.expandedLyrics {
                        LyricsListView(model: model, embedded: true).padding(.vertical, 10)
                    } else {
                    LiveLyricsView(model: model)
                        .opacity(model.songNotice ? 0 : 1)
                        .overlay {
                            if model.songNotice {
                                VStack(spacing: 3) {
                                    Text(model.track?.title ?? "Notch Letras").font(.system(size: model.fontSize, weight: .semibold)).lineLimit(1)
                                    if model.expanded { Text(model.track?.artist ?? "").font(.caption).foregroundStyle(.secondary) }
                                }.transition(.opacity.combined(with: .offset(y: 5)))
                            }
                        }
                    }
                } else {
                    Text(model.expanded ? "Controles de reproducción" : (model.track?.title ?? "Notch Letras"))
                        .font(.system(size: model.fontSize, weight: .medium)).lineLimit(1)
                }
            }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 18)
                .contentShape(Rectangle()).onTapGesture { if !model.expanded { model.toggleExpansion?() } }
            if model.expanded {
                LyricsToolsView(model: model).padding(.horizontal, 20).padding(.bottom, 6)
                PlaybackProgressView(model: model)
                HStack(spacing: 30) {
                    Button { model.control("previous track") } label: { Image(systemName: "backward.fill") }
                    Button { model.control("playpause") } label: { Image(systemName: model.track?.playing == true ? "pause.fill" : "play.fill") }
                    Button { model.control("next track") } label: { Image(systemName: "forward.fill") }
                    Button { withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { model.expandedLyrics.toggle() } } label: {
                        Image(systemName: model.expandedLyrics ? "text.badge.minus" : "text.alignleft")
                    }.help(model.expandedLyrics ? "Mostrar dos frases" : "Mostrar letra completa en el notch")
                    Button { model.showLyrics?() } label: { Image(systemName: "arrow.up.right.square") }.help("Abrir letra en una ventana")
                }.font(.system(size: 16)).padding(.bottom, 14)
                    .transition(.opacity.combined(with: .offset(y: 8)))
                if let error = model.playbackError {
                    Text(error).font(.caption).foregroundStyle(.orange).lineLimit(2).padding(.horizontal, 20).padding(.bottom, 8)
                }
                if model.demo { Text("DEMOSTRACIÓN").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary).padding(.bottom, 8) }
            }
        }
        .frame(width: model.visibleWidth, height: top + model.visibleHeight)
        .background {
            ZStack {
                Color.black
                if model.artworkEnabled, let artwork = model.artwork {
                    VStack(spacing: 0) {
                        Color.clear.frame(height: top)
                        GeometryReader { area in
                            Image(nsImage: artwork).resizable().scaledToFill()
                                .frame(width: min(model.visibleWidth * 0.6, 240), height: area.size.height)
                                .clipped().blur(radius: 5)
                                .mask(LinearGradient(colors: [.white, .white.opacity(0.8), .clear], startPoint: .leading, endPoint: .trailing))
                                .opacity(model.artworkOpacity)
                        }
                    }.accessibilityHidden(true).allowsHitTesting(false)
                }
            }
        }
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: model.expanded ? 22 : 14, bottomTrailingRadius: model.expanded ? 22 : 14))
        .foregroundStyle(.white).buttonStyle(.plain).environment(\.colorScheme, .dark)
        .frame(width: max(model.width, 500), height: top + model.maximumPanelHeight, alignment: .top)
    }
}
struct FullLyricsView: View {
    @ObservedObject var model: Model
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.track?.title ?? "Notch Letras").font(.title.bold())
            Text(model.track?.artist ?? "").foregroundStyle(.secondary)
            LyricsListView(model: model, embedded: false)
            if let error = model.playbackError { Text(error).font(.caption).foregroundStyle(.orange) }
        }.padding(28).frame(minWidth: 480, minHeight: 520)
    }
}
final class OverlayPanel: NSPanel {
    var closeNotch: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { closeNotch?() }
}
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = Model()
    var panel: OverlayPanel!
    var status: NSStatusItem!
    var settings: NSWindow?
    var lyrics: NSWindow?
    var hover = HoverState()
    var hapticTask: Task<Void, Never>?
    var choices: NSWindow?
    let shortcut = GlobalShortcut()
    var suppressHover = false
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Notch Letras")
        let menu = NSMenu()
        for (title, action) in [("Ajustes…", #selector(openSettings)), ("Letra completa", #selector(openLyrics)), ("Elegir otra letra…", #selector(openLyricChoices)), ("Fijar / cerrar notch", #selector(togglePinned)), ("Importar .lrc…", #selector(importLyrics)), ("Demostración", #selector(demo)), ("Salir", #selector(quit))] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: title == "Salir" ? "q" : ""); item.target = self; menu.addItem(item)
        }
        status.menu = menu
        panel = OverlayPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.level = .statusBar; panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false; panel.isMovable = false
        model.rebuild = { [weak self] in self?.refreshScreens() }
        model.toggleExpansion = { [weak self] in
            guard let self else { return }
            if self.model.expanded { self.closePanel() }
            else { self.model.pinned = true; self.setExpanded(true) }
        }
        panel.closeNotch = { [weak self] in self?.closePanel() }
        model.pinChanged = { [weak self] in
            guard let self else { return }
            self.shortcut.captureEscape(self.model.pinned)
            if self.model.pinned { self.suppressHover = false; self.setExpanded(true) }
            else { self.hover = HoverState(expanded: self.model.expanded) }
        }
        model.shortcutChanged = { [weak self] in self?.registerShortcut() }
        shortcut.action = { [weak self] in self?.togglePinned() }
        shortcut.close = { [weak self] in self?.closePanel() }
        registerShortcut()
        model.updateHover = { [weak self] in self?.checkHover() }
        model.layout = { [weak self] in self?.positionPanel() }
        model.showSettings = { [weak self] in self?.openSettings() }
        model.showLyrics = { [weak self] in self?.openLyrics() }
        model.showLyricChoices = { [weak self] in self?.openLyricChoices() }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(screenChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(playerChanged), name: Notification.Name("com.spotify.client.PlaybackStateChanged"), object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(playerChanged), name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(playerChanged), name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        refreshScreens(); model.start()
        if CommandLine.arguments.contains("--preview-cycle") {
            model.toggleDemo(); model.updateHover = nil
            Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { self.model.expanded.toggle() }
                }
            }
        } else if CommandLine.arguments.contains("--preview-karaoke") {
            model.toggleDemo(); model.updateHover = nil
            model.lines = (0..<40).map { row in
                let tokens = ["These ", "are ", "original ", "words ", "for ", "a ", "timing ", "test"]
                let start = Double(row * 5)
                let words = tokens.enumerated().map { index, text in WordTiming(text: text, start: start + Double(index)*0.5, end: start + Double(index)*0.5 + 0.45) }
                return LyricLine(time: start, text: tokens.joined(), end: start + 4, words: words)
            }
            model.track?.duration = 200
            model.wordStatus = "Original benchmark fixture · real test timestamps"
            positionPanel()
        } else if CommandLine.arguments.contains("--preview-player") {
            model.updateHover = nil; model.expanded = true; positionPanel()
        } else if CommandLine.arguments.contains("--preview-hover") {
            model.toggleDemo(); model.updateHover = nil; model.expanded = true; positionPanel()
        } else if !UserDefaults.standard.bool(forKey: "hasLaunched") {
            UserDefaults.standard.set(true, forKey: "hasLaunched"); openSettings()
        }
        if CommandLine.arguments.contains("--preview-paused") { model.sampledPosition = 2.25; model.position = 2.25; model.track?.playing = false }
        if CommandLine.arguments.contains("--preview-pinned") { model.pinned = true; setExpanded(true) }
        if CommandLine.arguments.contains("--preview-hidden") { model.panelVisible = false; panel.orderOut(nil) }
        if CommandLine.arguments.contains("--enable-login") { let login = LoginItem(); login.setEnabled(true) }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return true
    }
    func display() -> NSScreen? {
        NSScreen.screens.first { String(($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0) == model.screenID }
        ?? NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.screens.first
    }
    func refreshScreens() {
        model.screens = NSScreen.screens.map { ScreenChoice(id: String(($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0), name: $0.localizedName) }
        rebuildPanel()
    }
    func rebuildPanel() {
        let top = display()?.safeAreaInsets.top ?? 0
        model.availablePanelHeight = max(280, Double(display()?.frame.height ?? 900) - Double(top) - 80)
        let hosting = NSHostingView(rootView: NotchView(model: model, top: top))
        hosting.sizingOptions = []
        panel.contentView = hosting
        positionPanel()
    }
    @objc func screenChanged() { refreshScreens() }
    func checkHover() {
        let cursor = NSEvent.mouseLocation
        let visible = NSRect(x: panel.frame.midX - model.visibleWidth / 2,
                             y: panel.frame.maxY - (display()?.safeAreaInsets.top ?? 0) - model.visibleHeight,
                             width: model.visibleWidth, height: (display()?.safeAreaInsets.top ?? 0) + model.visibleHeight)
        let inside = panel.isVisible && visible.contains(cursor)
        // The hosting window keeps a stable size. Transparent space passes clicks through.
        if panel.ignoresMouseEvents != !inside { panel.ignoresMouseEvents = !inside }
        if suppressHover {
            if !inside { suppressHover = false }
            return
        }
        guard !model.pinned, !model.lyricsDiagnosticsOpen, !model.sourcePickerOpen, model.openOnHover else { hover = HoverState(expanded: model.expanded); return }
        let expanded = hover.update(inside: inside, now: ProcessInfo.processInfo.systemUptime)
        if model.expanded != expanded { setExpanded(expanded) }
    }
    func setExpanded(_ expanded: Bool) {
        hover = HoverState(expanded: expanded)
        let animation: Animation = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.42, dampingFraction: 0.86)
        withAnimation(animation) { model.expanded = expanded }
        hapticTask?.cancel()
        if expanded && model.hapticsEnabled {
            let style = model.hapticStyle
            let pattern: NSHapticFeedbackManager.FeedbackPattern = style == "soft" ? .alignment : (style == "marked" ? .levelChange : .generic)
            NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
            if style == "double" {
                hapticTask = Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(80))
                    guard !Task.isCancelled, let self, self.model.hapticsEnabled, self.model.expanded else { return }
                    NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                }
            }
        }
        positionPanel()
    }
    func positionPanel() {
        guard let screen = display() else { return }
        let height = screen.safeAreaInsets.top + model.maximumPanelHeight
        let width = max(model.width, 500)
        let frame = NSRect(x: screen.frame.midX - width / 2, y: screen.frame.maxY - height, width: width, height: height)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        let visible = shouldShowPanel(enabled: model.panelEnabled, hidePaused: model.hidePaused, playing: model.track?.playing == true || model.pinned,
                                      hideFullScreen: model.hideFullScreen, fullScreen: NSApp.currentSystemPresentationOptions.contains(.fullScreen))
        if model.panelVisible != visible { model.panelVisible = visible }
        if !visible {
            if panel.isVisible { panel.orderOut(nil) }
        } else if !panel.isVisible { panel.orderFrontRegardless() }
    }
    func registerShortcut() {
        model.shortcutStatus = shortcut.register(model.shortcut) ? "" : "Este atajo ya está ocupado. Elige otro."
    }
    @objc func togglePinned() {
        if model.pinned { closePanel() }
        else { model.pinned = true; setExpanded(true) }
    }
    func closePanel() {
        model.pinned = false
        suppressHover = true
        setExpanded(false)
        if panel.isKeyWindow { panel.resignKey() }
    }
    @objc func playerChanged() { model.nextPoll = .distantPast; model.poll() }
    @objc func willSleep() { model.prepareForSleep() }
    @objc func didWake() { refreshScreens(); model.resumePlayback() }
    func applicationWillTerminate(_ notification: Notification) {
        shortcut.stop(); model.networkMonitor?.cancel(); model.timer?.invalidate()
    }
    @objc func openLyricChoices() {
        if choices == nil { choices = window(title: "Notch Letras · Elegir letra", view: LyricChoicesView(model: model)) }
        NSApp.activate(ignoringOtherApps: true); choices?.makeKeyAndOrderFront(nil)
    }
    @objc func openSettings() {
        if settings == nil {
            settings = window(title: "Notch Letras · Ajustes", view: SettingsView(model: model))
            settings?.setContentSize(NSSize(width: 860, height: 600)); settings?.center()
        }
        NSApp.activate(ignoringOtherApps: true); settings?.makeKeyAndOrderFront(nil)
    }
    @objc func lyricsClosed() { model.lyricsWindowVisible = false }
    @objc func openLyrics() {
        if lyrics == nil {
            lyrics = window(title: "Notch Letras · Letra", view: FullLyricsView(model: model))
            NotificationCenter.default.addObserver(self, selector: #selector(lyricsClosed), name: NSWindow.willCloseNotification, object: lyrics)
        }
        model.lyricsWindowVisible = true
        NSApp.activate(ignoringOtherApps: true); lyrics?.makeKeyAndOrderFront(nil)
    }
    func window<V: View>(title: String, view: V) -> NSWindow {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 760), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        w.title = title; w.contentView = NSHostingView(rootView: view); w.isReleasedWhenClosed = false; w.center(); return w
    }
    @objc func importLyrics() { model.importLRC() }
    @objc func demo() { model.toggleDemo() }
    @objc func quit() { NSApp.terminate(nil) }
}
if CommandLine.arguments.contains("--self-test") {
    MainActor.assumeIsolated { verifyNativeInkAlignment() }
    verifyKaraoke()
    verifyWordSources()
    MainActor.assumeIsolated { verifyAppReliability() }
    MainActor.assumeIsolated {
        let model = Model()
        model.track = Track(title: "Timing check", artist: "", album: "", duration: 120, position: 10, playing: true, player: "Demo")
        model.lastSample = Date(timeIntervalSinceReferenceDate: 100)
        model.sampledPosition = 10
        precondition(model.playbackPosition(at: Date(timeIntervalSinceReferenceDate: 102)) == 12)
        model.track?.playing = false
        precondition(model.playbackPosition(at: Date(timeIntervalSinceReferenceDate: 110)) == 10)
        model.sampledPosition = 60
        precondition(model.playbackPosition(at: Date(timeIntervalSinceReferenceDate: 110)) == 60)
        model.track?.playing = true
        precondition(model.playbackPosition(at: Date(timeIntervalSinceReferenceDate: 170)) == 120)
        precondition(lyricSeekPosition(time: 45, offset: 2, duration: 120) == 43)
        precondition(lyricSeekPosition(time: 1, offset: 2, duration: 120) == 0)
        precondition(lyricSeekPosition(time: 150, offset: -2, duration: 120) == 120)
        precondition(lyricSeekPosition(time: .nan, offset: 0, duration: 120) == nil)
        precondition(lyricSeekPosition(time: 10, offset: 0, duration: 0) == nil)
        model.demo = true
        model.seek(toLyricTime: 42)
        precondition(model.position == 42 - model.offset)
        print("Playback checks passed: interpolation, pause freeze, lyric seek with offset, invalid times and duration clamp.")
    }
    let lines = parseLRC("[ar:Artist]\n[00:01.5]One\n[01:02.050][00:03.00]Two\n[00:04]\ninvalid")
    precondition(lines.count == 4)
    precondition(lines.map(\.time) == [1.5, 3, 4, 62.05])
    precondition(lines[1].text == "Two" && lines[2].text.isEmpty)
    precondition(nextLyric(in: lines, at: 0) == "One")
    precondition(nextLyric(in: lines, at: 1.5) == "Two")
    precondition(nextLyric(in: lines, at: 3) == "Two") // skip blank instrumental marker
    precondition(nextLyric(in: lines, at: 62.05) == nil)
    var hover = HoverState()
    precondition(hover.update(inside: true, now: 0))
    precondition(hover.update(inside: false, now: 0.1))
    precondition(hover.update(inside: true, now: 0.2)) // transient exit during resize
    precondition(hover.update(inside: false, now: 1))
    precondition(hover.update(inside: false, now: 1.2))
    precondition(!hover.update(inside: false, now: 1.3))
    precondition(hover.update(inside: true, now: 2))
    print("Checks passed: LRC parsing, next lyric boundaries and blanks, hover enter/exit hysteresis and re-entry.")
} else if let flag = CommandLine.arguments.firstIndex(of: "--probe-lyrics"), CommandLine.arguments.count > flag + 3 {
    let args = CommandLine.arguments
    Task { @MainActor in
        let model = Model()
        let song = Track(title: args[flag+1], artist: args[flag+2], album: "Deliberately different album edition", duration: Double(args[flag+3]) ?? 0, position: 0, playing: false, player: "Spotify")
        model.track = song
        model.cache = FileManager.default.temporaryDirectory.appendingPathComponent("notch-lookup-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: model.cache, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: model.cache) }
        model.fetch(song, bypass: true)
        for _ in 0..<600 {
            if !model.lyricsLoading { break }
            if model.lines.isEmpty && model.plain.isEmpty { precondition(!model.message.contains("Sin letra disponible")) }
            try? await Task.sleep(for: .milliseconds(100))
        }
        print("SOURCE=\(model.wordSource) LINES=\(model.lines.count) WORDS=\(model.lines.filter(\.hasWords).count) STATUS=\(model.message) LOADING=\(model.lyricsLoading)")
        exit(model.lyricsLoading || (model.lines.isEmpty && model.plain.isEmpty) ? 2 : 0)
    }
    dispatchMain()
} else if let flag = CommandLine.arguments.firstIndex(of: "--probe-song"), CommandLine.arguments.count > flag + 3 {
    let args = CommandLine.arguments
    let song = Track(title: args[flag + 1], artist: args[flag + 2], album: "", duration: Double(args[flag + 3]) ?? 0, position: 0, playing: false, player: "Spotify")
    Task {
        let provider = args.firstIndex(of: "--provider").flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
        let result: WordLyricsResult?
        if provider == "qq" { result = await WordSources.qqMusic(song) }
        else if provider == "kugou" { result = await WordSources.kugou(song) }
        else { result = await WordSources.fetch(song) }
        if let found = result {
            print("SOURCE=\(found.source) TITLE=\(found.title) WORDS=\(found.wordCount) COVERAGE=\(found.coverage)")
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("notch-word-probe.json")
            try? JSONEncoder().encode(found).write(to: file)
            exit(0)
        } else { print("NO_VERIFIED_WORD_TIMINGS"); exit(2) }
    }
    dispatchMain()
} else {
    MainActor.assumeIsolated {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
