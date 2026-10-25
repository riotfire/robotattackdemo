class_name Hitstop
extends RefCounted
## Freeze frames for big moments (a Heavy or Foreman popping, a multi-kill). The world nearly stops for
## 50–90 ms so the blow reads as heavy, then snaps back. Reduce Motion turns it off.
## The weapon wheel's slow-mo owns Engine.time_scale while it is open, so a freeze never starts then;
## the wheel asks resting_time_scale() so a freeze in progress is never saved as its "before" value.

const FROZEN_SCALE: float = 0.03
## Real seconds after a freeze ends before another may start, so a crowd of kills doesn't stutter.
const COOLDOWN: float = 0.3

static var _frozen: bool = false
static var _resting: float = 1.0
static var _ready_at_msec: int = 0


static func freeze(seconds: float) -> void:
	if seconds <= 0.0 or _frozen or bool(SaveManager.settings.get("reduce_motion", false)):
		return
	if Time.get_ticks_msec() < _ready_at_msec or Engine.time_scale < 0.999:
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	_frozen = true
	_resting = Engine.time_scale
	Engine.time_scale = FROZEN_SCALE
	_ready_at_msec = Time.get_ticks_msec() + int((seconds + COOLDOWN) * 1000.0)
	# Real time, and still counting while paused, so the game can never be left frozen.
	tree.create_timer(seconds, true, false, true).timeout.connect(_release)


static func is_frozen() -> bool:
	return _frozen


## Engine.time_scale as it is outside any freeze.
static func resting_time_scale() -> float:
	return _resting if _frozen else Engine.time_scale


static func _release() -> void:
	if not _frozen:
		return
	_frozen = false
	# Something else (the wheel) took over time during the freeze: leave its value alone.
	if is_equal_approx(Engine.time_scale, FROZEN_SCALE):
		Engine.time_scale = _resting
