import AVFoundation

/// A synthesized supercar engine that revs with upload progress: three gears, the revs climb
/// within each gear and drop at every shift. Generated live, so it follows the progress smoothly.
final class EngineSound {
    static let shared = EngineSound()

    private let engine = AVAudioEngine()
    private let sampleRate = 44_100.0
    private var source: AVAudioSourceNode?
    private var stopWork: DispatchWorkItem?

    // Written on the main thread, read by the audio thread.
    private var targetHz = 38.0
    private var targetGain = 0.0
    private var shiftKick = 0.0

    // Audio-thread state.
    private var hz = 38.0
    private var gain = 0.0
    private var phase = 0.0
    private var whinePhase = 0.0
    private var noise = 0.0
    private var seed: UInt32 = 0x1234_5678
    private var gear = 0

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
        gear = 0
        targetHz = 38
        targetGain = 1
        if !engine.isRunning { try? engine.start() }
    }

    /// 0…1. Revs climb inside each third, and fall back at every gear change.
    func set(progress: Double) {
        guard engine.isRunning else { return }
        let p = max(0, min(1, progress))
        let newGear = min(2, Int(p * 3))
        let inGear = p * 3 - Double(newGear)
        if newGear > gear { shiftKick = 1 }  // pop of the shift
        gear = newGear
        targetHz = 42 + Double(newGear) * 10 + inGear * (95 + Double(newGear) * 20)
    }

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
        // Revs glide (faster when dropping, like a real shift); volume fades in and out.
        let glide = targetHz < hz ? 0.0016 : 0.00045
        hz += (targetHz - hz) * glide
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
        // Turbo/gearbox whine on top.
        s += sin(whinePhase * 2 * .pi) * 0.05 * min(1, hz / 120)
        // Crackle at a gear change.
        if shiftKick > 0.001 {
            s += white * shiftKick * 0.6
            shiftKick *= 0.9994
        }
        return s * gain * 0.16
    }
}
