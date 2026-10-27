"""Numbers lifted from the Godot project (working tree, 2026-10-25). Every constant names its source file.

Nothing here is invented except where a comment says ASSUMPTION.
"""
import math

# --- scripts/systems/wave_director.gd -------------------------------------------------------------
INTERMISSION = 90.0
SIREN_LEAD = 3.0
CLEARED_HOLD = 2.0
STRAGGLER_TIME = 20.0
LIVE_CAP = 60
TYPE_WEIGHTS = [0.55, 0.35, 0.10]
FOREMAN_AT = 0.45
EARLY_BIRD_AL = 5
SALVAGE_EVERY = 2
SALVAGE = {"cu": 2, "au": 1, "pc": 1}

# --- data/difficulty/default_difficulty.tres + scripts/systems/difficulty_curve.gd -----------------
def spawn_window(w): return min(45.0 + 7.0 * (w - 1), 210.0)
def base_budget(w): return 12.0 + 6.0 * pow(w, 1.3)
def is_big_haul(w): return w > 0 and w % 5 == 0
def budget(w): return base_budget(w) * (1.3 if is_big_haul(w) else 1.0)
def hp_mult(w): x = w - 1; return 1.0 + 0.07 * x + 0.002 * x * x
def dmg_mult(w): x = w - 1; return 1.0 + 0.04 * x + 0.001 * x * x
def drop_mult(w): return 1.0 + 0.03 * (w - 1)
def trait_count(w): return 0 if w <= 5 else (1 if w <= 15 else (2 if w <= 30 else 3))
def lane_count(w): return 2 + sum(1 for t in (5, 15, 30) if w >= t)
def thief_share(w, thieving=False):
    s = min(0.4, 0.10 + 0.015 * (w - 1))
    return min(0.6, s * 1.5) if thieving else s
def attack_phase(w): return 0 if w <= 5 else (1 if w < 16 else (2 if w < 31 else 3))
def farmer_tokens(w): return [2, 3, 4, 5][attack_phase(w)]
def charge_mult(w): return [1.0, 0.9, 0.8, 0.7][attack_phase(w)]
def aim_lead(w): return 0.0 if w < 10 else [0.0, 0.3, 0.6, 0.6][attack_phase(w)]
def spitter_share(w): return 0.0 if w < 7 else min(0.4, 0.10 + 0.02 * (w - 7))
def column_weights(w):
    return [None, [0.60, 0.28, 0.12], [0.52, 0.30, 0.18], [0.45, 0.33, 0.22]][attack_phase(w)]
def arm_guard_up(w): return w >= 6
def climber_count(w, others):
    if w < 3: return 0
    return int(math.floor(others * 0.25 / 0.75 + 0.5))
def trio_chance(w, a):
    if a["type"] == 2 or a["cls"] == 2: return 0.0
    early, late = a["trio"], a["trio_late"]
    if late < 0 or w < 3: return early
    step = early + (late - early) * 0.6667
    t = min(1.0, max(0.0, (w - 3) / 12.0))
    return step + (late - step) * t
