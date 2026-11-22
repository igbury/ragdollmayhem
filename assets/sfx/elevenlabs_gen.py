"""Generate game SFX with the ElevenLabs Sound Effects API.

Key: ELEVENLABS_API_KEY in the repo's .env (gitignored) or the environment.
Output: assets/sfx/gen/<name>.mp3. Existing files are skipped, so a rerun only pays for
what is missing; delete a file to regenerate it.

    python assets/sfx/elevenlabs_gen.py            # everything missing
    python assets/sfx/elevenlabs_gen.py tomato_splat ui_click   # just these
    python assets/sfx/elevenlabs_gen.py --wire     # approved ids from gen/assets.json -> src/shared/Sfx.luau
"""
import json
import os
import sys
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = Path(__file__).resolve().parent / "gen"
URL = "https://api.elevenlabs.io/v1/sound-generation?output_format=mp3_44100_128"
STYLE = " Clean isolated game sound effect, no music, no voices, no background noise, dry studio recording."

# name, seconds, loop, description
SOUNDS = [
    # --- weapons: impacts that were silent ---
    ("bullet_hit_body", 0.5, False, "Video game hit marker: a single very short, dry, punchy thump of a bullet hitting a thick padded canvas punching bag, tight low-mid thud with a crisp papery snap at the start, no ringing, no echo, no tail, instant and clean."),
    ("bullet_hit_concrete", 0.7, False, "A single bullet impact on a concrete wall: sharp high crack, small debris and grit trickling for a moment afterwards, a faint bright ricochet whine at the end."),
    ("bullet_hit_metal", 0.8, False, "A single bullet hitting a thick steel plate: a bright metallic ping-clang with a short ringing resonance and a quick ricochet whizz flying away."),
    ("bullet_hit_wood", 0.6, False, "A single bullet punching into a wooden plank: a dry woody thock with tiny splinters crackling, short and crisp."),
    ("arrow_hit_body", 0.6, False, "An arrow thudding into a padded training dummy: a quick soft thunk followed by the wooden arrow shaft vibrating with a short twang wobble."),
    ("arrow_hit_wall", 0.7, False, "An arrow hitting a wooden wall and sticking: a hard tok, then the shaft quivering with a springy vibrating boing that fades quickly."),
    ("tomato_splat", 0.7, False, "A ripe tomato thrown hard splatting against a person: a wet juicy squelchy splat with a few droplets pattering, comedic and gross-funny like slapstick."),
    ("fire_burning_loop", 8.0, True, "A medium patch of fire burning on the street after a firebomb: steady roaring flames, crackling and popping, gentle whooshing gusts, seamless loop, constant intensity."),
    ("rocket_flight_loop", 4.0, True, "A small rocket propelled grenade flying through the air: a hissing, roaring rocket motor whoosh with a sizzling exhaust, steady and constant, seamless loop."),
    ("rocket_jump_pop", 1.2, False, "A small controlled explosion under the player's feet launching them into the air: a punchy compressed boom with a springy upward whoosh, smaller and snappier than a full explosion."),
    ("reload_pistol", 1.2, False, "Reloading a handgun: an empty magazine sliding out with a click, a fresh magazine slapped in firmly, then the slide racked back and released with a crisp metallic clack."),
    ("reload_rifle", 1.8, False, "Reloading an assault rifle: magazine release click, empty magazine pulled out, new magazine inserted with a solid metallic clunk, charging handle pulled back and snapped forward."),
    ("shotgun_pump", 0.8, False, "A pump-action shotgun being racked: a fast heavy chk-chk of the slide pulled back and pushed forward, chunky and mechanical."),
    ("dry_fire_click", 0.5, False, "An empty gun dry firing: a single small hollow metallic trigger click, nothing else."),
    ("bow_draw", 1.0, False, "An archer pulling back a bowstring: a smooth tight stretching creak of a taut string and flexing wooden bow limbs, rising tension, quiet and close-up, ending held at full draw, no release, no twang, no arrow flight."),
    ("bow_release", 0.6, False, "A bow firing an arrow: a sharp bowstring twang thrum and a quick airy whoosh of the arrow leaving."),
    # --- weapons: own clips for things that borrowed another weapon's sound ---
    ("revolver_shot", 1.4, False, "A single heavy revolver gunshot outdoors: a deep powerful bang with a sharp crack and a rolling echo off city buildings, heavier than a pistol."),
    ("shotgun_shot", 1.5, False, "A single pump shotgun blast outdoors: a wide, booming, chesty explosion of sound with a scattered spray character and a long rumbling echo."),
    ("sniper_shot", 2.0, False, "A single high-caliber sniper rifle shot fired outdoors: an extremely loud sharp supersonic crack followed by a long distant thunder-like echo rolling across the city."),
    ("melee_swing_light", 0.5, False, "A fast light swing through the air with a small knife or fist: a quick thin whoosh, short and airy."),
    ("melee_swing_heavy", 0.6, False, "A slow heavy swing of a baseball bat or axe through the air: a deep, broad, powerful whoomp whoosh."),
    ("bat_hit", 0.6, False, "A wooden baseball bat swung hard into a heavy padded punching bag: a loud sharp hollow wooden CRACK-thwack, bright woody knock on top of a solid low thump, short and snappy, slapstick cartoon fighting game impact."),
    ("baton_hit", 0.5, False, "A thin rubber police baton striking a person: a quick sharp slap-thwack, lighter and higher-pitched than a bat."),
    ("axe_hit", 0.7, False, "A heavy axe chopping into a padded training dummy: a deep chunky chop thunk with a short wooden creak, cartoon action game, not gory."),
    ("knife_hit", 0.5, False, "A thrown knife hitting a padded target: a quick metallic schink followed by a soft thud, short and clean, not gory."),
    ("glass_bottle_shatter", 1.0, False, "A glass bottle smashing on asphalt: a bright crash of breaking glass with shards tinkling and skittering across the ground."),
    # --- the comic weapon set (server/Specials) ---
    ("crowbar_hit", 0.6, False, "A steel crowbar whacking a padded training dummy: a hard metallic clonk with a short bright ring, slapstick cartoon fighting game impact, not gory."),
    ("sledgehammer_slam", 1.2, False, "A huge sledgehammer slammed into the ground: a massive heavy thud-boom with a metallic clang, a short ground rumble and a little debris, cartoon action game."),
    ("spear_stab", 0.6, False, "A quick spear thrust: a short sharp airy whoosh ending in a hard wooden thunk into a padded target, not gory."),
    ("lightsaber_swing", 0.8, False, "A sci-fi energy sword swung through the air: a deep electric humming whoom that bends in pitch as it sweeps past."),
    ("lightsaber_hit", 0.7, False, "A sci-fi energy sword striking something: a sharp crackling electric clash with a short sizzle, no voices."),
    ("chainsaw_rev", 1.2, False, "A small petrol chainsaw revving hard: a loud buzzing two-stroke engine snarl rising in pitch with the chain whirring, cartoon action game."),
    ("lasso_throw", 1.0, False, "A cowboy lasso swung and thrown: a whirling rope whoosh going round twice, then a quick rope slap as it lands."),
    ("taser_zap", 1.0, False, "A taser firing: a small pop of compressed air, then a loud crackling electric buzz zap that fizzles out, cartoon game."),
    ("frost_ray", 1.0, False, "A sci-fi freeze ray firing: a cold crystalline whoosh with tinkling ice shards forming and a frosty crackle at the end."),
    ("ice_freeze", 0.8, False, "Something freezing solid in an instant: a quick crackling and creaking of ice forming over it, crisp and cold."),
    ("ice_shatter", 0.9, False, "A thin shell of ice cracking apart and falling off: brittle crunching crack with small ice pieces tinkling on the ground."),
    ("boil_blast", 1.0, False, "A blast of boiling water from a pressurised steam gun: a gurgling bubbling spray with a loud hissing jet of steam, cartoon game."),
    ("boil_sizzle", 1.5, False, "Boiling and sizzling: fast bubbling like a pot at a rolling boil, with sharp steam hisses venting, getting more intense, cartoon game, no voices."),
    ("flamethrower_burst", 0.8, False, "A flamethrower spraying fire: a roaring whoosh of flame with crackling and a soft gassy hiss, short burst."),
    ("minigun_spin_up", 0.8, False, "A rotary minigun's barrels spinning up: a fast rising mechanical whir with a motor whine, no shots."),
    ("minigun_shot", 0.5, False, "A single shot from a rotary minigun firing very fast: a short punchy brrt-crack with a metallic rattle, dry and tight."),
    ("harpoon_fire", 0.8, False, "A speargun firing: a heavy rubber band snap thwang and a metal spear whooshing away."),
    ("harpoon_reel", 1.0, False, "A rope being reeled in fast: a fishing reel winding with a ratcheting click and a rope zipping through the air."),
    ("c4_stick", 0.5, False, "A sticky explosive charge slapping onto a surface: a wet sticky thwap followed by a tiny electronic beep."),
    ("c4_beep", 0.6, False, "A bomb detonator being pressed: a quick button click and two fast high electronic beeps, cartoon game."),
    ("landmine_arm", 0.6, False, "A landmine being set down and armed: a soft metal clunk on the ground, a mechanical click and a quiet low beep."),
    ("arm_rip", 1.2, False, "A cartoon slapstick tug-of-war: a stretchy rubbery creaking strain building up for a moment, then a loud comedic pop as something comes loose, rubber toy sound, not gory, no voices."),
    ("tnt_fuse", 3.0, False, "A lit dynamite fuse burning: a steady fizzing, crackling and sparkling hiss of a fuse, constant, cartoon game."),
    # --- bodies and movement ---
    ("body_thud", 0.7, False, "A ragdoll body slamming hard into the ground: a heavy dull whump with clothes rustling, cartoonish and weighty, no cracking."),
    ("body_fall", 1.2, False, "A person collapsing to the floor: a short clothes rustle, then two soft heavy thumps as the body hits the ground and settles."),
    ("body_scrape_loop", 4.0, True, "A body being dragged along a rough concrete street: a continuous coarse grinding scrape of fabric over grit and gravel, seamless loop."),
    ("walk_loop", 4.0, True, "Footsteps of one person walking at a relaxed pace in sneakers on a concrete sidewalk, steady even rhythm, about two steps per second, seamless loop."),
    ("land_soft", 0.5, False, "A player landing on their feet after a small jump onto concrete: a short soft sneaker thump with a tiny scuff."),
    ("land_hard", 0.8, False, "A player landing heavily on concrete after a long fall: a deep impact thud with both feet, a grunt-free crunchy scuff and a short low rumble."),
    ("dash_whoosh", 0.6, False, "A superhero-style quick dash: a fast energetic whoosh with a slight electric shimmer, rising then cutting off."),
    # --- monsters ---
    ("zombie_groan_1", 2.5, False, "A slow cartoonish zombie groan: a low, raspy, drawn-out moan, hungry and lazy, spooky but fun like a family-friendly horror game."),
    ("zombie_groan_2", 2.0, False, "A cartoon zombie gurgling growl: a throaty raspy rumble rising into a short moan, spooky but family-friendly."),
    ("zombie_hurt", 0.8, False, "A cartoon zombie getting hit: a short surprised raspy grunt-groan, goofy and spooky."),
    ("zombie_death", 2.0, False, "A cartoon zombie being defeated: a long falling raspy moan that fades into a dusty collapse thump, family-friendly."),
    ("zombie_attack", 1.0, False, "A cartoon zombie lunging to attack: an aggressive raspy snarl with a quick swipe whoosh."),
    # --- vehicles ---
    ("car_engine_idle_loop", 6.0, True, "A small petrol car engine idling: a steady low rumbling purr with subtle mechanical ticking, constant RPM, seamless loop."),
    ("car_engine_drive_loop", 6.0, True, "A small petrol car engine driving at steady medium speed: a smooth sustained mid-RPM engine hum with light tire road noise, constant pitch, seamless loop."),
    ("car_horn", 1.0, False, "A regular car horn honk: one short loud double beep-beep from a compact car."),
    ("tire_screech", 1.5, False, "Car tires skidding and screeching on asphalt during a hard turn: a long squealing rubber screech that fades."),
    ("car_crash", 1.8, False, "A car crashing into another car at medium speed: a loud crunch of bending metal, cracking plastic, a burst of glass shards tinkling down."),
    ("car_door", 0.7, False, "A car door being opened and slammed shut: a latch click then a solid heavy thunk."),
    ("police_siren_loop", 6.0, True, "An American police car siren wailing: a classic rising and falling wail, constant volume, seamless loop."),
    ("helicopter_rotor_loop", 6.0, True, "A military helicopter hovering nearby: deep rhythmic thumping rotor blades, turbine whine underneath, steady and constant, seamless loop."),
    # --- world ---
    ("factory_press_slam", 1.2, False, "A huge industrial hydraulic press slamming down: a hiss of hydraulics, then a massive heavy metallic boom clang with a deep resonant ring."),
    ("heavy_gate_slide", 2.5, False, "A heavy metal gate sliding open on rusty rails: a long grinding rumble with squeaky metal and a clunk when it stops."),
    ("city_ambience_loop", 20.0, True, "Daytime city street ambience: distant traffic hum, occasional far-away car horns, faint birds, light wind, no voices, seamless loop."),
    ("wind_loop", 15.0, True, "Gentle outdoor wind blowing across an open rooftop, soft gusts rising and falling, seamless loop."),
    # --- ui ---
    ("ui_click", 0.5, False, "A user interface button click for a cartoon game: a short bright plastic pop-click, satisfying and soft."),
    ("ui_hover", 0.5, False, "A user interface hover tick: a tiny soft high blip, very subtle."),
    ("ui_open", 0.5, False, "A cartoon game menu panel opening: a quick bouncy upward swoosh with a soft pop."),
    ("ui_close", 0.5, False, "A cartoon game menu panel closing: a quick downward swoosh with a soft muted pop."),
    ("ui_purchase", 1.0, False, "A successful purchase in a cartoon game shop: a cheerful cash register cha-ching with sparkly coins jingling."),
    ("ui_error", 0.5, False, "A user interface error: a short low double buzz bonk, friendly but clearly negative."),
    ("ui_notification", 0.8, False, "A friendly game notification pop-up: a bright two-note rising chime, short and pleasant."),
    ("tutorial_step", 0.8, False, "A tutorial step completed in a cartoon game: a bright happy three-note ascending ding with a sparkle."),
    ("wanted_star_up", 0.9, False, "A wanted level star appearing in a cops-and-robbers game: a tense dramatic metallic stinger hit with a short alarm-like whoop."),
    ("wanted_alarm", 2.0, False, "A short police alert alarm for a cartoon crime game: two quick urgent electronic siren whoops."),
    # --- the Arsenal comic book (client/Arsenal) ---
    ("comic_page_turn", 1.0, False, "Turning one page of a glossy comic book by its corner: a quick crisp paper swish as a single thin page lifts, flips over and lands flat with a light papery flap, close-up, snappy."),
    ("comic_book_open", 1.0, False, "Opening a comic book: the thicker glossy card cover swung open with a soft papery whoosh and landing flat on the table with a gentle slap, close-up."),
    ("comic_book_close", 0.7, False, "Closing a comic book: the cover and pages flapping shut with a quick papery whoomp ending in a soft flat slap, close-up."),
    # --- dummy voices (speech bubbles) ---
    ("dummy_talk", 1.2, False, "A cartoon character talking in gibberish: quick high-pitched babbling syllables like Animal Crossing style speech, no real words."),
    ("dummy_shout", 1.0, False, "A cartoon character shouting angrily in gibberish: a loud short squeaky indignant yell, no real words, comedic."),
    ("dummy_think", 1.2, False, "A cartoon character thinking: a soft curious hmmm hum rising in pitch, no words."),
]


