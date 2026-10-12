import Foundation

/// The UI is English. Russian is a hidden option: ⌥-click the version in Settings,
/// or hold ⌥ while the menu bar menu is open.
enum Lang: String { case en, ru }

func tr(_ en: String, _ ru: String) -> String { Settings.language == .ru ? ru : en }

func filesCount(_ n: Int) -> String {
    tr(n == 1 ? "1 file" : "\(n) files", ruCount(n, "файл", "файла", "файлов"))
}

func partsCount(_ n: Int) -> String {
    tr(n == 1 ? "1 part" : "\(n) parts", ruCount(n, "часть", "части", "частей"))
}

private func ruCount(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
    let m10 = n % 10, m100 = n % 100
    let word = m10 == 1 && m100 != 11 ? one : (2...4).contains(m10) && !(12...14).contains(m100) ? few : many
    return "\(n) \(word)"
}
