class_name PerchQuery
extends RefCounted
## Projects unreachable farmers onto ground beside their perch. RobotTargeting owns the give-up clock;
## ranged and climbing subclasses retain their existing reach rules.

const CLIMB_REACH: float = 2.5


static func is_perched(robot_feet: Vector3, target_feet: Vector3) -> bool:
	return target_feet.y - robot_feet.y > CLIMB_REACH


static func stand_spot(target: Vector3, ground_y: float) -> Vector3:
	return Vector3(target.x, ground_y, target.z)


## Stop outside the wall, rather than handing the navmesh a point inside the building. The closest
## navmesh point to an interior ground projection can be an unreachable roof island on a wide building.
## Queried at the normal repath interval, with world geometry only (no robots or defense targets).
static func reachable_stand(robot: Robot, target: Vector3) -> Vector3:
	var goal := stand_spot(target, robot.global_position.y)
	var height := Vector3.UP * 0.5
	var query := PhysicsRayQueryParameters3D.create(robot.global_position + height, goal + height, 1)
	var hit := robot.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var point: Vector3 = hit["position"]
		var normal: Vector3 = hit["normal"]
		normal.y = 0.0
		goal = stand_spot(point + normal.normalized() * (robot.archetype.body_radius + 0.5), robot.global_position.y)
	return goal
