# Notch Letras

Una app nativa de macOS que lleva las letras y controles de Spotify o Música al notch. Código propio en Swift y SwiftUI, independiente de Dynamic Lyrics.

## Funciones

- Notch compacto con expansión animada por hover o clic.
- Karaoke con tiempos reales por palabra cuando hay datos disponibles; sin barridos aproximados.
- Letra completa dentro del notch o en una ventana independiente. Pulsa una frase para saltar a ella.
- Carátula que abre el reproductor, fondo difuminado y color de letra inspirado en el álbum.
- Reproducción, pausa, anterior, siguiente y barra de progreso con salto al soltar.
- Chincheta para mantenerlo abierto. Escape cierra el notch fijado.
- Atajo global configurable: ⌘⇧L por defecto; también ⌘⌥L o ⌃⌥L.
- Ajuste de sincronía independiente por canción, letras alternativas con vista previa e importación local.
- Ancho, alturas, tipografía, pantalla, háptica y visibilidad configurables.
- Inicio de sesión opcional y recuperación del reproductor después del reposo.

No incluye control de volumen, traducción ni reproducción desde navegador.

## Requisitos e instalación

macOS 14 o posterior. El karaoke usa un renderer nativo de Core Text con tiempos por palabra. Spotify o Música deben ejecutarse en este Mac.

Para compilar necesitas Swift 6 o posterior y las herramientas de desarrollo de Apple:

```sh
./build.sh
```

La app se genera en `build/Notch Letras.app`. Copia la app a una carpeta estable, como `~/Applications`, antes de activar «Abrir al iniciar sesión». Abre la app y acepta el acceso de Automatización al reproductor. El icono de onda de la barra de menús permite abrir Ajustes, elegir letras y salir. Cerrar una ventana no cierra la app.

La compilación usa una firma local ad hoc. No es una distribución notarizada y no incluye un certificado Developer ID; la distribución pública firmada debe prepararse por separado. Tras recompilar, macOS puede pedir de nuevo permiso de Automatización. El inicio automático usa el registro de macOS y muestra su estado real, incluido cualquier error o aprobación pendiente.

## Uso

Al pasar el cursor se abre el notch. Fíjalo con la chincheta o con el atajo para mover el cursor fuera sin cerrarlo. Escape libera el modo fijado y lo cierra; vuelve a entrar con el cursor para abrirlo de nuevo. El atajo se puede cambiar o desactivar en Ajustes → General y se avisa si está ocupado. El atajo usa Carbon y no pide permisos de Accesibilidad.

El botón de lista alterna dos frases y letra completa. «Siguiendo» permite pausar el seguimiento para explorar; «Seguir canción» vuelve a la frase actual. En macOS 15+ los gestos de desplazamiento también pausan el seguimiento. La barra de progreso usa tiempo de audio; pulsar una frase descuenta el desfase de letra configurado para esa canción. Los saltos no cambian una reproducción pausada a activa.

En Ajustes → Letras y karaoke puedes corregir la sincronía de la canción o elegir otra letra. La búsqueda alternativa permite editar título/artista, revisar fuente, tipo de tiempos, duración y un fragmento antes de seleccionar. Las diferencias de duración se señalan para evitar confundir estudio, directo o remix. La selección se recuerda localmente; puedes volver al modo automático. Los archivos importados también se recuerdan.

## Datos y disponibilidad

Se consultan NetEase, QQ Music, Kugou, lrc.red y LRCLIB con título, artista y duración; AMLL se consulta por ID de Spotify. Spotify facilita la URL HTTPS de la carátula. La selección automática valida identidad y duración donde se proporcionan. Los proveedores no garantizan cobertura de todas las canciones; NetEase, QQ Music y Kugou usan interfaces no oficiales. La selección manual es explícita y puede corresponder a una versión distinta.

Las letras se guardan solo en `~/Library/Application Support/NotchLetras`. Ajustes y desfases se guardan en preferencias locales de macOS. La carátula se conserva en memoria. No hay cuentas propias, analítica, reconocimiento de audio, credenciales incrustadas ni servicios de pago.

