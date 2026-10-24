# M2-J5 audio foundation

`AudioDirector` is an autoload. It owns two crossfading music players, an eight-voice
SFX pool, and a looping grain-leak ambience player. The bus layout has Master,
Music, SFX, Ambience, and UI buses. The music is the two MP3s in
`assets/audio/music/`; the remaining sounds in `assets/audio/` are original
generated placeholders (run `python3 tools/audio/generate_placeholders.py` to
rebuild them).

The director follows `EventBus.wave_phase_changed`. The siren is the cut between
the two songs in `assets/audio/music/`:

| Phase | Music |
|---|---|
| Intermission, Cleared | *Surveying the Field* |
| Siren | silence while the siren cue sounds |
| Spawning, Mop-up | *Robot Attack Pixel Banjo Defense* |
| Game over | placeholder game-over stem |

- **Before the siren:** the field song fades out against the intermission
  countdown, over the last `PRE_SIREN_FADE_SECONDS` (2 s) before the siren
  starts, so it is silent when the siren sounds. Ringing the bell early cuts it
  in `MUSIC_FADE_SECONDS` instead.
- **After the siren:** once the siren cue has finished, the attack song fades in
  over `POST_SIREN_FADE_SECONDS` (1.5 s), so it is at full level as the robots spawn.
  It starts from the top each wave and loops if a wave runs long.
- **Wave cleared:** the attack song crossfades into the field song over
  `WAVE_END_FADE_SECONDS`, and the field song carries on through the intermission.
- Every fifth wave still has its own `boss` state, but it points at the attack song
  until a dedicated boss track exists.

`siren_started` plays the one-shot siren; `robot_destroyed` plays a pop; crack events
and a slow poll keep the grain leak loop in sync with the silo's live leak rate.
When the silo takes a hit while the farmer is at least 15 m away, the HUD plays the
two-note `silo_alarm` cue. A 9 s cooldown keeps multiple robots from making it repeat
on every strike. The warning banner stays visible after the cue and points back to
the silo; if a leak remains, it becomes an amber repair reminder.

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
