"""TikTok #4: Ragdoll Mayhem is out in beta - what sets it apart. ~40 s, 1080x1920 @ 60 fps.

    python make_tiktok4.py          (ELEVENLABS_API_KEY from the env or the repo-root .env)

One narrator (Lucy - Fresh & Casual, eleven_v3 tags). raw60/*.mp4 are real gameplay on the arena
(as updated 2026-11-21), recorded off the screen from the Studio play viewport with ffmpeg ddagrab at
60 fps (50-56 unique frames a second; `ss` is seconds into the capture). Only the boss shot is the
tiktok3 Myth Yard capture (black lead-in, `start` counted after it). A beat with `parts` cuts between
captures, each taking `share` of the beat. Captions and the mix work as in make_tiktok3.
"""
import subprocess, sys
from pathlib import Path

HERE = Path(__file__).parent
sys.path.insert(0, str(HERE.parent / "tiktok3"))
import make_tiktok3 as t3

t2, base = t3.t2, t3.base
GEN = HERE / "gen"
t2.GEN = base.GEN = GEN
t2.VOICES["F"] = ("Lucy", "&H00B469FF")
RAW, RAW3 = HERE / "raw60", t3.RAW3
SFX_DIR = t3.SFX_DIR
Y, W, G = t3.Y, t3.W, t3.G

# own captures: ss (capture seconds), speed, cx (crop centre, 0..1) or fit=True (whole frame on a blurred fill)
# old captures: start (after the black lead-in), speed
BEATS = [
    dict(src=RAW / "fly.mp4", ss=0.0, speed=1.0, min=2.6,
         voice="[excited] Ragdoll Mayhem by Cadabula Studios is out now in beta on Roblox!",
         titles=[("RAGDOLL", 560, 160, Y, 0.0), ("MAYHEM", 710, 160, Y, 0.1), ("BETA OUT NOW!", 1250, 115, G, 0.6)],
         sfx=[("riser", 0.0, 0.35), ("boom", 0.6, 0.45)]),
    dict(src=RAW / "orbit.mp4", ss=0.0, speed=1.0, min=1.4, voice="[curious] So what makes it different?",
         titles=[("WHAT'S", 260, 110, W, 0.0), ("DIFFERENT?", 380, 120, Y, 0.1)], sfx=[]),
    dict(src=RAW / "parkour.mp4", ss=0.0, speed=1.0, min=2.0,
         voice="[impressed] You move like a stuntman: sprint, slide, dash, and slam down from the air!",
         titles=[("PARKOUR", 260, 130, Y, 0.0), ("MOVES", 390, 120, W, 0.1)], sfx=[]),
    dict(src=RAW / "punt.mp4", ss=1.0, speed=1.0, cx=0.45, min=2.0,
         voice="[mischievous] Grab a dummy by the collar... [laughing] and punt it away!",
         titles=[("GRAB", 260, 130, Y, 0.0), ("& PUNT", 390, 120, W, 0.1)], sfx=[]),
    dict(src=RAW / "brawl.mp4", min=2.0, parts=[dict(ss=0.0, speed=1.0, share=0.4), dict(ss=5.2, speed=1.0, share=0.6)],
         voice="[laughing] And the dummies are alive! They talk, start fights, and cops show up to arrest them!",
         titles=[("THE DUMMIES", 260, 110, W, 0.0), ("ARE ALIVE", 380, 125, Y, 0.1)], sfx=[]),
    dict(src=RAW / "toolbox.mp4", min=2.0,
         parts=[dict(ss=0.0, speed=1.4, fit=True, share=0.6), dict(ss=6.6, speed=1.0, cx=0.55, share=0.4)],
         voice="[excited] Open the toolbox and spawn anyone: soldiers, workers... or a whole zombie horde!",
         titles=[("TOOLBOX", 330, 130, Y, 0.0)], sfx=[]),
    dict(src=RAW / "tank.mp4", ss=1.5, speed=1.3, cx=0.5, min=3.0, voice="[excited] Need more chaos? Hop in a tank!",
         titles=[("DRIVE", 260, 130, W, 0.0), ("A TANK", 390, 130, Y, 0.1)], sfx=[]),
    dict(src=RAW3 / "boss.mp4", speed=4, start=0.0, min=1.6,
         voice="[ominous] And myth bosses hunt the dummies down... and eat them.",
         titles=[("MYTH BOSSES", 260, 125, Y, 0.0)], sfx=[]),
    dict(src=RAW / "orbit.mp4", ss=2.0, speed=1.0, min=3.0,
         voice="[warmly] It's a beta, so tell us what to add next! [excited] Search Ragdoll Mayhem on Roblox!",
         titles=[("PLAY THE BETA", 260, 120, G, 0.0), ("COMMENT YOUR IDEAS", 380, 80, W, 0.2), ("SEARCH:", 980, 80, W, 1.6),
                 ("RAGDOLL MAYHEM", 1090, 105, Y, 1.7)], sfx=[("cheer", 0.0, 0.3)]),
]
MUSIC = ("Upbeat hype video game beta launch beat, 140 BPM, punchy drums, bouncy 808 bass, bright playful "
         "chiptune lead, energetic from the first second, instrumental, no vocals")


