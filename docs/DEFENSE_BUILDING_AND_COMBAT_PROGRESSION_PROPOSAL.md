# Robot Attack! — intermission construction and vertical defense

**Playtest change, October 30, 2026:** physical defense copies are now assembled and picked up at a marked workshop in front of the stables. The workshop also sells recipe unlocks at their existing prices. Finished stock stays inactive until the player collects it with Interact, carries it to a green preview and deploys it without another charge or assembly. Tab and the siren return a carried copy to its origin. From wave 2 a gold trail and persistent lesson teach the first build–pickup–placement. Queue, capacity, assist, cancel/refund, damage, relocation and salvage rules otherwise remain. This replaces the earlier ability to queue a new copy remotely at its intended deployment site; free placement of a collected copy remains. Existing unlocked recipes migrate without changes.


October 25, 2026. Revised after the user's design corrections. This replaces the previous version of this proposal, including its early forecast, battle construction, starter turret, separate Field Scrap currency, and automatic permanent-loot recovery recommendations. The roster/economy revision below is now implemented in the current game. Construction, new defensive items, and dedicated silo-ladder enemies remain proposed work. Exact defense prices, times, limits, and unlock timing below are prototype recommendations.

**Status, October 26, 2026: slices 2–6 are built; turrets (slice 7) are not.** [ROADMAP](ROADMAP.md) section 4.13 (DF-1 to DF-3) lists the work, which used the prices, capacities and times in the item table below. The Rung Runner climbs the silo ladder (two on the rungs at once, the rest waiting beside the foot), walks the first catwalk to a crack socket and bashes the silo at that height, with a climbing clank, hook tells and a HUD warning. It debuts alone on wave 5 and takes 35% of the climber share from wave 7. Construction runs only in intermission, on sites authored by rule: one at every lane gate, three on the first catwalk (the ladder top never takes a barricade), and the tool shed and barn roof perches. Confirming reserves the parts and capacity (8); one job advances with two waiting; standing by with the wrench doubles its speed; the siren freezes unfinished work as inactive ghosts; cancel and run-end refunds of the unbuilt share settle once; finished copies can be moved, repaired or dismantled for half their price times their condition. The Spring Trap really launches light robots (capped fall damage, a stun, kill credit to its owner, no throws for Heavies, loot kept inside the farm). The Scarecrow Decoy lures only robots that can reach it, never thieves or Foremen, and robots whose way a Scrap Barricade blocks have to smash it (a climber on the catwalk takes the other way round first). The BUILD pegboard branch holds the recipes plus Quick Assembly, Coil Springs, Loud Scarecrow, Sturdy Scrap and More Room. Springy Soles and Zipline Grip are retired and refunded once from fixed per-level schedules, and every gun now fires from a zipline. Wave 5 is the two-position encounter: a Rung Runner on the silo and a Lobber on the barn roof, joined by the existing dome-to-barn cable.

Changed from this proposal: the intermission is 30 s by default, with a Relaxed 90 s setting, because roadmap decision D1 and the playtest simulation both asked for short breaks; whether 30 s leaves time to build is the first playtest question. The farmer walks through barricades, so no placement can cut off a ladder, repair or exit. The Spring Trap recipe and one free copy are a guaranteed reward for clearing wave 4, before the first ladder climber. Deployed defenses are run-scoped and aren't saved with the profile. Not built: turrets, previews of launch arcs, lure routes and barricade coverage (the build menu shows price, capacity and assembly time), the Brawler and Sharpshooter perks, equipped perk slots, and the normal-speed playtest measurements.

**Reversed after the user's playtest (2026-10-26):** a quick-buy menu usable anywhere "takes out the fun of traveling". Intermissions are 90 s again with shopping at the shed; the quick-buy panel, Ready-from-anywhere, pinned goals and the Relaxed setting are removed; no wave hands over an item (no pistol kit, free tool or free Spring Trap copy); defenses are placed freely instead of on authored sites; and the opening is lighter (Clanker pairs, a 350 HP first Foreman the wrench can beat, a 900 HP second one). See ROADMAP section 4.13, "Playtest rework".

