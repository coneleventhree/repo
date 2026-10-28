#!/usr/bin/env python3
"""How loud each game sound is next to the engine, the way a player hears it:
the .ogg through Roblox's volume model (Config.Audio volume x the settings'
default 80% sound-group volume x inverse roll-off from the chase camera),
then a phone speaker / laptop / headphones and A-weighting.

    python3 sounds/mix_levels.py        # needs numpy, scipy, ffmpeg

Reads the volumes from src/shared/Config.luau. Steady sounds are measured as
RMS, one-shots as their loudest 120 ms. The columns show dB(A) and, in
brackets, dB relative to the engine at full throttle (the reference).
"""
import os, re, subprocess
import numpy as np
from scipy import signal

RATE = 44100
HERE = os.path.dirname(os.path.abspath(__file__))
CONFIG = os.path.join(HERE, "..", "src", "shared", "Config.luau")


def load(name):
    p = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", os.path.join(HERE, name + ".ogg"), "-f", "s16le", "-ac", "1", "-ar", str(RATE), "-"], capture_output=True, check=True)
    return np.frombuffer(p.stdout, dtype=np.int16) / 32768.0


def speed(x, s):
    n = int(len(x) / s)
    return np.interp(np.arange(n) * s, np.arange(len(x)), x)


def loop_to(x, seconds):
    n = int(seconds * RATE)
    return np.tile(x, int(np.ceil(n / len(x))))[:n]


def a_weight(x):
    f1, f2, f3, f4 = 20.598997, 107.65265, 737.86223, 12194.217
    nums = [(2 * np.pi * f4) ** 2 * (10 ** (1.9997 / 20)), 0, 0, 0, 0]
    dens = np.polymul([1, 4 * np.pi * f4, (2 * np.pi * f4) ** 2], [1, 4 * np.pi * f1, (2 * np.pi * f1) ** 2])
    dens = np.polymul(np.polymul(dens, [1, 2 * np.pi * f3]), [1, 2 * np.pi * f2])
    b, a = signal.bilinear(nums, dens, RATE)
    return signal.lfilter(b, a, x)


DEVICES = {
    "phone": lambda x: signal.sosfilt(signal.butter(4, [450, 9000], "bandpass", fs=RATE, output="sos"), x),
    "laptop": lambda x: signal.sosfilt(signal.butter(3, [200, 14000], "bandpass", fs=RATE, output="sos"), x),
    "headphones": lambda x: x,
}


def steady(x, d):
    y = a_weight(DEVICES[d](x))[int(0.2 * RATE):]
    return 20 * np.log10(np.sqrt(np.mean(y ** 2)) + 1e-12)


def burst(x, d):
    pad = np.zeros(int(0.3 * RATE))
    y = a_weight(DEVICES[d](np.concatenate([pad, x, pad])))[len(pad):]
    w = min(int(0.12 * RATE), len(y))
    return 10 * np.log10(np.convolve(y ** 2, np.ones(w) / w, mode="valid").max() + 1e-12)


def rolloff(dist, mn):
    return min(1.0, mn / max(dist, 1e-3))


def config():
    src = open(CONFIG).read()
    audio = src[src.index("Config.Audio = {"):]
    audio = audio[:audio.index("\n}")]
    return {k: float(v) for k, v in re.findall(r"\t(\w+) = ([0-9.]+),", audio)}


def main():
    c = config()
    group, cam = 0.8, rolloff(13, 12)
    db = lambda v: 20 * np.log10(v)
    eng = load("engine_loop")
    loop = c["EngineRpmLoop"]
    rows = []
    def add(name, fn):
        rows.append((name, {d: fn(d) for d in DEVICES}))
    add("engine (full throttle)", lambda d: steady(loop_to(speed(eng, 3600 / loop), 3), d) + db(c["EngineVolume"] * group * cam))
    add("engine (idle)", lambda d: steady(loop_to(speed(eng, c["EngineRpmIdle"] / loop), 3), d) + db(c["EngineVolume"] * group * cam * 0.55))
    crowd = loop_to(load("crowd_loop"), 3)
    for dist in (45, 150):
        add("crowd, stand %d studs" % dist, lambda d, dist=dist: steady(crowd, d) + db(c["CrowdVolume"] * group * rolloff(dist, c.get("CrowdRollOffMin", 20))))
    add("skid", lambda d: steady(loop_to(load("skid_loop"), 3), d) + db(c["SkidVolume"] * group * cam))
    add("off-road (gravel)", lambda d: steady(loop_to(speed(load("offroad_loop"), 1.1), 3), d) + db(c["OffroadVolume"] * group * cam))
    add("kerb", lambda d: steady(loop_to(speed(load("kerb_loop"), 0.9), 3), d) + db(c["KerbVolume"] * group * cam))
    for n in ["bump", "beep", "go", "lap", "best", "warning", "penalty", "flag", "finish", "podium", "click"]:
        x = load(n)
        key = n.capitalize() + "Volume"
        add(n, lambda d, x=x, key=key: burst(x, d) + db(c[key] * group))
    ref = rows[0][1]
    print("%-24s %18s %18s %18s" % ("", *DEVICES))
    for name, v in rows:
        print("%-24s %s" % (name, " ".join("%18s" % ("%6.1f (%+5.1f)" % (v[d], v[d] - ref[d])) for d in DEVICES)))


if __name__ == "__main__":
    main()
