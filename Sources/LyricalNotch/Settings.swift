import SwiftUI

enum PreferencesPage: String, CaseIterable, Identifiable {
    case island = "Isla dinámica", lyrics = "Letras y karaoke", appearance = "Aspecto", general = "General"
    var id: String { rawValue }
    var icon: String {
        switch self { case .island: "macbook"; case .lyrics: "text.alignleft"; case .appearance: "paintpalette"; case .general: "gearshape" }
    }
}
@MainActor final class PreferencesSelection: ObservableObject { @Published var page: PreferencesPage? = .island }
struct SettingsView: View {
    @ObservedObject var model: Model
    @StateObject private var selection = PreferencesSelection()
    @StateObject private var login = LoginItem()
    var body: some View {
        NavigationSplitView {
            List(PreferencesPage.allCases, selection: $selection.page) { item in
                Label(item.rawValue, systemImage: item.icon).tag(item)
            }
            .navigationSplitViewColumnWidth(min: 165, ideal: 185, max: 215)
            .safeAreaInset(edge: .top) {
                HStack { Image(systemName: "waveform").foregroundStyle(model.tint); Text("Lyrical Notch").font(.headline); Spacer() }.padding(16)
            }
        } detail: {
            VStack(alignment: .leading, spacing: 0) {
                Text((selection.page ?? .island).rawValue).font(.title2.bold()).padding(.horizontal, 22).padding(.top, 20)
                Form {
                    switch selection.page ?? .island {
                    case .island: island
                    case .lyrics: lyrics
                    case .appearance: appearance
                    case .general: general
                    }
                }.formStyle(.grouped)
            }
        }
        .frame(minWidth: 780, minHeight: 480)
        .tint(.blue)
        .onAppear { login.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in login.refresh() }
    }
    @ViewBuilder private var island: some View {
        Section {
            Toggle("Mostrar isla dinámica", isOn: $model.panelEnabled)
            Picker("Pantalla", selection: $model.screenID) {
                Text("Automática (preferir pantalla con notch)").tag("")
                ForEach(model.screens) { screen in Text(screen.name).tag(screen.id) }
                if !model.screenID.isEmpty && !model.screens.contains(where: { $0.id == model.screenID }) {
                    Text("Pantalla desconectada · usando automática").tag(model.screenID)
                }
            }
        }
        Section("Letras de la isla") {
            Toggle("Mostrar letras", isOn: $model.lyricsEnabled)
            Toggle("Usar el color de la carátula", isOn: $model.coverLyricsColor)
            Toggle("Letra completa al desplegar el notch", isOn: $model.expandedLyrics)
            Toggle("Dos frases también en modo compacto", isOn: $model.twoLines)
            Text("La letra completa se desplaza con la canción. Pulsa cualquier frase para saltar a ese momento. Sin esta opción verás la frase actual y la siguiente.").font(.caption).foregroundStyle(.secondary)
            LabeledContent("Ancho compacto · \(Int(model.width)) pt") { Slider(value: $model.width, in: 320...780) }
        }
        Section("Comportamiento") {
            Toggle("Mantener notch abierto", isOn: $model.pinned)
            Toggle("Animación al cambiar de canción", isOn: $model.songAnimation)
            Toggle("Abrir al pasar el cursor", isOn: $model.openOnHover)
            Text("Si desactivas el hover, pulsa el panel para abrirlo y la flecha superior para cerrarlo.").font(.caption).foregroundStyle(.secondary)
            Toggle("Ocultar en pantalla completa", isOn: $model.hideFullScreen)
            Toggle("Ocultar cuando no hay reproducción", isOn: $model.hidePaused)
            Toggle("Toque háptico al entrar", isOn: $model.hapticsEnabled)
            if model.hapticsEnabled {
                Picker("Tipo de toque", selection: $model.hapticStyle) {
                    Text("Suave").tag("soft")
                    Text("Marcado").tag("marked")
                    Text("Doble toque").tag("double")
                }
                Text("Doble toque emite dos pulsos separados por 80 ms. La fuerza final la controla macOS.").font(.caption).foregroundStyle(.secondary)
            }
        }

    }
    @ViewBuilder private var lyrics: some View {
        Section("Karaoke") {
            Toggle("Ocultar texto con caracteres chinos (han)", isOn: $model.filterHanLyrics)
            Text("Filtra traducciones y créditos añadidos. Desactívalo para escuchar canciones cuyo texto original use estos caracteres.").font(.caption).foregroundStyle(.secondary)
            Toggle("Relleno progresivo de las letras", isOn: $model.karaokeEnabled)
            Text(model.wordStatus).font(.caption).foregroundStyle(.secondary)
            LabeledContent("Sincronía · \(model.offset, specifier: "%.1f") s") { Slider(value: $model.offset, in: -10...10, step: 0.1) }.disabled(model.track == nil || model.demo)
            Button("Restablecer sincronía de esta canción") { model.offset = 0 }.disabled(model.track == nil || model.demo)
            Text("Ajuste guardado solo para esta canción. Si la letra llega tarde, aumenta el ajuste.").font(.caption).foregroundStyle(.secondary)
        }
        Section("Letra de la canción") {
            Button("Elegir otra letra…") { model.showLyricChoices?() }.disabled(model.track == nil || model.demo)
            Button("Abrir letra completa") { model.showLyrics?() }
            Button("Importar letra .lrc o .yaml…") { model.importLRC() }
            LyricsDiagnosticsView(model: model)
            Text(model.message).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }

    }
    @ViewBuilder private var appearance: some View {
        Section("Dimensiones") {
            LabeledContent("Ancho compacto · \(Int(model.width)) pt") { Slider(value: $model.width, in: 320...780) }
            LabeledContent("Altura mínima · \(Int(model.compactHeight)) pt") { Slider(value: $model.compactHeight, in: 28...64, step: 1) }
            LabeledContent("Altura de letra completa · \(Int(model.expandedHeight)) pt") { Slider(value: $model.expandedHeight, in: 280...640, step: 10) }
            LabeledContent("Texto · \(Int(model.fontSize)) pt") { Slider(value: $model.fontSize, in: 12...28) }
            Text("Las frases adicionales aumentan la altura necesaria.").font(.caption).foregroundStyle(.secondary)
        }
        Section("Color y carátula") {
            Toggle("Letras con color de la carátula", isOn: $model.coverLyricsColor)
            Text("Desactivado: letras blancas. Si no hay carátula disponible, se usa blanco.").font(.caption).foregroundStyle(.secondary)
            LabeledContent("Color de controles") { Slider(value: $model.accent, in: 0...1).tint(model.tint) }
            Toggle("Carátula difuminada de fondo", isOn: $model.artworkEnabled)
            LabeledContent("Intensidad de carátula") { Slider(value: $model.artworkOpacity, in: 0.1...0.65) }.disabled(!model.artworkEnabled)
        }
    }
    @ViewBuilder private var general: some View {
        Section("Inicio y atajos") {
            Toggle("Abrir al iniciar sesión", isOn: Binding(get: { login.enabled }, set: { login.setEnabled($0) }))
            Text(login.status).font(.caption).foregroundStyle(.secondary)
            Picker("Fijar / cerrar notch", selection: $model.shortcut) {
                Text("⌘ ⇧ L").tag("cmdShiftL")
                Text("⌘ ⌥ L").tag("cmdOptionL")
                Text("⌃ ⌥ L").tag("ctrlOptionL")
                Text("Desactivado").tag("off")
            }
            Text("Escape cierra el notch fijado. El atajo no requiere acceso de Accesibilidad.").font(.caption).foregroundStyle(.secondary)
            if !model.shortcutStatus.isEmpty { Text(model.shortcutStatus).font(.caption).foregroundStyle(.orange) }
        }
        Section("Reproducción") {
            Picker("Reproductor", selection: $model.preferred) {
                Text("Automático").tag("Auto"); Text("Spotify").tag("Spotify"); Text("Apple Music").tag("Music")
            }
            Toggle("Compensar transiciones de Spotify", isOn: $model.compensateSpotifyTransitions)
            if model.compensateSpotifyTransitions {
                Slider(value: $model.spotifyTransitionDelay, in: 0...2, step: 0.1) {
                    Text("Retraso de transición · \(String(format: "%.1f", model.spotifyTransitionDelay)) s")
                }
                Text("Se aplica al pasar automáticamente a otra canción. Se aprende cuando Spotify corrige su posición al pausar, y puedes ajustarlo aquí. No cambia Crossfade ni interrumpe la música.").font(.caption).foregroundStyle(.secondary)
            }
            Text(model.connectionStatus).font(.caption).foregroundStyle(.secondary)
            if !model.networkAvailable { Text("Sin conexión de red · se conserva la letra disponible").font(.caption).foregroundStyle(.secondary) }
            Button(model.demo ? "Terminar demostración" : "Probar demostración") { model.toggleDemo() }
        }
        Section("Datos") {
            Text("Las búsquedas envían título, artista y duración a NetEase, QQ Music, Kugou, lrc.red y LRCLIB; el ID de Spotify se consulta en el repositorio público AMLL. Las letras se guardan en este Mac. Spotify facilita la URL de la carátula, que se descarga de su proveedor de imágenes.").font(.callout).fixedSize(horizontal: false, vertical: true)
        }
        Section {
            Text("Lyrical Notch · \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")").foregroundStyle(.secondary)
            Text("Para cerrar la app, usa el icono de onda en la barra de menús → Salir.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
