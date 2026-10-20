import SwiftUI

struct LyricChoice: Codable, Identifiable {
    var id: String
    var source: String
    var title: String
    var artist: String
    var duration: Double
    var lines: [LyricLine]
    var plain: String
    var isUsable: Bool {
        duration.isFinite && duration > 0 && lines.count < 10_000 && plain.utf8.count < 2_000_000 &&
        (!lines.isEmpty || !plain.isEmpty) && lines.allSatisfy { $0.time.isFinite && $0.time >= 0 && $0.time < 86_400 }
    }
    var timing: String { lines.contains(where: \.hasWords) ? "Por palabra" : (lines.isEmpty ? "Sin tiempos" : "Por frase") }
    static func words(_ value: WordLyricsResult) -> LyricChoice {
        LyricChoice(id: value.source, source: value.source, title: value.title, artist: value.artist,
            duration: value.duration, lines: value.lines, plain: value.lines.map(\.text).joined(separator: "\n"))
    }
}

@MainActor extension Model {
    func selectedLyricsFile(for song: Track) -> URL { cacheFile(song.key).appendingPathExtension("selected.json") }
    func restoreSelectedLyrics(for song: Track) -> Bool {
        guard let raw = try? Data(contentsOf: selectedLyricsFile(for: song)),
              let choice = try? JSONDecoder().decode(LyricChoice.self, from: raw), choice.isUsable else { return false }
        let review = choice.lines.isEmpty ? LyricsQuality.reviewPlain(choice.plain, filterHan: filterHanLyrics) : LyricsQuality.review(choice.lines, reference: cachedReference(song), filterHan: filterHanLyrics)
        guard !review.suspicious else { return false }
        applySelectedLyrics(choice)
        return true
    }
    func applySelectedLyrics(_ choice: LyricChoice) {
        request?.cancel(); wordRequest?.cancel(); lyricRequestToken = UUID(); lyricsLoading = false; usingSelectedLyrics = true
        retryAfter = .distantFuture
        let review = LyricsQuality.review(choice.lines, reference: track.map(cachedReference) ?? [], filterHan: filterHanLyrics)
        lines = review.lines
        plain = lines.isEmpty ? choice.plain.components(separatedBy: .newlines).filter { !filterHanLyrics || !LyricsQuality.hasHan($0) }.joined(separator: "\n") : lines.map(\.text).joined(separator: "\n")
        qualityStatus = review.notes.joined(separator: " · ")
        wordSource = choice.source
        wordStatus = "\(choice.source) · \(choice.timing.lowercased()) · elección guardada para esta canción"
        message = "Letra elegida: \(choice.title) · \(choice.artist)"
    }
    func selectLyrics(_ choice: LyricChoice) {
        guard choice.isUsable, let song = track, !demo else { return }
        let review = choice.lines.isEmpty ? LyricsQuality.reviewPlain(choice.plain, filterHan: filterHanLyrics) : LyricsQuality.review(choice.lines, reference: cachedReference(song), filterHan: filterHanLyrics)
        guard !review.suspicious else { playbackError = "Esta versión tiene palabras pegadas o texto filtrado. Prueba otra fuente."; return }
        providerRequest?.cancel(); providerToken = UUID(); choosingProvider = false
        playbackError = nil
        applySelectedLyrics(choice)
        do {
            try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
            try JSONEncoder().encode(choice).write(to: selectedLyricsFile(for: song), options: .atomic)
        } catch { playbackError = "La letra se ha aplicado, pero no se pudo guardar: \(error.localizedDescription)" }
    }
    func useAutomaticLyrics() {
        guard let song = track, !demo else { return }
        do {
            let file = selectedLyricsFile(for: song)
            if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
        } catch { playbackError = "No se pudo restablecer la letra automática."; return }
        usingSelectedLyrics = false; wordSource = ""; lines = []; plain = ""
        fetch(song)
    }
}

