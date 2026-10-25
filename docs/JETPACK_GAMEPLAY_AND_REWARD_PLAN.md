# Milk-Can Jetpack — gameplay transformation and long-term reward

October 25, 2026. Planning revision following the user's direction. No gameplay changes are implemented here.

**The jetpack should reward mastery of the farm with a new way to fight across it.** The player can already reach every rooftop without flight. The first five waves should establish satisfying ground combat, climbing, rooftop positions, and zipline routes. Later, earning the jetpack should change how the player combines attacks, crosses the battlefield, and responds to threats.

The earlier recommendation to grant it after wave two is withdrawn. An unaffordable early purchase is not evidence that the opening needs flight. Moving the same unrewarding equipment earlier would weaken the long-term reward while leaving its gameplay problem intact.

**Why the current unlock lacks a payoff**

These are source-backed mechanics and design hypotheses. They have not yet been compared in normal-speed human flight tests.

| Current behavior | Likely consequence | Design requirement |
|---|---|---|
| Base thrust is 1.2 seconds; powered horizontal speed is 5 m/s, while running is 7 m/s. | Powered movement can feel like a short upward hop with a horizontal speed penalty. Total airborne travel also includes jumping and falling, so these values are not a measured route-time comparison. | The base purchase must support one complete, useful aerial maneuver with fuel to recover safely. |
| Hover requires three Fuel Tank levels and another purchase; air dash and ground pound are also separate purchases. | Much of the equipment's identity arrives after paying for the equipment itself. | Include a coherent aerial move set in the big unlock; subsequent upgrades specialize a satisfying base kit. |
| Roofs are already accessible. | Simply getting onto a roof does not establish a new gameplay style. | Flight creates rapidly changing angles and attack sequences that fixed routes and stationary perches cannot reproduce as quickly. |
| Fuel recharges on grounded surfaces after a delay; ordinary repair requires being grounded. | Leaving the ground temporarily removes repair access and creates a landing obligation. | Make the landing a useful part of the combat loop. Preserve meaningful reasons to return to the farm. |
| Parts normally magnetize within 3 m; grain sacks require contact. | Aerial kills can leave cleanup work behind, and flying past a thief is not the same as recovering its sack. | Flight's reward accounting must include salvage collection and objective recovery, not just kill time. |
| Ordinary enemies can abandon an unreachable farmer and attack the silo. | Hovering safely can still lose the objective; altitude alone is not a defensive advantage. | Aerial play must help remove or redirect threats quickly enough to justify leaving ground defense. |

Sources: [jetpack](../scripts/components/jetpack.gd), [movement and landing](../scripts/player/farmer_movement.gd), [upgrade dependencies](../data/source/upgrades/travel.csv), [repair](../scripts/player/farmer_repair.gd), [pickups](../scripts/systems/pickup.gd), [enemy targeting](../scripts/ai/robot.gd).

**The core loop to prototype**

**Launch → cross the fight → exploit an angle → impact or brake into a chosen landing → defend and refuel.**

An example: a squad is pinning down the barn approach while another group threatens the silo. The player launches over the squad, turns to fire into its exposed rear, then lands with a short crowd-control impact beside the silo. They finish the remaining attackers, collect salvage, and repair or reload while the pack refuels. The reward is compressing several useful actions into one expressive maneuver.

The ground player can still flank, climb, shoot, and defend successfully. The jetpack player can chain those decisions across open space and change their approach mid-fight. We should not damage the existing ground game to make the new equipment appear valuable.

**A complete base purchase**

Prototype these as a single earned kit. Reuse existing dash, hover, and ground-pound code where appropriate, but test their interaction rather than assuming that bundling flags makes them feel good.

| Capability | Purpose | First prototype and tradeoff |
|---|---|---|
| Directional powered traverse | Cross an active fight and choose a fresh angle. | Test 3 seconds of usable thrust and 9 m/s horizontal speed, with responsive direction changes. These are temporary test values. Compare against the current 1.2 s / 5 m/s baseline on measured routes. |
| Aim-brake and safe descent | Make an airborne shot deliberate and let the player choose a landing. | Include a brief aim-brake/hover in the base kit, charged against the same finite fuel budget. Preserve camera continuity and the existing ability to soften a fall by braking. Show low-fuel landing affordances early. |
| Controlled impact landing | End the aerial sequence by helping ground defense. | Include a targeted landing attack with a visible footprint and a readable short stagger against ordinary robots. Reuse ground pound, but tune damage and repeat cadence; current 75 damage / 4.5 m radius is a baseline to evaluate, not an approved new balance. Heavies resist stagger. |

