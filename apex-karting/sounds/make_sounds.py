#!/usr/bin/env python3
"""Synthesises the game's original sound set (no samples, no recordings).

    python3 sounds/make_sounds.py              # writes every sounds/*.ogg (needs numpy, scipy, ffmpeg)
    python3 sounds/make_sounds.py engine flag  # only those

Upload the .ogg files in Roblox Studio (Asset Manager > Import / Bulk Import)
and paste each id into Config.Audio:

    engine_loop.ogg  -> EngineSoundId   (looped; pitched from the engine rpm, Config.Audio EngineRpm*)
    skid_loop.ogg    -> SkidSoundId     (looped, fades with tyre slip)
    offroad_loop.ogg -> OffroadSoundId  (looped: wheels on gravel, grass or water)
    kerb_loop.ogg    -> KerbSoundId     (looped: wheels on the kerbs, rate follows speed)
    bump.ogg         -> BumpSoundId     (kart-to-kart contact)
    beep.ogg         -> BeepSoundId     (each start light)
    go.ogg           -> GoSoundId       (lights out)
    lap.ogg          -> LapSoundId      (a lap completed)
    best.ogg         -> BestSoundId     (personal best / fastest lap / track record)
    warning.ogg      -> WarningSoundId  (track-limits warning)
    penalty.ogg      -> PenaltySoundId  (lap deleted / time penalty)
    flag.ogg         -> FlagSoundId     (qualifying starts / chequered flag)
    finish.ogg       -> FinishSoundId   (your chequered flag in the race)
    podium.ogg       -> PodiumSoundId   (results and podium)
    click.ogg        -> ClickSoundId    (buttons)
    crowd_loop.ogg   -> CrowdSoundId    (looped at every grandstand)

Every sound is made from oscillators, noise and filters below, so the set is
free to use. The loops are an exact number of engine cycles / have their
ends cross-faded, so they repeat without a click.
"""
import os
import subprocess
import tempfile
import wave

import numpy as np
from scipy import signal

RATE = 44100
OUT = os.path.dirname(os.path.abspath(__file__))
rng = np.random.default_rng(270)


def t_axis(seconds):
    return np.arange(int(seconds * RATE)) / RATE


def bandpass(x, lo, hi, order=2):
    sos = signal.butter(order, [lo, hi], btype="bandpass", fs=RATE, output="sos")
    return signal.sosfilt(sos, x)


def lowpass(x, hz, order=2):
    sos = signal.butter(order, hz, btype="lowpass", fs=RATE, output="sos")
    return signal.sosfilt(sos, x)


def highpass(x, hz, order=2):
    sos = signal.butter(order, hz, btype="highpass", fs=RATE, output="sos")
    return signal.sosfilt(sos, x)


def loop_filter(x, fn, pad=0.5):
    """Filter a loop as if it repeated: run it over three copies, keep the middle."""
    n = len(x)
    y = fn(np.concatenate([x, x, x]))
    return y[n:2 * n]


def crossfade_loop(x, fade):
    """Make the end of x blend into its start (for noise-based loops)."""
    n = int(fade * RATE)
    head, body = x[:n], x[n:]
    ramp = np.linspace(0, 1, n)
    body[-n:] = body[-n:] * (1 - ramp) + head * ramp
    return body


def normalise(x, peak=0.89):
    m = np.max(np.abs(x))
    return x if m == 0 else x * (peak / m)


def envelope(n, attack, release, hold=None):
    """Linear attack, exponential release (seconds)."""
    t = np.arange(n) / RATE
    env = np.minimum(1, t / max(attack, 1e-4))
    start = hold if hold is not None else attack
    tail = np.where(t > start, np.exp(-(t - start) / max(release, 1e-4)), 1)
    return env * tail


