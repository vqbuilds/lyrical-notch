# Consumo y revisión de rendimiento · 0.5.0

Mediciones locales el 20 de octubre de 2026, Apple Silicon, macOS 27.0.1. CPU expresada como porcentaje de **un núcleo**. No son vatios, porcentaje total de la máquina ni una estimación de autonomía.

## Hallazgo inicial

La app instalada consumía una media de 44,07 % de CPU y 181 MB RSS durante una muestra de 20 segundos con música real y notch compacto. Una muestra de pila de cinco segundos señaló composición/dibujo de texto en SwiftUI y repintado del karaoke. Son observaciones de esa sesión; no una comparación controlada entre canciones.

## Comparación controlada

Se compiló el commit anterior `ecd04ec` en una carpeta temporal, añadiendo únicamente el mismo modo de prueba. Se ejecutaron antes y después con:

- Texto original de prueba, 40 líneas, ocho segmentos temporales por línea.
- Mismos tiempos, tamaño de panel, pantalla y preferencias. Una sola app de prueba a la vez.
- Tres segundos de arranque fuera de la muestra; 20 segundos de medición por condición.
- CPU calculada mediante diferencia de tiempo de CPU del proceso / tiempo real. RSS al final.
- Spotify continuó reproduciendo independientemente: los textos de prueba no controlan el audio.

| Condición | Anterior CPU | Nueva CPU | RSS anterior / nueva |
|---|---:|---:|---:|
| Karaoke compacto | 12,24 % | 2,55 % | 75,91 / 75,83 MB |
| Karaoke expandido | 17,64 % | 4,70 % | 93,22 / 89,77 MB |
| Expandido en pausa, nueva versión | — | 0,15 % | — / 88,14 MB |
| Panel oculto, nueva versión | — | 0,10 % | — / 88,05 MB |

El compacto baja aproximadamente 79 % y el expandido 73 % en estas muestras. La memoria resulta parecida en la comparación controlada. Las canciones, la carátula, la longitud de las letras y el desplazamiento pueden cambiar las cifras. Una muestra corta no sustituye una prueba de autonomía de varias horas.

## Cambios

- Core Text compone el texto una vez por línea, ancho, fuente y color. Los fotogramas solo actualizan recortes de color.
- Hasta 30 fps durante palabras cantadas. El temporizador visual espera al próximo inicio durante pausas vocales; se cancela al pausar, ocultar, cerrar o desmontar la vista.
- Los avances del reloj dentro de una frase no publican cambios de toda la interfaz. Las ventanas ocultas no reciben avances de frase hasta volver a mostrarse.
- Progreso visual a 1 Hz, con interacción de arrastre inmediata; reloj de karaoke independiente.
- Consulta del reproductor aproximadamente cada 1,05 s reproduciendo, 2 s en pausa y 5 s sin pista. Notificaciones de Spotify y de inicio/cierre de apps adelantan la consulta.
- Temporizador de hover con tolerancia y sin recalcular marcos de ventana en cada paso. Se invalida durante el reposo.
- Máximo de tres reintentos automáticos por canción; selección manual protegida. Letras elegidas de cada proveedor se reutilizan durante la sesión de esa canción.
- Referencias de texto ya guardadas se reutilizan al comprobar espacios; descargas y descompresión tienen límites de tamaño.

## Repetir

`python3 scripts/measure-cpu.py PID --seconds 20` lee CPU/RSS sin modificar preferencias ni reproducción. Para un escenario determinista, el ejecutable admite `--preview-karaoke`, opcionalmente `--preview-pinned`, `--preview-paused` o `--preview-hidden`. Son escenarios de desarrollo, no letras incluidas de canciones comerciales.

La validación física de reposo, el consumo total GPU/WindowServer y una descarga completa de batería no se han medido en esta pasada. No se promete un número de horas extra de autonomía.
