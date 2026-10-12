import Foundation

struct UploadError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

// MARK: - Bot API

enum Telegram {
    /// Bots may upload up to 50 MB; keep a margin for the multipart envelope.
    static let partLimit = 49 * 1024 * 1024

    struct Bot { let username: String; let name: String }
    struct Chat { let id: String; let name: String }

    /// Finds a bot token anywhere in a text — e.g. the whole BotFather message pasted at once.
    static func extractToken(_ text: String) -> String? {
        guard let range = text.range(of: #"\d{5,}:[A-Za-z0-9_-]{30,}"#, options: .regularExpression) else { return nil }
        return String(text[range])
    }

    static func isTokenShaped(_ token: String) -> Bool {
        token.range(of: #"^\d{5,}:[A-Za-z0-9_-]{30,}$"#, options: .regularExpression) != nil
    }

    static func getMe(_ token: String) async throws -> Bot {
        let result = try await call(token, "getMe") as? [String: Any]
        return Bot(username: result?["username"] as? String ?? "", name: result?["first_name"] as? String ?? "")
    }

    /// The most recent private chat that wrote to the bot — the user pressing Start during setup.
    static func latestPrivateChat(_ token: String) async throws -> Chat? {
        let updates = try await call(token, "getUpdates") as? [[String: Any]] ?? []
        for update in updates.reversed() {
            guard let message = update["message"] as? [String: Any],
                  let chat = message["chat"] as? [String: Any],
                  chat["type"] as? String == "private", let id = chat["id"] else { continue }
            let name = [chat["first_name"], chat["last_name"]].compactMap { $0 as? String }.joined(separator: " ")
            return Chat(id: "\(id)", name: name.isEmpty ? (chat["username"] as? String ?? "") : name)
        }
        return nil
    }

    static func sendMessage(_ text: String, cfg: TGConfig) async throws {
        _ = try await call(cfg.token, "sendMessage", ["chat_id": cfg.chatID, "text": text])
    }

    /// Uploads one file as a document, retrying when Telegram asks to slow down.
    /// `reading` reports how much of the file has been read (slow when it has to come down from iCloud),
    /// `progress` how much has been uploaded.
    static func sendDocument(_ file: URL, caption: String?, cfg: TGConfig,
                             reading: @escaping (Double) -> Void = { _ in },
                             progress: @escaping (Double) -> Void) async throws {
        let boundary = "TeleDrop-\(UUID().uuidString)"
        let body = try writeBody(file, caption: caption, chatID: cfg.chatID, boundary: boundary, reading: reading)
        defer { try? FileManager.default.removeItem(at: body) }

        var request = URLRequest(url: URL(string: "https://api.telegram.org/bot\(cfg.token)/sendDocument")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 600
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        for attempt in 0..<3 {
            let (data, _) = try await URLSession.shared.upload(for: request, fromFile: body,
                                                               delegate: ProgressDelegate(progress))
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            if json?["ok"] as? Bool == true { return }
            if attempt < 2, let wait = (json?["parameters"] as? [String: Any])?["retry_after"] as? Int {
                try await Task.sleep(for: .seconds(wait))
                continue
            }
            throw UploadError(friendly(json?["description"] as? String))
        }
    }

    static func friendly(_ error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost: return tr("No internet connection", "Нет интернета", "Немає інтернету")
            case .timedOut: return tr("Telegram didn't answer in time", "Telegram не ответил вовремя", "Telegram не відповів вчасно")
            default: break
            }
        }
        return error.localizedDescription
    }

    private static func friendly(_ description: String?) -> String {
        guard let description else { return tr("Unknown Telegram error", "Неизвестная ошибка Telegram", "Невідома помилка Telegram") }
        if description.contains("chat not found") { return tr("Press Start in your bot in Telegram", "Нажми Start у бота в Telegram", "Натисни Start у бота в Telegram") }
        if description.contains("Unauthorized") || description.contains("Not Found") { return tr("That token didn't work", "Токен не подошёл", "Токен не підійшов") }
        if description.contains("blocked by the user") { return tr("The bot is blocked — unblock it in Telegram", "Бот заблокирован — разблокируй его в Telegram", "Бота заблоковано — розблокуй його в Telegram") }
        if description.contains("too big") { return tr("File is too big for Telegram", "Файл слишком большой для Telegram", "Файл завеликий для Telegram") }
        return description
    }

    private static func call(_ token: String, _ method: String, _ params: [String: String] = [:]) async throws -> Any {
        guard isTokenShaped(token) else { throw UploadError(tr("That token didn't work", "Токен не подошёл", "Токен не підійшов")) }
        var components = URLComponents(string: "https://api.telegram.org/bot\(token)/\(method)")!
        if !params.isEmpty { components.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) } }
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard json?["ok"] as? Bool == true, let result = json?["result"] else {
            throw UploadError(friendly(json?["description"] as? String))
        }
        return result
    }

    private static func writeBody(_ file: URL, caption: String?, chatID: String, boundary: String,
                                  reading: (Double) -> Void) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(boundary)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let out = try FileHandle(forWritingTo: url)
        defer { try? out.close() }
        func field(_ name: String, _ value: String) {
            out.write(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        }

        field("chat_id", chatID)
        if let caption { field("caption", caption) }
        let name = file.lastPathComponent.replacingOccurrences(of: "\"", with: "'")
        out.write(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"document\"; filename=\"\(name)\"\r\n".utf8))
        out.write(Data("Content-Type: application/octet-stream\r\n\r\n".utf8))
        let input = try FileHandle(forReadingFrom: file)
        defer { try? input.close() }
        let total = Double(max(1, Packer.size(of: file)))
        var done = 0.0
        while let chunk = try input.read(upToCount: 1 << 20), !chunk.isEmpty {
            out.write(chunk)
            done += Double(chunk.count)
            reading(done / total)
        }
        out.write(Data("\r\n--\(boundary)--\r\n".utf8))
        return url
    }
}

