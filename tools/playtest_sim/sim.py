"""Agent-based play-session model of Robot Attack built from the project's own rules (game_data.py) and a
behavioural model of the human playtesters (Persona). Stepped at DT seconds; no Godot required.

Run: python3 tools/playtest_sim/run_sims.py
"""
import math
import random
from dataclasses import dataclass, field

from game_data import *

DT = 0.1


def dist(a, b):
    return math.hypot(a[0] - b[0], a[1] - b[1])


def dist3(a, az, b, bz):
    return math.sqrt((a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2 + (az - bz) ** 2)


def unit(v):
    l = math.hypot(v[0], v[1])
    return (v[0] / l, v[1] / l) if l > 1e-6 else (1.0, 0.0)


def angle_of(p):
    return math.atan2(p[1], p[0])


def ang_diff(a, b):
    d = (a - b) % (2 * math.pi)
    return min(d, 2 * math.pi - d)


# =================================================================================================
# Persona: how the testers play (from the user's playtest averages)
# =================================================================================================
@dataclass
class Persona:
    name: str
    quit_minutes: float
    seed: int
    melee_acc: float              # 70-88 %
    proj_peak: float              # best-case gun accuracy (close range); falls to 4 % at range
    ring: tuple = (7.0, 14.0)     # 3-10 m from the silo wall (silo radius 4 m)
    # Weapon picks against ordinary ground targets, among owned weapons. Roofs/drones force a gun.
    weights: dict = field(default_factory=lambda: {"wrench": 0.86, "pistol": 0.10, "shotgun": 0.30, "rifle": 0.22})
    rifle_after_deaths: int = 99  # "the long rifle is used after many deaths"
    shotgun_after_deaths: int = 99
    repair_intermission: float = 0.35   # chance per ground crack to fix it during the break
    repair_in_wave: float = 0.06        # chance per safe 4 s window to start a repair mid-wave
    heal_wave_hp: float = 0.30          # run to the porch below this HP share during a wave
    heal_break_hp: float = 0.70         # visit the porch during the break below this share
    fight_chaser: float = 0.45          # turn and fight a chasing robot instead of backing off
    bell: float = 0.0                   # chance to ring the dinner bell after shopping
    sweep_radius: float = 16.0          # picks up loot within this radius of the silo during breaks
    shop_mean: float = 67.0
    priority: list = field(default_factory=list)


# Upgrade priorities that reproduce "the wrench gets strong quickly" + "pistol fires fast and can be strong".
BASE_PRIORITY = [
    ("attack.wrench_damage", 2), ("attack.pistol", 1), ("attack.wrench_damage", 3), ("attack.wrench_speed", 1),
    ("attack.pistol_damage", 1), ("attack.wrench_damage", 4), ("attack.pistol_rate", 1), ("defend.hearty_breakfast", 1),
    ("attack.wrench_speed", 2), ("attack.pistol_damage", 2), ("attack.wrench_damage", 5), ("defend.armor_overalls", 1),
    ("attack.pistol_rate", 2), ("attack.wrench_speed", 3), ("attack.wrench_damage", 6), ("attack.pistol_damage", 3),
    ("defend.hearty_breakfast", 2), ("attack.pistol_handling", 1), ("attack.wrench_damage", 7), ("attack.pistol_rate", 3),
    ("attack.wrench_speed", 4), ("attack.pistol_damage", 4), ("attack.wrench_damage", 8), ("attack.wrench_speed", 5),
    ("attack.pistol_rate", 4), ("attack.pistol_damage", 5), ("attack.wrench_damage", 9), ("attack.wrench_damage", 10),
]
RIFLE_PRIORITY = [("attack.rifle", 1), ("attack.rifle_damage", 1), ("attack.rifle_damage", 2), ("attack.rifle_damage", 3)]
SHOTGUN_PRIORITY = [("attack.shotgun", 1), ("attack.shotgun_damage", 1)]


# =================================================================================================
# Robot targeting (port of scripts/ai/robot_targeting.gd)
# =================================================================================================
class Targeting:
    def __init__(self, a, rng):
        self.a = a
        self.hunter = rng.random() >= a["focus"]
        self.goal = "farmer" if self.hunter else "silo"
        self.engaged = False
        self.since_switch = 1e9
        self.chase = 0.0
        self.unreach = 0.0
        self.clock = 0.0
        self.hurt_left = 0.0
        self.can_distract = True
        self.rng = random.Random(rng.random())
        self.ticked_at = -1.0
        self.senses = None

    def switch_to_farmer(self):
        self.goal = "farmer"; self.engaged = False; self.chase = 0.0; self.unreach = 0.0; self.since_switch = 0.0

    def return_to_silo(self):
        if self.goal == "silo":
            return
        self.goal = "silo"; self.hunter = False; self.since_switch = 0.0; self.clock = 0.0

    def trigger_active(self, s):
        tr = self.a["triggers"]
        if "hurt" in tr and self.hurt_left > 0: return True
        if "near" in tr and s["fd"] <= self.a["drange"]: return True
        if "repairing" in tr and s["repairing"] and s["fd"] <= self.a["drange"]: return True
        if "airborne" in tr and s["airborne"] and s["fd"] <= self.a["drange"]: return True
        return False

    def roll(self, s):
        if not self.can_distract or self.since_switch < self.a["commit"] or not s["reachable"] or not s["alive"]:
            return
        if not self.trigger_active(s):
            return
        if self.rng.random() < self.a["distract"]:
            self.switch_to_farmer()

    def on_hurt(self, d):
        if "hurt" not in self.a["triggers"] or d > self.a["drange"]:
            return
        self.hurt_left = 1.0
        if self.goal == "silo" and self.senses is not None:
            self.clock = 0.0
            self.roll(self.senses)

    def tick(self, now, dt, s):
        if self.ticked_at == now:
            return
        self.ticked_at = now
        self.senses = s
        self.since_switch += dt
        self.hurt_left = max(0.0, self.hurt_left - dt)
        if self.goal == "farmer":
            if not s["alive"]:
                self.return_to_silo(); return
            if not self.engaged and s["fd"] <= self.a["drange"]:
                self.engaged = True
            if self.engaged:
                self.chase += dt
            self.unreach = 0.0 if s["reachable"] else self.unreach + dt
            a = self.a
            if a["giveup"] > 0 and self.unreach >= a["giveup"]:
                self.return_to_silo()
            elif self.engaged and a["chase"] > 0 and self.chase >= a["chase"]:
                self.return_to_silo()
            elif self.engaged and a["leash"] > 0 and s["silo_d"] > a["leash"]:
                self.return_to_silo()
            return
        self.clock += dt
        if self.clock >= 1.0:
            self.clock -= 1.0
            self.roll(s)


class Squad:
    def __init__(self):
        self.members = []
        self.targeting = None
        self.heist_leader = None
        self.heist_escaped = False


# =================================================================================================
# Robots
# =================================================================================================
class Robot:
    _ids = 0

    def __init__(self, sim, name, wave, pos, foreman, traits, squad, rng):
        Robot._ids += 1
        self.id = Robot._ids
        self.sim = sim
        self.name = name
        self.a = ARCH[name]
        self.wave = wave
        self.x, self.y = pos
        self.z = 0.0
        self.foreman = foreman
        self.traits = traits
        hpm = hp_mult(wave) * (FOREMAN_HP_MULT if foreman else 1.0)
        spd = 1.0
        for t in traits:
            hpm *= TRAITS[t]["hp"]; spd *= TRAITS[t]["speed"]
        self.maxhp = self.hp = self.a["hp"] * hpm
        # ASSUMPTION: navmesh detours around corn, fences and the silo cost ~8 % of straight-line speed.
        self.speed = self.a["speed"] * spd * 0.92
        self.dm = dmg_mult(wave)
        self.radius = self.a["radius"] * (TYPE_SCALES[self.a["type"]] if name == "thumper" else 1.0)
        self.alive = True
        self.escaped = False
        self.state = "seek"
        self.timer = 0.0
        self.first_attack = True
        self.spawn_t = sim.t
        self.first_hit_t = None
        self.squad = squad
        self.squad_index = 0
        self.thief = False
        self.escort = False
        self.sack = 0.0
        self.escape_pt = None
        self.facing = unit((-self.x, -self.y))
        self.guard_up = arm_guard_up(wave)
        self.kind = {"roof_lobber": "lobber", "drone": "drone", "spitter": "spitter"}.get(name, "ground")
        self.travel = "approach"
        self.roof = None
        self.orbit = math.atan2(self.y, self.x)
        self.rstate = "idle"
        self.rtimer = 0.0
        self.rtarget = None
        self.escort_threat = False
        self.attack_target = None
        self.blast = 0.0
        if any(TRAITS[t].get("blast_r") for t in traits):
            s = math.sqrt(TYPE_SCALES[self.a["type"]])
            self.blast = 3.5 * s
            self.blast_dmg = 80 * s * hp_mult(wave)
            self.blast_farmer = 12 * s * self.dm
        if squad is not None:
            self.squad_index = len(squad.members)
            squad.members.append(self)
        if squad is not None and self.squad_index > 0 and squad.targeting is not None:
            self.targeting = squad.targeting
            if squad.heist_leader is not None:
                self.escort = True
        else:
            self.targeting = Targeting(self.a, rng)
            if self.a["cls"] == 0 and self.a["type"] == 0:  # Nibbler: thief share (GDD 11.7)
                thieving = any(TRAITS[t].get("thieving") for t in traits)
                chance = thief_share(wave, thieving) / max(0.01, self.a["focus"])
                if not self.targeting.hunter and not foreman and rng.random() < chance:
                    self.thief = True
                    self.targeting.can_distract = False
            if squad is not None:
                squad.targeting = self.targeting
                if self.thief:
                    squad.heist_leader = self
        if self.kind == "lobber":
            self._choose_roof()

    # ---------------------------------------------------------------------------------------------
    def pos(self):
        return (self.x, self.y)

    def silo_d(self):
        return math.hypot(self.x, self.y)

    def _choose_roof(self):
        best, best_i = 1e9, 0
        for i, r in enumerate(ROOFS):
            score = dist(self.pos(), r["entry"])
            for o in self.sim.robots:
                if o is not self and o.alive and o.kind == "lobber" and o.roof is r:
                    score += 100
            if score < best:
                best, best_i = score, i
        self.roof = ROOFS[best_i]
        self.climb_left = (0.65 + self.roof["edge"] + max(0.0, self.roof["h"] - self.roof["edge"])
                           + dist(self.roof["entry"], self.roof["top"])) / CLIMB_SPEED

    def move_to(self, pt, dt, stop=0.0):
        d = dist(self.pos(), pt)
        if d <= stop + 1e-3:
            return True
        step = min(self.speed * dt, d - stop)
        u = unit((pt[0] - self.x, pt[1] - self.y))
        self.x += u[0] * step; self.y += u[1] * step
        self.facing = u
        return d - step <= stop + 1e-3

    def senses(self):
        p = self.sim.player
        fd = dist3(self.pos(), self.z, p.pos(), p.z)
        return dict(fd=fd, silo_d=self.silo_d(), reachable=self.can_reach(), alive=p.alive,
                    repairing=p.repairing, airborne=p.z > 2.5)

    def can_reach(self):
        if self.kind in ("lobber", "drone"):
            return True
        return self.sim.player.z <= 2.5

    def stand_point(self):
        u = unit(self.pos())
        r = SILO_R + self.radius + (self.a.get("range", 1.5) * 0.8)
        return (u[0] * r, u[1] * r)

    # ---------------------------------------------------------------------------------------------
    def step(self, dt):
        sim = self.sim
        p = sim.player
        self.targeting.tick(sim.t, dt, self.senses())
        if self.kind == "lobber":
            return self._step_lobber(dt)
        if self.kind == "drone":
            return self._step_drone(dt)
        if self.escort:
            self._update_escort()
        if self.state == "flee":
            if self.move_to(self.escape_pt, dt) or self.silo_d() >= ESCAPE_RADIUS:
                sim.escape(self)
            return
        on_farmer = self.targeting.goal == "farmer" and p.alive and not self.thief and not self.escort
        if self.escort and self.state != "flee":
            th = self.squad.heist_leader
            if self.escort_threat:
                on_farmer = True
            elif th is not None and th.alive:
                self.move_to((th.x, th.y), dt, stop=1.6)
                return
        if self.kind == "spitter":
            return self._step_spitter(dt, on_farmer)
        a = self.a
        if self.state == "seek":
            if self.thief:
                spot = (CHUTE[0], CHUTE[1] + 1.0)
                if self.move_to(spot, dt, stop=0.4):
                    self.state = "steal"; self.timer = 0.6
                return
            if on_farmer:
                reach = a["range"] + self.radius + 0.4
                d = dist3(self.pos(), 0.0, p.pos(), p.z)
                if self.can_reach() and d <= reach:
                    self._start_windup("farmer")
                else:
                    self.move_to(p.pos(), dt, stop=reach * 0.85)
            else:
                if self.move_to(self.stand_point(), dt, stop=0.25):
                    self.facing = unit((-self.x, -self.y))
                    self._start_windup("silo")
        elif self.state == "windup":
            self.timer -= dt
            if self.timer <= 0:
                self._deal_hit()
                self.state = "recover"; self.timer = max(0.0, a["interval"] - a["windup"])
        elif self.state == "recover":
            self.timer -= dt
            if self.timer <= 0:
                self.state = "seek"
        elif self.state == "steal":
            self.timer -= dt
            if self.timer <= 0:
                self.sack = sim.silo.steal(SACK)
                sim.stats["grain_stolen"] += self.sack
                sim.stats["thefts"] += 1
                lane = min(LANES.values(), key=lambda l: dist(l, self.pos()))
                u = unit(lane)
                self.escape_pt = (u[0] * (ESCAPE_RADIUS + 4), u[1] * (ESCAPE_RADIUS + 4))
                self.state = "flee"

    def _start_windup(self, target):
        self.state = "windup"; self.attack_target = target
        self.timer = self.a["windup"]
        if self.first_attack and self.squad is not None:
            self.timer += self.squad_index * self.a["interval"] / 3.0
        self.first_attack = False

    def _deal_hit(self):
        sim, p, a = self.sim, self.sim.player, self.a
        if self.attack_target == "farmer":
            d = dist3(self.pos(), 0.0, p.pos(), p.z)
            if p.alive and d <= a["range"] + self.radius + 0.9:
                self.facing = unit((p.x - self.x, p.y - self.y))
                if sim.rng.random() < sim.land_chance("melee", self):
                    p.take_damage(a["dmg_f"] * self.dm, self.name)
        else:
            sim.silo.hit(a["dmg_s"] * self.dm, angle_of(self.pos()), 0, self)
        if a.get("shock_dmg"):
            d = dist(self.pos(), p.pos())
            if p.alive and d <= a["shock_r"] and sim.rng.random() < sim.land_chance("shock", self):
                p.take_damage(a["shock_dmg"] * self.dm, "shockwave")

    def _update_escort(self):
        sq = self.squad
        th = sq.heist_leader
        self.escort_threat = False
        if th is None or not th.alive:
            self.escort = False
            if sq.heist_escaped:
                u = unit(self.pos())
                self.escape_pt = (u[0] * (ESCAPE_RADIUS + 4), u[1] * (ESCAPE_RADIUS + 4))
                self.state = "flee"
            else:
                self.targeting.can_distract = True
            return
        p = self.sim.player
        r = self.a["drange"]
        if p.alive and self.can_reach() and (dist(p.pos(), self.pos()) <= r or dist(p.pos(), th.pos()) <= r):
            self.escort_threat = True

    def _step_spitter(self, dt, on_farmer):
        p = self.sim.player
        prof = ATTACKS["spitter_pea"]
        if on_farmer and dist(self.pos(), p.pos()) > prof["range"] * 0.75:
            self.move_to(p.pos(), dt, stop=prof["range"] * 0.7); self.sim.ranged_cancel(self); return
        if not on_farmer and self.silo_d() - SILO_R > prof["range"] * 0.75:
            u = unit(self.pos()); r = SILO_R + prof["range"] * 0.7
            self.move_to((u[0] * r, u[1] * r), dt); self.sim.ranged_cancel(self); return
        self.sim.ranged_step(self, prof, dt)

    def _step_lobber(self, dt):
        if self.travel == "approach":
            if self.move_to(self.roof["entry"], dt, stop=2.0):
                self.travel = "climb"
            return
        if self.travel == "climb":
            self.climb_left -= dt
            if self.climb_left <= 0:
                self.travel = "perched"
                self.x, self.y = self.roof["top"]; self.z = self.roof["h"]
            return
        self.sim.ranged_step(self, ATTACKS["lobber_lob"], dt)

    def _step_drone(self, dt):
        spd = self.speed / 0.92  # flight ignores the navmesh detour
        if self.z < 13.5:
            self.z = min(DRONE_H, self.z + spd * dt)
        else:
            self.orbit += dt * 0.22
            tgt = (math.cos(self.orbit) * DRONE_ORBIT_R, math.sin(self.orbit) * DRONE_ORBIT_R)
            d = dist(self.pos(), tgt)
            if d > 1e-3:
                step = min(spd * dt, d)
                u = unit((tgt[0] - self.x, tgt[1] - self.y))
                self.x += u[0] * step; self.y += u[1] * step
        if self.z >= 13.5:
            self.sim.ranged_step(self, ATTACKS["drone_shot"], dt)

    # ---------------------------------------------------------------------------------------------
    def take_damage(self, amount, weapon, src):
        if not self.alive:
            return 0.0
        sim = self.sim
        if self.first_hit_t is None:
            self.first_hit_t = sim.t
        if self.guard_up and self.a["guard"] > 0:
            to = unit((src[0] - self.x, src[1] - self.y))
            if to[0] * self.facing[0] + to[1] * self.facing[1] >= 0.5:
                amount *= 1.0 - self.a["guard"]
                sim.stats["guard_blocks"] += 1
        if not self.thief and not self.escort:
            self.targeting.on_hurt(dist3(self.pos(), self.z, src, sim.player.z))
        dealt = min(self.hp, amount)
        self.hp -= amount
        if self.hp <= 0:
            sim.kill(self, weapon)
        return dealt


# =================================================================================================
# Silo (port of scripts/systems/silo.gd + silo_crack.gd)
# =================================================================================================
class Crack:
    def __init__(self, socket, pool):
        self.socket = socket
        self.band, self.angle = SOCKETS[socket]
        self.size = 0
        self.pool = pool
        self.hits = 0
        self.progress = 0.0

    def seconds_left(self):
        return sum(STAGE_SECONDS[: self.size + 1]) - self.progress

    def repair(self, seconds):
        before = self.pool
        remaining = self.seconds_left()
        left = seconds
        while left > 0 and self.pool > 0:
            step = min(left, STAGE_SECONDS[self.size] - self.progress)
            self.progress += step; left -= step
            if self.progress >= STAGE_SECONDS[self.size] - 1e-4:
                self.progress = 0.0
                if self.size == 0:
                    self.pool = 0.0
                    break
                self.size -= 1; self.hits = 0
        if self.pool > 0 and remaining > 0:
            self.pool = before * (self.seconds_left() / remaining)
        return before - self.pool


class Silo:
    def __init__(self, sim):
        self.sim = sim
        self.structure = MAX_STRUCTURE
        self.grain = MAX_GRAIN
        self.cracks = []
        self.counter = 0.0

    def leak_rate(self):
        return sum(LEAK[c.size] for c in self.cracks)

    def tick(self, dt):
        leak = self.leak_rate() * dt
        if leak > 0:
            lost = min(self.grain, leak)
            self.grain -= lost
            self.sim.stats["grain_leaked"] += lost
            if self.grain <= 0:
                self.sim.game_over("grain")

    def steal(self, amount):
        taken = min(amount, self.grain)
        self.grain -= taken
        if self.grain <= 0:
            self.sim.game_over("grain")
        return taken

    def hit(self, amount, angle, band, robot):
        sim = self.sim
        if sim.over or self.structure <= 0:
            return
        amount = min(amount, self.structure)
        self.structure -= amount
        sim.stats["silo_damage"] += amount
        key = "foreman" if robot.foreman else robot.name
        sim.stats["silo_damage_by"][key] = sim.stats["silo_damage_by"].get(key, 0.0) + amount
        near = None
        for c in self.cracks:
            if c.band == band and ang_diff(c.angle, angle) * SILO_R <= 2.5:
                near = c; break
        if near is not None and near.size < 2:
            near.hits += 1
            if near.hits >= HITS_TO_GROW[near.size]:
                near.hits = 0; near.progress = 0.0; near.size += 1
        th = MAX_STRUCTURE * CRACK_EVERY
        self.counter += amount
        while self.counter >= th:
            sock = self._pick_socket(angle, band) if len(self.cracks) < MAX_CRACKS else -1
            if sock >= 0:
                self.cracks.append(Crack(sock, th)); self.counter -= th
                sim.stats["cracks_opened"] += 1
            else:
                tgt = near or (min(self.cracks, key=lambda c: ang_diff(c.angle, angle)) if self.cracks else None)
                if tgt is not None:
                    tgt.pool += self.counter
                self.counter = 0.0
        if self.structure <= 0:
            sim.game_over("silo")

    def _pick_socket(self, angle, hit_band):
        used = {c.socket for c in self.cracks}
        free = {0: [], 1: [], 2: []}
        for i, (b, _) in enumerate(SOCKETS):
            if i not in used:
                free[b].append(i)
        bands = [0] if self.sim.wave <= GROUND_ONLY_UNTIL else [0, 1, 2]
        bw = [0.5, 0.3, 0.2]
        others = sum(bw[b] for b in bands if b != hit_band and free[b])
        weights = {}
        for b in bands:
            if not free[b]: continue
            weights[b] = 0.7 if b == hit_band else ((0.3 * bw[b] / others) if others > 0 else 0.0)
        if sum(weights.values()) <= 0:
            weights = {b: 1.0 for b in bands if free[b]}
            if not weights:
                return -1
        roll = self.sim.rng.random() * sum(weights.values())
        chosen = None
        for b in bands:
            if weights.get(b, 0) <= 0: continue
            chosen = b; roll -= weights[b]
            if roll <= 0: break
        return min(free[chosen], key=lambda i: ang_diff(SOCKETS[i][1], angle))


# =================================================================================================
# The farmer (human model)
# =================================================================================================
class Player:
    def __init__(self, sim):
        self.sim = sim
        self.x, self.y, self.z = -9.0, 4.0, 0.0
        self.alive = True
        self.repairing = False
        self.hp = self.maxhp()
        self.armor = self.max_armor()
        self.since_damage = 99.0
        self.weapon = "wrench"
        self.switch_left = 0.0
        self.cd = 0.0
        self.combo = 0
        self.since_swing = 99.0
        self.ammo = {}
        self.reload_left = 0.0
        self.target = None
        self.task = None
        self.decide_t = 0.0
        self.pick_t = -99.0
        self.ring_r = sum(sim.persona.ring) / 2
        self.ring_t = 0.0
        self.chase_choice = {}
        self.kite_shoot = False
        self.repair_check = 0.0

    def pos(self):
        return (self.x, self.y)

    def lvl(self, uid):
        return self.sim.levels.get(uid, 0)

    def maxhp(self):
        return MAX_HP + 10 * self.lvl("defend.hearty_breakfast")

    def max_armor(self):
        return 50.0 if self.lvl("defend.armor_vest") else (25.0 if self.lvl("defend.armor_overalls") else 0.0)

    def run_speed(self):
        return RUN_SPEED * (1 + 0.03 * self.lvl("travel.comfy_boots"))

    def magnet(self):
        return MAGNET + 1.5 * self.lvl("farmhand.scrap_magnet")

    def owned(self):
        out = ["wrench"]
        for w in ("pistol", "shotgun", "rifle"):
            if self.lvl("attack." + w):
                out.append(w)
        return out

    def wstat(self, w):
        L = self.lvl
        if w == "wrench":
            return dict(dmg=25 * (1 + 0.12 * L("attack.wrench_damage")), rate=1.6 * (1 + 0.08 * L("attack.wrench_speed")))
        if w == "pistol":
            h = L("attack.pistol_handling")
            return dict(dmg=12 * (1 + 0.12 * L("attack.pistol_damage")), rate=4 * (1 + 0.08 * L("attack.pistol_rate")),
                        mag=10 + 2 * h, reload=1.1 * (1 - 0.08 * h), range=40)
        if w == "shotgun":
            return dict(dmg=10 * (1 + 0.12 * L("attack.shotgun_damage")), rate=1.0, mag=5, reload=1.8, range=16)
        return dict(dmg=55 * (1 + 0.12 * L("attack.rifle_damage")), rate=0.8, mag=4, reload=1.9, range=100)

    def take_damage(self, amount, source):
        sim = self.sim
        if not self.alive:
            return
        self.since_damage = 0.0
        absorbed = min(self.armor, amount)
        self.armor -= absorbed
        amount -= absorbed
        self.hp -= amount
        sim.stats["damage_taken"] += amount + absorbed
        sim.stats["damage_taken_by"][source] = sim.stats["damage_taken_by"].get(source, 0.0) + amount + absorbed
        sim.stats["hits_taken"] += 1
        if self.hp <= 0:
            self.hp = 0
            self.alive = False
            sim.game_over("farmer")

    def move_to(self, pt, speed, dt, stop=0.0):
        d = dist(self.pos(), pt)
        if d <= stop + 1e-3:
            return True
        step = min(speed * dt, d - stop)
        u = unit((pt[0] - self.x, pt[1] - self.y))
        self.x += u[0] * step; self.y += u[1] * step
        self.sim.stats["distance"] += step
        self.sim.run_stats["distance"] += step
        return d - step <= stop + 1e-3

    def move_dir(self, u, speed, dt):
        self.x += u[0] * speed * dt; self.y += u[1] * speed * dt
        self.sim.stats["distance"] += speed * dt
        self.sim.run_stats["distance"] += speed * dt

    def tick_common(self, dt):
        self.since_damage += dt
        self.since_swing += dt
        self.cd = max(0.0, self.cd - dt)
        self.switch_left = max(0.0, self.switch_left - dt)
        if self.reload_left > 0:
            self.reload_left -= dt
            if self.reload_left <= 0:
                self.ammo[self.weapon] = self.wstat(self.weapon)["mag"]
        if self.armor < self.max_armor() and self.since_damage >= ARMOR_DELAY:
            self.armor = min(self.max_armor(), self.armor + ARMOR_REGEN * dt)
        if dist(self.pos(), PORCH) <= 3.0:
            self.hp = min(self.maxhp(), self.hp + PORCH_HEAL * (1 + 0.2 * self.lvl("defend.porch_swing")) * dt)

    def equip(self, w):
        if w != self.weapon:
            self.weapon = w
            self.switch_left = 0.45  # ASSUMPTION: weapon wheel open + pick
            self.reload_left = 0.0
            self.sim.stats["weapon_switches"] += 1
            if w != "wrench" and w not in self.ammo:
                self.ammo[w] = self.wstat(w)["mag"]

    # --- attacking -------------------------------------------------------------------------------
    def try_attack(self, r):
        """Attack robot r with the equipped weapon if in reach. Returns True if in range (stand still)."""
        sim, per = self.sim, self.sim.persona
        if self.switch_left > 0:
            return True
        w = self.weapon
        d = dist3(self.pos(), self.z, r.pos(), r.z)
        if w == "wrench":
            reach = WEAPONS["wrench"]["reach"] + r.radius + 0.3
            if d > reach:
                return False
            if self.cd <= 0:
                st = self.wstat("wrench")
                self.cd = 1.0 / st["rate"]
                if self.since_swing > 1.2:
                    self.combo = 0
                self.since_swing = 0.0
                self.combo += 1
                fin = self.combo >= 3
                if fin:
                    self.combo = 0
                sim.wstats["wrench"]["fired"] += 1
                if sim.rng.random() < per.melee_acc:
                    sim.wstats["wrench"]["hits"] += 1
                    dmg = st["dmg"] * (1.5 if fin else 1.0)
                    sim.wstats["wrench"]["damage"] += r.take_damage(dmg, "wrench", self.pos())
                    for o in sim.robots:  # a trio-mate inside the 0.9 m swing sphere
                        if o is not r and o.alive and o.z < 1 and dist(o.pos(), r.pos()) < 1.6 and sim.rng.random() < 0.25:
                            sim.wstats["wrench"]["damage"] += o.take_damage(dmg, "wrench", self.pos())
            return True
        st = self.wstat(w)
        hunting = sim.phase == PH_MOP and sim.mop_time > STRAGGLER_TIME
        if hunting:  # stragglers are marked: walk in for a better shot
            engage = {"pistol": 14.0, "shotgun": 7.0, "rifle": 40.0}[w]
        else:
            engage = {"pistol": 25.0, "shotgun": 10.0, "rifle": 60.0}[w]
        if d > engage:
            return False
        if self.reload_left > 0 or self.cd > 0:
            return True
        if self.ammo.get(w, 0) <= 0:
            self.reload_left = st["reload"]
            return True
        # ASSUMPTION: humans tap a semi-auto at most ~3.3 times a second.
        self.cd = max(1.0 / st["rate"], 0.3)
        self.ammo[w] -= 1
        sim.wstats[w]["fired"] += 1
        acc = sim.gun_accuracy(w, d, r)
        if w == "shotgun":
            tr = {"nibbler": 0.45, "spitter": 0.45, "roof_lobber": 0.45, "drone": 0.7, "clanker": 0.75}.get(r.name, 1.3)
            ri = 0.45 * math.tan(math.radians(11)) * d
            ro = math.tan(math.radians(11)) * d
            g = lambda ring: max(0.0, min(1.0, (1.4 * tr - ring) / (0.8 * tr)))
            pellets = (1 if sim.rng.random() < acc else 0)
            for _ in range(3):
                if sim.rng.random() < acc * g(ri): pellets += 1
                if sim.rng.random() < acc * g(ro): pellets += 1
            sim.wstats[w]["pellets"] += pellets
            if pellets:
                sim.wstats[w]["hits"] += 1
                sim.wstats[w]["damage"] += r.take_damage(st["dmg"] * pellets, w, self.pos())
            for o in sim.robots:  # outer-ring pellets can catch a neighbour in a trio
                if o is not r and o.alive and dist(o.pos(), r.pos()) < 1.8 and sim.rng.random() < 0.15:
                    sim.wstats[w]["damage"] += o.take_damage(st["dmg"], w, self.pos())
        elif sim.rng.random() < acc:
            sim.wstats[w]["hits"] += 1
            weak = sim.rng.random() < 0.12  # ASSUMPTION: 12 % of landed gun hits are eye / vent hits (x2)
            sim.wstats[w]["damage"] += r.take_damage(st["dmg"] * (WEAK_POINT_MULT if weak else 1.0), w, self.pos())
            if w == "rifle":
                for o in sim.robots:
                    if o is not r and o.alive and dist(o.pos(), r.pos()) < 3.0 and sim.rng.random() < 0.15:
                        sim.wstats[w]["damage"] += o.take_damage(st["dmg"], w, self.pos())
                        break
        if self.ammo[w] <= 0:
            self.reload_left = st["reload"]
        return True

    def pick_weapon(self, r):
        sim, per = self.sim, self.sim.persona
        owned = self.owned()
        guns = [w for w in owned if w != "wrench"]
        if r.kind in ("lobber", "drone") and r.z > 2.5 and self.z < 1:
            if not guns:
                return "wrench"
            d = dist3(self.pos(), self.z, r.pos(), r.z)
            if "rifle" in guns and (d > 22 or sim.rng.random() < 0.5):
                return "rifle"
            return "pistol" if "pistol" in guns else guns[0]
        w = {k: v for k, v in per.weights.items() if k in owned}
        if r.silo_d() > per.ring[1] + 8 and guns:
            w["wrench"] = w.get("wrench", 0) * 0.3  # far targets: reach for a gun
        tot = sum(w.values())
        roll = sim.rng.random() * tot
        for k, v in w.items():
            roll -= v
            if roll <= 0:
                return k
        return "wrench"


# =================================================================================================
# The session
# =================================================================================================
PH_TUTORIAL, PH_INTER, PH_SIREN, PH_SPAWN, PH_MOP, PH_CLEARED, PH_OVER = range(7)
PHASE_NAMES = ["Morning chores", "Intermission", "Siren", "Attack", "Mop-up", "Cleared", "Game over"]


class Session:
    def __init__(self, persona):
        self.persona = persona
        self.rng = random.Random(persona.seed)
        self.t = 0.0
        self.quit_t = persona.quit_minutes * 60.0
        self.parts = {"al": 0, "cu": 0, "au": 0, "pc": 0}
        self.levels = {}
        self.deaths = 0
        self.runs = []
        self.events = []
        self.purchases = []
        self.stats = dict(distance=0.0, damage_taken=0.0, hits_taken=0, damage_taken_by={}, silo_damage=0.0,
                          silo_damage_by={}, grain_leaked=0.0, grain_stolen=0.0, grain_recovered=0.0, thefts=0,
                          thieves_escaped=0, cracks_opened=0, cracks_repaired=0, repair_seconds=0.0,
                          structure_repaired=0.0, guard_blocks=0, weapon_switches=0, porch_visits=0,
                          collected={"al": 0, "cu": 0, "au": 0, "pc": 0}, vacuumed={"al": 0, "cu": 0, "au": 0, "pc": 0},
                          lost_on_ground={"al": 0, "cu": 0, "au": 0, "pc": 0}, salvage={"al": 0, "cu": 0, "au": 0, "pc": 0},
                          foreman_bounty={"al": 0, "cu": 0, "au": 0, "pc": 0}, tutorial={"al": 0},
                          early_bird={"al": 0}, spent={"al": 0, "cu": 0, "au": 0, "pc": 0},
                          kills={}, ttk={}, kills_by_weapon={}, upgrade_time=0.0, ring_samples=[0.0, 0.0],
                          time_in_phase={n: 0.0 for n in PHASE_NAMES}, robots_spawned=0, max_wave=0,
                          waves_cleared=0, time_far_from_silo=0.0, combat_time=0.0, activity={}, thieves_spawned=0, thieves_killed=0)
        self.wstats = {w: dict(fired=0, hits=0, damage=0.0, pellets=0, kills=0, equipped=0.0)
                       for w in ("wrench", "pistol", "shotgun", "rifle")}
        self.robots = []
        self.pickups = []
        self.sacks = []
        self.shots = []
        self.over = False
        self.wave = 1
        self.phase = PH_INTER
        self.player = None
        self.silo = None
        self.run_stats = None
        self.tasks = []
        self.wave_records = []
        self.wave_rec = None
        self.lanes = [1]
        self.bell_rung_wave = 0
        self.wave_kills = 0
        self.family = []

    # ---------------------------------------------------------------------------------------------
    def log(self, text):
        self.events.append((self.t, text))

    def land_chance(self, kind, robot):
        # ASSUMPTION (from "prioritises not getting hit"): the tester dodges most telegraphed attacks.
        if kind == "melee":
            return {"nibbler": 0.45, "clanker": 0.40, "thumper": 0.30}.get(robot.name, 0.4)
        if kind == "shock":
            return 0.30
        if kind == "lob":
            return 0.30
        return 0.35 + (0.10 if aim_lead(robot.wave) > 0 else 0.0)

    def gun_accuracy(self, w, d, r):
        """4-57 % band from the playtests: best up close, falling to 4 % near the pistol's 40 m reach."""
        peak = self.persona.proj_peak
        dd = max(d, 3.0) - 3.0
        if w == "rifle":
            acc = 0.04 + (peak - 0.04) * max(0.0, 1.0 - dd / 90.0)
        else:
            acc = 0.04 + (peak - 0.04) * max(0.0, 1.0 - dd / 35.0) ** 1.3
        acc *= {"clanker": 1.1, "thumper": 1.25, "drone": 0.8}.get(r.name, 1.0)
        if r.kind == "ground" and r.state == "seek" and r.z < 1:
            acc *= 0.85  # moving target
        return max(0.04, min(0.57, acc))

    # ---------------------------------------------------------------------------------------------
    def new_run(self, first):
        self.silo = Silo(self)
        self.player = Player(self)
        self.robots, self.pickups, self.sacks, self.shots = [], [], [], []
        self.over = False
        self.wave = 1
        self.genomes = {}
        self.tasks = []
        self.run_stats = dict(start=self.t, distance=0.0, waves_cleared=0, max_wave=1, reason=None, end=None,
                              kills=0, parts={"al": 0, "cu": 0, "au": 0, "pc": 0})
        self.runs.append(self.run_stats)
        if first:
            # Level 0 "Morning Chores": tractor parts -> buy wrench -> dummy -> porch -> practice Nibbler -> catwalk vista
            # -> bell. ASSUMPTION: ~3 min for a first-time player reading prompts, ~260 m of walking.
            tut = self.rng.uniform(160, 210)
            self.advance_block(tut, PH_TUTORIAL)
            self.stats["distance"] += 260; self.run_stats["distance"] += 260
            self.levels["attack.wrench"] = 1
            self.parts["al"] += TUTORIAL_AL_AFTER
            self.stats["tutorial"]["al"] += 16
            self.stats["spent"]["al"] += 6
            self.log("Morning Chores done: wrench bought (6 Al), dummy +5 Al, bell +5 Al -> 10 Al in pocket")
            self.player.x, self.player.y = BELL
            self.enter_siren()
        else:
            self.enter_intermission()

    def advance_block(self, seconds, phase):
        self.t += seconds
        self.stats["time_in_phase"][PHASE_NAMES[phase]] += seconds

    def game_over(self, reason):
        if self.over:
            return
        self.over = True
        self.deaths += 1
        self.run_stats["reason"] = reason
        self.run_stats["end"] = self.t
        label = {"farmer": "the farmer was knocked out", "silo": "the silo's Structure hit 0",
                 "grain": "the grain ran out"}[reason]
        self.log(f"GAME OVER on wave {self.wave} ({PHASE_NAMES[self.phase]}): {label}")
        if self.phase in (PH_SPAWN, PH_MOP):
            self.close_wave("lost: " + reason)
        elif self.wave_rec is not None and self.phase in (PH_INTER, PH_SIREN):
            self.log(f"(lost during the break before wave {self.wave})")

    # --- wave director --------------------------------------------------------------------------
    def roll_family(self, w):
        if w in self.genomes:
            return self.genomes[w]
        traits = self.rng.sample(list(TRAITS.keys()), trait_count(w))
        self.genomes[w] = traits
        return traits

    def build_events(self, w):
        rng = self.rng
        avail, climber = [], None
        for n in DIRECTOR_ARCHETYPES:
            if ARCH[n]["unlock"] <= w:
                if n == "roof_lobber" and w >= 3:
                    climber = n
                else:
                    avail.append(n)
        events = []
        bud = budget(w)
        heavies, drones = 0, 0
        others = 1 if is_big_haul(w) else 0
        reserve = lambda o: 0.0 if climber is None else max(1, climber_count(w, o)) * threat_cost(climber)
        if "drone" in avail and w == ARCH["drone"]["unlock"]:
            if threat_cost("drone") + reserve(others + 1) <= bud:
                events.append(["drone", 1, False]); bud -= threat_cost("drone"); others += 1; drones += 1
        while True:
            single = bud - reserve(others + 1)
            opts = [n for n in avail if threat_cost(n) <= single + 0.001
                    and not (ARCH[n]["type"] == 2 and heavies >= heavy_cap(w))
                    and not (n == "drone" and drones >= drone_cap(w))]
            if not opts:
                break
            weights = [TYPE_WEIGHTS[ARCH[n]["type"]] * ARCH[n]["weight"] for n in opts]
            cw = column_weights(w)
            if cw:
                col_tot = [0.0, 0.0, 0.0]
                for n, wt in zip(opts, weights):
                    col_tot[ARCH[n]["cls"]] += wt
                present = sum(cw[c] for c in range(3) if col_tot[c] > 0)
                weights = [wt / col_tot[ARCH[n]["cls"]] * cw[ARCH[n]["cls"]] / present for n, wt in zip(opts, weights)]
            roll = rng.random() * sum(weights)
            pick = opts[-1]
            for n, wt in zip(opts, weights):
                roll -= wt
                if roll <= 0:
                    pick = n; break
            if ARCH[pick]["type"] == 0 and ARCH[pick]["cls"] == 0:
                share = spitter_share(w)
                if share > 0 and rng.random() < share and threat_cost("spitter") <= single + 0.001:
                    pick = "spitter"
            trio_budget = bud - reserve(others + 3)
            size = 1
            ch = trio_chance(w, ARCH[pick])
            if ch > 0 and rng.random() < ch and threat_cost(pick) * 3 <= trio_budget + 0.001:
                size = 3
            events.append([pick, size, False])
            bud -= threat_cost(pick) * size
            others += size
            if ARCH[pick]["type"] == 2: heavies += 1
            if pick == "drone": drones += size
        if climber:
            count = min(max(1, climber_count(w, others)), int(bud // threat_cost(climber)))
            mixed, ins = [], 0
            for i in range(len(events) + 1):
                while ins < count and i >= (ins + 0.5) * len(events) / max(1, count):
                    mixed.append([climber, 1, False]); ins += 1
                if i < len(events):
                    mixed.append(events[i])
            events = mixed
        return events

    def enter_intermission(self):
        self.phase = PH_INTER
        self.phase_left = INTERMISSION
        self.bell_rung = False
        self.plan_intermission()

    def enter_siren(self):
        self.phase = PH_SIREN
        self.phase_left = SIREN_LEAD
        self.lanes = sorted(self.rng.sample(list(LANES.keys()), lane_count(self.wave)))
        self.family = self.roll_family(self.wave)

    def enter_spawning(self):
        # Scrap Vac: leftover parts from the last battle, 50 % banked, rest cleared.
        frac = 0.5
        for pk in self.pickups:
            got = int(pk[3] * frac) + (1 if self.rng.random() < (pk[3] * frac) % 1 else 0)
            self.parts[pk[2]] += got
            self.stats["vacuumed"][pk[2]] += got
            self.stats["lost_on_ground"][pk[2]] += pk[3] - got
            self.run_stats["parts"][pk[2]] += got
        self.pickups = []
        self.phase = PH_SPAWN
        w = self.wave
        self.window = spawn_window(w)
        self.ev = self.build_events(w)
        self.sched = spawn_schedule(len(self.ev), self.window * 0.8)
        if is_big_haul(w):
            at = self.window * FOREMAN_AT
            idx = next((i for i, s in enumerate(self.sched) if s >= at), len(self.sched))
            self.sched.insert(idx, at); self.ev.insert(idx, ["thumper", 1, True])
        self.spawn_clock = 0.0
        self.mop_time = 0.0
        self.spawned = 0
        self.wave_start_t = self.t
        self.wave_kills = 0
        self.wave_spawn_count = sum(1 if e[2] else e[1] for e in self.ev)
        self.run_stats["max_wave"] = max(self.run_stats["max_wave"], w)
        self.stats["max_wave"] = max(self.stats["max_wave"], w)
        comp = {}
        for n, s, f in self.ev:
            key = "FOREMAN" if f else n
            comp[key] = comp.get(key, 0) + (1 if f else s)
        self.wave_comp = comp
        self.wave_rec = dict(run=len(self.runs), wave=w, start_min=round(self.t / 60, 2), robots=self.wave_spawn_count,
                             comp=comp, structure_start=round(self.silo.structure), grain_start=round(self.silo.grain),
                             hp_start=round(self.player.hp), dmg_taken_start=self.stats["damage_taken"],
                             parts_start=dict(self.run_stats["parts"]), dist_start=self.stats["distance"],
                             shots_start={k: (v["fired"], v["hits"]) for k, v in self.wstats.items()},
                             silo_by_start=dict(self.stats["silo_damage_by"]))
        self.wave_records.append(self.wave_rec)
        fam = (" family traits: " + ", ".join(self.family)) if self.family else ""
        self.log(f"Wave {w} attack: {self.wave_spawn_count} robots from lanes {self.lanes} "
                 f"({', '.join(f'{v} {k}' for k, v in sorted(comp.items()))}){fam}")

    def spawn_due(self):
        while self.spawned < len(self.ev) and self.sched[self.spawned] <= self.spawn_clock:
            live = [r for r in self.robots if r.alive]
            if len(live) >= LIVE_CAP:
                return
            idx = -1
            roof_live = sum(1 for r in live if r.name == "roof_lobber")
            for i in range(self.spawned, len(self.ev)):
                if self.sched[i] > self.spawn_clock:
                    break
                if self.ev[i][0] != "roof_lobber" or roof_live < rooftop_cap(self.wave):
                    idx = i; break
            if idx < 0:
                return
            if idx != self.spawned:
                self.ev[self.spawned], self.ev[idx] = self.ev[idx], self.ev[self.spawned]
            name, size, foreman = self.ev[self.spawned]
            self.spawn_event(name, size, foreman)
            self.spawned += 1

    def spawn_event(self, name, size, foreman):
        lane = LANES[self.rng.choice(self.lanes)]
        u = unit(lane)
        lat = (-u[1], u[0])
        off = self.rng.uniform(-1, 1) * 4.0
        center = (lane[0] + lat[0] * off, lane[1] + lat[1] * off)
        squad = Squad() if size > 1 else None
        traits = list(self.family)
        if foreman:
            pool = [t for t in TRAITS if t not in traits]
            traits = traits + [self.rng.choice(pool)]
        scale = TYPE_SCALES[ARCH[name]["type"]]
        for i in range(size):
            o = [(0, 0), (-1.4, 1.4), (1.4, 1.4)][i]
            pos = (center[0] + (lat[0] * o[0] - u[0] * o[1]) * scale, center[1] + (lat[1] * o[0] - u[1] * o[1]) * scale)
            r = Robot(self, name, self.wave, pos, foreman, traits, squad, self.rng)
            self.robots.append(r)
            if r.thief:
                self.stats["thieves_spawned"] += 1
            self.stats["robots_spawned"] += 1
        if foreman:
            self.log(f"FOREMAN arrives (Thumper x3 HP = {self.robots[-1].maxhp:.0f} HP, bonus trait {traits[-1]})")

    def live(self):
        return [r for r in self.robots if r.alive]

    def close_wave(self, outcome):
        rec = self.wave_rec
        if rec is None or "outcome" in rec:
            return
        rec["outcome"] = outcome
        rec["seconds"] = round(self.t - self.wave_start_t)
        rec["kills"] = self.wave_kills
        rec["structure_end"] = round(max(0, self.silo.structure))
        rec["grain_end"] = round(max(0, self.silo.grain))
        rec["cracks_end"] = len(self.silo.cracks)
        rec["damage_taken"] = round(self.stats["damage_taken"] - rec.pop("dmg_taken_start"))
        rec["hp_end"] = round(max(0, self.player.hp))
        ps = rec.pop("parts_start")
        rec["parts"] = {k: self.run_stats["parts"][k] - ps[k] for k in ps}
        rec["distance_m"] = round(self.stats["distance"] - rec.pop("dist_start"))
        sb = rec.pop("silo_by_start")
        rec["silo_damage_by"] = {k: round(v - sb.get(k, 0)) for k, v in self.stats["silo_damage_by"].items() if v - sb.get(k, 0) > 0.5}
        ss = rec.pop("shots_start")
        rec["shots"] = {k: (v["fired"] - ss[k][0], v["hits"] - ss[k][1]) for k, v in self.wstats.items() if v["fired"] - ss[k][0] > 0}

    def enter_cleared(self):
        self.close_wave("cleared")
        self.phase = PH_CLEARED
        self.phase_left = CLEARED_HOLD
        w = self.wave
        self.stats["waves_cleared"] += 1
        self.run_stats["waves_cleared"] += 1
        before = self.silo.grain
        self.silo.grain = min(MAX_GRAIN, self.silo.grain + HARVEST_BONUS)
        rewards = dict(SALVAGE) if w % SALVAGE_EVERY == 0 else {}
        if self.bell_rung_wave == w:
            rewards["al"] = EARLY_BIRD_AL
            self.stats["early_bird"]["al"] += EARLY_BIRD_AL
        for k, v in rewards.items():
            self.parts[k] += v
            self.run_stats["parts"][k] += v
            if not (k == "al" and self.bell_rung_wave == w):
                self.stats["salvage"][k] += v
        self.log(f"Wave {w} CLEARED in {self.t - self.wave_start_t:.0f}s ({self.wave_kills} kills). "
                 f"Silo {self.silo.structure:.0f}/1000 structure, {self.silo.grain:.0f} grain "
                 f"(+{self.silo.grain - before:.0f} harvest), {len(self.silo.cracks)} open cracks"
                 + (f"; salvage {rewards}" if rewards else ""))

    # --- combat bookkeeping ---------------------------------------------------------------------
    def kill(self, r, weapon):
        r.alive = False
        if r.thief:
            self.stats["thieves_killed"] += 1
        self.wave_kills += 1
        self.run_stats["kills"] += 1
        self.stats["kills"][r.name if not r.foreman else "foreman"] = self.stats["kills"].get(r.name if not r.foreman else "foreman", 0) + 1
        self.stats["kills_by_weapon"][weapon] = self.stats["kills_by_weapon"].get(weapon, 0) + 1
        if weapon in self.wstats:
            self.wstats[weapon]["kills"] += 1
        if r.first_hit_t is not None:
            key = "foreman" if r.foreman else r.name
            self.stats["ttk"].setdefault(key, []).append(self.t - r.first_hit_t)
        # drops (Robot.roll_drops)
        if r.foreman:
            drops = dict(FOREMAN_DROPS)
            for k in ("au", "pc"):
                self.parts[k] += drops[k]; self.stats["foreman_bounty"][k] += drops[k]; self.run_stats["parts"][k] += drops[k]
                drops[k] = 0
            self.log(f"Foreman down after {self.t - (r.first_hit_t or self.t):.0f}s of fighting: bounty +2 Au +3 PC banked")
        else:
            a = r.a
            gold = 1.0; pcm = 1.0
            for t in r.traits:
                gold *= TRAITS[t].get("gold", 1.0); pcm *= TRAITS[t].get("pc", 1.0)
            al = (self.rng.randint(*a["al"]) + a["al_bonus"]) * drop_mult(r.wave)
            drops = {
                "al": int(al) + (1 if self.rng.random() < al - int(al) else 0),
                "cu": self.rng.randint(*a["cu_n"]) if self.rng.random() < a["cu"] else 0,
                "au": 1 if self.rng.random() < a["au"] * gold else 0,
                "pc": 1 if self.rng.random() < a["pc"] * pcm else 0,
            }
        at = (r.x, r.y)
        if r.kind == "drone":
            at = (r.x, r.y)  # falls below the orbit, 22 m out
        for k, v in drops.items():
            if v > 0:
                ang = self.rng.uniform(0, 2 * math.pi); rad = self.rng.uniform(0.3, 1.6)
                self.pickups.append([at[0] + math.cos(ang) * rad, at[1] + math.sin(ang) * rad, k, v])
        if r.sack > 0:
            self.sacks.append([r.x, r.y, r.sack, self.t])
            r.sack = 0
        if r.blast > 0:
            for o in self.robots:
                if o.alive and o is not r and dist(o.pos(), r.pos()) <= r.blast:
                    o.take_damage(r.blast_dmg, weapon, r.pos())
            d = dist(self.player.pos(), r.pos())
            if d <= r.blast and self.player.alive:
                self.player.take_damage(r.blast_farmer * max(0.5, 1 - d / r.blast), "overcharged blast")

    def escape(self, r):
        r.alive = False
        r.escaped = True
        if r.sack > 0:
            self.stats["thieves_escaped"] += 1
            self.log(f"A thief escaped into the corn with {r.sack:.0f} bushels")
        if r.squad is not None and r.squad.heist_leader is r:
            r.squad.heist_escaped = True

    def ranged_cancel(self, r):
        r.rstate = "idle"

    def ranged_step(self, r, prof, dt):
        p = self.player
        if r.rstate == "idle":
            target = "silo"
            if r.kind == "drone" and r.silo_d() > DRONE_FIRE_R:
                return
            if r.targeting.goal == "farmer" and p.alive and dist3(r.pos(), r.z, p.pos(), p.z) <= prof["range"]:
                held = sum(1 for o in self.robots if o.alive and o.rstate == "charge" and o.rtarget == "farmer")
                if held < farmer_tokens(r.wave):
                    target = "farmer"
            r.rtarget = target
            r.rstate = "charge"
            r.rtimer = max(0.45, prof["charge"] * charge_mult(r.wave))
        elif r.rstate == "charge":
            r.rtimer -= dt
            if r.rtimer <= 0:
                if r.rtarget == "farmer":
                    d = dist3(r.pos(), r.z, p.pos(), p.z)
                else:
                    d = max(1.0, r.silo_d() - SILO_R)
                flight = d / prof["speed"] * (1.3 if prof["kind"] == "lob" else 1.0)
                self.shots.append([self.t + flight, r, r.rtarget, prof])
                r.rstate = "recover"
                r.rtimer = max(0.0, prof["interval"] - max(0.45, prof["charge"] * charge_mult(r.wave)))
        elif r.rstate == "recover":
            r.rtimer -= dt
            if r.rtimer <= 0:
                r.rstate = "idle"

    def resolve_shots(self):
        keep = []
        for s in self.shots:
            if s[0] > self.t:
                keep.append(s); continue
            _, r, target, prof = s
            if target == "farmer":
                if self.player.alive and self.rng.random() < self.land_chance(prof["kind"], r):
                    self.player.take_damage(prof["dmg_f"] * r.dm, r.name)
            else:
                band = 0 if r.kind == "spitter" else (1 if self.rng.random() < 0.6 else 2)
                self.silo.hit(prof["dmg_s"] * r.dm, angle_of(r.pos()), band, r)
        self.shots = keep

    def collect(self):
        p = self.player
        if not p.alive:
            return
        mr = p.magnet()
        keep = []
        for pk in self.pickups:
            if math.hypot(pk[0] - p.x, pk[1] - p.y) <= mr and p.z < 1:
                self.parts[pk[2]] += pk[3]
                self.stats["collected"][pk[2]] += pk[3]
                self.run_stats["parts"][pk[2]] += pk[3]
            else:
                keep.append(pk)
        self.pickups = keep
        sk = []
        for s in self.sacks:
            if self.t - s[3] > 20.0:
                self.log(f"A dropped grain sack burst ({s[2]:.0f} bushels lost)")
                continue
            if math.hypot(s[0] - p.x, s[1] - p.y) <= 1.4:
                self.silo.grain = min(MAX_GRAIN, self.silo.grain + s[2])
                self.stats["grain_recovered"] += s[2]
            else:
                sk.append(s)
        self.sacks = sk

    # --- shopping -------------------------------------------------------------------------------
    def affordable(self, cost):
        return all(self.parts.get(k, 0) >= v for k, v in cost.items())

    def shop(self):
        per = self.persona
        pri = list(per.priority)
        if self.deaths >= per.shotgun_after_deaths:
            pri = SHOTGUN_PRIORITY + pri
        if self.deaths >= per.rifle_after_deaths:
            pri = RIFLE_PRIORITY + pri
        saving_for = {u for u, _ in (RIFLE_PRIORITY[:1] + SHOTGUN_PRIORITY[:1]) if (u, 1) in pri[:2]}
        bought = True
        while bought:
            bought = False
            for uid, target in pri:
                lvl = self.levels.get(uid, 0)
                spec = UPGRADES[uid]
                if lvl >= target or lvl >= spec["max"]:
                    continue
                if any(self.levels.get(q, 0) < n for q, n in spec["req"]):
                    continue
                if spec.get("min_wave", 0) > self.wave:
                    continue
                cost = upgrade_cost(uid, lvl + 1)
                if uid in saving_for and not self.affordable(cost):
                    break  # saving up for the new gun
                if self.affordable(cost):
                    for k, v in cost.items():
                        self.parts[k] -= v; self.stats["spent"][k] += v
                    self.levels[uid] = lvl + 1
                    self.purchases.append((self.t, uid, lvl + 1, cost, self.wave, self.deaths))
                    self.log(f"Bought {UPGRADE_NAMES[uid]} L{lvl + 1} for {cost}")
                    if uid == "defend.hearty_breakfast":
                        self.player.hp += 10
                    if uid.startswith("defend.armor"):
                        self.player.armor = self.player.max_armor()
                    bought = True
                    break

    def next_goal(self):
        pri = list(self.persona.priority)
        if self.deaths >= self.persona.rifle_after_deaths:
            pri = RIFLE_PRIORITY + pri
        for uid, target in pri:
            lvl = self.levels.get(uid, 0)
            if lvl < target and lvl < UPGRADES[uid]["max"]:
                return uid, lvl + 1, upgrade_cost(uid, lvl + 1)
        return None

    # --- intermission plan ----------------------------------------------------------------------
    def plan_intermission(self):
        per, p = self.persona, self.player
        tasks = [("collect", min(14.0, 6.0 + 0.4 * len(self.pickups)))]
        for c in list(self.silo.cracks):
            chance = per.repair_intermission * (1.0 if c.band == 0 else 0.3)
            if self.rng.random() < chance:
                tasks.append(("repair", c))
        tasks.append(("goto", SHED, "shed"))
        shop_t = max(25.0, self.rng.gauss(per.shop_mean, 10.0))
        tasks.append(("shop", shop_t))
        tasks.append(("maybe_heal", None))
        if self.rng.random() < per.bell:
            tasks.append(("bell", None))
        tasks.append(("ring", None))
        p.task = None
        self.tasks = tasks
        self.bell_rung_wave = getattr(self, "bell_rung_wave", 0)

    # --- main loop ------------------------------------------------------------------------------
    def run(self):
        self.new_run(first=True)
        while self.t < self.quit_t:
            if self.over:
                self.advance_block(10.0, PH_OVER)  # harvest report, press R
                if self.t >= self.quit_t:
                    break
                self.new_run(first=False)
                continue
            self.step(DT)
        self.end_phase = PHASE_NAMES[self.phase]
        if self.phase in (PH_SPAWN, PH_MOP) and not self.over:
            self.close_wave("quit mid-wave")
        self.run_stats["end"] = self.run_stats["end"] or self.t
        return self

    def step(self, dt):
        self.t += dt
        self.stats["time_in_phase"][PHASE_NAMES[self.phase]] += dt
        ph = self.phase
        if ph == PH_INTER:
            self.phase_left -= dt
            if self.phase_left <= SIREN_LEAD:
                self.enter_siren()
        elif ph == PH_SIREN:
            self.phase_left -= dt
            if self.phase_left <= 0:
                self.enter_spawning()
        elif ph == PH_SPAWN:
            self.spawn_clock += dt
            self.spawn_due()
            if self.spawn_clock >= self.window:
                self.phase = PH_MOP
        elif ph == PH_MOP:
            self.spawn_clock += dt
            self.mop_time += dt
            self.spawn_due()
            if self.spawned >= len(self.ev) and not self.live():
                self.enter_cleared()
        elif ph == PH_CLEARED:
            self.phase_left -= dt
            if self.phase_left <= 0:
                self.wave += 1
                self.robots = [r for r in self.robots if r.alive]
                self.enter_intermission()
        for r in self.robots:
            if r.alive:
                r.step(dt)
                if self.over:
                    return
        self.resolve_shots()
        if self.over:
            return
        self.silo.tick(dt)
        if self.over:
            return
        self.player_step(dt)
        self.collect()
        if len(self.robots) > 200:
            self.robots = [r for r in self.robots if r.alive]

    # =============================================================================================
    # Player brain
    # =============================================================================================
    def player_step(self, dt):
        p, per = self.player, self.persona
        if not p.alive:
            return
        p.tick_common(dt)
        p.repairing = False
        if self.phase in (PH_SPAWN, PH_MOP):
            self.stats["combat_time"] += dt
            d_wall = dist(p.pos(), (0, 0)) - SILO_R
            self.stats["ring_samples"][0] += d_wall * dt
            self.stats["ring_samples"][1] += dt
            if d_wall > 10.0:
                self.stats["time_far_from_silo"] += dt
            if p.target is not None and p.target.alive:
                self.wstats[p.weapon]["equipped"] += dt
        if self.phase == PH_INTER or (self.phase == PH_SIREN and self.tasks):
            self.intermission_step(dt)
            return
        self.combat_step(dt)

    def run_task_repair(self, c, dt):
        p = self.player
        if c not in self.silo.cracks:
            return True
        if c.band == 0:
            spot = (math.cos(c.angle) * (SILO_R + 0.8), math.sin(c.angle) * (SILO_R + 0.8))
            if not p.move_to(spot, p.run_speed(), dt, stop=0.3):
                return False
            climb = 0.0
        else:
            ladder = (SILO_R + 0.8, 0.0)
            if not getattr(c, "climbed", False):
                if not p.move_to(ladder, p.run_speed(), dt, stop=0.3):
                    return False
                c.climbed = True
                c.climb_left = 4.0 if c.band == 1 else 7.0
            if c.climb_left > 0:
                c.climb_left -= dt
                return False
        p.repairing = True
        speed = 1.0 + 0.15 * self.levels.get("repair.elbow_grease", 0)
        restored = c.repair(dt * speed)
        self.silo.structure = min(MAX_STRUCTURE, self.silo.structure + restored)
        self.stats["structure_repaired"] += restored
        self.stats["repair_seconds"] += dt
        if c.pool <= 0:
            self.silo.cracks.remove(c)
            self.stats["cracks_repaired"] += 1
            return True
        return False

    def intermission_step(self, dt):
        p, per = self.player, self.persona
        if not self.tasks:
            return
        task = self.tasks[0]
        kind = task[0]
        done = False
        if kind == "collect":
            if p.task is None:
                p.task = task[1]
            p.task -= dt
            near = [pk for pk in self.pickups if math.hypot(pk[0], pk[1]) <= per.sweep_radius]
            sk = [s for s in self.sacks if math.hypot(s[0], s[1]) <= 30]
            if (not near and not sk) or p.task <= 0:
                done = True
            else:
                tgt = min(near + sk, key=lambda q: math.hypot(q[0] - p.x, q[1] - p.y))
                p.move_to((tgt[0], tgt[1]), p.run_speed(), dt)
        elif kind == "repair":
            done = self.run_task_repair(task[1], dt)
        elif kind == "goto":
            done = p.move_to(task[1], p.run_speed(), dt, stop=1.5)
        elif kind == "shop":
            if p.task is None:
                p.task = min(task[1], max(5.0, self.phase_left - 1.0)) if self.phase == PH_INTER else 0.0
                self.shop()
                self.stats["upgrade_time"] += p.task
            p.task -= dt
            if p.task <= 0 or self.phase != PH_INTER:
                done = True
        elif kind == "maybe_heal":
            if p.hp < per.heal_break_hp * p.maxhp() and self.phase == PH_INTER and self.phase_left > 8:
                if p.task is None:
                    self.stats["porch_visits"] += 1
                    p.task = 1
                if p.move_to(PORCH, p.run_speed(), dt, stop=1.0):
                    done = p.hp >= 0.95 * p.maxhp() or self.phase_left < 4
            else:
                done = True
        elif kind == "bell":
            if self.phase != PH_INTER:
                done = True
            elif p.move_to(BELL, p.run_speed(), dt, stop=1.5):
                self.bell_rung_wave = self.wave
                self.log(f"Rang the dinner bell with {self.phase_left:.0f}s of the break left")
                self.enter_siren()
                done = True
        elif kind == "ring":
            ang = angle_of(p.pos()) if math.hypot(p.x, p.y) > 1 else 0.0
            goal = (math.cos(ang) * p.ring_r, math.sin(ang) * p.ring_r)
            done = p.move_to(goal, p.run_speed(), dt, stop=0.5)
        if done:
            self.tasks.pop(0)
            p.task = None

    def act(self, what, dt):
        if self.phase in (PH_SPAWN, PH_MOP):
            a = self.stats["activity"]
            a[what] = a.get(what, 0.0) + dt

    def combat_step(self, dt):
        p, per, rng = self.player, self.persona, self.rng
        if p.z > 0 and p.task is None:
            p.z = 0.0
        # ongoing multi-step tasks: porch run, repair, roof climb, sack retrieval
        if p.task is not None:
            self.act("task:" + p.task[0], dt)
            if self.run_combat_task(dt):
                p.task = None
            return
        # 1. low HP: get to the porch (they would rather not get hit than hold the silo)
        if p.hp < per.heal_wave_hp * p.maxhp():
            self.stats["porch_visits"] += 1
            self.log(f"Low HP ({p.hp:.0f}) -> running to the porch to heal")
            p.task = ("heal",)
            return
        live = [r for r in self.robots if r.alive]
        # 2. chased by a ground robot: back away (the only time they leave the silo) or turn and fight
        chasers = [r for r in live if r.targeting.goal == "farmer" and r.kind == "ground" and not r.thief
                   and dist(r.pos(), p.pos()) < 9.0]
        if chasers:
            c = min(chasers, key=lambda r: dist(r.pos(), p.pos()))
            # Re-decide every few seconds: back off (their preference) or stand and swing.
            if self.t - getattr(p, "chase_roll_t", -99) > 4.0 or c.id not in p.chase_choice:
                p.chase_roll_t = self.t
                fight = per.fight_chaser * (1.4 if c.name == "nibbler" else 0.6)
                p.chase_choice[c.id] = rng.random() < fight
                p.kite_shoot = rng.random() < 0.5
            d_c = dist(c.pos(), p.pos())
            reach = WEAPONS["wrench"]["reach"] + c.radius + 0.3
            finish = p.weapon == "wrench" and d_c <= reach and (
                c.hp <= p.wstat("wrench")["dmg"] * 1.5 or c.state == "recover")
            if p.chase_choice[c.id] or finish:
                self.act("fight chaser", dt)
                if p.weapon != "wrench" and d_c < 4:
                    p.equip("wrench")
                p.target = c
                if not p.try_attack(c):
                    p.move_to(c.pos(), p.run_speed(), dt)
                return
            self.act("back away from chaser", dt)
            away = unit((p.x - c.x, p.y - c.y))
            out = unit(p.pos())
            u = unit((away[0] + 0.5 * out[0], away[1] + 0.5 * out[1]))
            if p.kite_shoot and p.weapon != "wrench" and p.try_attack(c):
                p.target = c
                p.move_dir(u, AIM_SPEED, dt)
            else:
                p.move_dir(u, p.run_speed(), dt)
            return
        # 3. dropped grain sacks close to the silo
        for s in self.sacks:
            if math.hypot(s[0], s[1]) < 30:
                p.task = ("sack", s)
                return
        # 4. pick a target
        if self.t - p.pick_t > 0.5 or p.target is None or not p.target.alive:
            p.pick_t = self.t
            new = self.pick_target(live)
            if new is not p.target and new is not None:
                p.target = new
                need_gun = new.kind in ("lobber", "drone") and new.z > 2.5
                if need_gun or p.weapon == "wrench" or rng.random() < 0.35:
                    p.equip(p.pick_weapon(new))
                if need_gun and p.weapon == "wrench":
                    if new.kind == "lobber" and (self.phase == PH_MOP or len(live) <= 2):
                        p.task = ("roof", new)
                        self.log(f"Wrench only: climbing the {new.roof['name']} roof after a Roof Lobber")
                        return
                    p.target = None
            elif new is None:
                p.target = None
        r = p.target
        if r is not None and r.alive:
            if p.try_attack(r):
                self.act("attacking (in reach)", dt)
                if p.weapon != "wrench":
                    # strafe along the ring while aiming
                    tang = unit((-p.y, p.x))
                    p.move_dir(tang, 1.0, dt)
                return
            # move into reach, staying near the silo unless the straggler hunt is on
            self.act("closing on target", dt)
            hunting = self.phase == PH_MOP and self.mop_time > STRAGGLER_TIME
            goal = r.pos()
            if p.weapon != "wrench" and not hunting:
                u = unit(goal); rr = min(per.ring[1], max(per.ring[0], math.hypot(*goal)))
                goal = (u[0] * rr, u[1] * rr)
            speed = AIM_SPEED if p.weapon != "wrench" else p.run_speed()
            p.move_to(goal, speed if dist(goal, p.pos()) < 6 else p.run_speed(), dt, stop=0.5)
            return
        # 5. nothing to hit: maybe patch a crack, otherwise circle the silo watching the lanes
        p.repair_check += dt
        if p.repair_check >= 4.0:
            p.repair_check = 0.0
            ground = [c for c in self.silo.cracks if c.band == 0]
            if ground and rng.random() < per.repair_in_wave:
                p.task = ("repair", min(ground, key=lambda c: ang_diff(c.angle, angle_of(p.pos()))))
                return
        self.act("circling silo, no target", dt)
        if self.t - p.ring_t > 15:
            p.ring_t = self.t
            p.ring_r = rng.uniform(*per.ring)
        cur = angle_of(p.pos())
        aim_at = None
        app = [r for r in live]
        if app:
            aim_at = angle_of(min(app, key=lambda r: r.silo_d()).pos())
        else:
            aim_at = angle_of(LANES[self.lanes[0]])
        delta = (aim_at - cur + math.pi) % (2 * math.pi) - math.pi
        step_ang = max(-0.35, min(0.35, delta))
        tgt = (math.cos(cur + step_ang) * p.ring_r, math.sin(cur + step_ang) * p.ring_r)
        p.move_to(tgt, 3.0 if abs(delta) < 0.4 else p.run_speed(), dt)

    def pick_target(self, live):
        p, per = self.player, self.persona
        owned_gun = len(p.owned()) > 1
        hunting = self.phase == PH_MOP and self.mop_time > STRAGGLER_TIME
        best, best_s = None, 1e9
        for r in live:
            d = dist3(p.pos(), p.z, r.pos(), r.z)
            sd = r.silo_d()
            if r.thief and r.state == "flee" and sd < 35:
                s = d * 0.5
            elif r.thief and sd < per.ring[1] + 6:
                s = 2 + d * 0.5
            elif r.kind in ("ground", "spitter") and r.state in ("windup", "recover") and r.attack_target == "silo":
                s = 10 + d
            elif r.kind in ("ground", "spitter") and r.targeting.goal == "farmer" and d < 15:
                s = 12 + d
            elif r.kind in ("lobber", "drone") and (r.z > 2.5):
                if not hunting:
                    if not owned_gun:
                        continue
                    # only from the ring: is it within ~25 m of the nearest ring spot?
                    u = unit(r.pos()); rr = min(per.ring[1], max(per.ring[0], math.hypot(*r.pos())))
                    if dist3((u[0] * rr, u[1] * rr), 0.0, r.pos(), r.z) > (60 if "rifle" in p.owned() else 25):
                        continue
                s = 30 + d
            elif sd < per.ring[1] + 6:
                s = 20 + d
            elif owned_gun and d < 25 and r.z < 1:
                s = 35 + d
            elif hunting:
                s = 60 + d
            else:
                continue
            if s < best_s:
                best, best_s = r, s
        return best

    def run_combat_task(self, dt):
        p = self.player
        task = p.task
        kind = task[0]
        if kind == "heal":
            if p.move_to(PORCH, p.run_speed(), dt, stop=1.0):
                return p.hp >= 0.9 * p.maxhp()
            return False
        if kind == "repair":
            threat = any(r.alive and r.targeting.goal == "farmer" and dist(r.pos(), p.pos()) < 10 for r in self.robots)
            if threat:
                return True
            return self.run_task_repair(task[1], dt)
        if kind == "sack":
            s = task[1]
            if s not in self.sacks:
                return True
            p.move_to((s[0], s[1]), p.run_speed(), dt)
            return False
        if kind == "roof":
            r = task[1]
            roof = r.roof
            if not r.alive:
                if p.z > 0:
                    if not hasattr(p, "down_left"):
                        p.down_left = 2.0
                    p.down_left -= dt
                    if p.down_left <= 0:
                        p.z = 0.0
                        p.x, p.y = roof["entry"]
                        del p.down_left
                        return True
                    return False
                return True
            if p.z == 0:
                if p.move_to(roof["entry"], p.run_speed(), dt, stop=1.0):
                    if not hasattr(p, "climb_left"):
                        p.climb_left = 1.5 + roof["h"] / 1.8  # ladders / mantles (ASSUMPTION)
                    p.climb_left -= dt
                    if p.climb_left <= 0:
                        del p.climb_left
                        p.z = roof["h"]
                        p.x, p.y = roof["top"][0] + 1.5, roof["top"][1]
                return False
            if not p.try_attack(r):
                p.move_to(r.pos(), p.run_speed(), dt)
            return False
        return True
