extends Node
## Stepped-animation clock (GDD 15.4). Emits 12 Hz and 24 Hz ticks for pose and VFX updates, and steps
## the clay shader's surface "boil" through the clay_boil_frame global shader uniform.
## Gameplay never waits on these ticks: roots, camera, aiming and hitboxes stay at full rate.

signal tick_12(frame: int)
signal tick_24(frame: int)

## Reduce Motion (GDD 20) turns this off, which also freezes the clay boil.
@export var enabled: bool = true:
	set(value):
		enabled = value
		RenderingServer.global_shader_parameter_set(&"clay_boil_enabled", 1.0 if value else 0.0)

var frame_12: int = 0
var frame_24: int = 0
var _accum_12: float = 0.0
var _accum_24: float = 0.0


func _process(delta: float) -> void:
	if not enabled:
		return
	_accum_24 += delta
	while _accum_24 >= 1.0 / 24.0:
		_accum_24 -= 1.0 / 24.0
		frame_24 += 1
		tick_24.emit(frame_24)
	_accum_12 += delta
	while _accum_12 >= 1.0 / 12.0:
		_accum_12 -= 1.0 / 12.0
		frame_12 += 1
		RenderingServer.global_shader_parameter_set(&"clay_boil_frame", float(frame_12 % 997))
		tick_12.emit(frame_12)
