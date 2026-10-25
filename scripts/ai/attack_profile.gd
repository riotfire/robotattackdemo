class_name AttackProfile
extends Resource
## One robot ranged attack (M2-B7): how it charges, flies and hits, and which telegraph it shows. Generated
## in data/robots/attacks from the data/source/robots/attacks table by tools/build_robot_data.gd; an
## archetype names its profile in ranged_attack_id. RangedAttack fires it.
##
## Every shot charges a glow first (never under MIN_CHARGE_TIME). On top of that, lobs show a chalk circle
## where they will land, rails a red-yarn aim line and bombs a shadow circle (GDD 9.6 fairness rules).

## STRAIGHT: a shot along a straight line. LOB: an arc that never leads its target. RAIL: a near-instant
## shot along an aim line that a farmer standing in it blocks. BOMB: dropped from above.
enum Kind { STRAIGHT, LOB, RAIL, BOMB }

## No shot charges for less than this, whatever scaling and traits do (fairness rule).
const MIN_CHARGE_TIME: float = 0.45

@export var id: StringName = &""
@export var kind: Kind = Kind.STRAIGHT
## Glow before each shot (the attack windup).
@export var charge_time: float = 0.9
## Seconds from one attack to the next, charge included.
@export var interval: float = 2.8
@export var damage_vs_farmer: float = 4.0
@export var damage_vs_silo: float = 8.0
## Flight speed in m/s; horizontal speed for lobs.
@export var speed: float = 20.0
## Downward pull on the shot, m/s². Lobs and bombs fall; straight shots and rails don't.
@export var gravity: float = 0.0
## It shoots a farmer only within this distance; rails reach this far.
@export var attack_range: float = 24.0
## Aim this high above a farmer's feet and above the silo's base.
@export var aim_height_farmer: float = 1.0
@export var aim_height_silo: float = 8.0
## 0 = direct hits only.
@export var splash_radius: float = 0.0
## Shots per attack, volley_gap seconds apart.
@export var volley: int = 1
@export var volley_gap: float = 0.25
## Rails stop following their target this long before they fire, so a farmer can step out of the line.
@export var aim_lock_time: float = 0.4
@export var projectile_radius: float = 0.2
@export var color: Color = Color(1.0, 0.45, 0.1)


static func resource_path_for(profile_id: StringName) -> String:
	return RobotArchetype.ATTACK_DIR.path_join("%s.tres" % profile_id)


## The charge time after a multiplier (scaling, traits), never under MIN_CHARGE_TIME.
func effective_charge_time(multiplier: float = 1.0) -> float:
	return maxf(MIN_CHARGE_TIME, charge_time * multiplier)


## The extra telegraph this kind shows on top of the charge glow: &"landing_circle", &"aim_line",
## &"bomb_shadow", or &"" for straight shots.
func telegraph() -> StringName:
	match kind:
		Kind.LOB:
			return &"landing_circle"
		Kind.RAIL:
			return &"aim_line"
		Kind.BOMB:
			return &"bomb_shadow"
	return &""
