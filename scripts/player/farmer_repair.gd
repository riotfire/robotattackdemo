class_name FarmerRepair
extends Node
## Hold Interact next to a silo crack to wrench it shut (GDD 7.1). The wrench is the only repair tool in
## M1; the Auto Wrench and the Welder (GDD 7.2, M2-D1/D2) belong here too.

## Structure per second with the wrench.
@export var repair_rate: float = 20.0
## How close a crack must be to the farmer's chest.
@export var repair_reach: float = 2.5

## The crack in reach, if any (highlighted in the world).
var target: SiloCrack = null
var is_repairing: bool = false

var farmer: Farmer


func setup(owner_farmer: Farmer) -> void:
	farmer = owner_farmer


func physics_step(delta: float) -> void:
	var previous := target
	target = null
	var silo := GameState.silo
	if silo != null and farmer.state == Farmer.State.GROUNDED:
		target = silo.nearest_crack(farmer.global_position + Vector3.UP, repair_reach)
	if previous != target and previous != null and is_instance_valid(previous):
		previous.set_highlighted(false)
	if target != null:
		target.set_highlighted(true)
	is_repairing = target != null and farmer.input.is_pressed(&"interact")
	if is_repairing:
		var to_crack := target.global_position - farmer.global_position
		farmer.facing_yaw = atan2(-to_crack.x, -to_crack.z)
		silo.repair_crack(target, rate_now() * delta)


## Structure per second the wrench restores, after Elbow Grease and Bigger Patches.
func rate_now() -> float:
	return repair_rate * StatService.get_stat(&"repair.speed", 1.0) * StatService.get_stat(&"repair.amount", 1.0)
