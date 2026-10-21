import Foundation

// Spotify can keep reporting a position about one second ahead after an automatic
// crossfade. A pause corrects Spotify's own position. Keep that correction separate
// from lyric timestamps and per-song offsets; never pause or seek the player here.
struct SpotifyTransitionClock {
    struct Sample {
        var key: String
        var player: String
        var album: String = ""
        var duration: Double
        var position: Double
        var playing: Bool
        var uptime: TimeInterval
    }
    var learnedDelay: Double = 0
    private(set) var activeDelay: Double = 0
    private(set) var automaticTransition = false
    private var previous: Sample?
    private var suppressAutomaticUntil: TimeInterval = 0
    mutating func updateDelay(_ delay: Double) {
        learnedDelay = min(2, max(0, delay))
        if automaticTransition { activeDelay = learnedDelay }
    }
    mutating func manualAction(at uptime: TimeInterval) {
        reset(); suppressAutomaticUntil = uptime + 3
    }

    mutating func reset() {
        activeDelay = 0; automaticTransition = false; previous = nil
    }
    mutating func accept(_ sample: Sample, enabled: Bool) {
        defer { previous = sample }
        guard sample.player == "Spotify", sample.position.isFinite, sample.duration.isFinite else { reset(); return }
        guard let old = previous, old.player == "Spotify" else { activeDelay = 0; automaticTransition = false; return }
        let elapsed = max(0, sample.uptime - old.uptime)
        if old.key != sample.key {
            let remaining = old.duration - old.position - (old.playing ? elapsed : 0)
            // Near-end transitions only. Mid-track skips and app-issued controls are excluded.
            let sameAlbum = !old.album.isEmpty && old.album.caseInsensitiveCompare(sample.album) == .orderedSame
            automaticTransition = !sameAlbum && sample.uptime >= suppressAutomaticUntil && old.playing && sample.playing && old.duration > 30 &&
                remaining >= -1 && remaining <= 12 && sample.position < 12
            activeDelay = enabled && automaticTransition ? min(2, max(0, learnedDelay)) : 0
        } else if old.playing && !sample.playing {
            let correction = old.position + elapsed - sample.position
            if enabled && automaticTransition && elapsed < 3 && correction >= 0.35 && correction <= 2 {
                learnedDelay = (correction * 10).rounded() / 10
            }
            // Spotify's pause fixes its raw clock; retaining our delay would double-correct it.
            activeDelay = 0; automaticTransition = false
        } else if !old.playing && sample.playing {
            activeDelay = 0; automaticTransition = false
        } else if old.playing && sample.playing && elapsed < 3 && abs(sample.position - old.position - elapsed) > 0.5 {
            // A seek or Spotify's own clock correction supersedes the crossfade compensation.
            activeDelay = 0; automaticTransition = false
        }
        if !enabled { activeDelay = 0; automaticTransition = false }
    }
}

