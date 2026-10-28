#!/usr/bin/env python3
"""Assemble a Last Route trailer from rendered shots, title cards and a synthesised KyttusLab-MIDI track.

  tools/playtest/trailer.py tools/playtest/trailers/descent.json --clips captures/videos/<commit> [--out captures/videos/<commit>/trailers]

A trailer spec (JSON) lists shots in order: {"clip": "<area>", "ss": start_s, "t": seconds} cuts a flythrough/sequencer clip, {"card": ["LINE", ...], "t": s}
is a title card on black (drawn here with Pillow: this ffmpeg has no drawtext). Every segment dips through black, the game's own audio rides at low
volume, and the MIDI track (numpy synth, no soundfont needed) plays under it. Stdlib + Pillow + numpy; never runs Godot.
"""
import argparse
import json
import math
import os
import struct
import subprocess
import sys
import tempfile
import wave
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

REPO = Path(__file__).resolve().parents[2]
MIDI_DIR = Path(os.environ.get("KYTTUSLAB_MIDI", "/Volumes/BIG-HDD-2/Game Stuff/KyttusLab-MIDI/soundtracks"))
FONTS = ["/System/Library/Fonts/Menlo.ttc", "/System/Library/Fonts/Supplemental/Courier New Bold.ttf", "/System/Library/Fonts/Monaco.ttf"]
SR = 32000


# ---------------------------------------------------------------------------------------------------- MIDI -> audio
def read_vlq(data, pos):
    value = 0
    while True:
        byte = data[pos]
        pos += 1
        value = (value << 7) | (byte & 0x7F)
        if not byte & 0x80:
            return value, pos


def parse_midi(path):
    data = Path(path).read_bytes()
    assert data[:4] == b"MThd"
    _fmt, ntrks, division = struct.unpack(">HHH", data[8:14])
    pos = 14
    events = []  # (tick, kind, channel, a, b)
    tempos = [(0, 500000)]
    for _ in range(ntrks):
        assert data[pos:pos + 4] == b"MTrk"
        length = struct.unpack(">I", data[pos + 4:pos + 8])[0]
        pos += 8
        end = pos + length
        tick = 0
        running = 0
        while pos < end:
            delta, pos = read_vlq(data, pos)
            tick += delta
            status = data[pos]
            if status == 0xFF:
                meta = data[pos + 1]
                size, pos2 = read_vlq(data, pos + 2)
                if meta == 0x51:
                    tempos.append((tick, int.from_bytes(data[pos2:pos2 + 3], "big")))
                pos = pos2 + size
                continue
            if status in (0xF0, 0xF7):
                size, pos2 = read_vlq(data, pos + 1)
                pos = pos2 + size
                continue
            if status & 0x80:
                running = status
                pos += 1
            kind = running & 0xF0
            channel = running & 0x0F
            if kind in (0xC0, 0xD0):
                pos += 1
                continue
            a, b = data[pos], data[pos + 1]
            pos += 2
            if kind in (0x90, 0x80):
                events.append((tick, "on" if kind == 0x90 and b > 0 else "off", channel, a, b))
        pos = end
    tempos.sort()
    return division, tempos, sorted(events, key=lambda e: e[0])


def ticks_to_seconds(tick, division, tempos):
    seconds = 0.0
    last_tick, last_tempo = 0, 500000
    for t, tempo in tempos:
        if t >= tick:
            break
        seconds += (t - last_tick) * last_tempo / 1e6 / division
        last_tick, last_tempo = t, tempo
    return seconds + (tick - last_tick) * last_tempo / 1e6 / division


