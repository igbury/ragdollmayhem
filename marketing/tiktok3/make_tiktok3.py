"""TikTok #3: launch trailer - the game is out and what sets it apart. ~30 s, 1080x1920 @ 60 fps.

    python make_tiktok3.py          (ELEVENLABS_API_KEY from the env or the repo-root .env)

Shots: raw/*.mp4 here are camera moves captured 4x slower in Studio (arena flyover, volcano,
Minotaur); the physics shots and the weapon orbit are the replays in ../tiktok2/raw. Voices,
captions and the mix work as in make_tiktok2. Generated audio is cached in gen/; the
sound effects are shared with tiktok2/gen.
"""
import re, subprocess, sys
from pathlib import Path

HERE = Path(__file__).parent
sys.path.insert(0, str(HERE.parent / "tiktok2"))
import make_tiktok2 as t2

base = t2.base
GEN = HERE / "gen"
t2.GEN = base.GEN = GEN
RAW2, RAW3 = HERE.parent / "tiktok2" / "raw", HERE / "raw"
SFX_DIR = HERE.parent / "tiktok2" / "gen"
Y, W, G, P = "&H28E6FF&", "&HFFFFFF&", "&H50FF78&", "&HB469FF&"  # yellow, white, green, pink (BGR)

# speed: how much the capture is sped up (camera moves 4x, replays 5x like tiktok2)
# start: seconds into the shot (final time, after the black lead-in); hit: SFX at that time in the beat
BEATS = [
    dict(src=RAW2 / "c4.mp4", speed=5, start=0.12, min=2.3, voice=[("M", "Ragdoll Mayhem is OUT on Roblox!")],
         titles=[("RAGDOLL", 600, 160, Y, 0.0), ("MAYHEM", 750, 160, Y, 0.1), ("OUT NOW!", 1250, 130, G, 0.35)],
         sfx=[("riser", 0.0, 0.7), ("boom", 0.32, 0.9), ("boom", 0.68, 0.8), ("boom", 1.04, 0.8)]),
    dict(src=RAW3 / "arena.mp4", speed=4, start=0.2, min=1.6, voice=[("F", "And it's not just another ragdoll game.")],
         titles=[("NOT JUST ANOTHER", 230, 92, W, 0.0), ("RAGDOLL GAME", 340, 110, Y, 0.1)], sfx=[]),
    dict(src=RAW2 / "bat.mp4", speed=5, start=0.25, min=1.6, voice=[("M", "Every hit is real physics!")],
         titles=[("REAL PHYSICS", 640, 120, Y, 0.0)], sfx=[("batcrack", 0.2, 1.0)]),
    dict(src=RAW2 / "intro.mp4", speed=4, start=0.8, min=1.8,
         voice=[("F", "Thirty plus weapons: lassos, harpoons, freeze guns, C4!")],
         titles=[("30+", 210, 200, Y, 0.0), ("WEAPONS", 370, 120, W, 0.1)], sfx=[]),
    dict(src=RAW2 / "rocket.mp4", speed=5, start=0.2, min=1.8, voice=[("M", "Send them flying across the map!")],
         titles=[("SEND THEM", 600, 130, Y, 0.0), ("FLYING", 740, 150, W, 0.1)], sfx=[("rocket", 0.0, 0.8), ("boom", 0.25, 0.9)]),
    dict(src=RAW2 / "sledge.mp4", speed=5, start=0.2, min=1.6,
         voice=[("M", "Break their bones and they limp, crawl... or fight back!")],
         titles=[("REAL INJURIES", 640, 115, Y, 0.0)], sfx=[("thud", 0.24, 1.0)]),
    dict(src=RAW3 / "volcano.mp4", speed=4, start=0.0, min=1.6, voice=[("F", "Huge maps: a volcano, a port, a whole city!")],
         titles=[("HUGE MAPS", 230, 130, Y, 0.0)], sfx=[]),
    dict(src=RAW3 / "boss.mp4", speed=4, start=0.9, min=1.5, voice=[("M", "Myth bosses that eat dummies for breakfast!")],
         titles=[("MYTH BOSSES", 230, 125, Y, 0.0)], sfx=[]),
    dict(src=RAW2 / "tnt.mp4", speed=5, start=0.1, min=1.8, voice=[("F", "And you can blow up everything!")],
         titles=[("TOTAL", 600, 150, Y, 0.0), ("MAYHEM", 750, 150, Y, 0.1)], sfx=[("boom", 0.38, 1.0)]),
    dict(src=RAW2 / "intro.mp4", speed=4, start=0.2, min=2.9,
         voice=[("M", "Play Ragdoll Mayhem now!"), ("F", "Search it on Roblox!")],
         titles=[("PLAY NOW", 230, 150, G, 0.0), ("ON ROBLOX", 380, 110, W, 0.15), ("SEARCH:", 1150, 80, W, 1.2),
                 ("RAGDOLL MAYHEM", 1260, 105, Y, 1.3)], sfx=[("cheer", 0.0, 0.5)]),
]
MUSIC = ("Epic hype video game launch trailer beat, 140 BPM, huge punchy drums, distorted 808 bass, "
         "bright chiptune lead, big drop right at the start, nonstop energy, instrumental, no vocals")


