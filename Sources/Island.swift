import AppKit
import SwiftUI

// MARK: - Island

struct ProgressBar: View {
    var value: Double
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.12))
                    if value < 0.01 {
                        // Still receiving / preparing the file: a blue glint runs along the track.
                        let x = (t * 0.9).truncatingRemainder(dividingBy: 1.4) - 0.2
                        Capsule()
                            .fill(LinearGradient(colors: [.clear, telegramBlue, Color(red: 0.45, green: 0.85, blue: 1), .clear],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: g.size.width * 0.35)
                            .offset(x: g.size.width * x)
                    } else {
                        Capsule()
                            .fill(LinearGradient(colors: [Color(red: 0.3, green: 0.78, blue: 1), telegramBlue],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(5, g.size.width * value))
                            .overlay(
                                // Soft shine sweeping over the filled part.
                                LinearGradient(colors: [.clear, .white.opacity(0.45), .clear], startPoint: .leading, endPoint: .trailing)
                                    .frame(width: 40)
                                    .offset(x: g.size.width * ((t * 0.7).truncatingRemainder(dividingBy: 1.3) - 0.15))
                                    .mask(Capsule()),
                                alignment: .leading)
                    }
                }
                .clipShape(Capsule())
            }
        }
        .frame(height: 5)
        .animation(.easeOut(duration: 0.2), value: value)
    }
}

/// Coucou-style drop zone, in Telegram blue: dashed marching border, pulsing glow, file chips.
struct DropZone: View {
    var look: CGSize

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let pulse = 0.5 + 0.5 * sin(t * 2.6)
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(RadialGradient(colors: [telegramBlue.opacity(0.26 + 0.14 * pulse), telegramBlue.opacity(0.05), .clear],
                                         center: .bottom, startRadius: 4, endRadius: 200))
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(telegramBlue.opacity(0.7 + 0.25 * pulse),
                                  style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [6, 5], dashPhase: -t * 16))
                HStack(spacing: 0) {
                    VStack(spacing: 8) {
                        Text(tr("Drop files here", "Брось файлы сюда"))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.8))
                        HStack(spacing: 6) {
                            ForEach([tr("Photos", "Фото"), tr("Videos", "Видео"), "PDF", tr("Archives", "Архивы")], id: \.self) { chip($0) }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    Blob(mood: .excited, look: look, size: 50)
                        .offset(y: 3 * sin(t * 3.2))
                        .padding(.trailing, 16)
                }
            }
        }
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(telegramBlue.opacity(0.95))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(telegramBlue.opacity(0.14)))
    }
}

struct IslandView: View {
    @ObservedObject var m: DropModel
    static let flare: CGFloat = 8
    static let leadingInset: CGFloat = 44
    static let shadowRoom: CGFloat = 44

    private var expanded: Bool { m.phase != .peek && m.phase != .hidden }

    private var size: CGSize {
        switch m.phase {
        case .hidden: CGSize(width: 150, height: 10)
        case .peek: CGSize(width: 214, height: m.menuBarHeight + 14)
        case .hover: CGSize(width: 380, height: 128)
        default: CGSize(width: 320, height: 100)
        }
    }

    private var mood: Mood {
        switch m.phase {
        case .hover: .excited
        case .sending: .eating
        case .done: .happy
        case .error: .sad
        default: .idle
        }
    }

    private var title: String {
        switch m.phase {
        case .hidden, .peek: tr("To Telegram", "В Telegram")
        case .hover: tr("Let go — I'll send it", "Отпусти — отправлю")
        case .sending: m.progress < 0.01 ? tr("Preparing…", "Готовлю файл…") : tr("Sending… ", "Отправляю… ") + "\(Int(m.progress * 100))%"
        case .done: tr("Sent", "Отправлено")
        case .error: tr("Didn't work", "Не получилось")
        }
    }

    private var subtitle: String {
        switch m.phase {
        case .hidden, .peek: tr("drag a file here", "перетащи файл сюда")
        case .hover: m.botName.map { "@\($0)" } ?? tr("Telegram bot", "бот Telegram")
        default: m.detail
        }
    }

    private var titleColor: Color {
        switch m.phase {
        case .done: Color(red: 0.4, green: 0.88, blue: 0.55)
        case .error: Color(red: 1, green: 0.5, blue: 0.5)
        default: .white
        }
    }