def synth(path, seconds):
    """A small additive synth: soft pads for sustained voices, bell-ish decays for high notes, noise percussion on channel 10, then a little room reverb."""
    division, tempos, events = parse_midi(path)
    active = {}
    notes = []
    for tick, kind, ch, note, vel in events:
        t = ticks_to_seconds(tick, division, tempos)
        key = (ch, note)
        if kind == "on":
            active[key] = (t, vel)
        elif key in active:
            start, v = active.pop(key)
            notes.append((start, t, ch, note, v))
    total = max((n[1] for n in notes), default=1.0)
    length = int(min(total + 3.0, seconds + 3.0) * SR)
    out = np.zeros(length, dtype=np.float32)
    rng = np.random.default_rng(7)
    for start, end, ch, note, vel in notes:
        if start > seconds + 1:
            continue
        i0 = int(start * SR)
        dur = max(end - start, .08)
        n = int((dur + .6) * SR)
        if i0 + n > length:
            n = length - i0
        if n <= 0:
            continue
        t = np.arange(n) / SR
        amp = (vel / 127.0) ** 1.4 * .22
        if ch == 9:
            if note in (35, 36):      # kick
                sig = np.sin(2 * np.pi * (110 * np.exp(-t * 18) + 38) * t) * np.exp(-t * 9)
            else:                     # noise tick
                sig = rng.standard_normal(n) * np.exp(-t * (45 if note in (42, 44, 46) else 18)) * .5
            out[i0:i0 + n] += (sig * amp * 1.6).astype(np.float32)
            continue
        f = 440.0 * 2 ** ((note - 69) / 12)
        if f < 90:
            sig = np.sin(2 * np.pi * f * t) + .25 * np.sin(2 * np.pi * 2 * f * t)
            env = np.minimum(t / .05, 1) * np.where(t < dur, 1.0, np.exp(-(t - dur) * 6))
        elif f > 700:
            sig = np.sin(2 * np.pi * f * t) + .3 * np.sin(2 * np.pi * 2.76 * f * t) * np.exp(-t * 6)
            env = np.exp(-t * 3.0)
        else:
            sig = np.sin(2 * np.pi * f * t) + .4 * np.sin(2 * np.pi * 2 * f * t + .3) + .2 * np.sin(2 * np.pi * 3 * f * t)
            sig *= 1.0 + .03 * np.sin(2 * np.pi * 5.1 * t)
            env = np.minimum(t / .25, 1) * np.where(t < dur, 1.0, np.exp(-(t - dur) * 3.0))
        out[i0:i0 + n] += (sig * env * amp).astype(np.float32)
    # reverb: exponentially decaying noise impulse response
    ir_len = int(1.8 * SR)
    ir = (rng.standard_normal(ir_len) * np.exp(-np.arange(ir_len) / (.45 * SR))).astype(np.float32)
    ir[0] = 1.0
    spec = np.fft.rfft(out, n=length + ir_len)
    wet = np.fft.irfft(spec * np.fft.rfft(ir, n=length + ir_len))[:length].astype(np.float32)
    mix = out * .6 + wet * .035
    peak = float(np.max(np.abs(mix))) or 1.0
    return (mix / peak * .85)


def write_wav(path, samples):
    pcm = (np.clip(samples, -1, 1) * 32767).astype(np.int16)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


# ---------------------------------------------------------------------------------------------------- cards + cuts
def make_card(lines, path):
    img = Image.new("RGB", (1280, 720), (0, 0, 0))
    draw = ImageDraw.Draw(img)
    font_path = next((f for f in FONTS if Path(f).exists()), None)
    sizes = [74] + [34] * (len(lines) - 1)
    y = 360 - sum(sizes) // 2 - 10 * (len(lines) - 1)
    for line, size in zip(lines, sizes):
        font = ImageFont.truetype(font_path, size) if font_path else ImageFont.load_default()
        w = draw.textlength(line, font=font)
        draw.text(((1280 - w) / 2, y), line, fill=(226, 226, 226), font=font)
        y += size + 26
    img.save(path)


