import AVFoundation

/// A synthesized supercar engine that revs with upload progress: one long, smooth pull from idle
/// to redline, getting louder as it goes. Generated live, so it follows the progress smoothly.
final class EngineSound {
    static let shared = EngineSound()

    private let engine = AVAudioEngine()
    private let sampleRate = 44_100.0
    private var source: AVAudioSourceNode?
    private var stopWork: DispatchWorkItem?

    // Written on the main thread, read by the audio thread.
    private var targetHz = 38.0
    private var targetGain = 0.0

    // Audio-thread state.
    private var hz = 38.0
    private var gain = 0.0
    private var phase = 0.0
    private var whinePhase = 0.0
    private var noise = 0.0
    private var seed: UInt32 = 0x1234_5678

    private init() {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let node = AVAudioSourceNode(format: format) { [unowned self] _, _, frameCount, bufferList in
            let out = UnsafeMutableAudioBufferListPointer(bufferList)[0].mData!.assumingMemoryBound(to: Float.self)
            for i in 0..<Int(frameCount) { out[i] = Float(self.nextSample()) }
            return noErr
        }
        source = node
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.prepare()
    }

    func start() {
        guard Settings.soundsOn else { return }
        stopWork?.cancel()
        targetHz = 38
        targetGain = Self.gain(at: 0)
        if !engine.isRunning { try? engine.start() }
    }

    /// 0…1: revs and volume both climb with the upload, no gear changes.
    func set(progress: Double) {
        guard engine.isRunning else { return }
        let p = max(0, min(1, progress))
        targetHz = 40 + p * 180
        targetGain = Self.gain(at: p)
    }

    /// Quiet idle at the start, full volume at 100%.
    private static func gain(at progress: Double) -> Double { 0.12 + 0.88 * progress * progress }

    /// Lets the engine wind down, then frees the audio hardware.
    func stop() {
        targetGain = 0
        targetHz = 30
        stopWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.targetGain == 0 else { return }
            self.engine.stop()
        }
        stopWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    private func nextSample() -> Double {
        // Revs and volume glide toward their targets so the pull is smooth.
        hz += (targetHz - hz) * 0.0005
        gain += (targetGain - gain) * 0.0007

        phase += hz / sampleRate
        if phase >= 1 { phase -= 1 }
        whinePhase += hz * 7.5 / sampleRate
        if whinePhase >= 1 { whinePhase -= 1 }

        let p = phase * 2 * .pi
        // Firing pulses: a few harmonics, with a half-rate wobble that gives a V8-ish burble.
        var s = sin(p) * 0.55 + sin(2 * p) * 0.35 + sin(3 * p) * 0.22 + sin(4 * p) * 0.12 + sin(6 * p) * 0.06
        s *= 0.78 + 0.22 * sin(p * 0.5)
        // Exhaust rumble: low-passed noise, louder at high revs.
        seed = seed &* 1_664_525 &+ 1_013_904_223
        let white = Double(seed) / Double(UInt32.max) * 2 - 1
        noise += (white - noise) * 0.08
        s += noise * (0.25 + hz / 300)
        // Turbo whine on top.
        s += sin(whinePhase * 2 * .pi) * 0.05 * min(1, hz / 120)
        return s * gain * 0.16
    }
}
