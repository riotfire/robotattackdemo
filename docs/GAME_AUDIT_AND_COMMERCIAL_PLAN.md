**Robot Attack! — product audit and commercial plan**

Prepared October 18, 2026; expanded with the sharing, score-comparison, and build-sharing strategy. Working-tree inspection, native visual inspection, automated tests, a short graphical probe, and primary-source market research. Repository HEAD at the end of inspection: `8832272`. This is a proposed strategy; it does not replace the accepted GDD or roadmap decisions automatically.

**The opportunity is a recognizable action game about a handmade farm, a ridiculous jetpack, and robots stealing your harvest.** The existing prototype supports that fantasy. It has seeded encounters, persistent upgrades, a vertical arena, repair pressure, readable enemy roles, and useful automated coverage. Those are assets worth preserving.

The present build does not yet demonstrate bestseller-level combat, retention, presentation, or demand. The best next investment is a polished, testable 10–15 minute experience that proves the fantasy. Expanding to roughly 350 upgrade levels, twelve robot themes, and nine archetypes before that proof would multiply production and balancing costs without establishing why players buy or recommend the game.

My recommended positioning is: **“Strap on a milk-can jetpack. Turn greedy robots into spare parts. Save the harvest.”** Lead with movement, comic destruction, and a farm worth protecting. Use “cozy” to describe the setting carefully: the actual game has aiming, urgency, and three failure conditions, which can disappoint buyers expecting a relaxed farming simulator.

**What was actually verified.** I inspected the GDD, roadmap, scenes, shaders, player/camera/weapons, AI, spawning, pickups, saves, UI, and content generators. I launched the game with a disposable profile and inspected its opening and active-wave presentation. This was a limited visual/control inspection, not a representative human playtest or controller usability study. No player retention, sales, audience, or store analytics were available.

| Evidence | Result | Interpretation |
|---|---|---|
| GUT unit suite | 34/34 tests, 1,894 assertions pass | Useful formula and integration coverage; does not establish fun or shipping stability |
| Smoke test, seed 42 | 93 checks pass | Current happy path works |
| Smoke test, seed 1234 | 38 failures among 82 executed checks | Reproduces the known failure; failures cascade after the first wave |
| Seed 1234 navigation checks | All eight lane paths pass | Do not assume the failure is a broken navmesh |
| Seed 1234 later state | Silo Structure is zero; run ends for silo loss | Strong evidence that the test fixture allows objective destruction before later scenarios; instrument the first failure before changing AI |
| Seed 42 economy | 14 Aluminium banked at wave-one completion | This scripted path cannot afford the 20-Al pistol; not a measurement of average human earnings |
| Native visuals | Recognizable farm and material experiments; capsule farmer and very small HUD | Environment work is ahead of character presentation and interface polish |
| Audio inspection | No gameplay audio implementation/assets found | Combat and threat feedback cannot yet be evaluated as a finished experience |

The first unit-test attempt could not write sandboxed temporary saves. The passing rerun had that filesystem access. That initial failure is an environment issue, not a save-system defect. Logs and the diagnostic scene are in `docs/audit-evidence/`.

**The first priority is repairing the opening and economy.** A new player currently begins with a wrench, zero currency, and a 120-second intermission. The defining jetpack arrives only after wave two. Optional bell use can shorten this, but the player must discover it. The game is asking players to wait before showing its strongest promise.

There is also a large bell-reward imbalance. `wave_director.gd:349` pays skipped seconds immediately, multiplied by `1 + wave / 10`. At the initial 120 seconds, its theoretical wave-one maximum is `(120 − 10) × 1.1 = 121 Al`; walking to the bell reduces that. The native debug-bell inspection awarded 101 Al after some elapsed time. Both dwarf the pistol price and the scripted wave-one earnings. The bell is a normal gameplay interaction; the debug key merely invokes it. At a 30-second intermission, the maximum becomes 22 Al, so changing the timer also changes the economy dramatically.

Make the first weapon and traversal unlock guaranteed tutorial rewards. Pay a small, capped Early Bird reward only after clearing the wave, and make it independent of the player's relaxed-timer setting. Simulate waiting, rushing, losing immediately, buying before defeat, and restarting so the optimal progression strategy is playing well. Review whether permanent parts should bank immediately, at milestones, or on run end; communicate the chosen rule clearly. Do not remove earned progress merely to manufacture tension.

| First-session time | Proposed experience | What it proves |
|---|---|---|
| 0–20 seconds | Player control immediately; clear silo objective and one nearby bot to bonk | Basic movement and hit feedback |
| 20–60 seconds | Guaranteed rivet pistol; satisfying weak-point kill; first grain thief | Shooting, reward, and purpose |
| 60–120 seconds | Introduce or loan the jetpack; recover the sack via a rooftop shortcut | The unique movement fantasy |
| 2–5 minutes | Two attack directions, one repair decision, one meaningful upgrade choice | The main tactical loop |
| 5–10 minutes | Telegraph a heavy, create a recoverable emergency, introduce a build combination | Escalation and skill expression |
| 10–15 minutes | A distinctive Foreman encounter and clear victory/reward | A complete demo arc and desire to replay |

