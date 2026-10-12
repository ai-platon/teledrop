import Foundation

/// Bot credentials used for sending.
struct TGConfig {
    let token: String
    let chatID: String

    static func load() -> TGConfig? {
        Settings.migrateLegacyConfig()
        guard let token = Settings.token, let chat = Settings.chatID else { return nil }
        return TGConfig(token: token, chatID: chat)
    }
}

/// Everything lives in UserDefaults except the bot token, which is kept in a file only this
/// user can read. (A Keychain item would ask for the login password after every app update.)
enum Settings {
    private static let defaults = UserDefaults.standard
    private static let tokenFile: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TeleDrop", isDirectory: true)
        return dir.appendingPathComponent("bot-token")
    }()

    static var token: String? {
        get {
            let value = try? String(contentsOf: tokenFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
            return value?.isEmpty == false ? value : nil
        }
        set {
            guard let newValue else { try? FileManager.default.removeItem(at: tokenFile); return }
            let dir = tokenFile.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                     attributes: [.posixPermissions: 0o700])
            FileManager.default.createFile(atPath: tokenFile.path, contents: Data(newValue.utf8),
                                           attributes: [.posixPermissions: 0o600])
        }
    }

    static var chatID: String? {
        get { defaults.string(forKey: "chatID") }
        set { defaults.set(newValue, forKey: "chatID") }
    }

    /// Display name of the person the bot writes to.
    static var chatName: String? {
        get { defaults.string(forKey: "chatName") }
        set { defaults.set(newValue, forKey: "chatName") }
    }

    static var botName: String? {
        get { defaults.string(forKey: "botName") }
        set { defaults.set(newValue, forKey: "botName") }
    }

    static var language: Lang {
        get { Lang(rawValue: defaults.string(forKey: "language") ?? "") ?? .en }
        set { defaults.set(newValue.rawValue, forKey: "language") }
    }

    static var soundsOn: Bool {
        get { defaults.object(forKey: "sounds") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "sounds") }
    }

    /// Slide the island to the right of Coucou's panel while it is expanded.
    static var avoidCoucou: Bool {
        get { defaults.object(forKey: "avoidCoucou") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "avoidCoucou") }
    }

    static func forgetBot() {
        token = nil
        chatID = nil
        chatName = nil
        botName = nil
    }

    /// Imports TG_TOKEN / TG_CHAT_ID from the tg-send script's config file when no bot is set up yet.
    static func migrateLegacyConfig() {
        let path = NSHomeDirectory() + "/.config/tg-send/config"
        guard token == nil, let text = try? String(contentsOfFile: path, encoding: .utf8) else { return }
        var values: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }
            values[parts[0]] = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }
        guard let t = values["TG_TOKEN"], !t.isEmpty, let c = values["TG_CHAT_ID"], !c.isEmpty else { return }
        token = t
        chatID = c
        log("imported bot from ~/.config/tg-send/config")
    }
}
