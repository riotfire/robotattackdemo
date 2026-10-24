class_name Jetpack
extends Node
## Grandpa's Milk-Can Jetpack (GDD 5.4). Hold Jump in the air to thrust.
## Fuel only recharges while grounded: 0.5 s delay, then empty to full in 2.0 s.
## Built at the shed from wave 3 onward, then kept forever (GameState.jetpack_unlocked).
## The base_* values are GDD 5.4's; Fuel Tank, Quick Refill and Thrusters apply on top via StatService.

signal thrust_changed(thrusting: bool)

## Seconds of thrust. Each Fuel Tank level multiplies this by 1.2.
@export var base_flight_time: float = 1.2
## Vertical speed while thrusting, m/s.
@export var base_climb_rate: float = 6.0
@export var base_air_speed: float = 5.0
## How fast vertical speed is pulled toward the climb rate, m/s^2.
@export var thrust_acceleration: float = 45.0
@export var base_recharge_delay: float = 0.5
@export var base_recharge_time: float = 2.0

var fuel: float = 0.0
var is_thrusting: bool = false
var _grounded_time: float = 0.0


func _ready() -> void:
	fuel = flight_time()


func is_unlocked() -> bool:
	return GameState.jetpack_unlocked


func flight_time() -> float:
	return StatService.get_stat(&"jetpack.flight_time", base_flight_time)


func climb_rate() -> float:
	return StatService.get_stat(&"jetpack.climb_rate", base_climb_rate)


func air_speed() -> float:
	return StatService.get_stat(&"jetpack.air_speed", base_air_speed)


func recharge_delay() -> float:
	return maxf(0.0, StatService.get_stat(&"jetpack.recharge_delay", base_recharge_delay))


func recharge_time() -> float:
	return base_recharge_time / maxf(0.01, StatService.get_stat(&"jetpack.recharge_speed", 1.0))


func fuel_fraction() -> float:
	var full := flight_time()
	return clampf(fuel / full, 0.0, 1.0) if full > 0.0 else 0.0


## Call once per physics step. `drain_scale` < 1 burns fuel slower (Hover Mode).
## Returns true while thrusting this step.
func update(delta: float, grounded: bool, wants_thrust: bool, drain_scale: float = 1.0) -> bool:
	var full := flight_time()
	if grounded:
		_grounded_time += delta
		if _grounded_time >= recharge_delay():
			fuel = minf(full, fuel + full / recharge_time() * delta)
	else:
		_grounded_time = 0.0
	var thrusting := wants_thrust and not grounded and fuel > 0.0 and is_unlocked()
	if thrusting:
		fuel = maxf(0.0, fuel - delta * drain_scale)
	set_thrusting(thrusting)
	return thrusting


func set_thrusting(thrusting: bool) -> void:
	if thrusting != is_thrusting:
		is_thrusting = thrusting
		thrust_changed.emit(thrusting)


func refill() -> void:
	fuel = flight_time()