**The central loop is commitment under uncertainty.** During a fixed intermission, collect parts, buy upgrades, repair the silo, climb to useful positions, and build a defensive arrangement without knowing the next gates. The siren reveals the attack. During battle, fight using the arrangement already built, including the consequences of a mistaken bet. Height should improve that arrangement and create combat opportunities, while climbing enemies make upper levels worth defending.

The user's confirmed direction is:

| Decision | Rule |
|---|---|
| Reveal | Keep gates and family hidden until the siren. Preparing for gate 6 and receiving gates 2 and 3 is an intended outcome. |
| Construction | Build and place only during intermission; no construction or placement during battle. |
| Pressure | The intermission clock is intentional stress shared by planning, upgrading, building, and other chores. |
| Persistence | Keep parts and purchased upgrades persistent. |
| Collection | Parts remain until the next battle starts instead of expiring after 25 seconds. |
| Starter defenses | Decoys, barricades, and spring traps that launch robots. Turrets unlock later. |
| Height | Make defenses more effective in useful elevated positions. Enemies should climb the silo ladder and attack upper levels. |
| Playtest evidence | Players rarely zipline, but the existing ladder-to-dome cable approach works well when used. Preserve that route. Players have not progressed beyond six waves after repeated losses; vertical threats must be common and progression useful within that window. |
| Climber share | Roughly 25% of individual robots are climbers after introduction; keep drones scarce. |

**Current implementation supports parts of this, but not the full loop.** The [wave director](../scripts/systems/wave_director.gd) currently has a 90-second default preparation period, with the last three seconds used for the siren reveal. The shed closes for combat. The [pickup system](../scripts/systems/pickup.gd) expires ordinary parts after 25 seconds, and wave clear calls Scrap Vac, which removes the remaining pickups after awarding a fraction. Both removal mechanisms must change to preserve an intermission collection window.

The [profile save](../scripts/autoload/save_manager.gd) persists parts, upgrade levels, unlocks, and records. It is not a complete active-run save of placements and construction jobs. [Roof Lobbers](../scripts/ai/vertical_robot.gd) already follow scripted approaches up outer walls. The [ladder component](../scripts/components/climbable.gd) currently handles farmers, with a player collision mask; robots do not gain ladder behavior merely by being sent toward it.

The user confirms that the existing silo ladder leads onto the dome and makes the silo-to-barn cable approach work well in playtesting. Keep its start, end, and ladder access as they are. The design task is to make fights and defenses provide reasons to use this tested route.

**Keep the existing parts wallet as the source of competing investments.** Use Aluminium and Copper for ordinary construction, with Gold and Power Cells reserved mainly for advanced recipes, lasting upgrades, and later machinery. Do not add a new field-only currency in this version. Saving for a weapon upgrade versus buying a defensive item becomes a deliberate decision across runs and within the intermission.

Separate permanent recipe ownership from each physical copy. Unlocking a spring-trap recipe is lasting progression; assembling one spring trap consumes parts. A destroyed copy does not remove the recipe or refund its purchase. Unspent banked parts and purchased character upgrades survive defeat as they do now. The first teaching trap should be guaranteed and immediately usable; its availability must not depend on a lucky Copper drop.

For initial balance, recommend a small defense-capacity budget as well as parts costs: for example eight capacity, with a decoy occupying one, a barricade two, and a spring trap two. Queued and unfinished jobs reserve capacity too. Capacity limits how much a wealthy persistent profile can automate; earned wealth still buys better configurations and replacement options.

Deployed items stay in position between waves, retaining damage. They are run-scoped physical objects, while recipes and upgrades are profile progression. Price them as consumable defenses rather than permanent equipment. Define any later checkpoint or suspend-run restoration explicitly; do not assume that saving the parts wallet also saves the farm. A restart clears placements and unfinished work; refund the unbuilt portion of unfinished jobs once, so a reservation is not mistaken for a completed consumed item. Destroyed or already deployed copies remain spent.