def load_key() -> str:
    env = ROOT / ".env"
    if env.exists():
        for line in env.read_text(encoding="utf-8").splitlines():
            if line.startswith("ELEVENLABS_API_KEY="):
                value = line.split("=", 1)[1].strip()
                if value:
                    return value
    key = os.environ.get("ELEVENLABS_API_KEY", "")
    if not key:
        sys.exit("ELEVENLABS_API_KEY missing (.env or environment)")
    return key


def generate(key: str, name: str, seconds: float, loop: bool, text: str) -> str:
    path = OUT / f"{name}.mp3"
    if path.exists():
        return f"skip  {name}"
    body = {
        "text": text + STYLE,
        "duration_seconds": seconds,
        "prompt_influence": 0.6,
        "model_id": "eleven_text_to_sound_v2",
    }
    if loop:
        body["loop"] = True
    req = urllib.request.Request(URL, data=json.dumps(body).encode(), method="POST",
                                 headers={"xi-api-key": key, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            data = r.read()
    except urllib.error.HTTPError as e:
        return f"FAIL  {name}: HTTP {e.code} {e.read()[:200].decode(errors='replace')}"
    except OSError as e:
        return f"FAIL  {name}: {e}"
    path.write_bytes(data)
    return f"ok    {name} ({len(data) // 1024} KB)"


def wire() -> None:
    """Write the approved ids (gen/assets.json, from upload_asset.py) into src/shared/Sfx.luau's generated block."""
    ids = json.loads((OUT / "assets.json").read_text(encoding="utf-8"))
    lines = [f'Sfx.{name.upper()} = "{e["assetId"]}"' for name, e in sorted(ids.items())
             if e.get("moderation") == "Approved"]
    sfx = ROOT / "src/shared/Sfx.luau"
    text = sfx.read_text(encoding="utf-8")
    head, rest = text.split("--@generated-sfx-begin\n", 1)
    _, tail = rest.split("--@generated-sfx-end", 1)
    sfx.write_text(head + "--@generated-sfx-begin\n" + "\n".join(lines) + "\n--@generated-sfx-end" + tail, encoding="utf-8")
    print(f"wired {len(lines)} ids; not approved: {sorted(n for n, e in ids.items() if e.get('moderation') != 'Approved')}")


def main() -> None:
    if sys.argv[1:] == ["--wire"]:
        return wire()
    names = {s[0] for s in SOUNDS}
    assert len(names) == len(SOUNDS), "duplicate sound name"
    assert all(0.5 <= s[1] <= 30 for s in SOUNDS), "API takes 0.5-30 s"
    wanted = set(sys.argv[1:])
    unknown = wanted - names
    if unknown:
        sys.exit(f"unknown: {', '.join(sorted(unknown))}")
    key = load_key()
    OUT.mkdir(exist_ok=True)
    todo = [s for s in SOUNDS if not wanted or s[0] in wanted]
    with ThreadPoolExecutor(3) as pool:  # creator plan allows a few concurrent requests
        for line in pool.map(lambda s: generate(key, *s), todo):
            print(line, flush=True)


if __name__ == "__main__":
    main()
