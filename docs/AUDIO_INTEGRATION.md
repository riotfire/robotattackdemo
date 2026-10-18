# M2-J5 audio foundation

`AudioDirector` is an autoload. It owns two crossfading music players, an eight-voice
SFX pool, and a looping grain-leak ambience player. The bus layout has Master,
Music, SFX, Ambience, and UI buses. All sounds in `assets/audio/` are original,
generated placeholders; run `python3 tools/audio/generate_placeholders.py` to
rebuild them.

The director follows `EventBus.wave_phase_changed`: intermission, siren,
spawning, mop-up, cleared, and game over all have music. Every fifth wave uses
the boss combat stem. `siren_started` plays the one-shot siren;
`robot_destroyed` plays a pop; crack events and a slow poll keep the grain
leak loop in sync with the silo's live leak rate.

## M2-A2 integration seam

The farmer/weapon framework is being changed in a separate work package.
When that work is ready, add these calls **after a successful action**:

- Pistol: `AudioDirector.play_cue(&"pistol")` after ammo is consumed.
- Wrench: `AudioDirector.play_cue(&"wrench")` after `swing()` passes its
  cooldown and farmer checks.

Do not fire the cues on raw input: that would play a shot when the weapon
cannot fire. These two WAVs and their bus routing are already in place.
Later weapons can use `play_cue()` with additional entries in `CUES`.

The current one-shot playback is non-positional because these are local
player and objective cues. A later spatial pass can add a separate 3D pool
for distant robot and co-op player sounds without changing the phase logic.