def write(name, x, loop=False):
    if not loop:
        # a short fade so a one-shot never ends on a click
        n = int(0.015 * RATE)
        x = x.copy()
        x[-n:] *= np.linspace(1, 0, n)
    x = np.clip(x, -1, 1)
    pcm = (x * 32767).astype(np.int16)
    with tempfile.TemporaryDirectory() as tmp:
        wav = os.path.join(tmp, "x.wav")
        with wave.open(wav, "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(RATE)
            w.writeframes(pcm.tobytes())
        out = os.path.join(OUT, name)
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-c:a", "libvorbis", "-q:a", "6", out], check=True)
    print("wrote", name, "%.2f s" % (len(x) / RATE))


# --------------------------------------------------------------------------
# Engine: the game's rental kart, a ~15 hp single-cylinder four-stroke
# (GX390 class, one gear, centrifugal clutch, chain drive), recorded at a
# steady 3000 rpm. One firing every two turns. Each firing is a sharp exhaust
# pulse ringing through the pipe and muffler resonances (most of the energy
# between 150 Hz and 1.5 kHz: the first version sat below 150 Hz and a phone
# speaker could not play it, so the engine was all but silent next to the
# crowd and the tyres). On top: the chain whine (12-tooth sprocket, 12x the
# crank speed), valve clatter, intake roar and a little cycle-to-cycle
# variation. The game pitches it to the engine rpm (Config.Audio EngineRpm*).
# --------------------------------------------------------------------------
ENGINE_RPM = 3000


def engine():
    r = np.random.default_rng(3000)
    crank_hz = ENGINE_RPM / 60  # 50 turns a second
    fire_hz = crank_hz / 2  # 25 firings a second
    cycles = 50  # 2 s, a whole number of cycles so the loop is seamless
    period = int(round(RATE / fire_hz))
    n = period * cycles
    x = np.zeros(n)
    span = period * 2
    k = np.arange(span) / RATE
    # pipe / muffler resonances: (Hz, amplitude, decay per second)
    modes = [(85, 1.0, 38), (172, 0.9, 60), (330, 0.75, 85), (520, 0.6, 110), (790, 0.45, 150), (1180, 0.3, 210), (1750, 0.16, 300)]
    for c in range(cycles):
        jit = 0.85 + 0.3 * r.random()
        pulse = np.zeros(span)
        for f, amp, d in modes:
            ph = r.uniform(0, 0.4)
            pulse += amp * np.exp(-k * d) * np.sin(2 * np.pi * f * (1 + 0.01 * (r.random() - 0.5)) * k + ph)
        # the crack of the exhaust valve opening: a very short broadband pop
        m = int(0.004 * RATE)
        pop = np.zeros(span)
        pop[:m] = r.standard_normal(m) * np.exp(-np.arange(m) / RATE * 900)
        pulse += 0.5 * bandpass(pop, 250, 3500)
        idx = (c * period + np.arange(span)) % n
        np.add.at(x, idx, pulse * jit)
    t = np.arange(n) / RATE
    cyc = (t * fire_hz) % 1.0
    # valve clatter twice a cycle, intake roar on the intake stroke
    clatter = r.standard_normal(n) * (np.exp(-((cyc - 0.35) % 1.0) * 60) + 0.7 * np.exp(-((cyc - 0.6) % 1.0) * 60))
    clatter = loop_filter(clatter, lambda v: bandpass(v, 1300, 4200))
    intake = r.standard_normal(n) * (0.4 + 0.6 * np.sin(np.pi * np.clip((cyc - 0.5) * 2, 0, 1)) ** 2)
    intake = loop_filter(intake, lambda v: bandpass(v, 220, 650))
    # chain whine: 12 teeth a turn on the engine sprocket, wavering a touch
    tooth = crank_hz * 12  # 600 Hz at 3000 rpm
    whine = np.sin(2 * np.pi * tooth * t) + 0.35 * np.sin(2 * np.pi * 2 * tooth * t + 0.5)
    whine *= 0.75 + 0.25 * np.sin(2 * np.pi * fire_hz * t)
    rumble = np.sin(2 * np.pi * fire_hz * t) + 0.5 * np.sin(2 * np.pi * crank_hz * t + 0.8)
    x = normalise(x, 1.0) + 0.10 * normalise(clatter) + 0.16 * normalise(intake) + 0.07 * whine + 0.18 * rumble
    x = loop_filter(x, lambda v: highpass(v, 40))
    # a pushed muffler: soft saturation adds the bark
    x = np.tanh(normalise(x, 1.0) * 2.0)
    write("engine_loop.ogg", normalise(x, 0.85), loop=True)


# --------------------------------------------------------------------------
# Tyre skid: rubber scrubbing on asphalt. Band-passed noise with a wavering
# squeal tone on top (slick tyres squeal less than road tyres).
# --------------------------------------------------------------------------
def skid():
    seconds = 2.6
    t = t_axis(seconds)
    noise = rng.standard_normal(len(t))
    scrub = bandpass(noise, 500, 2600, 3)
    scrub *= 0.75 + 0.25 * lowpass(rng.standard_normal(len(t)), 6) * 8
    wobble = 1 + 0.04 * np.sin(2 * np.pi * 3.1 * t) + 0.02 * np.sin(2 * np.pi * 7.3 * t + 1)
    phase = 2 * np.pi * np.cumsum(1050 * wobble) / RATE
    squeal = np.sin(phase) + 0.35 * np.sin(2 * phase + 0.3) + 0.15 * np.sin(3 * phase)
    squeal *= 0.6 + 0.4 * np.abs(lowpass(rng.standard_normal(len(t)), 4)) * 6
    x = 0.8 * normalise(scrub) + 0.32 * normalise(squeal)
    x = crossfade_loop(x, 0.5)
    write("skid_loop.ogg", normalise(x, 0.7), loop=True)


# --------------------------------------------------------------------------
# Bump: two plastic bumpers knocking together - a hollow low thud and a
# short bright knock, over in a fifth of a second.
# --------------------------------------------------------------------------
def bump():
    t = t_axis(0.35)
    n = len(t)
    thud = np.sin(2 * np.pi * (120 - 50 * t) * t) * np.exp(-t * 22)
    body = sum(a * np.sin(2 * np.pi * f * t + p) * np.exp(-t * d)
               for a, f, p, d in [(0.6, 310, 0.0, 40), (0.4, 467, 0.7, 55), (0.3, 720, 1.4, 70), (0.2, 1130, 0.2, 90)])
    knock = bandpass(rng.standard_normal(n), 1200, 5000) * np.exp(-t * 140)
    # the hollow plastic knock carries it (a phone speaker cannot play the thud)
    x = thud * 0.5 + body * 1.2 + knock * 1.1
    x *= envelope(n, 0.001, 1.0)
    write("bump.ogg", normalise(np.tanh(normalise(x, 1.0) * 1.5), 0.92))


def tone(freq, seconds, attack=0.004, release=0.06, hold=None, harmonics=((1, 1.0), (2, 0.25), (3, 0.12))):
    t = t_axis(seconds)
    x = sum(a * np.sin(2 * np.pi * freq * h * t) for h, a in harmonics)
    return x * envelope(len(t), attack, release, hold)


# Beep: a short clean electronic tone for each red light.
def beep():
    x = tone(880, 0.22, release=0.03, hold=0.12)
    write("beep.ogg", normalise(x, 0.7))


# Go: higher, longer and brighter, so lights-out stands out.
def go():
    x = tone(1320, 0.6, release=0.12, hold=0.32, harmonics=((1, 1.0), (2, 0.35), (3, 0.2), (4, 0.08)))
    x += 0.5 * tone(1980, 0.6, release=0.12, hold=0.32)
    write("go.ogg", normalise(x, 0.75))


# Lap: a quick rising two-note chime.
def lap():
    a = tone(784, 0.18, release=0.08, hold=0.06, harmonics=((1, 1.0), (2, 0.4), (4, 0.1)))
    b = tone(1175, 0.42, release=0.18, hold=0.08, harmonics=((1, 1.0), (2, 0.4), (4, 0.1)))
    gap = int(0.11 * RATE)
    x = np.zeros(gap + len(b))
    x[:len(a)] += a
    x[gap:] += b
    write("lap.ogg", normalise(x, 0.7))


# Finish: a short bright fanfare (rising arpeggio and a held chord) with a
# touch of brass-like brightness (stacked harmonics and a slow vibrato).
def finish():
    def brass(freq, seconds, hold):
        t = t_axis(seconds)
        vib = 1 + 0.004 * np.sin(2 * np.pi * 5.5 * t) * np.minimum(1, t / 0.3)
        phase = 2 * np.pi * np.cumsum(freq * vib) / RATE
        x = sum((0.8 ** h) * np.sin(h * phase) for h in range(1, 9))
        return lowpass(x, 3500) * envelope(len(t), 0.02, 0.25, hold)

    notes = [(523.25, 0.0), (659.25, 0.14), (783.99, 0.28)]
    total = 1.9
    x = np.zeros(int(total * RATE))
    for f, start in notes:
        s = brass(f, 0.5, 0.12)
        i = int(start * RATE)
        x[i:i + len(s)] += s
    # held chord
    i = int(0.46 * RATE)
    for f in (523.25, 659.25, 783.99, 1046.5):
        s = brass(f, total - 0.46, 0.8) * 0.6
        x[i:i + len(s)] += s
    write("finish.ogg", normalise(np.tanh(x * 0.6), 0.8))


# Click: a tiny tick for buttons.
def click():
    t = t_axis(0.05)
    x = bandpass(rng.standard_normal(len(t)), 2000, 7000) * np.exp(-t * 400)
    x += 0.5 * np.sin(2 * np.pi * 1800 * t) * np.exp(-t * 250)
    write("click.ogg", normalise(x, 0.6))


# --------------------------------------------------------------------------
# Crowd: a grandstand murmur - many soft voice-like formant bursts over a
# bed of filtered noise, with the odd distant cheer. Loops (6 s).
# --------------------------------------------------------------------------
def crowd():
    seconds = 6.5
    n = int(seconds * RATE)
    t = np.arange(n) / RATE
    bed = bandpass(rng.standard_normal(n), 250, 2500, 2) * 0.5
    x = bed.copy()
    formants = [(500, 1500), (700, 1200), (400, 2000), (600, 1700), (350, 2300)]
    for _ in range(260):
        length = rng.uniform(0.15, 0.55)
        m = int(length * RATE)
        start = rng.integers(0, n - m)
        f1, f2 = formants[rng.integers(len(formants))]
        pitch = rng.uniform(110, 260)
        k = np.arange(m) / RATE
        voice = signal.sawtooth(2 * np.pi * pitch * k * (1 + 0.03 * np.sin(2 * np.pi * 4 * k)))
        voice = bandpass(voice, f1 * 0.7, f1 * 1.3) + 0.6 * bandpass(voice, f2 * 0.8, f2 * 1.2)
        env = np.sin(np.pi * k / length) ** 2
        x[start:start + m] += voice * env * rng.uniform(0.05, 0.18)
    # two swells of cheering
    for centre in (1.8, 4.6):
        swell = np.exp(-((t - centre) / 0.6) ** 2)
        x += bandpass(rng.standard_normal(n), 600, 3500) * swell * 0.35
    x = crossfade_loop(lowpass(x, 5000), 0.5)
    write("crowd_loop.ogg", normalise(x, 0.6), loop=True)


# --------------------------------------------------------------------------
# Off-track: wheels on gravel, grass or water. A low rumble of the kart
# bouncing over the uneven ground and the crunch of small stones flicked by
# the tyres. Loops (3 s); the game turns it up with speed.
# --------------------------------------------------------------------------
def offroad():
    r = np.random.default_rng(42)
    seconds = 3.5
    n = int(seconds * RATE)
    t = np.arange(n) / RATE
    bumps = lowpass(r.standard_normal(n), 14, 2)
    bumps = 0.6 + 0.4 * bumps / np.max(np.abs(bumps))
    rumble = bandpass(r.standard_normal(n), 70, 450, 2) * bumps
    crunch = np.zeros(n)
    count = int(seconds * 380)
    m = int(0.006 * RATE)
    kk = np.arange(m) / RATE
    for _ in range(count):
        i = r.integers(0, n - m)
        crunch[i:i + m] += r.uniform(0.2, 1.0) * r.standard_normal(m) * np.exp(-kk * r.uniform(500, 1400))
    crunch = bandpass(crunch, 1200, 6500, 2)
    x = 0.8 * normalise(rumble) + 0.65 * normalise(crunch)
    x = crossfade_loop(x, 0.5)
    write("offroad_loop.ogg", normalise(np.tanh(normalise(x, 1.0) * 1.4), 0.85), loop=True)


# --------------------------------------------------------------------------
# Kerbs: the tyres drumming over the red and white blocks - a low thud and
# a plastic rattle for each block, 12 blocks a second (the game speeds the
# loop up and down with the kart). 24 blocks, so it loops exactly.
# --------------------------------------------------------------------------
def kerb():
    r = np.random.default_rng(12)
    rate = 12
    blocks = 24
    period = int(round(RATE / rate))
    n = period * blocks
    x = np.zeros(n)
    span = period * 2
    k = np.arange(span) / RATE
    for b in range(blocks):
        amp = (1.0 if b % 2 == 0 else 0.8) * (0.9 + 0.2 * r.random())
        # a low thud, the hollow slap of the tyre on the block (what a phone
        # speaker plays) and a rattle of the kart
        hit = 0.7 * np.sin(2 * np.pi * 75 * k) * np.exp(-k * 40)
        hit += sum(a * np.sin(2 * np.pi * f * k + p) * np.exp(-k * d)
                   for a, f, p, d in [(0.8, 410, 0.0, 55), (0.55, 780, 0.6, 75), (0.35, 1350, 1.1, 110)])
        rattle = bandpass(r.standard_normal(span) * np.exp(-k * 70), 600, 3000)
        idx = (b * period + np.arange(span)) % n
        np.add.at(x, idx, amp * (hit + 0.6 * rattle / np.max(np.abs(rattle))))
    x = loop_filter(x, lambda v: highpass(v, 40))
    x = np.tanh(normalise(x, 1.0) * 1.6)
    write("kerb_loop.ogg", normalise(x, 0.85), loop=True)


def fade_out(x, seconds=0.012):
    """End a note at zero (a note that stops mid-ring clicks)."""
    n = min(int(seconds * RATE), len(x))
    x = x.copy()
    x[-n:] *= np.linspace(1, 0, n)
    return x


def square_tone(freq, seconds, hold, release=0.03):
    t = t_axis(seconds)
    x = sum(np.sin(2 * np.pi * freq * h * t) / h for h in (1, 3, 5, 7))
    return fade_out(lowpass(x, 4000) * envelope(len(t), 0.004, release, hold))


# Track-limits warning: two short low alert tones, a little buzzy.
def warning():
    a = square_tone(523.25, 0.16, 0.1)
    gap = int(0.2 * RATE)
    x = np.zeros(gap + len(a))
    x[:len(a)] += a
    x[gap:gap + len(a)] += a
    write("warning.ogg", normalise(x, 0.65))


# Penalty / lap deleted: a falling two-step buzzer.
def penalty():
    def buzz(freq, seconds, hold):
        t = t_axis(seconds)
        x = signal.sawtooth(2 * np.pi * freq * t) + 0.5 * signal.sawtooth(2 * np.pi * freq * 1.005 * t)
        return fade_out(lowpass(x, 2200) * envelope(len(t), 0.006, 0.05, hold))

    a, b = buzz(392, 0.24, 0.17), buzz(262, 0.42, 0.3)
    gap = int(0.26 * RATE)
    x = np.zeros(gap + len(b))
    x[:len(a)] += a
    x[gap:] += b
    write("penalty.ogg", normalise(x, 0.6))


# Personal best / fastest lap / track record: a quick rising bell arpeggio
# with a sparkle on top.
def best():
    def bell(freq, seconds):
        t = t_axis(seconds)
        partials = [(1.0, 1.0, 3.5), (2.0, 0.5, 6), (2.76, 0.35, 9), (5.4, 0.15, 16)]
        return sum(a * np.sin(2 * np.pi * freq * p * t) * np.exp(-t * d) for p, a, d in partials) * envelope(len(t), 0.003, 10)

    total = 1.3
    x = np.zeros(int(total * RATE))
    for k, f in enumerate((1046.5, 1318.5, 1568.0, 2093.0)):
        s = bell(f, total - k * 0.08)
        i = int(k * 0.08 * RATE)
        x[i:i + len(s)] += s * (0.8 if k < 3 else 1.0)
    r = np.random.default_rng(7)
    t = t_axis(total)
    sparkle = highpass(r.standard_normal(len(t)), 6000) * np.exp(-((t - 0.45) / 0.25) ** 2) * 0.12
    write("best.ogg", normalise(x + sparkle, 0.7))


# Flag: an air horn blast for the start of qualifying and the chequered flag.
def flag():
    seconds = 0.85
    t = t_axis(seconds)
    rise = 1 - 0.04 * np.exp(-t * 25)  # pitch settles as the horn fills
    x = np.zeros(len(t))
    for f in (349.2, 440.0):
        phase = 2 * np.pi * np.cumsum(f * rise) / RATE
        x += sum((0.75 ** h) * np.sin(h * phase) for h in range(1, 12))
    x = bandpass(x, 250, 3500, 2) * envelope(len(t), 0.03, 0.08, 0.68)
    write("flag.ogg", normalise(np.tanh(x * 1.2), 0.75))


# Podium: the grandstands cheering and clapping as the results come up.
def podium():
    r = np.random.default_rng(1)
    seconds = 4.2
    n = int(seconds * RATE)
    t = np.arange(n) / RATE
    swell = np.minimum(1, t / 0.35) * np.exp(-np.maximum(t - 1.2, 0) / 1.8)
    x = bandpass(r.standard_normal(n), 400, 3500, 2) * 0.35 * swell
    # voices: rising "woo"s
    formants = [(500, 1500), (700, 1200), (400, 2000), (600, 1700)]
    for _ in range(90):
        length = r.uniform(0.3, 0.9)
        m = int(length * RATE)
        start = r.integers(0, int(1.6 * RATE))
        k = np.arange(m) / RATE
        pitch = r.uniform(180, 380) * (1 + 0.35 * k / length)
        v = signal.sawtooth(2 * np.pi * np.cumsum(pitch) / RATE)
        f1, f2 = formants[r.integers(len(formants))]
        v = bandpass(v, f1 * 0.7, f1 * 1.3) + 0.6 * bandpass(v, f2 * 0.8, f2 * 1.2)
        x[start:start + m] += v * np.sin(np.pi * k / length) ** 2 * r.uniform(0.05, 0.14)
    # applause: lots of short noise claps
    claps = np.zeros(n)
    m = int(0.012 * RATE)
    kk = np.arange(m) / RATE
    for _ in range(int(seconds * 70)):
        i = r.integers(0, n - m)
        claps[i:i + m] += r.standard_normal(m) * np.exp(-kk * 420) * r.uniform(0.3, 1.0)
    claps = bandpass(claps, 900, 6000, 2) * np.minimum(1, t / 0.5) * np.exp(-np.maximum(t - 2.2, 0) / 1.2)
    x = lowpass(x, 6000) + 0.5 * normalise(claps)
    write("podium.ogg", normalise(x, 0.7))


SOUNDS = {
    "engine": engine, "skid": skid, "offroad": offroad, "kerb": kerb, "bump": bump,
    "beep": beep, "go": go, "lap": lap, "best": best, "warning": warning,
    "penalty": penalty, "flag": flag, "finish": finish, "podium": podium,
    "click": click, "crowd": crowd,
}


if __name__ == "__main__":
    import sys
    for name in sys.argv[1:] or SOUNDS:
        SOUNDS[name]()