def make_lower_third(name, line, path):
    """Transparent 1280x720 overlay: a stylised name and one short line, bottom-left."""
    img = Image.new("RGBA", (1280, 720), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    font_path = next((f for f in FONTS if Path(f).exists()), None)
    big = ImageFont.truetype(font_path, 44) if font_path else ImageFont.load_default()
    small = ImageFont.truetype(font_path, 22) if font_path else ImageFont.load_default()
    width = max(draw.textlength(name, font=big), draw.textlength(line, font=small)) + 40
    draw.rectangle((60, 560, 60 + width, 650), fill=(0, 0, 0, 150))
    draw.rectangle((60, 560, 66, 650), fill=(120, 190, 255, 255))
    draw.text((84, 566), name, fill=(235, 235, 235, 255), font=big)
    draw.text((86, 618), line, fill=(170, 190, 210, 255), font=small)
    img.save(path)


def run(cmd):
    out = subprocess.run(cmd, capture_output=True, text=True)
    if out.returncode != 0:
        sys.exit("ffmpeg failed: %s\n%s" % (" ".join(map(str, cmd))[:300], out.stderr[-600:]))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("spec")
    ap.add_argument("--clips", required=True, help="folder with the rendered <area>.mp4 clips (captures/videos/<commit>)")
    ap.add_argument("--out", default="", help="output folder (default <clips>/trailers)")
    ap.add_argument("--no-music", action="store_true")
    args = ap.parse_args()
    spec = json.loads(Path(args.spec).read_text())
    clips = Path(args.clips)
    out_dir = Path(args.out) if args.out else clips / "trailers"
    out_dir.mkdir(parents=True, exist_ok=True)
    tmp = Path(tempfile.mkdtemp(prefix="trailer-"))
    segments = []
    total = 0.0
    for index, shot in enumerate(spec["shots"]):
        seg = tmp / ("seg%02d.mp4" % index)
        dur = float(shot["t"])
        fade = min(.45, dur / 4)
        # per-shot override: "fade_out": 0 is a hard cut (the flicker approach ends on a cut to black)
        fade_in = float(shot.get("fade_in", fade))
        fade_out = float(shot.get("fade_out", fade))
        parts = []
        if fade_in > 0:
            parts.append("fade=t=in:st=0:d=%.2f" % fade_in)
        if fade_out > 0:
            parts.append("fade=t=out:st=%.2f:d=%.2f" % (dur - fade_out, fade_out))
        vf_fade = ",".join(parts) or "null"
        common = ["-c:v", "libx264", "-preset", "medium", "-crf", "24", "-pix_fmt", "yuv420p", "-r", "30", "-c:a", "aac", "-b:a", "96k", "-ar", "44100", "-ac", "2"]
        if "card" in shot:
            png = tmp / ("card%02d.png" % index)
            make_card(shot["card"], png)
            run(["ffmpeg", "-y", "-loglevel", "error", "-loop", "1", "-t", str(dur), "-i", str(png), "-f", "lavfi", "-t", str(dur), "-i", "anullsrc=r=44100:cl=stereo",
                 "-vf", vf_fade + ",format=yuv420p", *common, "-shortest", str(seg)])
        else:
            src = clips / ("%s.mp4" % shot["clip"])
            if not src.exists():
                sys.exit("missing clip %s (render it with tools/playtest/flythrough.py --areas %s)" % (src, shot["clip"]))
            af = "volume=%.2f,afade=t=in:st=0:d=%.2f" % (float(shot.get("game_audio", .45)), max(fade_in, .02))
            if fade_out > 0:
                af += ",afade=t=out:st=%.2f:d=%.2f" % (dur - fade_out, fade_out)
            if "lower" in shot:
                low = shot["lower"]
                png = tmp / ("lower%02d.png" % index)
                make_lower_third(low["name"], low.get("line", ""), png)
                a, b = float(low.get("from", 0.8)), float(low.get("to", dur - 0.8))
                fc = ("[1:v]format=rgba,fade=t=in:st=%.2f:d=0.4:alpha=1,fade=t=out:st=%.2f:d=0.4:alpha=1[ov];[0:v]scale=1280:720[b];[b][ov]overlay=0:0:shortest=0,%s" % (a, b - 0.4, vf_fade))
                run(["ffmpeg", "-y", "-loglevel", "error", "-ss", str(shot.get("ss", 0)), "-t", str(dur), "-i", str(src), "-loop", "1", "-t", str(dur), "-i", str(png),
                     "-filter_complex", fc, "-af", af, *common, str(seg)])
            else:
                run(["ffmpeg", "-y", "-loglevel", "error", "-ss", str(shot.get("ss", 0)), "-t", str(dur), "-i", str(src), "-vf", "scale=1280:720," + vf_fade, "-af", af, *common, str(seg)])
        segments.append(seg)
        total += dur
    listing = tmp / "list.txt"
    listing.write_text("".join("file '%s'\n" % s for s in segments))
    silent = tmp / "silent.mp4"
    run(["ffmpeg", "-y", "-loglevel", "error", "-f", "concat", "-safe", "0", "-i", str(listing), "-c", "copy", str(silent)])
    final = out_dir / ("%s.mp4" % spec["name"])
    if args.no_music or not spec.get("music"):
        silent.replace(final)
    else:
        wav = tmp / "music.wav"
        write_wav(wav, synth(MIDI_DIR / spec["music"], total))
        mv = float(spec.get("music_volume", .75))
        run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(silent), "-stream_loop", "-1", "-i", str(wav), "-filter_complex",
             "[1:a]volume=%.2f,afade=t=in:st=0:d=2,afade=t=out:st=%.2f:d=3[m];[0:a][m]amix=inputs=2:duration=first:normalize=0[a]" % (mv, total - 3),
             "-map", "0:v", "-map", "[a]", "-c:v", "copy", "-c:a", "aac", "-b:a", "128k", "-t", "%.2f" % total, "-movflags", "+faststart", str(final)])
    print("%s  %.0f s  %.1f MB" % (final, total, final.stat().st_size / 1e6))
    for f in tmp.iterdir():
        f.unlink()
    tmp.rmdir()
    return 0


if __name__ == "__main__":
    sys.exit(main())
