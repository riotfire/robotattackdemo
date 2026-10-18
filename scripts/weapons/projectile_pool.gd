class_name ProjectilePool
extends Node3D
## Reuses Projectile nodes instead of making one per shot (GDD 18.7). One pool per scene, made on first
## use by ProjectilePool.of(); it lives in the world, not in an autoload, so a network host can own it later.

const NODE_NAME: StringName = &"ProjectilePool"

## Projectiles made up front when the pool enters the tree, so the first volley doesn't allocate.
@export var prewarm: int = 24

var _idle: Array[Projectile] = []
var _total: int = 0


## The pool in `context`'s current scene, made on first use.
static func of(context: Node) -> ProjectilePool:
	var tree := context.get_tree()
	var scene := tree.current_scene if tree.current_scene != null else tree.root
	var pool := scene.get_node_or_null(NodePath(NODE_NAME)) as ProjectilePool
	if pool == null:
		pool = ProjectilePool.new()
		pool.name = NODE_NAME
		scene.add_child(pool)
	return pool


func _ready() -> void:
	for i in prewarm:
		_idle.append(_make())


## Fires a projectile from `from` at `launch_velocity`. `on_hit(hit: Dictionary) -> bool` is called for
## each thing it hits (an intersect_ray result); return true to fly on through it. It retires after
## `lifetime` seconds or on a hit that stops it.
func launch(from: Vector3, launch_velocity: Vector3, gravity: float, lifetime: float, mask: int, exclude: Array[RID],
		on_hit: Callable, color: Color = Color(1.0, 0.85, 0.45), radius: float = 0.06) -> Projectile:
	var projectile: Projectile = _idle.pop_back() if not _idle.is_empty() else _make()
	projectile.launch(self, from, launch_velocity, gravity, lifetime, mask, exclude, on_hit, color, radius)
	return projectile


func release(projectile: Projectile) -> void:
	if projectile not in _idle:
		_idle.append(projectile)


func active_count() -> int:
	return _total - _idle.size()


func total_count() -> int:
	return _total


func _make() -> Projectile:
	var projectile := Projectile.new()
	add_child(projectile)
	_total += 1
	return projectile
