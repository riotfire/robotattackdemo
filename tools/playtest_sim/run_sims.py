"""Runs the five playtest personas (one per boredom bucket) plus a Monte Carlo cohort, and writes results.json.

python3 tools/playtest_sim/run_sims.py [--cohort N]
"""
import json
import os
import random
import statistics
import sys

sys.path.insert(0, os.path.dirname(__file__))
from sim import BASE_PRIORITY, Persona, Session, PHASE_NAMES  # noqa: E402
from game_data import UPGRADE_NAMES  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))

PERSONAS = [
    Persona("Sim 1 - 5-minute quitter (5% of testers)", 5.0, 101, melee_acc=0.71, proj_peak=0.30,
            repair_intermission=0.25, fight_chaser=0.35, priority=BASE_PRIORITY),
    Persona("Sim 2 - 10-minute player (44% of testers)", 10.0, 202, melee_acc=0.76, proj_peak=0.42,
            repair_intermission=0.30, fight_chaser=0.45, priority=BASE_PRIORITY),
    Persona("Sim 3 - 15-minute player (32% of testers)", 15.0, 303, melee_acc=0.79, proj_peak=0.48,
            repair_intermission=0.35, fight_chaser=0.45, shotgun_after_deaths=1, priority=BASE_PRIORITY),
    Persona("Sim 4 - 25-minute player (13% of testers)", 25.0, 404, melee_acc=0.83, proj_peak=0.52,
            repair_intermission=0.40, fight_chaser=0.50, shotgun_after_deaths=1, rifle_after_deaths=2,
            priority=BASE_PRIORITY),
    Persona("Sim 5 - 30+ minute player (6% of testers)", 34.0, 505, melee_acc=0.87, proj_peak=0.56,
            repair_intermission=0.45, fight_chaser=0.55, shotgun_after_deaths=2, rifle_after_deaths=1, bell=0.15,
            priority=BASE_PRIORITY),
]

BUCKETS = [(0.05, 3.5, 7.5), (0.44, 7.5, 12.5), (0.32, 12.5, 20.0), (0.13, 20.0, 27.5), (0.06, 30.0, 40.0)]


def summarize(s):
    st = s.stats
    ttk = {k: round(statistics.mean(v), 1) for k, v in st["ttk"].items() if v}
    eq_total = sum(w["equipped"] for w in s.wstats.values()) or 1.0
    weapons = {}
    for w, d in s.wstats.items():
        if d["fired"] == 0 and d["equipped"] == 0:
            continue
        weapons[w] = dict(fired=d["fired"], hits=d["hits"], hit_rate=round(d["hits"] / d["fired"], 3) if d["fired"] else None,
                          damage=round(d["damage"]), kills=d["kills"], usage_share=round(d["equipped"] / eq_total, 3),
                          pellets=d["pellets"])
    gathered = {k: st["collected"][k] + st["vacuumed"][k] + st["salvage"][k] + st["foreman_bounty"][k]
                for k in ("al", "cu", "au", "pc")}
    gathered["al"] += st["tutorial"]["al"] + st["early_bird"]["al"]
    runs = []
    for i, r in enumerate(s.runs):
        runs.append(dict(run=i + 1, start_min=round(r["start"] / 60, 2), end_min=round((r["end"] or s.t) / 60, 2),
                         waves_cleared=r["waves_cleared"], reached_wave=r["max_wave"], reason=r["reason"] or "quit",
                         kills=r["kills"], distance_m=round(r["distance"]), parts=r["parts"]))
    return dict(
        name=s.persona.name, minutes=round(s.t / 60, 2), quit_phase=s.end_phase, quit_wave=s.wave,
        melee_acc=s.persona.melee_acc, proj_peak=s.persona.proj_peak,
        deaths=s.deaths, waves_cleared_total=st["waves_cleared"], best_wave_reached=st["max_wave"],
        best_wave_cleared=max((r["waves_cleared"] for r in s.runs), default=0),
        phases_completed=max((r["waves_cleared"] for r in s.runs), default=0) // 5,
        distance_m=round(st["distance"]), avg_dist_from_silo_wall_in_combat=round(st["ring_samples"][0] / max(1, st["ring_samples"][1]), 1),
        share_of_combat_time_over_10m=round(st["time_far_from_silo"] / max(1, st["combat_time"]), 3),
        time_in_phase={k: round(v) for k, v in st["time_in_phase"].items() if v > 0},
        upgrade_time=round(st["upgrade_time"]), robots_spawned=st["robots_spawned"], kills=st["kills"],
        kills_by_weapon=st["kills_by_weapon"], ttk_seconds=ttk, weapons=weapons,
        damage_taken=round(st["damage_taken"]), hits_taken=st["hits_taken"],
        damage_taken_by={k: round(v) for k, v in sorted(st["damage_taken_by"].items(), key=lambda kv: -kv[1])},
        silo_damage=round(st["silo_damage"]), silo_damage_by={k: round(v) for k, v in sorted(st["silo_damage_by"].items(), key=lambda kv: -kv[1])},
        cracks_opened=st["cracks_opened"], cracks_repaired=st["cracks_repaired"], repair_seconds=round(st["repair_seconds"], 1),
        structure_repaired=round(st["structure_repaired"]), grain_leaked=round(st["grain_leaked"]),
        grain_stolen=round(st["grain_stolen"]), grain_recovered=round(st["grain_recovered"]), thefts=st["thefts"],
        thieves_escaped=st["thieves_escaped"], porch_visits=st["porch_visits"], guard_blocks=st["guard_blocks"],
        parts_gathered=gathered, collected_by_hand=st["collected"], scrap_vac=st["vacuumed"],
        left_on_ground=st["lost_on_ground"], salvage=st["salvage"], foreman_bounty=st["foreman_bounty"],
        spent=st["spent"], parts_in_pocket=dict(s.parts),
        upgrades={UPGRADE_NAMES.get(k, k): v for k, v in s.levels.items() if k != "attack.wrench"},
        purchases=[dict(min=round(t / 60, 2), item=UPGRADE_NAMES[u], level=l, cost=c, wave=w, deaths=d)
                   for (t, u, l, c, w, d) in s.purchases],
        waves=s.wave_records, thieves_spawned=st['thieves_spawned'], thieves_killed=st['thieves_killed'],
        activity={k: round(v) for k, v in sorted(st['activity'].items(), key=lambda kv: -kv[1])},
        runs=runs, events=[(round(t / 60, 2), e) for t, e in s.events],
    )


