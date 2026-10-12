import SwiftUI

/// Look of the app: the classic blue, or the Halloween pumpkin.
enum Theme {
    static let blue = Color(red: 0.17, green: 0.65, blue: 0.93)
    static let pumpkin = Color(red: 1.0, green: 0.55, blue: 0.1)
    static let stem = Color(red: 0.27, green: 0.45, blue: 0.18)

    /// Set by the app from Settings (nil = automatic: October 20 through November 5).
    static var override: Bool?

    static var isHalloween: Bool { override ?? inSeason() }

    static func inSeason(_ date: Date = Date()) -> Bool {
        let c = Calendar.current.dateComponents([.month, .day], from: date)
        return (c.month == 10 && (c.day ?? 0) >= 20) || (c.month == 11 && (c.day ?? 99) <= 5)
    }
}

/// The accent color of the current theme.
var accent: Color { Theme.isHalloween ? Theme.pumpkin : Theme.blue }

/// A lighter shade of the accent, for gradients and glints.
var accentLight: Color {
    Theme.isHalloween ? Color(red: 1, green: 0.76, blue: 0.38) : Color(red: 0.36, green: 0.8, blue: 1)
}

// MARK: - Shapes

/// Flat top that flares into the screen edge (like the notch), rounded bottom.
struct IslandShape: Shape {
    var flare: CGFloat = 8
    var radius: CGFloat
    var animatableData: CGFloat {
        get { radius }
        set { radius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height, f = flare
        let r = max(0, min(radius, h - f, (w - 2 * f) / 2))
        var p = Path()
        p.move(to: .zero)
        p.addQuadCurve(to: CGPoint(x: f, y: f), control: CGPoint(x: f, y: 0))
        p.addLine(to: CGPoint(x: f, y: h - r))
        p.addArc(tangent1End: CGPoint(x: f, y: h), tangent2End: CGPoint(x: f + r, y: h), radius: r)
        p.addLine(to: CGPoint(x: w - f - r, y: h))
        p.addArc(tangent1End: CGPoint(x: w - f, y: h), tangent2End: CGPoint(x: w - f, y: h - r), radius: r)
        p.addLine(to: CGPoint(x: w - f, y: f))
        p.addQuadCurve(to: CGPoint(x: w, y: 0), control: CGPoint(x: w - f, y: 0))
        p.closeSubpath()
        return p
    }
}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// A carved pumpkin grin with two teeth.
struct JaggedGrin: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        p.move(to: CGPoint(x: 0, y: 0))
        p.addQuadCurve(to: CGPoint(x: w, y: 0), control: CGPoint(x: w / 2, y: h * 0.5))
        p.addQuadCurve(to: CGPoint(x: w * 0.5, y: h), control: CGPoint(x: w * 0.85, y: h))
        p.addQuadCurve(to: CGPoint(x: 0, y: 0), control: CGPoint(x: w * 0.15, y: h))
        // Two teeth hanging from the top edge (cut out with even-odd fill).
        let edge = { (x: CGFloat) in x * (1 - x) * h }
        for x: CGFloat in [0.3, 0.56] {
            p.move(to: CGPoint(x: w * x, y: edge(x)))
            p.addLine(to: CGPoint(x: w * (x + 0.14), y: edge(x + 0.14)))
            p.addLine(to: CGPoint(x: w * (x + 0.07), y: h * 0.62))
            p.closeSubpath()
        }
        return p
    }
}

struct ArcShape: Shape {
    var up = true
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: up ? rect.maxY : rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: up ? rect.maxY : rect.minY),
                       control: CGPoint(x: rect.midX, y: up ? rect.minY - rect.height : rect.maxY + rect.height))
        return p
    }
}

// MARK: - Mascot

enum Mood { case idle, excited, eating, happy, sad }

struct Blob: View {
    var mood: Mood
    var look: CGSize
    var size: CGFloat
    @State private var blink = false

