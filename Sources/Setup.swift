import AppKit
import ServiceManagement
import SwiftUI

// MARK: - Window

/// One dark, Coucou-style window: the 3-step bot setup on first launch, the settings afterwards.
final class SetupWindow {
    static let shared = SetupWindow()
    private var window: NSWindow?

    /// `step` reopens the window at a given page (used by visual tests).
    func show(model: DropModel, step: SetupView.Step? = nil) {
        if step != nil { window?.close(); window = nil }
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 560),
                             styleMask: [.titled, .closable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isMovableByWindowBackground = true
            w.isReleasedWhenClosed = false
            w.appearance = NSAppearance(named: .darkAqua)
            w.backgroundColor = NSColor(red: 0.055, green: 0.06, blue: 0.07, alpha: 1)
            w.contentView = NSHostingView(rootView: SetupView(model: model, initialStep: step) { [weak w] in w?.close() })
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

// MARK: - Content

struct SetupView: View {
    @ObservedObject var model: DropModel
    var close: () -> Void

    init(model: DropModel, initialStep: Step? = nil, close: @escaping () -> Void) {
        self.model = model
        self.close = close
        _step = State(initialValue: initialStep ?? (TGConfig.load() == nil ? .create : .settings))
    }

    enum Step: Int { case create, token, start, done, settings }
    enum TokenState: Equatable { case empty, checking, valid(String), invalid(String) }

    @State private var step: Step
    @State private var token = ""
    @State private var revealToken = false
    @State private var tokenState: TokenState = .empty
    @State private var foundChat: Telegram.Chat?
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var sounds = Settings.soundsOn
    @State private var avoidCoucou = Settings.avoidCoucou
    @State private var testStatus: String?
    /// Clipboard changed while the user was away (copying the token in BotFather).
    @State private var clipboardOffer = false
    @State private var clipboardSeen = NSPasteboard.general.changeCount
    @State private var clipboardNote: String?
    @State private var autoAdvance = false

    private var botUsername: String {
        if case .valid(let name) = tokenState { return name }
        return Settings.botName ?? model.botName ?? "bot"
    }

    var body: some View {
        ZStack {
            RadialGradient(colors: [telegramBlue.opacity(0.22), .clear], center: .top, startRadius: 0, endRadius: 360)
                .ignoresSafeArea()
            VStack(spacing: 0) {
                header
                if step.rawValue <= Step.start.rawValue {
                    StepDots(current: step.rawValue, count: 3).padding(.top, 18)
                }
                Group {
                    switch step {
                    case .create: createStep
                    case .token: tokenStep
                    case .start: startStep
                    case .done: doneStep
                    case .settings: settingsPage
                    }
                }
                .padding(.top, 22)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal: .move(edge: .leading).combined(with: .opacity)))
                .id(step)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 28)
            .padding(.top, 38)
            .padding(.bottom, 24)
        }
        .frame(width: 480, height: 560)
        .preferredColorScheme(.dark)
        .animation(.spring(response: 0.45, dampingFraction: 0.86), value: step)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: clipboardOffer)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            noticeClipboard()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            noticeClipboard()
        }
    }

    // MARK: Header

    private var mood: Mood {
        switch step {
        case .create: .idle
        case .token:
            switch tokenState {
            case .valid: .excited
            case .invalid: .sad
            default: .idle
            }
        case .start: foundChat == nil ? .idle : .happy
        case .done: .happy
        case .settings: .idle
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                Blob(mood: mood, look: CGSize(width: sin(t * 0.7) * 0.5, height: cos(t * 0.5) * 0.3), size: 64)
                    .offset(y: 2 * sin(t * 2))
                    .padding(12)
                    .drawingGroup()
                    .padding(-12)
            }
            .frame(height: 70)
            Text("TeleDrop")
                .font(.system(size: 22, weight: .bold))
            Text(tr("Drop files on the notch — get them in Telegram", "Бросай файлы в вырез — получай в Telegram"))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Steps

    private var createStep: some View {
        VStack(spacing: 16) {
            Card {
                CardTitle(number: 1, text: tr("Create your bot", "Создай своего бота"))
                Instruction(n: 1, text: LocalizedStringKey(tr("Open **@BotFather** in Telegram", "Открой **@BotFather** в Telegram")))
                Instruction(n: 2, text: LocalizedStringKey(tr("Send the **/newbot** command", "Отправь команду **/newbot**")))
                Instruction(n: 3, text: LocalizedStringKey(tr("Pick a name and a username — it must end in **bot**", "Придумай имя и юзернейм — он должен заканчиваться на **bot**")))
                Instruction(n: 4, text: LocalizedStringKey(tr("BotFather replies with a **token** — copy it", "BotFather пришлёт **токен** — скопируй его")))
                Label(tr("Then just come back here — I'll pick the token up", "Потом просто вернись сюда — я подхвачу токен"),
                      systemImage: "sparkles")
                    .font(.system(size: 12))
                    .foregroundStyle(telegramBlue)
            }
            HStack {
                SecondaryButton(title: tr("Open @BotFather", "Открыть @BotFather"), icon: "arrow.up.right") { openTelegram("BotFather") }
                Spacer()
                PrimaryButton(title: tr("I have a token", "У меня есть токен")) { step = .token }
            }
        }
    }

    private var tokenStep: some View {
        VStack(spacing: 16) {
            Card {
                CardTitle(number: 2, text: tr("Paste the bot token", "Вставь токен бота"))
                if clipboardOffer && !isValid {
                    clipboardBanner
                }
                HStack(spacing: 8) {
                    Group {
                        if revealToken {
                            TextField("123456789:AAH…", text: $token)
                        } else {
                            SecureField("123456789:AAH…", text: $token)
                        }
                    }
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, design: .monospaced))
                    Button { revealToken.toggle() } label: {
                        Image(systemName: revealToken ? "eye.slash" : "eye").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    Button(tr("Paste", "Вставить")) { pasteFromClipboard() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(telegramBlue)
                }
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(.white.opacity(0.06)))
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(fieldBorder, lineWidth: 1))

                if let clipboardNote {
                    Label(clipboardNote, systemImage: "doc.on.clipboard")
                        .font(.system(size: 12)).foregroundStyle(.orange)
                } else {
                    tokenStatus
                }
                Text(tr("The token stays on this Mac and is only ever sent to Telegram.", "Токен хранится только на этом Mac и уходит только в Telegram."))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            HStack {
                SecondaryButton(title: tr("Back", "Назад"), icon: "chevron.left") { step = .create }
                Spacer()
                PrimaryButton(title: tr("Next", "Дальше"), enabled: isValid,
                              isDefault: !(clipboardOffer && !isValid)) { step = .start }
            }
        }
        .task(id: token) { await checkToken() }
        .onAppear {
            // Came here with something already copied: offer it right away.
            if token.isEmpty, NSPasteboard.general.types?.contains(.string) == true { clipboardOffer = true }
        }
    }

    private var fieldBorder: Color {
        switch tokenState {
        case .valid: Color.green.opacity(0.5)
        case .invalid: Color.red.opacity(0.5)
        default: Color.white.opacity(0.08)
        }
    }

    private var isValid: Bool {
        if case .valid = tokenState { return true }
        return false
    }

    @ViewBuilder private var tokenStatus: some View {
        switch tokenState {
        case .empty:
            Text(tr("Looks like: 123456789:AAH-xYz…", "Выглядит так: 123456789:AAH-xYz…")).font(.system(size: 12)).foregroundStyle(.secondary)
        case .checking:
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text(tr("Checking…", "Проверяю…")) }
                .font(.system(size: 12)).foregroundStyle(.secondary)
        case .valid(let name):
            Label(LocalizedStringKey(tr("Found bot **@\(name)**", "Бот **@\(name)** найден")), systemImage: "checkmark.circle.fill")
                .font(.system(size: 12)).foregroundStyle(.green)
        case .invalid(let message):
            Label(message, systemImage: "exclamationmark.circle.fill")
                .font(.system(size: 12)).foregroundStyle(Color(red: 1, green: 0.45, blue: 0.45))
        }
    }

    private var startStep: some View {
        VStack(spacing: 16) {
            Card {
                CardTitle(number: 3, text: tr("Press Start in your bot", "Нажми Start у бота"))
                Text(LocalizedStringKey(tr("Open **@\(botUsername)** and press **Start** — I'll find your chat and say hi.", "Открой **@\(botUsername)** и нажми **Start** — я сам найду твой чат и пришлю приветствие.")))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let foundChat {
                    Label(tr("Found you", "Нашёл тебя") + (foundChat.name.isEmpty ? "" : ", \(foundChat.name)") + "!", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(.green)
                } else {
                    HStack(spacing: 8) {
                        WaitingDots()
                        Text(tr("Waiting for your message to the bot…", "Жду твоё сообщение боту…")).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
            }
            HStack {
                SecondaryButton(title: tr("Back", "Назад"), icon: "chevron.left") { step = .token }
                Spacer()
                PrimaryButton(title: tr("Open", "Открыть") + " @\(botUsername)", icon: "arrow.up.right") { openTelegram(botUsername) }
            }
        }
        .task { await waitForChat() }
    }

    private var doneStep: some View {
        VStack(spacing: 16) {
            Card {
                Text(tr("All set! 🎉", "Готово! 🎉")).font(.system(size: 17, weight: .semibold))
                Text(LocalizedStringKey(tr("Drag any file to the notch — it lands in Telegram via **@\(botUsername)**.", "Перетащи любой файл к вырезу — он прилетит в Telegram к **@\(botUsername)**.")))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Tip(icon: "doc.on.doc", text: tr("Files & folders", "Файлы и папки"))
                    Tip(icon: "photo", text: tr("Photos & screenshots", "Фото и скриншоты"))
                    Tip(icon: "archivebox", text: tr("Over 49 MB — zipped", "Больше 49 МБ — zip"))
                }
                SettingToggle(title: tr("Open at login", "Запускать при входе в систему"), isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in setLaunchAtLogin(on) }
            }
            HStack {
                SecondaryButton(title: tr("Show animation", "Показать анимацию"), icon: "sparkles") { model.demo() }
                Spacer()
                PrimaryButton(title: tr("Start", "Начать")) {
                    close()
                    step = .settings
                }
            }
        }
        .onAppear {
            if !launchAtLogin { launchAtLogin = true }
        }
    }

    // MARK: Settings

    private var settingsPage: some View {
        VStack(spacing: 14) {
            Card {
                HStack(spacing: 12) {
                    Circle().fill(telegramBlue.gradient).frame(width: 38, height: 38)
                        .overlay(Image(systemName: "paperplane.fill").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("@\(botUsername)").font(.system(size: 14, weight: .semibold))
                        Text(Settings.chatName.map { tr("Sends to: ", "Отправляет: ") + $0 } ?? tr("Sends to your chat", "Отправляет в твой чат"))
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    HStack(spacing: 5) {
                        Circle().fill(.green).frame(width: 7, height: 7)
                        Text(tr("Connected", "Подключён")).font(.system(size: 11, weight: .medium)).foregroundStyle(.green)
                    }
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Capsule().fill(.green.opacity(0.12)))
                }
                HStack(spacing: 8) {
                    SecondaryButton(title: tr("Send test", "Отправить тест"), icon: "paperplane") { Task { await sendTest() } }
                    SecondaryButton(title: tr("Change bot", "Сменить бота"), icon: "arrow.triangle.2.circlepath") {
                        token = ""
                        tokenState = .empty
                        foundChat = nil
                        step = .create
                    }
                }
                if let testStatus {
                    Text(testStatus).font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            Card {
                SettingToggle(title: tr("Open at login", "Запускать при входе в систему"), isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in setLaunchAtLogin(on) }
                SettingToggle(title: tr("Sounds", "Звуки"), isOn: $sounds)
                    .onChange(of: sounds) { _, on in Settings.soundsOn = on }
                if CoucouWatcher.isInstalled {
                    SettingToggle(title: tr("Make room for expanded Coucou", "Уступать место раскрытому Coucou"), isOn: $avoidCoucou)
                        .onChange(of: avoidCoucou) { _, on in Settings.avoidCoucou = on }
                }
            }
            HStack {
                Text(tr("Version ", "Версия ") + (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"))
                    // Hidden language switch: ⌥-click the version.
                    .onTapGesture {
                        if NSEvent.modifierFlags.contains(.option) { model.toggleLanguage() }
                    }
                Text("·")
                Button(tr("Log", "Журнал")) {
                    NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory() + "/Library/Logs/TeleDrop.log"))
                }
                .buttonStyle(.plain)
                .foregroundStyle(telegramBlue)
                Spacer()
                SecondaryButton(title: tr("Show animation", "Показать анимацию"), icon: "sparkles") { model.demo() }
            }
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
        }
    }

    // MARK: Actions

    private var clipboardBanner: some View {
        Button(action: pasteFromClipboard) {
            HStack(spacing: 12) {
                Image(systemName: "doc.on.clipboard.fill").font(.system(size: 16))
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("Paste token from clipboard", "Вставить токен из буфера"))
                        .font(.system(size: 13, weight: .semibold))
                    Text(tr("Copied it in BotFather? Just one click.", "Скопировал в BotFather? Всего один клик."))
                        .font(.system(size: 11)).opacity(0.8)
                }
                Spacer()
                Image(systemName: "return").font(.system(size: 12, weight: .semibold)).opacity(0.7)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(height: 52)
            .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(telegramBlue.gradient))
            .shadow(color: telegramBlue.opacity(0.45), radius: 10, y: 3)
        }
        .buttonStyle(PressStyle())
        .keyboardShortcut(.defaultAction)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    /// Back from Telegram with a fresh clipboard: jump to the token step and offer to paste.
    private func noticeClipboard() {
        guard step == .create || step == .token, !isValid else { return }
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != clipboardSeen, pasteboard.types?.contains(.string) == true else { return }
        clipboardSeen = pasteboard.changeCount
        clipboardNote = nil
        clipboardOffer = true
        if step == .create { step = .token }
    }

    /// Reading happens only on a click, so macOS doesn't flag a silent clipboard read.
    private func pasteFromClipboard() {
        let text = NSPasteboard.general.string(forType: .string) ?? ""
        guard let found = Telegram.extractToken(text) else {
            clipboardNote = tr("No token in the clipboard — copy it in BotFather (tap the token to copy)",
                               "В буфере нет токена — скопируй его в BotFather (нажми на токен)")
            return
        }
        clipboardNote = nil
        clipboardOffer = false
        autoAdvance = true
        token = found
    }

    private func checkToken() async {
        let candidate = Telegram.extractToken(token) ?? token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { tokenState = .empty; return }
        guard Telegram.isTokenShaped(candidate) else {
            tokenState = .invalid(tr("Doesn't look like a token — copy the whole thing from BotFather", "Не похоже на токен — скопируй его из BotFather целиком"))
            return
        }
        tokenState = .checking
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        do {
            let bot = try await Telegram.getMe(candidate)
            guard !Task.isCancelled else { return }
            tokenState = .valid(bot.username)
            if autoAdvance {
                autoAdvance = false
                try? await Task.sleep(for: .milliseconds(800))
                if step == .token, isValid { step = .start }
            }
        } catch {
            guard !Task.isCancelled else { return }
            tokenState = .invalid(Telegram.friendly(error))
        }
    }

    private func waitForChat() async {
        let candidate = Telegram.extractToken(token) ?? token.trimmingCharacters(in: .whitespacesAndNewlines)
        while !Task.isCancelled, step == .start, foundChat == nil {
            if let chat = try? await Telegram.latestPrivateChat(candidate) {
                Settings.token = candidate
                Settings.chatID = chat.id
                Settings.chatName = chat.name
                Settings.botName = botUsername
                model.botName = botUsername
                foundChat = chat
                log("bot @\(botUsername) connected")
                if let cfg = TGConfig.load() {
                    try? await Telegram.sendMessage(
                        tr("👋 TeleDrop is connected!\nDrag any file to the notch on your Mac — it will show up here.", "👋 TeleDrop подключён!\nПеретащи любой файл к вырезу на Mac — он придёт сюда."), cfg: cfg)
                }
                try? await Task.sleep(for: .milliseconds(900))
                step = .done
                return
            }
            try? await Task.sleep(for: .seconds(1.5))
        }
    }

    private func sendTest() async {
        guard let cfg = TGConfig.load() else { return }
        testStatus = tr("Sending…", "Отправляю…")
        do {
            try await Telegram.sendMessage(tr("✅ Connection check: TeleDrop is here.", "✅ Проверка связи: TeleDrop на месте."), cfg: cfg)
            testStatus = tr("Sent — check Telegram", "Сообщение отправлено — проверь Telegram")
        } catch {
            testStatus = tr("Didn't work: ", "Не получилось: ") + Telegram.friendly(error)
        }
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            log("launch at login: \(error.localizedDescription)")
        }
    }

    private func openTelegram(_ username: String) {
        let app = URL(string: "tg://resolve?domain=\(username)")!
        let web = URL(string: "https://t.me/\(username)")!
        NSWorkspace.shared.open(NSWorkspace.shared.urlForApplication(toOpen: app) != nil ? app : web)
    }
}

// MARK: - Building blocks

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.white.opacity(0.045)))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(0.08)))
    }
}

