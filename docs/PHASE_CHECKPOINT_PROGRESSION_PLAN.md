# Robot Attack! — three-wave phases and phase checkpoints

October 25, 2026. Proposed design, based on the working tree at HEAD `23b8683` and its uncommitted changes. It changes GDD 2.4, 10.3, 11.2, 11.6 and 14.2, and the [first five waves plan](FIRST_FIVE_WAVES_FUN_PLAN.md)'s wave numbers. None of those documents are edited yet.

**Status, October 26, 2026: steps 1–5 and 7 are built, step 6 in part, step 8 not yet.** Decisions P-D1 to P-D6 were adopted as recommended; [ROADMAP](ROADMAP.md) section 4.13 (PS-1, PS-2) lists the work. Built: one phase length on the curve, with Big Hauls on 3, 6, 9, …; the re-keyed schedule, with a unit test that every threshold except the two lane twists lands on a phase's first wave; Retry Phase and Start over on the Harvest Report (which names the phase, wave and attempt lost) and in the pause menu, which also offers Continue at the furthest phase; `resume_wave`, attempts per phase and save schema v2, where a v1 profile resumes at the start of the phase it would play next; a new seed per attempt; a no-retry Full Harvest; Early Bird above the best wave only; the jetpack as a wave-9 milestone; time of day counted from wave 1; and the six-wave authored opening (step 4). The GDD, README and roadmap are updated (step 7).

Of step 6, only the drops are built: 2 PC + 1 Au, paid on the first kill of each Foreman wave per profile. The Longneck and Blimp don't exist yet, so every Foreman is still the Thumper (M2-B14). Two changes to the schedule above: the Rung Runner, a silo-ladder climber from the [defense proposal](DEFENSE_BUILDING_AND_COMBAT_PROGRESSION_PROPOSAL.md), debuts on wave 5, phase 2's twist, as climbing under pressure after wave 4's Lobber lesson, so wave 5 has one Lobber and two Rung Runners instead of three Lobbers. And generated waves 7–9 ramp their budget (×0.7, ×0.8, ×0.85), because the economy probe showed a jump from about 15 robots in the authored wave 6 to 33 in a generated wave 7. Not built: the optional Clean Phase bonus, the Hub's checkpoint list (M2-H3), battle plans (M2-B11), and the step 8 playtest.

**Losing should cost minutes, not the whole climb.** Today any loss (farmer down, silo destroyed, grain gone) reloads the scene at wave 1, phase 1, with every upgrade kept. A geared-up player then spends 10–20 minutes replaying waves they can no longer lose. This plan makes two changes:

1. **A phase is 3 waves, not 5.** The third wave of each phase is the Big Haul, with the Foreman.
2. **A loss sends you back to wave 1 of the phase you were in.** You keep your parts, upgrades and unlocks, the silo and grain start full, and the next intermission begins. At most you replay two waves before you're back where you lost.

Shorter phases change when every threat shows up. The rule below keeps each new thing early in a phase, so a retry always shows you the lesson again before the test.

## What the code does today

| Piece | Where | Today |
|---|---|---|
| Phase length | `GameState.WAVES_PER_PHASE` (5) **and** `DifficultyCurve.waves_per_phase` (5) | Two copies of the same number. The HUD and time of day read the first, Big Haul reads the second |
| Big Haul | `DifficultyCurve.is_big_haul` | `wave % 5 == 0`: budget ×1.3, Foreman (always the Thumper) |
| Game over → restart | `hud.gd` `_unhandled_input` | `reload_current_scene()`; `WaveDirector.start_run` always calls `_set_wave(1)` |
| Checkpoint hooks | `GameState.start_wave`, `SaveManager._record_run`, `EnvironmentTable.preset_index` | `start_wave` exists and is read, but nothing ever sets it above 1 |
| Robot debuts | archetype CSVs (`unlock_wave`) | Nibbler 1, Clanker 2, Roof Lobber 3, Drone 5, Thumper 6, Spitter 7 |
| Wave-number rules | `difficulty_curve.gd`, `wave_director.gd` | Opening ends at 5; arm guard 6; throws and Spitters 7; aim lead 10; mid phase 16; volleys 16 / 24; late phase 31; traits 0/1/2/3 at 5/15/30; lanes step at 5/15/30; drone cap rises at 8; rooftop cap 3 at wave 4; heavy cap +1 every 8 from 6 |
| Jetpack gate | `stat_service.gd:79`, `pegboard_ui.gd:293/392/406` | `GameState.wave < 3` blocks the purchase; 40 Al + 15 Cu |
| Build-choice prompt | `hud.gd:141` | Shown at the intermission before wave 2 |