@MainActor final class LyricSearch: ObservableObject {
    @Published var title = ""
    @Published var artist = ""
    @Published var loading = false
    @Published var results: [LyricChoice] = []
    @Published var message = "Busca versiones alternativas y revisa el comienzo antes de elegir."
    var task: Task<Void, Never>?
    var generation = UUID()
    func reset(_ song: Track?) {
        task?.cancel(); generation = UUID(); loading = false
        title = song?.title ?? ""; artist = song?.artist ?? ""; results = []
        message = "Busca versiones alternativas y revisa el comienzo antes de elegir."
    }
    func search(_ playing: Track, filterHan: Bool = true) {
        task?.cancel(); generation = UUID()
        let token = generation
        var query = playing
        query.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        query.artist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.title != playing.title || query.artist != playing.artist { query.spotifyID = "" }
        guard !query.title.isEmpty else { message = "Escribe un título."; return }
        loading = true; results = []; message = "Buscando versiones en las fuentes disponibles…"
        task = Task {
            let reference = Task { await WordSources.referenceLines(playing) }
            defer { reference.cancel() }
            await withTaskGroup(of: [LyricChoice].self) { group in
                group.addTask { await WordSources.qqMusic(query).map { [LyricChoice.words($0)] } ?? [] }
                group.addTask { await WordSources.kugou(query).map { [LyricChoice.words($0)] } ?? [] }
                group.addTask { await WordSources.amll(query).map { [LyricChoice.words($0)] } ?? [] }
                group.addTask { await WordSources.netease(query).map { [LyricChoice.words($0)] } ?? [] }
                group.addTask { await WordSources.lrcRed(query).map { [LyricChoice.words($0)] } ?? [] }
                group.addTask {
                    var url = URLComponents(string: "https://lrclib.net/api/search")!
                    url.queryItems = [URLQueryItem(name: "track_name", value: query.title), URLQueryItem(name: "artist_name", value: query.artist)]
                    guard let raw = try? await WordSources.data(url.url!),
                          let rows = try? JSONDecoder().decode([LyricResponse].self, from: raw) else { return [] }
                    return rows.prefix(30).enumerated().compactMap { index, row in
                        let rich = parseLyricsfile(row.lyricsfile ?? "")
                        let lines = rich.isEmpty ? parseLRC(row.syncedLyrics ?? "") : rich
                        let choice = LyricChoice(id: "lrclib-\(index)", source: "LRCLIB", title: row.trackName ?? query.title,
                            artist: row.artistName ?? query.artist, duration: row.duration ?? playing.duration,
                            lines: lines, plain: row.plainLyrics ?? lines.map(\.text).joined(separator: "\n"))
                        return choice.isUsable ? choice : nil
                    }
                }
                for await choices in group {
                    guard !Task.isCancelled, generation == token else { group.cancelAll(); return }
                    let refs = await reference.value
                    guard !Task.isCancelled, generation == token else { group.cancelAll(); return }
                    let readable = choices.filter(\.isUsable).compactMap { choice -> LyricChoice? in
                        let checked = LyricsQuality.review(choice.lines, reference: refs, filterHan: filterHan)
                        guard !checked.suspicious, !choice.lines.isEmpty || !LyricsQuality.reviewPlain(choice.plain, filterHan: filterHan).suspicious else { return nil }
                        var value = choice; value.lines = checked.lines
                        value.plain = checked.lines.isEmpty ? choice.plain.components(separatedBy: .newlines).filter { !filterHan || !LyricsQuality.hasHan($0) }.joined(separator: "\n") : checked.lines.map(\.text).joined(separator: "\n")
                        return value.lines.isEmpty && value.plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : value
                    }
                    results.append(contentsOf: readable)
                    results.sort { left, right in
                        let leftDistance = abs(left.duration - playing.duration)
                        let rightDistance = abs(right.duration - playing.duration)
                        if abs(leftDistance - rightDistance) > 2.5 { return leftDistance < rightDistance }
                        if left.lines.contains(where: \.hasWords) != right.lines.contains(where: \.hasWords) { return left.lines.contains(where: \.hasWords) }
                        return left.id < right.id
                    }
                }
            }
            guard generation == token, !Task.isCancelled else { return }
            loading = false
            message = results.isEmpty ? "No hay resultados. Revisa título y artista o importa un archivo local. Si estás sin conexión, vuelve a buscar al reconectar." : "\(results.count) versiones. Una duración distinta puede corresponder a otra grabación."
        }
    }
}

struct LyricChoicesView: View {
    @ObservedObject var model: Model
    @StateObject private var search = LyricSearch()
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Elegir letra para esta canción").font(.title2.bold())
            Text("\(model.track?.title ?? "Sin canción") · \(model.track?.artist ?? "")").foregroundStyle(.secondary)
            HStack {
                TextField("Título", text: $search.title)
                TextField("Artista", text: $search.artist)
                Button("Buscar") { if let song = model.track { search.search(song, filterHan: model.filterHanLyrics) } }
                    .disabled(model.track == nil || model.demo || search.loading)
            }.textFieldStyle(.roundedBorder)
            HStack {
                if search.loading { ProgressView().controlSize(.small) }
                Text(search.message).font(.caption).foregroundStyle(.secondary)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(search.results) { choice in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(choice.title).font(.headline)
                                    Text("\(choice.artist) · \(playbackTimeLabel(choice.duration)) · \(choice.source) · \(choice.timing)").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Usar esta letra") { model.selectLyrics(choice) }
                            }
                            if abs(choice.duration - (model.track?.duration ?? 0)) > 2.5 {
                                Text("Duración distinta: comprueba que sea la misma grabación.").font(.caption).foregroundStyle(.orange)
                            }
                            Text(String(choice.plain.prefix(240))).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                        }.padding(12).background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            Divider()
            HStack {
                Button("Volver a selección automática") { model.useAutomaticLyrics() }.disabled(model.track == nil || model.demo)
                Button("Importar archivo…") { model.importLRC() }.disabled(model.track == nil || model.demo)
            }
            Text(model.message).font(.caption).foregroundStyle(.secondary)
        }.padding(22).frame(minWidth: 640, minHeight: 520)
        .onAppear { search.reset(model.track) }
        .onChange(of: model.track?.key) { _, _ in search.reset(model.track) }
        .onDisappear { search.task?.cancel() }
    }
}
