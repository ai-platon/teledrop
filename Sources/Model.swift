import AppKit
import SwiftUI

// MARK: - Model

enum Phase: Equatable { case hidden, peek, hover, sending, done, error }

final class DropModel: ObservableObject {
    @Published var phase: Phase = .hidden {
        didSet {
            guard phase != oldValue else { return }
            log("phase \(oldValue) → \(phase)")
            playSound(from: oldValue, to: phase)
            onPhaseChange?(phase)
        }
    }
    @Published var progress: Double = 0
    @Published var detail = ""
    @Published var look: CGSize = .zero
    @Published var botName: String?
    @Published var menuBarHeight: CGFloat = 37
    /// Hanging from the notch itself (no Coucou): grow around the notch, content below it.
    @Published var centered = false
    /// Mirrors Settings.language so views redraw when it changes.
    @Published var language = Settings.language
    /// Set by visual tests so the drag watcher doesn't collapse a frozen state.
    var pinned = false
    /// Pasteboard churn right after a drop must not reopen the island.
    var suppressPeekUntil = Date.distantPast
    private var uploading = false

    var onPhaseChange: ((Phase) -> Void)?
    /// Asked to show the setup window (e.g. a drop arrived before a bot was connected).
    var onNeedsSetup: (() -> Void)?
    private var queue: [URL] = []
    private var total = 0
    private var hideWork: DispatchWorkItem?
    private var demoTimer: Timer?

    func refreshBotName() {
        botName = Settings.botName
        guard let cfg = TGConfig.load() else { botName = nil; return }
        Task { @MainActor in
            guard let bot = try? await Telegram.getMe(cfg.token) else { return }
            Settings.botName = bot.username
            self.botName = bot.username
        }
    }

    func setHover(_ targeted: Bool) {
        if targeted, phase == .peek {
            phase = .hover
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        } else if !targeted, phase == .hover {
            phase = .peek
        }
    }

    /// Called synchronously from the drop so the island never collapses between drop and send.
    func beginDrop() {
        hideWork?.cancel()
        suppressPeekUntil = Date().addingTimeInterval(1.5)
        guard !uploading else { return }
        if phase != .sending { progress = 0 }
        detail = tr("receiving file…", "получаю файл…", "отримую файл…")
        phase = .sending
    }

    /// The mouse was released over the island: start the animation right away, before macOS
    /// delivers the drop (file promises can take seconds). Collapse if no drop ever arrives.
    func releasedOverIsland() {
        beginDrop()
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            guard let self, self.phase == .sending, !self.uploading else { return }
            log("no drop arrived after release")
            self.phase = .hidden
        }
    }

    /// The drag ended without a drop on us.
    func dropCancelled() {
        guard phase == .sending, !uploading else { return }
        phase = .hidden
    }

    func send(_ urls: [URL]) {
        log("send \(urls.map(\.path))")
        guard !urls.isEmpty else { phase = .hidden; return }
        guard let cfg = TGConfig.load() else {
            fail(tr("Connect a bot first", "Сначала подключи бота", "Спершу підключи бота"))
            onNeedsSetup?()
            return
        }
        queue = urls
        total = urls.count
        uploading = true
        next(cfg)
    }

    private func next(_ cfg: TGConfig) {
        guard let file = queue.first else { finish(); return }
        queue.removeFirst()
        let index = total - queue.count
        let label = total > 1 ? "\(file.lastPathComponent) · \(index) " + tr("of", "из", "з") + " \(total)" : file.lastPathComponent
        progress = 0
        detail = label
        phase = .sending

        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let prepared = try Packer.prepare(file) { status in
                    DispatchQueue.main.async { self?.detail = "\(file.lastPathComponent) · \(status)" }
                }
                defer { prepared.workDir.map { try? FileManager.default.removeItem(at: $0) } }
                let count = prepared.parts.count
                for (i, part) in prepared.parts.enumerated() {
                    await MainActor.run {
                        self?.detail = count > 1 ? "\(label) · " + tr("part \(i + 1) of \(count)", "часть \(i + 1) из \(count)", "частина \(i + 1) з \(count)") : label
                    }
                    try await Telegram.sendDocument(part, caption: i == 0 ? prepared.caption : nil, cfg: cfg) { fraction in
                        DispatchQueue.main.async { self?.progress = (Double(i) + fraction) / Double(count) }
                    }
                }
                log("uploaded \(file.lastPathComponent) in \(count) part(s)")
                await MainActor.run { self?.next(cfg) }
            } catch {
                log("upload failed: \(error)")
                await MainActor.run { self?.fail(Telegram.friendly(error)) }
            }
        }
    }

    private func finish() {
        uploading = false
        let bot = botName.map { " → @\($0)" } ?? ""
        detail = total == 1 ? detail : filesCount(total) + bot
        phase = .done
        scheduleHide(after: 1.8)
    }

    func fail(_ message: String) {
        uploading = false
        queue = []
        detail = message
        phase = .error
        scheduleHide(after: 4)
    }

    func scheduleHide(after delay: Double) {
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.phase == .done || self.phase == .error else { return }
            self.phase = .hidden
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Freezes the island in one state for visual tests (see Tests/snap.sh).
    func showTestState(_ name: String) {
        hideWork?.cancel()
        demoTimer?.invalidate()
        pinned = name != "hidden"
        botName = botName ?? "my_bot"
        switch name {
        case "peek": phase = .peek
        case "hover": phase = .peek; phase = .hover
        case "sending": detail = tr("vacation-2026.jpg", "отпуск-2026.jpg", "відпустка-2026.jpg"); progress = 0.42; phase = .sending
        case "done": detail = filesCount(3) + " → @\(botName!)"; phase = .done
        case "error": detail = tr("Press Start in your bot in Telegram", "Нажми Start у бота в Telegram", "Натисни Start у бота в Telegram"); phase = .error
        case "demo": demo()
        default: phase = .hidden
        }
    }

    /// Plays the whole animation without sending anything.
    func cycleLanguage() {
        Settings.language = Settings.language.next
        Sfx.language.play()
        withAnimation(.easeInOut(duration: 0.35)) { language = Settings.language }
    }

    func demo() {
        hideWork?.cancel()
        demoTimer?.invalidate()
        // No real drag is happening, so keep the drag watcher from collapsing the island.
        pinned = true
        total = 1
        phase = .peek
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { self.setHover(true) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            self.detail = tr("vacation-2026.jpg", "отпуск-2026.jpg", "відпустка-2026.jpg")
            self.progress = 0
            self.phase = .sending
            self.demoTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { t in
                self.progress = min(1, self.progress + 0.025)
                if self.progress >= 1 {
                    t.invalidate()
                    self.pinned = false
                    self.finish()
                }
            }
        }
    }

    /// Every island state change has its own sound, so it can be followed by ear.
    private func playSound(from old: Phase, to new: Phase) {
        switch (old, new) {
        case (.hidden, .peek), (.done, .peek), (.error, .peek): Sfx.peek.play(volume: 0.3)
        case (.peek, .hover): Sfx.hover.play(volume: 0.35)
        case (.hover, .sending), (.hidden, .sending): Sfx.drop.play()
        case (.sending, .done): Sfx.sent.play(volume: 0.4)
        case (_, .error): Sfx.error.play(volume: 0.4)
        case (.peek, .hidden), (.hover, .hidden): Sfx.close.play(volume: 0.25)
        default: break
        }
    }
}
