# Gameplay responsiveness audit — 2026-10-31

The strongest explanation for the reported **general choppiness throughout** is uneven frame delivery with VSync disabled. Controlled runtime tests became substantially more consistent when VSync was enabled, with the same scene and visual detail. The intentional 24 Hz player animation and 12 Hz robot animation add a separate stepped appearance. Ordinary animation processing is inexpensive; lowering character detail did not materially improve the original baseline.

There are also two reproducible combat feedback defects, deliberate combat slowdowns, and a genuine hitch under extreme explosion load. Those explain specific moments, rather than continuous choppiness while traversing an empty farm.

This was a diagnostic investigation. Production code, project settings, the player's profile, and saved preferences were preserved. Three reusable probe scenes and their evidence were added.

## Frame pacing is the first thing to address

[project.godot:39](</Users/DH_1/Code/Claude Game Test/project.godot:39>) explicitly sets VSync to disabled. There is no configured frame cap. The renderer is Forward+/Metal, with 3D resolution already scaled to 50%.

The most controlled comparison traversed the same 360 camera angles in each configuration; the diagnostic window reported focused at the end of each sample. Median draw calls were 669 and maximum draw calls 1,341 in all three main comparisons. No new pipelines compiled during these samples.

| Runtime configuration | Average callback FPS | Interval standard deviation | 95th percentile interval | 99th percentile interval | Worst interval |
|---|---:|---:|---:|---:|---:|
| Current: VSync off, uncapped | 142.9 | 4.79 ms | 17.20 ms | 19.39 ms | 29.26 ms |
| VSync on, uncapped | 120.0 | 0.95 ms | 9.85 ms | 10.11 ms | 10.21 ms |
| Restore VSync off, uncapped | 166.7 | 4.37 ms | 15.89 ms | 18.92 ms | 30.66 ms |
| VSync off, capped at 60 | 60.0 | 0.36 ms | 17.42 ms | 17.70 ms | 17.93 ms |
| VSync off, all 3D rendering disabled | 170.0 | 4.69 ms | 16.59 ms | 17.51 ms | 26.09 ms |

The important result is consistency, rather than the largest average FPS. Uncapped rendering submits many fast frames mixed with substantially slower ones. VSync produces approximately one frame every 8.33 ms on this screen. Restoring the original configuration brings the irregularity back. A 60 FPS cap also produces consistent intervals, at a lower update rate. Removing all 3D rendering leaves much of the unevenness intact, which argues against character complexity or farm shading being its sole cause.

An earlier constant-speed camera test independently showed a 99th percentile improvement from **30.42 ms to 10.49 ms** with VSync enabled. The first baseline run delivered approximately 60 callback FPS; subsequent uncapped runs delivered much higher averages. That variability is another reason a single FPS counter is misleading. Reducing render scale from 0.5 to 0.25 did not match the consistency achieved by synchronization.

**Recommendation:** enable VSync first and repeat the moving-camera and populated-wave checks. Test the exported build on the intended displays as well. Retain a frame-cap option if desired. There is no evidence here that increasing run speed or reducing model detail would solve the whole-scene problem.