Con letra por frase solo se resalta la frase. Sin tiempos se muestra texto sin saltos. Las letras cargadas siguen disponibles sin red; los fallos se reintentan con espera creciente de 20 a 120 segundos, y se reintenta al restablecerse la conexión. Una elección manual no se sustituye automáticamente. La háptica necesita un trackpad compatible; macOS controla su fuerza física.

Apple Music: se lee reproducción, posición y metadatos; todavía no se obtiene su carátula. Ocultar en pantalla completa usa el estado global de presentación y puede tener limitaciones con varias pantallas.

## Desarrollo

`./build.sh` compila, empaqueta, firma localmente y ejecuta las comprobaciones de parsers, tiempos reales, límites, pausas, reposo, desconexión, preferencias y selección. Detalles y límites de validación en [docs/VALIDATION.md](docs/VALIDATION.md). El workflow de GitHub está preparado, pero debe ejecutarse en GitHub después de publicar.

La dependencia Yams 6.2.2 está fijada en `Package.resolved`. Su licencia se incorpora a la app. Véanse [LICENSE](LICENSE) y [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

```sh
./scripts/package-source.sh
```

Genera `dist/notch-letras-0.5.2-source.tar.gz` con una lista explícita de archivos publicables. No incluye investigación local, binarios de terceros, letras descargadas ni preferencias. La carpeta `research/` es solo local y se excluye también de Git.

Modos de desarrollo: `--self-test` ejecuta comprobaciones sin UI; `--preview-hover` abre una demo sintética desplegada; `--preview-player` mantiene el panel desplegado con el reproductor real; `--preview-cycle` alterna la expansión de la demo. La demo no reproduce audio ni demuestra precisión de una canción real. `--check-wake-recovery` comprueba los manejadores de despertar con un reproductor real abierto, simulando avisos solo dentro de este proceso, sin dormir el Mac ni cambiar la reproducción.

### Diagnóstico y ajuste rápido

En el notch desplegado, pulsa el indicador «Por palabra / Por frase» para ver la fuente, la cobertura y volver a buscar. «Antes» muestra la letra 0,1 s antes; «Después», 0,1 s después. Pulsa el valor para restablecerlo. El ajuste se guarda por canción y no cambia la posición del audio. Las letras elegidas manualmente se cambian desde «Elegir otra…».

### Fuentes y legibilidad

En el notch desplegado, «Fuente» permite elegir QQ Music, Kugou, NetEase, AMLL, lrc.red o LRCLIB sin abrir Ajustes. Se conserva la letra actual mientras se busca; la elección válida se recuerda para esa canción. «Automática» vuelve al modo habitual. No todas las fuentes tienen todas las grabaciones.

Por defecto se excluyen líneas con caracteres han, incluidos créditos o traducciones añadidos. Se puede desactivar en Letras y karaoke para canciones originales que los necesiten. Se detectan líneas latinas largas sin espacios. Solo se recuperan espacios cuando otra letra tiene exactamente los mismos caracteres y las separaciones respetan los segmentos temporales; las versiones sospechosas se descartan. Este filtro es conservador y no garantiza detectar todos los errores.

### Consumo

El texto del karaoke se compone una vez por línea y ancho. Solo se actualiza el recorte de color mientras se canta, hasta 30 fps; pausa, ocultación y descansos vocales detienen esos repintados. El reloj no publica cambios de toda la interfaz en cada paso. Las búsquedas automáticas tienen un máximo de tres reintentos por canción. Medidas y límites: [docs/ENERGY.md](docs/ENERGY.md).

La búsqueda automática comprueba las cinco fuentes de karaoke y LRCLIB en paralelo. Muestra cuanto antes una letra por frase y solo la sustituye por una versión con mejores tiempos. El aviso de ausencia se muestra al finalizar todas las consultas. La coincidencia usa canción, artista y duración; no exige el nombre exacto del álbum. Las consultas de LRCLIB para texto visible y referencias de espacios se comparten para evitar descargas duplicadas. Las letras válidas ya guardadas se reutilizan.
