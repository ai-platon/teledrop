// Logic tests: token parsing, plurals in all languages, language order, Halloween season, file packing.
// Run: Tests/run_all.sh (builds this together with the app's sources, without main.swift).
import Foundation

var failures = 0
func check(_ ok: Bool, _ name: String) {
    print((ok ? "  ✅ " : "  ❌ ") + name)
    if !ok { failures += 1 }
}

print("Tokens")
let good = "123456789:AAHdqTcvCH1vGWJxfSeofSAs0K5PALDsaw"
check(Telegram.isTokenShaped(good), "a real-looking token is accepted")
check(!Telegram.isTokenShaped("hello world"), "random text is rejected")
check(!Telegram.isTokenShaped("123:short"), "a too-short token is rejected")
let botFather = "Done! Congratulations on your new bot.\nUse this token to access the HTTP API:\n\(good)\nKeep your token secure"
check(Telegram.extractToken(botFather) == good, "token is found inside the whole BotFather message")
check(Telegram.extractToken("nothing here") == nil, "no token → nil")

print("Languages")
check(Lang.en.next == .uk && Lang.uk.next == .ru && Lang.ru.next == .en, "⌘L order is EN → UK → RU → EN")
let saved = Settings.language
let expected: [Lang: [String]] = [
    .en: ["1 file", "3 files", "5 files", "21 files", "2 parts"],
    .uk: ["1 файл", "3 файли", "5 файлів", "21 файл", "2 частини"],
    .ru: ["1 файл", "3 файла", "5 файлов", "21 файл", "2 части"],
]
for lang in Lang.allCases {
    Settings.language = lang
    let got = [filesCount(1), filesCount(3), filesCount(5), filesCount(21), partsCount(2)]
    check(got == expected[lang]!, "plurals in \(lang.rawValue): \(got.joined(separator: ", "))")
    check(!tr("Sent", "Отправлено", "Надіслано").isEmpty, "tr() returns text in \(lang.rawValue)")
}
Settings.language = saved

print("Halloween season")
func day(_ m: Int, _ d: Int) -> Date { Calendar.current.date(from: DateComponents(year: 2026, month: m, day: d))! }
check(!Theme.inSeason(day(10, 19)), "Oct 19 → classic")
check(Theme.inSeason(day(10, 20)), "Oct 20 → Halloween")
check(Theme.inSeason(day(10, 31)), "Oct 31 → Halloween")
check(Theme.inSeason(day(11, 5)), "Nov 5 → Halloween")
check(!Theme.inSeason(day(11, 6)), "Nov 6 → classic")
check(!Theme.inSeason(day(3, 1)), "March → classic")

print("Island layout on every MacBook screen")
// (name, width in points at default scaling, has notch). Coucou's open panel ends ~318 pt right of center.
let screens: [(String, CGFloat, Bool)] = [
    ("Air 13\" (M2–M4)", 1470, true), ("Air 13\" larger text", 1280, true), ("Air 13\" more space", 1710, true),
    ("Pro 14\"", 1512, true), ("Air 15\"", 1710, true), ("Pro 16\"", 1728, true),
    ("Pro 13\" / old Air (no notch)", 1440, false), ("Air 13\" M1 smallest", 1280, false),
]
for (name, width, notch) in screens {
    let mid = width / 2
    let notchRight = mid + (notch ? 92 : 100)
    var cases: [(String, CGFloat)] = [("beside notch", notchRight + 2), ("beside Coucou pills", notchRight + 75 + 10)]
    cases.append(("beside open Coucou", mid + 318 + 12))
    for (label, anchor) in cases {
        let p = Layout.beside(anchor: anchor, screenMaxX: width)
        let fits = p.left + p.maxWidth <= width - Layout.margin + 0.5
        let clear = p.left >= anchor - 0.5 || p.maxWidth == Layout.minWidth
        check(fits && clear && p.maxWidth >= Layout.minWidth,
              "\(name), \(label): island \(Int(p.maxWidth)) pt wide, fits on screen, doesn't cover Coucou")
    }
    let centered = Layout.centered(screenWidth: width)
    check(centered <= width - 2 * Layout.margin, "\(name), no Coucou: centered island \(Int(centered)) pt fits")
}

print("Packing big files")
let fm = FileManager.default
let dir = fm.temporaryDirectory.appendingPathComponent("teledrop-tests-\(UUID().uuidString)")
try! fm.createDirectory(at: dir, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: dir) }

let small = dir.appendingPathComponent("small.txt")
try! Data("hello".utf8).write(to: small)
let p1 = try! Packer.prepare(small) { _ in }
check(p1.parts == [small] && p1.caption == nil, "a small file is sent as is")

let folder = dir.appendingPathComponent("folder")
try! fm.createDirectory(at: folder, withIntermediateDirectories: true)
try! Data("a".utf8).write(to: folder.appendingPathComponent("a.txt"))
let p2 = try! Packer.prepare(folder) { _ in }
check(p2.parts.count == 1 && p2.parts[0].pathExtension == "zip", "a folder becomes one zip")

let zeros = dir.appendingPathComponent("zeros.bin")
try! Data(count: 120 * 1024 * 1024).write(to: zeros)
let p3 = try! Packer.prepare(zeros) { _ in }
check(p3.parts.count == 1 && Packer.size(of: p3.parts[0]) < Telegram.partLimit, "120 MB of zeros → one small zip")

let random = dir.appendingPathComponent("random.bin")
var bytes = Data(count: 120 * 1024 * 1024)
bytes.withUnsafeMutableBytes { _ = SecRandomCopyBytes(kSecRandomDefault, $0.count, $0.baseAddress!) }
try! bytes.write(to: random)
let p4 = try! Packer.prepare(random) { _ in }
check(p4.parts.count == 3, "120 MB of random data → 3 parts (\(p4.parts.map { Packer.size(of: $0) / 1_048_576 }) MB)")
check(p4.parts.allSatisfy { Packer.size(of: $0) <= Telegram.partLimit }, "every part fits the 49 MB limit")
check(p4.caption?.contains("cat ") == true, "the first part's caption explains how to join")
// Join the parts back and compare with the original.
let joined = dir.appendingPathComponent("joined.zip")
fm.createFile(atPath: joined.path, contents: nil)
let out = try! FileHandle(forWritingTo: joined)
for part in p4.parts { out.write(try! Data(contentsOf: part)) }
try! out.close()
let unzip = Process()
unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
unzip.arguments = ["-x", "-k", joined.path, dir.appendingPathComponent("out").path]
try! unzip.run(); unzip.waitUntilExit()
let listing = Process()
let pipe = Pipe()
listing.executableURL = URL(fileURLWithPath: "/usr/bin/zipinfo")
listing.arguments = ["-1", joined.path]
listing.standardOutput = pipe
try! listing.run(); listing.waitUntilExit()
let entries = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)!.split(separator: "\n")
check(entries == ["random.bin"], "the zip holds just the file, no parent folder or ._ files (\(entries))")
let restored = dir.appendingPathComponent("out/random.bin")
check(unzip.terminationStatus == 0 && (try? Data(contentsOf: restored)) == bytes, "joined parts unzip to the exact original file")
for p in [p2, p3, p4] { p.workDir.map { try? fm.removeItem(at: $0) } }

print(failures == 0 ? "\nAll logic tests passed." : "\n\(failures) logic test(s) FAILED.")
exit(failures == 0 ? 0 : 1)