The behavior resembles reported macOS/Metal pacing problems, but the measurements do not identify a particular engine or OS defect. This host runs macOS **15.7.7**, so the analogous [Godot issue concerning macOS 26](https://github.com/godotengine/godot/issues/110600) is background context, not proof of the same cause. There are also [macOS reports of unexpected frame caps with VSync disabled](https://github.com/godotengine/godot/issues/105699).

## Animation cadence adds visible choppiness without a large CPU cost

The [stop-motion clock](</Users/DH_1/Code/Claude Game Test/scripts/autoload/stop_motion_clock.gd:21>) emits player pose updates at 24 Hz and robot pose updates at 12 Hz. Mabel therefore holds each skeletal pose for about **41.7 ms**, even when the camera renders at 120 FPS. Robots hold poses for about **83.3 ms**. At a 60 FPS render rate, 24 Hz poses alternate approximately 33/50 ms holds. Clay surfaces also change at 12 Hz, although their default displacement is small.

The [player pose transition](</Users/DH_1/Code/Claude Game Test/scripts/player/mabel_model.gd:365>) adds a 150 ms snapshot cross-fade. A new action can wait up to 41.7 ms for the next pose tick; the new pose becomes dominant approximately 42–83 ms after the triggering event and completes its blend approximately 125–167 ms afterward. Those are presentation timings, not delays before physics accepts input.

| Same stationary farm view | Median interval | 95th percentile interval |
|---|---:|---:|
| Mabel running pose | 16.65 ms | 25.28 ms |
| Mabel pose evaluation disconnected | 16.68 ms | 25.37 ms |
| Clay model, pose evaluation disconnected | 16.64 ms | 25.15 ms |

A separate CPU microbenchmark measured `MabelModel.step_pose()` at approximately **0.010 ms normally**, or **0.023 ms** with forced alternating transitions. This excludes rendering and GPU work. Together with the rendered A/B, it argues against normal skeletal pose evaluation being the main performance bottleneck.

**Recommendation after pacing:** compare the existing 24 Hz look with a correctly time-scaled 60 Hz player-pose mode, while keeping world motion and camera smooth. Shorter action-specific blends would also improve immediacy. Simply disabling `StopMotionClock` freezes Mabel; it is not a smooth-animation comparison.

## The underlying controls respond promptly

The headless input probe runs the actual Farmer, InputRouter, movement and weapon components on a generated floor at 60 physics ticks per second. Input is injected immediately before simulation, so these measurements exclude mouse/keyboard hardware, OS input delivery, render queues, and display latency.

| Behavior | Observed result |
|---|---|
| Movement begins | First injected physics tick |
| Jump begins | First tick; approximately 0.12 m upward displacement |
| Ready wrench and pistol fire | First expected physics tick |
| Reach default 7 m/s run speed | 7 ticks / 116.7 ms |
| Stop from full speed | 7 ticks / 116.7 ms; travels 0.35 m |
| Reverse from full forward to full backward | 14 ticks / 233.3 ms |
| Complete 90% of a 90-degree body turn | 10 ticks / 166.7 ms |
| Aim movement speed | 4 m/s, 43% below normal running |

The [physics sequence](</Users/DH_1/Code/Claude Game Test/scripts/player/farmer.gd:101>) does not wait for animation completion. The [camera](</Users/DH_1/Code/Claude Game Test/scripts/player/farmer_camera.gd:66>) applies mouse look every rendered frame and follows the interpolated player transform. Normal yaw and pitch are not smoothed. Aim zoom and shoulder transitions do ease over time.

Acceleration, pose blending, body facing and camera zoom overlap. Their durations must not be added into one claimed input-latency number. They affect weight and visual feedback, but do not explain continuous whole-scene frame irregularity.

## Combat defects and deliberate slowdowns

**Repeated upgraded wrench attacks can freeze Mabel's full-body pose.** [Mabel's fire callback](</Users/DH_1/Code/Claude Game Test/scripts/player/mabel_model.gd:156>) resets a 0.5-second melee timer, but `_play()` skips restarting an already-current slash. At Swing Speed rank 4 or 5, another hit arrives before the melee state expires. The non-looping slash reaches its final pose and stays there while attacks continue.

The isolated real-component reproduction ran for three simulated seconds, using the normal weapon cooldown and 24 Hz pose path, with no cooldown resets:

| Swing Speed rank | Successful attacks | Terminal slash poses out of 72 |
|---|---:|---:|
| 0 | 5 | 0 |
| 4 | 7 | 25 |
| 5 | 7 | 61 |

At rank 5, the body reaches the terminal pose at 0.5 seconds and remains there for the rest of the sample. The weapon's own Pivot tween and damage continue. Restarting the action clip on each accepted attack is a targeted fix.

**Quick melee discards early presses.** [V/R3 handling](</Users/DH_1/Code/Claude Game Test/scripts/weapons/weapon_holder.gd:123>) calls `attack()` only on the press. Pressing 91.7 ms before the cooldown expires produced no second attack, even after waiting well past readiness. An equivalent pistol click 100 ms early was buffered and fired. Matching the existing 150 ms weapon press buffer would make quick melee more forgiving.

The wrench's tool tween lasts 320 ms, its full-body reaction approximately 500 ms, and its base repeat interval measured 633 ms. These different recovery cues reinforce inconsistent expectations. A secondary cooldown boundary issue also makes a nominal 250 ms pistol interval measure 266.7 ms at 60 Hz.

Other presentation mismatches are visible in the code: melee replaces running legs for 0.5 seconds while movement continues; the run clip's rate cap implies approximately 6.38 m/s foot motion against a 7 m/s body; maul/scythe whole-body reactions begin when damage lands, after their 420/180 ms windups. These can look like sliding or late response.

**Hitstop is actual, intentional world slowdown.** [Hitstop](</Users/DH_1/Code/Claude Game Test/scripts/util/hitstop.gd:17>) sets global time to 3% for 45 ms on kill streaks, 65 ms on large kills, and 85 ms on Foremen. Movement and cooldowns slow along with animation. Controller camera look uses scaled delta and slows as well; mouse look does not. This explains brief combat hesitation, not choppiness during an empty-farm camera sweep. An independent hitstop toggle or reduced duration would allow a useful comparison without changing animation cadence.

## Explosions can hitch, but ordinary small bursts were much closer to baseline

These samples blocked hitstop directly while preserving normal visual effects. Every recorded death-burst frame had `time_scale=1`, and no death-burst sample compiled new pipelines.

| Simultaneous kills | 95th percentile interval | 99th percentile interval | Worst interval |
|---|---:|---:|---:|
| 3 Nibblers | 25.25 ms | 35.79 ms | 37.49 ms |
| 6 Nibblers | 26.89 ms | 35.18 ms | 35.97 ms |
| 12 Nibblers | 27.38 ms | 33.42 ms | 34.85 ms |
| 60 mixed robots, deliberately extreme | 28.57 ms | 49.09 ms | **102.37 ms** |

