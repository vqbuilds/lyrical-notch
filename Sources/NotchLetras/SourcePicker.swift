import SwiftUI

enum LyricProvider: String, CaseIterable, Identifiable {
    case qq = "QQ Music", kugou = "Kugou", netease = "NetEase", amll = "AMLL", red = "lrc.red", lrclib = "LRCLIB"
    var id: String { rawValue }
    func fetch(_ song: Track) async -> WordLyricsResult? {
        switch self {
        case .qq: return await WordSources.qqMusic(song)
        case .kugou: return await WordSources.kugou(song)
        case .netease: return await WordSources.netease(song)
        case .amll: return await WordSources.amll(song)
        case .red: return await WordSources.lrcRed(song)
        case .lrclib:
            let lines = await WordSources.referenceLines(song, bypass: true)
            guard lines.contains(where: { $0.time > 0 }) else { return nil }
            return WordLyricsResult(source: "LRCLIB", title: song.title, artist: song.artist, duration: song.duration, lines: lines)
        }
    }
}
@MainActor extension Model {
    func chooseProvider(_ provider: LyricProvider) {
        guard let song = track, !demo else { return }
        providerRequest?.cancel(); providerToken = UUID()
        if let cached = providerChoices[provider] {
            choosingProvider = false; selectLyrics(cached)
            providerMessage = "\(provider.rawValue) seleccionada · ya disponible en esta sesión."
            return
        }
        let token = providerToken
        choosingProvider = true; providerMessage = "Buscando en \(provider.rawValue)…"
        let filter = filterHanLyrics
        let cached = cachedReference(song)
        providerRequest = Task {
            async let raw = provider.fetch(song)
            async let refs = cached.isEmpty ? WordSources.referenceLines(song) : cached
            let (result, reference) = await (raw, refs)
            guard !Task.isCancelled, token == providerToken, track?.key == song.key else { return }
            choosingProvider = false
            guard let result else { providerMessage = "\(provider.rawValue) no tiene una versión válida para esta grabación. Se conserva la actual."; return }
            let review = LyricsQuality.review(result.lines, reference: reference, filterHan: filter)
            guard !review.suspicious, !review.lines.isEmpty else {
                providerMessage = "\(provider.rawValue): texto descartado por legibilidad. Se conserva la letra actual."; return
            }
            let choice = LyricChoice(id: provider.id, source: result.source, title: result.title, artist: result.artist,
                duration: result.duration, lines: review.lines, plain: review.lines.map(\.text).joined(separator: "\n"))
            providerChoices[provider] = choice
            selectLyrics(choice)
            qualityStatus = review.notes.joined(separator: " · ")
            providerMessage = "\(provider.rawValue) seleccionada y guardada para esta canción."
        }
    }
}
struct SourcePickerView: View {
    @ObservedObject var model: Model
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Fuente de letras").font(.headline)
            Text(model.lyricsSourceLabel).font(.caption).foregroundStyle(.secondary)
            ForEach(LyricProvider.allCases) { provider in
                Button { model.chooseProvider(provider) } label: {
                    HStack { Text(provider.rawValue); Spacer(); Image(systemName: "arrow.triangle.2.circlepath") }
                }.disabled(model.track == nil || model.demo || !model.networkAvailable)
            }
            if model.choosingProvider { ProgressView().controlSize(.small) }
            if !model.providerMessage.isEmpty { Text(model.providerMessage).font(.caption).fixedSize(horizontal: false, vertical: true) }
            if !model.qualityStatus.isEmpty { Text(model.qualityStatus).font(.caption).foregroundStyle(.secondary) }
            Divider()
            Button("Automática") {
                model.providerRequest?.cancel(); model.providerToken = UUID(); model.choosingProvider = false; model.providerMessage = ""
                model.useAutomaticLyrics()
            }.disabled(model.track == nil || model.demo)
            Button("Ver versiones y fragmentos…") { model.sourcePickerOpen = false; model.showLyricChoices?() }
        }.padding(16).frame(width: 290)
    }
}