    private var tint: Color { mood == .sad ? Color(red: 0.94, green: 0.42, blue: 0.45) : accent }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: mood != .eating)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let squash = mood == .eating ? 0.045 * sin(t * 18) : 0
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.4, style: .continuous)
                    .fill(tint.gradient)
                    .overlay(
                        RoundedRectangle(cornerRadius: size * 0.4, style: .continuous)
                            .fill(LinearGradient(colors: [.white.opacity(0.3), .clear], startPoint: .top, endPoint: .center))
                    )
                if Theme.isHalloween { pumpkinRibs }
                face(t).offset(x: look.width * size * 0.1, y: look.height * size * 0.06)
            }
            .frame(width: size, height: size * 0.86)
            .overlay(alignment: .top) { if Theme.isHalloween { pumpkinStem } }
            .scaleEffect(x: 1 + squash, y: 1 - squash, anchor: .bottom)
        }
        .overlay(alignment: .bottomTrailing) { badge.offset(x: size * 0.14, y: size * 0.1) }
        .rotationEffect(.degrees(Double(look.width) * 5))
        .task { await blinkLoop() }
    }

    private func face(_ t: Double) -> some View {
        VStack(spacing: size * 0.05) {
            HStack(spacing: size * 0.2) { eye; eye }
            mouth(t).frame(height: size * 0.14)
        }
        .offset(y: size * 0.02)
    }

    @ViewBuilder private var eye: some View {
        switch mood {
        case .happy:
            ArcShape(up: true)
                .stroke(.black, style: StrokeStyle(lineWidth: size * 0.055, lineCap: .round))
                .frame(width: size * 0.15, height: size * 0.06)
                .frame(height: size * 0.17)
        case .sad:
            Capsule().fill(.black).frame(width: size * 0.13, height: size * 0.07).frame(height: size * 0.17)
        default:
            let big = mood == .excited
            if Theme.isHalloween {
                // Jack-o'-lantern eyes.
                Triangle().fill(.black)
                    .frame(width: size * (big ? 0.17 : 0.14), height: size * (big ? 0.15 : 0.12) * (blink ? 0.15 : 1))
                    .frame(height: size * 0.2)
            } else {
                Capsule().fill(.black)
                    .frame(width: size * (big ? 0.15 : 0.12), height: size * (big ? 0.2 : 0.16) * (blink ? 0.12 : 1))
                    .frame(height: size * 0.2)
            }
        }
    }

    @ViewBuilder private func mouth(_ t: Double) -> some View {
        switch mood {
        case .excited where Theme.isHalloween, .idle where Theme.isHalloween:
            JaggedGrin().fill(.black.opacity(0.9), style: FillStyle(eoFill: true)).frame(width: size * 0.36, height: size * 0.11)
        case .eating where Theme.isHalloween:
            JaggedGrin().fill(.black.opacity(0.9), style: FillStyle(eoFill: true))
                .frame(width: size * 0.34, height: size * (0.05 + 0.08 * abs(sin(t * 9))))
        case .excited:
            Ellipse().fill(.black.opacity(0.85)).frame(width: size * 0.17, height: size * 0.12)
        case .eating:
            Ellipse().fill(.black.opacity(0.85)).frame(width: size * 0.19, height: size * (0.03 + 0.1 * abs(sin(t * 9))))
        case .happy:
            ArcShape(up: false).stroke(.black, style: StrokeStyle(lineWidth: size * 0.05, lineCap: .round))
                .frame(width: size * 0.16, height: size * 0.04)
        case .sad:
            ArcShape(up: true).stroke(.black, style: StrokeStyle(lineWidth: size * 0.05, lineCap: .round))
                .frame(width: size * 0.14, height: size * 0.035)
        case .idle:
            Color.clear.frame(width: 1, height: 1)
        }
    }

    /// Pumpkin segments: darker curved bands down the body.
    private var pumpkinRibs: some View {
        ZStack {
            ForEach([-0.36, 0.36], id: \.self) { x in
                Ellipse()
                    .stroke(Color(red: 0.62, green: 0.27, blue: 0).opacity(0.22), lineWidth: size * 0.025)
                    .frame(width: size * 0.5, height: size * 1.05)
                    .offset(x: size * x)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: size * 0.4, style: .continuous))
    }

    private var pumpkinStem: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: size * 0.03)
                .fill(Theme.stem.gradient)
                .frame(width: size * 0.1, height: size * 0.17)
                .rotationEffect(.degrees(12), anchor: .bottom)
            Ellipse()
                .fill(Theme.stem.opacity(0.9))
                .frame(width: size * 0.16, height: size * 0.08)
                .rotationEffect(.degrees(-25))
                .offset(x: size * 0.07, y: -size * 0.06)
        }
        .offset(y: -size * 0.13)
    }

    private var badge: some View {
        let symbol = mood == .happy ? "checkmark" : mood == .sad ? "exclamationmark" : "paperplane.fill"
        let color: Color = mood == .happy ? Color(red: 0.2, green: 0.75, blue: 0.4) : mood == .sad ? .red : accent
        return Circle()
            .fill(.white)
            .frame(width: size * 0.42, height: size * 0.42)
            .overlay(Image(systemName: symbol).font(.system(size: size * 0.2, weight: .bold)).foregroundStyle(color))
            .shadow(color: .black.opacity(0.3), radius: 1.5, y: 1)
            .contentTransition(.symbolEffect(.replace))
    }

    private func blinkLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(Double.random(in: 2.2...4.8)))
            guard mood == .idle || mood == .eating else { continue }
            withAnimation(.easeIn(duration: 0.07)) { blink = true }
            try? await Task.sleep(for: .milliseconds(110))
            withAnimation(.easeOut(duration: 0.1)) { blink = false }
        }
    }
}