**Use three starter items with different placement problems.** Numbers below are initial test inputs. Base copies should be Aluminium-only; Copper can enter upgraded configurations after players have learned the item.

| Item | Starting cost / capacity / assembly | Ground use | Elevated advantage | Limitation |
|---|---|---|---|---|
| Scarecrow Decoy | 6 Al / 1 / 5 seconds | Pull a few nearby eligible attackers toward a chosen position. | Clearer broadcast sight lines and a valid climbing route can lure eligible robots through a longer approach, buying more time and guiding them toward a trap. | Limited lure count and commitment duration. Cannot distract committed thieves or bosses, or summon unreachable ground robots beneath an invulnerable roof. |
| Scrap Barricade | 8 Al / 2 / 8 seconds | Delay a push or protect the farmer's chosen firing angle. | A narrow catwalk or roof approach concentrates a small number of attackers against its durability, letting the farmer defend a flank. | Destructible. Place only in authored, validated positions in the first version. Must leave farmer access to ladders, repairs, and exits. |
| Spring Trap | 12 Al / 2 / 10 seconds | Launch light robots up/back, disrupt a formation, and delay arrival. | Launch outward from a roof or catwalk: knock climbers back down, separate a squad, and gain a bounded fall-impact payoff. | Reset delay, mass limit, predictable launch direction, and capped impact damage. Heavies resist displacement; bosses cannot be repeatedly thrown off the farm. |
| Turret, later | Set after starter-loop tests | Sustained coverage when the player is elsewhere. | Better sight lines and less ground obstruction, balanced against exposure to ranged attacks. | Introduce after positioning, climbing threats, and trap combinations are established. It is not part of the initial kit. |

Ground placements must remain useful. Elevation adds a specific advantage with a travel-time and exposure cost; it should not multiply every item's power simply because its Y coordinate is higher. A ground spring can stop a thief sooner than climbing to place a rooftop spring that never meets it. A broad elevated decoy is a hedge against several possible approaches, while a trap by one gate is a concentrated bet.

Show each item's advantage in its preview: launch arrow and likely landing, valid lure routes, barricade coverage and remaining access. Explain why an elevated position helps. Keep construction close enough to the farmer that setting up a rooftop defense actually requires visiting the roof.

Spring-trap launches must resolve real combat outcomes. Knockback, landing recovery, and impact damage are separate from a purely visual explosion. Credit legitimate trap kills to their owner, including environmental falls, exactly once. Place dropped parts at a reachable landing or safe point; never throw essential loot outside the playable boundary. Launches that only delay a robot do not generate kill rewards.

**Commit the plan at the siren.** Recommended boundary: close construction, placement, upgrades, relocation, salvage, and deployable repair when the siren begins. The final three seconds reveal the gates and allow player repositioning. This preserves the bet by preventing a last-second build after the answer is known. Parts can still be collected until battle starts, as requested.

A confirmed blueprint reserves its full parts cost and footprint. One assembly job advances at a time while the farmer can collect, shop, repair, or travel; allow at most two waiting jobs initially. The player must visit a valid site to start a placement. A visible assembly animation makes the time cost clear.

Only intermission advances construction. An unfinished site freezes at the siren, remains inactive throughout battle, and resumes next intermission if it survives. It supplies no lure, collision cover, or trap effect. Show both the required time and time left before the player commits. Waiting ghosts stay inactive and do not act as free barriers. An active unfinished site is a vulnerable investment once the battle begins.

Ordinary item triggers and spring reset cycles continue during combat; these are operations of an already built defense. Combat never completes an unfinished job. Silo repair remains a normal battle action, but recommend keeping deployable repair, replacement, rearming, and upgrade work in intermission for the first version. This keeps the construction restriction legible.

During intermission, cancel an entirely unbuilt reservation for a full refund. Cancelling a partially built item removes the project and returns only its recorded unbuilt material fraction; completed work is lost. Merely suspending a job retains both its progress and full material reservation. Never refund the same material twice. A completed defense can be relocated during a later intermission without buying another copy, but it requires another setup timer. Dismantling returns a clearly displayed partial material value based on condition. Do not make repeatedly selling and rebuilding yield parts or a free health refill.

