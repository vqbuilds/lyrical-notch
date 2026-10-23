# Validación 0.5.5

## Revisión 0.5.5 · 23 de octubre de 2026

- Retirada completa de la compensación de Crossfade de 0.5.4; el reloj vuelve al comportamiento de 0.5.3.
- Eliminados el aprendizaje automático, los controles de transición y el registro de diagnóstico añadidos con ese cambio.
- Nombre, identidad, datos de usuario y recuperación tras reposo conservados.

## Revisión 0.5.3 · 20 de octubre de 2026

- Cambio de nombre a Lyrical Notch: interfaz, ejecutable, proyecto Swift y paquetes de distribución.
- Identidad de preferencias y carpeta de letras heredadas conservadas para mantener ajustes y selecciones.
- App instalada y comprobada: ventana «Lyrical Notch · Ajustes», versión 0.5.3, inicio automático activo y ajustes de anchura/color conservados. El resumen SHA-256 de las preferencias coincide antes y después del cambio.

## Revisión 0.5.2 · 20 de octubre de 2026

- Reproducida antes del cambio una regresión de reactivación sin aviso previo de reposo: el reloj avanzaba desde el ancla antigua antes de recibir posición nueva. La prueba ahora pasa.
- Regresiones de reloj monotónico, espera de muestra nueva, respuesta retenida, reproductor temporalmente no disponible, ajuste de hora y salto largo sin aviso de reposo.
- Comprobación en vivo con Spotify: los manejadores de despertar del sistema, pantalla y sesión, y despertar de pantalla sin reposo previo, recuperaron muestras nuevas. Avisos simulados solo en este proceso; sin pausar ni cambiar la reproducción.
- Regresión de consumo: una muestra normal de posición no publica cambios globales de la interfaz.
- Karaoke y controles inspeccionados en la app instalada con «Ten Tonne Skeleton» de Royal Blood.
- Crossfade, Automix y desfases por canción conservados.
- El reposo físico y la sincronía contra audio tras cerrar/abrir la tapa necesitan validación en uso real; no equivalen a la simulación de notificaciones.

## Revisión 0.5.1 · 20 de octubre de 2026

- Regresión del karaoke: el texto base y el resaltado comparten ahora las mismas posiciones de dibujo. Comprobación por píxeles con resaltado parcial y completo, alineación izquierda y centrada, y una o varias líneas.

- Comprobación visual en la app instalada con Spotify y «Crying Lightning»: frase partida en dos líneas y relleno parcial sin duplicación ni desplazamiento.

## Revisión 0.5.0 · 20 de octubre de 2026

- Renderer Core Text con composición guardada por línea/ancho; repintado acotado a las palabras activas.
- Pruebas de regresión: avanzar dentro de una frase no emite cambios del modelo; cruzar a otra frase sí. Reintentos limitados a tres por canción.
- Filtro de caracteres han configurable, detección conservadora de frases pegadas y reparación de espacios solo con referencia idéntica. Tests verifican que no cambian los tiempos.
- Prueba real del mismo flujo automático con álbum deliberadamente distinto: «Mañana No Existe» de Sexy Zebras recupera 46 líneas por frase de LRCLIB; Hysteria recupera karaoke de Kugou y Amsterdam de NetEase.
- Búsqueda completa: regresión de letra por frase disponible mientras sigue la búsqueda; «sin letra» solo después de terminar. La consulta usa la misma ruta para automático y selector.
- Selector «Fuente» probado en el notch: QQ Music sin versión conserva la actual; lrc.red válida se aplica y persiste; vuelta a automático comprobada, sin detener Spotify.
- Clic de una línea y de la frase resaltada comprobados con el escenario de prueba: la posición salta a 0:10 conservando los controles.
- Pantallas del karaoke nativo compacto y expandido inspeccionadas con texto de prueba original, resaltado parcial y controles visibles.
- Medición controlada antes/después: ver [ENERGY.md](ENERGY.md). No son medidas de autonomía ni vatios.

Las comprobaciones antiguas siguientes conservan sus límites; no implican haber repetido físicamente todas las pruebas en esta versión.


## Fuentes añadidas en 0.4.2 · 20 de octubre de 2026

Consultas independientes desde el ejecutable nativo, sin usar la caché:

| Fuente | Canción | Resultado |
|---|---|---|
| QQ Music | Muse — Hysteria | 129 segmentos con tiempos; cobertura 100 % |
| QQ Music | Arctic Monkeys — Do I Wanna Know? | 384 segmentos con tiempos; cobertura 95 % |
| QQ Music | Nothing But Thieves — Amsterdam | 330 segmentos con tiempos; cobertura 100 % |
| Kugou | Muse — Hysteria | 129 segmentos con tiempos; cobertura 100 % |
| Kugou | Do I Wanna Know? / Amsterdam | Sin candidatos; se mantienen las demás fuentes |

