# Changelog

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
