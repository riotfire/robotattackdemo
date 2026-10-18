class_name Zipline
extends Interactable
## A zipline (GDD 4.5): Interact at the high end to grab on and slide to the low end at 12 m/s.
## Jump lets go early. You can fire the pistol while riding (any weapon with Zipline Grip 2).
## The node sits at the cable's start; the child "End" marker is the cable's end.

## How far below the cable the rider's feet hang.
@export var hang_height: float = 1.95
@export var speed: float = 12.0

@onready var _end: Marker3D = $End


func _ready() -> void:
	super._ready()
	if prompt == "Interact":
		prompt = "Ride the zipline"


func interaction_point() -> Vector3:
	return start_point() - Vector3.UP * hang_height


func start_point() -> Vector3:
	return global_position


func end_point() -> Vector3:
	return _end.global_position


func length() -> float:
	return start_point().distance_to(end_point())


func direction() -> Vector3:
	return (end_point() - start_point()).normalized()


## Where the rider's feet are after `distance` meters along the cable.
func rider_position(distance: float) -> Vector3:
	return start_point() + direction() * clampf(distance, 0.0, length()) - Vector3.UP * hang_height


func ride_speed() -> float:
	return StatService.get_stat(&"zipline.speed", speed)


func can_interact(farmer: Farmer) -> bool:
	return farmer.state == Farmer.State.GROUNDED


func interact(farmer: Farmer) -> void:
	farmer.movement.start_zipline(self)
