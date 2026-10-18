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

## Weapon cues (M2-A2 seam, wired)

Each weapon's `WeaponData` names its sound in `fire_cue` (a key of
`AudioDirector.CUES`): `pistol` in `data/weapons/pistol.tres`, `wrench` in
`data/weapons/wrench.tres`. `Weapon.begin_shot()`, the shot path every weapon
shares, plays it. Weapons call `begin_shot()` only after a shot or swing has
really started, so the cue plays only on a successful action:

- Pistol: `fire()` spends a round and starts its cooldown, then calls
  `begin_shot()`. No sound plays while it is reloading or on cooldown.
- Wrench: `swing()` passes its cooldown and farmer checks, then calls
  `begin_shot()`, whether or not the swing hits anything.

Cues never play on raw input, so pressing fire when a weapon cannot fire is
silent. `tests/unit/test_weapons.gd` checks this. A new weapon gets its sound
from a `CUES` entry plus a `fire_cue` in its data. Leave `fire_cue` empty for
a silent weapon.

The current one-shot playback is non-positional because these are local
player and objective cues. A later spatial pass can add a separate 3D pool
for distant robot and co-op player sounds without changing the phase logic.

## Shutdown

`AudioDirector._exit_tree()` stops every player. Stopping alone is not enough:
the AudioServer releases a stopped playback only on its next mix step, which
runs on the audio thread. A quit can win that race while music, a cue or the
grain-leak loop is still playing. The AudioServer would then still hold those
playbacks, and their WAVs, at exit. Headless runs report that as leaked
`AudioStreamWAV` and `AudioStreamPlaybackWAV` instances and "resources still
in use at exit". So after stopping, the director waits until a mix step that
started after the stop has finished. That usually takes under 0.1 s, and the
wait is capped at 0.5 s.
