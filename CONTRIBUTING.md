# Contributing

Use macOS 14+ with Swift 6 or newer and Apple's command line tools. Run `./build.sh` before proposing a change. The build runs offline regression checks against original synthetic fixtures; it does not need Spotify, credentials or network beyond resolving Yams the first time.

Keep UI text in Spanish for now. Preserve real word timestamps: never manufacture karaoke timing from line duration. New providers must validate recording identity, document data sent and gracefully handle unavailable services. Avoid adding secrets, downloaded lyrics, personal playback logs or third-party binaries to the repository.

For UI changes, verify hover and pinned modes, the smallest expanded height, pause/resume and seeking. For playback changes, test frozen pause/sleep clocks and stale responses. Update `docs/VALIDATION.md` with what was actually tested and any remaining limits.
