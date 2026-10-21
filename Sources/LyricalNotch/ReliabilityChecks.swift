import Foundation
import Combine

@MainActor func verifyAppReliability() {
    let suiteName = "NotchLetras.Checks.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let preferences = SongPreferences(defaults: defaults)
    preferences.setOffset(1.4, for: "song-A")
    preferences.setOffset(-0.6, for: "song-B")
    precondition(preferences.offset(for: "song-A") == 1.4)
    precondition(preferences.offset(for: "song-B") == -0.6)
    precondition(preferences.offset(for: "new-song") == 0)
    preferences.setOffset(.nan, for: "song-A")
    precondition(preferences.offset(for: "song-A") == 1.4)
    preferences.setOffset(30, for: "song-C")
    precondition(preferences.offset(for: "song-C") == 10)

    let model = Model()
    model.songPreferences = preferences
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("NotchLetras-check-\(UUID().uuidString)")
    model.cache = folder
    try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    var song = Track(title: "Reliability fixture", artist: "Original test data", album: "", duration: 120, position: 12, playing: true, player: "Spotify")
    preferences.setOffset(1.4, for: song.key)
    model.acceptPlayback(song, error: nil)
    precondition(model.offset == 1.4 && model.position == 12)
    model.adjustLyrics(by: 0.1)
    precondition(model.offset == 1.5 && preferences.offset(for: song.key) == 1.5)
    precondition(model.position == 12) // Adjusting lyrics must not seek the audio.
    model.adjustLyrics(by: -0.1)
    precondition(model.offset == 1.4)
    model.adjustLyrics(by: .nan)
    precondition(model.offset == 1.4)
    model.offset = 10; model.adjustLyrics(by: 0.1)
    precondition(model.offset == 10)
    model.offset = -10; model.adjustLyrics(by: -0.1)
    precondition(model.offset == -10)
    model.offset = 1.4
    precondition(model.lyricsTimingLabel == "Sin letra")
    song.playing = false; song.position = 24
    model.acceptPlayback(song, error: nil)
    precondition(model.playbackPosition(at: model.sampledUptime + 50) == 24)
    song.playing = true
    model.acceptPlayback(song, error: nil)
    model.prepareForSleep()
    let sleepPosition = model.position
    precondition(model.playbackPosition(at: model.sampledUptime + 3600) == sleepPosition)
    model.resumePlayback(reconnect: false)
    precondition(model.playbackPosition(at: model.sampledUptime + 3600) == sleepPosition)
    song.position = 73
    model.acceptPlayback(song, error: nil)
    precondition(model.position == 73 && !model.suspended)

    let quietClock = Model()
    quietClock.acceptPlayback(song, error: nil)
    var clockPublications = 0
    let clockObservation = quietClock.objectWillChange.sink { clockPublications += 1 }
    quietClock.acceptPlayback(song, error: nil)
    precondition(clockPublications == 0) // Normal position samples must not invalidate the whole UI.
    clockObservation.cancel()

    let correctedSleep = Model()
    correctedSleep.track = song; correctedSleep.sampledPosition = 40
    correctedSleep.sampledUptime = ProcessInfo.processInfo.systemUptime - 1
    correctedSleep.spotifyTransitionCorrection = 1
    correctedSleep.prepareForSleep()
    precondition(abs(correctedSleep.position - 40) < 0.05) // Do not add elapsed time twice while clearing a correction.

    // Screen/session wake can arrive without a preceding system-sleep notification.
    let screenWake = Model()
    screenWake.track = song
    screenWake.sampledPosition = 30
    screenWake.resumePlayback(reconnect: false)
    let waitingPosition = screenWake.playbackPosition(at: screenWake.sampledUptime + 1)
    guard waitingPosition == 30 else {
        print("Wake regression: lyrics advance from an old anchor before a fresh player sample (expected 30, received \(waitingPosition)).")
        exit(1)
    }

    precondition(screenWake.awaitingPlaybackSample)
    let wakeRevision = screenWake.clockRevision
    let wakeEpoch = screenWake.playbackEpoch
    // A response captured before a suspended queue resumed cannot unlock the clock.
    precondition(!screenWake.acceptPlayback(song, error: nil, capturedAt: ProcessInfo.processInfo.systemUptime - 30))
    precondition(screenWake.awaitingPlaybackSample && screenWake.sampledPosition == 30)
    let originalKey = screenWake.track?.key
    screenWake.acceptPlayback(nil, error: "Player still waking")
    precondition(screenWake.track?.key == originalKey && screenWake.awaitingPlaybackSample)
    var wakeSong = song
    wakeSong.position = 42
    screenWake.acceptPlayback(wakeSong, error: nil)
    precondition(!screenWake.awaitingPlaybackSample && screenWake.position == 42)
    precondition(screenWake.playbackPosition(at: screenWake.sampledUptime + 0.5) == 42.5)
    precondition(screenWake.clockRevision > wakeRevision && screenWake.playbackEpoch == wakeEpoch)
    // Ordinary ticks leave the epoch alone; clock corrections or missed wake events re-anchor.
    let tickDate = Date(timeIntervalSinceReferenceDate: 100)
    precondition(!screenWake.recoverAfterClockGap(date: tickDate, uptime: 100, reconnect: false))
    precondition(!screenWake.recoverAfterClockGap(date: tickDate.addingTimeInterval(0.15), uptime: 100.15, reconnect: false))
    precondition(screenWake.recoverAfterClockGap(date: tickDate.addingTimeInterval(1.30), uptime: 100.30, reconnect: false))
    precondition(screenWake.awaitingPlaybackSample && screenWake.playbackPosition(at: 9000) == 42)
    screenWake.acceptPlayback(wakeSong, error: nil)
    precondition(screenWake.recoverAfterClockGap(date: tickDate.addingTimeInterval(3601.3), uptime: 100.3, reconnect: false))
    precondition(screenWake.awaitingPlaybackSample && screenWake.playbackPosition(at: 9000) == 42)
    screenWake.acceptPlayback(wakeSong, error: nil)
    precondition(screenWake.recoverAfterClockGap(date: tickDate.addingTimeInterval(3611.3), uptime: 110.3, reconnect: false))
    screenWake.acceptPlayback(wakeSong, error: nil)
    precondition(!screenWake.awaitingPlaybackSample && screenWake.position == 42)
    precondition(screenWake.offset == 0) // Recovery never invents a per-song timing correction.
    print("Wake regression checks passed: display-only wake, stale reply rejection, temporary player unavailability, fresh-anchor recovery, wall-clock jumps and missed sleep notifications.")

    let choice = LyricChoice(id: "fixture", source: "Local test", title: song.title, artist: song.artist, duration: 120,
        lines: [LyricLine(time: 1, text: "Original fixture one"), LyricLine(time: 5, text: "Original fixture two")], plain: "Original fixture one\nOriginal fixture two")
    model.selectLyrics(choice)
    precondition(model.usingSelectedLyrics && model.lines.count == 2)
    model.apply(LyricResponse(syncedLyrics: "[00:01]Late automatic response", plainLyrics: nil, instrumental: false))
    precondition(model.lines.first?.text == "Original fixture one")
    model.lines = []
    precondition(model.restoreSelectedLyrics(for: song))
    precondition(model.lines.count == 2 && model.wordSource == "Local test")
    var invalid = choice
    invalid.lines = [LyricLine(time: .infinity, text: "Invalid")]
    precondition(!invalid.isUsable)
    model.acceptPlayback(nil, error: "Disconnected fixture")
    precondition(model.track == nil && model.lines.isEmpty && model.plain.isEmpty && model.offset == 0)
    precondition(model.message == "Disconnected fixture")
    model.acceptPlayback(song, error: nil)
    precondition(model.offset == 1.4 && model.position == 73)
    precondition(model.restoreSelectedLyrics(for: song))
    precondition(model.lyricsSourceLabel == "Local test" && model.lyricsTimingLabel == "Por frase")
    model.refreshLyrics()
    precondition(!model.refreshingLyrics && model.usingSelectedLyrics)
    model.lines = [LyricLine(time: 0, text: "First original line"), LyricLine(time: 80, text: "Second original line")]
    model.panelVisible = true
    model.position = 73
    var publications = 0
    let observation = model.objectWillChange.sink { publications += 1 }
    model.position = 74; model.position = 75
    precondition(publications == 0) // Advancing inside a phrase never invalidates the whole UI.
    model.position = 81
    precondition(publications == 1 && model.currentIndex == 1)
    observation.cancel()
    model.panelVisible = false
    var hiddenPublications = 0
    let hiddenObservation = model.objectWillChange.sink { hiddenPublications += 1 }
    model.position = 20
    precondition(hiddenPublications == 0)
    hiddenObservation.cancel()
    model.networkAvailable = false
    model.scheduleLyricsRetry()
    precondition(model.lines.count == 2) // Existing lyrics survive network loss.
    model.usingSelectedLyrics = false; model.lyricRetryCount = 0
    for _ in 0..<10 { model.scheduleLyricsRetry() }
    precondition(model.lyricRetryCount == 3 && model.retryAfter == .distantFuture)
    precondition(playbackTimeLabel(0) == "0:00" && playbackTimeLabel(125) == "2:05")
    precondition(playbackTimeLabel(.nan) == "0:00")
    precondition(lyricSeekPosition(time: 40, offset: 1.4, duration: 120) == 38.6)
    model.demo = true
    model.seek(toPosition: 40)
    precondition(model.position == 40) // Progress ignores lyric offset.
    let lookup = Model()
    lookup.track = song; lookup.lyricsLoading = true; lookup.message = "Buscando letras en todas las fuentes…"
    let phrase = WordLyricsResult(source: "LRCLIB", title: song.title, artist: song.artist, duration: song.duration, lines: choice.lines)
    lookup.mergeLyricsCandidate(phrase)
    precondition(lookup.lyricsLoading && lookup.lines.count == 2 && !lookup.message.contains("Sin letra"))
    lookup.finishLyricsSearch()
    precondition(!lookup.lyricsLoading && lookup.wordSource == "LRCLIB" && lookup.lines.count == 2)
    lookup.lines = []; lookup.plain = ""; lookup.lyricsLoading = true
    precondition(!lookup.message.contains("Sin letra"))
    lookup.finishLyricsSearch()
    precondition(lookup.message == "Sin letra disponible en las fuentes consultadas")
    model.request?.cancel(); model.wordRequest?.cancel(); model.songNoticeTask?.cancel()
    print("Reliability checks passed: per-song persistence, pause/resume, sleep/wake resampling, disconnect/reconnect, offline lyric retention, saved selection and progress seeking.")
}