Optional wrench assistance can accelerate the active job during intermission, trading personal time against collection, shopping, and reaching another site. It is not a combat action. Test whether it produces real decisions before adding a dedicated hold-to-build chore.

**The preparation clock should keep running while decisions are made.** Shopping, reading a node, selecting a build, and inspecting placement do not pause or extend intermission. A normal pause freezes the whole game and offers no purchases, construction work, or placements. Tutorials can teach outside the active run clock, but the normal run does not enter an untimed construction mode.

Start the prototype with the existing 90-second window, including the siren. Measure the complete workload before deciding whether 60 or 90 seconds produces the intended pressure. Climbing, traveling to the shed, collecting parts, and sealing leaks all consume that same budget. The goal is choosing what to leave unfinished, rather than merely increasing the number of slow interactions. Build-time upgrades help complete a useful extra task within that fixed window; they do not extend it.

Keep unknown gates genuinely unknown. Do not add an Almanac upgrade that reveals them early. It could instead record previous attacks or show general robot behavior and trap interactions. Previous-gate history is historical information, not a promise that those lanes predict the next roll. Avoid secret lane manipulation that always makes the player's investment wrong.

Defenses persisting across waves softens a bad bet without removing it: a gate-6 barricade may be idle now and useful later. Offer a mixture of broad but weaker coverage, narrow strong placements, and personal intervention. The player still has a recoverable fight when the guess fails. A wrong guess should redirect their combat plan, not automatically determine defeat.

The former timer-based bell payout could grant roughly 104 Al before wave two. It is now replaced with a five-Al base reward paid only after that wave clears, independent of skipped time. Existing Early Bird ranks still multiply it, up to eight Al. Ringing and losing/restarting pays nothing; normal tutorial completion retains its separate teaching reward.

**Make upper levels a second combat front.** The implemented roster now allocates roughly 25% of individual robots to existing wall-climbing Roof Lobbers from wave three. The next dedicated ladder behavior should take part of this same climber allocation, rather than adding another 25% on top. Give a clearly marked light robot that behavior. It approaches the silo ladder, climbs to a specific catwalk, moves onto the catwalk, and attacks the silo at that height. Damage and cracks follow the real impact point. A farmer can intercept it below, shoot it while climbing, meet it above, or prepare a spring/barricade combination at a safe distance from the landing.

This enemy has a reason to climb even without a roof decoy or a high crack. The threat creates a proactive upper-level defense decision. Players can still fight it from the ground where sight lines permit, but reaching its attack position should offer faster interruption, melee access, or a better trap opportunity. Do not make it immune to ground fire just to force climbing.

Use an audible metal climbing rhythm, a visible ladder approach, and a small directional climbing warning. Keep the first climber solitary, with time to notice and respond. After the lesson, overlap a climb with ordinary ground pressure. Do not introduce the climber, all three defenses, and a new boss pattern in the same encounter.

Implement authored ladder links and catwalk movement, not full freeform climbing. Reserve ladder access and landings so robots cannot permanently jam the farmer or each other. Initially limit concurrent climbers on a route and let the farmer pass. If blocked by a barricade on the catwalk, the robot must attack it or use a supported alternate route. The barricade cannot make the objective unreachable to its AI.

Decoys only lure robots to elevated sites they can actually reach. Thieves remain committed to their sacks. Heavy robots do not all become nimble ladder climbers; a clear subset supplies the first vertical pressure. Continue using Lobbers and ranged threats to pressure exposed upper positions, with readable tells and useful counterplay.

**Give ziplines useful work to connect.** The player's test behavior says that firing while riding has not earned its progression slot. Remove the paid zipline-speed/firing track as a progression priority, compensate prior purchases, and keep basic riding straightforward. Preserve an existing firing capability if convenient, but stop using it as the promised reward for going upward.

