#!/usr/bin/env python3
"""Synthesizes TeleDrop's UI sounds into Resources/Sounds/*.wav (44.1 kHz, 16-bit mono).
Every sound is generated here, so the set is TeleDrop's own and stays consistent."""
import math, os, random, struct, wave

RATE = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "Resources", "Sounds")


def tone(f0, f1, dur, attack=0.004, decay=None, harmonics=((1, 1.0),), amp=0.5):
    """A glide from f0 to f1 Hz with an exponential decay envelope."""
    n = int(RATE * dur)
    decay = decay or dur / 4
    out, phase = [], 0.0
    for i in range(n):
        t = i / RATE
        f = f0 * (f1 / f0) ** (t / dur)  # exponential glide sounds natural
        phase += 2 * math.pi * f / RATE
        env = min(1.0, t / attack) * math.exp(-t / decay)
        out.append(amp * env * sum(a * math.sin(phase * h) for h, a in harmonics))
    return out


def bell(f, dur, amp=0.45):
    return tone(f, f, dur, attack=0.002, decay=dur / 3.5, harmonics=((1, 1.0), (2.01, 0.35), (3.02, 0.12)), amp=amp)


def noise(dur, amp=0.15, decay=None, seed=1):
    rnd = random.Random(seed)
    n, decay = int(RATE * dur), decay or dur / 3
    smooth, out = 0.0, []
    for i in range(n):
        smooth += (rnd.uniform(-1, 1) - smooth) * 0.25  # crude low-pass: softer "air"
        out.append(amp * smooth * math.exp(-(i / RATE) / decay))
    return out


def mix(*parts):
    """parts: (start_seconds, samples)"""
    end = max(int(s * RATE) + len(p) for s, p in parts)
    out = [0.0] * end
    for s, p in parts:
        o = int(s * RATE)
        for i, v in enumerate(p):
            out[o + i] += v
    return out


def save(name, samples, gain=0.9):
    peak = max(1e-9, max(abs(v) for v in samples))
    scale = gain / peak if peak > gain else 1.0
    # 3 ms fade-out so nothing clicks at the end
    fade = int(RATE * 0.003)
    for i in range(1, min(fade, len(samples)) + 1):
        samples[-i] *= i / fade
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, v * scale)) * 32767)) for v in samples))


os.makedirs(OUT, exist_ok=True)
# Setup window
save("tap",      mix((0, tone(2300, 2100, 0.03, decay=0.008, amp=0.35)), (0, noise(0.01, 0.08))))
save("next",     mix((0, bell(784, 0.12, 0.35)), (0.06, bell(1175, 0.18, 0.35))))
save("back",     tone(820, 560, 0.09, decay=0.03, harmonics=((1, 1), (2, 0.2)), amp=0.4))
save("open",     mix((0, noise(0.16, 0.25, 0.06, seed=3)), (0, tone(420, 980, 0.16, attack=0.03, decay=0.06, amp=0.25))))
save("paste",    mix((0, tone(1320, 1300, 0.14, decay=0.035, harmonics=((1, 1), (2, 0.45), (3, 0.2)), amp=0.4)),
                     (0, noise(0.012, 0.1))))
save("valid",    mix((0, bell(1047, 0.28)), (0, bell(1568, 0.28, 0.3))))
save("invalid",  tone(330, 245, 0.2, attack=0.006, decay=0.07, harmonics=((1, 1), (2, 0.3)), amp=0.45))
save("found",    mix(*[(i * 0.075, bell(f, 0.35, 0.33)) for i, f in enumerate((1047, 1319, 1568, 2093))]))
save("toggle",   mix((0, tone(1650, 1500, 0.02, decay=0.006, amp=0.35)), (0.004, tone(760, 700, 0.05, decay=0.015, amp=0.3))))
save("language", mix((0, bell(988, 0.14, 0.32)), (0.05, bell(1319, 0.14, 0.32)), (0.1, bell(1976, 0.2, 0.22))))
save("send",     mix((0, tone(600, 1400, 0.12, attack=0.01, decay=0.05, amp=0.3)), (0.02, noise(0.1, 0.12, 0.04, seed=5))))
# Island at the notch
save("peek",     tone(280, 640, 0.13, attack=0.008, decay=0.06, harmonics=((1, 1), (2, 0.15)), amp=0.45))
save("hover",    tone(1050, 1380, 0.06, decay=0.02, amp=0.3))
save("drop",     mix((0, tone(520, 170, 0.12, attack=0.004, decay=0.05, amp=0.5)), (0.07, tone(320, 140, 0.09, decay=0.04, amp=0.3))))
save("sent",     mix((0, bell(1568, 0.25, 0.35)), (0.09, bell(2093, 0.35, 0.3))))
save("error",    mix((0, tone(233, 220, 0.3, attack=0.01, decay=0.1, amp=0.4)), (0, tone(247, 235, 0.3, attack=0.01, decay=0.1, amp=0.25))))
save("close",    tone(620, 300, 0.1, attack=0.006, decay=0.035, amp=0.3))
print("\n".join(sorted(os.listdir(OUT))))


def vibrato(f0, f1, dur, rate=6.0, depth=0.03, amp=0.4, attack=0.06, decay=None):
    """Ghostly wavering glide."""
    n, decay = int(RATE * dur), decay or dur / 2
    out, phase = [], 0.0
    for i in range(n):
        t = i / RATE
        f = f0 * (f1 / f0) ** (t / dur) * (1 + depth * math.sin(2 * math.pi * rate * t))
        phase += 2 * math.pi * f / RATE
        env = min(1.0, t / attack) * math.exp(-t / decay)
        out.append(amp * env * (math.sin(phase) + 0.25 * math.sin(2 * phase)))
    return out


# Halloween
save("boo",    mix((0, vibrato(330, 520, 0.45, amp=0.45)), (0.05, noise(0.35, 0.06, 0.15, seed=9))))
# The long ghost wail (theme switch, island opening): swells in, holds, then a long fade from loud to silent.
def ghost(dur, f0, f1, fade, amp=0.45, attack=0.25, rate=4.5, depth=0.04):
    n = int(RATE * dur)
    out, phase = [], 0.0
    for i in range(n):
        t = i / RATE
        f = f0 * (f1 / f0) ** min(1.0, t / (dur - fade)) * (1 + depth * math.sin(2 * math.pi * rate * t))
        phase += 2 * math.pi * f / RATE
        rise = min(1.0, t / attack)
        left = dur - t
        fall = 1.0 if left > fade else 0.5 - 0.5 * math.cos(math.pi * left / fade)  # smooth high → low
        out.append(amp * rise * fall * (math.sin(phase) + 0.25 * math.sin(2 * phase)))
    return out


def faded_noise(dur, amp, fade, seed):
    out = noise(dur, amp, decay=dur * 10, seed=seed)  # flat, then shaped like the wail
    for i in range(len(out)):
        left = dur - i / RATE
        if left < fade:
            out[i] *= 0.5 - 0.5 * math.cos(math.pi * left / fade)
        out[i] *= min(1.0, i / (RATE * 0.25))
    return out


save("boolong", mix((0, ghost(1.8, 300, 540, fade=1.0)), (0.1, faded_noise(1.7, 0.05, 1.0, seed=9))))
save("spooky", mix(*[(i * 0.11, bell(f, 0.5, 0.3)) for i, f in enumerate((784, 932, 1109, 1568))]))
print("halloween sounds ok")