def black_span(f):
    """(end of the black lead-in, start of the black after the shot) in capture seconds."""
    out = subprocess.run(["ffmpeg", "-hide_banner", "-i", str(f), "-vf", "blackdetect=d=0.1:pix_th=0.05",
                          "-an", "-f", "null", "-"], capture_output=True, text=True).stderr
    be = float(re.search(r"black_end:([\d.]+)", out).group(1))
    later = [float(x) for x in re.findall(r"black_start:([\d.]+)", out) if float(x) > be]
    return be, (later[0] if later else base.dur(f))


def main():
    GEN.mkdir(exist_ok=True)
    voice_cues, sfx_cues, ass, clips = [], [], [], []
    t = 0.0

    def title(text, s, e, y, size, colour):
        pop = "{\\fscx40\\fscy40\\t(0,110,\\fscx115\\fscy115)\\t(110,190,\\fscx100\\fscy100)}"
        ass.append(f"Dialogue: 1,{base.ts(s)},{base.ts(e)},Title,,0,0,0,,{{\\pos(540,{y})\\c{colour}\\fs{size}}}{pop}{text}")

    for i, beat in enumerate(BEATS):
        at = t + 0.05
        for who, text in beat["voice"]:
            mp3, words, d = t2.line(who, text)
            voice_cues.append((at, who, mp3, words))
            at += d + 0.05
        length = max(beat["min"], at - t + 0.1)
        be, stop = black_span(beat["src"])
        ss = be + beat["start"] * beat["speed"]
        # the capture turns black again when its shot ends: slow the shot down rather than run into it
        speed = max(2.5, min(beat["speed"], (stop - ss - 0.05) / length))
        clips.append((beat["src"], ss, length, speed))
        if i:
            sfx_cues.append(("whoosh", t - 0.08, 0.7))
        for name, dt, vol in beat["sfx"]:
            sfx_cues.append((name, t + dt, vol))
        for text, y, size, colour, delay in beat["titles"]:
            title(text, t + delay, t + length, y, size, colour)
            sfx_cues.append(("pop", t + delay, 0.35))
        t += length
    total = t
    print(f"total {total:.2f} s")

    for at, who, mp3, words in voice_cues:
        groups = base.caption_groups([(w, s + at, e + at) for w, s, e in words])
        for i, g in enumerate(groups):
            s = g[0][1]
            e = groups[i + 1][0][1] if i + 1 < len(groups) else g[-1][2] + 0.25
            parts = [f"{{\\kf{max(1, round((we - ws) * 100))}}}{w.upper()}" for w, ws, we in g]
            pop = "{\\fscx70\\fscy70\\t(0,80,\\fscx112\\fscy112)\\t(80,150,\\fscx100\\fscy100)}"
            ass.append(f"Dialogue: 0,{base.ts(s)},{base.ts(e)},{who},,0,0,0,,{pop}" + " ".join(parts))
    style = ("Style: {n},Arial Black,{fs},{c1},&H00FFFFFF,&H00000000,&H64000000,-1,0,0,0,100,100,0,0,1,{o},4,"
             "{al},60,60,{mv},1")
    head = ("[Script Info]\nScriptType: v4.00+\nPlayResX: 1080\nPlayResY: 1920\n\n[V4+ Styles]\n"
            "Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, "
            "Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, "
            "MarginL, MarginR, MarginV, Encoding\n"
            + "\n".join([style.format(n="M", fs=88, c1=t2.VOICES["M"][1], o=7, al=2, mv=440),
                         style.format(n="F", fs=88, c1=t2.VOICES["F"][1], o=7, al=2, mv=440),
                         style.format(n="Title", fs=96, c1="&H00FFFFFF", o=9, al=5, mv=0)])
            + "\n\n[Events]\nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n")
    (HERE / "captions.ass").write_text(head + "\n".join(ass) + "\n", encoding="utf-8")

    music = base.cached("music.mp3", lambda: base.api("/music", {
        "prompt": MUSIC, "music_length_ms": int(total * 1000) + 2000, "force_instrumental": True}, raw=True))

    inputs, fc, vl = [], [], []
    for i, (src, ss, length, speed) in enumerate(clips):
        inputs += ["-ss", f"{ss:.3f}", "-i", str(src)]
        fc.append(f"[{i}:v]setpts=(PTS-STARTPTS)/{speed},fps=60,crop=ih*9/16:ih:(iw-ih*9/16)/2:0,scale=1080:1920:flags=lanczos,"
                  f"tpad=stop_mode=clone:stop_duration=3,trim=duration={length:.3f},setpts=PTS-STARTPTS,"
                  f"fade=t=in:st=0:d=0.1:color=white[v{i}]")
        vl.append(f"[v{i}]")
    sub = str(HERE / "captions.ass").replace("\\", "/").replace(":", "\\:")
    fc.append(f"{''.join(vl)}concat=n={len(clips)}:v=1:a=0,subtitles='{sub}'[v]")
    n = len(clips)
    audio = [(m, at, 1.0) for at, _, m, _ in voice_cues]
    nv = len(audio)
    audio += [(SFX_DIR / f"sfx_{nm}.mp3", at, vol) for nm, at, vol in sfx_cues]
    inputs += ["-i", str(music)]
    for f, _, _ in audio:
        inputs += ["-i", str(f)]
    fmt = "aformat=sample_rates=48000:channel_layouts=stereo"
    vo, fx = [], []
    for k, (_, at, vol) in enumerate(audio):
        fc.append(f"[{n + 1 + k}:a]{fmt},volume={vol},adelay={max(0, int(at * 1000))}:all=1[a{k}]")
        (vo if k < nv else fx).append(f"[a{k}]")
    fc.append(f"{''.join(vo)}amix=inputs={len(vo)}:normalize=0,apad,atrim=duration={total:.3f},asplit[vox][key]")
    fc.append(f"[{n}:a]{fmt},atrim=duration={total:.3f},volume=0.34,afade=t=out:st={total - 1:.3f}:d=1[mus]")
    fc.append("[mus][key]sidechaincompress=threshold=0.03:ratio=5:attack=15:release=250[duck]")
    fc.append(f"[vox][duck]{''.join(fx)}amix=inputs={2 + len(fx)}:normalize=0,atrim=duration={total:.3f},"
              "loudnorm=I=-14:TP=-1.5:LRA=11,aresample=48000[a]")
    out = HERE / "tiktok_premiera.mp4"
    subprocess.check_call(["ffmpeg", "-v", "error", "-y", *inputs, "-filter_complex", ";".join(fc),
                           "-map", "[v]", "-map", "[a]", "-r", "60", "-c:v", "libx264", "-preset", "slow", "-crf", "18",
                           "-pix_fmt", "yuv420p", "-profile:v", "high", "-c:a", "aac", "-b:a", "192k",
                           "-movflags", "+faststart", str(out)])
    print(out)


if __name__ == "__main__":
    main()