A useful route is: climb to prepare a roof defense → fight an upper threat or exploit that position → use a cable to reach another active position. On a wrong-gate reveal, the cable lets the farmer abandon their bet and personally cover another approach. After a catwalk interception, a cable can return them to a meaningful fight or collection route.

Keep the current silo-to-barn cable and its ladder-to-dome approach. Create a useful sequence of upper-level defense, dome access, and a barn-side fight so the existing cable connects actions the farmer already wants to take. No new connector or cable relocation is proposed.

Measure voluntary cable use and response outcomes in those encounters. Its existing physical approach is supported by the user's playtests; evaluate the motivation supplied by the encounters and defenses. All important roofs still need ordinary access before the jetpack; the later jetpack reward changes how routes can be combined rather than introducing the first reason to care about height.

**Combat progression should reinforce these interactions.** Keep permanent ownership and the player's existing earned stat value. The initial tree can support three preferences without hard class locks:

| Path | Personal combat contribution | Defense synergy | Useful new progression |
|---|---|---|---|
| Brawler | Hold an approach, interrupt an attacker, and fight on a constrained catwalk. | Barricade protects a flank; decoy concentrates eligible robots; spring separates a dangerous group. | Heavy strike, controlled cleave, timed brace, shove that can knock a light robot off an edge. |
| Sharpshooter | Prioritize a climber, thief, or ranged attacker from a useful angle. | Decoy creates a firing window; barricade supports a position; spring disrupts a formation. | Weak-point payoff, deliberate pierce, handling/reload improvements, an accurate follow-up against an airborne launched target. |
| Engineer / Trapper | Spend intermission time efficiently and arrange combinations with broader coverage. | Decoy leads to spring; barricade holds a group in a trap's approach; later turrets add another option. | Assembly speed, wider placement orientation options, durable barricades, controlled launch direction, spring reset specialization. |

Engineer combat still includes fighting and exploiting the prepared network. It does not rely on building new equipment mid-wave. Optional actions such as marking a target for an already active later turret can come after the basic trap loop is proven.

Retire paid jump-height and zipline-speed ranks in favor of effects with demonstrated uses. A 25% construction work-rate upgrade changes a ten-second spring build to eight seconds, potentially leaving time to collect another cluster or reach a roof before the siren. Avoid reducing assembly times to zero or allowing any perk to bypass the construction cutoff.

New behavior-changing perk choices can remain limited to a few equipped slots so that eventually owning every recipe does not erase specialization. That is still a recommendation, not a reason to turn off already purchased passive bonuses. Keep loadout changes and new purchases inside the preparation rules. Refund retired nodes using supported historical cost schedules, with a documented generous fallback when old saves lack price history.

**Parts last through the battle and its following intermission.** Ordinary parts have no per-pickup age expiration. Parts dropped early in a long wave remain collectable after the last robot dies. They persist through the clear jingle, the whole next intermission, and the siren. At the transition to the next battle, settle Scrap Vac's configured share of what remains, then remove the rest before any new enemies or pickups are created.

Move automatic Scrap Vac from wave clear to that battle-start boundary. Keeping the current partial recovery model preserves the value of manually collecting parts during preparation and keeps Magnet/Vac relevant. A 100% Vac is still a valid earned upgrade, but it should not become the free baseline. Show an honest countdown warning near the end: remaining parts will be swept when combat starts.

This makes collection compete with climbing, building, repairs, and permanent purchases. A ranged player can leave loot while fighting and collect it afterward; they are no longer punished by an arbitrary 25-second lifespan. Their intermission route still matters. Collected parts bank immediately and persist; uncollected parts are not silently granted on defeat.

Grain sacks remain separate objective items with their own recovery and burst behavior; the direction about parts does not change grain theft. New loot types should declare whether they are parts or objective items instead of inheriting a lifetime accidentally. Keep a stacking/merging budget for persistent pickups so a long wave does not create unlimited render and physics work.

Rare parts continue supporting lasting progression and later machinery. Named mods can deepen decoy, barricade, and spring behavior once the loop works, without adding a full random-stat inventory immediately. Essential recipes should have guaranteed access; rare rolls should not decide whether the player can participate in the vertical-defense lesson. Award normal kill credit and drops for legitimate spring-trap kills, independent of direct weapon damage.