struct CardTitle: View {
    var number: Int
    var text: String
    var body: some View {
        Text(text).font(.system(size: 15, weight: .semibold))
    }
}

struct Instruction: View {
    var n: Int
    var text: LocalizedStringKey
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(n)")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(telegramBlue)
                .frame(width: 20, height: 20)
                .background(Circle().fill(telegramBlue.opacity(0.15)))
            Text(text).font(.system(size: 13)).foregroundStyle(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct SettingToggle: View {
    var title: String
    @Binding var isOn: Bool
    var body: some View {
        HStack {
            Text(title).font(.system(size: 13))
            Spacer()
            Toggle("", isOn: $isOn).labelsHidden().toggleStyle(.switch).tint(telegramBlue).controlSize(.small)
        }
    }
}

struct Tip: View {
    var icon: String
    var text: String
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 15)).foregroundStyle(telegramBlue)
            Text(text).font(.system(size: 10.5, weight: .medium)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(telegramBlue.opacity(0.08)))
    }
}

struct StepDots: View {
    var current: Int
    var count: Int
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i <= current ? telegramBlue : .white.opacity(0.15))
                    .frame(width: i == current ? 22 : 7, height: 7)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: current)
    }
}

struct WaitingDots: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    Circle().fill(telegramBlue)
                        .frame(width: 6, height: 6)
                        .opacity(0.3 + 0.7 * max(0, sin(t * 4 - Double(i) * 0.7)))
                }
            }
        }
    }
}

struct PrimaryButton: View {
    var title: String
    var icon: String?
    var enabled = true
    var isDefault = true
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                if let icon { Image(systemName: icon).font(.system(size: 11, weight: .bold)) }
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .frame(height: 36)
            .background(Capsule().fill(telegramBlue.opacity(enabled ? (hovering ? 1 : 0.9) : 0.3)))
            .shadow(color: telegramBlue.opacity(enabled ? 0.4 : 0), radius: hovering ? 12 : 6, y: 2)
        }
        .buttonStyle(PressStyle())
        .disabled(!enabled)
        .onHover { hovering = $0 }
        .keyboardShortcut(isDefault ? .defaultAction : nil)
    }
}

struct SecondaryButton: View {
    var title: String
    var icon: String?
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon).font(.system(size: 11, weight: .semibold)) }
                Text(title)
            }
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(Capsule().fill(.white.opacity(hovering ? 0.12 : 0.07)))
        }
        .buttonStyle(PressStyle())
        .onHover { hovering = $0 }
    }
}

struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
