import Foundation

/// The UI is English. Ukrainian and Russian are tucked away: ⌘L anywhere in the app,
/// the 🌐 badge that appears while ⌥ is held, or ⌥ in the menu bar menu. Order: EN → UK → RU.
enum Lang: String, CaseIterable {
    case en, uk, ru

    var name: String {
        switch self {
        case .en: "English"
        case .ru: "Русский"
        case .uk: "Українська"
        }
    }

    var next: Lang {
        let all = Lang.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}

func tr(_ en: String, _ ru: String, _ uk: String) -> String {
    switch Settings.language {
    case .en: en
    case .ru: ru
    case .uk: uk
    }
}

func filesCount(_ n: Int) -> String {
    tr(n == 1 ? "1 file" : "\(n) files", slavicCount(n, "файл", "файла", "файлов"), slavicCount(n, "файл", "файли", "файлів"))
}

func partsCount(_ n: Int) -> String {
    tr(n == 1 ? "1 part" : "\(n) parts", slavicCount(n, "часть", "части", "частей"), slavicCount(n, "частина", "частини", "частин"))
}

/// Russian and Ukrainian share the plural rules: 1 / 2–4 / 5+ (11–14 are "many").
private func slavicCount(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
    let m10 = n % 10, m100 = n % 100
    let word = m10 == 1 && m100 != 11 ? one : (2...4).contains(m10) && !(12...14).contains(m100) ? few : many
    return "\(n) \(word)"
}
