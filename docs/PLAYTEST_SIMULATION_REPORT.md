# Robot Attack: simulated play sessions from playtest averages

October 25, 2026. Built against the working tree at `be5e0b0` plus its uncommitted changes. Godot was not opened. Every rule in the model is taken from the project files, and each number names its source in [`tools/playtest_sim/game_data.py`](../tools/playtest_sim/game_data.py). The human side of the model comes from the 55-test playtest averages. Re-run everything with `python3 tools/playtest_sim/run_sims.py --cohort 1000` (about 2 minutes) and `python3 tools/playtest_sim/sensitivity.py 400`.

**Headline:** a player who plays the way your testers play clears waves 1–2 almost every time. They stall on waves 3–4 and never clear wave 5. Across 1,000 simulated sessions, 64% clear wave 3, 10% clear wave 4, 4% reach wave 5, and **none finish Phase 1**. The silo is usually lost to **grain leaking from cracks nobody repairs**, not to the farmer being knocked out. Those cracks keep leaking through the 90-second break. Players also spend more time between waves (41%) than fighting (35%). That fits the drop-off at 10 minutes.

---

## 1. What went into the model

### Your playtest data (behaviour inputs)

| Observation | How the simulated player uses it |
|---|---|
| Stays 3–10 m from the silo | Circles at 7–14 m from the silo centre (the silo radius is 4 m) and re-picks a radius every 15 s. Ground targets are engaged from that ring. Measured result: average 10.2 m from the wall during fights. |
| Gun hit rate 4–57% | Hit chance is 57% (the tester's best) at 3 m, falling to 4% at 38 m. Each tester's peak is drawn from 30–57%. The rifle falls off more slowly (it is the gun that "picks enemies off far away"). Measured pistol hit rate: 25%. |
| Melee hit rate 70–88% | Each wrench swing lands at the tester's rate, drawn from 70–88%. Measured: 79%. |
| Avoiding hits matters more than repairing | Dodges most telegraphed attacks (30–45% of attacks land). Repairs a ground crack during a break 20–45% of the time, a catwalk crack about a third as often. Starts a mid-wave repair only when nothing is nearby (6% per safe 4 s window). Runs to the porch below 30% HP. |
| Circles the silo and rarely approaches the fields | No target means circling the ring toward the nearest robot. The player leaves the ring only when chased, chasing a fleeing grain thief, or hunting marked stragglers 20 s into mop-up. |
| Backs away only when chased | A robot chasing the farmer triggers a choice every 4 s: back off (away from the robot and out from the silo) or turn and swing. A robot that is one hit from dying always gets finished. |
| Weapon preference: wrench 55%, pistol 28%, shotgun 8%, rifle 9% | Ground targets are picked with weights favouring the wrench. Roofs and the drone force a gun. The shotgun is bought after the first or second death and the rifle "after many deaths". |
| No other melee weapons obtained | Not modelled as an economy problem. See finding 5: those weapons are not on the pegboard at all. |
| Upgrading takes 67 s on average | Each break: collect loot near the silo, maybe repair, walk to the shed, shop for about N(67 s, 10 s), heal if hurt, return. Measured: 67.5 s per break. |
| Boredom curve 5 / 10 / 15 / 25 / 30+ minutes | The five headline simulations each represent one bucket. The 1,000-session cohort draws quit times from your 5 / 44 / 32 / 13 / 6% distribution. |

### Game rules (from the files, not assumed)

* **Waves** (`wave_director.gd`, `difficulty_curve.gd`, `default_difficulty.tres`):
  * 90 s break (the siren sounds for its last 3 s), then the spawn window: 45 s plus 7 s per wave.
  * Mop-up runs until every robot is gone, then a 2 s "Cleared" hold.
  * The threat budget pays for robots: Nibbler 2, Clanker 4, Roof Lobber 2.5, Drone 3.2, Thumper 14. A Big Haul wave multiplies the budget by 1.3 and adds a Foreman.
  * Roof Lobbers take about 25% of robots from wave 3 onward. Drones start at wave 5, with a cap.
  * HP and damage rise by +7% / +4% per wave.
* **Silo** (`silo.gd`, `silo_crack.gd`):
  * 1,000 Structure and 1,000 grain. Every 100 Structure lost opens a crack, up to 10 cracks.
  * A crack leaks 0.6 / 1.2 / 2.0 bushels per second as it grows. It grows after 3 and then 4 more hits near it.
  * **The leak runs during breaks too.**
  * Repairs take 1.2 / 2.1 / 2.4 s per stage. Each wave cleared adds 40 grain.
  * The silo has 16 crack sockets: 8 on the ground, 4 on each catwalk. Cracks open in the band that was hit 70% of the time, so lobbed and flying shots mostly crack the catwalks.
* **Robots** (`data/robots/archetypes/*.tres`, `robot.gd`, `robot_targeting.gd`, `vertical_robot.gd`):
  * Each robot rolls at spawn whether it goes for the silo or hunts the farmer.
  * While attacking the silo, a robot rolls each second to switch to the farmer if it was just hit or the farmer is near (or repairing). It gives up a chase after a set time or distance from the silo (chase time / leash).
  * Trios share one decision, and any Nibbler group can be a grain thief.
  * Roof Lobbers walk to the shed, barn, stables or chicken house, climb, and lob from the roof. Drones circle 22 m out at a height of 14 m.
  * The Foreman has 3× HP plus one random trait. Overcharged robots explode when they die.
* **Farmer and economy**:
  * The farmer has 100 HP. The porch heals 15 HP/s, the loot magnet reaches 3 m, and the Scrap Vac banks 50% of leftover parts when the next attack starts.
  * Every second wave cleared pays salvage (2 Cu, 1 Au, 1 PC). The Foreman bounty is banked when it dies.
  * Upgrade costs come from the CSV recipes, ×1.25 per level (for example, Swing Damage costs 12, 15, 19, 23 Al + 2 Cu, …).
  * A farmer KO, a silo at 0 Structure, or empty grain ends the run. Parts and upgrades carry over, and the next run restarts at wave 1.
* **Tutorial** (`LEVEL_0_MORNING_CHORES.md`, `tutorial_director.gd`): 6 Al buys the wrench, the dummy drops 5 Al and the bell pays 5 Al, so the first wave starts with 10 Al in pocket.

### What a wave looks like today (300 seeds each)

| Wave | Budget | Spawn window | Lanes | Robot HP | Robots (range) | Typical roster |
|---|---|---|---|---|---|---|
| 1 | 18 | 45 s | 2 | ×1.00 | 9 | 9 Nibblers |
| 2 | 27 | 52 s | 2 | ×1.07 | 10 (7–13) | 7 Nibblers, 3 Clankers |
| 3 | 37 | 59 s | 2 | ×1.15 | 14 (9–17) | 8 Nibblers, 3 Clankers, **3.5 Roof Lobbers** |
| 4 | 48 | 66 s | 2 | ×1.23 | 18 (13–21) | 10 Nibblers, 4 Clankers, 4.5 Roof Lobbers |
| **5** | **79** | 73 s | **3** | ×1.31 | **31 (24–36)** | 16 Nibblers, 6 Clankers, **8 Roof Lobbers, 1 Drone, the Foreman (1,574 HP)** |
| 6 | 74 | 80 s | 3 | ×1.40 | 26 (17–33) | adds Thumpers and a family trait |

---

## 2. The five simulations at a glance

| | **Sim 1** 5-min | **Sim 2** 10-min | **Sim 3** 15-min | **Sim 4** 25-min | **Sim 5** 30+ min |
|---|---|---|---|---|---|
| Testers like this | 5% | 44% | 32% | 13% | 6% |
| Skill (melee / best gun) | 71% / 30% | 76% / 42% | 79% / 48% | 83% / 52% | 87% / 56% |
| Time played | 5:00 | 10:00 | 15:00 | 25:00 | 34:00 |
| Runs (game overs) | 1 (0) | 1 (0) | 2 (1) | 2 (1) | 3 (2) |
| Waves cleared, total | 1 | 3 | 4 | 7 | 10 |
| Best wave cleared / reached | 1 / 1 | 3 / 3 | 3 / 4 | 4 / 4 | 4 / **5** |
| Phases completed | 0 | 0 | 0 | 0 | 0 |
| How runs ended | quit in the wave-2 break | quit at the wave-3 clear | grain ran out at wave 4; quit | grain ran out in the wave-4→5 break; quit mid wave 4 | silo destroyed at wave 5 (×2); quit |
| Robots destroyed | 9 | 34 | 37 | 103 | 149 |
| Distance on foot | 389 m | 1,018 m | 1,475 m | 2,470 m | 3,195 m |
| Average distance from silo wall in combat | 7.8 m | 9.7 m | 9.7 m | 9.6 m | 8.9 m |
| Wrench swings (hit %) | 24 (63%) | 72 (69%) | 65 (75%) | 140 (80%) | 152 (89%) |
| Pistol shots (hit %) | — | 121 (22%) | 113 (25%) | 289 (23%) | 284 (27%) |
| Shotgun shots (any pellet hit %) | — | — | — | 16 (75%) | 27 (63%) |
| Rifle shots (hit %) | — | — | — | — | 85 (49%) |
| Weapon usage (time on target) | wrench 100% | W 49 / P 51 | W 63 / P 37 | W 44 / P 48 / S 8 | W 37 / P 30 / S 10 / R 24 |
| Damage taken by farmer | 36 | 69 | 77 | 132 | 149 |
| Damage taken by silo | 6 | 445 | 744 | 1,861 | 2,542 |
| Cracks opened / repaired | 0 / 0 | 4 / 0 | 6 / 2 | 17 / 6 | 23 / 5 |
| Grain leaked / stolen | 0 / 0 | 230 / 0 | 1,020 / 80 | 1,796 / 60 | 2,060 / 0 |
| Parts gathered (Al / Cu / Au / PC) | 41 / 0 / 0 / 0 | 96 / 10 / 2 / 2 | 117 / 18 / 2 / 2 | 288 / 43 / 4 / 5 | 356 / 46 / 8 / 6 |
| Parts unspent at quit (Al / Cu / Au / PC) | 8 / 0 / 0 / 0 | 43 / 10 / 2 / 2 | 30 / 18 / 2 / 2 | 64 / 41 / 4 / 5 | 18 / 41 / 8 / 6 |
| Upgrades owned at quit | Swing Damage 2 | Swing Damage 2, Pistol | Swing Damage 3, Swing Speed 1, Pistol | Swing Damage 4, Swing Speed 2, Pistol, Pistol Damage 1, Pistol Rate 1, Shotgun, Shotgun Damage 1, Hearty Breakfast 1 | Sim 4's set plus Rifle, Rifle Damage 3 |
| Time on the pegboard | 71 s | 120 s | 345 s | 524 s | 810 s |

"Parts gathered" includes the tutorial's 16 Al, wave-clear salvage, and Scrap Vac recoveries. Kills by weapon in Sim 5: wrench 92, rifle 36, pistol 14, shotgun 7.

---

## 3. Simulation narratives

### Sim 1: the 5-minute quitter (5% of testers)

| Time | What happens |
|---|---|
| 0:00–3:09 | Morning Chores: picks up 6 Al, buys the wrench, bonks the dummy, heals on the porch, stops the practice Nibbler, sees the catwalk vista, rings the bell. About 260 m walked. |
| 3:12–3:59 | **Wave 1**: 9 Nibblers from two lanes, the first one roughly 15 s after the siren. Every kill is with the wrench (24 swings, 15 hits). The silo loses only 6 Structure. The farmer takes 36 damage from Nibblers that chased them, then ends the wave at 64 HP. Picks up 25 Al by hand. |
| 4:05 | Buys Swing Damage L1 and L2 (27 Al). A Nibbler is already a two-hit kill at 25 damage, so neither level changes a breakpoint. |
| 5:00 | Quits about 60 s into a 90 s break. **Time split: 63% tutorial, 20% break, 16% fighting.** |

### Sim 2: the 10-minute player (44% of testers, the most common)

| Time | What happens |
|---|---|
| 3:21–4:06 | Wave 1 cleared in 45 s, all with the wrench. The silo loses 12 Structure. |
| 4:12 | Swing Damage L1 and L2. |
| 5:38–6:44 | Wave 2: 7 Nibblers and 2 Clankers, cleared in 66 s. The Clankers do 50 silo damage while the farmer is busy with Nibblers. |
| 6:50 | Rivet Pistol (20 Al). |
| 8:17–10:00 | **Wave 3: Roof Lobbers.** Four lobbers climb roofs 17–44 m from the silo. The wrench can't reach them, so the player switches to the pistol: 121 shots, 27 hits (22%). The wave takes **103 s**. The lobbers do 221 silo damage and the Nibblers, left alone meanwhile, do 143 more. Structure falls 919 → 555, 4 cracks open (mostly on the catwalks), none are repaired, and grain falls to 771. |
| 10:00 | Quits as wave 3 clears, with 43 Al in pocket. |

The playtest data says testers prefer the wrench. In this session that preference ends at wave 3, when half of all time on target moves to the pistol, the weapon they hit 22% of the time with.

### Sim 3: the 15-minute player (32% of testers)

| Time | What happens |
|---|---|
| 2:44–6:06 | Waves 1–2 cleared, then Swing Damage 2 and the Pistol. |
| 7:31–9:20 | Wave 3 is cleared after 109 s, but the silo goes into the break at **310 Structure, 618 grain and 6 open cracks**. |
| 9:20–10:52 | During the break the farmer repairs 2 ground cracks (2.4 s of wrenching, +200 Structure) and spends 67 s on the pegboard. The 4 catwalk cracks are left alone and **leak 493 bushels in about 90 s**, even after the 40-grain harvest bonus. |
| 10:52–11:19 | Wave 4 starts with 165 grain. The grain runs out 28 s in, before a single robot reaches the silo. |
| 11:29–15:00 | Run 2: wave 1 cleared, then quits in the break. 4 thefts this session: 2 thieves escaped and 1 sack was recovered. |

### Sim 4: the 25-minute player (13% of testers)

* **Run 1 (0:00–13:51)** clears waves 1–4.
  * Wave 4 (20 robots, 108 s) ends at 234 Structure, 303 grain and 7 cracks.
  * The grain runs out **during the break before wave 5**, while the player is at the shed.
  * This is the death the player has the least control over: no robot is on the field.
* **The break after that death**: buys Pistol Damage, Swing Damage 4 and Pistol Rate.
* **Run 2 (14:01–25:00)**:
  * After the first death the player saves for the Barn Blaster (19:00). In the sim, 75% of shots land at least one pellet, but on average only 1.8 of the 7 pellets hit.
  * Reaches wave 4 again. Quits mid-wave with the silo at 105 Structure and 8 cracks.
* **Silo damage**: Nibblers 867, Roof Lobbers 823, Clankers 170.

### Sim 5: the 30+ minute player (6% of testers)

* **Run 1**:
  * Clears waves 1–4 and starts wave 5 at 604 Structure and 447 grain.
  * Wave 5 brings 28 robots from 3 lanes: 10 Clankers, 9 Nibblers, 7 Roof Lobbers, a Drone, and an Overcharged Foreman with 1,574 HP.
  * The silo is destroyed 56 s into the wave, before the Foreman has even walked in. Thumpers move at 2.5 m/s, so it needs about 48 s from its lane.
* **Run 2**:
  * Buys the **Longneck Rifle** after the first death (17:19), then Rifle Damage 1–3.
  * The rifle hits 49% of the time and gets 36 kills. It becomes the lobber answer.
  * Waves 1–4 are cleared again, and wave 4 costs the silo only 8 Structure.
  * Wave 5 brings 32 robots. The silo is destroyed after 77 s while the Foreman (a Thieving variant) is still alive.
* **Run 3**: the Barn Blaster is finally bought. Quits in the wave-3 break.
* **Economy**: 356 Al gathered and 338 spent. **41 Cu, 8 Au and 6 PC are never spent**, because every item the player wants is gated by Aluminium.

---

## 4. How long it takes to destroy each robot

Seconds of continuous attacking, at a tester's typical accuracy: 79% with the wrench, 45% best-case with guns. Walking and target switching are not included. Pistol and rifle times include reloads, and 12% of landed gun hits are weak-point (×2) hits. Regenerate the table with `python3 tools/playtest_sim/ttk_table.py`.

| Robot (wave) | HP | Wrench L0 | Wrench L4 (dmg + speed) | Pistol 10 m | Pistol 25 m | Pistol 10 m, Dmg L3 | Shotgun 6 m | Rifle 25 m | Rifle 45 m |
|---|---|---|---|---|---|---|---|---|---|
| Nibbler (w1) | 30 | **0.8 s** | 0.4 s | 2.6 s | 6.0 s | 1.9 s | 5.4 s | 2.4 s | 3.2 s |
| Clanker (w2) | 64 | **1.7 s** | 0.9 s | 5.7 s | 12.8 s | 4.2 s | 6.0 s | 5.1 s | 7.0 s |
| Roof Lobber (w3, on a roof) | 52 | can't reach | can't reach | 4.5 s | 10.3 s | 3.3 s | 9.2 s | **4.1 s** | **5.6 s** |
| Drone (w5, 14 m up) | 46 | can't reach | can't reach | 4.0 s | 9.1 s | 3.0 s | 8.2 s | 3.7 s | 5.0 s |
| **Foreman (w5)** | **1,574** | 43 s | 22 s | 139 s | 314 s | 102 s | 90 s | 126 s | 170 s |
| Thumper (w6) | 560 | 15 s | 7.8 s | 49 s | 112 s | 36 s | 32 s | 45 s | 61 s |
| Nibbler (w10) | 54 | 1.5 s | 0.7 s | 4.7 s | 10.7 s | 3.5 s | 9.6 s | 4.3 s | 5.8 s |

Average time from first hit to death inside the sims, including chasing and misses:

* Nibbler 1.0–1.8 s
* Clanker 1.3–2.6 s
* Roof Lobber 3–14 s (3 s once the rifle is bought)
* Drone 4.6 s

These tables explain the testers' preferences:

* **The wrench does 3–4× the damage per second of a pistol** at the distances these testers fight from. It is also the cheapest weapon to upgrade: Swing Damage starts at 12 Al.
* **The shotgun really is weak** against single robots. At 6 m, only about 1.35 of its 7 pellets hit a Nibbler-sized target, because the 11° outer ring is already 1.2 m wide at that distance. It fires once a second, so it kills a Nibbler slower than a pistol at 10 m. Testers saying it "doesn't hit the target" are reporting the geometry correctly.
* **The rifle's advantage is range, not damage**. At 25–45 m it is the only gun that still hits more than 25% of the time. That is exactly where Roof Lobbers on the barn and stables roofs sit.

---

## 5. 1,000-session cohort (your boredom distribution)

Skill, repair habits, and when the shotgun or rifle gets bought are randomised within your ranges. Quit times follow 5 / 44 / 32 / 13 / 6%.

| Quit bucket | Sessions | Avg minutes | Game overs | Waves cleared | Clear w3 | Clear w4 | Reach w5 | Clear w5 | Kills | Distance | Al / Cu / Au / PC | Upgrades |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 5 min | 51 | 5.4 | 0 | 1.1 | 0% | 0% | 0% | 0% | 11 | 499 m | 44 / 3 / 0.4 / 0.3 | 1.9 |
| 10 min | 439 | 10.1 | 0.19 | 2.5 | 47% | 0% | 0% | 0% | 30 | 967 m | 90 / 11 / 1.9 / 1.4 | 4.2 |
| 15 min | 310 | 15.9 | 0.98 | 4.0 | 79% | 15% | 5% | 0% | 50 | 1,522 m | 143 / 19 / 3.0 / 2.3 | 7.3 |
| 25 min | 133 | 23.6 | 1.66 | 6.2 | 93% | 20% | 8% | 0% | 78 | 2,232 m | 212 / 29 / 4.6 / 3.5 | 10.7 |
| 30+ min | 67 | 35.1 | 2.78 | 9.4 | 100% | 42% | 24% | 0% | 118 | 3,212 m | 311 / 44 / 7.2 / 5.7 | 14.9 |
| **All testers** | 1,000 | 15.1 | 0.79 | 3.8 | **64%** | **10%** | **4%** | **0%** | 48 | 1,434 m | 135 / 18 / 2.8 / 2.2 | 6.7 |

* **How runs end:**
  * 794 game overs: 57% grain ran out, 43% silo Structure hit 0, **0% farmer knocked out**.
  * **20% of game overs happened during a break**, with no robots on the field.
* **Where runs end:** wave 3 (29% of game overs), wave 4 (43%), during breaks (20%) and wave 5 (5%). Wave 5 is mostly a wall that runs never reach.
* **Where the time goes** (average of all testers):

  | Activity | Share of session |
  |---|---|
  | Tutorial | 20% |
  | **Breaks** | **41%** |
  | Attack + mop-up | 35% |
  | Siren, cleared hold, game-over screen | 3% |

  A 10-minute tester sees about 3 minutes of combat.
* **Inside combat**, the most common thing the farmer does is circle the silo with nothing in reach. The robots have to walk 110 m from the lanes.
* **Gun accuracy**: the cohort's pistol hit rate averages **25%**, the rifle 33%, and the wrench 79%. These sit inside your measured ranges.
* **Weapon mix** (cohort): wrench 68%, pistol 30%, shotgun 1.6%, rifle 0.2%. Your testers: 55 / 28 / 8 / 9. The wrench and pistol shares match. The shotgun and rifle shares are about 5× and 45× lower in the model, because very few simulated testers can afford them inside one session. If your testers were returning to a profile that already owned them (`SaveManager` keeps parts and upgrades between sessions), that would close the gap.

### What-if: the same testers, but they repair

400 sessions per row. Only the repair habit changes.

| Repair habit | Reach w5 | Clear w4 | Clear w5 | Grain game overs | Lost during a break | Grain leaked per session |
|---|---|---|---|---|---|---|
| As observed (20–45% of ground cracks in breaks) | 3% | 10% | 0% | 162 | 54 | 789 |
| Every ground crack, every break | 10% | 18% | 0% | 107 | 29 | 633 |
| Every crack, catwalks included | **20%** | **26%** | **0%** | 56 | 15 | 523 |

Repairing is the biggest lever a player has. It raises the share of players who see the Foreman from 3% to 10–20%. It doesn't get anyone through wave 5. A best-case player (88% melee, 57% guns, repairs every crack, 60 minutes, ending with Swing Damage 6–7, Rifle Damage 3 and Pistol Damage 3–5) still lost **10 of 10** wave-5 attempts across three seeds, each within 67–108 s:

* They had killed 15–23 of the 29–33 robots when the silo fell.
* The Foreman was never killed.
* The silo damage per attempt came from all sides: Roof Lobbers 200–500, Clankers 70–550, the Foreman 70–280 and Nibblers 65–390.

---

## 6. Findings

1. **Wave 3 is the first wall, and the Roof Lobber causes it.** Three to five lobbers per wave climb roofs 17–44 m from the silo, where the wrench can't reach and your testers' pistol accuracy is 4–25%.
   * A lobber takes 10 s of pistol fire from the ring, against under 2 s for anything the wrench can hit.
   * Waves 3–4 take 75–110 s, against 45–66 s for waves 1–2, and the silo often loses 300–700 Structure in one of them.
   * Your plan for wave 3 ("Take the High Ground") is aimed at the right problem.
2. **Grain leaking through breaks is the top cause of game overs.** Lobbed and flying shots crack the catwalks 70% of the time, and these testers almost never climb to fix them.
   * Four Large cracks drain 8 bushels a second, so 720 bushels are gone before the next siren.
   * Game overs where the grain empties during the break, with no robot on the field, are 20% of all game overs. A player who is avoiding hits may not even see them coming.
   * Options: pause or halve leaks between waves; highlight catwalk cracks during the break; or let the 40-grain Harvest Bonus also repair one crack.
3. **Wave 5 is a cliff, not a step.**
   * The robot count jumps by 71% (18 → 31) and a third lane appears.
   * About 8 Roof Lobbers arrive, along with the first Drone and a 1,574 HP Foreman (2,204 HP when it rolls Armored).
   * That Foreman takes 43 s of uninterrupted wrench contact, which a player who backs away when chased never gets.
   * No simulated player cleared it. This agrees with the P0/P1 items in [the first five waves plan](FIRST_FIVE_WAVES_FUN_PLAN.md): a 700 HP authored Foreman, no drone, no lobbers.
4. **Too little of a session is combat.** 41% of a session is spent in breaks and 20% in the tutorial. The 90 s break is still 3× the GDD's 30 s target (ROADMAP D1). With 67 s of shopping inside each break, a 10-minute tester gets about 3 minutes of fighting across 2–3 waves. That lines up with the 44% who quit at 10 minutes.
5. **"No other melee items could be obtained" is a data issue, not grinding.**
   * Haymaker Maul, Harvest Scythe and Boiler Grenades are **commented out** in [`data/source/upgrades/attack.csv`](../data/source/upgrades/attack.csv) (lines 14–18). No `.tres` was generated for them, so the pegboard has no peg for them.
   * Their weapon resources (`data/weapons/maul.tres`, `scythe.tres`, `grenade.tres`) exist, and the Maul would cost only 30 Al.
   * No number of deaths would have unlocked them.
6. **Aluminium is the only currency that matters for 30 minutes.** Copper, Gold and Power Cells pile up unspent: the 30+ minute cohort ends holding 39 Cu on average. Swing Damage doesn't need Gold until L7 or Power Cells until L9, and no simulated tester got past Swing Damage L7. Rare parts don't yet feel like a reward.
7. **The farmer almost never dies.** Testers who back away and dodge take 20–180 damage per session and lose essentially no runs to KOs. The danger falls on the silo. That matches "prioritises not getting hit", and it means the tension lives in a meter the player isn't watching.
8. **The shotgun complaint checks out against the math** (section 4). At the 5–10 m distances these testers fight from, it lands 1–2 pellets per shot. Damage upgrades won't fix that. A tighter inner ring or a bigger pellet hitbox would.

## 7. Limits of the model

* **Movement**: robots walk straight lines at 92% speed, as a stand-in for the navmesh. They don't jam around the silo or each other. Camera, occlusion and target-finding problems are not modelled, so real players are probably slower to find targets than these.
* **Combat assumptions** (flagged `ASSUMPTION` in the code):
  * 30–45% of telegraphed attacks land on a careful player.
  * 12% of landed gun hits are weak-point hits.
  * Humans tap a semi-auto at most about 3.3 times a second.
  * The tutorial takes about 3 minutes and 260 m.
* **Rules left out**: clanker bolts, Thumper clod throws and Spitter relocation are not modelled. Only waves 1–5 matter for these testers, and those rules start at wave 7.
* **Checks**: wave composition was checked against the director's own rules. The schedules in `docs/audit-evidence` were made from older robot data and show more Clankers than today's tables produce.
* **Results** are in `tools/playtest_sim/results.json`, `cohort_summary.json` and `sensitivity.json`. Re-run them after any tuning change. The simulator reads nothing from Godot, so edit `game_data.py` alongside the `.tres` and `.csv` files.
