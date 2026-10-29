#!/usr/bin/env python3
"""Hear the engine before uploading it: a short drive (idle, flat out from a
standstill, lift, brake, back on it, stop) rendered the way the game plays
the sounds, once with the single old loop (engine_loop.ogg pitched to the
rpm) and once with the layered engine (shared/EngineAudio: engine_1700 /
2800 / 4000 cross-faded by rpm, engine_off on a closed throttle).

    python3 sounds/engine_preview.py OUT_DIR     # needs numpy, ffmpeg

Writes OUT_DIR/engine_old.mp3 and OUT_DIR/engine_new.mp3. The rpm model and
the mix follow KartVisuals.engineRpm and EngineAudio.mix; the speed is a rough
kart (DriveAccel 8.5, PowerPerMass 520, drag, engine braking, brakes).
"""
import math, os, subprocess, sys
import numpy as np

RATE = 44100
HERE = os.path.dirname(os.path.abspath(__file__))
FRAME = 1 / 60

IDLE, CLUTCH, RELEASE, RPM_MAX, TOP = 1600, 2600, 2000, 4200, 100.0
LAYERS = [("engine_1700", 1700), ("engine_2800", 2800), ("engine_4000", 4000)]
OFF = ("engine_off", 3400)


def load(name):
    p = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", os.path.join(HERE, name + ".ogg"), "-f", "s16le", "-ac", "1", "-ar", str(RATE), "-"], capture_output=True, check=True)
    return np.frombuffer(p.stdout, dtype=np.int16) / 32768.0


def drive():
    """(throttle, speed) every frame."""
    plan = [(2.0, 0, 0), (13.0, 1, 0), (3.0, 0, 0), (1.6, 0, 1), (5.0, 1, 0), (2.0, 0, 0), (3.0, 0, 1), (2.5, 0, 0)]
    out, v = [], 0.0
    for secs, thr, brake in plan:
        for _ in range(int(secs / FRAME)):
            a = thr * min(8.5, 520 / max(v, 1)) - 0.00055 * v * v
            if not thr:
                a -= 0.9 if v > 1 else 0
            a -= brake * 25 if v > 0.5 else 0
            v = min(max(v + a * FRAME, 0), TOP)
            out.append((thr, v))
    return out


def engine_rpm(speed, throttle):
    road = RPM_MAX * min(max(speed / TOP, 0), 1.1)
    if throttle > 0.05:
        return max(road, IDLE + (CLUTCH - IDLE) * min(throttle * 1.5, 1))
    return road if road > RELEASE else IDLE


def weights(rpms, rpm):
    n = len(rpms)
    w = [0.0] * n
    if rpm <= rpms[0]:
        w[0] = 1
    elif rpm >= rpms[-1]:
        w[-1] = 1
    else:
        for i in range(n - 1):
            a, b = rpms[i], rpms[i + 1]
            if a <= rpm < b:
                f = (rpm - a) / (b - a)
                w[i], w[i + 1] = math.cos(f * math.pi / 2), math.sin(f * math.pi / 2)
    return w


def mix(rpm, load):
    """EngineAudio.mix: (layer volumes, layer speeds, off volume, off speed)."""
    wf = weights([r for _, r in LAYERS[1:]], rpm)
    closed = weights([LAYERS[0][1], LAYERS[0][1] + 800], rpm)
    vol = [closed[0] * (1 - load)] + [w * load for w in wf]
    speeds = [min(max(rpm / r, 0.5), 2) for _, r in LAYERS]
    return vol, speeds, closed[1] * (1 - load), min(max(rpm / OFF[1], 0.5), 2)


def play(buf, state, speed, n):
    """n samples of looped `buf` from phase state[0] at `speed` (linear interp)."""
    ph = state[0] + np.arange(n) * speed
    i = np.floor(ph).astype(int)
    f = ph - i
    out = buf[i % len(buf)] * (1 - f) + buf[(i + 1) % len(buf)] * f
    state[0] = (state[0] + n * speed) % len(buf)
    return out


def render(new):
    per = int(RATE * FRAME)
    frames = drive()
    out = np.zeros(len(frames) * per)
    rpm, ld = IDLE, 0.0
    if new:
        bufs = [load(nm) for nm, _ in LAYERS]
        off = load(OFF[0])
        st = [[0.0] for _ in LAYERS] + [[0.0]]
    else:
        old = load("engine_loop")
        st = [[0.0]]
    prev = None
    for k, (thr, v) in enumerate(frames):
        rpm += (engine_rpm(v, thr) - rpm) * min(FRAME * 8, 1)
        ld += (thr - ld) * min(FRAME * 12, 1)
        seg = slice(k * per, (k + 1) * per)
        if new:
            vol, sp, offv, offs = mix(rpm, ld)
            y = sum(vol[i] * play(bufs[i], st[i], sp[i], per) for i in range(len(bufs)))
            y = y + offv * play(off, st[-1], offs, per)
        else:
            y = (0.55 + 0.45 * thr) * play(old, st[0], rpm / 3000, per)
        out[seg] = y
    out /= max(np.max(np.abs(out)), 1e-9) / 0.9
    return out


def write(path, x):
    pcm = (np.clip(x, -1, 1) * 32767).astype(np.int16).tobytes()
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "s16le", "-ar", str(RATE), "-ac", "1", "-i", "-", "-b:a", "160k", path], input=pcm, check=True)
    print("wrote", path)


if __name__ == "__main__":
    out_dir = sys.argv[1] if len(sys.argv) > 1 else HERE
    os.makedirs(out_dir, exist_ok=True)
    write(os.path.join(out_dir, "engine_old.mp3"), render(False))
    write(os.path.join(out_dir, "engine_new.mp3"), render(True))
