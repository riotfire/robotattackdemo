class_name WeaponHolder
extends Node3D
## The farmer's weapons (GDD 6.1: every unlocked weapon is carried at once). Its Weapon children are
## found at setup and ordered by WeaponData.slot. Handles switching (number keys 1-6, the mouse wheel and
## the weapon wheel), melee bonks, firing and reloading. The Farmer calls physics_step() each frame.
## Weapon wheel (GDD 5.2): tap Q / (Y) to swap to the last weapon; hold it to open the wheel, point with
## the mouse or left stick, and let go to equip. Look input steers the wheel instead of the camera while
## it's open, and nothing fires; the farmer keeps moving (no slow-motion, so co-op stays fair).

signal equipped(weapon: Weapon)

## Holding the wheel button longer than this opens the wheel; a shorter tap swaps to the last weapon.
const WHEEL_HOLD_TIME: float = 0.2
## Positions round the wheel: slot 1 at the top, then clockwise.
const WHEEL_SLOTS: int = 6
## Pointer deflection (0-1) needed to change the wheel's choice.
const WHEEL_DEADZONE: float = 0.35
const SLOT_ACTIONS: Array[StringName] = [&"weapon_1", &"weapon_2", &"weapon_3", &"weapon_4", &"weapon_5", &"weapon_6"]

## The weapon V / (R3) bonks with, whatever is equipped.
@export var melee_weapon_id: StringName = &"wrench"

var farmer: Farmer
## Ordered by slot.
var weapons: Array[Weapon] = []
var current: Weapon = null
## What tapping the wheel button swaps back to.
var previous: Weapon = null
var wheel_open: bool = false
## The weapon the wheel points at while it's open.
var wheel_choice: Weapon = null

var _wheel_held: float = 0.0
var _was_available: Dictionary[Weapon, bool] = {}


func setup(owner_farmer: Farmer) -> void:
	farmer = owner_farmer
	weapons.clear()
	for child in get_children():
		var weapon := child as Weapon
		if weapon != null and weapon.data != null:
			weapons.append(weapon)
			weapon.setup(farmer)
	weapons.sort_custom(func(a: Weapon, b: Weapon) -> bool: return a.data.slot < b.data.slot)
	for weapon in weapons:
		_was_available[weapon] = weapon.is_available()
	_equip_now(_best_available())
	StatService.stats_changed.connect(_on_stats_changed)


func get_weapon(id: StringName) -> Weapon:
	for weapon in weapons:
		if weapon.data.id == id:
			return weapon
	return null


func in_slot(slot: int) -> Weapon:
	for weapon in weapons:
		if weapon.data.slot == slot:
			return weapon
	return null


## Equips `weapon` if the farmer has it; otherwise says where to get it. Returns true if it's in hand.
func equip(weapon: Weapon) -> bool:
	if weapon == null or weapon not in weapons:
		return false
	if not weapon.is_available():
		EventBus.hud_message.emit("Buy the %s at the tool shed pegboard first" % weapon.display_name, 2.0)
		return false
	_equip_now(weapon)
	return true


func equip_slot(slot: int) -> bool:
	return equip(in_slot(slot))


## Tap Q / (Y): back to the weapon used before this one.
func swap_to_previous() -> bool:
	if previous == null or previous == current or not previous.is_available():
		return false
	return equip(previous)


## Next (step 1) or previous (step -1) available weapon in slot order.
func cycle(step: int) -> void:
	var index := weapons.find(current)
	for i in range(1, weapons.size()):
		var candidate := weapons[posmod(index + step * i, weapons.size())]
		if candidate.is_available():
			equip(candidate)
			return


