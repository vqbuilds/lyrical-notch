import SwiftUI

@MainActor extension Model {
    var lyricsSourceLabel: String {
        if demo { return "Demostración" }
        if !wordSource.isEmpty { return wordSource }
        return lines.isEmpty && plain.isEmpty ? "Sin fuente cargada" : "LRCLIB"
    }
    var lyricsTimingLabel: String {
        let timed = lines.filter(\.hasWords).count
        if timed > 0 {
            let vocal = lines.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
            return timed < vocal ? "Por palabra · cobertura parcial" : "Por palabra"
        }
        return lines.isEmpty ? (plain.isEmpty ? "Sin letra" : "Sin tiempos") : "Por frase"
    }
    func adjustLyrics(by delta: Double) {
        guard track != nil, !demo, delta.isFinite else { return }
        offset = min(10, max(-10, ((offset + delta) * 10).rounded() / 10))
    }
    func refreshLyrics() {
        guard let song = track, !demo, !usingSelectedLyrics, networkAvailable, !refreshingLyrics else { return }
        refreshToken = UUID()
        let token = refreshToken
        lyricRetryCount = 0; retryDelay = 20
        refreshingLyrics = true
        fetch(song, bypass: true)
        let lineTask = request
        let wordsTask = wordRequest
        Task {
            await lineTask?.value
            await wordsTask?.value
            guard refreshToken == token else { return }
            refreshingLyrics = false
        }
    }
}

struct LyricsDiagnosticsView: View {
    @ObservedObject var model: Model
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Fuente: \(model.lyricsSourceLabel)").font(.headline)
            if model.lyricsLoading { Text("Comprobando todas las fuentes…").font(.caption).foregroundStyle(.secondary) }
            Text("Sincronización: \(model.lyricsTimingLabel)")
            if model.spotifyTransitionCorrection > 0 {
                Text("Compensación de transición: \(String(format: "%.1f", model.spotifyTransitionCorrection)) s").font(.caption)
            }
            if !model.karaokeEnabled { Text("Relleno karaoke desactivado en Ajustes.").foregroundStyle(.secondary) }
            if !model.networkAvailable { Text("Sin conexión · se conserva la letra cargada.").foregroundStyle(.secondary) }
            Text(model.wordStatus).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if model.usingSelectedLyrics {
                Text("Letra elegida manualmente. Puedes buscar otra versión o volver a la selección automática desde el selector.").font(.caption)
            }
            HStack {
                Button(model.refreshingLyrics ? "Buscando…" : "Volver a buscar") { model.refreshLyrics() }
                    .disabled(model.track == nil || model.demo || model.usingSelectedLyrics || !model.networkAvailable || model.refreshingLyrics)
                Button("Elegir otra…") { model.showLyricChoices?() }.disabled(model.track == nil || model.demo)
            }
        }
    }
}

struct LyricsToolsView: View {
    @ObservedObject var model: Model
    var body: some View {
        HStack(spacing: 10) {
            Button { model.lyricsDiagnosticsOpen.toggle() } label: {
                Label(model.lyricsTimingLabel, systemImage: "info.circle").lineLimit(1)
            }
            .help("Ver fuente y diagnóstico de las letras")
            .popover(isPresented: $model.lyricsDiagnosticsOpen) {
                LyricsDiagnosticsView(model: model).padding(18).frame(width: 340)
            }
            Button { model.sourcePickerOpen.toggle() } label: {
                Label("Fuente", systemImage: "arrow.triangle.2.circlepath")
            }
            .help("Cambiar la fuente de letras de esta canción")
            .popover(isPresented: $model.sourcePickerOpen) { SourcePickerView(model: model) }
            Spacer(minLength: 0)
            Button("Antes") { model.adjustLyrics(by: 0.1) }
                .help("Mostrar la letra 0,1 segundos antes")
            Button { model.offset = 0 } label: { Text(String(format: "%+.1f s", model.offset)).monospacedDigit() }
                .help("Restablecer el ajuste de esta canción")
                .accessibilityLabel("Ajuste de letra, \(String(format: "%.1f", model.offset)) segundos. Restablecer")
            Button("Después") { model.adjustLyrics(by: -0.1) }
                .help("Mostrar la letra 0,1 segundos después")
        }
        .font(.system(size: 10))
        .disabled(model.track == nil || model.demo)
    }
}
