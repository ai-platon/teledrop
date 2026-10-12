import CoreGraphics

/// Where the island goes and how wide it may get. Pure, so it can be tested for every screen size.
enum Layout {
    static let fullWidth: CGFloat = 380
    static let minWidth: CGFloat = 270
    static let margin: CGFloat = 8

    struct Placement: Equatable {
        /// Left edge of the island, in screen points.
        var left: CGFloat
        /// The widest the island may get there (narrow screens, or next to an open Coucou).
        var maxWidth: CGFloat
    }

    /// Next to something (the notch, Coucou's pills or panel) that ends at `anchor`.
    /// Shrinks to fit the room on the right; on very narrow screens it slides left instead.
    static func beside(anchor: CGFloat, screenMaxX: CGFloat) -> Placement {
        let room = screenMaxX - margin - anchor
        if room >= fullWidth { return Placement(left: anchor, maxWidth: fullWidth) }
        if room >= minWidth { return Placement(left: anchor, maxWidth: room) }
        return Placement(left: screenMaxX - margin - minWidth, maxWidth: minWidth)
    }

    /// Hanging from the middle of the screen (no Coucou): limited only by the screen itself.
    static func centered(screenWidth: CGFloat) -> CGFloat {
        min(fullWidth, screenWidth - 2 * margin)
    }
}