func physics_step(delta: float) -> void:
	var input := farmer.input
	_update_wheel(delta)
	if wheel_open:
		return
	for i in SLOT_ACTIONS.size():
		if input.is_just_pressed(SLOT_ACTIONS[i]):
			equip_slot(i + 1)
	if input.is_just_pressed(&"weapon_next"):
		cycle(1)
	elif input.is_just_pressed(&"weapon_prev"):
		cycle(-1)

	if not farmer.can_use_weapons():
		return
	var melee := get_weapon(melee_weapon_id)
	if input.is_just_pressed(&"melee") and melee != null and usable_now(melee):
		if melee.attack():
			farmer.face_combat(0.5)
	var fire_pressed := input.is_just_pressed(&"fire")
	var fire_held := input.is_pressed(&"fire")
	if fire_held:
		farmer.face_combat(0.6)
	if current == null:
		return
	if usable_now(current):
		current.trigger(fire_pressed, fire_held)
	if input.is_just_pressed(&"reload") and farmer.repair.target == null and farmer.interaction.focus == null:
		current.reload()


## While ziplining only weapons marked usable_on_zipline work (the pistol), unless Zipline Grip 2 is
## owned (GDD 13.4).
func usable_now(weapon: Weapon) -> bool:
	if farmer.state != Farmer.State.ZIPLINING:
		return true
	return weapon.data.usable_on_zipline or StatService.has_flag(&"zipline.any_weapon")


# --- Weapon wheel ---------------------------------------------------------------------------------

## The wheel slot (1-6) a pointer (x right, y down, length 0-1) points at, or 0 inside the deadzone.
static func slot_at(pointer: Vector2) -> int:
	if pointer.length() < WHEEL_DEADZONE:
		return 0
	var angle := fposmod(atan2(pointer.x, -pointer.y), TAU)  # 0 at the top, growing clockwise.
	return posmod(roundi(angle / (TAU / WHEEL_SLOTS)), WHEEL_SLOTS) + 1


## The carried weapon whose wheel position is nearest the pointer, or null inside the deadzone.
func weapon_at(pointer: Vector2) -> Weapon:
	var slot := slot_at(pointer)
	if slot == 0:
		return null
	var best: Weapon = null
	var best_steps := WHEEL_SLOTS
	for weapon in weapons:
		var steps := absi(weapon.data.slot - slot)
		steps = mini(steps, WHEEL_SLOTS - steps)
		if steps < best_steps:
			best_steps = steps
			best = weapon
	return best


## Closes the wheel; equips its choice if `select`.
func close_wheel(select: bool) -> void:
	if not wheel_open:
		return
	wheel_open = false
	farmer.input.look_locked = false
	if select and wheel_choice != null and wheel_choice != current:
		equip(wheel_choice)
	wheel_choice = null


func _update_wheel(delta: float) -> void:
	var input := farmer.input
	if input.is_pressed(&"weapon_wheel"):
		_wheel_held += delta
		if not wheel_open and _wheel_held >= WHEEL_HOLD_TIME:
			wheel_open = true
			wheel_choice = current
			input.look_locked = true
		if wheel_open:
			var pointed := weapon_at(input.wheel_pointer())
			if pointed != null:
				wheel_choice = pointed
		return
	if wheel_open:
		# Let go: equip the choice. If input was taken away (pegboard, console), just close.
		close_wheel(input.enabled)
	elif _wheel_held > 0.0 and input.enabled:
		swap_to_previous()
	_wheel_held = 0.0


# --- Internals ------------------------------------------------------------------------------------

func _equip_now(weapon: Weapon) -> void:
	if weapon != current:
		if current != null:
			previous = current
		current = weapon
	for w in weapons:
		w.set_equipped(w == current)
	equipped.emit(current)


## The highest-slot weapon the farmer has (the pistol over the wrench).
func _best_available() -> Weapon:
	for i in range(weapons.size() - 1, -1, -1):
		if weapons[i].is_available():
			return weapons[i]
	return null


## A weapon just bought goes straight into the farmer's hands; one taken away (a profile reset) is
## swapped for the best one left.
func _on_stats_changed() -> void:
	var unlocked: Weapon = null
	for weapon in weapons:
		var available := weapon.is_available()
		if available and not _was_available.get(weapon, false):
			unlocked = weapon
		_was_available[weapon] = available
	if unlocked != null:
		_equip_now(unlocked)
	elif current == null or not current.is_available():
		_equip_now(_best_available())
