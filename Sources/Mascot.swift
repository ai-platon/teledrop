import SwiftUI

let telegramBlue = Color(red: 0.17, green: 0.65, blue: 0.93)

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

    private var tint: Color { mood == .sad ? Color(red: 0.94, green: 0.42, blue: 0.45) : telegramBlue }

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
                face(t).offset(x: look.width * size * 0.1, y: look.height * size * 0.06)
            }
            .frame(width: size, height: size * 0.86)
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
            Capsule().fill(.black)
                .frame(width: size * (big ? 0.15 : 0.12), height: size * (big ? 0.2 : 0.16) * (blink ? 0.12 : 1))
                .frame(height: size * 0.2)
        }
    }

    @ViewBuilder private func mouth(_ t: Double) -> some View {
        switch mood {
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

    private var badge: some View {
        let symbol = mood == .happy ? "checkmark" : mood == .sad ? "exclamationmark" : "paperplane.fill"
        let color: Color = mood == .happy ? Color(red: 0.2, green: 0.75, blue: 0.4) : mood == .sad ? .red : telegramBlue
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