def video_filter(i, clip):
    src, ss, length, speed, cx, fit = clip
    head = f"[{i}:v]setpts=(PTS-STARTPTS)/{speed},fps=60,"
    tail = (f"setsar=1,tpad=stop_mode=clone:stop_duration=3,trim=duration={length:.3f},setpts=PTS-STARTPTS,"
            f"fade=t=in:st=0:d=0.1:color=white[v{i}]")
    if fit:  # the whole frame across, on a blurred, zoomed copy of itself
        return (head + f"split[fa{i}][fb{i}];[fa{i}]scale=-2:1920,crop=1080:1920,boxblur=30:2,eq=brightness=-0.15[bg{i}];"
                f"[fb{i}]scale=1080:-2[fg{i}];[bg{i}][fg{i}]overlay=0:(H-h)/2," + tail)
    x = f"max(0\\,min(iw-ih*9/16\\,iw*{cx}-ih*9/32))"
    return head + f"crop=ih*9/16:ih:{x}:0,scale=1080:1920:flags=lanczos," + tail


def main():
    GEN.mkdir(exist_ok=True)
    voice_cues, sfx_cues, ass, clips = [], [], [], []
    t = 0.0

    def title(text, s, e, y, size, colour):
        pop = "{\\fscx40\\fscy40\\t(0,110,\\fscx115\\fscy115)\\t(110,190,\\fscx100\\fscy100)}"
        ass.append(f"Dialogue: 1,{base.ts(s)},{base.ts(e)},Title,,0,0,0,,{{\\pos(540,{y})\\c{colour}\\fs{size}}}{pop}{text}")

    for i, beat in enumerate(BEATS):
        mp3, words, d = t2.line("F", beat["voice"])
        voice_cues.append((t + 0.05, "F", mp3, words))
        length = max(beat["min"], d + 0.2)
        if "start" in beat:
            be, stop = t3.black_span(beat["src"])
            ss = be + beat["start"] * beat["speed"]
            speed = max(1.8, min(beat["speed"], (stop - ss - 0.05) / length))
            clips.append((beat["src"], ss, length, speed, 0.5, False))
        else:
            parts = beat.get("parts") or [dict(ss=beat["ss"], speed=beat["speed"], cx=beat.get("cx", 0.5),
                                               fit=beat.get("fit", False), share=1.0)]
            for part in parts:
                plen = length * part["share"]
                room = (base.dur(beat["src"]) - part["ss"]) / part["speed"]
                if room < plen:
                    print(f"  beat {i}: {beat['src'].name} runs out {plen - room:.2f} s early (held on its last frame)")
                clips.append((beat["src"], part["ss"], plen, part["speed"], part.get("cx", 0.5), part.get("fit", False)))
        if i:
            sfx_cues.append(("whoosh", t - 0.08, 0.4))
        for name, dt, vol in beat["sfx"]:
            sfx_cues.append((name, t + dt, vol))
        for text, y, size, colour, delay in beat["titles"]:
            title(text, t + delay, t + length, y, size, colour)
            sfx_cues.append(("pop", t + delay, 0.25))
        print(f"{i}: {t:6.2f} +{length:.2f}  {beat['src'].name}")
        t += length
    total = t
    print(f"total {total:.2f} s")

    for at, who, mp3, words in voice_cues:
        groups = base.caption_groups([(w, s + at, e + at) for w, s, e in words if "[" not in w and "]" not in w])
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
            + "\n".join([style.format(n="F", fs=88, c1=t2.VOICES["F"][1], o=7, al=2, mv=440),
                         style.format(n="Title", fs=96, c1="&H00FFFFFF", o=9, al=5, mv=0)])
            + "\n\n[Events]\nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n")
    (HERE / "captions.ass").write_text(head + "\n".join(ass) + "\n", encoding="utf-8")

    music = base.cached("music.mp3", lambda: base.api("/music", {
        "prompt": MUSIC, "music_length_ms": int(total * 1000) + 2000, "force_instrumental": True}, raw=True))

    inputs, fc, vl = [], [], []
    for i, clip in enumerate(clips):
        inputs += ["-ss", f"{clip[1]:.3f}", "-i", str(clip[0])]
        fc.append(video_filter(i, clip))
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
    fc.append(f"[{n}:a]{fmt},atrim=duration={total:.3f},volume=0.32,afade=t=out:st={total - 1:.3f}:d=1[mus]")
    fc.append("[mus][key]sidechaincompress=threshold=0.03:ratio=5:attack=15:release=250[duck]")
    fc.append(f"[vox][duck]{''.join(fx)}amix=inputs={2 + len(fx)}:normalize=0,atrim=duration={total:.3f},"
              "loudnorm=I=-14:TP=-1.5:LRA=11,aresample=48000[a]")
    out = HERE / "tiktok_beta.mp4"
    subprocess.check_call(["ffmpeg", "-v", "error", "-y", *inputs, "-filter_complex", ";".join(fc),
                           "-map", "[v]", "-map", "[a]", "-r", "60", "-c:v", "libx264", "-preset", "slow", "-crf", "18",
                           "-pix_fmt", "yuv420p", "-profile:v", "high", "-c:a", "aac", "-b:a", "192k",
                           "-movflags", "+faststart", str(out)])
    print(out)


if __name__ == "__main__":
    main()
