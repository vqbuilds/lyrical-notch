import SwiftUI

@MainActor final class ScrubState: ObservableObject {
    @Published var dragging = false
    @Published var value = 0.0
}
func playbackTimeLabel(_ time: Double) -> String {
    let seconds = Int(max(0, time.isFinite ? time : 0))
    return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
}
struct PlaybackProgressView: View {
    @ObservedObject var model: Model
    @StateObject private var scrub = ScrubState()
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0, paused: model.track?.playing != true || !model.panelVisible || model.awaitingPlaybackSample || model.suspended)) { _ in
            let duration = max(1, model.track?.duration ?? 1)
            let current = min(duration, scrub.dragging ? scrub.value : model.playbackPosition())
            VStack(spacing: 0) {
                Slider(value: Binding(get: { current }, set: { scrub.value = $0 }), in: 0...duration, onEditingChanged: { editing in
                    if editing { scrub.value = current; scrub.dragging = true }
                    else { scrub.dragging = false; model.seek(toPosition: scrub.value) }
                })
                .tint(model.lyricColor)
                .disabled(model.track == nil || model.track?.duration ?? 0 <= 0)
                .accessibilityLabel("Posición de reproducción")
                HStack {
                    Text(playbackTimeLabel(current)); Spacer(); Text("−" + playbackTimeLabel(duration - current))
                }.font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
            }
            .onChange(of: model.track?.key) { _, _ in scrub.dragging = false }
        }
        .padding(.horizontal, 24).padding(.bottom, 8)
    }
}
