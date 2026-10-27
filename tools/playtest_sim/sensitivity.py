"""What-if cohorts: same testers, one behaviour or rule changed. python3 sensitivity.py N"""
import json, os, random, statistics as st, sys
from collections import defaultdict
sys.path.insert(0, os.path.dirname(__file__))
import game_data, sim
from sim import BASE_PRIORITY, Persona, Session
from run_sims import BUCKETS, summarize

def cohort(n, seed=9, **over):
    rng = random.Random(seed); out = []
    for i in range(n):
        roll, acc = rng.random(), 0.0
        for share, lo, hi in BUCKETS:
            acc += share
            if roll <= acc: break
        kw = dict(melee_acc=rng.uniform(0.70, 0.88), proj_peak=rng.uniform(0.30, 0.57),
                  repair_intermission=rng.uniform(0.2, 0.45), fight_chaser=rng.uniform(0.35, 0.55),
                  shotgun_after_deaths=rng.choice([1, 2, 3, 99]), rifle_after_deaths=rng.choice([2, 3, 4, 99]),
                  priority=BASE_PRIORITY)
        kw.update(over)
        out.append(summarize(Session(Persona(f"c{i}", rng.uniform(lo, hi), 1000 + i, **kw)).run()))
    return out

def report(name, c):
    n = len(c)
    runs = [r for s in c for r in s["runs"] if r["reason"] != "quit"]
    by = defaultdict(int)
    for r in runs:
        by[r["reason"]] += 1
    lost_wave = defaultdict(int)
    for s in c:
        for w in s["waves"]:
            if w.get("outcome", "").startswith("lost"): lost_wave[w["wave"]] += 1
    in_break = sum(1 for s in c for t, e in s["events"] if e.startswith("(lost during the break"))
    return dict(name=name, sessions=n,
                reach_w4=round(sum(s["best_wave_reached"] >= 4 for s in c) / n, 3),
                reach_w5=round(sum(s["best_wave_reached"] >= 5 for s in c) / n, 3),
                clear_w4=round(sum(s["best_wave_cleared"] >= 4 for s in c) / n, 3),
                clear_w5=round(sum(s["best_wave_cleared"] >= 5 for s in c) / n, 3),
                deaths=round(st.mean(s["deaths"] for s in c), 2), waves_cleared=round(st.mean(s["waves_cleared_total"] for s in c), 2),
                game_overs=dict(by), lost_in_break=in_break, lost_on_wave=dict(sorted(lost_wave.items())),
                grain_leaked=round(st.mean(s["grain_leaked"] for s in c)), cracks_repaired=round(st.mean(s["cracks_repaired"] for s in c), 1),
                cracks_opened=round(st.mean(s["cracks_opened"] for s in c), 1))

if __name__ == "__main__":
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 300
    out = [report("Baseline (your testers)", cohort(n))]
    out.append(report("Repairs every ground crack in the break", cohort(n, repair_intermission=1.0)))
    # Also climbs to repair catwalk cracks: model by making band>0 cracks count as ground for the repair roll
    orig = sim.Session.plan_intermission
    def diligent(self):
        orig(self)
        self.tasks = [t for t in self.tasks if t[0] != "repair"]
        self.tasks[1:1] = [("repair", c) for c in list(self.silo.cracks)]
    sim.Session.plan_intermission = diligent
    out.append(report("Repairs every crack, catwalks included", cohort(n)))
    sim.Session.plan_intermission = orig
    json.dump(out, open(os.path.join(os.path.dirname(__file__), "sensitivity.json"), "w"), indent=1)
    for r in out: print(r)
