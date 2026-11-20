"""TikTok: character walks + ElevenLabs voice, music and SFX + word captions, 1080x1920 @ 60 fps.

    ELEVENLABS_API_KEY from the env or the git-ignored repo-root .env
    python make_tiktok.py [--voice NAME_OR_ID]

Generated audio is cached in gen/ (delete a file to regenerate it, e.g. gen/voice.mp3
after changing TEXT or the voice). raw/shot1-3.mp4 are Studio captures (15 fps,
recorded with the game slowed 4x, sped back up 4x -> real 60 fps).
"""
import base64, json, os, subprocess, sys, urllib.request
from pathlib import Path

HERE = Path(__file__).parent
GEN = HERE / "gen"
TEXT = ("Yo! This is Ragdoll Mayhem! Here's the deal: "
        "comment what we should add to the game. "
        "The most liked idea? We're actually adding it! "
        "Seriously, no matter what it is! The more creative, the better. Go!")
VOICE = "Arthur"  # "Energetic American Male Narrator"
MUSIC = ("Hype energetic TikTok gaming beat, 150 BPM, punchy trap drums, bouncy distorted 808 bass, "
         "playful chiptune synth lead, chaotic fun cartoon vibe, instant start with no intro, "
         "big drop at the start, instrumental, no vocals")
# name -> (prompt, seconds); times are attached in main() from the voice timing
SFX = {
    "riser": ("fast cartoon whoosh riser into a hit, video game intro", 1.0),
    "boom": ("huge punchy cinematic bass boom impact with a cartoon bonk", 1.2),
    "whoosh": ("quick swoosh transition whoosh, short and snappy", 0.6),
    "like": ("bright social media notification pop ding, satisfying like sound", 0.7),
    "levelup": ("video game level up chime with coins, triumphant and short", 1.2),
    "pop": ("tiny soft bubble pop, ui click", 0.5),  # API minimum is 0.5 s
    "cheer": ("small crowd cheering and an air horn, hype", 2.0),
}
API = "https://api.elevenlabs.io/v1"


def key():
    k = os.environ.get("ELEVENLABS_API_KEY")
    env = HERE.parents[1] / ".env"  # repo-root .env, git-ignored
    if not k and env.exists():
        k = next((l.split("=", 1)[1].strip().strip('"') for l in env.read_text().splitlines()
                  if l.startswith("ELEVENLABS_API_KEY=")), None)
    return k or sys.exit("ELEVENLABS_API_KEY is not set")


def api(path, body=None, raw=False):
    req = urllib.request.Request(API + path, headers={"xi-api-key": key(), "Content-Type": "application/json"},
                                 data=json.dumps(body).encode() if body else None)
    with urllib.request.urlopen(req, timeout=300) as r:
        return r.read() if raw else json.load(r)


def gen_voice(voice_arg):
    voices = api("/voices")["voices"]
    want = voice_arg or VOICE
    pick = next(v for v in voices if want in (v["voice_id"], v["name"], v["name"].split()[0]))
    print("voice:", pick["name"])
    res = api(f"/text-to-speech/{pick['voice_id']}/with-timestamps", {
        "text": TEXT, "model_id": "eleven_multilingual_v2", "language_code": "en",
        "voice_settings": {"stability": 0.3, "similarity_boost": 0.8, "style": 0.7, "use_speaker_boost": True}})
    (GEN / "voice.mp3").write_bytes(base64.b64decode(res["audio_base64"]))
    (GEN / "alignment.json").write_text(json.dumps(res["alignment"], ensure_ascii=False), encoding="utf-8")


def cached(name, make):
    f = GEN / name
    if not f.exists():
        print("generating", name)
        f.write_bytes(make())
    return f


def dur(f):
    return float(subprocess.check_output(["ffprobe", "-v", "error", "-show_entries", "format=duration",
                                          "-of", "csv=p=0", str(f)]))


def words_from_alignment(al):
    words, cur, t0 = [], "", None
    for ch, s, e in zip(al["characters"], al["character_start_times_seconds"], al["character_end_times_seconds"]):
        if ch.isspace():
            if cur:
                words.append((cur, t0, last))
            cur, t0 = "", None
        else:
            cur, t0, last = cur + ch, s if t0 is None else t0, e
    if cur:
        words.append((cur, t0, last))
    return words


def ts(t):
    return f"{int(t // 3600)}:{int(t % 3600 // 60):02}:{t % 60:05.2f}"


def caption_groups(words):
    # 1-3 words per caption, break after punctuation
    groups, g = [], []
    for w in words:
        g.append(w)
        if len(g) == 3 or w[0][-1] in ".,!?:":
            groups.append(g); g = []
    return groups + ([g] if g else [])


