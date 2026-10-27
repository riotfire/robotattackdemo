"""Expected time-to-kill (seconds of continuous attacking, no walking) per weapon, robot and wave, at the
testers' average accuracy. python3 ttk_table.py"""
import math, os, sys
sys.path.insert(0, os.path.dirname(__file__))
from game_data import ARCH, hp_mult, FOREMAN_HP_MULT

MELEE = 0.79           # middle of the 70-88 % band
PEAK = 0.45            # typical tester's best-case gun accuracy

def gun_acc(d, rifle=False, peak=PEAK):
    dd = max(d, 3.0) - 3.0
    if rifle:
        return max(0.04, 0.04 + (peak - 0.04) * max(0, 1 - dd / 90))
    return max(0.04, 0.04 + (peak - 0.04) * max(0, 1 - dd / 35) ** 1.3)

def dps(weapon, d, lv=0, target="nibbler"):
    if weapon == "wrench":
        return 25 * (1 + 0.12 * lv) * (1 + 1 + 1.5) / 3 * 1.6 * (1 + 0.08 * lv) * MELEE
    if weapon == "pistol":
        rate = min(4 * (1 + 0.08 * lv), 1 / 0.3); mag = 10; rel = 1.1
        cycle = mag / rate + rel
        return 12 * (1 + 0.12 * lv) * 1.12 * gun_acc(d) * mag / cycle
    if weapon == "shotgun":
        tr = 1.3 if target == "thumper" else (0.75 if target == "clanker" else 0.45)
        t = math.tan(math.radians(11))
        g = lambda ring: max(0.0, min(1.0, (1.4 * tr - ring) / (0.8 * tr)))
        a = gun_acc(d)
        pellets = a * (1 + 3 * g(0.45 * t * d) + 3 * g(t * d))
        cycle = 5 / 1.0 + 1.8
        return 10 * (1 + 0.12 * lv) * pellets * 5 / cycle
    if weapon == "rifle":
        cycle = 4 / 0.8 + 1.9
        return 55 * (1 + 0.12 * lv) * 1.12 * gun_acc(d, True) * 4 / cycle

def hp(name, wave, foreman=False):
    return ARCH[name]["hp"] * hp_mult(wave) * (FOREMAN_HP_MULT if foreman else 1)

ROWS = [("nibbler", 1, False), ("clanker", 2, False), ("roof_lobber", 3, False), ("drone", 5, False),
        ("thumper", 5, True), ("thumper", 6, False), ("nibbler", 10, False), ("clanker", 10, False)]
CASES = [("wrench", 2, 0), ("wrench", 2, 4), ("pistol", 10, 0), ("pistol", 25, 0), ("pistol", 10, 3),
         ("shotgun", 6, 0), ("rifle", 25, 0), ("rifle", 45, 0)]

if __name__ == "__main__":
    head = ["Robot (wave)", "HP"] + [f"{w} {d}m L{lv}" for w, d, lv in CASES]
    print("| " + " | ".join(head) + " |")
    print("|" + "---|" * len(head))
    for name, wave, fm in ROWS:
        h = hp(name, wave, fm)
        cells = []
        for w, d, lv in CASES:
            if w == "wrench" and name in ("roof_lobber", "drone"):
                cells.append("roof/air"); continue
            cells.append(f"{h / dps(w, d, lv, name):.1f}s")
        label = ("Foreman" if fm else name.replace("_", " ").title()) + f" (w{wave})"
        print(f"| {label} | {h:.0f} | " + " | ".join(cells) + " |")
    print()
    print("Accuracy used: wrench", MELEE, "; gun at 6/10/25/45 m:", [round(gun_acc(d), 2) for d in (6, 10, 25, 45)],
          "; rifle at 25/45 m:", [round(gun_acc(d, True), 2) for d in (25, 45)])