Cobertura significa proporción de líneas con tiempos por palabra aceptados, no una medida de exactitud auditiva. No se ha realizado una escucha completa de estas grabaciones en esta pasada.

Fixtures originales para QRC y KRC: decodificación, tiempos absolutos frente a relativos, pausas vocales, entradas inválidas y comprobación de cobertura. Los textos descargados no se incluyen en el paquete.


## Comprobaciones añadidas en 0.4.1

- Compilación de producción y todos los grupos de autopruebas superados.
- Ajuste rápido: dirección, pasos de 0,1 s, persistencia por canción, límites ±10 s, rechazo de NaN y ausencia de saltos de audio.
- Diagnóstico de fuente y tipo de tiempos; búsqueda bloqueada para elecciones manuales.
- En la app instalada: Antes cambia 0,0 a +0,1 s y Después devuelve 0,0; posición pausada conservada en 158,57 s.
- Popover real muestra lrc.red/TTML y 180 palabras. Búsqueda real mantiene la letra visible mientras carga y termina con NetEase/YRC y 151 palabras.
- Distribución revisada visualmente a 420 pt. La comprobación de altura mínima de 280 pt descrita abajo corresponde a 0.4.0.

Las comprobaciones físicas pendientes siguen pendientes: no se ha suspendido el Mac, desconectado su red ni probado el atajo con teclado físico desde otra app.

## Base validada en 0.4.0

Validación local: 19 de octubre de 2026, macOS 27.0.1, Apple Silicon, Swift 6.4. El mínimo de compilación es macOS 14; no se ha ejecutado físicamente en macOS 14 ni en Intel.

## Automatizada, sin reproductor ni servicios externos

`./build.sh` ejecuta los siguientes grupos en la compilación de producción. Las pruebas de preferencias usan un dominio temporal de UserDefaults y las de letras una carpeta temporal que se elimina al terminar.

- LRC y etiquetas enriquecidas: fracciones, etiquetas múltiples, offsets, texto malformado.
- Lyricsfile YAML, YRC y TTML: palabras reales, pausas vocales y rechazo de frases disfrazadas de palabras.
- Identidad: artista, estudio/directo y diferencias de duración.
- Reloj: interpolación, pausa congelada, salto y límite de duración.
- Saltos: diferencia entre tiempo de audio y tiempo de letra, ajuste por canción, negativos, NaN y duración inválida.
- Preferencias: dos canciones con desfases distintos, canción nueva sin herencia y límites.
- Ciclo de reposo: congelación, ausencia de avance al despertar antes de recibir muestra y nueva posición del reproductor.
- Desconexión: elimina pista/letras antiguas; reconexión carga posición, desfase y selección guardada.
- Persistencia de elección de letra, rechazo de tiempos no finitos y protección frente a una respuesta automática tardía.
- Pérdida de red: conserva la letra cargada.
- Hover: margen de salida, reentrada y salidas transitorias.

## Comprobación en la app instalada

- Inicio automático activado: Service Management devuelve estado habilitado.
- Panel fijado visible mientras Spotify está pausado; carátula, letra completa, tiempos y controles visibles.
- Barra de progreso: un incremento desde 2:38 mueve Spotify a 3:07, manteniendo la pausa.
- Atajo ⌘⇧L dentro de la app: cambia entre fijado y cerrado; Escape libera la fijación y cierra.
- Altura mínima de 280 pt comprobada con lista, progreso y controles visibles. Restaurada a 420 pt tras la prueba.
- Búsqueda alternativa real para «Shadow of the Day»: 22 resultados de fuentes con tiempos por palabra y por frase; selección manual aplicada y vuelta a automático comprobadas.
- Cierre real de Spotify: desaparecen las letras antiguas y se deshabilitan acciones que necesitan una canción. Al reabrir Spotify se recuperan la pista pausada, posición y tiempos por palabra.
- En la versión anterior se verificaron saltos de frase hacia delante y atrás con «Do I Wanna Know?»; las comprobaciones de regresión conservan esa lógica.

## Límites explícitos

El reposo y la red se prueban mediante las mismas transiciones del modelo que usan las notificaciones del sistema; no se ha forzado una suspensión física ni desconectado la red del usuario. La prueba de inicio automático verifica registro habilitado, sin cerrar la sesión de macOS. La entrega física del atajo desde otra aplicación requiere una comprobación con teclado real; el registro global y la ruta local se incluyen en la app. La intensidad háptica necesita prueba física.

Apple Music todavía no tiene una prueba completa de integración en esta pasada. Su carátula no está implementada. No se ha repetido una campaña de cambios rápidos ni probado anuncios, fuera del alcance pedido. La cobertura de karaoke depende de cada grabación y del estado de los proveedores.

La app y el archivo limpio de fuentes se compilan localmente. La revisión 0.4.2 ya superó el workflow de GitHub; cada actualización ejecuta de nuevo su compilación y pruebas. La firma es local ad hoc; no hay notarización ni firma Developer ID.