Keep three clear player intentions: travel, aim, land. Introduce them in that order during the unlock demonstration. Do not require an extra air-dash purchase merely to make travel responsive; determine whether a distinct dash input adds useful control after the basic traverse works. Preserve keyboard and gamepad parity.

Fuel is a planning budget, not an arbitrary interruption halfway through the first useful maneuver. Keep landing/refueling as the baseline cycle. Avoid unconditional kill-to-fuel refunds in the first prototype: they could turn plentiful weak robots into unlimited airtime. Tune later specializations only after the basic cycle works.

**Give flight something worth doing**

Build three small encounter prototypes using existing farm spaces before expanding the enemy catalog. Run each with a ground kit, the current jetpack, and the proposed base kit at equal weapon power.

| Encounter | Ground solution | What flight adds | What would disprove the idea |
|---|---|---|---|
| Changing attack angle | Circle cover or climb to a fixed firing position to attack a squad's exposed side/rear. | Cross overhead and adjust position as the formation turns; fire during the crossing and land beyond it. Prototype one directional defense tell on an existing squad. Elevated ground shots can exploit it too. | Standing on one roof is equally effective with less effort, or the player cannot track targets while crossing. |
| Cross-farm rescue | Use learned paths and ziplines to respond to two staggered threats. | Cut across the route, interrupt one group during transit, and land beside the second threat. Both events remain recoverable on foot. | Flight saves travel time but loses enough damage, salvage, or repair time to be a net burden. |
| Attack-and-land defense | Hold a ground lane and prioritize enemies approaching the silo. | Attack from a useful angle, then choose a landing that briefly interrupts a dangerous group and creates room to finish/repair. | Repeated tiny hops and slams beat meaningful flight, or the best tactic becomes hovering outside all danger. |

Place useful threats within a reachable aerial circuit. Do not spread fights arbitrarily farther apart, create inaccessible mandatory objectives, or make existing climbs slow and unpleasant. Fixed perches provide stability; flight provides changing position and timing. The encounter should make those advantages visible.

Use existing ranged threats as readable counterpressure: an aimed shot commits to a position with a clear windup, giving a moving player an evade opportunity. Avoid perfect tracking or unavoidable antiair. Start with one cue at a time so an aerial player can read the farm, fuel, and target without scanning five HUD elements.

For salvage, first test bounded collection of parts from the player's own aerial kills: mark them for collection on the next safe landing, show the amount, and prevent double credit with Scrap Vac. Grain sacks retain the physical recovery decision. Compare this with simply improving landing-route pickup collection before committing to a new banking rule. Do not silently award all world loot or erase the value of existing collection upgrades.

**Make earning it a major event**

Keep flight outside the first-five-wave reward ladder. Introduce the physical unfinished milk-can rig at the shed as an optional long-term goal. Show what it will eventually let the player do through a short preview; early tasks should still have their own worthwhile rewards.

Proposed progression structure: earn a blueprint through a later defended milestone, secure a guaranteed component from a later major encounter, and finish a visible construction project with saved parts. Component progress persists across runs. Use deterministic milestone rewards rather than requiring a lucky rare drop or repeated early-wave farming. Limit required components to a small understandable project, with each step visibly changing the rig.

Do not choose the final unlock wave or price yet. First prove the kit, then measure when players have mastered the ground loop, accumulated meaningful progress toward it, and encountered situations it transforms. The eventual requirement should represent substantial play beyond the opening. The current wave-three eligibility and 40 Al / 15 Cu price will need explicit revision; merely leaving those values unchanged does not implement this long-term design. Remove any bell-income shortcut that bypasses the intended progression.

At completion, give the rig a short handmade assembly/ignition payoff and an untimed test opportunity. Then present a controlled version of a familiar combat problem where the new sequence immediately helps. The player should finish that fight thinking “I can play differently now,” and be able to explain how. Test any preview/demo separately from normal progression; no early production loan is part of this plan.

