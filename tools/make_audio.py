#!/usr/bin/env python3
"""Genera la música (loops chiptune) y los ambientes de clima del juego con numpy + ffmpeg.

Todo se compone por código, así que no tiene derechos de autor de terceros.
Uso: python3 tools/make_audio.py            -> assets/audio/music/*.ogg y assets/audio/ambience/*.ogg

Cada pista es un loop exacto de N compases: el juego la repite sin cortes.
"""
import subprocess
from pathlib import Path

import numpy as np

SR = 32000
OUT = Path(__file__).resolve().parent.parent / "assets/audio"
NOTE = {n: i for i, n in enumerate(["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"])}
MAJOR = [0, 2, 4, 5, 7, 9, 11]
MINOR = [0, 2, 3, 5, 7, 8, 10]


def freq(midi):
    return 440.0 * 2 ** ((midi - 69) / 12)


def midi(name, octave):
    return NOTE[name] + 12 * (octave + 1)


# --- Osciladores y envolventes ------------------------------------------------------

def square(f, n, duty=0.5):
    t = np.arange(n) / SR
    return np.where((t * f) % 1.0 < duty, 1.0, -1.0)


def triangle(f, n):
    t = np.arange(n) / SR
    return 2.0 * np.abs(2.0 * ((t * f) % 1.0) - 1.0) - 1.0


def envelope(n, attack=0.005, decay=0.08, sustain=0.6, release=0.05):
    env = np.full(n, sustain)
    a, d, r = int(attack * SR), int(decay * SR), int(release * SR)
    a, d = min(a, n), min(d, max(0, n - a))
    env[:a] = np.linspace(0, 1, a, endpoint=False)
    env[a:a + d] = np.linspace(1, sustain, d, endpoint=False)
    if r and n > r:
        env[-r:] *= np.linspace(1, 0, r)
    return env


def place(track, start, sound):
    end = min(len(track), start + len(sound))
    if start < len(track):
        track[start:end] += sound[:end - start]


# --- Percusión ------------------------------------------------------------------------

rng = np.random.default_rng(7)


def kick():
    n = int(0.18 * SR)
    t = np.arange(n) / SR
    f = 120 * np.exp(-t * 25) + 45
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 18)


def snare():
    n = int(0.15 * SR)
    t = np.arange(n) / SR
    return (rng.uniform(-1, 1, n) * 0.7 + np.sin(2 * np.pi * 190 * t) * 0.3) * np.exp(-t * 28)


def hat():
    n = int(0.05 * SR)
    noise = rng.uniform(-1, 1, n)
    noise = np.diff(noise, prepend=0)  # agudo
    return noise * np.exp(-np.arange(n) / SR * 90) * 0.5


# --- Composición -------------------------------------------------------------------------