def captions(groups, end):
    head = """[Script Info]
ScriptType: v4.00+
PlayResX: 1080
PlayResY: 1920

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Cap,Arial Black,110,&H0000E5FF,&H00FFFFFF,&H00000000,&H64000000,-1,0,0,0,100,100,0,0,1,7,4,2,60,60,560,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
"""
    lines = []
    for i, g in enumerate(groups):
        s = g[0][1]
        e = groups[i + 1][0][1] if i + 1 < len(groups) else end
        # pop in with a slight overshoot, words fill white -> yellow as they are spoken
        parts = [f"{{\\kf{max(1, round((we - ws) * 100))}}}{w.upper()}" for w, ws, we in g]
        text = "{\\fscx70\\fscy70\\t(0,80,\\fscx112\\fscy112)\\t(80,150,\\fscx100\\fscy100)}" + " ".join(parts)
        lines.append(f"Dialogue: 0,{ts(s)},{ts(e)},Cap,,0,0,0,,{text}")
    return head + "\n".join(lines) + "\n"


def main():
    GEN.mkdir(exist_ok=True)
    voice_arg = sys.argv[sys.argv.index("--voice") + 1] if "--voice" in sys.argv else None
    if not (GEN / "voice.mp3").exists():
        gen_voice(voice_arg)
    words = words_from_alignment(json.loads((GEN / "alignment.json").read_text(encoding="utf-8")))
    total = dur(GEN / "voice.mp3") + 1.2
    music = cached("music.mp3", lambda: api("/music", {"prompt": MUSIC, "music_length_ms": int(total * 1000) + 3000,
                                                       "force_instrumental": True}, raw=True))
    sfx = {n: cached(f"sfx_{n}.mp3", lambda p=p, d=d: api("/sound-generation", {
        "text": p, "duration_seconds": d, "prompt_influence": 0.5}, raw=True)) for n, (p, d) in SFX.items()}

    def at(prefix):  # start time of the first spoken word starting with prefix
        return next(s for w, s, _ in words if w.lower().startswith(prefix.lower()))

    groups = caption_groups(words)
    third = total / 3
    impacts = [at("Yo"), at("Ragdoll"), at("Go!")]  # zoom punches
    cues = ([("riser", 0.0, 0.8), ("boom", at("Yo"), 0.9), ("boom", at("Ragdoll"), 0.7),
             ("whoosh", third - 0.25, 0.8), ("whoosh", 2 * third - 0.25, 0.8),
             ("like", at("liked"), 0.9), ("levelup", at("adding"), 0.8),
             ("boom", at("Go!"), 1.0), ("cheer", at("Go!") + 0.1, 0.7)]
            + [("pop", g[0][1], 0.35) for g in groups])
    (HERE / "captions.ass").write_text(captions(groups, total), encoding="utf-8")

    # video: start of shot 1, middle of 2, end of 3 (character stops); zoom punch on impacts
    raw = HERE / "raw"
    cuts = [(0, third), (0.5, third), (max(0, dur(raw / "shot3.mp4") - third), third)]
    inputs = []
    for i, (ss, d) in enumerate(cuts, 1):
        inputs += ["-ss", f"{ss:.3f}", "-t", f"{d:.3f}", "-i", str(raw / f"shot{i}.mp4")]
    inputs += ["-i", str(GEN / "voice.mp3"), "-i", str(music)]
    for n, _, _ in cues:
        inputs += ["-i", str(sfx[n])]
    zoom = "+".join(f"0.09*exp(-(t-{t:.3f})*9)*gte(t,{t:.3f})" for t in impacts)
    sub = str(HERE / "captions.ass").replace("\\", "/").replace(":", "\\:")
    fc = [("[0:v][1:v][2:v]concat=n=3:v=1:a=0,fps=60,"
           f"tpad=stop_mode=clone:stop_duration=2,trim=duration={total:.3f},setpts=PTS-STARTPTS,"
           f"scale=w='2*trunc(540*(1+{zoom}))':h='2*trunc(960*(1+{zoom}))':eval=frame,crop=1080:1920,"
           f"subtitles='{sub}'[v]"),
          "[3:a]aformat=sample_rates=48000:channel_layouts=stereo,asplit[vo][key]",
          f"[4:a]aformat=sample_rates=48000:channel_layouts=stereo,atrim=duration={total:.3f},volume=0.35,"
          f"afade=t=out:st={total - 0.8:.3f}:d=0.8[mus]",
          "[mus][key]sidechaincompress=threshold=0.03:ratio=6:attack=20:release=300[duck]"]
    mix = ["[vo]", "[duck]"]
    for i, (n, t, vol) in enumerate(cues):
        ms = max(0, int(t * 1000))
        fc.append(f"[{5 + i}:a]aformat=sample_rates=48000:channel_layouts=stereo,volume={vol},"
                  f"adelay={ms}:all=1[s{i}]")
        mix.append(f"[s{i}]")
    fc.append(f"{''.join(mix)}amix=inputs={len(mix)}:normalize=0,atrim=duration={total:.3f},"
              "loudnorm=I=-14:TP=-1.5:LRA=11,aresample=48000[a]")
    out = HERE / "tiktok_komentarze.mp4"
    subprocess.check_call(["ffmpeg", "-v", "error", "-y", *inputs, "-filter_complex", ";".join(fc),
                           "-map", "[v]", "-map", "[a]", "-r", "60", "-c:v", "libx264", "-preset", "slow",
                           "-crf", "17", "-pix_fmt", "yuv420p", "-profile:v", "high", "-c:a", "aac", "-b:a", "192k",
                           "-movflags", "+faststart", str(out)])
    print(out)


if __name__ == "__main__":
    main()
