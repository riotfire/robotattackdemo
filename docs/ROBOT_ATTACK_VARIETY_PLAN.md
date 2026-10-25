# Robot Attack! — robot attack variety plan

October 25, 2026. Decisions R-D1 to R-D6 were made on October 25, 2026 (the recommendations below were accepted). The work packages are M2-B6 to M2-B15 in [the roadmap](ROADMAP.md#robot-attack-variety). **Built:** M2-B6 (behavior variables and groups), M2-B7 (shared ranged attack and telegraphs), M2-B8 (hit-height cracks), M2-B9 (the Spitter, out-of-reach throws and the Clanker's arm guard) and M2-B10 (the scaling curve); GDD sections 3.3, 9.1–9.6, 11.4, 11.6, 11.7 and 11.8 now describe them, and [what was built](#built-notes-m2-b9-and-b10) lists the calls made while building. Everything else here is still design.

**Goal:** every robot size can fight up close, from range or from the air, each kind of attacker hurts the silo in its own way, and later waves get harder through how robots behave, not just bigger numbers.

## How this fits the other plans

- **The opening is authored separately.** [The first five waves plan](FIRST_FIVE_WAVES_FUN_PLAN.md) authors waves 1–5. This plan adds no new archetype, sidearm, battle plan or trait to those waves. The opening still uses this plan's building blocks: the Roof Lobber's charge glow and landing marker (wave 3), the teaching thief, and the fixed-behavior wave-5 Foreman. Waves 1–2 keep cracks at ground level. Everything below about scaling starts at wave 6.
- **Flight is a reward, never a requirement.** As [the jetpack plan](JETPACK_GAMEPLAY_AND_REWARD_PLAN.md) requires, every enemy can be beaten without the jetpack; flight may only make a fight shorter or more expressive.
  - Airborne farmers get the same telegraphs and attack tokens as everyone else, and lobs never lead their target, so there is no perfect tracking and no anti-air you can't dodge.
  - Out-of-reach throwing stops after two throws and the robot goes back to the silo. Hovering is neither immune nor a lure.
  - The flying archetypes (Crop Duster, Harvester Blimp) wait for that plan's stage 3, the combat proof, because it asks for flight encounters to be proven before the enemy catalog grows.
  - The Clanker arm guard (M2-B9) gives the jetpack prototype the directional defense it wants on an existing robot.

## The attack grid

Rows are sizes; columns are attack styles. Damage is at wave 1, shown as *farmer / silo*.

| | **Melee** (close up) | **Ranged** (long-distance projectile) | **Flight** (projectile from above) |
|---|---|---|---|
| **Small** | **Nibbler** *(built)*<br>**Move:** unicycle at 8 m/s, faster than the farmer; weaves a little on approach.<br>**Attack:** nips once a second, 4 / 6; opens ground cracks. Trios nip in a 3-beat rhythm (*nip-nip-NIP*).<br>**Defend:** 30 HP and a tiny target; its speed is its armor, and any hit knocks it back.<br>**Behave:** heads straight for the silo. Thieves grab a 20-bushel sack and sprint for the corn. | **Spitter** *(built in M2-B9: a role of the small ground robot, with a pea-shooter)*<br>**Move:** 7 m/s; stops 12–16 m from its target and hops to a new spot every 3 shots.<br>**Attack:** 0.8 s glowing charge, then a 14 m/s pea, 3 / 5 every 2.2 s. Aims at catwalk height, so it opens **high cracks**. A trio fires a staggered 3-beat volley.<br>**Defend:** 30 HP. Stands still while it charges, so that is the moment to rush it. Backs off 4 m once if the farmer gets within 5 m.<br>**Behave:** from wave 7, a share of small ground robots spawn as Spitters. | **Drone** *(built; replaces the GDD's Buzzer)*<br>**Move:** rises to 14 m and circles the silo 22 m out at 9 m/s.<br>**Attack:** 0.9 s charge, then a straight shot, 4 / 8 every 2.8 s; hits the top of the silo, opening upper-catwalk cracks.<br>**Defend:** 35 HP; altitude makes it hard to hit from the ground.<br>**Behave:** goes after a farmer who is jetpacking or on a perch within 24 m; otherwise shoots the silo. Always solo. |
| **Medium** | **Clanker** *(built)*<br>**Move:** 4.5 m/s waddle. Usually alone; a rare trio walks in a triangle behind its leader.<br>**Attack:** punches every 1.2 s, 8 / 12. A trio punches one spot in a 3-beat rhythm (*clank-clank-CLANK*), so that crack grows fast.<br>**Defend:** 60 HP. Raises an arm guard that halves damage from the front, so flank it *(built, from wave 6)*.<br>**Behave:** never steals. If its target is out of reach it throws up to two bolts (5 / 8), then goes back to the silo *(built, from wave 7)*. | **Roof Lobber** *(built; moves up from small to medium)*<br>**Move:** walks to a building, climbs its wall at 3.2 m/s and perches on the roof. Usually one per roof; a rare trio shares a roof.<br>**Attack:** arcing lob with a chalk circle where it will land, 6 / 12 every 3.6 s; a trio fires a 3-beat volley. 2 m splash from wave 12.<br>**Defend:** 60 HP. It can't attack while it climbs, which is the best time to kill it. Knockback (shotgun, maul) throws it off the roof and stuns it.<br>**Behave:** if the farmer reaches its roof, it drops down and climbs a different building. | **Crop Duster** *(new; waits for the jetpack combat proof)*<br>**Move:** flies in alone from its lane at 18 m and makes straight passes over the silo at 10 m/s, banking and looping back. It can't hover.<br>**Attack:** drops 3 bombs per pass, with shadow circles showing where each lands 1 s ahead, 10 / 15. Hits the silo roof and the ground where the farmer stands to repair.<br>**Defend:** 50 HP. A belly plate halves damage from steep angles below, so shoot from a perch level with its path.<br>**Behave:** silo-focused; only targets a farmer perched on its flight path. |
| **Large** | **Thumper** *(built)*<br>**Move:** treads at 2.5 m/s; can't be knocked back and shoves smaller robots aside. Turns at no more than 60°/s, so circling behind it works.<br>**Attack:** rears up for 0.8 s, then slams, 25 / 60 every 2.5 s, plus a 10-damage shockwave ring you can jump. Against an out-of-reach farmer: up to two lobbed clods (chalk circle, 15 splash), then back to the silo *(built, from wave 7)*.<br>**Defend:** 400 HP, armored front, back vent weak point ×2.<br>**Behave:** slow and committed. Always solo. | **Longneck** *(GDD, not built)*<br>**Move:** 2 m/s to a siege spot 45–55 m out facing the silo, then plants stabilizer legs.<br>**Attack:** 2 s red-yarn aim line, then a rail shot, 80 to the silo every 6 s. Deals 30 to a farmer standing in the line, so the farmer can shield the silo with their body.<br>**Defend:** 400 HP, front shield, top hatch weak point ×3 (hit it from a high perch or the jetpack). Turns slowly once planted.<br>**Behave:** moves to a new siege spot after 4 shots. Always solo. | **Harvester Blimp** *(new; waits for the jetpack combat proof)*<br>**Move:** drifts in at 3 m/s, 24 m up, and parks over the silo.<br>**Attack:** lowers a hose onto the silo roof that **siphons 4 bushels/s**, drops a Nibbler every 10 s, and has a belly turret that shoots a farmer within 15 m, 4 per shot.<br>**Defend:** 600 HP; belly armor blocks 75% from below; the balloon top is a weak point ×2; the hose can be cut (150 HP) from the upper catwalk.<br>**Behave:** a cut hose is reeled in and lowered again 5 s later. At 30% HP it flees with the stolen grain; shoot it down to get the grain back. Always solo. |

## Groups (trios)

Groups of three are no longer a fixed Grunt rule. Each archetype has a `trio_chance`:

| Size | On the ground (melee, ranged) | Flying |
|---|---|---|
| **Small** | Usually a trio: 40% in waves 1–2, then 60%, rising to 70% by wave 15 | Solo |
| **Medium** | Rarely a trio: 15% | Solo |
| **Large** | Solo | Solo |
| **Foreman** | Solo | Solo |

Authored opening waves set their groups explicitly instead of rolling them (see decision R-D5).

**How a trio works:**

- **One roll for the group.** The leader rolls the target, role and any distraction; the other two follow.
- **Formation:** a loose triangle behind the leader.
- **Rhythm:** the 3-beat attack belongs to trios, not to Clankers.
- **Heist crew** (replaces "squads never steal"): in a thief trio, only the leader carries a sack, and the other two escort it and fight anyone who chases it. The trio counts as one thief toward the wave's thief share.
- **Cost:** threat cost is per robot × group size. Per robot it is size cost × column multiplier: Small 2, Medium 4, Large 14; melee ×1.0, ranged ×1.25, flight ×1.6. A solo Clanker costs twice a Nibbler, matching its double HP. The spawn type weights need retuning with M2-B11.

## Behavior variables

Every robot has the same set of variables. Each archetype sets its defaults, and family traits and battle plans can change them.

| Variable | Range | What it does | In code today |
|---|---|---|---|
| `silo_focus` | 0–1 | Chance at spawn to go for the silo; otherwise it goes for the farmer. | Yes, as 1 − `farmer_target_chance` |
| `thief_chance` | 0–1 | Chance a silo-bound robot steals grain instead of doing damage. Small robots steal with a sack, the Blimp with its hose. | Yes, as `steal_chance` plus the thief curve |
| `trio_chance` | 0–1 | Chance a spawn is a trio (see above). Forced to 0 for flyers, large robots and Foremen. | No (`squad_size` is fixed) |
| `distractibility` | 0–1 | Once a second while attacking the silo, the chance to switch to the farmer when one of its triggers is active. | No |
| `distract_triggers` | any of `hurt`, `near`, `repairing`, `airborne` | **hurt:** the farmer damaged it. **near:** the farmer is within `distract_range`. **repairing:** the farmer is repairing a crack within range. **airborne:** the farmer is jetpacking or on a perch. | Partly: `hurt` is today's aggro |
| `distract_range` | m | How close the farmer must be for a trigger to count. | Yes, as `aggro_range` |
| `commit_time` | s | Minimum time on a target before it can switch again, so robots don't flip back and forth. | No |
| `chase_time` | s | Goes back to the silo after chasing the farmer this long. | No |
| `leash_range` | m | Goes back to the silo if the farmer leads it this far from the silo. | No |
| `give_up_time` | s | Goes back to the silo if the farmer stays out of reach this long. | Yes, as `unreachable_give_up_time` |
| `on_unreachable` | `give_up` / `throw` / `relocate` | What it does when it can't reach its target. `throw` makes up to two telegraphed throws, then gives up. | No (always gives up) |

**Rules that apply to every robot:**

- It goes back to the silo when **any** return condition is met, or when the farmer goes down.
- Thieves carrying a sack are never distracted.
- When a robot switches to the farmer it shows a "!" pop and an angry eye.

### Defaults per robot

| Robot | silo_focus | thief_chance | trio_chance | distractibility | triggers | range | chase / leash / give-up | on_unreachable |
|---|---|---|---|---|---|---|---|---|
| Nibbler | 0.7 | thief curve (10% → 40%) | 0.4 → 0.7 | 0.3 | hurt, near | 8 m | 6 s / 25 m / 3 s | give_up |
| Spitter | 0.6 | 0 | 0.4 → 0.7 | 0.6 | hurt, near, repairing | 12 m | 8 s / 30 m / — | relocate |
| Drone | 0.6 | 0 | 0 | 0.8 | airborne, near | 24 m | 8 s / 36 m from the silo / — | — |
| Clanker | 0.7 | 0 | 0.15 | 0.5 (a trio rolls once) | hurt | 10 m | 8 s / 30 m / 3 s | throw |
| Roof Lobber | 0.5 | 0 | 0.15 | 0.7 | near, repairing | 24 m | — / stays on its roof / — | relocate (new roof) |
| Crop Duster | 0.9 | 0 | 0 | 0.3 | airborne (perched on its path) | 18 m | one pass / — / — | — |
| Thumper | 0.8 | 0 | 0 | 0.2 | hurt | 10 m | 10 s / 20 m / 4 s | throw (clod) |
| Longneck | 1.0 | 0 | 0 | 0.2 | hurt | 15 m | 6 s / — / — | relocate |
| Harvester Blimp | 1.0 | 1.0 (siphon) | 0 | 0 (its turret aims on its own) | — | 15 m (turret) | — | — |

## Ways to hurt the silo

Each kind of attack hurts something different, so the player has to choose a response.

| How it attacks | What it damages | Player response | Who does it |
|---|---|---|---|
| **Bash** at the base | Ground cracks | Intercept on the ground | Nibbler, Clanker, Thumper |
| **Heist** at the chute or from above | Grain | Chase the sack, or cut the hose | Thief Nibblers, heist crews, Harvester Blimp |
| **Pelt from range** | High cracks | Climb, kill the shooter, repair up high | Spitter, Roof Lobber, Drone |
| **Bomb or mortar** with splash | Ground and roof cracks, plus a farmer repairing there | Leave the circle, hunt the bomber | Crop Duster, Roof Lobber (wave 12+), Thumper clods |
| **Siege** | Big hits from far away | Body-block the yarn line, then hit the top hatch | Longneck |

**Hits open cracks near where they land.** A new crack is weighted 70% toward the height band of the hit, replacing the fixed 50/30/20 weights (decision R-D3). Ground robots open low cracks and ranged and flying robots open high ones, so more ranged robots later means more catwalk repairs. Waves 1–2 stay ground-only, and the opening plan decides when the first catwalk crack appears.

## Fairness rules

- **Attack tokens:** only N robots may shoot at the farmer at once (N = 2 in the opening, then 3 / 4 / 5 by the scaling table). The rest shoot the silo.
- **Telegraphs:**
  - every shot charges a glow for at least 0.45 s;
  - lobs, mortars and bombs show a circle where they will land;
  - rails show a red-yarn aim line.
- **Dodgeable speed:** shots are slow enough to dodge, about 1 s of flight at the robot's range.
- **No out-of-reach perches:** every perch can be hit with the pistol from the ground, and every enemy can be beaten without flight.
- **Warnings and limits:** a HUD pip warns of shots coming from off screen, and a cap on projectiles in flight protects performance.

## Scaling from wave 6

The damage curve (GDD 11.5) already raises raw numbers, so these knobs change behavior instead. *Built in M2-B10 as `DifficultyCurve` functions (GDD 11.8).*

| Knob | Waves 6–15 | 16–30 | 31+ |
|---|---|---|---|
| Spitter share of small ground robots | 10% at wave 7, +2 points per wave | up to 40% | 40% |
| Charge-time multiplier (never under 0.45 s) | 0.9 | 0.8 | 0.7 |
| Aim lead (straight shots only, never lobs) | 0 until wave 10, then 0.3 | 0.6 | 0.6 |
| Farmer attack tokens | 3 | 4 | 5 |
| Shots per volley (Drone, Spitter trio) | 1 | 2–3 | 3 |
| Column weights, melee / ranged / flight | 60 / 28 / 12 | 52 / 30 / 18 | 45 / 33 / 22 |

**Ranged family traits** fill the GDD's existing trait slots:

- **Sharpshooter:** faster shots plus aim lead.
- **Scattershot:** +2 pellets.
- **Sticky:** shots leave goo that slows the farmer.
- **Spotter:** a marked target takes focused fire.

**Foremen** after the first get a ranged phase at 50% HP. The wave-5 Foreman keeps the opening plan's fixed behavior.

## Built notes (M2-B9 and B10)

Calls made while building, where the plan left a detail open:

- **Wave gates.** Spitters and out-of-reach throwing start at wave 7, as the unlock schedule says. The Clanker's arm guard starts at wave 6, so the opening keeps the M1 Clanker; its plate and the throwers' bolt pouch and clod scoop only show once they work. All three gates are `DifficultyCurve` settings.
- **The Spitter role.** The director picks a small ground melee archetype by its weight, then turns the group into Spitters with the Spitter share, if the budget covers them. The column weights are measured before that roll. Waves 1–6 build exactly the same spawns as before.
- **Throws.** A farmer must be out of reach for 0.5 s before the first throw, so a jump doesn't draw one, and within the throw's range (Clanker bolt 16 m, Thumper clod 18 m). Both are lobs with a chalk circle, so they never lead. A throw needs one of the farmer's attack tokens; with none free the robot doesn't throw at the silo instead, and gives up on its usual clock. The give-up clock holds while a throw is under way. In a trio each robot gets its two throws, and the first to finish sends the trio back. A robot whose farmer comes back within reach keeps fighting.
- **Arm guard.** "From the front" means within 60° of where the Clanker faces, judged from the attacker's position.
- **Spitter details.** It rolls its stand-off distance (12–16 m) once, hops 35° around its target every 3 shots, alternating sides, and can shoot a farmer up on a roof (it never gives up on one; `relocate` waits for M2-B12). Its pea aims 8.5 m up the silo and hits the wall at about 6.7 m from its stand-off distance, in the first catwalk band.
- **Volleys.** "2–3" in waves 16–30 is 2 shots in waves 16–23 and 3 from wave 24.

## Unlock schedule

Waves 1–5 follow the opening plan: Nibblers, then a Clanker and the teaching thief, the Roof Lobber at wave 3, a third-direction raid at wave 4, and the Thumper Foreman at wave 5.

| Wave | New threat |
|---|---|
| 6 | Drone; first family trait; battle plans begin (Rush, Rooftop, Heist) |
| 7 | Spitters; out-of-reach throwing |
| 8 | Sky Raid plan |
| 9 | Roof Lobber trios; Barrage plan |
| 10 | Longneck Foreman |
| 11 | Longneck in regular spawns; Crop Duster; Swarm plan |
| 12 | Roof Lobber splash; ranged traits; Pincer plan |
| 15 | Harvester Blimp Foreman (if the flyers aren't ready, the Longneck again) |
| 16+ | Every archetype; volleys; Blimp in regular spawns; Siege plan |

**Foreman rotation follows the grid's columns:** melee (Thumper, wave 5) → ranged (Longneck, wave 10) → flight (Harvester Blimp, wave 15), then repeating.

## Battle plans

Each wave from 6 on rolls a plan that bends its spawn mix and director rules, shown on the family name card (*"The Minty Pirate Teapots — Barrage!"*). Plans replace the director's hardcoded `roof_lobber` and `drone` checks and caps.

| Plan | From wave | Effect |
|---|---|---|
| Rush | 6 | Mostly melee |
| Rooftop | 6 | Up to 3 Roof Lobbers |
| Heist | 6 | Thief share ×1.5; Spitters guard the chute |
| Sky Raid | 8 | More Drones, fewer ground robots |
| Barrage | 9 | Ranged-heavy; more high cracks |
| Swarm | 11 | Small robots only, ×1.4 count, lower HP |
| Pincer | 12 | Opposite lanes spawn together |
| Siege | 16 | Longnecks with a screen of escorts |

**Plan rules:**

- No plan repeats within 3 waves.
- Big Hauls pair a plan with the Foreman.
- From wave 31, two plans stack (for example Barrage + Pincer).

## Decisions

All six were decided on October 25, 2026, as recommended.

| ID | Question | Decision |
|---|---|---|
| **R-D1** | The grid has no short-range class. What happens to the GDD's Spritzer, Popper and Boiler? | Drop them from M2 and revisit after the M2 playtest. The Longneck replaces the Boiler as the wave-10 Foreman. |
| **R-D2** | Should every melee robot throw at a farmer it can't reach? | Yes, up to two throws, then back to the silo. |
| **R-D3** | Should hit height pick the crack band instead of the fixed 50/30/20 weights? | Yes, with ground-only cracks in waves 1–2. |
| **R-D4** | Is the Drone the GDD's Buzzer? | Yes; the Roof Lobber becomes the medium ranged robot. |
| **R-D5** | The opening plan uses Clanker trios in waves 2–5, but Clankers now rarely form trios. | Use solo Clankers and Nibbler trios in the opening, so players learn the groups they will keep seeing. |
| **R-D6** | Should the flying archetypes wait for the jetpack plan's combat proof? | Yes, as that plan asks. Ground archetypes and the framework go first. |