The smaller cases are near this run's already uneven baseline. The extreme case has adjacent frames of approximately 48, 84, 102 and 49 ms, so it is a real burst hitch. A sampled engine physics maximum reached 50.13 ms. The synchronous 60-robot kill loop itself took another 8.72 ms before the frame sample began.

[Robot explosions](</Users/DH_1/Code/Claude Game Test/scripts/vfx/robot_explosion.gd:244>) create 29–46 cosmetic pieces per explosion before original debris, bolts, flash/ring, and loot. The global debris budget does not cap most small cosmetic pieces. Moving original debris raycasts each physics tick and retains its shadow setting. Budgeting/pooling those pieces, stopping debris shadows, and reducing debris collision work are plausible optimization targets; the investigation did not separately attribute each one's cost.

First appearance also has residual work: the first three Nibblers took 36.87 ms of synchronous spawn work and added 20 pipelines across creation/rendering; a later six-Nibbler batch took 3.35 ms and added none. Boot warm-up does not draw representative robots. The existing first-kill regression passed both kills with zero new pipelines and approximately 0.45 ms kill CPU time, so ordinary death-pipeline compilation was not reproduced as the main issue.

## Recommended order

1. Enable VSync and validate scene-wide pacing on target displays. This is the strongest measured response to the user's stated symptom.
2. Compare player animation cadence and action blending after pacing is consistent. Keep the clay style as a deliberate visual choice rather than conflating it with engine performance.
3. Fix slash retriggering and buffer quick melee. These are reproducible defects independent of the pacing choice.
4. Offer an isolated hitstop comparison, warm representative robot appearances, and budget explosion work for dense encounters.
5. Revisit movement acceleration or run speed only after these changes. Current evidence does not justify using faster movement to mask choppy frame delivery.

## Reproduction and measurement limits

Hardware/software: Apple M4 Pro, Godot 4.7.2 official, macOS 15.7.7, Metal Forward+, 1600×900 window/viewport, 0.5 3D render scale, 120 Hz reported display, seed 42. Diagnostic settings changes were process-local and saves used disposable `/tmp` profiles.

Use the Godot binary at `/Users/DH_1/Downloads/Godot.app/Contents/MacOS/Godot` from the project folder:

```sh
# Original animation/60-robot stress comparison; use real time, without --fixed-fps.
godot --path . --resolution 1600x900 res://tests/tools/responsiveness_probe.tscn -- --profile=/tmp/audit-profile.json --out=/tmp/audit-rendered

# Smaller death bursts.
godot --path . --resolution 1600x900 res://tests/tools/responsiveness_probe.tscn -- --profile=/tmp/audit-profile.json --out=/tmp/audit-bursts --bursts-only

# Matched-angle pacing comparison, including restoration and no-3D control.
godot --path . --always-on-top --resolution 1600x900 res://tests/tools/responsiveness_probe.tscn -- --profile=/tmp/audit-profile.json --out=/tmp/audit-pacing --pacing-only --pacing-confirm

# Actual control components, fixed simulation steps.
godot --headless --path . --fixed-fps 60 res://tests/tools/input_latency_probe.tscn -- --profile=/tmp/audit-input-profile.json --out=/tmp/audit-input.json

# Isolated repeated slash reproduction and CPU microbenchmark.
godot --headless --path . res://tests/tools/slash_retrigger_probe.tscn -- --profile=/tmp/audit-slash-profile.json --out=/tmp/audit-slash.json
```

The rendered comparisons, input probe, slash reproduction, and existing first-kill regression completed successfully. Expected headless macOS certificate warnings and existing exit-time ObjectDB leak warnings appeared; no script errors were reported in the completed measurements. A separate headless parse check correctly rejected the rendered probe because it requires graphics.

`wall_ms` records intervals between `process_frame` callbacks. It includes game work, rendering/presentation waits, and scheduling; it is not physical display scanout or measured device-to-photon latency. Average FPS above is `frames / total elapsed`, not the reciprocal of the median interval. Equal-angle pacing samples render the same views at different angular speeds, making them a delivery comparison rather than a matched-speed subjective playtest.

Godot 4.7.2 publishes process/physics monitors as **one-second maxima**, not individual CPU frame samples. Archived JSON labels those observations explicitly; old run logs retain the initial labels. Those repeated monitor values must not be treated as CPU percentile distributions. See the [exact engine update code](https://github.com/godotengine/godot/blob/4.7.2-stable/main/main.cpp#L4743).

The GPU timer returned zero because this [Metal backend does not supply timestamp results](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/metal/rendering_device_driver_metal.cpp#L2108). No claim of negligible GPU work or a conclusively identified GPU bottleneck follows from those zeros. Physics interpolation adds presentation latency as documented by [Godot](https://docs.godotengine.org/en/stable/tutorials/rendering/jitter_stutter.html), but it is already enabled and is not an observed recurring world stall.

Evidence files in this directory contain normalized JSON, frame CSV data saved as `.csv.txt` to avoid Godot's translation importer, and engine logs. The decisive pacing capture is `pacing-matched.json`; `pacing-initial.json` is the earlier constant-angular-speed comparison. `animation-and-stress.json`, `small-bursts.json`, `input-latency.json`, and `slash-retrigger.json` cover the other findings.