The phase count of a wave is used in three places: the HUD's "PHASE n · WAVE n", the Harvest Report, and the time-of-day step. All three go through `GameState.phase_of` and `wave_in_phase`.

## The rule for introductions: Lesson → Twist → Big Haul

Every phase has the same shape.

| Phase wave | Role | What may be new |
|---|---|---|
| 1 — **Lesson** | Meet the phase's new thing in a gentle, readable form | At most **one** new robot or player ability, with an authored first appearance |
| 2 — **Twist** | Use it under pressure | More of the new thing, or one map-pressure change (a lane, a battle plan, a behavior on a robot you already know) |
| 3 — **Big Haul** | The exam | **Nothing new** except the Foreman. Budget ×1.3 |

Why this shape:

- **A retry always replays the lesson.** If wave 3 of a phase beats you, wave 1 shows the threat again in its easy form.
- **A Big Haul never surprises you.** You lose to something you've already met twice.
- **Every scaling step starts on a phase's first wave** (waves 1, 4, 7, 10, 13, 16, …; `wave % 3 == 1`). A phase never changes its rules halfway through, so each retry plays by the same rules. Two of today's thresholds already line up (mid phase at 16, late phase at 31) and so does the aim lead at 10.
- **The first time is special, later times aren't.** A debut's caption, slow-motion beat and "new robot" card show once per profile (a `seen_intros` list in the save). The authored spawn layout stays on every retry, so the lesson still works.

## The new schedule

Wave numbers are absolute. Phase *p* covers waves 3*p*−2 to 3*p*.

