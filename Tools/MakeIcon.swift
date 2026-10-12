// Renders Resources/AppIcon.icns from the same mascot the island uses.
// Run: Tools/make_icon.sh
import AppKit
import SwiftUI

struct IconView: View {
    var body: some View {
        let squircle = RoundedRectangle(cornerRadius: 185, style: .continuous)
        ZStack {
            squircle
                .fill(LinearGradient(colors: [Color(red: 0.12, green: 0.13, blue: 0.16), Color(red: 0.03, green: 0.035, blue: 0.045)],
                                     startPoint: .top, endPoint: .bottom))
            RadialGradient(colors: [telegramBlue.opacity(0.55), telegramBlue.opacity(0.08), .clear],
                           center: UnitPoint(x: 0.5, y: 0.78), startRadius: 0, endRadius: 430)
                .clipShape(squircle)
            // The notch the app lives next to.
            IslandShape(flare: 16, radius: 40)
                .fill(.black)
                .frame(width: 270, height: 74)
                .frame(maxHeight: .infinity, alignment: .top)
                .clipShape(squircle)
            Blob(mood: .excited, look: CGSize(width: 0, height: -0.6), size: 440)
                .offset(x: -14, y: 70)
            squircle.strokeBorder(.white.opacity(0.10), lineWidth: 4)
        }
        .frame(width: 824, height: 824)
        .shadow(color: .black.opacity(0.4), radius: 24, y: 14)
        .frame(width: 1024, height: 1024)
    }
}

MainActor.assumeIsolated {
    let dir = URL(fileURLWithPath: CommandLine.arguments[1])
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let renderer = ImageRenderer(content: IconView())
    renderer.scale = 1
    guard let master = renderer.nsImage else { fatalError("render failed") }

    for (size, scales) in [(16, [1, 2]), (32, [1, 2]), (128, [1, 2]), (256, [1, 2]), (512, [1, 2])] {
        for scale in scales {
            let px = size * scale
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                                       samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                       colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            NSGraphicsContext.current?.imageInterpolation = .high
            master.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
            NSGraphicsContext.restoreGraphicsState()
            let name = scale == 1 ? "icon_\(size)x\(size).png" : "icon_\(size)x\(size)@2x.png"
            try! rep.representation(using: .png, properties: [:])!.write(to: dir.appendingPathComponent(name))
        }
    }
}