/// A few bats fluttering around — Halloween decoration. `t` comes from the caller's TimelineView.
struct Bats: View {
    var t: Double
    var count: Int

    var body: some View {
        GeometryReader { g in
            ForEach(0..<count, id: \.self) { i in
                let speed = 0.09 + Double(i) * 0.035
                let x = (t * speed + Double(i) * 0.37).truncatingRemainder(dividingBy: 1)
                let y = 0.3 + 0.18 * sin(t * 1.3 + Double(i) * 2) + Double(i) * 0.15
                BatShape()
                    .fill(accent.opacity(0.7))
                    .frame(width: 16 + CGFloat(i) * 3, height: 8 + CGFloat(i) * 1.5)
                    .scaleEffect(x: 1, y: 0.55 + 0.45 * abs(sin(t * 11 + Double(i))))  // wing flaps
                    .shadow(color: accent.opacity(0.5), radius: 3)
                    .position(x: g.size.width * x, y: g.size.height * y)
            }
        }
        .allowsHitTesting(false)
    }
}

/// Bat silhouette: pointed ears, scalloped wings.
struct BatShape: Shape {
    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * w, y: r.minY + y * h) }
        var p = Path()
        p.move(to: pt(0, 0.15))
        p.addQuadCurve(to: pt(0.4, 0.38), control: pt(0.22, 0.05))
        p.addLine(to: pt(0.44, 0.12))   // left ear
        p.addLine(to: pt(0.5, 0.3))
        p.addLine(to: pt(0.56, 0.12))   // right ear
        p.addLine(to: pt(0.6, 0.38))
        p.addQuadCurve(to: pt(1, 0.15), control: pt(0.78, 0.05))
        // Scalloped trailing edge of the right wing, the body, then the left wing.
        p.addQuadCurve(to: pt(0.82, 0.6), control: pt(0.95, 0.5))
        p.addQuadCurve(to: pt(0.66, 0.62), control: pt(0.76, 0.45))
        p.addQuadCurve(to: pt(0.5, 1.0), control: pt(0.6, 0.95))
        p.addQuadCurve(to: pt(0.34, 0.62), control: pt(0.4, 0.95))
        p.addQuadCurve(to: pt(0.18, 0.6), control: pt(0.24, 0.45))
        p.addQuadCurve(to: pt(0, 0.15), control: pt(0.05, 0.5))
        p.closeSubpath()
        return p
    }
}