def drone_cap(w): return 0 if w < 5 else (1 if w < 8 else (2 if w < 16 else 3))
def heavy_cap(w): return 1 + int(max(0.0, w - 6.0) // 8)
def rooftop_cap(w): return 2 if w <= 5 else (3 if w <= 15 else (4 if w <= 30 else 5))

def pacing(t):
    first = 1.0 * math.exp(-((t - 0.22) / 0.15) ** 2)
    second = 1.5 * math.exp(-((t - 0.7) / 0.15) ** 2)
    x = min(1.0, max(0.0, t / 0.15)); smooth = x * x * (3 - 2 * x)
    return 0.55 * smooth + first + second

def spawn_schedule(count, window):
    if count <= 0: return []
    S = 200
    cdf = [0.0]
    for i in range(S):
        cdf.append(cdf[-1] + pacing((i + 0.5) / S))
    total = cdf[-1]; out = []; s = 0
    for k in range(count):
        target = (k + 0.5) / count * total
        while s < S and cdf[s + 1] < target: s += 1
        span = cdf[s + 1] - cdf[s]
        frac = (target - cdf[s]) / span if span > 0 else 0
        out.append((s + frac) / S * window)
    out[0] = 0.0
    return out

# --- data/robots/archetypes/*.tres (RobotArchetype defaults where a field is absent) --------------
TYPE_COSTS = [2.0, 4.0, 14.0]
CLASS_MULT = [1.0, 1.25, 1.6]
TYPE_SCALES = [1.0, 1.75, 2.8]
ARCH = {
    "nibbler": dict(type=0, cls=0, unlock=1, weight=1.0, radius=0.35, hp=30, speed=8.0, range=1.8,
                    interval=1.0, windup=0.3, dmg_f=4, dmg_s=6, focus=0.7, trio=0.4, trio_late=0.7,
                    distract=0.3, triggers={"hurt", "near"}, drange=8, commit=2, chase=6, leash=25, giveup=3,
                    al=(1, 2), al_bonus=1, cu=0.25, cu_n=(1, 1), au=0.02, pc=0.01, guard=0.0),
    "clanker": dict(type=1, cls=0, unlock=2, weight=1.0, radius=0.6, hp=60, speed=4.5, range=2.2,
                    interval=1.2, windup=0.35, dmg_f=8, dmg_s=12, focus=0.7, trio=0.15, trio_late=-1,
                    distract=0.5, triggers={"hurt"}, drange=10, commit=2, chase=8, leash=30, giveup=3,
                    al=(1, 3), al_bonus=1, cu=0.6, cu_n=(1, 1), au=0.06, pc=0.03, guard=0.5),
    "thumper": dict(type=2, cls=0, unlock=6, weight=1.0, radius=1.0, hp=400, speed=2.5, range=3.0,
                    interval=2.5, windup=0.8, dmg_f=25, dmg_s=60, focus=0.8, trio=0.0, trio_late=-1,
                    distract=0.2, triggers={"hurt"}, drange=10, commit=2, chase=10, leash=20, giveup=4,
                    al=(4, 6), al_bonus=1, cu=1.0, cu_n=(2, 3), au=1.0, pc=1.0, guard=0.0,
                    shock_dmg=10, shock_r=8),
    "roof_lobber": dict(type=0, cls=1, unlock=3, weight=0.55, radius=0.35, hp=45, speed=6.0,
                        focus=0.5, trio=0.0, trio_late=-1, distract=0.7, triggers={"near", "repairing"},
                        drange=24, commit=2, chase=0, leash=0, giveup=0, al=(2, 3), al_bonus=1,
                        cu=0.75, cu_n=(1, 1), au=0.12, pc=0.08, guard=0.0, attack="lobber_lob"),
    "drone": dict(type=0, cls=2, unlock=5, weight=0.6, radius=0.7, hp=35, speed=9.0, focus=0.6,
                  trio=0.0, trio_late=-1, distract=0.8, triggers={"airborne", "near"}, drange=24, commit=2,
                  chase=8, leash=36, giveup=0, al=(2, 3), al_bonus=1, cu=0.5, cu_n=(1, 1), au=0.1, pc=0.1,
                  guard=0.0, attack="drone_shot"),
    "spitter": dict(type=0, cls=1, unlock=7, weight=1.0, radius=0.35, hp=30, speed=7.0, focus=0.6,
                    trio=0.4, trio_late=0.7, distract=0.6, triggers={"hurt", "near", "repairing"}, drange=12,
                    commit=2, chase=8, leash=30, giveup=0, al=(1, 2), al_bonus=0, cu=0.2, cu_n=(1, 1),
                    au=0.01, pc=0.01, guard=0.0, attack="spitter_pea"),
}
DIRECTOR_ARCHETYPES = ["nibbler", "clanker", "thumper", "roof_lobber", "drone"]
def threat_cost(name):
    a = ARCH[name]; return TYPE_COSTS[a["type"]] * CLASS_MULT[a["cls"]]

# --- data/source/robots/attacks/m2.csv -------------------------------------------------------------
ATTACKS = {
    "drone_shot": dict(kind="straight", charge=0.9, interval=2.8, dmg_f=4, dmg_s=8, speed=20, range=32),
    "lobber_lob": dict(kind="lob", charge=1.1, interval=3.6, dmg_f=6, dmg_s=12, speed=20, range=24),
    "spitter_pea": dict(kind="straight", charge=0.8, interval=2.2, dmg_f=3, dmg_s=5, speed=14, range=18),
}

# --- scripts/ai/robot.gd ----------------------------------------------------------------------------
FOREMAN_HP_MULT = 3.0
FOREMAN_DROPS = {"al": 10, "cu": 6, "au": 2, "pc": 3}
SACK = 20.0
ESCAPE_RADIUS = 102.0

# --- data/source/robots/traits/*.csv ---------------------------------------------------------------
TRAITS = {
    "speedy": dict(hp=1.0, speed=1.25), "armored": dict(hp=1.4, speed=0.9), "gilded": dict(hp=1.0, speed=1.0, gold=3.0),
    "thieving": dict(hp=1.0, speed=1.0, thieving=True),
    "overcharged": dict(hp=1.0, speed=1.0, pc=2.0, blast_r=3.5, blast_dmg=80, blast_farmer=12),
}

# --- scenes/farm/farm.tscn (silo at the origin) ----------------------------------------------------
SILO_R = 4.0
LANES = {1: (-42.1, -101.6), 2: (42.1, -101.6), 3: (101.6, -42.1), 4: (101.6, 42.1),
         5: (42.1, 101.6), 6: (-42.1, 101.6), 7: (-101.6, 42.1), 8: (-101.6, -42.1)}
SHED = (-20.0, -2.0)
PORCH = (-30.0, 22.0)
BELL = (-21.0, 31.8)
CHUTE = (0.0, 5.0)  # ASSUMPTION: chute marker angle not checked; any wall point gives the same timings.
# scripts/ai/vertical_robot.gd ROOF_SITES, offsets applied to farm.tscn building positions (no rotation).
ROOFS = [
    dict(name="Tool shed", entry=(-14.8, -2.0), top=(-16.7, -2.0), edge=4.05, h=4.05),
    dict(name="Barn", entry=(-21.6, -28.0), top=(-32.0, -28.0), edge=9.15, h=13.1),
    dict(name="Stables", entry=(20.0, -28.6), top=(20.0, -31.4), edge=6.1, h=6.1),
    dict(name="Chicken house", entry=(27.7, -6.0), top=(30.8, -6.0), edge=3.6, h=3.6),
]
CLIMB_SPEED = 3.2
DRONE_ORBIT_R = 22.0
DRONE_H = 14.0
DRONE_FIRE_R = 36.0

# --- scripts/systems/silo.gd, silo_crack.gd, scenes/farm/silo.tscn ---------------------------------
MAX_STRUCTURE = 1000.0
MAX_GRAIN = 1000.0
CRACK_EVERY = 0.1
MAX_CRACKS = 10
LEAK = [0.6, 1.2, 2.0]
HITS_TO_GROW = [3, 4]
STAGE_SECONDS = [1.2, 2.1, 2.4]
HARVEST_BONUS = 40.0
# 16 sockets: 8 ground (alternating 1.3 / 2.6 m), 4 on catwalk 1 (9.3 m), 4 on catwalk 2 (17.3 m).
SOCKETS = [(0, i * math.pi / 4 + math.pi / 8) for i in range(8)] + \
          [(1, i * math.pi / 2 + math.pi / 4) for i in range(4)] + \
          [(2, i * math.pi / 2 + math.pi / 8) for i in range(4)]
GROUND_ONLY_UNTIL = 2

# --- scripts/player/*.gd, scripts/components/heal_zone.gd, pickup.gd -------------------------------
RUN_SPEED = 7.0
AIM_SPEED = 4.0
MAX_HP = 100.0
ARMOR_REGEN = 10.0
ARMOR_DELAY = 4.0
PORCH_HEAL = 15.0
MAGNET = 3.0

# --- data/weapons/*.tres ---------------------------------------------------------------------------
WEAPONS = {
    "wrench": dict(dmg=25.0, rate=1.6, reach=2.2, combo=1.5, combo_reset=1.2),
    "pistol": dict(dmg=12.0, rate=4.0, range=40.0, mag=10, reload=1.1),
    "shotgun": dict(dmg=10.0, rate=1.0, range=16.0, mag=5, reload=1.8, pellets=7, spread_deg=11.0, inner=0.45),
    "rifle": dict(dmg=55.0, rate=0.8, range=100.0, mag=4, reload=1.9, pierce=1),
}
WEAK_POINT_MULT = 2.0

# --- data/source/upgrades/*.csv expanded by tools/content_tables.gd _add_recipe --------------------
def _r(x): return int(math.floor(x + 0.5))  # Godot roundi/roundf: half away from zero (positive here)
def _whole(x): return max(1.0, float(_r(x)))

def recipe(kind, base, levels):
    parts = []
    def add(p, b, first, last):
        if first <= last: parts.append((p, b, first, last))
    if kind in ("al_to_pc", "al_to_au"):
        add("al", base, 1, levels); add("cu", _whole(base * 0.2), 4, levels); add("au", _whole(base * 0.067), 7, levels)
        if kind == "al_to_pc":
            add("pc", 1.0, 9, min(9, levels)); add("pc", 2.0, 10, levels)
    elif kind == "al_cu":
        add("al", base, 1, levels); add("cu", _whole(base * 0.2), 4, levels)
    elif kind == "al_cu_au":
        add("al", base, 1, levels); add("cu", _whole(base * 0.125), 1, levels)
        add("au", _whole(base * 0.04), int(math.ceil(levels / 2.0)) + 1, levels)
    return parts

def fixed(*items):
    return [(p, b, f, l) for (p, b, f, l) in items]

UPGRADES = {
    "attack.wrench_damage": dict(max=10, req=[], cost=recipe("al_to_pc", 12, 10)),
    "attack.wrench_speed": dict(max=5, req=[], cost=recipe("al_cu", 15, 5)),
    "attack.pistol": dict(max=1, req=[], cost=fixed(("al", 20, 1, 1))),
    "attack.pistol_damage": dict(max=10, req=[("attack.pistol", 1)], cost=recipe("al_to_pc", 15, 10)),
    "attack.pistol_rate": dict(max=10, req=[("attack.pistol", 1)], cost=recipe("al_to_pc", 15, 10)),
    "attack.pistol_handling": dict(max=5, req=[("attack.pistol", 1)], cost=recipe("al_cu", 20, 5)),
    "attack.shotgun": dict(max=1, req=[("attack.pistol", 1)], cost=fixed(("al", 35, 1, 1))),
    "attack.shotgun_damage": dict(max=10, req=[("attack.shotgun", 1)], cost=recipe("al_to_pc", 15, 10)),
    "attack.rifle": dict(max=1, req=[("attack.pistol", 1)], cost=fixed(("al", 45, 1, 1), ("cu", 3, 1, 1))),
    "attack.rifle_damage": dict(max=10, req=[("attack.rifle", 1)], cost=recipe("al_to_pc", 18, 10)),
    "defend.hearty_breakfast": dict(max=5, req=[], cost=recipe("al_cu", 15, 5)),
    "defend.porch_swing": dict(max=5, req=[], cost=fixed(("al", 12, 1, 5))),
    "defend.armor_overalls": dict(max=1, req=[], cost=fixed(("al", 30, 1, 1))),
    "defend.armor_vest": dict(max=1, req=[("defend.armor_overalls", 1)], cost=fixed(("al", 60, 1, 1), ("cu", 8, 1, 1))),
    "defend.plating_tin": dict(max=1, req=[], cost=fixed(("al", 40, 1, 1))),
    "farmhand.scrap_magnet": dict(max=5, req=[], cost=fixed(("al", 10, 1, 5))),
    "repair.elbow_grease": dict(max=8, req=[], cost=recipe("al_to_au", 12, 8)),
    "travel.comfy_boots": dict(max=5, req=[], cost=recipe("al_cu", 12, 5)),
    "travel.jetpack": dict(max=1, req=[], cost=fixed(("al", 40, 1, 1), ("cu", 15, 1, 1)), min_wave=3),
}
UPGRADE_NAMES = {
    "attack.wrench_damage": "Swing Damage", "attack.wrench_speed": "Swing Speed", "attack.pistol": "Rivet Pistol",
    "attack.pistol_damage": "Pistol Damage", "attack.pistol_rate": "Pistol Fire Rate",
    "attack.pistol_handling": "Pistol Handling", "attack.shotgun": "Barn Blaster", "attack.shotgun_damage": "Shotgun Damage",
    "attack.rifle": "Longneck Rifle", "attack.rifle_damage": "Rifle Damage", "defend.hearty_breakfast": "Hearty Breakfast",
    "defend.porch_swing": "Porch Swing", "defend.armor_overalls": "Armor: Overalls", "defend.armor_vest": "Armor: Padded Vest",
    "defend.plating_tin": "Plating: Tin", "farmhand.scrap_magnet": "Scrap Magnet", "repair.elbow_grease": "Elbow Grease",
    "travel.comfy_boots": "Comfy Boots", "travel.jetpack": "Milk-Can Jetpack",
}

def upgrade_cost(uid, level):
    out = {}
    for (p, b, first, last) in UPGRADES[uid]["cost"]:
        if first <= level <= last:
            amt = _r(b * pow(1.25, level - first))
            if amt > 0: out[p] = out.get(p, 0) + amt
    return out

# Tutorial (docs/LEVEL_0_MORNING_CHORES.md + tutorial_director.gd): 6 Al -> wrench, dummy 5 Al, bell +5 Al.
TUTORIAL_AL_AFTER = 10
