class_name PerchQuery
extends RefCounted
## Perch-aware positioning (GDD 4.4, 4.5, 9.6). Robots can't climb, so a farmer on a perch (a roof,
## catwalk, hayloft, or anything else well above the ground) is out of a ground robot's reach. Melee
## robots wait for a perched farmer at the foot of the perch and give up after a while (BTTrackTarget,
## BTApproach). The ranged classes (M2-B1, M2-B2) are meant to build their firing spots on the same test.
##
## The farm navmesh has rooftops on it as islands robots can't reach. Walking toward the farmer's own
## position would aim the path at the roof under their feet; aiming it at stand_spot() instead makes the
## path end on the robot's own level, at the reachable ground nearest to the spot below the farmer.
## That costs nothing extra: the agent's regular repath does the query.

## A target more than this far above a robot's feet is perched out of its reach (M1's give-up rule).
const CLIMB_REACH: float = 2.5


static func is_perched(robot_feet: Vector3, target_feet: Vector3) -> bool:
	return target_feet.y - robot_feet.y > CLIMB_REACH


## Where a ground robot whose feet are at `ground_y` heads for a farmer perched at `target`: the spot
## straight below them, on the robot's level. Its path ends at the nearest point it can reach.
static func stand_spot(target: Vector3, ground_y: float) -> Vector3:
	return Vector3(target.x, ground_y, target.z)
