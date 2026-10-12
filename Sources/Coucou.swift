import AppKit
import ScreenCaptureKit

// MARK: - Coucou awareness

/// Where Coucou currently ends on the right, so the island can sit next to it.
/// Coucou keeps one fixed-size window, so its frame alone doesn't tell; we look at its pixels.
enum CoucouWatcher {
    static let bundleID = "fr.louisraille.NotchBuddy"

    struct Edges: Equatable {
        /// Right edge of the collapsed pills in the menu bar.
        var collapsed: CGFloat?
        /// Right edge of the expanded panel below the menu bar.
        var expanded: CGFloat?
    }

    static var isInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }

    static var isRunning: Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundleID }
    }

    /// nil when Coucou isn't running or its window can't be read (no Screen Recording permission).
    static func edges(menuBarHeight: CGFloat) async -> Edges? {
        guard isRunning else { return nil }
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            log("screen capture unavailable: \(error.localizedDescription)")
            return nil
        }
        guard let window = content.windows
                .filter({ $0.owningApplication?.bundleIdentifier == bundleID })
                .max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height })
        else { return nil }

        // Only the strip around the menu bar matters: a tiny capture instead of the whole window.
        let stripHeight = min(window.frame.height, menuBarHeight + 32)
        let config = SCStreamConfiguration()
        config.sourceRect = CGRect(x: 0, y: 0, width: window.frame.width, height: stripHeight)
        config.width = Int(window.frame.width)
        config.height = Int(stripHeight)
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true
        let image: CGImage
        do {
            image = try await SCScreenshotManager.captureImage(
                contentFilter: SCContentFilter(desktopIndependentWindow: window), configuration: config)
        } catch {
            log("coucou capture failed: \(error.localizedDescription)")
            return nil
        }

        let scale = CGFloat(image.height) / stripHeight
        let toScreen = { (x: Int) in window.frame.minX + CGFloat(x) * window.frame.width / CGFloat(image.width) }
        let pillsRow = Int(menuBarHeight * 0.5 * scale)
        let panelRow = Int((menuBarHeight + 24) * scale)
        return Edges(collapsed: rightmostOpaque(image, row: pillsRow).map(toScreen),
                     expanded: rightmostOpaque(image, row: panelRow).map(toScreen))
    }

    private static func rightmostOpaque(_ image: CGImage, row: Int) -> Int? {
        guard row >= 0, row < image.height else { return nil }
        let w = image.width
        var pixels = [UInt8](repeating: 0, count: w * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let ctx = CGContext(data: buffer.baseAddress, width: w, height: 1, bitsPerComponent: 8,
                                      bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            // Shift the image so that `row` (counted from the top) lands on the context's single line.
            ctx.draw(image, in: CGRect(x: 0, y: -CGFloat(image.height - 1 - row),
                                       width: CGFloat(w), height: CGFloat(image.height)))
            return true
        }
        guard drawn else { return nil }
        for x in stride(from: w - 1, through: 0, by: -1) where pixels[x * 4 + 3] > 200 { return x }
        return nil
    }
}