def cohort(n, seed=9):
    rng = random.Random(seed)
    out = []
    for i in range(n):
        roll, acc = rng.random(), 0.0
        for share, lo, hi in BUCKETS:
            acc += share
            if roll <= acc:
                break
        minutes = rng.uniform(lo, hi)
        melee = rng.uniform(0.70, 0.88)
        peak = rng.uniform(0.30, 0.57)
        p = Persona(f"cohort-{i}", minutes, 1000 + i, melee_acc=melee, proj_peak=peak,
                    repair_intermission=rng.uniform(0.2, 0.45), fight_chaser=rng.uniform(0.35, 0.55),
                    shotgun_after_deaths=rng.choice([1, 2, 3, 99]), rifle_after_deaths=rng.choice([2, 3, 4, 99]),
                    priority=BASE_PRIORITY)
        s = Session(p).run()
        out.append(summarize(s))
    return out


def main():
    n = 0
    if "--cohort" in sys.argv:
        n = int(sys.argv[sys.argv.index("--cohort") + 1])
    sims = [summarize(Session(p).run()) for p in PERSONAS]
    result = dict(sims=sims)
    if n:
        result["cohort"] = cohort(n)
    with open(os.path.join(HERE, "results.json"), "w") as f:
        json.dump(result, f, indent=1)
    tw = [0.05, 0.44, 0.32, 0.13, 0.06]
    mix = {}
    for wgt, s in zip(tw, sims):
        for w, d in s["weapons"].items():
            mix[w] = mix.get(w, 0) + wgt * d["usage_share"]
    print("tester-weighted weapon mix:", {k: round(v, 3) for k, v in mix.items()})
    for s in sims:
        print(f"{s['name']}: {s['minutes']} min, deaths {s['deaths']}, best wave cleared {s['best_wave_cleared']}, "
              f"waves cleared total {s['waves_cleared_total']}, kills {sum(s['kills'].values())}, dist {s['distance_m']} m")
        print("   weapons:", {w: (d['usage_share'], d['hit_rate']) for w, d in s['weapons'].items()})
        print("   runs:", [(r['reached_wave'], r['waves_cleared'], r['reason'], r['end_min']) for r in s['runs']])


if __name__ == "__main__":
    main()