    var body: some View {
        let s = size
        let shape = IslandShape(flare: Self.flare, radius: expanded ? 28 : 18)
        let hover = m.phase == .hover

        ZStack(alignment: .leading) {
            shape.fill(.black)
                .shadow(color: .black.opacity(0.45), radius: 14, y: 6)
                .shadow(color: telegramBlue.opacity(hover ? 0.5 : 0), radius: 18)
                .overlay(shape.stroke(telegramBlue.opacity(hover ? 0.5 : 0), lineWidth: 1))
                .overlay(shape.stroke(.white.opacity(hover ? 0 : 0.08), lineWidth: 1))

            Group {
                if hover {
                    DropZone(look: m.look)
                        .padding(.horizontal, Self.flare + 10)
                        .padding(.top, 10)
                        .padding(.bottom, 12)
                        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                } else {
                    content
                        .padding(.leading, Self.flare + (expanded ? 18 : 12))
                        .padding(.trailing, Self.flare + 16)
                        .transition(.opacity)
                }
            }
            .frame(width: s.width, height: s.height, alignment: .leading)
            .clipShape(shape)
        }
        .frame(width: s.width, height: s.height)
        // Render the island (shadows, glow, animations) into one GPU layer inside TeleDrop, so
        // WindowServer only composites a bitmap instead of re-blurring shadows every frame.
        .padding(Self.shadowRoom)
        .drawingGroup()
        .padding(-Self.shadowRoom)
        .opacity(m.phase == .hidden ? 0 : 1)
        .padding(.leading, Self.leadingInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(.spring(response: 0.42, dampingFraction: 0.72), value: m.phase)
    }

    private var content: some View {
        HStack(spacing: expanded ? 14 : 9) {
            Blob(mood: mood, look: m.look, size: expanded ? 48 : 24)
            VStack(alignment: .leading, spacing: expanded ? 4 : 1) {
                Text(title)
                    .font(.system(size: expanded ? 15 : 12.5, weight: .semibold))
                    .foregroundStyle(titleColor)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(subtitle)
                    .font(.system(size: expanded ? 12 : 10.5))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if m.phase == .sending {
                    ProgressBar(value: m.progress)
                        .padding(.top, 5)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .lineLimit(1)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Drop target

/// AppKit drop target behind the SwiftUI island. Accepts plain files (Finder) and file promises
/// (Photos, screenshot thumbnails, browsers, Telegram…), which SwiftUI's onDrop(.fileURL) misses.
final class DropView: NSView {
    static let promiseTypes = NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }
    private let model: DropModel
    private let promiseQueue = OperationQueue()

    init(model: DropModel) {
        self.model = model
        super.init(frame: .zero)
        registerForDraggedTypes([.fileURL] + Self.promiseTypes)
    }

    required init?(coder: NSCoder) { fatalError() }

    static func carriesFiles(_ types: [NSPasteboard.PasteboardType]) -> Bool {
        types.contains { $0 == .fileURL || promiseTypes.contains($0) || $0.rawValue.hasPrefix("com.apple.pasteboard.promised") }
    }

    /// Only the island (with some slack) accepts drops, not the whole transparent panel.
    private func overIsland(_ info: NSDraggingInfo) -> Bool {
        let p = convert(info.draggingLocation, from: nil)
        let rect = NSRect(x: IslandView.leadingInset - 16, y: bounds.maxY - 150,
                          width: 380 + 32, height: 150)
        return rect.contains(p)
    }

    private func update(_ info: NSDraggingInfo) -> NSDragOperation {
        let inside = overIsland(info)
        model.setHover(inside)
        return inside ? .copy : []
    }

    override func draggingEntered(_ info: NSDraggingInfo) -> NSDragOperation { update(info) }
    override func draggingUpdated(_ info: NSDraggingInfo) -> NSDragOperation { update(info) }
    override func draggingExited(_ info: NSDraggingInfo?) { model.setHover(false) }

    private var performed = false

    override func draggingEnded(_ info: NSDraggingInfo) {
        if !performed { model.dropCancelled() }
        performed = false
    }

    override func performDragOperation(_ info: NSDraggingInfo) -> Bool {
        guard overIsland(info) else { return false }
        performed = true
        let pasteboard = info.draggingPasteboard
        log("drop types: \(pasteboard.types?.map(\.rawValue).prefix(6) ?? [])")
        model.beginDrop()

        if let urls = pasteboard.readObjects(forClasses: [NSURL.self],
                                             options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            model.send(urls)
            return true
        }

        guard let promises = pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self]) as? [NSFilePromiseReceiver],
              !promises.isEmpty else {
            model.fail(tr("Couldn't read the file", "Не удалось прочитать файл"))
            return false
        }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("TeleDrop-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let group = DispatchGroup()
        let lock = NSLock()
        var urls: [URL] = []
        for promise in promises {
            for _ in promise.fileNames { group.enter() }
            promise.receivePromisedFiles(atDestination: dir, options: [:], operationQueue: promiseQueue) { url, error in
                if let error {
                    log("promise failed: \(error.localizedDescription)")
                } else {
                    lock.lock()
                    urls.append(url)
                    lock.unlock()
                }
                group.leave()
            }
        }
        group.notify(queue: .main) { self.model.send(urls) }
        return true
    }
}