func verifySpotifyTransitionClock() {
    typealias Sample = SpotifyTransitionClock.Sample
    var clock = SpotifyTransitionClock(learnedDelay: 1)
    clock.accept(Sample(key: "outgoing", player: "Spotify", duration: 256, position: 252.873, playing: true, uptime: 100), enabled: true)
    clock.accept(Sample(key: "incoming", player: "Spotify", duration: 253, position: 0, playing: true, uptime: 100.635), enabled: true)
    precondition(clock.automaticTransition && clock.activeDelay == 1)
    clock.accept(Sample(key: "incoming", player: "Spotify", duration: 253, position: 14.543, playing: true, uptime: 115.292), enabled: true)
    // Recorded shape of the bug, using original fixture identities: Spotify moves
    // its own clock backwards on pause while our interpolation had followed it.
    clock.accept(Sample(key: "incoming", player: "Spotify", duration: 253, position: 14.620, playing: false, uptime: 116.327), enabled: true)
    precondition(clock.learnedDelay == 1 && clock.activeDelay == 0)
    clock.accept(Sample(key: "incoming", player: "Spotify", duration: 253, position: 14.956, playing: true, uptime: 117), enabled: true)
    precondition(clock.activeDelay == 0)
    clock.accept(Sample(key: "manual-skip", player: "Spotify", duration: 200, position: 0, playing: true, uptime: 118), enabled: true)
    precondition(!clock.automaticTransition && clock.activeDelay == 0)
    clock.accept(Sample(key: "manual-skip", player: "Spotify", duration: 200, position: 198, playing: true, uptime: 120), enabled: true)
    clock.accept(Sample(key: "next", player: "Spotify", duration: 200, position: 0, playing: true, uptime: 121), enabled: false)
    precondition(clock.activeDelay == 0)
    clock.reset()
    clock.accept(Sample(key: "music", player: "Music", duration: 200, position: 198, playing: true, uptime: 200), enabled: true)
    clock.accept(Sample(key: "music-next", player: "Music", duration: 200, position: 0, playing: true, uptime: 201), enabled: true)
    precondition(clock.activeDelay == 0)
    clock.reset()
    clock.accept(Sample(key: "a", player: "Spotify", duration: 200, position: 198, playing: true, uptime: 300), enabled: true)
    clock.accept(Sample(key: "b", player: "Spotify", duration: 200, position: 0, playing: true, uptime: 301), enabled: true)
    precondition(clock.activeDelay == 1)
    clock.accept(Sample(key: "b", player: "Spotify", duration: 200, position: 20, playing: true, uptime: 302), enabled: true)
    precondition(clock.activeDelay == 0)
    clock.reset()
    clock.accept(Sample(key: "album-a", player: "Spotify", album: "Consecutive album", duration: 200, position: 198, playing: true, uptime: 390), enabled: true)
    clock.accept(Sample(key: "album-b", player: "Spotify", album: "Consecutive album", duration: 200, position: 0, playing: true, uptime: 391), enabled: true)
    precondition(clock.activeDelay == 0) // Spotify can keep consecutive album tracks gapless.
    clock.manualAction(at: 400)
    clock.accept(Sample(key: "a", player: "Spotify", duration: 200, position: 198, playing: true, uptime: 400.1), enabled: true)
    clock.accept(Sample(key: "b", player: "Spotify", duration: 200, position: 0, playing: true, uptime: 400.3), enabled: true)
    precondition(clock.activeDelay == 0) // App controls near the end must not look like crossfade.
    clock.reset()
    clock.accept(Sample(key: "a", player: "Spotify", duration: 200, position: 198, playing: true, uptime: 500), enabled: true)
    clock.accept(Sample(key: "b", player: "Spotify", duration: 200, position: 0, playing: true, uptime: 501), enabled: true)
    clock.updateDelay(0.8)
    precondition(clock.activeDelay == 0.8)
    print("Spotify transition checks passed: automatic crossfade compensation, pause calibration, no double correction, manual skips, seeks, disabled mode and Apple Music.")
}

// Replay an opt-in trace through the production transition clock without touching a player.
func replaySpotifyTransitions(_ path: String, delay: Double) throws {
    let text = try String(contentsOfFile: path, encoding: .utf8)
    let rows = text.split(separator: "\n").compactMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
    var durations: [String: Double] = [:]
    for row in rows where row["event"] as? String == "playerNotification" {
        if let id = row["Track ID"] as? String, let duration = row["Duration"] as? Double { durations[id.components(separatedBy: ":").last!] = duration / 1000 }
    }
    var clock = SpotifyTransitionClock(learnedDelay: delay)
    var previous: (uptime: Double, position: Double, playing: Bool, key: String, correction: Double)?
    var transitions = 0, correctedPauses = 0
    for row in rows where row["event"] as? String == "sample" {
        guard let uptime = row["uptime"] as? Double, let position = row["reported"] as? Double,
              let key = row["trackID"] as? String, let playing = row["playing"] as? Bool else { continue }
        let duration = durations[key] ?? (row["duration"] as? Double) ?? 0
        let sample = SpotifyTransitionClock.Sample(key: key, player: "Spotify", album: row["album"] as? String ?? "", duration: duration, position: position, playing: playing, uptime: uptime)
        clock.accept(sample, enabled: true)
        if let old = previous {
            if old.key != key && clock.activeDelay > 0 { transitions += 1 }
            if old.key == key && old.playing && !playing && old.correction > 0 {
                let rawJump = position - old.position - (uptime - old.uptime)
                let correctedJump = rawJump + old.correction
                print(String(format: "Recorded pause: raw discontinuity=%+.3fs compensated discontinuity=%+.3fs", rawJump, correctedJump))
                guard abs(correctedJump) < 0.2, clock.activeDelay == 0 else {
                    throw NSError(domain: "LyricalNotch.Replay", code: 1, userInfo: [NSLocalizedDescriptionKey: "Recorded transition compensation did not converge"])
                }
                correctedPauses += 1
            }
        }
        previous = (uptime, position, playing, key, clock.activeDelay)
    }
    guard transitions > 0, correctedPauses > 0 else { throw NSError(domain: "LyricalNotch.Replay", code: 2, userInfo: [NSLocalizedDescriptionKey: "Trace has no matching automatic transition and pause"] ) }
    print("Recorded transition replay passed: \(transitions) compensated transitions, \(correctedPauses) pause checks; no player commands issued.")
}
