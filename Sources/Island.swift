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
                            .fill(LinearGradient(colors: [.clear, accent, accentLight, .clear],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: g.size.width * 0.35)
                            .offset(x: g.size.width * x)
                    } else {
                        Capsule()
                            .fill(LinearGradient(colors: [accentLight, accent],
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
                    .fill(RadialGradient(colors: [accent.opacity(0.26 + 0.14 * pulse), accent.opacity(0.05), .clear],
                                         center: .bottom, startRadius: 4, endRadius: 200))
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(accent.opacity(0.7 + 0.25 * pulse),
                                  style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [6, 5], dashPhase: -t * 16))
                if Theme.isHalloween { Bats(t: t, count: 3) }
                HStack(spacing: 0) {
                    VStack(spacing: 8) {
                        Text(tr("Drop files here", "Брось файлы сюда", "Кидай файли сюди"))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.8))
                        HStack(spacing: 6) {
                            ForEach([tr("Photos", "Фото", "Фото"), tr("Videos", "Видео", "Відео"), "PDF", tr("Archives", "Архивы", "Архіви")], id: \.self) { chip($0) }
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
            .foregroundStyle(accent.opacity(0.95))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(accent.opacity(0.14)))
    }
}

struct IslandView: View {
    @ObservedObject var m: DropModel
    static let flare: CGFloat = 8
    static let leadingInset: CGFloat = 44
    static let shadowRoom: CGFloat = 44

    private var expanded: Bool { m.phase != .peek && m.phase != .hidden }

    /// Room the content leaves for the camera notch when the island hangs from it.
    private var notchClearance: CGFloat { m.centered ? m.menuBarHeight - 6 : 0 }

    private var size: CGSize {
        switch m.phase {
        case .hidden: CGSize(width: 150, height: 10)
        case .peek: CGSize(width: m.centered ? 250 : 214, height: m.menuBarHeight + (m.centered ? 40 : 14))
        case .hover: CGSize(width: 380, height: 128 + notchClearance)
        default: CGSize(width: 320, height: 100 + notchClearance)
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
        case .hidden, .peek: tr("To Telegram", "В Telegram", "У Telegram")
        case .hover: tr("Let go — I'll send it", "Отпусти — отправлю", "Відпусти — надішлю")
        case .sending: m.progress < 0.01 ? tr("Preparing…", "Готовлю файл…", "Готую файл…") : tr("Sending… ", "Отправляю… ", "Надсилаю… ") + "\(Int(m.progress * 100))%"
        case .done: tr("Sent", "Отправлено", "Надіслано")
        case .error: tr("Didn't work", "Не получилось", "Не вийшло")
        }
    }

    private var subtitle: String {
        switch m.phase {
        case .hidden, .peek: tr("drag a file here", "перетащи файл сюда", "перетягни файл сюди")
        case .hover: m.botName.map { "@\($0)" } ?? tr("Telegram bot", "бот Telegram", "бот Telegram")
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
                .shadow(color: accent.opacity(hover ? 0.5 : 0), radius: 18)
                .overlay(shape.stroke(accent.opacity(hover ? 0.5 : 0), lineWidth: 1))
                .overlay(shape.stroke(.white.opacity(hover ? 0 : 0.08), lineWidth: 1))

            Group {
                if hover {
                    DropZone(look: m.look)
                        .padding(.horizontal, Self.flare + 10)
                        .padding(.top, 10 + notchClearance)
                        .padding(.bottom, 12)
                        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                } else {
                    content
                        .padding(.leading, Self.flare + (expanded ? 18 : 12))
                        .padding(.trailing, Self.flare + 16)
                        .padding(.top, m.phase == .peek && m.centered ? m.menuBarHeight : notchClearance)
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
        // Appears by springing out of the notch: squeezed against the top edge, then overshoots a bit.
        .scaleEffect(m.phase == .hidden ? CGSize(width: 0.5, height: 0.2) : CGSize(width: 1, height: 1), anchor: .top)
        .blur(radius: m.phase == .hidden ? 6 : 0)
        .opacity(m.phase == .hidden ? 0 : 1)
        .padding(.leading, m.centered ? 0 : Self.leadingInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: m.centered ? .top : .topLeading)
        .animation(m.phase == .peek ? .spring(response: 0.48, dampingFraction: 0.58)
                                    : .spring(response: 0.42, dampingFraction: 0.72), value: m.phase)
        .animation(.easeInOut(duration: 0.3), value: m.language)
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
                    // Error hints are sentences: let them wrap instead of cutting the middle out.
                    .lineLimit(m.phase == .error ? 2 : 1)
                    .truncationMode(.middle)
                    .fixedSize(horizontal: false, vertical: m.phase == .error)
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
        registerForDraggedTypes([.fileURL, .URL, .png, .tiff, .string] + Self.promiseTypes)
    }

    required init?(coder: NSCoder) { fatalError() }

    static func carriesFiles(_ types: [NSPasteboard.PasteboardType]) -> Bool {
        // Files, file promises, links and images open the island (plain text drags inside editors don't).
        types.contains {
            $0 == .fileURL || $0 == .URL || $0 == .png || $0 == .tiff
                || promiseTypes.contains($0) || $0.rawValue.hasPrefix("com.apple.pasteboard.promised")
        }
    }

    /// Only the island (with some slack) accepts drops, not the whole transparent panel.
    private func overIsland(_ info: NSDraggingInfo) -> Bool {
        let p = convert(info.draggingLocation, from: nil)
        let width: CGFloat = 380 + 32, height: CGFloat = 185
        let x = model.centered ? bounds.midX - width / 2 : IslandView.leadingInset - 16
        let rect = NSRect(x: x, y: bounds.maxY - height, width: width, height: height)
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

    /// Browsers often drag a link instead of a file; images and text can come without a file too.
    private func acceptNonFile(_ pasteboard: NSPasteboard) -> Bool {
        if let links = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL],
           let link = links.first(where: { ["http", "https", "data"].contains($0.scheme?.lowercased() ?? "") }) {
            model.sendLink(link)
            return true
        }
        if let image = (pasteboard.readObjects(forClasses: [NSImage.self]) as? [NSImage])?.first,
           let tiff = image.tiffRepresentation,
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("Image \(Int(Date().timeIntervalSince1970)).png")
            if (try? png.write(to: file)) != nil {
                model.send([file])
                return true
            }
        }
        if let text = pasteboard.string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            model.sendText(text)
            return true
        }
        model.fail(tr("Couldn't read that — try dragging a file", "Не удалось прочитать — перетащи файл",
                      "Не вдалося прочитати — перетягни файл"))
        return false
    }

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
            return acceptNonFile(pasteboard)
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
