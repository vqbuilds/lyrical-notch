import AppKit
import SwiftUI
import CoreImage

struct ScreenChoice: Identifiable { var id: String; var name: String }
func shouldShowPanel(enabled: Bool, hidePaused: Bool, playing: Bool, hideFullScreen: Bool, fullScreen: Bool) -> Bool {
    enabled && !(hidePaused && !playing) && !(hideFullScreen && fullScreen)
}
func readableCoverColor(_ image: NSImage) -> Color {
    guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return .white }
    let input = CIImage(cgImage: cg)
    let average = input.applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: input.extent)])
    var pixel = [UInt8](repeating: 0, count: 4)
    CIContext(options: [.workingColorSpace: NSNull()]).render(average, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
    let values = pixel.prefix(3).map { Double($0) / 255 }
    let averageColor = NSColor(srgbRed: values[0], green: values[1], blue: values[2], alpha: 1)
    var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 1
    averageColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
    return Color(hue: Double(hue), saturation: min(0.7, Double(saturation) * 0.85), brightness: 0.96)
}