These times are prototype targets. Test this accelerated opening against the current wrench-first progression; retain the version that improves comprehension and voluntary replay. Once an untimed hub and quick-buy flow exist, use a short intermission with a relaxed option, as the existing D1 decision already intends. Give players useful repairs and purchases during pauses rather than mandatory waiting.

**Combat needs a hierarchy of feedback and decisions.** The current pistol delivers 12 damage at four semi-automatic shots per second; the Nibbler has 30 HP and runs at 8 m/s against the farmer's 7 m/s. The wrench does 25 damage. These create understandable early breakpoints: three body shots, two eye hits if the 2× weak-point multiplier applies, or two basic wrench hits. Preserve legible breakpoints while tuning actual feel. The speed difference makes chasing a thief from behind unfavorable; show interception routes and give players an early mobility answer.

Improve the pistol before adding four more guns: crisp muzzle animation, recoil and recovery, distinct body/weak-point hit cues, directional robot flinch, satisfying death breakup, immediate audio, and optional subtle haptics. Offer hold-to-fire accessibility while preserving the designed rate. Keep camera and input responsive while stepping cosmetic poses. World-wide hitstop would be risky in co-op; prefer brief local animation emphasis and audio accents.

Give each weapon a distinct tactical job. Prototype three coherent build styles before filling the catalog:

| Build | Example interaction to prototype | Necessary tradeoff |
|---|---|---|
| Rooftop mechanic | Airborne weak-point hits sustain short jetpack bursts | Precision and fuel management; poor sustained crowd clear |
| Scrap wrangler | Magnetic pull clusters bots for a wrench finisher | Strong close-range control; exposure to heavy attacks |
| Harvest engineer | A decoy draws attackers through an electrified repair zone | Setup and resource commitment; less personal burst damage |

These are new design proposals, not existing capabilities. Start with approximately twelve behavior-changing modifiers and three viable builds. Measure pick rates and win rates by skill and unlock state. A less popular choice is not automatically weak; establish whether its role is understood. Keep percentage upgrades only when their effect is visible in combat, and make loadout respec easy.

**Repair should be an interesting emergency, not a recurring chore.** The current silo has Structure, grain, leakage, and cracks at multiple heights, while the player also has health. That can create good triage, but the failure chain needs to be readable. Show the immediate cause of grain loss, point toward the worst leak, distinguish thieves from direct attackers, and explain the cause of defeat on the results screen. Use spatial sound and icons together.

Prototype a short repair burst that seals a leak, with fuller restoration available during intermission. Compare it to the current five-second repair of a 100-Structure crack at 20 per second. Reward a well-timed repair under pressure without making players hold a button for a large share of every wave. Test whether upper cracks before the jetpack unlock create interesting ladder decisions or simply punish beginners. Teach each failure condition separately before combining them.

**The farm should create tactical routes, and runs need an ending players can pursue.** Keep the silo as the unmistakable anchor. Build three intentional loops: close-range ground defense, fast roof-to-roof interception, and a risky outer salvage route. Every traversal feature should provide a useful angle, shortcut, escape, or reward. Measure travel time from the silo to each active lane and repair socket; avoid distant errands while damage happens off camera.

Use seeded variation to alter decisions: a blocked shortcut, a relocated resource cache, or a different enemy entrance. Scattering more crates has limited replay value unless routes change meaningfully. Reserve guaranteed clear corridors and validate route accessibility after scattering. A flying camera can see over buildings, so do not count on occlusion alone to solve rendering cost.

Prototype a 20–30 minute “Harvest Contract” with a final boss and an optional endless extension. Keep endless as a mastery mode. A finite objective gives ordinary buyers a victory, creators an understandable episode, and the team a tractable balance target. Compare this against endless-only sessions before revising the GDD. Add suspend/resume so a long run is not lost to an interruption.

Enemy variety should come from behavior before palette count. The current three melee roles are a good base: thief, coordinated attacker, and heavy shockwave. Next add one ranged enemy that makes roof camping require movement, then one support unit that changes target priority. Teach attacks with consistent silhouettes, sound, windups, and ground indicators. Keep the body scale and weapon role stable across procedural families. A pirate hat should never obscure an eye weak point or turn a ranged enemy into an ambiguous silhouette.

Make the Foreman a recognizable encounter with an entrance, readable phases, a counterplay opportunity, and a funny defeat. Simply multiplying HP by three risks a lengthy version of the same fight. Escalate enemy combinations, lane pressure, and counterplay before relying on quadratic health and damage scaling. Evaluate time-to-kill across fresh, intermediate, and maxed profiles; otherwise endless progression becomes a stat check.

**The visual identity needs authored characters more urgently than additional surface detail.** The clayified buildings, painted sky, felt ground, and paper corn provide a useful direction. The live opening still puts a large textured silo beside a capsule farmer. The player character is on screen almost constantly, so improving that model and animation has unusually high value.

Commission a distinctive farmer silhouette, an expressive Nibbler, and one signature Foreman first. Give the farmer readable boots, hands, face, overalls, and a milk-can rig that visibly coughs and rattles. Build a small library of anticipation, recoil, idle, panic, and victory poses. The robots should have a recognizable comic personality in silhouette and motion without needing their generated names to be read.

