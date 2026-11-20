"""TikTok #2: which weapon launches a ragdoll the furthest. ~30 s, 1080x1920 @ 60 fps.

    python make_tiktok2.py          (ELEVENLABS_API_KEY from the env or the repo-root .env)

raw/*.mp4 are Studio captures of replays: every hit was really fired in game, its physics
recorded at 60 Hz, then replayed 4x slower (3x more around the impact) and captured at
15 fps, so sped back up 4x it is real 60 fps. Each capture starts black; the replay starts
where the black ends. impact/final/end are the replay's own clocks (seconds after that point,
real time), distances are the measured landing distances. Generated audio is cached in gen/.
"""
import hashlib, json, re, subprocess, sys
from pathlib import Path

HERE = Path(__file__).parent
sys.path.insert(0, str(HERE.parent / "tiktok"))
import make_tiktok as base  # api, cached, dur, words_from_alignment, ts

GEN = HERE / "gen"
base.GEN = GEN
RAW = HERE / "raw"
VOICES = {"M": ("Arthur", "&H0028E6FF"), "F": ("Laura", "&H00B469FF")}  # name, caption colour (BGR)

INTRO = [("M", "Which weapon launches a ragdoll the furthest?"), ("F", "Let's test it!")]
SEGS = [  # ascending, the record last
    dict(raw="pan", rank=6, title="FRYING PAN", impact=2.119, final=8.785, end=10.185, dist=4.94,
         a=("F", "Frying pan!"), b=("M", "Bonk. Five studs."), hit=["bonk"]),
    dict(raw="bat", rank=5, title="BASEBALL BAT", impact=2.171, final=11.420, end=12.823, dist=9.94,
         a=("M", "Baseball bat!"), b=("F", "Huge air... only ten studs!"), hit=["batcrack"]),
    dict(raw="sledge", rank=4, title="SLEDGEHAMMER", impact=2.206, final=9.404, end=10.805, dist=24.52,
         a=("F", "Sledgehammer!"), b=("M", "Twenty-four and a half!"), hit=["thud"]),
    dict(raw="rocket", rank=3, title="ROCKET LAUNCHER", impact=2.249, final=10.276, end=11.676, dist=40.94,
         a=("M", "Rocket launcher!"), b=("F", "Forty-one studs!"), hit=["boom"], pre=["rocket"]),
    dict(raw="tnt", rank=2, title="TNT", impact=2.155, final=11.971, end=13.371, dist=54.21,
         a=("F", "T. N. T!"), b=("M", "Fifty-four! Way past the rocket!"), hit=["boom"]),
    dict(raw="c4", rank=1, title="TRIPLE C4", impact=2.179, final=13.311, end=14.712, dist=67.21,
         a=("M", "Triple C4!"), b=("F", "Sixty-seven?! Six seven!"), hit=["boom", "boom", "boom"], pre=["drumroll"],
         laugh=True),
]
# the 6-7 meme payoff after the C4 result: both of them crack up (eleven_v3 for a real laugh)
LAUGH = [("F", "[laughing] Ha ha ha ha ha!"), ("M", "[laughs hard] Ha ha ha ha!")]
OUTRO = [("M", "Which weapon should we test next?"), ("F", "Comment below!")]
MUSIC = ("High energy hype gaming countdown beat, 150 BPM, punchy trap drums, distorted bouncy 808, "
         "playful chiptune lead, builds tension and gets bigger toward the end, instant start, "
         "instrumental, no vocals")
