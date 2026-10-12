import AppKit

/// TeleDrop's own UI sounds (Resources/Sounds, made by Tools/make_sounds.py).
enum Sfx: String {
    // Setup window
    case tap, next, back, open, paste, valid, invalid, found, toggle, language, send
    // Island at the notch
    case peek, hover, drop, sent, error, close
    // Halloween
    case boo, spooky

    private static var cache: [Sfx: NSSound] = [:]

    func play(volume: Float = 0.45) {
        guard Settings.soundsOn else { return }
        if Self.cache[self] == nil,
           let url = Bundle.main.url(forResource: rawValue, withExtension: "wav", subdirectory: "Sounds") {
            Self.cache[self] = NSSound(contentsOf: url, byReference: true)
        }
        // A copy lets the same sound overlap itself (fast clicks).
        guard let sound = Self.cache[self]?.copy() as? NSSound else { return }
        sound.volume = volume
        sound.play()
    }
}
