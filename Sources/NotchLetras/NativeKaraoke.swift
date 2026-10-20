import AppKit
import SwiftUI
import CoreText

// Core Text layout is cached per line/width. Only the clipping changes while singing;
// no SwiftUI view tree or attributed-string layout is rebuilt on each frame.
struct NativeKaraoke: NSViewRepresentable {
    @ObservedObject var model: Model
    let line: LyricLine
    let fontSize: Double
    let centered: Bool
    let visible: Bool
    func makeNSView(context: Context) -> KaraokeDrawingView { KaraokeDrawingView() }
    func updateNSView(_ view: KaraokeDrawingView, context: Context) {
        view.configure(line: line, size: fontSize, color: NSColor(model.lyricColor), centered: centered,
                       running: visible && model.track?.playing == true, clock: { [weak model] in
                           guard let model else { return 0 }
                           return model.playbackPosition(at: Date()) + model.offset
                       })
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: KaraokeDrawingView, context: Context) -> CGSize? {
        nsView.fittingSize(width: proposal.width ?? 450)
    }
    static func dismantleNSView(_ view: KaraokeDrawingView, coordinator: ()) { view.stop() }
}

final class KaraokeDrawingView: NSView {
    private var lyric: LyricLine?
    private var fontSize = 17.0
    private var ink = NSColor.white
    private var centered = false
    private var running = false
    private var clock: () -> Double = { 0 }
    private var framesetter: CTFramesetter?
    private var textFrame: CTFrame?
    private var cachedBounds = CGRect.zero
    private var timer: Timer?
    private var observer: NSObjectProtocol?
    private var signature = -Double.infinity
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil } // Lyrics buttons own pointer interaction.

    func configure(line: LyricLine, size: Double, color: NSColor, centered: Bool, running: Bool, clock: @escaping () -> Double) {
        let changed = lyric != line || fontSize != size || ink != color || self.centered != centered
        lyric = line; fontSize = size; ink = color; self.centered = centered; self.running = running; self.clock = clock
        if changed {
            let paragraph = NSMutableParagraphStyle(); paragraph.alignment = centered ? .center : .left
            let base = NSFont.systemFont(ofSize: CGFloat(size), weight: .semibold)
            let font = base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: CGFloat(size)) } ?? base
            let attr = NSAttributedString(string: line.text, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph])
            framesetter = CTFramesetterCreateWithAttributedString(attr)
            textFrame = nil; cachedBounds = .zero; invalidateIntrinsicContentSize()
            setAccessibilityElement(true); setAccessibilityRole(.staticText); setAccessibilityLabel(line.text)
        }
        needsDisplay = true
        schedule()
    }
    func fittingSize(width: CGFloat) -> CGSize {
        guard let framesetter else { return CGSize(width: width, height: CGFloat(fontSize + 6)) }
        let measured = CTFramesetterSuggestFrameSizeWithConstraints(framesetter, CFRange(location: 0, length: 0), nil,
            CGSize(width: max(1, width), height: 10000), nil)
        return CGSize(width: width, height: ceil(measured.height) + 6)
    }
    override var intrinsicContentSize: NSSize { fittingSize(width: bounds.width > 0 ? bounds.width : 450) }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        if let window {
            observer = NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main) { [weak self] _ in self?.schedule() }
        }
        schedule()
    }
    func stop() { timer?.invalidate(); timer = nil }
    private func schedule() {
        stop()
        guard running, let window, window.isVisible, window.occlusionState.contains(.visible), let lyric else { return }
        let now = clock()
        let active = lyric.words.contains { now >= $0.start && now < ($0.end ?? $0.start) }
        let next = lyric.words.first { $0.start > now }?.start
        guard active || next != nil else { needsDisplay = true; return }
        let delay = active ? 1.0/30 : max(1.0/30, (next ?? now) - now)
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            guard let self else { return }
            let time = self.clock()
            if time != self.signature { self.signature = time; self.needsDisplay = true }
            self.schedule()
        }
        timer.tolerance = active ? 0.003 : 0.02
        RunLoop.main.add(timer, forMode: .common); self.timer = timer
    }
    override func draw(_ dirtyRect: NSRect) {
        guard let lyric, let framesetter, let context = NSGraphicsContext.current?.cgContext else { return }
        if textFrame == nil || cachedBounds != bounds {
            cachedBounds = bounds
            textFrame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), CGPath(rect: bounds.insetBy(dx: 0, dy: 3), transform: nil), nil)
        }
        guard let frame = textFrame else { return }
        context.saveGState(); defer { context.restoreGState() }
        context.textMatrix = .identity
        let time = clock()
        let textLines = CTFrameGetLines(frame) as! [CTLine]
        var origins = [CGPoint](repeating: .zero, count: textLines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
        // CTFrame line origins are relative to the path. Both passes must use
        // identical absolute baselines; mixing CTFrameDraw with CTLineDraw shifts ink.
        let pathOrigin = CTFrameGetPath(frame).boundingBoxOfPath.origin
        for index in origins.indices {
            origins[index].x += pathOrigin.x; origins[index].y += pathOrigin.y
            context.setAlpha(0.34)
            context.textMatrix = .identity; context.textPosition = origins[index]
            CTLineDraw(textLines[index], context)
        }
        context.setAlpha(1)
        let rawText = lyric.words.map(\.text).joined()
        var offset = -String(rawText.prefix(while: { $0.isWhitespace })).utf16.count
        for word in lyric.words {
            let startOffset = max(0, offset)
            offset += word.text.utf16.count
            let endOffset = min(lyric.text.utf16.count, offset)
            guard endOffset > startOffset else { continue }
            let wordRange = NSRange(location: startOffset, length: endOffset - startOffset)
            let progress = CGFloat(fillProgress(at: time, start: word.start, end: word.end ?? word.start))
            guard progress > 0 else { continue }
            for (index, textLine) in textLines.enumerated() {
                let range = CTLineGetStringRange(textLine)
                let intersection = NSIntersectionRange(wordRange, NSRange(location: range.location, length: range.length))
                guard intersection.length > 0 else { continue }
                let start = CTLineGetOffsetForStringIndex(textLine, intersection.location, nil)
                let end = CTLineGetOffsetForStringIndex(textLine, NSMaxRange(intersection), nil)
                var ascent: CGFloat = 0, descent: CGFloat = 0
                CTLineGetTypographicBounds(textLine, &ascent, &descent, nil)
                let x = origins[index].x + min(start, end)
                let width = abs(end-start)
                let left = start <= end ? x : x + width*(1-progress)
                let rect = CGRect(x: left, y: origins[index].y-descent-2, width: width*progress, height: ascent+descent+4)
                context.saveGState(); context.clip(to: rect)
                context.textMatrix = .identity; context.textPosition = origins[index]; CTLineDraw(textLine, context)
                context.restoreGState()
            }
        }
    }
    deinit { timer?.invalidate(); if let observer { NotificationCenter.default.removeObserver(observer) } }
}

