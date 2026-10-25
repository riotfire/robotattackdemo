class_name AttackTokens
extends RefCounted
## Farmer attack tokens (M2-B7, GDD 9.6 fairness rules): only so many robots may shoot at one farmer at
## once. A RangedAttack takes a token when it starts charging at a farmer and gives it back when its shot
## has landed or missed; a robot that finds none free shoots the silo instead.
## The limit comes from DifficultyCurve.farmer_attack_tokens (2 in the opening).

## Farmer instance id -> the attacks holding one of its tokens.
static var _holders: Dictionary[int, Array] = {}


## Takes one of `farmer`'s tokens for `holder`. True if it got one (or already had one).
static func acquire(farmer: Node, holder: Object, limit: int) -> bool:
	var held := _live_holders(farmer)
	if holder in held:
		return true
	if held.size() >= limit:
		return false
	held.append(holder)
	return true


## Gives back every token `holder` has.
static func release(holder: Object) -> void:
	for key: int in _holders.keys():
		_holders[key].erase(holder)


## How many robots are shooting at `farmer` right now.
static func count(farmer: Node) -> int:
	return _live_holders(farmer).size()


static func clear() -> void:
	_holders.clear()


static func _live_holders(farmer: Node) -> Array:
	var key := farmer.get_instance_id()
	if not _holders.has(key):
		_holders[key] = []
	var held: Array = _holders[key]
	for i in range(held.size() - 1, -1, -1):
		if not is_instance_valid(held[i]):
			held.remove_at(i)
	return held