private final class ProgressDelegate: NSObject, URLSessionTaskDelegate {
    let onProgress: (Double) -> Void
    init(_ onProgress: @escaping (Double) -> Void) { self.onProgress = onProgress }

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard totalBytesExpectedToSend > 0 else { return }
        onProgress(Double(totalBytesSent) / Double(totalBytesExpectedToSend))
    }
}

// MARK: - Packing

/// What actually gets uploaded for one dropped item.
struct PreparedFile {
    let parts: [URL]
    let caption: String?
    /// Working folder to delete afterwards.
    let workDir: URL?
}

/// Folders and files over 49 MB are zipped. A zip that is still too big is cut into
/// name.zip.001, .002, … — 7-Zip, The Unarchiver and Keka open these, or `cat name.zip.* > name.zip`.
enum Packer {
    static func prepare(_ file: URL, status: (String) -> Void) throws -> PreparedFile {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: file.path, isDirectory: &isDir) else {
            throw UploadError(tr("File not found", "Файл не найден", "Файл не знайдено"))
        }
        if !isDir.boolValue, size(of: file) <= Telegram.partLimit {
            return PreparedFile(parts: [file], caption: nil, workDir: nil)
        }

        status(isDir.boolValue ? tr("zipping folder…", "упаковываю папку…", "пакую папку…") : tr("over 49 MB — zipping…", "больше 49 МБ — упаковываю в zip…", "понад 49 МБ — пакую в zip…"))
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("TeleDrop-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let zip = work.appendingPathComponent(file.lastPathComponent + ".zip")
        // Folders keep their own name inside the zip; a single file goes in on its own.
        // --norsrc leaves out macOS-only "._name" metadata files.
        let keepParent = isDir.boolValue ? ["--keepParent"] : []
        try run("/usr/bin/ditto", ["-c", "-k", "--norsrc"] + keepParent + [file.path, zip.path])
        if size(of: zip) <= Telegram.partLimit {
            return PreparedFile(parts: [zip], caption: nil, workDir: work)
        }

        status(tr("splitting into 49 MB parts…", "режу на части по 49 МБ…", "ріжу на частини по 49 МБ…"))
        let parts = try split(zip)
        try? FileManager.default.removeItem(at: zip)
        let name = zip.lastPathComponent
        let caption = tr("""
        📦 \(name) — \(partsCount(parts.count)).
        Open the first part with 7-Zip, The Unarchiver or Keka, or join them on a Mac:
        cat "\(name)".* > "\(name)"
        """, """
        📦 \(name) — \(partsCount(parts.count)).
        Открой первую часть в 7-Zip, The Unarchiver или Keka, или склей на Mac:
        cat "\(name)".* > "\(name)"
        """, """
        📦 \(name) — \(partsCount(parts.count)).
        Відкрий першу частину в 7-Zip, The Unarchiver або Keka, або склей на Mac:
        cat "\(name)".* > "\(name)"
        """)
        return PreparedFile(parts: parts, caption: caption, workDir: work)
    }

    static func size(of url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }

    private static func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw UploadError(tr("Couldn't zip the file", "Не удалось упаковать файл", "Не вдалося запакувати файл")) }
    }

    private static func split(_ file: URL) throws -> [URL] {
        let input = try FileHandle(forReadingFrom: file)
        defer { try? input.close() }
        var parts: [URL] = []
        while true {
            let part = file.deletingLastPathComponent()
                .appendingPathComponent(file.lastPathComponent + String(format: ".%03d", parts.count + 1))
            FileManager.default.createFile(atPath: part.path, contents: nil)
            let out = try FileHandle(forWritingTo: part)
            var written = 0
            while written < Telegram.partLimit,
                  let chunk = try input.read(upToCount: min(1 << 20, Telegram.partLimit - written)), !chunk.isEmpty {
                out.write(chunk)
                written += chunk.count
            }
            try out.close()
            if written == 0 {
                try? FileManager.default.removeItem(at: part)
                break
            }
            parts.append(part)
            if written < Telegram.partLimit { break }
        }
        return parts
    }
}
