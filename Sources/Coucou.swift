import AppKit
import ScreenCaptureKit

// MARK: - Coucou awareness

/// Finds how far right Coucou's expanded panel reaches, by looking at the pixels of its window
/// just below the menu bar. Coucou keeps one fixed-size window, so its frame alone doesn't tell.
enum CoucouWatcher {
    static let bundleID = "fr.louisraille.NotchBuddy"

    static var isInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }

    static var isRunning: Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundleID }
    }

    /// Right edge of the expanded panel in screen x, or nil when collapsed, not running or not permitted.
    static func expandedRightEdge(menuBarHeight: CGFloat) async -> CGFloat? {
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

        let config = SCStreamConfiguration()
        config.width = Int(window.frame.width)
        config.height = Int(window.frame.height)
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

        let row = Int((menuBarHeight + 24) * CGFloat(image.height) / window.frame.height)
        guard row < image.height, let x = rightmostOpaque(image, row: row) else { return nil }
        return window.frame.minX + CGFloat(x) * window.frame.width / CGFloat(image.width)
    }

    private static func rightmostOpaque(_ image: CGImage, row: Int) -> Int? {
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