def song(name, key, scale, progression, bpm, bars_per_chord=1, repeats=2, lead_octave=5, seed=1,
         drums="rock", lead_duty=0.25, swing=0.0, lead_density=0.7, volume=0.8):
    """progression: grados de la escala (0 = tónica) por acorde. Se repite `repeats` veces con
    una melodía A/B para que el loop no canse."""
    r = np.random.default_rng(seed)
    beat = 60.0 / bpm
    step = beat / 2  # corcheas
    steps_per_bar = 8
    chords = progression * repeats
    total_steps = len(chords) * bars_per_chord * steps_per_bar
    n_total = int(round(total_steps * step * SR))
    bass, arp, lead, perc = (np.zeros(n_total) for _ in range(4))
    root = midi(key, 2)

    def degree(d, octave_base):
        return octave_base + scale[d % 7] + 12 * (d // 7)

    # Motivo de melodía: ritmo y contorno que se repiten con variaciones.
    motif_rhythm = [1 if r.random() < lead_density else 0 for _ in range(steps_per_bar * 2)]
    motif_rhythm[0] = 1
    motif_moves = [int(r.choice([-2, -1, 0, 1, 1, 2, 3])) for _ in range(steps_per_bar * 2)]
    lead_pos = 2

    for ci, chord_degree in enumerate(chords):
        chord = [chord_degree, chord_degree + 2, chord_degree + 4]
        for bar in range(bars_per_chord):
            bar_index = ci * bars_per_chord + bar
            for s in range(steps_per_bar):
                i = bar_index * steps_per_bar + s
                start = int((i * step + (swing * step if s % 2 else 0)) * SR)
                # Bajo: tónica del acorde en negras con octava en contratiempo.
                if s % 2 == 0:
                    m = degree(chord_degree, root) + (12 if s % 4 == 2 else 0)
                    n = int(step * 1.8 * SR)
                    place(bass, start, triangle(freq(m), n) * envelope(n, decay=0.1, sustain=0.7))
                # Arpegio del acorde.
                m = degree(chord[s % 3] + (7 if s >= 4 else 0), root + 12)
                n = int(step * 0.9 * SR)
                place(arp, start, square(freq(m), n, 0.125) * envelope(n, decay=0.05, sustain=0.3))
                # Melodía: el motivo, con la segunda mitad variada.
                mi = (bar_index % 2) * steps_per_bar + s
                if motif_rhythm[mi]:
                    move = motif_moves[mi]
                    if (bar_index // 2) % 2 == 1 and s >= 4:
                        move = -move
                    lead_pos = int(np.clip(lead_pos + move, 0, 9))
                    # En el primer tiempo del compás, mejor una nota del acorde.
                    if s == 0:
                        lead_pos = min(chord, key=lambda c: abs((c % 7) - (lead_pos % 7))) % 7 + 7 * (lead_pos // 7)
                    length = 1
                    while mi + length < len(motif_rhythm) and length < 3 and not motif_rhythm[(mi + length) % len(motif_rhythm)]:
                        length += 1
                    m = degree(lead_pos, midi(key, lead_octave - 1))
                    n = int(step * length * 0.95 * SR)
                    vib = 1 + 0.004 * np.sin(2 * np.pi * 5.5 * np.arange(n) / SR)
                    tone = square(freq(m), n, lead_duty) * envelope(n, decay=0.12, sustain=0.55, release=0.04)
                    place(lead, start, tone * vib)
                # Batería.
                if drums == "rock":
                    if s in (0, 5):
                        place(perc, start, kick())
                    if s in (2, 6):
                        place(perc, start, snare() * 0.7)
                    place(perc, start, hat() * (0.8 if s % 2 == 0 else 0.5))
                elif drums == "soft":
                    if s == 0:
                        place(perc, start, kick() * 0.7)
                    if s == 4:
                        place(perc, start, snare() * 0.35)
                    if s % 2 == 0:
                        place(perc, start, hat() * 0.4)
                elif drums == "march":
                    if s in (0, 4):
                        place(perc, start, kick())
                    if s in (2, 3, 6):
                        place(perc, start, snare() * 0.55)
                    place(perc, start, hat() * 0.5)

    mix = bass * 0.32 + arp * 0.12 + lead * 0.16 + perc * 0.38
    write(OUT / "music" / f"{name}.ogg", mix, volume)


def ambience(name, seconds, kind):
    n = int(seconds * SR)
    noise = rng.uniform(-1, 1, n)
    if kind == "rain":
        # Ruido rosado aproximado + gotas.
        x = np.convolve(noise, np.ones(6) / 6, mode="same")
        for _ in range(int(seconds * 60)):
            p = rng.integers(0, n - 800)
            x[p:p + 800] += rng.uniform(-1, 1, 800) * np.exp(-np.arange(800) / 120) * rng.uniform(0.3, 0.9)
        x *= 0.5
    elif kind == "wind":
        smooth = np.convolve(noise, np.ones(40) / 40, mode="same")
        t = np.arange(n) / SR
        gust = 0.55 + 0.45 * np.sin(2 * np.pi * t / seconds * 3) * np.sin(2 * np.pi * t / seconds * 2 + 1)
        x = smooth * gust * 3.0
    elif kind == "hail":
        x = np.convolve(noise, np.ones(30) / 30, mode="same") * 1.2
        for _ in range(int(seconds * 25)):
            p = rng.integers(0, n - 400)
            x[p:p + 400] += np.diff(rng.uniform(-1, 1, 401)) * np.exp(-np.arange(400) / 40) * rng.uniform(0.3, 0.8)
    # Fundido cruzado del final con el principio para que el loop no se note.
    fade = int(0.5 * SR)
    x[:fade] = x[:fade] * np.linspace(0, 1, fade) + x[-fade:] * np.linspace(1, 0, fade)
    x = x[:-fade]
    write(OUT / "ambience" / f"{name}.ogg", x, 0.5)


def write(path, signal, volume):
    path.parent.mkdir(parents=True, exist_ok=True)
    signal = np.tanh(signal * 1.2)  # saturación suave en vez de recortes
    signal = signal / max(1e-6, np.abs(signal).max()) * volume
    pcm = (signal * 32767).astype(np.int16).tobytes()
    subprocess.run(["ffmpeg", "-v", "quiet", "-y", "-f", "s16le", "-ar", str(SR), "-ac", "1", "-i", "-",
                    "-c:a", "libvorbis", "-q:a", "4", str(path)], input=pcm, check=True)
    print(f"{path.relative_to(OUT.parent.parent)}  ({len(signal) / SR:.1f} s)")


def main():
    # I-V-vi-IV y variaciones (grados 0-based: 0=I, 3=IV, 4=V, 5=vi).
    song("menu", "D", MAJOR, [0, 4, 5, 3], 100, bars_per_chord=2, repeats=2, seed=3, drums="soft", lead_duty=0.5, lead_density=0.55)
    song("battle", "A", MINOR, [0, 5, 6, 4], 146, bars_per_chord=1, repeats=4, seed=11, drums="rock", lead_density=0.8)
    song("battle_heroic", "C", MAJOR, [0, 3, 4, 0, 5, 3, 1, 4], 138, bars_per_chord=1, repeats=2, seed=5, drums="march")
    song("cave", "E", MINOR, [0, 5, 3, 4], 96, bars_per_chord=2, repeats=2, seed=21, drums="soft", lead_density=0.45, lead_octave=4)
    song("gym", "G", MINOR, [0, 6, 5, 4], 158, bars_per_chord=1, repeats=4, seed=8, drums="rock", lead_density=0.85)
    song("editor", "F", MAJOR, [0, 5, 1, 4], 88, bars_per_chord=2, repeats=2, seed=13, drums="soft", lead_duty=0.5, lead_density=0.4, swing=0.15)
    ambience("rain", 8, "rain")
    ambience("wind", 10, "wind")
    ambience("hail", 8, "hail")


if __name__ == "__main__":
    main()