Existing owners keep their earned jetpack and relevant upgrade value. Before migration, decide how purchased hover/dash/ground-pound levels convert if those functions enter the base kit. Offer equivalent specialization credit or a clear refund; never delete the purchase or require earning the same equipment again. New-profile progression and existing-profile compatibility need separate tests.

**Further upgrades deepen a style**

After the base kit works, prototype three directions one at a time:

- **Aerial gunner:** better aim-braking and short firing opportunities; trades maneuver fuel for accuracy and exposure time.
- **Impact defender:** more control over landing placement and disruption; commits the player to entering melee danger.
- **Interceptor:** longer lateral bursts and faster turnaround; prioritizes covering threats over hovering and sustained fire.

Avoid using many Fuel Tank purchases as the repair for an unsatisfying first purchase. A later build can extend or reshape the loop, but should not be required to complete it once. Keep ground-oriented upgrades competitive in sustained defense, repair, and stable shooting.

**Presentation is part of the reward**

Give the launch a readable anticipation and a punchy ignition, then preserve responsive movement. Tie flame and sound to actual thrust and fuel. Use a restrained speed cue rather than shaking the aiming view. The camera should show the landing area and current attack direction without repeatedly changing zoom or pitching away from the target.

Make the end of a successful circuit feel different from an ordinary fall: a controlled landing pose, localized impact, clear enemy reaction, and a brief fuel-recovery sound. Keep effects below the priority of enemy windups. The old prototype already adjusts camera pullback and fall damage; evaluate those together with the new movement instead of layering unrelated effects onto them.

**Implementation sequence and go/no-go gates**

| Stage | Deliverable | Gate before proceeding |
|---|---|---|
| 1 — Ground baseline | First-five-wave route/encounter plan with flight disabled; capture real climb, interception, and repair times. | Ground combat is enjoyable and all rooftops/required repairs have functioning routes. No wave-three jetpack dependency remains. |
| 2 — Flight sandbox | Toggleable current and proposed kits in an isolated test scene; same weapons and farm. Log launch, shots, useful hits, fuel, landing, damage taken, salvage, and time away from objectives. | Players can deliberately cross, attack, and land on both control schemes without the kit feeling like extra busywork. |
| 3 — Combat proof | The three encounters above, played with ground/current/new kits. | Flight produces useful attack sequences and objective outcomes, rather than merely longer airtime. Ground play remains a viable preference. |
| 4 — Reward arc | Blueprint/project/component progression and first-flight encounter, using the proven kit. | Substantial later effort produces an immediately valued change; no random-drop wall or early bell-farming shortcut. Exact wave/cost comes from this test. |
| 5 — Specialization and integration | A small upgrade set, save migration, full weather/camera/audio QA, later-wave pressure tuning. | Players retain value from prior purchases; no infinite-air or repeated-hop-slam dominant strategy; first five waves remain complete without flight. |

Use a small, counterbalanced playtest round with at least eight players who already understand the ground loop. Let them learn both flight variants before comparing preference. Starting prototype gates, not claims of validated results:

- At least 6/8 execute a launch → useful attack → intentional landing sequence without coaching after the demonstration.
- At least 6/8 can name a combat choice the new kit enables and voluntarily use it again in a suitable encounter.
- In at least two of the three prototypes, the new kit creates a meaningful objective advantage or equally effective, clearly preferred expressive solution. Track grain retained, response time, hits landed, damage taken, recovery/repair time, and salvage together; airborne seconds and kill counts alone cannot pass the gate.
- Test a 20–30% response-time improvement on a suitable cross-farm route as a starting hypothesis. Confirm that aiming, landing, and cleanup do not erase the gain. Do not demand that flight win every encounter.
- Ask players to choose equipment freely after comparison. If they mostly return to the ground in situations built to showcase flight, revise movement/encounters before tuning acquisition timing.
- After earning the production reward, look for voluntary use over several subsequent fights, not just excitement in a forced demonstration. Check the weakest newly unlocked kit, not only a fully upgraded build.

**Next concrete task:** build and compare one cross-farm combat circuit with the current kit and a complete prototype kit. Prove that flying changes a useful decision and feels rewarding, then design the long-term earn around that experience.
