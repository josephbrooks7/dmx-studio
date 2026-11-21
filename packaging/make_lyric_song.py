"""Known-lyrics test song. Each line (spoken by macOS `say`, as WAV files l0.wav…) is placed at a known
time over a music bed (kick, snare, bass, chords), with an 8 s instrumental break in the middle.
Writes the song, the truth (line start times) and a messy "pasted from a web page" lyrics file:
web leftovers + the lyrics twice, like a real copy-paste.
usage: make_lyric_song.py clips_dir out.wav truth.json pasted.txt"""
import json, math, random, struct, sys, wave
LINES = ["Neon rivers running through the city", "Every window burning like a star",
         "I keep dancing on the silver ceiling", "Calling out your name across the dark",
         "Hold the thunder in your open hands", "We are golden when the morning lands",
         "Paper lanterns floating on the water", "Singing softly to the summer moon"]
clips, out, truth_p, pasted_p = sys.argv[1:5]
sr = 16000
voice = []
for k in range(len(LINES)):
    w = wave.open(f"{clips}/l{k}.wav"); assert w.getframerate() == sr and w.getnchannels() == 1
    a = w.readframes(w.getnframes()); voice.append([v / 32768 for v in struct.unpack(f"<{len(a)//2}h", a)])
starts, t = [], 4.0
for k, v in enumerate(voice):
    starts.append(round(t, 2)); t += len(v) / sr + 1.2
    if k == 3: t += 8.0                      # instrumental break
dur = t + 4.0
n = int(dur * sr); x = [0.0] * n
random.seed(2); beat = 60 / 100
def add(t0, gen, length, amp):
    i0 = int(t0 * sr)
    for i in range(int(length * sr)):
        if 0 <= i0 + i < n: x[i0 + i] += amp * gen(i / sr)
kick = lambda t: math.sin(2 * math.pi * (50 + 80 * math.exp(-t * 40)) * t) * math.exp(-t * 12)
snare = lambda t: random.uniform(-1, 1) * math.exp(-t * 18)
chord = lambda f: (lambda t: sum(math.sin(2 * math.pi * f * r * t) for r in (1, 1.26, 1.5)) / 3 * min(1, t * 20))
b, tb = 0, 0.0
while tb < dur:
    add(tb, kick, 0.3, 0.5)
    if b % 2: add(tb, snare, 0.2, 0.15)
    if b % 4 == 0: add(tb, chord([220, 196, 175, 165][(b // 4) % 4]), beat * 4, 0.12)
    tb += beat; b += 1
for s0, v in zip(starts, voice):
    i0 = int(s0 * sr)
    for i, val in enumerate(v):
        if i0 + i < n: x[i0 + i] += val * 0.8
peak = max(abs(v) for v in x) or 1
w = wave.open(out, "wb"); w.setnchannels(1); w.setsampwidth(2); w.setframerate(sr)
w.writeframes(b"".join(struct.pack("<h", int(v / peak * 0.9 * 32767)) for v in x)); w.close()
json.dump({"lines": LINES, "starts": starts}, open(truth_p, "w"))
junk_top = ["Neon Rivers Lyrics", ""]
junk_mid = ["Source: LyricFind", "Songwriters: Test Writer", "Neon Rivers lyrics © Test Music Publishing",
            "Watch a lyric video to follow along with the song in sync:", "3:51", "Test Band - Neon Rivers (Lyrics)",
            "13M views · 1 year ago", "YouTube · Some Channel", "AI can make mistakes, so double-check responses Learn more",
            "Show more", "Lyrics", ""]
short = LINES[:2] + LINES[4:]                 # a shorter copy first, like search pages show
open(pasted_p, "w").write("\n".join(junk_top + short + junk_mid + ["[Verse 1]"] + LINES[:4] + ["", "[Chorus]"] + LINES[4:]) + "\n")
print("line starts:", starts, "duration", round(dur, 1))