**The implemented economy is tuned around progress within six waves.** The original catalog needed 4,022 Al, 2,116 Cu, 224 Au, and 31 PC. Aluminium stopped contributing to several major tracks after rank six. That stranded the player's common-metal savings while scarce Copper, Gold, and Power Cells blocked further purchases.

The revised catalog costs 6,321 Al, 765 Cu, 63 Au, and 19 PC. Existing inventories and owned ranks are preserved. Aluminium remains part of every rank on long combat tracks; material price growth is 1.25 instead of 1.35. Previously Copper-only support tracks now combine Aluminium with a modest Copper cost. Core armor/plating unlocks use eight Copper instead of twenty. The new defense copies remain Aluminium-only at entry level, with no Power Cell requirement; later configuration upgrades can add Copper.

| Example: all ten Pistol Damage ranks | Aluminium | Copper | Gold | Power Cells |
|---|---:|---:|---:|---:|
| Previous cost | 216 | 165 | 26 | 5 |
| Revised cost | 499 | 45 | 6 | 3 |

Every even-numbered wave clear now directly banks 2 Cu, 1 Au, and 1 PC. The same wave pays once per attempt; actually clearing it in another attempt earns the reward again. A legitimate Foreman kill banks its existing 2 Au and 3 PC immediately, leaving the common-metal portion as pickups. Debug/quiet kills do not pay. These guarantees prevent a player from having to reach the Foreman merely to begin dependable Power Cell progression.

Ordinary drop chances (Cu / Au / PC) are now Nibbler 25% / 2% / 1%, Clanker 60% / 6% / 3%, wall climber 75% / 12% / 8%, and Drone 50% / 10% / 10%. Regular Heavies retain guaranteed Copper and PC and now guarantee one Gold. The higher climber share consequently creates a useful Copper source as well as a combat reason to visit upper levels. Basic defenses never depend on a lucky rare drop.

A reproducible [economy probe](../tools/economy_probe.gd) samples the real scene configuration and spawn generator. Across 256 seeds, climbers are 24.76% of robots in waves 3–6. Approximate mean climber counts are 3.5, 4.5, 7.7, and 6.4 respectively. They replace ground budget and are spread through the wave; live caps are two through wave five and three through wave fifteen. Drones are absent before wave five, one on their debut, and zero or one in wave six. Later drone totals remain capped at two through wave fifteen and three afterward.

| Six completed waves, modeled recovery | Al | Cu | Au | PC |
|---|---:|---:|---:|---:|
| Full collection | 344 | 59 | 11 | 9.8 |
| No manual collection, baseline 50% Scrap Vac | 172 | 32 | 8 | 7.9 |

The Vac model includes the next battle-start sweep after the last sampled wave. Both models assume all enemies killed and waves cleared, and exclude luck, traits, tutorial rewards, optional bell bonuses, and spending. They are not survival or enjoyment measurements. Full-collection cumulative PC expectations are approximately 1.25 after wave two and 3.26 after wave four, allowing shorter failed attempts to improve future prospects. Optional bell rewards add at most 30 base Al for six completed waves rather than approximately 702 before clears.

Progression targets for subsequent human tests: usually one affordable meaningful purchase in an intermission, a visible larger goal within a few attempts, and enough surplus Aluminium to consider an item without making all construction free. Price initial physical defenses around 6–12 Al, reserving budget for a combat upgrade. As players survive longer, replacement, repairs, and higher-tier copies can become recurring Aluminium sinks. Validate that these expenses do not stop weaker players from making permanent progress. The first prototype should measure both a returning player with thousands of Al and a genuinely fresh profile; neither stockpile is erased to create scarcity.

**A representative encounter should test the whole loop.** The farmer collects last wave's parts, buys a useful improvement, and bets on gate 6 with a ground barricade. They also climb to prepare a spring and decoy covering a silo catwalk approach. Time runs short, leaving some loot and another desired purchase behind.

