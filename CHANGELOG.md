# Changelog

## 0.5.3

- Rename the app and project to Lyrical Notch, including windows, executable, build artifacts and documentation.
- Preserve the existing bundle identifier and lyric storage so settings, timing offsets and saved lyrics remain available.
- Show the installed app version in Settings.

## 0.5.2

- Re-anchor playback after system, screen and session wake; freeze karaoke until a fresh player position arrives.
- Use a monotonic playback clock and recover from missed wake notifications or wall-clock jumps.
- Discard delayed playback replies and invalidate pending seeks across sleep; briefly resample while reconnecting.
- Add regression checks for display-only wake and a read-only live player wake-handler check.

## 0.5.1

- Fix vertically displaced karaoke highlighting by drawing base text and sung text with identical Core Text baselines.
- Add pixel regression checks for partial and complete highlighting, centered and left-aligned, including wrapped lyrics.

## 0.5.0

- Exhaust all five timing providers plus LRCLIB, retain phrase lyrics while looking for karaoke, and report absence only after all lookups complete.
- Shared LRCLIB lookup ignores album edition spelling and also supports strict recording-matched search fallback.

- Core Text karaoke with cached layout and animation only while visible and singing.
- Phrase-boundary UI updates, adaptive player polling and bounded lyric retries.
- Source picker directly inside the expanded notch, with per-song saved choice.
- Han text filtering and conservative glued-word checks; exact-reference whitespace repair preserves timing.
- Reproducible before/after CPU measurements, quality and invalidation regression checks.

## 0.4.2

- QQ Music (QRC) y Kugou (KRC) en la búsqueda automática y en el selector de letras.
- Decodificación nativa de tiempos por palabra, con validación de grabación y límites de tamaño.
- Pruebas de formatos, licencia del decodificador y aviso de fuentes externas actualizados.

## 0.4.1

- Diagnóstico de fuente y tipo de sincronización accesible desde el notch.
- Ajuste Antes / Después de 0,1 s, guardado por canción, sin mover el audio.
- Búsqueda manual con estado visible y protección de la selección guardada.
- Documentación de proveedores y regresiones de los ajustes de sincronía.

## 0.4.0

- Pin the notch open; Escape closes a pinned panel. Configurable global shortcut.
- Seekable playback progress, elapsed time and remaining time.
- Per-song timing correction, saved independently.
- Search and preview alternate lyrics; remember an explicit choice or local import.
- Optional launch at login via macOS Service Management.
- Configurable expanded height, limited to the available display area.
- Freeze the clock on sleep, refresh player position on wake, bound Apple Event timeouts and discard stale playback reads.
- Retry lyric services after temporary failures or restored connectivity. Keep loaded lyrics offline.
- First-launch settings only; subsequent launches stay in the menu bar.
- Offline regression checks, build workflow and clean source packaging.

## 0.3.0

- Real word timing from YRC/TTML and enriched local lyrics, without estimated word sweeps.
- Album tint, faded artwork, haptics, animated hover panel, transport controls.
- Larger clickable cover, embedded full lyrics and seeking by lyric line.
