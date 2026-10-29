"""Listen-test by numbers for the ambience beds rendered by tools/audio/render_ambience.tscn.

    python3 tools/audio/analyse_ambience.py <dir of wavs>

Per bed: loudness (RMS dBFS, a rough stand-in for LUFS on these broadband beds), peak, DC offset, the jump across the
loop seam against the bed's typical sample-to-sample step (a click), the share of energy above 6 kHz (hiss), spectral
flatness and the strongest narrow peak above the median spectrum (pure "beepy" tones), and the margin under the
walking footsteps. Needs numpy only.
"""
import sys
import wave
from pathlib import Path

import numpy as np


def load(path):
    with wave.open(str(path)) as w:
        rate = w.getframerate()
        channels = w.getnchannels()
        data = np.frombuffer(w.readframes(w.getnframes()), dtype="<i2").astype(np.float64) / 32768.0
    return data.reshape(-1, channels).mean(axis=1), rate


def db(x):
    return 20.0 * np.log10(max(x, 1e-9))


def analyse(mono, rate):
    rms = np.sqrt(np.mean(mono ** 2))
    steps = np.abs(np.diff(mono))
    typical = np.percentile(steps, 99) + 1e-9
    seam = abs(mono[0] - mono[-1]) / typical
    spec = np.abs(np.fft.rfft(mono * np.hanning(len(mono)))) ** 2
    freqs = np.fft.rfftfreq(len(mono), 1.0 / rate)
    total = spec.sum() + 1e-18
    hiss = spec[freqs > 6000].sum() / total
    band = spec[(freqs > 40) & (freqs < 8000)] + 1e-18
    flatness = np.exp(np.mean(np.log(band))) / np.mean(band)
    # strongest narrow peak over a 1/3-octave-ish running median: a pure tone stands far above its neighbours
    mags = 10 * np.log10(band)
    width = 200
    pad = np.pad(mags, width, mode="edge")
    median = np.array([np.median(pad[i:i + 2 * width]) for i in range(0, len(mags), 50)])
    median = np.interp(np.arange(len(mags)), np.arange(0, len(mags), 50), median)
    tone = float(np.max(mags - median))
    tone_hz = float(freqs[(freqs > 40) & (freqs < 8000)][int(np.argmax(mags - median))])
    return {"rms": db(rms), "peak": db(np.max(np.abs(mono))), "dc": float(np.mean(mono)), "seam": seam,
            "hiss": hiss, "flat": flatness, "tone": tone, "tone_hz": tone_hz}


def main():
    folder = Path(sys.argv[1])
    steps = [analyse(*load(p))["rms"] for p in sorted(folder.glob("step_walk_*.wav"))]
    step_rms = float(np.mean(steps)) if steps else 0.0
    print(f"walking footsteps mean RMS {step_rms:6.1f} dBFS")
    print(f"{'bed':28s} {'rms':>6s} {'peak':>6s} {'dc':>8s} {'seam':>6s} {'hiss%':>6s} {'flat':>5s} {'tone dB@Hz':>14s} {'under steps':>11s}")
    flags = 0
    for path in sorted(folder.glob("*.wav")):
        if path.stem.startswith("step_") or path.stem.startswith("cue_"):
            continue
        a = analyse(*load(path))
        notes = []
        if a["seam"] > 1.0:
            notes.append("CLICK")
        if abs(a["dc"]) > 0.002:
            notes.append("DC")
        if a["hiss"] > 0.05:
            notes.append("HISS")
        if a["tone"] > 30:
            notes.append("TONE")
        if a["peak"] > -1.0:
            notes.append("CLIP")
        flags += len(notes)
        print(f"{path.stem:28s} {a['rms']:6.1f} {a['peak']:6.1f} {a['dc']:8.4f} {a['seam']:6.2f} {a['hiss'] * 100:6.2f} "
              f"{a['flat']:5.2f} {a['tone']:6.1f}@{a['tone_hz']:6.0f} {step_rms - a['rms']:11.1f}  {' '.join(notes)}")
    print(f"{flags} flags")


if __name__ == "__main__":
    main()