The siren reveals gates 2 and 3. Construction closes. The gate-6 barricade remains for a future wave. The farmer uses the roof network or drops to intercept one active approach. A marked climber reaches the silo ladder; the decoy pulls an eligible attacker along its supported route, and the spring throws one off the catwalk. The player chooses whether to stay high and interrupt the next climber or take a cable to the other fight. Nothing new can be placed to solve the surprise immediately.

On clear, the remaining parts stay put. The next timed intermission offers a decision to collect, relocate the idle barricade, repair an existing defense, or invest in an upgrade. This is the intended pressure cycle; the wrong bet does not have to be erased for the wave to be winnable.

**Implement the smallest complete vertical-defense loop first.** The order below differs from the previous turret-first proposal.

| Slice | Work | Completion question |
|---|---|---|
| 1 | Phase-based parts lifetime; move Scrap Vac to battle start; preserve physical pickup value. | Can players reliably defer collection until preparation without loot vanishing or being counted twice? |
| 2 | One authored silo ladder route for a light robot, one catwalk attack position, clear climbing tells. | Does this create a worthwhile upper-level combat decision before high repairs are needed? |
| 3 | Spring trap on a validated catwalk site, plus a ground version for comparison; actual launch, fall/recovery, and kill credit. | Is the rooftop placement visibly better for that situation, and is returning upward worth the time? |
| 4 | Timed intermission construction using existing parts, strict siren cutoff, previews, reserved resources, and unfinished-job behavior. | Does the shared time budget create understandable sacrifices? |
| 5 | Decoy and authored barricade positions, reachable lure/obstruction behavior, persistence between waves. | Do combinations and uncertain gates create more than one useful setup? |
| 6 | A controlled two-position encounter using the unchanged silo-ladder, dome, and cable route; then short combat/trapper upgrade paths. | Do players voluntarily use height and the existing cable because of where they need to fight? |
| 7 | Later turret recipe and limited configurations after those systems pass. | Does sustained automation add another decision without making traps or personal combat redundant? |

Keep wave-number choices provisional while the separate phase/checkpoint plan is being evaluated. This proposal does not approve its three-wave phase change or lock these introductions to the old five-wave schedule. Coordinate the lesson, remix, and boss beats once that schedule is decided. The [opening plan](FIRST_FIVE_WAVES_FUN_PLAN.md)'s shop-pause and other conflicting preparation recommendations are superseded for this design; the [jetpack plan](JETPACK_GAMEPLAY_AND_REWARD_PLAN.md)'s later reward and normal roof access remain applicable. Coordinate ladder attackers with the [robot variety plan](ROBOT_ATTACK_VARIETY_PLAN.md), rather than assuming current Lobber wall-climbing implements them.

Use data-driven defense definitions, a run construction manager, clear source/owner damage attribution, and explicit ladder links. Keep construction accounting separate from the wave director; phase changes authorize or freeze work. Update generated progression through its source tables. Ground navigation remains authoritative between climb links; a physical barricade alone is not an AI route solution.

Verify: no construction input or timer advances after cutoff; shopping keeps the clock running; pause freezes all simulation; incomplete jobs stay inactive; capacity and material refunds settle exactly once; combat relocation cannot bypass the cutoff; ladder routes stay reachable; launches respect mass, boundaries, and kill ownership; and a new wave sweeps only old parts before spawning new loot. Saving/reloading progression must preserve banked parts and refunds without duplicating deployed copies.

Use normal-speed playtests with equal progression budgets, several farm seeds, and no debug assists. Measure voluntary upper-level visits before a repair warning, time spent using elevated combat, route-to-action time, spontaneous cable use, construction completion, loot left at cutoff, grain retained, and each failure's cause. Compare ground and elevated placements using the same item, and test an intentionally wrong-gate bet. Do not infer fun from the presence of a climbing animation or a purchased zipline perk.

**The first proof should be a climber, a catwalk spring, and a useful route between two fights.** That establishes a reason to go upward. Then timed construction, decoys, and barricades turn those positions into risky intermission investments, with the siren preserving the surprise.
