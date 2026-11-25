"""TikTok #5: the world events - meteor shower, tsunami, tornado, volcano. ~15 s, 1080x1920 @ 60 fps.

    python make_tiktok5.py          (ELEVENLABS_API_KEY from the env or the repo-root .env)

One narrator (Lucy - Fresh & Casual, eleven_v3 tags). raw60/*.mp4 are the events going off on the arena
(Admin `disaster`), shot from a scripted camera with the game HUD off but the event banner on, recorded
off the screen from the Studio play viewport with ffmpeg ddagrab at 60 fps (rec.ps1). `ss` is seconds
into the capture; smooth() makes each window true 60 fps first. Captions and the mix work as in make_tiktok4; the event sounds are this video's own.
"""
import subprocess, sys
from pathlib import Path

HERE = Path(__file__).parent
sys.path.insert(0, str(HERE.parent / "tiktok4"))
import make_tiktok4 as t4

t3, t2, base = t4.t3, t4.t2, t4.base
GEN = HERE / "gen"
t2.GEN = base.GEN = t4.GEN = GEN
RAW = HERE / "raw60"
INTERP = HERE / "interp60"
Y, W, G = t4.Y, t4.W, t4.G
R = "&H003C3CFF"  # red (BGR)
B = "&H00FFB040"  # blue
O = "&H00208CFF"  # orange

SFX = {  # this video's own, in gen/ (the shared ones stay in tiktok2/gen)
    "meteor": ("flaming meteor whistling down from the sky and slamming into the ground, huge impact boom", 2.0),
    "wave": ("massive tsunami wave roaring in and crashing, rushing water, cinematic", 2.5),
    "tornado": ("violent tornado wind howling and roaring, debris whipping around", 2.5),
    "eruption": ("volcano erupting, deep rumbling explosion and lava blast, cinematic", 2.5),
    "impact": ("deep cinematic trailer hit with sub drop, braam", 1.5),
}
BEATS = [
    dict(src=RAW / "meteors.mp4", ss=12.0, speed=1.0, min=2.9,
         voice="[excited] Meteors are raining down on the dummies!",
         titles=[("4 WORLD EVENTS", 250, 105, W, 0.0), ("METEOR", 520, 150, O, 0.15), ("SHOWER!", 670, 135, Y, 0.3)],
         sfx=[("impact", 0.0, 0.4), ("meteor", 0.3, 0.45)]),
    dict(src=RAW / "tsunami.mp4", ss=4.6, speed=1.0, min=2.9,
         voice="[shocked] Then a giant tsunami washes everyone away!",
         titles=[("TSUNAMI!", 580, 160, B, 0.0)], sfx=[("wave", 0.0, 0.45)]),
    dict(src=RAW / "tornado.mp4", ss=7.5, speed=1.0, min=2.7,
         voice="[laughing] Tornadoes yeet them into the sky!",
         titles=[("TORNADO!", 580, 160, W, 0.0)], sfx=[("tornado", 0.0, 0.4)]),
    dict(src=RAW / "volcano.mp4", ss=5.6, speed=1.0, min=2.4,
         voice="[shouts] And the volcano ERUPTS!",
         titles=[("VOLCANO!", 580, 160, R, 0.0)], sfx=[("eruption", 0.0, 0.45), ("impact", 0.0, 0.35)]),
    dict(src=RAW / "volcano.mp4", ss=10.5, speed=1.0, min=2.4,
         voice="[excited] Play Ragdoll Mayhem on Roblox!",
         titles=[("RAGDOLL", 420, 150, Y, 0.0), ("MAYHEM", 570, 150, Y, 0.1), ("PLAY NOW!", 730, 120, G, 0.4)],
         sfx=[("boom", 0.0, 0.4)]),
]
MUSIC = ("Epic high energy disaster trailer hype beat, 150 BPM, huge punchy trap drums, distorted 808 bass, "
         "intense orchestral stabs and a hard drop from the very first second, relentless, "
         "instrumental, no vocals")


def smooth(beat):
    """The beat's window of its capture as true 60 fps: Studio drew only 20-45 new frames a second while
    the events ran (the rest of the 60 are repeats), so the repeats are dropped (mpdecimate) and the gaps
    filled by motion-compensated interpolation (minterpolate). The game's own mouse arrow, locked to
    the middle of the viewport, is painted out (delogo) and the 9:16 middle cropped first. Cached."""
    out = INTERP / f"{beat['src'].stem}_{beat['ss']:.2f}.mp4"
    if not out.exists():
        INTERP.mkdir(exist_ok=True)
        print("interpolating", out.name)
        cut = INTERP / "cut.mp4"  # two passes: ffmpeg crashes running delogo and minterpolate in one graph
        subprocess.check_call(["ffmpeg", "-v", "error", "-y", "-ss", f"{beat['ss']:.3f}", "-t", "4.5", "-i", str(beat["src"]),
                               "-vf", "crop=ih*9/16:ih:(iw-ih*9/16)/2:0,delogo=x=320:y=524:w=26:h=36,mpdecimate=hi=64*4:lo=64*2:frac=0.1",
                               "-fps_mode", "vfr", "-c:v", "libx264", "-preset", "fast", "-crf", "10", "-pix_fmt", "yuv420p", str(cut)])
        subprocess.check_call(["ffmpeg", "-v", "error", "-y", "-i", str(cut),
                               "-vf", "minterpolate=fps=60:mi_mode=mci:mc_mode=aobmc:me_mode=bidir:vsbmc=1",
                               "-c:v", "libx264", "-preset", "medium", "-crf", "14", "-pix_fmt", "yuv420p", str(out)])
        cut.unlink()
    return dict(beat, src=out, ss=0.0)


def main():
    GEN.mkdir(exist_ok=True)
    for name, (prompt, d) in SFX.items():
        base.cached(f"sfx_{name}.mp3", lambda p=prompt, d=d: base.api("/sound-generation", {
            "text": p, "duration_seconds": d, "prompt_influence": 0.5}, raw=True))
    # make_tiktok4.main does the rest with these beats; its sfx come from SFX_DIR, so point that at a
    # folder holding both the shared ones and this video's
    mix = GEN / "sfx"
    mix.mkdir(exist_ok=True)
    for f in list(t3.SFX_DIR.glob("sfx_*.mp3")) + list(GEN.glob("sfx_*.mp3")):
        target = mix / f.name
        if not target.exists():
            target.write_bytes(f.read_bytes())
    t4.SFX_DIR = mix
    t4.BEATS, t4.MUSIC, t4.HERE = [smooth(b) for b in BEATS], MUSIC, HERE
    t4.main()


if __name__ == "__main__":
    main()
