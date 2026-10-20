# Third-party notices

The app's source code is independent. No code, artwork, branding or executable from Dynamic Lyrics is included.

## Yams

[Yams](https://github.com/jpsim/Yams), version 6.2.2, is distributed under the MIT License. The exact revision is pinned in `Package.resolved`; its full license is copied to `Contents/Resources/Yams-LICENSE.txt` when packaging the app. Yams contains LibYAML; its upstream MIT notice is preserved in `docs/LibYAML-LICENSE.txt` and copied to the app. Source: https://github.com/yaml/libyaml/blob/master/License.

## Lyric services

NetEase, QQ Music, Kugou, LRCLIB, lrc.red and the AMLL TTML database are external sources queried at runtime. Lyrics and album artwork remain subject to their respective rights; the MIT license for this app does not license that material. No downloaded lyrics or artwork are included in the source package. Provider availability can change. The NetEase, QQ Music and Kugou interfaces are unofficial.

Spotify, Apple Music and macOS are names of their respective owners. This project is not affiliated with those services or with Dynamic Lyrics.

### Provider transparency and failures

- LRCLIB: https://github.com/tranxuanthang/lrclib — server code under MIT; the API supplies line timings and text.
- AMLL TTML DB: https://github.com/amll-dev/amll-ttml-db — community repository declaring CC0-1.0, with word timings where available.
- NetEase Cloud Music: commercial service accessed through an unofficial interface. Compatibility and continued availability are not guaranteed.
- lrc.red: https://lrc.red/docs — public API; no blanket open license for its service or lyric data is asserted here.

These project licenses do not establish rights to redistribute every song's lyrics. The app queries providers at runtime, keeps local caches, preserves loaded lyrics on network failure and supports manual LRC/YAML imports. Word highlighting requires actual timestamps; line-only results do not simulate karaoke. A manually chosen lyric is retained until the user changes it.

## QQMusicDecoder

The native QRC decoder uses protocol tables and byte ordering from [WXRIW/QQMusicDecoder](https://github.com/WXRIW/QQMusicDecoder), MIT, Copyright (c) 2023 WXRIW. The full notice is included in `docs/QQMusicDecoder-LICENSE.txt` and bundled in app resources. The Swift implementation includes bounded decompression and input validation. It does not use CommonCrypto's standard 3DES, which is incompatible with QRC's variant.

QQ Music (QRC) and Kugou (KRC) are queried directly over HTTPS without user account credentials. These commercial services are not open-source lyric databases. LDDC was consulted for protocol interoperability; no LDDC code is included in the app.