| Phase | Waves | Theme | Lesson (wave 1) | Twist (wave 2) | Big Haul (wave 3) | Reward on clearing the phase |
|---|---|---|---|---|---|---|
| 1 | 1–3 | **Ground basics** | Nibblers, wrench only (today's wave 1) | Clanker trio, the pistol and the teaching thief (today's wave 2) | **First Foreman:** Thumper, authored, fixed behavior, no trait. 6 Nibblers + 1 Clanker trio as adds | The free **Barn Blaster or Haymaker Maul** choice moves to *after wave 2*, so you take a new tool into the first boss. Clearing the Foreman pays its guaranteed drop |
| 2 | 4–6 | **Climbers** | Roof Lobber debut: exactly one, on a designated roof with a readable ladder route (today's wave 3 lesson) | Rooftop wave (up to 3 Lobbers) and a **third lane** that opens late in the wave (today's wave 4) | Thumper Foreman with the clod-throw phase at 50% HP (M2-B14's "ranged phase from the second Foreman"), plus one Lobber add | End of the authored opening |
| 3 | 7–9 | **Drones** | Drone debut: one, circling the silo at a readable height. Families start rolling **1 trait** | Two Drones; regular **Thumpers** join (heavy cap 1); battle plans start (M2-B11) | Thumper Foreman with a random trait; at most 2 Drones as adds | **Jetpack blueprint:** the jetpack becomes buildable at the shed |
| 4 | 10–12 | **Take to the air** | No new robot. First-flight beat, if the jetpack is built (see below). **Aim lead** on straight shots starts (already 10) | Sky Raid plan (Drones and Lobbers) that flight answers best. Drone cap 3 | **Longneck Foreman** debut (B12). Until it's built, the Thumper | — |
| 5 | 13–15 | **The robots fight back** | **Spitters**, the Clanker **arm guard** and melee **throws at an out-of-reach farmer** (B9). They all answer roof camping and hovering, so they teach one lesson | **Fourth lane** | **Blimp Foreman** (B13). Until then, the Longneck | — |
| 6+ | 16+ | **Endless** | Mid phase from 16 (tokens 4, charge ×0.8, volley 2); families roll **2 traits** | Battle plans | Foreman rotates melee → ranged → flight, one per phase | — |
| 9 | 25–27 | | **Volley 3** (moved from 24, a Big Haul) | | | |
| 11 | 31–33 | | Late phase (tokens 5, charge ×0.7); **3 traits**; **fifth lane** (moved from 30); two battle plans stack (B11, today 31) | | | |

### What this changes for each named threat

**Climbers (Roof Lobber): wave 3 → wave 4.** Phase 1 stays on the ground, so the first boss gets the player's full attention. The Lobber's debut is the first lesson of phase 2, and today's two-wave Lobber arc (lesson on 3, rooftop-heavy on 4) moves as a whole to 4 and 5. The third lane stays at wave 5, which is now phase 2's twist: it opens late in the wave while one main lane rests. That matches the opening plan's "teach the third direction before the Foreman." The ladder, catwalk and zipline routes that Level 0 teaches are the answer, with no jetpack needed (opening plan, jetpack plan).

**Drones: wave 5 → wave 7.** The opening plan already asked to postpone Drones out of the first Foreman wave. Now they get a whole phase. The player meets one from the ground and roofs, then several, then as boss adds, all before flight is on offer. When the jetpack arrives in phase 4 it's a new answer to a known threat, not a fix for a confusing one.

**Jetpack: purchasable from wave 3 → blueprint for clearing wave 9, built in phase 4.** The [jetpack plan](JETPACK_GAMEPLAY_AND_REWARD_PLAN.md) withdrew the early unlock and asked for "a later defended milestone" without choosing a wave. With three-wave phases there's a clean milestone: **beating the phase 3 Big Haul**, the first one with Drones. That's 9 waves and three Foremen, roughly the effort of the old wave 10–15. It sits right before phase 4, whose twist is built for flight.

- The gate becomes a profile milestone, not the in-run wave: "phase 3 cleared" (`records.best_wave >= 9`). Today's checks against `GameState.wave < 3` in four places collapse into one `StatService` function. Then a later run started from phase 1 still lets you build it, and a phase 4 retry doesn't need to re-earn it.
- The price stays 40 Al + 15 Cu for now. The jetpack plan's component steps and final price come from its own prototype (its stage 4). This plan only fixes **when** it unlocks.
- Profiles that already own the jetpack keep it (unchanged "kept forever" rule).

## The retry flow

| Moment | Behavior |
|---|---|
| Loss (any of the three reasons) | Harvest Report as today, plus "Lost at **Phase 4 · Wave 3**". The main prompt is **Retry Phase 4** (R / Enter / Jump). A second option, **Start over at Phase 1** (hold R, or a second button), keeps today's behavior for players who want a Full Harvest |
| Retry | Scene reload, as today. `main.gd` reads `SaveManager.resume_wave` and calls `WaveDirector.start_run(resume_wave)` with `GameState.start_wave = resume_wave`. Silo, grain, lanes and robots start fresh; parts, upgrades and unlocks are untouched (they're already banked) |
| Seed | **A new run seed per attempt.** You get a fresh family, fresh lanes and a fresh spawn mix, so a retry feels different. The authored waves (1–6) keep their authored structure, with only cosmetics and constrained lane picks seeded, as the opening plan specifies |
| Clearing a Big Haul | `resume_wave` moves to the next phase's first wave and is saved at that intermission (the autosave already runs there) |
| Quitting the game | `resume_wave` is in the profile, so relaunching continues at the start of that phase. The Hub (M2-H3) shows **Continue: Phase N** and **Start at Phase 1**, plus GDD 14.2's list of earlier phase starts |
| Level 0 | Never replayed by a retry. Losing in phase 1 retries from wave 1's intermission |

### Records and score

- **Best wave** stays "the highest wave cleared", across retries. Score still shows as Phase.Wave (Phase 4 · Wave 3 = 12 waves).
- **Full Harvest** becomes "from wave 1 with no retries". It's already keyed on `start_wave <= 1`, and a retry sets `start_wave` above 1 from phase 2 on. A phase 1 retry needs a `retried` flag so it doesn't count.
- **New records:** retries per phase (best and latest), shown on the Harvest Report ("Phase 4, attempt 2"). Optionally, a small **Clean Phase** Gold bonus for clearing a Big Haul on the first attempt, so playing well still pays more than dying and replaying.

### Exploits a cheap retry opens

- **Early Bird farming.** Each attempt opens on a fresh intermission, so ringing the bell pays again. Adopt the opening plan's fixed 5-Al ready bonus, and pay it only for waves above `records.best_wave`.
- **Parts from a lost attempt are kept.** That's intended ("keep all the gear") and makes a loss feel productive. Drop value scales with the wave (`drop_multiplier`), so the best place to farm is the hardest wave you can reach, which is just playing the game.
- **Foreman drops** are guaranteed (3 Power Cells + 2 Gold). A phase 1 retry loop is three waves long, so that's a short path to the boss and its drop. Pay the guaranteed drop on the first kill of each Foreman wave per profile only, and fall back to the normal Heavy drop table on repeats.

## Knock-on changes

**Economy.** A Big Haul every 3 waves instead of every 5 adds about 4% to the average threat budget (×1.10 per wave on average instead of ×1.06) and gives 67% more Foremen. Per wave, guaranteed Power Cells go from 0.6 to 1.0 and Gold from 0.4 to 0.67. Start with a Foreman drop of **2 Power Cells + 1 Gold** (0.67 PC and 0.33 Au per wave, close to today's 0.6 and 0.4). Then check the GDD 12.5 targets with the M2-G2 economy simulator and the first playtest.

**Difficulty per wave stays the same.** HP, damage, budget and spawn windows stay functions of the absolute wave. Phase 4 is now waves 10–12, which is easier than the old phase 4 (waves 16–20). The phase number grows faster, but the challenge per wave doesn't. The soft ceiling (a maxed player stalls around wave 45–60) moves from phase 9–12 to phase 15–20.

**Foreman HP.** The first Foreman now arrives at wave 3 (hp ×1.15 instead of ×1.30). The authored first Foreman should still use the opening plan's 700 HP target (600–800), tuned with a wrench, a pistol and the free tool. Bosses every third wave can wear players out in the endless phases. Watch Foreman engagement time in playtests. If it drags, scale the 3× HP multiplier down to about 2.5× from phase 6 on.

**Time of day** steps once per phase, so a full day cycle now takes 18 waves instead of 30. That gives more variety, and nothing else depends on it. Count steps from wave 1 instead of from `start_wave` (`preset_index(start, wave, 1)`), so a phase 5 retry opens at phase 5's time of day instead of resetting to the run's first preset.

**Lanes** go 2 (waves 1–4) → 3 (from wave 5) → 4 (from 14) → 5 (from 31). Lane thresholds become `[5, 14, 31]`. The third and fourth lanes are deliberate twist-wave exceptions to "steps start on a phase's first wave". Each is an announced late-wave raid, the twist's job.

## Implementation steps

Each step leaves the game playable and the tests green.

| # | Step | Files | Done when |
|---|---|---|---|
| 1 | **One phase length.** Delete `GameState.WAVES_PER_PHASE`; `phase_of`, `wave_in_phase` and a new `phase_first_wave(wave)` read `DifficultyCurve.waves_per_phase`. Set it to 3 in `default_difficulty.tres` | `game_state.gd`, `difficulty_curve.gd`, `environment_table.gd`, `hud.gd`, the data file | Big Hauls fall on 3, 6, 9; the HUD shows PHASE 2 · WAVE 1 at wave 4; unit tests for the helpers |
| 2 | **Retry from the phase start.** `SaveManager.resume_wave` (defaults to 1; a v1 profile gets the first wave of the phase after its `best_wave`), `seen_intros` and per-phase retry records. `WaveDirector.start_run(tutorial, start_wave)`. Harvest Report and input: Retry and Start over. Pause menu: Restart phase and Restart at phase 1. Full Harvest and Early Bird rules | `save_manager.gd`, `main.gd`, `wave_director.gd`, `hud.gd`, `pause_menu.gd`, `game_state.gd` | Losing at wave 8 restarts at wave 7's intermission with parts and upgrades intact. Relaunching resumes there. A v1 profile migrates (test). A smoke test forces a loss and checks the restart wave |
| 3 | **Re-key the schedule.** Archetype CSVs: Roof Lobber 4, Drone 7, Thumper 8, Spitter 13 (then run `build_robot_data.gd`). `DifficultyCurve`: `opening_last_wave` 6, `arm_guard_first_wave` 13, `unreachable_throw_first_wave` 13, `spitter_first_wave` 13, `volley_three_wave` 25, `lane_thresholds` [5, 14, 31], `trait_count` at 7/16/31. `WaveDirector`: rooftop cap 3 on wave 5, drone cap 1 on its debut wave, then 2 for the rest of phase 3, then 3 from wave 10; heavy cap steps on phase starts | CSVs, generated `.tres`, `difficulty_curve.gd`, `wave_director.gd` | A unit test lists every threshold and checks that each one, except the lane twists, lands on `wave % 3 == 1`. Wave-buying tests over 1,000 seeds: no Lobber before 4, no Drone before 7, no Spitter before 13 |
| 4 | **Six-wave authored opening.** Rework the opening plan's table onto waves 1–6 as above. The free Blaster or Maul choice moves to the intermission after wave 2 (`hud.gd:141`'s prompt moves with it). Debut captions read `seen_intros` | `wave_director.gd` (authored waves), `hud.gd`, the opening plan doc | Waves 1–6 follow the table on every seed; a retry of wave 4 reuses the Lobber's authored roof but shows no caption |
| 5 | **Jetpack milestone.** `StatService.jetpack_available()` = `records.best_wave >= 9`, used by the purchase check and the three pegboard checks; a reward card on clearing wave 9 | `stat_service.gd`, `pegboard_ui.gd`, `hud.gd` | It can't be bought before wave 9 has ever been cleared, and can be bought in a later phase 1 run once it has (tests) |
| 6 | **Foreman rotation and drops** (folds into M2-B14). Thumper at 3/6/9, Longneck from 12, Blimp from 15, then by phase. 2 PC + 1 Au, guaranteed only on the first kill of each Foreman wave per profile | `wave_director.gd`, `robot.gd`, Foreman data | Waves 3, 6, 9, 12, 15 spawn the right Foreman; drop test |
| 7 | **Docs.** GDD 2.4, 10.3, 11.2, 11.6, 14.2, the glossary and Appendix A; README's debut waves and jetpack line (already out of date: it says Lobbers 4, Drones 6); ROADMAP entries B4, B5, B10, B11, B14, H3 and the D-decision log; a superseded note on the opening plan | docs | No document gives a 5-wave phase or the old debut waves |
| 8 | **Playtest check.** Economy simulator run; 3 people × 3 runs that include at least one loss. Questions: does a retry feel quick? Does each phase's lesson read? Is the wave-3 Foreman fair with the starter kit? | — | Retry-to-action under 2 minutes; no phase where most losses happen on the lesson wave |

Steps 1 and 2 can ship on their own: three-wave phases with retries work on the current debut waves, though Drones would then debut on wave 5, the twist of phase 2, until step 3 lands. Step 3 touches `wave_director.gd` like the opening plan's authored waves and M2-B11, so do it in the same session as step 4.

## Decisions (recommendations adopted unless you say otherwise)

| # | Question | Recommendation |
|---|---|---|
| P-D1 | Is the third wave of every phase a Big Haul, including wave 3? | **Yes.** A uniform rule is easy to learn, and wave 3 gets the authored, gentler first Foreman |
| P-D2 | Same seed or a new seed on retry? | **New seed.** A fresh family and lanes keep retries from feeling like a rerun. The authored opening stays authored |
| P-D3 | Does a lost attempt keep the parts collected in it? | **Yes**, they're banked when collected. Guaranteed Foreman drops and Early Bird pay only the first time |
| P-D4 | Where does the jetpack unlock? | **Blueprint for clearing wave 9** (phase 3 Big Haul, the first with Drones), buildable from phase 4. The price is still the jetpack plan's call |
| P-D5 | Keep "Start over at Phase 1"? | **Yes**, as the second option. It's the only way to set a Full Harvest record |
| P-D6 | Per-wave difficulty stays the same, or the curve is squeezed to match the shorter phases? | **Stays the same.** The shorter phase is about how much you replay, not about making it harder sooner |