SFX = {
    "riser": ("fast cartoon whoosh riser into a punchy hit, video game intro", 1.0),
    "whoosh": ("quick swoosh transition whoosh, short and snappy", 0.6),
    "bonk": ("cartoon frying pan bonk, loud metallic clang, funny", 0.8),
    "batcrack": ("baseball bat crack, wooden smack home run hit", 0.8),
    "thud": ("heavy sledgehammer smash, deep ground thump impact", 1.0),
    "boom": ("big punchy explosion boom with debris, cinematic", 1.6),
    "rocket": ("rocket launcher firing, fast whoosh", 0.8),
    "ding": ("game show score ding, satisfying points chime", 0.7),
    "drumroll": ("short snare drum roll building tension", 1.5),
    "cheer": ("crowd cheering with air horns, new record celebration", 2.5),
    "pop": ("tiny soft bubble pop, ui click", 0.5),
}
INTRO_LEN, OUTRO_LEN, SLOW = 2.4, 3.3, 5.0  # SLOW > 4 also tightens the pace a little


def ffprobe_black_end(f):
    out = subprocess.run(["ffmpeg", "-hide_banner", "-i", str(f), "-vf", "blackdetect=d=0.1:pix_th=0.05",
                          "-an", "-f", "null", "-"], capture_output=True, text=True).stderr
    return float(re.search(r"black_end:([\d.]+)", out).group(1))


def line(who, text):
    """TTS one line with timestamps, cached: (mp3 path, [(word, start, end)], duration)."""
    name, _ = VOICES[who]
    v3 = "[" in text  # audio tags ([laughing]) need eleven_v3
    tag = hashlib.md5(f"{name}|{text}".encode()).hexdigest()[:10]
    mp3, js = GEN / f"line_{tag}.mp3", GEN / f"line_{tag}.json"
    if not mp3.exists():
        voices = base.api("/voices")["voices"]
        vid = next(v["voice_id"] for v in voices if v["name"].split()[0] == name)
        res = base.api(f"/text-to-speech/{vid}/with-timestamps", {
            "text": text, "model_id": "eleven_v3" if v3 else "eleven_multilingual_v2", "language_code": "en",
            "voice_settings": {"stability": 0.0 if v3 else 0.3, "similarity_boost": 0.8,
                               **({} if v3 else {"style": 0.75, "use_speaker_boost": True})}})
        import base64
        mp3.write_bytes(base64.b64decode(res["audio_base64"]))
        js.write_text(json.dumps(res["alignment"]), encoding="utf-8")
    words = [w for w in base.words_from_alignment(json.loads(js.read_text(encoding="utf-8")))
             if "[" not in w[0] and "]" not in w[0]]
    return mp3, words, base.dur(mp3)


