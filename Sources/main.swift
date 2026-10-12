// TeleDrop — a drop zone next to the MacBook notch that sends files to your own Telegram bot.

import AppKit
import ServiceManagement
import SwiftUI

// MARK: - Window

final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    static let panelSize = CGSize(width: 480, height: 190)

    let model = DropModel()
    var panel: IslandPanel!
    var statusItem: NSStatusItem!
    var watchTimer: Timer?
    private var screenFrame: NSRect = .zero
    private var notchRight: CGFloat = 0
    private var coucouRight: CGFloat?
    private var measuring = false
    private var tick = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpPanel()
        setUpStatusItem()
        watchDrags()
        model.refreshBotName()
        model.onNeedsSetup = { [weak self] in self?.openSettings() }
        // Started by "launch at login": stay quiet in the menu bar, never pop a window.
        if TGConfig.load() == nil, !launchedAtLogin { openSettings() }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in self?.position() }
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("app.teledrop.TeleDrop.test"),
                                                            object: nil, queue: .main) { [weak self] note in
            guard let self, let name = note.object as? String else { return }
            if name.hasPrefix("setup:") {
                let steps: [String: SetupView.Step] = ["create": .create, "token": .token, "start": .start,
                                                       "done": .done, "settings": .settings]
                SetupWindow.shared.show(model: self.model, step: steps[String(name.dropFirst(6))])
            } else {
                self.model.showTestState(name)
            }
        }
    }

    private func setUpPanel() {
        panel = IslandPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.ignoresMouseEvents = true
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 4)  // above Coucou
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        let host = NSHostingView(rootView: IslandView(m: model))
        host.sizingOptions = []
        host.autoresizingMask = [.width, .height]
        let dropView = DropView(model: model)
        dropView.addSubview(host)
        panel.contentView = dropView
        host.frame = dropView.bounds
        position()
        panel.orderFrontRegardless()

        // Only catch the mouse while a drag is waiting for a drop; otherwise clicks pass through.
        model.onPhaseChange = { [weak self] phase in
            self?.panel.ignoresMouseEvents = !(phase == .peek || phase == .hover)
        }
    }

    private func position() {
        let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]
        screenFrame = screen.frame
        notchRight = screenFrame.midX + 100
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            notchRight = screenFrame.midX + (screenFrame.width - left.width - right.width) / 2
        }
        model.menuBarHeight = screen.safeAreaInsets.top > 0 ? screen.safeAreaInsets.top : NSStatusBar.system.thickness
        placePanel(animated: false)
    }

    /// Sits right of the notch, or right of Coucou's panel while Coucou is expanded.
    private func placePanel(animated: Bool) {
        let s = Self.panelSize
        var x = notchRight + 2
        if let coucouRight { x = max(x, coucouRight + 12) }
        x = min(x, screenFrame.maxX - 400)
        let frame = NSRect(x: x - IslandView.leadingInset, y: screenFrame.maxY - s.height, width: s.width, height: s.height)
        guard frame != panel.frame else { return }
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.38
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
    }

    private func measureCoucou() {
        guard !measuring, Settings.avoidCoucou else {
            if !Settings.avoidCoucou, coucouRight != nil { coucouRight = nil; placePanel(animated: true) }
            return
        }
        measuring = true
        let menuBarHeight = model.menuBarHeight
        Task { @MainActor in
            let right = await CoucouWatcher.expandedRightEdge(menuBarHeight: menuBarHeight)
            self.measuring = false
            guard right != self.coucouRight else { return }
            log("coucou panel right edge: \(right.map { String(Int($0)) } ?? "collapsed")")
            self.coucouRight = right
            self.placePanel(animated: self.model.phase != .hidden)
        }
    }

    /// Shows the island as soon as any app starts dragging files, hides it when the drag ends elsewhere.
    private func watchDrags() {
        let pasteboard = NSPasteboard(name: .drag)
        var baseline = pasteboard.changeCount
        var wasDown = false
        var releasedAt: Date?

        watchTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            guard let self else { return }
            let m = self.model
            let down = NSEvent.pressedMouseButtons & 1 != 0
            if down && !wasDown { baseline = pasteboard.changeCount }
            wasDown = down

            if down, pasteboard.changeCount != baseline,
               [.hidden, .done, .error].contains(m.phase) || m.pinned,
               Date() > m.suppressPeekUntil,
               DropView.carriesFiles(pasteboard.types ?? []) {
                baseline = pasteboard.changeCount
                m.pinned = false
                m.phase = .peek
                self.measureCoucou()
            }

            if !down, !m.pinned, m.phase == .hover {
                m.releasedOverIsland()
                releasedAt = nil
            } else if !down, !m.pinned, m.phase == .peek {
                if let t = releasedAt {
                    if Date().timeIntervalSince(t) > 0.3 { m.phase = .hidden; releasedAt = nil }
                } else {
                    releasedAt = Date()
                }
            } else {
                releasedAt = nil
            }

            if m.phase != .hidden { self.updateLook() }
            self.tick += 1
            if (m.phase == .peek || m.phase == .hover), self.tick % 8 == 0 { self.measureCoucou() }
        }
        RunLoop.main.add(watchTimer!, forMode: .common)
    }

    private func updateLook() {
        let mouse = NSEvent.mouseLocation
        let center = CGPoint(x: panel.frame.minX + IslandView.leadingInset + 50, y: panel.frame.maxY - 45)
        let clamp = { (v: CGFloat) in max(-1, min(1, v)) }
        let look = CGSize(width: clamp((mouse.x - center.x) / 240), height: clamp((center.y - mouse.y) / 160))
        if abs(look.width - model.look.width) + abs(look.height - model.look.height) > 0.02 {
            model.look = look
        }
    }

    // MARK: Menu bar

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "paperplane", accessibilityDescription: "TeleDrop")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let bot = TGConfig.load() == nil ? tr("No bot connected", "Бот не подключён")
            : tr("Bot: ", "Бот: ") + (model.botName.map { "@\($0)" } ?? "…")
        menu.addItem(withTitle: bot, action: nil, keyEquivalent: "").isEnabled = false
        menu.addItem(.separator())
        menu.addItem(item(tr("Send Files…", "Отправить файлы…"), #selector(pickFiles), "o"))
        menu.addItem(item(tr("Show Animation", "Показать анимацию"), #selector(demo), "d"))
        // Hidden language switch: appears in place of "Show Animation" while ⌥ is held.
        let language = item(Settings.language == .en ? "Русский язык" : "English", #selector(toggleLanguage), "d")
        language.keyEquivalentModifierMask = [.command, .option]
        language.isAlternate = true
        menu.addItem(language)
        menu.addItem(.separator())
        menu.addItem(item(tr("Settings…", "Настройки…"), #selector(openSettings), ","))
        menu.addItem(.separator())
        menu.addItem(item(tr("Quit TeleDrop", "Выйти из TeleDrop"), #selector(quit), "q"))
        model.refreshBotName()
    }

    private func item(_ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func pickFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }
        model.beginDrop()
        model.send(panel.urls)
    }

    @objc private func demo() { model.demo() }

    @objc private func toggleLanguage() { model.toggleLanguage() }

    @objc private func openSettings() { SetupWindow.shared.show(model: model) }

    /// Opening TeleDrop again (Finder, Spotlight, Launchpad) while it runs shows the settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return false
    }

    private var launchedAtLogin: Bool {
        let event = NSAppleEventManager.shared().currentAppleEvent
        let asLoginItem = event?.eventID == kAEOpenApplication
            && event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        return asLoginItem || ProcessInfo.processInfo.systemUptime < 180
    }

    @objc private func quit() { NSApp.terminate(nil) }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