Use three scales of surface detail: broad hand-shaped forms, occasional fingerprints/seams, then restrained microtexture. In the inspected view, strong fine normal detail reads closer to rough stone or foam than soft plasticine on some surfaces. Reduce it on skin and large building faces; keep fingerprints as selective evidence of handcraft. A shared shader should still allow material-specific roughness, print scale, and boil strength. Felt, paper, metal, and skin should not feel identical.

| Visual area | Improvement | Acceptance check |
|---|---|---|
| Composition | Open with farmer, silo objective, and approaching threat in one readable arrangement | New viewers identify the objective from a five-second clip |
| Lighting | Warm farm, quieter ground values, controlled enemy accents; stronger local contact | Bots separate from crops at gameplay distance and in grayscale |
| Animation | Authored stepped poses over smooth movement/camera | Deliberate stop-motion impression without sluggish controls |
| VFX | Cotton puffs, chunky recoverable-looking parts, paper sparks, clear weak-point flashes | Threat telegraphs remain visible during the largest effects |
| Interface | Larger text, short labels, shape-coded currencies/threats, one dominant urgent alert | Readable on an actual 800p handheld without zooming |
| Camera | Tune collision near silo/ladders, shoulder swap, aerial framing, optional shake | No target hidden by the farmer or involuntary disorientation during repairs |

Avoid gameplay depth-of-field blur until target readability is proven. Reserve stronger miniature photography effects for menus, victory moments, and optional photo mode. Maintain separate quiet, normal-combat, and boss visual references so the art team judges the whole frame rather than isolated assets.

**Audio is part of the playable prototype, not a final polish layer.** Move the already-planned audio skeleton forward. Build pistol, wrench, impact, robot windup, pickup, theft, leak, jetpack, and wave-transition cues now. Prioritize threats over rewards in the mix, cap simultaneous voices, and avoid a separate loud sound for every pickup. Use the proposed bluegrass/electronic combination as a musical identity, with calm, pressure, and victory arrangements. Review the same combat clip with and without audio to see whether timing and emotional payoff improve. Provide visual equivalents for critical cues and separate volume controls.

**Performance measurements point to bursts and rendering complexity first.** The diagnostic ran Godot 4.7.2, Metal Forward+, on an Apple M4 Pro, with a requested 1280×800 window, VSync disabled, and a logical viewport reported as 1600×1000. It used a stationary camera, seed 42, a stopped wave director, an enlarged silo health pool, and 60 explicitly spawned mixed robots. This is a short debug-build diagnostic, not a release benchmark, GPU-time capture, full match, or Steam Deck result. The near-60 Hz pacing in the first two samples may include presentation/environment effects; do not infer maximum throughput from it.

| Scenario | Sample frames | Median frame interval | P95 | P99 | Worst | Median engine draw calls |
|---|---:|---:|---:|---:|---:|---:|
| Farm, no robots | 180 | 16.66 ms | 17.84 ms | 18.32 ms | 18.37 ms | 1,287 |
| 60 mixed robots | 300 | 16.67 ms | 17.61 ms | 21.42 ms | 24.21 ms | 1,601 |
| Simultaneous deaths and pickups | 180 | 5.04 ms | 12.09 ms | 45.02 ms | 51.52 ms | 2,415 |

The 60-robot spawn calls took 13.46 ms synchronously; enqueueing all deaths took 17.02 ms. Those call durations are separate from the frame distribution and must not be added to it as if independent. The death sample ended with 267 pickups. Physics-process monitor P95 was 2.36 ms in the live-robot sample and 33.21 ms during the burst, but these are coarse engine monitors rather than function-level profiles. Rendered primitive counters increased from about 751,000 to 1.54 million to 1.75 million across these scenarios; counters can include passes, so these are not unique model polygon counts. Engine static memory is not total process RAM or VRAM.

| Priority | Existing evidence | Change to investigate | Verification |
|---|---|---|---|
| P0 | Death burst exceeds a 16.7 ms frame budget by a wide margin | Cache pickup meshes; pool short-lived pickup/VFX objects; merge nearby same-currency pickups; budget cosmetic breakup across frames | Repeat identical burst after warm-up; preserve total currency and pickup feel |
| P1 | High baseline render counters; robot families use many mesh parts | Profile shadow/depth/color passes; consolidate static robot subparts and building trim; preserve animated parts; add distance LOD | Same camera/seed, lower CPU submission or GPU time, unchanged silhouettes |
| P1 | Expensive clay detail on large surfaces; SSAO and long-range shadows enabled | Quality tiers for shadow distance/filtering, SSAO, SSS, boil, and normal detail; distance-based material simplification | GPU capture at equal resolution and visual comparison, especially Deck |
| P1 | `_navigate` refreshes goals every 0.25 s, with an already randomized initial timer | Keep staggering; update static goals only when needed; profile avoidance neighbors and blocked routes | Stable agent arrival, no oscillation, better worst-case physics time |
| P1 | Runtime asynchronous navigation bake at run start | Explicit readiness barrier; collision-only bake inputs; compare cached/prevalidated scatter layouts | Every lane and objective route valid before combat starts |
| P2 | HUD rewrites strings and queries groups each frame | Signals for health/currency; low-frequency counters; cached live counts | Lower UI CPU cost with no stale alerts |
| P2 | `_spawn_due` admits an event when current count is below cap | Reserve the entire event's population before spawning | A three-bot squad at 59 live bots cannot overshoot a cap of 60 |