def main():
    GEN.mkdir(exist_ok=True)
    sfx = {n: base.cached(f"sfx_{n}.mp3", lambda p=p, d=d: base.api("/sound-generation", {
        "text": p, "duration_seconds": d, "prompt_influence": 0.5}, raw=True)) for n, (p, d) in SFX.items()}

    voice_cues = []  # (start, who, mp3, words)
    sfx_cues = []    # (name, start, volume)
    ass = []         # dialogue lines
    clips = []       # (ffmpeg args for one segment, length)
    t = 0.0

    def say(who, text, at):
        mp3, words, d = line(who, text)
        voice_cues.append((at, who, mp3, words))
        return d

    def title(text, s, e, size=96, y=210, colour="&HFFFFFF&", x=540):
        pop = "{\\fscx40\\fscy40\\t(0,110,\\fscx115\\fscy115)\\t(110,190,\\fscx100\\fscy100)}"
        ass.append(f"Dialogue: 1,{base.ts(s)},{base.ts(e)},Title,,0,0,0,,{{\\pos({x},{y})\\c{colour}\\fs{size}}}{pop}{text}")

    # intro: the dummy and the weapons circling it
    raw = RAW / "intro.mp4"
    be = ffprobe_black_end(raw)
    clips.append((["-ss", f"{be + 0.6:.3f}", "-i", str(raw)], INTRO_LEN, False))
    sfx_cues.append(("riser", 0.0, 0.8))
    d1 = say(*INTRO[0], 0.15)
    say(INTRO[1][0], INTRO[1][1], 0.15 + d1 + 0.05)
    title("WHICH WEAPON", 0.1, INTRO_LEN, 110, 230, "&H28E6FF&")
    title("LAUNCHES THE", 0.25, INTRO_LEN, 110, 360)
    title("FURTHEST?", 0.4, INTRO_LEN, 140, 510, "&H28E6FF&")
    t = INTRO_LEN

    for seg in SEGS:
        raw = RAW / f"{seg['raw']}.mp4"
        be = ffprobe_black_end(raw)
        imp, fin, end = seg["impact"] / SLOW, seg["final"] / SLOW, seg["end"] / SLOW
        _, _, db = line(*seg["b"])
        laugh_at = t + fin - 0.2 + db + 0.05
        laugh_len = 1.4 if seg.get("laugh") else 0  # the laugh runs on into the ranking
        length = max(end, fin - 0.2 + db + 0.15 + laugh_len)
        clips.append((["-ss", f"{be:.3f}", "-t", f"{seg['end']:.3f}", "-i", str(raw)], length, True))
        sfx_cues.append(("whoosh", t, 0.8))
        for n in seg.get("pre", []):
            sfx_cues.append((n, t + (imp - 0.45 if n == "rocket" else 0.0), 0.7 if n == "drumroll" else 0.9))
        for k, n in enumerate(seg["hit"]):
            sfx_cues.append((n, t + imp + k * 0.36, 1.0 if n != "boom" else 0.85))
        sfx_cues.append(("ding", t + fin, 0.8))
        say(*seg["a"], t + 0.05)
        say(*seg["b"], t + fin - 0.2)
        title(f"#{seg['rank']}", t, t + length, 120, 105, "&H28E6FF&")
        title(seg["title"], t + 0.05, t + length, 88, 215)
        if seg["rank"] == 1:
            sfx_cues.append(("cheer", t + fin, 0.6))
            title("NEW RECORD!", t + fin, t + length, 90, 1000, "&H50FF78&")
            title("6", t + fin + 0.25, t + length, 280, 1210, "&H50FF78&", 400)
            title("7", t + fin + 0.55, t + length, 280, 1210, "&H50FF78&", 680)
        if seg.get("laugh"):
            for who, text in LAUGH:  # no captions: the laugh gets a shaking HAHAHA instead
                voice_cues.append((laugh_at, who, line(who, text)[0], []))
            shake = "".join(f"\\t({k * 80},{k * 80 + 80},\\frz{6 if k % 2 else -6})" for k in range(12))
            ass.append(f"Dialogue: 2,{base.ts(laugh_at)},{base.ts(t + length)},Title,,0,0,0,,"
                       f"{{\\pos(540,1460)\\c&HFFFFFF&\\fs120{shake}}}HAHAHAHA!")
        t += length

    # outro: the final ranking over the last frame of the record
    last = SEGS[-1]
    raw = RAW / f"{last['raw']}.mp4"
    be = ffprobe_black_end(raw)
    clips.append((["-ss", f"{be + last['end'] - 0.3:.3f}", "-i", str(raw)], OUTRO_LEN, "still"))
    title("FINAL RANKING", t + 0.05, t + OUTRO_LEN, 100, 330, "&H28E6FF&")
    for k, seg in enumerate(sorted(SEGS, key=lambda s: s["rank"])):
        s = t + 0.25 + k * 0.2
        colour = "&H28E6FF&" if seg["rank"] == 1 else "&HFFFFFF&"
        title(f"{seg['rank']}. {seg['title']}  {seg['dist']:.1f}", s, t + OUTRO_LEN, 70, 500 + k * 105, colour)
        sfx_cues.append(("pop", s, 0.5))
    d1 = say(*OUTRO[0], t + 1.35)
    say(OUTRO[1][0], OUTRO[1][1], t + 1.35 + d1 + 0.05)
    t += OUTRO_LEN
    total = t
    for at, _, mp3, _ in voice_cues:
        if at + base.dur(mp3) > total:
            total = at + base.dur(mp3) + 0.2
    print(f"total {total:.2f} s")

    # speaker captions: male yellow / female pink, words fill as they are spoken
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
            + "\n".join([style.format(n="M", fs=96, c1=VOICES["M"][1], o=7, al=2, mv=470),
                         style.format(n="F", fs=96, c1=VOICES["F"][1], o=7, al=2, mv=470),
                         style.format(n="Title", fs=96, c1="&H00FFFFFF", o=8, al=5, mv=0)])
            + "\n\n[Events]\nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n")
    (HERE / "captions.ass").write_text(head + "\n".join(ass) + "\n", encoding="utf-8")

    music = base.cached("music.mp3", lambda: base.api("/music", {
        "prompt": MUSIC, "music_length_ms": int(total * 1000) + 2000, "force_instrumental": True}, raw=True))

    # one ffmpeg pass: segments -> 9:16 60 fps with a white flash on each cut, captions, the mix
    inputs, fc, vlabels = [], [], []
    for i, (args, length, kind) in enumerate(clips):
        inputs += args
        crop = "crop=648:1152:(iw-648)/2:0,scale=1080:1920:flags=lanczos"
        if kind == "still":
            fc.append(f"[{i}:v]trim=end_frame=1,{crop},boxblur=12:2,eq=brightness=-0.3:saturation=1.2,"
                      f"loop=-1:1:0,fps=60,trim=duration={length:.3f},setpts=PTS-STARTPTS[v{i}]")
        else:
            fc.append(f"[{i}:v]setpts=(PTS-STARTPTS)/{SLOW},fps=60,{crop},tpad=stop_mode=clone:stop_duration=3,"
                      f"trim=duration={length:.3f},setpts=PTS-STARTPTS,fade=t=in:st=0:d=0.12:color=white[v{i}]")
        vlabels.append(f"[v{i}]")
    sub = str(HERE / "captions.ass").replace("\\", "/").replace(":", "\\:")
    fc.append(f"{''.join(vlabels)}concat=n={len(clips)}:v=1:a=0,tpad=stop_mode=clone:stop_duration=2,"
              f"trim=duration={total:.3f},subtitles='{sub}'[v]")
    n = len(clips)
    audio = [(m, at, 1.0) for at, _, m, _ in voice_cues]
    voice_n = len(audio)
    audio += [(sfx[nm], at, vol) for nm, at, vol in sfx_cues]
    inputs += ["-i", str(music)]
    music_i = n
    for f, _, _ in audio:
        inputs += ["-i", str(f)]
    fmt = "aformat=sample_rates=48000:channel_layouts=stereo"
    vo, fx = [], []
    for k, (_, at, vol) in enumerate(audio):
        lab = f"a{k}"
        fc.append(f"[{music_i + 1 + k}:a]{fmt},volume={vol},adelay={max(0, int(at * 1000))}:all=1[{lab}]")
        (vo if k < voice_n else fx).append(f"[{lab}]")
    fc.append(f"{''.join(vo)}amix=inputs={len(vo)}:normalize=0,apad,atrim=duration={total:.3f},asplit[vox][key]")
    fc.append(f"[{music_i}:a]{fmt},atrim=duration={total:.3f},volume=0.32,afade=t=out:st={total - 1:.3f}:d=1[mus]")
    fc.append("[mus][key]sidechaincompress=threshold=0.03:ratio=5:attack=15:release=250[duck]")
    fc.append(f"[vox][duck]{''.join(fx)}amix=inputs={2 + len(fx)}:normalize=0,atrim=duration={total:.3f},"
              "loudnorm=I=-14:TP=-1.5:LRA=11,aresample=48000[a]")
    out = HERE / "tiktok_bronie.mp4"
    subprocess.check_call(["ffmpeg", "-v", "error", "-y", *inputs, "-filter_complex", ";".join(fc),
                           "-map", "[v]", "-map", "[a]", "-r", "60", "-c:v", "libx264", "-preset", "slow", "-crf", "17",
                           "-pix_fmt", "yuv420p", "-profile:v", "high", "-c:a", "aac", "-b:a", "192k",
                           "-movflags", "+faststart", str(out)])
    print(out)


if __name__ == "__main__":
    main()
