import SwiftUI

@MainActor final class LyricsFollowState: ObservableObject {
    @Published var following = true
}

private struct TrackLyricsScrolling: ViewModifier {
    @ObservedObject var state: LyricsFollowState
    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content.onScrollPhaseChange { _, phase in
                if phase == .tracking || phase == .interacting || phase == .decelerating { state.following = false }
            }
        } else { content }
    }
}

struct LyricsListView: View {
    @ObservedObject var model: Model
    let embedded: Bool
    @StateObject private var follow = LyricsFollowState()
    private var visible: Bool { embedded ? model.panelVisible : model.lyricsWindowVisible }
    var body: some View {
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(model.lines.isEmpty ? "Letra" : "Pulsa una frase para saltar")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        follow.following.toggle()
                        if follow.following { center(proxy) }
                    } label: {
                        Label(follow.following ? "Siguiendo" : "Seguir canción", systemImage: follow.following ? "location.fill" : "location")
                            .font(.system(size: 10))
                    }.help(follow.following ? "Pausar seguimiento para explorar la letra" : "Volver a la frase actual")
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: embedded ? 16 : 22) {
                        if model.lines.isEmpty {
                            Text(model.plain.isEmpty ? model.message : model.plain)
                                .foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        ForEach(Array(model.lines.enumerated()), id: \.offset) { index, line in
                            Button {
                                follow.following = true
                                model.seek(toLyricTime: line.time)
                                withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(index, anchor: .center) }
                            } label: {
                                Group {
                                    if index == model.currentIndex {
                                        AnimatedLyricLine(model: model, line: line,
                                            visible: embedded ? model.panelVisible : model.lyricsWindowVisible,
                                            size: embedded ? max(18, model.fontSize + 2) : 25)
                                    } else {
                                        Text(line.text.isEmpty ? "♪" : line.text)
                                            .foregroundStyle(model.lyricColor.opacity(index < (model.currentIndex ?? -1) ? 0.58 : 0.35))
                                    }
                                }
                                .font(.system(size: embedded ? max(18, model.fontSize + 2) : 25, weight: .semibold, design: .rounded))
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .id(index)
                            .accessibilityLabel(line.text.isEmpty ? "Pausa instrumental" : line.text)
                            .accessibilityHint("Saltar a esta frase")
                            .help("Saltar a \(Int(line.time) / 60):\(String(format: "%02d", Int(line.time) % 60))")
                        }
                    }
                    .padding(.vertical, embedded ? 65 : 90)
                    .padding(.horizontal, 4)
                }
                .modifier(TrackLyricsScrolling(state: follow))
                .onAppear { center(proxy) }
                .onChange(of: model.currentIndex) { _, _ in if follow.following && visible { center(proxy) } }
                .onChange(of: visible) { _, shown in if shown && follow.following { center(proxy) } }
                .onChange(of: model.lines) { _, _ in center(proxy) }
                .onChange(of: model.track?.key) { _, _ in follow.following = true; center(proxy) }
            }
        }
    }
    private func center(_ proxy: ScrollViewProxy) {
        guard let index = model.currentIndex ?? (model.lines.isEmpty ? nil : 0) else { return }
        withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(index, anchor: .center) }
    }
}