Several optimizations are already present: shared clay materials and cached robot primitive meshes, chunked crop/corn MultiMeshes, non-shadowing small decorations, lightweight scripted pickups, and staggered repaths. Preserve these. A shared material does not guarantee the entire robot becomes one draw call. Do not replace the whole AI system for an assumed speedup; use maintainability and measured behavior complexity to decide whether the planned LimboAI migration is worthwhile.

Godot recommends profiling LOD, instancing, transparency, and lighting costs; it also recommends avoiding unnecessary path resets and using simple navigation source geometry. These support the investigation order, not a claim that any one feature is the measured bottleneck. [Godot 3D performance guidance](https://docs.godotengine.org/en/stable/tutorials/performance/optimizing_3d_performance.html), [navigation guidance](https://docs.godotengine.org/en/stable/tutorials/navigation/navigation_optimizing_performance.html).

Set a release benchmark matrix now: 0/20/40/60 live robots; mass death; rapid-fire weapons; boss effects; maximum cracks; low and high viewpoints; startup/restart; 30-minute soak. Record cold and warm runs, hardware, export configuration, actual render resolution, CPU/GPU frame times, P95/P99, memory, and hitch counts. Target 60 fps on the chosen minimum PC and a stable handheld preset; evaluate 40 fps as a fallback on a suitable Deck display mode. Treat those as targets until on-device tests pass. A graphics preset must not silently alter competitive difficulty: the existing 40-versus-60 live-cap proposal changes spawn pressure and needs equivalent pacing or separate rules/records.

**Reliability and accessibility need to move ahead of content expansion.** The smoke test should fail at the first invalid scenario precondition and print phase, silo health, alive bots, queued spawns, pause state, and seed. Protect the objective during tests unrelated to objective survival. Create deterministic theft and squad fixtures rather than silently skipping those checks when the random wave lacks them. Then run the known seeds and a bounded multi-seed soak; a formula test passing is not equivalent to a whole run passing.

Other concrete engineering work:

- `save_manager.gd:57` writes directly to the only profile file. Add a validated temporary write, safe replacement, a last-known-good backup, and explicit recovery. Currently a malformed JSON profile falls back to defaults and the next autosave can replace it. Validate types/ranges and future schema versions; test interruption and cloud-conflict recovery before shipping permanent progression.
- `input_router.gd:30` releases the cursor on Pause but does not pause play. Add a real solo pause/settings flow and focus-loss behavior. In co-op, show clearly that the shared match continues.
- `pickup.gd:65` adds the pickup to the tree before setting its world position, while `_ready()` raycasts for ground. This ordering can sample ground at the parent's origin instead of the drop site. Initialize location before its ground query; verify raised surfaces and uneven terrain.
- The player registry is useful, but currency and stat evaluation remain global, and player zero owns every gamepad. These are unresolved multiplayer boundaries, not completed co-op architecture. Split per-player equipment/progression from shared silo/run state before network implementation.
- Audit generated-versus-authored files and the existing credits trail. Preserve reproducible imports, pin engine/addon versions, build clean exports, and diagnose first-import crashes rather than declaring a retry sufficient release assurance.

Accessibility belongs in the first external demo: remapping, controller glyphs, aim sensitivity/dead zones, hold/toggle choices, hold-to-fire, HUD scale, color-plus-shape cues, reduced motion, camera shake control, readable damage warnings, and relaxed timing. Keep combat difficulty assistance distinct from legibility or motor-access options. Test focus order and purchasing on controller. Existing reload/interaction priority handling should be verified in overlapping interactions rather than assumed broken because both use X.

**Co-op is a high-upside hypothesis that needs an early decision.** Defending a shared farm naturally creates complementary tasks, but networking adds substantial engineering and QA. Run a bounded two-player spike after the solo loop works: one defends while the other intercepts thieves and repairs. Include downed-player recovery, personal loot, understandable shared upgrade rules, and joining/invites. Test latency and disconnects early.

If independent pairs consistently prefer replaying together and invites drive new interest, consider two-player co-op for launch. Re-estimate schedule and budget before promising it. If it does not improve the product enough, keep solo launch and reconsider multiplayer later. Defer four-player scaling, host migration, split-screen, and cross-play unless funded and validated. This intentionally reopens the roadmap's post-launch placement as a commercial experiment, not as an already-approved scope change.

**The commercial case must distinguish appeal from sales evidence.** Atomicrops already combines farm protection, action, and persistent upgrades. Orcs Must Die! 3 offers solo/two-player third-person defense with traps and alternate modes. Roboquest emphasizes movement, weapon variety, build synergies, and solo/two-player play. These are relevant design and positioning references; their store descriptions do not prove this game's potential revenue, and I have not inferred units sold from review counts. [Atomicrops](https://store.steampowered.com/app/757320/Atomicrops/), [Orcs Must Die! 3](https://store.steampowered.com/app/1522820/Orcs_Must_Die_3/), [Roboquest](https://store.steampowered.com/app/692890/Roboquest/).

The differentiation to test is the combination of handmade comic characters, aerial interception, and reactive farm defense. “Many upgrades” and “procedural enemies” are supporting features. Recruit action-roguelite, defense, and approachable-action players separately; compare their expectations instead of treating everyone who likes farming games as a likely customer.

Test $19.99, $24.99, and $29.99 positioning with a concrete demo and content promise. My starting hypothesis is $24.99 for a polished premium release with substantial replay value; this is a proposed price, not a market conclusion. Validate willingness to buy rather than asking only whether testers like the art. Use meaningful expansions after launch if the audience exists. Avoid building a monetization service before the base game earns sustained demand.

**A transparent route to $20 million.** For planning, define the target as lifetime game/expansion sales over roughly three to five years, after discounts, refunds, and indirect taxes, but before platform fees and publisher participation. This is a modeling convention, not an accounting conclusion. If the intended goal is $20 million of developer receipts or profit, the necessary sales are substantially higher.

| Scenario, not forecast | Paid base units | Realized base price | Expansion units × realized price | Sales before platform fees |
|---|---:|---:|---:|---:|
| Downside planning case | 50,000 | $16 | None | $0.80m |
| Meaningful indie success | 250,000 | $18 | None | $4.50m |
| $20m breakout case | 1,000,000 | $18 | 250,000 × $8 | $20.00m |
| Larger breakout sensitivity | 2,000,000 | $19 | 600,000 × $9 | $43.40m |

Without an expansion, $20m requires about 1.11 million units at an $18 realized price, 1.33 million at $15, or 1.67 million at $12. The expansion case assumes a 25% attachment rate and enough retained audience to justify producing it. None of these rates is observed for this game.

For an illustrative 70% developer share after the storefront, $20m in modeled sales becomes $14m before publisher terms, costs, and income taxes. Achieving $20m in receipts at that share requires about $28.57m in sales, or 1.59 million base units at $18 without DLC. Actual contracts and fee tiers must replace the placeholder. Do not present consumer spending, developer receipts, and profit as interchangeable.

Demand acquisition must scale accordingly. As an arithmetic sensitivity, one million purchases at a 5% qualified store-visit conversion would require twenty million qualified visits; at 10%, ten million. These are assumptions, not Steam benchmarks, and repeat visits/attribution complicate measurement. A launch with 200,000 wishlists and an assumed 15% launch-window conversion yields only 30,000 initial purchases. Most of the million-copy case would still depend on post-launch discovery, recommendations, updates, discounts, and potentially later platform releases.

Valve explicitly says there is no accurate universal sales formula from wishlist totals and no fixed wishlist threshold that unlocks visibility. Track wishlist cohorts as evidence of interest, not guaranteed revenue. [Steamworks wishlist guidance](https://partner.steamgames.com/doc/marketing/wishlist).

**Build the audience before release production is complete.** The current roadmap places store work late. Move positioning, capsule experiments, and an honest Coming Soon page forward once representative gameplay footage exists. Test whether a five-second clip communicates both the fantasy and the activity. Validate a distinctive, searchable title; “Robot Attack!” describes the genre more than the farm identity. Any replacement name remains provisional until availability checks.

Create three repeatable marketing demonstrations: a jetpack interception that saves a grain sack, a surprising build combination, and an expressive robot defeat. Make each readable without narration. Use gameplay in the opening seconds of the trailer, show the defense objective quickly, and avoid a long logo intro. Test capsule readability at thumbnail scale. Never imply a cutscene or concept image represents gameplay that does not exist.

Recruit relevant small and medium creators with a reliable demo and a simple hook. Track outreach response, actual coverage, qualified visits, demo activity, and wishlists; do not substitute impressions for buyer interest. Use source-tagged links and Steamworks reporting to compare campaigns, with attribution limitations recorded. [Steamworks UTM analytics](https://partner.steamgames.com/doc/marketing/utm_analytics).

Use closed tests before committing the demo to Next Fest. Current Steam rules allow a title one Next Fest participation and require a public base-game page plus a playable demo. Select the event around readiness and verify its actual deadlines, rather than choosing a date first and hoping polish catches up. [Steam Next Fest documentation](https://partner.steamgames.com/doc/marketing/upcoming_events/nextfest).

Externalize text early, then choose localization languages from regional interest and costs. Test UI expansion, glyph coverage, and controller flow in localized builds. Evaluate ports after PC demand and performance are demonstrated; the revenue model does not require speculative console sales to add up. Keep community feedback focused on observed friction and recurring requests, not whichever feature has the loudest single advocate.

**Sharing should connect a memorable run to a challenge another player can accept.** Build this loop deliberately: see a ridiculous moment → try the challenge → improve the build → beat a friend → share the result. The game already has seeded runs, named robot families, persistent upgrades, and a Harvest Report. Connect those foundations before commissioning a large social platform. Virality is an outcome to measure, not a feature that can be guaranteed.

The first social prototype should answer: **“Here is my build. Same farm, same budget—save more grain than I did.”** Test it with twenty independently recruited friend pairs after the core loop passes its own playtest gate. Asynchronous competition can prove this appeal before online co-op is implemented.

**“Beat My Harvest” recreates the conditions behind a score.** After a run, offer **Challenge a Friend**. The recipient receives the same farm layout, enemy schedule, starting equipment, upgrade budget, and rules. Present two explicit options: **Beat my score**, using the same loadout, and **Beat my build**, allowing different purchases within the same budget. The second invites a useful conversation about strategy rather than only execution.

Start with approximately ten-minute challenges that can be attempted immediately. A short challenge is distinct from the longer Harvest Contract proposed above; it can reuse a curated portion of that content. Retain enough preparation time to inspect the loadout, then offer a quick restart after defeat.

The existing six-character robot-family code recreates a family, not a whole competitive run. Define a separate, versioned challenge identifier that resolves to the seed, content and balance version, mode, enemy schedule, starting state, loadout or allowed catalog, budget, gameplay assists, player count, scoring rules, and target result. A build code describes equipment and modifiers independently of the challenge. Show compatibility before importing, and never overwrite normal progression when loading a challenge kit. Validate seed outcomes on supported platforms; seeded content is not proof of deterministic physics or a trustworthy replay.

**Competition must be fair for a newcomer and a veteran.** Keep earned upgrades in the main progression mode. In **Harvest Challenge**, lend the prescribed equipment and equalize access so a hundred-hour upgrade advantage cannot decide the comparison. Begin with one featured weekly challenge and two categories, rather than fragmenting the initial audience across many leaderboards.

| Category | Conditions | What players compare |
|---|---|---|
| Same Tools | Identical starting loadout and rules | Execution, routing, and resource management |
| Open Workshop | Identical upgrade budget and allowed catalog | Build design as well as execution |

Rank by waves completed first, grain remaining second, and active completion time third. Explain that order visibly. Fix starting grain, reward opportunities, and capacity rules within each challenge so the comparison remains meaningful. Specify the handling of unfinished waves, ties, pauses, retries, and disconnects. Display kills, aerial kills, repairs, and rescued sacks as expressive statistics, but avoid making repeatable kills, repairs, or elapsed survival time the primary score. Audit strategies that stall a wave or repeatedly generate resources.

Show friends and nearby scores first, with global rankings available afterward. “You need 18 more grain to beat Sam” gives an ordinary player an attainable objective. Display honest ties rather than inventing precision. Separate incompatible balance versions, player counts, and gameplay rules, while preserving legibility and motor-access settings that do not change the challenge. Graphics quality must preserve competitive mechanics; reducing the live-robot cap on slower devices cannot quietly change ranked pressure.

Steam provides leaderboard infrastructure and a trusted-write option, but the game still needs score validation. For public competition, record the challenge version and run summary, reject impossible submissions, exclude debug-modified runs, and design a review path for disputed top results. Client-side plausibility checks alone do not prove a score is legitimate; select stronger verification before attaching valuable prizes. Friends-only prototypes can precede that work. [Steam leaderboard documentation](https://partner.steamgames.com/doc/features/leaderboards).

**Players should be able to name, borrow, and remix a build.** Meaningful combinations are the material people discuss. Extend the earlier three-build prototype with these candidate interactions; they are options to evaluate, not four additional mandatory launch classes.

| Candidate build | Memorable interaction | Constraint to test |
|---|---|---|
| Flying Scrap Collector | Airborne weak-point kills replenish a limited amount of jetpack fuel | Precision requirement and capped replenishment prevent effortless infinite flight |
| Chicken Cannon | Egg explosions chain through clustered enemies | Limited charges, positioning, and bounded chain length |
| Magnetic Menace | Pull robots together and launch them with a wrench finisher | Close-range exposure and limits on heavy-enemy control |
| Emergency Mechanic | Sealing a leak briefly empowers nearby defenses | Genuine damage/repair conditions and cooldowns prevent repair farming |

Give each build a compact card with a player-selected name, equipment, three defining modifiers, cost, and best compatible challenge result. Offer **Copy Build**, **Try in Workshop**, and **Remix**. Show what changed in a remix so players can explain why it works. Let imported equipment be tested in the workshop even when it is still locked in normal progression; a shared build should lead directly to experimentation. Keep names and shared text within basic length and moderation limits if they become publicly discoverable.

**Turn the Harvest Report into a farm postcard.** Replace the text-heavy result presentation with a readable, exportable composition. One example:

> **I SAVED THE FARM WITH 7 GRAIN LEFT.**  
> The Flying Scrap Collector  
> 10 waves · 43 aerial kills · 3 stolen sacks recovered  
> **Can your build save more?**

Include a recognizable farmer pose, the opposing robot family, a small equipment strip, and the challenge code/link. Keep the score and headline readable at phone size. Offer image export and copyable text, with sharing always initiated by the player. Select truthful highlights from the run: a narrow escape, personal best, unusual build, or comic defeat. Ordinary players should have entertaining results to share even when they never reach a global leaderboard. Avoid spoilers when highlighting content a recipient may not have encountered.

A challenge link should show the result, rules, build, approximate duration, and supported version before asking the recipient to launch or install. Give existing owners a direct route into the challenge, with a copy-code fallback. Evaluate a compatible demo challenge for non-owners so interest can become play immediately; clearly label any content restriction instead of silently substituting different rules. The landing page can also offer a store link. Do not require a new social account merely to inspect a shared result.

**Create moments that make sense in a short clip.** Prioritize four repeatable situations: a jetpack interception of the final stolen grain sack; a magnetic crowd setup followed by an enormous wrench bonk; a Foreman defeated beside a nearly destroyed silo; and a coordinated robot squad caught in a comic chain reaction. Viewers should recognize setup, danger, action, and payoff within seconds. Use framing, silhouettes, sound, and objective indicators to communicate those beats rather than relying on tiny damage numbers or an explanation of the upgrade menu.

Add highlight markers for clutch saves, major combos, boss defeats, and records. Steam Timeline can help players find and share moments in Steam Game Recording; markers improve discovery of recorded moments and are not themselves a video recorder or automatic posting system. Integrate these cues before considering a custom recording pipeline. [Steam Timeline documentation](https://partner.steamgames.com/doc/features/timeline).

**A weekly Harvest Cup gives friends a reason to return.** Feature one farm, one twist, and one comparable challenge. Keep previous challenges available, with the competitive window and archived results clearly labeled. Reward participation and mastery with cosmetic ribbons or trophies; rewards must not make future competitive runs easier. Avoid requiring daily attendance to retain progress.

Later, allow creators to publish curated presets such as **Wrench Only** or **Never Touch the Ground**. Begin with bounded rules that can be validated. Unrestricted custom rules, public discovery, and extensive user-generated content require additional balancing, moderation, compatibility, and support work, and should follow demonstrated demand. Creator challenges should use the same share/import flow as ordinary players.

**Build and measure the smallest complete sharing loop.** The order below defines dependencies; it does not assume all social features fit into the first ninety days.

| Order | Deliverable | Dependencies | Evidence to collect |
|---|---|---|---|
| 1 | One standardized challenge with comparable results | Challenge rules, normalized progression, versioned run data | Friends voluntarily retry to beat each other |
| 2 | Build export/import and equal-budget rematches | Stable equipment identifiers, budget validation, isolated workshop state | Recipients try and modify shared builds |
| 3 | Harvest postcard, challenge link, and preview page | Reliable run summaries and import flow | Shared results produce recipient challenge starts |
| 4 | Friends leaderboard and weekly rotation | Score submission, identity integration, validation, compatible versions | Players return for another competition |
| 5 | Highlight markers and curated creator challenges | Memorable gameplay moments and tested challenge presets | Clips attract new players who continue playing |

Track the funnel from result viewed to export/link copied, unique recipient opening, challenge start, completion, rematch, build remix, and return on another day. Record denominators, time windows, and owned-game versus demo recipients. An export or copy action is only intent to share; it does not establish that the player sent anything. Distinguish new referred players from existing players challenging each other, and acknowledge attribution gaps across devices and private messages. Use minimal disclosed data and opt-in test measurement.

For the initial twenty-pair test, observe whether the recipient can understand and launch the challenge without coaching, whether either player voluntarily rematches, and whether Open Workshop produces actual build changes. Compare this with the ordinary results screen. The initial social success gates below are proposed experiment thresholds, not claims about industry averages or guaranteed viral growth. If the social loop underperforms, diagnose whether the problem is weak gameplay, unclear comparisons, import friction, or an uninteresting shared result before adding more features.

**Use evidence gates to control spending.** The following thresholds are proposed internal targets, not established industry benchmarks. Recruit independent players, report denominators and confidence intervals where practical, and compare cohorts. Incentivized sessions and developer friends are weak evidence of voluntary retention; recruit existing friend pairs independently for the specific social experiment.

| Gate | Sample and measurement | Initial pass target | Response if missed |
|---|---|---|---|
| Comprehension | 20 new target players, no coaching | ≥80% explain defense objective and complete first wave unaided | Revise opening, indicators, and threat teaching |
| Core desire | Same cohort, optional extra run after scheduled test ends | ≥60% voluntarily start another run; median combat/movement rating ≥4/5 | Improve feel/build choices before adding content |
| Demo repeatability | At least 100 independent starts; opt-in measurement over 7 days | ≥60% reach demo finale; ≥25% return on a different day | Segment difficulty/technical issues; revise and retest |
| Challenge comprehension | Twenty independently recruited friend pairs; recipient uses a shared challenge without coaching | At least 16 of 20 recipients understand the comparison and start successfully | Fix preview, compatibility, equipment access, or import friction |
| Social replay | Same twenty pairs; optional play after the scheduled session | At least 10 pairs voluntarily play a rematch; at least 6 pairs try a modified build in Open Workshop | Improve challenge length, scoring, and build tradeoffs before scaling social features |
| Referral quality | Demo/link cohorts observed over 7 days, distinguishing existing owners and new players | Establish challenge-start, completion, and return baselines; improve against the ordinary report flow | Revise the shared result or recipient experience; do not scale on share clicks alone |
| Commercial appeal | Distinct audience/price cohorts with identical honest content | Consistent improvement in qualified wishlists and purchase intent; establish own baseline | Rework hook, packaging, or scope before scaling promotion |
| Release trust | Exported builds on minimum PC, Deck, and supported OS matrix | No known save-loss/run-blocking defects; stable chosen frame budget; successful long soaks | Delay release or narrow supported scope |

Capture first action, first kill, first purchase, first jetpack use, wave start/end, time repairing, deaths by cause, build choices, quit point, and performance spikes. Add challenge identity/version, import success, rule compatibility, recipient starts, rematches, and build remixes for the sharing experiments. Use minimal, disclosed telemetry or local logs with tester consent. Observe hands and screens for the first small cohort: a timestamp cannot tell you why someone misunderstood a thief. An unusually high finale completion rate can also indicate an unchallenging demo, so pair completion with enjoyment and replay.

**A practical 90-day plan follows, with dependencies and deliverables.** This assumes a small team with dedicated gameplay engineering plus art/audio support. It is a work plan, not a shipping-date promise. Owner roles can be combined in a smaller team, with corresponding schedule tradeoffs.

| Window | Owner | Deliverables | Exit decision |
|---|---|---|---|
| Days 1–14 | Engineer + designer | Fix smoke fixture; reproducible seed matrix; bell/pistol economy; true pause; backup saves; benchmark burst; first combat SFX; specify versioned challenge/run records | Reliable test build and a coherent first five minutes |
| Days 15–30 | Gameplay + character artist + audio | Expressive farmer/Nibbler, polished pistol/wrench, early jetpack teaching, larger HUD, one strong thief rescue; mock the Harvest postcard and recipient flow | First 20-person core test; stop content expansion if the loop misses its gate |
| Days 31–60 | Designer + engineers + art | Three build prototypes, one new ranged role, boss prototype, contract-mode test; one normalized challenge, build import/export, and equal-budget rematch; bounded two-player spike only if capacity permits | Choose run structure and launch multiplayer scope; run the twenty-pair social experiment; re-estimate scope |
| Days 61–90 | Team + producer/marketing | Polished 10–15 minute demo, on-device performance, independent 100-player test, representative trailer/capsule, store preparation; postcard/link prototype and referral measurement if social gates pass | Approve full production, repeat validation, or reduce scope; schedule friends leaderboards, weekly rotation, and highlight integration from evidence |

Public release of store assets or outreach would be a later execution step; this audit prepares the plan and does not publish anything.

After those gates pass, plan a bounded launch package: one excellent farm with three materially different authored layouts/contracts; four highly distinct weapons plus wrench/repair; roughly five or six enemy behaviors; three memorable bosses; a focused set of behavior-changing build modifiers; cosmetics/Almanac collecting; difficulty tiers; and optional endless play. Include the validated challenge/import/share flow; prioritize friends leaderboards, a weekly Harvest Cup, and highlight markers when the social gates justify them. Keep curated creator publishing as a later expansion of that system. Treat these counts as a budget envelope. Add content when it creates a new decision or memorable moment, and cut it when it merely increases the checklist. Two-player co-op remains conditional on the spike; four-player co-op is deferred.

The existing roadmap already recognizes many missing features. The main change is sequencing: move onboarding, audio, accessibility, save protection, telemetry, Deck profiling, audience validation, and a small asynchronous challenge experiment earlier. Replace the assumption that shared-seed competition must wait for post-launch Daily Harvest work with an early bounded test, while retaining the larger service features as gated scope. Reduce emphasis on hundreds of upgrade levels and extensive procedural cosmetics until the core earns demand. Do not treat AI-assisted implementation speed as an upper bound on the calendar: art direction, integration, testing, marketing, and iteration can still extend it.

**Budget against the downside, not the aspiration.** No actual team size, runway, salaries, or publishing terms were supplied. Use an initial validation tranche of roughly $80,000 as an example: two people for two months at $10,000 loaded cost per person-month ($40,000), $30,000 in targeted art/audio, and $10,000 in testing/contingency. Founder labor still has an opportunity cost. Replace all figures with real quotes before committing.

For a later production scenario, six core people for twelve months at $12,000 loaded cost per person-month cost $864,000. Add $200,000 external art/audio, $120,000 QA/localization, $200,000 marketing, and $80,000 operations: $1.464m. With 25% contingency, that is about $1.83m, excluding the earlier validation tranche. At eighteen months with the same external allowances, it becomes about $2.37m. This envelope must be re-estimated after the demo, social experiments, and co-op decision; it is not a quote or evidence that the current scope fits twelve months.

The sharing recommendations are additional scope, not free additions to those estimates. Price challenge serialization/import, normalized stat profiles, score validation, Steam integration, postcard rendering, link routing/hosting, analytics, compatibility QA, and support explicitly. Fund the early social experiment by prioritizing it over additional cosmetic/content breadth; move the optional co-op spike if the same engineers cannot cover both. Public score services and creator discovery add ongoing hosting, moderation, and support costs. Do not increase sales projections merely because these features are planned; use observed referrals and retention to revise the commercial model.

At $18 realized base price and a hypothetical 70% receipt share, contribution before remaining costs is $12.60 per copy. Recovering $1.83m therefore requires about 145,000 base copies, before publisher recoupment, additional support costs, and taxes. The 50,000-copy downside case would not recover this budget. Release spending in stages and retain launch-support runway. Expansion production is separately gated on actual customers and engagement.

The immediate decision is to fund and build the proof: a dependable, distinctive demo that strangers understand, enjoy, and choose to replay. A million-customer outcome becomes a credible ambition only when that product evidence is joined by repeatable audience growth. The plan gives the team ways to discover that evidence early and to stop expensive assumptions from turning into production commitments.
