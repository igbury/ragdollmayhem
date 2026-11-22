"""How long a player takes to buy every weapon: a Monte Carlo of the cash progression.

Prices, kill pay and the hooligan bonus come from src/shared/Progression.luau (or another copy of it, e.g.
an older one from git), each weapon's kind from src/shared/Weapons.luau, so it follows any retune.

    python tools/pacing_sim.py                     # 15 players listed, then 2000 for the spread
    python tools/pacing_sim.py --file old.luau     # the same for another Progression.luau

Assumptions (guesses, as in Progression's comment; retune once Analytics shows real numbers):
  * kills a minute: 3 with only the fists, rising evenly to 8 with every weapon owned, times the player's
    skill (0.5x-1.8x, most near 1); kills come at random (Poisson);
  * the weapon a kill is made with: the newest one bought half the time, any owned one 35%, the fists 15%;
    it pays by its kind (melee / ranged / explosive), a hooligan (5 of 100 dummies) 1.1x, rounded;
  * buying: the cheapest weapon not owned yet, as soon as there is the cash (now and then one of the
    three cheapest instead); no passes, no Anime Pack, no group Frostgun.
"""
import argparse
import math
import random
import re
import statistics
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HOOLIGAN_SHARE = 0.05  # Kinds weights in the main server script: Normal 80, Cop 15, Hooligan 5
PAY_KIND = {"melee": "kills", "gun": "ranged", "bow": "ranged", "knife": "ranged", "thrown": "thrown", "rocket": "thrown"}


def load(progression: Path):
    text = progression.read_text(encoding="utf-8")
    block = text[text.index("Progression.PRICE = {"):]
    block = block[:block.index("}")]
    prices = {k: int(v) for k, v in re.findall(r"^\s*(\w+) = (\d+),", block, re.M)}
    cash = dict(re.findall(r"(kills|ranged|thrown) = (\d+)", re.search(r"KILL_CASH = \{[^}]*\}", text).group(0)))
    cash = {k: int(v) for k, v in cash.items()}
    m = re.search(r"Hooligan = ([\d.]+)", text)
    hooligan = float(m.group(1)) if m else 1.0
    kinds = dict(re.findall(r'id = "(\w+)".*?kind = "(\w+)"', (ROOT / "src/shared/Weapons.luau").read_text(encoding="utf-8")))
    return prices, cash, hooligan, kinds


def play(rng: random.Random, prices, cash_by, hooligan, kinds, double=1):
    """One player from nothing to every weapon. Returns the minute of each buy, in order."""
    left = sorted(prices, key=lambda w: (prices[w], w))
    owned = ["Fists"]
    skill = min(1.8, max(0.5, rng.lognormvariate(0, 0.3)))
    t, cash, buys = 0.0, 0, []
    target = left[0]
    while left:
        rate = (3 + 5 * (len(owned) - 1) / len(prices)) * skill  # kills a minute
        t += rng.expovariate(rate)
        roll = rng.random()
        weapon = owned[-1] if roll < 0.5 else (rng.choice(owned) if roll < 0.85 else "Fists")
        pay = cash_by[PAY_KIND.get(kinds.get(weapon, "melee"), "kills")]
        if rng.random() < HOOLIGAN_SHARE:
            pay *= hooligan
        cash += round(pay * double)
        while left and cash >= prices[target]:
            cash -= prices[target]
            left.remove(target)
            owned.append(target)
            buys.append(t)
            if left:
                target = rng.choice(left[:3]) if rng.random() < 0.3 else left[0]
    return buys


def fmt(minutes: float) -> str:
    h, m = divmod(round(minutes), 60)
    return f"{h} h {m:02d} min" if h else f"{m} min"


def demo():  # the smallest check: a player always ends up owning everything, buys in time order
    prices, cash, hooligan, kinds = {"A": 10, "B": 50}, {"kills": 15, "ranged": 10, "thrown": 5}, 1.1, {}
    buys = play(random.Random(1), prices, cash, hooligan, kinds)
    assert len(buys) == 2 and buys == sorted(buys)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--file", type=Path, default=ROOT / "src/shared/Progression.luau")
    ap.add_argument("--players", type=int, default=15)
    ap.add_argument("--seed", type=int, default=7)
    a = ap.parse_args()
    demo()
    prices, cash, hooligan, kinds = load(a.file)
    n = len(prices)
    print(f"{n} weapons for sale, {sum(prices.values())}$ in all; a kill pays {cash}, hooligan x{hooligan}")
    rng = random.Random(a.seed)
    print(f"\n{'player':>6}  {'1st 5':>9}  {'half':>11}  {'all':>11}  {'all with 2X CASH':>16}")
    for p in range(1, a.players + 1):
        state = rng.getstate()
        buys = play(rng, prices, cash, hooligan, kinds)
        rng.setstate(state)  # the same player and luck, with 2X CASH
        doubled = play(rng, prices, cash, hooligan, kinds, double=2)
        print(f"{p:>6}  {fmt(buys[4]):>9}  {fmt(buys[n // 2 - 1]):>11}  {fmt(buys[-1]):>11}  {fmt(doubled[-1]):>16}")
    for label, double in (("no pass", 1), ("2X CASH", 2)):
        ends = sorted(play(random.Random(a.seed * 1000 + i), prices, cash, hooligan, kinds, double)[-1] for i in range(2000))
        q = lambda f: ends[min(len(ends) - 1, math.floor(f * len(ends)))]
        print(f"\n2000 players, {label}: all weapons in {fmt(statistics.median(ends))} (median), "
              f"fastest tenth by {fmt(q(0.1))}, slowest tenth after {fmt(q(0.9))}")


if __name__ == "__main__":
    main()