@MainActor func verifyNativeInkAlignment() {
    let text = "Original words for a rendering check"
    let tokens = ["Original ", "words ", "for ", "a ", "rendering ", "check"]
    let line = LyricLine(time: 0, text: text, words: tokens.enumerated().map { WordTiming(text: $0.element, start: Double($0.offset), end: Double($0.offset)+0.8) })
    for centered in [false, true] {
        for width in [CGFloat(180), CGFloat(500)] {
            let view = KaraokeDrawingView(frame: NSRect(x: 0, y: 0, width: width, height: 100))
            func raster(_ time: Double) -> [UInt8] {
                let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width), pixelsHigh: 100, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: Int(width)*4, bitsPerPixel: 32)!
                let graphics = NSGraphicsContext(bitmapImageRep: bitmap)!
                NSGraphicsContext.saveGraphicsState(); defer { NSGraphicsContext.restoreGraphicsState() }
                NSGraphicsContext.current = graphics
                graphics.cgContext.clear(view.bounds)
                view.configure(line: line, size: 22, color: .white, centered: centered, running: false, clock: { time })
                view.draw(view.bounds)
                return Array(UnsafeBufferPointer(start: bitmap.bitmapData!, count: bitmap.bytesPerRow*100))
            }
            let base = raster(-1)
            precondition(stride(from: 3, to: base.count, by: 4).contains { base[$0] > 30 })
            for time in [1.3, 99.0] {
                let sung = raster(time)
                let outsideBase = stride(from: 3, to: base.count, by: 4).filter { sung[$0] > 40 && base[$0] == 0 }.count
                precondition(outsideBase == 0, "Karaoke highlight must share the base text pixel footprint")
            }
        }
    }
    print("Native rendering checks passed: identical base/highlight baselines, centered and left aligned, single and wrapped lines.")
}
