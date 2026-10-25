class_name PegboardUI
extends CanvasLayer
## The upgrade pegboard (GDD 13.1, 17.3), opened at the tool shed door during intermissions.
## One board per branch; each node is a peg showing its name, level pips and next cost (have/need), with
## red yarn to its prerequisites. Fill colour says what you have or can get (green owned, cream available,
## grey locked); the ring says whether you can afford the next level now (gold) or are short on parts (red).
## Controller: D-pad or left stick moves the cursor across every branch, hold A to buy, B or Start closes.
## The intermission timer keeps running while it's open, and it closes itself when the shed shutters for
## the wave. Graybox 2D overlay; the 3D pegboard dolly comes later.

## The board was shut (by the player, or by the shutters coming down).
signal closed

const CELL := Vector2(236.0, 112.0)
const PEG_SIZE := Vector2(212.0, 88.0)
## Tab order. One branch shows at a time, so every board fits without scrolling.
const BRANCH_ORDER: Array[int] = [UpgradeNode.Branch.ATTACK, UpgradeNode.Branch.DEFEND, UpgradeNode.Branch.REPAIR,
	UpgradeNode.Branch.TRAVEL, UpgradeNode.Branch.FARMHAND]
const PART_SHORT: Dictionary[StringName, String] = {&"al": "Al", &"cu": "Cu", &"au": "Au", &"pc": "PC"}
const CARDBOARD := Color(0.55, 0.41, 0.28)
const CARDBOARD_DARK := Color(0.36, 0.26, 0.17)
const HOLE := Color(0.27, 0.19, 0.12, 0.45)
const YARN := Color(0.82, 0.18, 0.14)
## Peg fill: finished (green), buyable now or later (cream), not reachable yet (dark).
const FILL_DONE := Color(0.63, 0.82, 0.52)
const FILL_OPEN := Color(0.96, 0.9, 0.76)
const FILL_LOCKED := Color(0.4, 0.3, 0.21)
## A gold edge marks every peg you can buy right now.
const EDGE_BUY := Color(1.0, 0.78, 0.18)
const EDGE_PLAIN := Color(0.0, 0.0, 0.0, 0.18)
const CURSOR_COLOR := Color(1.0, 1.0, 1.0)
const INK := Color(0.16, 0.1, 0.05)
const INK_SOFT := Color(0.16, 0.1, 0.05, 0.6)
const LOCKED_INK := Color(0.85, 0.78, 0.68, 0.55)
const SHORT_INK := Color(0.75, 0.16, 0.1)
const CREAM := Color(1.0, 0.95, 0.85)
## Hold A (or the mouse on a peg) this long to buy, the same as the dinner bell.
const HOLD_TIME: float = 1.0

@export var director: WaveDirector

var is_open: bool = false
var _farmer: Farmer = null
var _root: Control
var _title_label: Label
var _timer_label: Label
var _part_labels: Dictionary[StringName, Label] = {}
var _detail_name: Label
var _detail_text: Label
var _detail_status: Label
var _pegs: Dictionary[StringName, Button] = {}
var _peg_parts: Dictionary[StringName, Dictionary] = {}
var _cursors: Dictionary[StringName, Panel] = {}
var _peg_branch: Dictionary[StringName, int] = {}
var _boards: Dictionary[int, Board] = {}
var _tabs: Dictionary[int, Button] = {}
var _branch: int = UpgradeNode.Branch.ATTACK
## The peg the cursor is on; reopening the board starts here.
var _focus_id: StringName = &""
var _hold_bar: ProgressBar
## The peg being held for purchase, how long it's been held, and whether a buy needs a fresh press.
var _hold_id: StringName = &""
var _hold_time: float = 0.0
var _needs_release: bool = false
## The peg the mouse button went down on, if it's still held.
var _mouse_hold_id: StringName = &""
var _opened_frame: int = 0


## One branch's board: the pegs plus the red yarn between them and their prerequisites.
class Board:
	extends Control

	## Pairs of rects: prerequisite peg, then the peg that needs it.
	var links: Array[Rect2] = []

	func _draw() -> void:
		for i in range(0, links.size(), 2):
			var points := _route(links[i], links[i + 1])
			draw_polyline(points, Color(0, 0, 0, 0.25), 6.0, true)
			draw_polyline(points, PegboardUI.YARN, 3.0, true)
			draw_circle(points[0], 4.5, PegboardUI.YARN)
			draw_circle(points[points.size() - 1], 4.5, PegboardUI.YARN)

	## Runs the yarn along the gutters between pegs so it never cuts across one: down into the gutter
	## below the prerequisite, along it, then into the top of the peg below (or, for a peg further down,
	## down the gutter beside it and into its side). Pegs in the same row are joined side to side.
	static func _route(from: Rect2, to: Rect2) -> PackedVector2Array:
		var gutter := PegboardUI.CELL - PegboardUI.PEG_SIZE
		if to.position.y < from.end.y:
			var a := Vector2(from.end.x, from.get_center().y)
			var b := Vector2(to.position.x, to.get_center().y)
			var mid := (a.x + b.x) * 0.5
			return PackedVector2Array([a, Vector2(mid, a.y), Vector2(mid, b.y), b])
		var start := Vector2(from.get_center().x, from.end.y)
		var bus := from.end.y + gutter.y * 0.5
		if to.position.y - from.end.y < PegboardUI.CELL.y:
			return PackedVector2Array([start, Vector2(start.x, bus), Vector2(to.get_center().x, bus),
					Vector2(to.get_center().x, to.position.y)])
		var lane := to.position.x - gutter.x * 0.5
		return PackedVector2Array([start, Vector2(start.x, bus), Vector2(lane, bus),
				Vector2(lane, to.get_center().y), Vector2(to.position.x, to.get_center().y)])


## The cardboard backdrop with its grid of peg holes.
class Holes:
	extends Control

	func _draw() -> void:
		var step := 26.0
		var y := step * 0.5
		while y < size.y:
			var x := step * 0.5
			while x < size.x:
				draw_circle(Vector2(x, y), 3.0, PegboardUI.HOLE)
				x += step
			y += step


## Level pips: filled for levels bought, hollow for the rest.
class Pips:
	extends Control

	var level: int = 0
	var max_level: int = 1
	var color: Color = Color.BLACK

	func _draw() -> void:
		for i in max_level:
			var at := Vector2(5.0 + i * 13.0, size.y * 0.5)
			if i < level:
				draw_circle(at, 4.5, color)
			else:
				draw_arc(at, 4.0, 0.0, TAU, 16, Color(color, 0.45), 1.5, true)


func _ready() -> void:
	layer = 5
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_root.visible = false
	StatService.stats_changed.connect(_refresh)
	EventBus.parts_changed.connect(func(_parts: Dictionary) -> void: _refresh())
	EventBus.wave_phase_changed.connect(_on_wave_phase_changed)
	_connect_sheds.call_deferred()


func _connect_sheds() -> void:
	for node in get_tree().get_nodes_in_group(ToolShed.GROUP_SHED):
		var shed := node as ToolShed
		if not shed.pegboard_requested.is_connected(open):
			shed.pegboard_requested.connect(open)


func open(farmer: Farmer) -> void:
	if is_open:
		return
	is_open = true
	_opened_frame = Engine.get_process_frames()
	_farmer = farmer
	_set_player_input(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_root.visible = true
	_focus_id = _starting_peg()
	_show_branch(_peg_branch.get(_focus_id, _branch))
	_refresh()
	_focus_peg(_focus_id)


func close() -> void:
	if not is_open:
		return
	is_open = false
	_root.visible = false
	_set_player_input(true)
	if not GameState.is_game_over and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	closed.emit()


## A peg's button, for UI effects and navigation.
func peg_button(id: StringName) -> Button:
	return _pegs.get(id)


## Opens with a particular peg selected, used by the first purchase lesson.
func set_opening_peg(id: StringName) -> void:
	if not is_open and _pegs.has(id):
		_focus_id = id


func _set_player_input(enabled: bool) -> void:
	if _farmer != null and is_instance_valid(_farmer):
		_farmer.input.enabled = enabled


func _unhandled_input(event: InputEvent) -> void:
	if not is_open:
		return
	if event.is_action_pressed(&"pause") or event.is_action_pressed(&"interact") or event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


## Board switching runs before the GUI so Tab and the D-pad at a board's edge aren't eaten by focus.
func _input(event: InputEvent) -> void:
	if not is_open:
		return
	var step := 0
	var joy := event as InputEventJoypadButton
	if joy != null and joy.pressed:
		step = -1 if joy.button_index == JOY_BUTTON_LEFT_SHOULDER else (1 if joy.button_index == JOY_BUTTON_RIGHT_SHOULDER else 0)
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.physical_keycode == KEY_TAB:
		step = -1 if key.shift_pressed else 1
	var peg := _pegs.get(_focus_id) as Button
	if step == 0 and peg != null and peg.has_focus():
		if event.is_action_pressed(&"ui_left") and peg.focus_neighbor_left.is_empty():
			step = -1
		elif event.is_action_pressed(&"ui_right") and peg.focus_neighbor_right.is_empty():
			step = 1
	if step != 0:
		get_viewport().set_input_as_handled()
		_switch_branch(step)


func _process(delta: float) -> void:
	if not is_open:
		return
	# Focused UI can swallow ui_accept and ui_cancel before _unhandled_input sees them, so B (and the
	# shed's interact, X) are read from the controller state too, the same way the jump is. The frame the
	# board opened on is skipped, so the press that opened it can't close it again.
	if Engine.get_process_frames() > _opened_frame + 1 and (Input.is_action_just_pressed(&"ui_cancel")
			or Input.is_action_just_pressed(&"interact") or Input.is_action_just_pressed(&"pause")):
		close()
		return
	_update_hold(delta)
	var timing := director != null and director.phase in [WaveDirector.Phase.INTERMISSION, WaveDirector.Phase.SIREN]
	_timer_label.get_parent().get_parent().visible = timing
	if timing:
		_timer_label.text = "Next wave  %s" % Hud._clock(director.time_left)
	for key: StringName in _part_labels:
		_part_labels[key].text = str(GameState.parts[key])


func _on_wave_phase_changed(phase: int, _wave: int) -> void:
	if is_open and phase in [WaveDirector.Phase.SPAWNING, WaveDirector.Phase.GAME_OVER]:
		close()
		EventBus.hud_message.emit("The shed shutters: here they come!", 2.0)


## Buys the next level of a node (also used by tests and the debug console). A refused purchase says why.
func buy(id: StringName) -> bool:
	if not StatService.purchase(id):
		EventBus.hud_message.emit(_refusal_text(id), 2.0)
		return false
	var peg := _pegs.get(id) as Button
	if peg != null:
		# The clay "thwump" (GDD 13.1).
		peg.pivot_offset = peg.size * 0.5
		var tween := create_tween()
		tween.tween_property(peg, ^"scale", Vector2(1.15, 0.85), 0.06)
		tween.tween_property(peg, ^"scale", Vector2(0.95, 1.05), 0.08)
		tween.tween_property(peg, ^"scale", Vector2.ONE, 0.08)
	var node := StatService.catalog[id]
	EventBus.hud_message.emit("Bought %s %s" % [node.display_name,
			"" if node.is_unlock() else "Lv %d" % StatService.level_of(id)], 1.5)
	return true


func _refresh() -> void:
	if _root == null:
		return
	for id in _pegs:
		_style_peg(id, _pegs[id])
	for branch in _tabs:
		var buyable := 0
		for id in _pegs:
			if _peg_branch[id] == branch and StatService.can_purchase(id):
				buyable += 1
		_style_tab(branch, buyable)
	_update_detail()


func _style_peg(id: StringName, peg: Button) -> void:
	var node := StatService.catalog[id]
	var level := StatService.level_of(id)
	var maxed := StatService.is_maxed(id)
	var prereqs := StatService.prerequisites_met(id)
	var cost := StatService.next_cost(id)
	var affordable := StatService.can_afford(cost)
	var free_unlock := node.cost_curve == null
	var wave_locked := id == &"travel.jetpack" and GameState.wave < 3
	var locked := level == 0 and (free_unlock or not prereqs or wave_locked)
	var buyable := not maxed and not locked and prereqs and affordable

	var parts: Dictionary = _peg_parts[id]
	var name_label: Label = parts.name
	var status: Label = parts.status
	var pips: Pips = parts.pips
	var ink := LOCKED_INK if locked else INK
	name_label.add_theme_color_override(&"font_color", ink)
	pips.visible = node.max_level > 1 and not locked
	pips.level = level
	pips.max_level = node.max_level
	pips.color = ink
	pips.queue_redraw()
	if maxed:
		status.text = "OWNED" if node.is_unlock() else "MAXED"
		status.add_theme_color_override(&"font_color", Color(0.2, 0.4, 0.15))
	elif wave_locked:
		status.text = "Wave 3"
		status.add_theme_color_override(&"font_color", LOCKED_INK)
	elif locked:
		status.text = "Locked"
		status.add_theme_color_override(&"font_color", LOCKED_INK)
	else:
		status.text = _price_text(cost)
		status.add_theme_color_override(&"font_color", INK if affordable else SHORT_INK)
	peg.tooltip_text = node.description

	var fill := FILL_LOCKED if locked else (FILL_DONE if maxed else FILL_OPEN)
	var style := _peg_style(fill, EDGE_BUY if buyable else EDGE_PLAIN, 4 if buyable else 2)
	var hover := style.duplicate() as StyleBoxFlat
	hover.bg_color = fill.lightened(0.08)
	for state: StringName in [&"normal", &"pressed", &"disabled"]:
		peg.add_theme_stylebox_override(state, style)
	peg.add_theme_stylebox_override(&"hover", hover)


func _style_tab(branch: int, buyable: int) -> void:
	var tab := _tabs[branch]
	var active := branch == _branch
	tab.text = UpgradeNode.BRANCH_NAMES[branch].to_upper() + ("   %d" % buyable if buyable > 0 else "")
	tab.tooltip_text = "%d upgrade%s you can buy now" % [buyable, "" if buyable == 1 else "s"]
	var style := _peg_style(FILL_OPEN if active else Color(CARDBOARD_DARK, 0.85), Color(0, 0, 0, 0), 0)
	style.set_content_margin_all(10)
	style.content_margin_left = 18
	style.content_margin_right = 18
	for state: StringName in [&"normal", &"hover", &"pressed", &"focus"]:
		tab.add_theme_stylebox_override(state, style)
	for color_name: StringName in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_focus_color"]:
		tab.add_theme_color_override(color_name, INK if active else CREAM)


## A peg's box: the fill says done / open / locked, a gold edge says you can buy it now.
func _peg_style(fill: Color, edge: Color, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.set_corner_radius_all(10)
	style.border_color = edge
	style.set_border_width_all(width)
	style.shadow_color = Color(0, 0, 0, 0.25)
	style.shadow_size = 3
	style.shadow_offset = Vector2(0, 3)
	return style


## Just the price, e.g. "15 Al  8 Cu".
func _price_text(cost: Dictionary[StringName, int]) -> String:
	var parts := PackedStringArray()
	for part in cost:
		parts.append("%d %s" % [cost[part], PART_SHORT.get(part, part)])
	return "  ".join(parts)


## The parts still missing for a cost, e.g. "6 Cu, 2 Al".
func _missing_text(cost: Dictionary[StringName, int]) -> String:
	var missing := PackedStringArray()
	for part in cost:
		var short: int = cost[part] - GameState.parts.get(part, 0)
		if short > 0:
			missing.append("%d %s" % [short, PART_SHORT.get(part, part)])
	return ", ".join(missing)


func _requirement_text(node: UpgradeNode) -> String:
	var needs := PackedStringArray()
	for requirement in node.prerequisites:
		if StatService.level_of(requirement.node_id) < requirement.level:
			var other := StatService.catalog.get(requirement.node_id) as UpgradeNode
			var label := other.display_name if other != null else String(requirement.node_id)
			needs.append(label if requirement.level <= 1 else "%s %d" % [label, requirement.level])
	return ", ".join(needs)


## Why a purchase was refused, for the toast.
func _refusal_text(id: StringName) -> String:
	var node := StatService.catalog[id]
	if StatService.is_maxed(id):
		return "Already owned" if node.is_unlock() else "Already at max level"
	if id == &"travel.jetpack" and GameState.wave < 3:
		return "Available at wave 3"
	if node.cost_curve == null:
		return "Free after wave 2"
	if not StatService.prerequisites_met(id):
		return "Locked: needs " + _requirement_text(node)
	return "Not enough parts: need " + _missing_text(StatService.next_cost(id))


## One line under the board for the peg under the cursor, so a controller player can read it.
func _status_text(id: StringName) -> String:
	var node := StatService.catalog[id]
	if StatService.is_maxed(id):
		return "Owned" if node.is_unlock() else "Owned, at max level"
	if id == &"travel.jetpack" and GameState.wave < 3:
		return "Available at wave 3"
	if node.cost_curve == null:
		return "Free after wave 2"
	if not StatService.prerequisites_met(id):
		return "Locked: needs " + _requirement_text(node)
	var cost := StatService.next_cost(id)
	if not StatService.can_afford(cost):
		return "Short on parts: need " + _missing_text(cost)
	return "Hold A or hold left click to %s for %s" % ["buy" if StatService.level_of(id) == 0 else "upgrade", _price_text(cost)]


func _update_detail() -> void:
	if _detail_name == null:
		return
	if _focus_id == &"" or not StatService.catalog.has(_focus_id):
		_detail_name.text = ""
		_detail_text.text = ""
		_detail_status.text = ""
		return
	var node := StatService.catalog[_focus_id]
	var level := StatService.level_of(_focus_id)
	_detail_name.text = node.display_name + ("   Lv %d / %d" % [level, node.max_level] if node.max_level > 1 else "")
	_detail_text.text = node.description
	_detail_status.text = _status_text(_focus_id)
	var ready := StatService.can_purchase(_focus_id)
	_detail_status.add_theme_color_override(&"font_color", Color(1.0, 0.85, 0.35) if ready else Color(CREAM, 0.75))


# --- Controller focus -----------------------------------------------------------------------------

## Points each peg's focus neighbours at the nearest peg in each direction on its own board. Left and right
## off a board's edge are left empty: _input turns those into a switch to the next board.
func _link_focus() -> void:
	for branch in _boards:
		var centers: Dictionary[StringName, Vector2] = {}
		for id in _pegs:
			if _peg_branch[id] == branch:
				centers[id] = _pegs[id].position + PEG_SIZE * 0.5
		for id in centers:
			var peg := _pegs[id]
			peg.focus_neighbor_left = _nearest_in_direction(id, centers, Vector2.LEFT)
			peg.focus_neighbor_right = _nearest_in_direction(id, centers, Vector2.RIGHT)
			# Up and down stay on the board: point at itself when there's nothing further.
			var up := _nearest_in_direction(id, centers, Vector2.UP)
			var down := _nearest_in_direction(id, centers, Vector2.DOWN)
			peg.focus_neighbor_top = up if not up.is_empty() else ^"."
			peg.focus_neighbor_bottom = down if not down.is_empty() else ^"."


func _show_branch(branch: int) -> void:
	_branch = branch
	for b in _boards:
		(_boards[b].get_parent() as Control).visible = b == branch
	_refresh()


## Moves to the neighbouring board and puts the cursor on its nearest peg to where it came from.
func _switch_branch(step: int) -> void:
	var index := wrapi(BRANCH_ORDER.find(_branch) + step, 0, BRANCH_ORDER.size())
	var row := 0.0
	if _pegs.has(_focus_id):
		row = _pegs[_focus_id].position.y
	_show_branch(BRANCH_ORDER[index])
	var best: StringName = &""
	var best_score := INF
	for id in _pegs:
		if _peg_branch[id] != _branch:
			continue
		var at := _pegs[id].position
		# Enter from the side we came from, on the closest row.
		var score := absf(at.y - row) * 4.0 + (at.x if step > 0 else -at.x)
		if score < best_score:
			best_score = score
			best = id
	_focus_peg(best)


func _nearest_in_direction(id: StringName, centers: Dictionary[StringName, Vector2], dir: Vector2) -> NodePath:
	var origin := centers[id]
	var best: StringName = &""
	var best_score := INF
	for other in centers:
		if other == id:
			continue
		var offset := centers[other] - origin
		var along := offset.dot(dir)
		if along <= 0.0:
			continue
		# Favour pegs straight ahead: sideways drift costs twice as much as distance along the direction.
		var score := along + absf(offset.dot(dir.orthogonal())) * 2.0
		if score < best_score:
			best_score = score
			best = other
	if best == &"":
		return NodePath()
	return _pegs[id].get_path_to(_pegs[best])


func _starting_peg() -> StringName:
	if _focus_id != &"" and _pegs.has(_focus_id):
		return _focus_id
	for id in _pegs:
		if StatService.can_purchase(id):
			return id
	for id in _pegs:
		if _peg_branch[id] == _branch:
			return id
	var ids := _pegs.keys()
	return ids[0] if not ids.is_empty() else &""


## The first peg you can buy on a board, else its first peg.
func _first_peg(branch: int) -> StringName:
	var first: StringName = &""
	for id in _pegs:
		if _peg_branch[id] != branch:
			continue
		if StatService.can_purchase(id):
			return id
		if first == &"":
			first = id
	return first


func _focus_peg(id: StringName) -> void:
	if id != &"" and _pegs.has(id):
		_pegs[id].grab_focus()


func _on_peg_focused(id: StringName) -> void:
	_focus_id = id
	for peg_id in _cursors:
		_cursors[peg_id].visible = peg_id == id
	_update_detail()


func _on_peg_gui_input(event: InputEvent, id: StringName) -> void:
	var mouse := event as InputEventMouseButton
	if mouse != null and mouse.button_index == MOUSE_BUTTON_LEFT and mouse.pressed:
		_mouse_hold_id = id


## Holding A (or the mouse on a peg) fills the bar; a full bar buys. Letting go early cancels, and after a
## buy the player has to release before another one counts. Polling the input keeps this working whatever
## the focus is doing.
func _update_hold(delta: float) -> void:
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_mouse_hold_id = &""
	var target: StringName = &""
	if Input.is_action_pressed(&"ui_accept"):
		target = _focus_id if _focus_id != &"" else _starting_peg()
	elif _mouse_hold_id != &"":
		target = _mouse_hold_id
	if target == &"":
		_needs_release = false
		_hold_id = &""
		_hold_time = 0.0
		_hold_bar.visible = false
		return
	if _needs_release:
		_hold_bar.visible = false
		return
	if target != _hold_id:
		_hold_id = target
		_hold_time = 0.0
		if not StatService.can_purchase(target):
			# Say why straight away instead of making the player hold for nothing.
			EventBus.hud_message.emit(_refusal_text(target), 2.0)
			_needs_release = true
			return
	_hold_time += delta
	_hold_bar.visible = true
	_hold_bar.value = minf(1.0, _hold_time / HOLD_TIME)
	if _hold_time >= HOLD_TIME:
		_needs_release = true
		_hold_time = 0.0
		_hold_bar.visible = false
		buy(target)


# --- Construction ---------------------------------------------------------------------------------

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.03, 0.02, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 48.0
	panel.offset_top = 32.0
	panel.offset_right = -48.0
	panel.offset_bottom = -32.0
	var board_style := StyleBoxFlat.new()
	board_style.bg_color = CARDBOARD
	board_style.set_corner_radius_all(22)
	board_style.set_content_margin_all(22)
	board_style.border_color = CARDBOARD_DARK
	board_style.set_border_width_all(6)
	board_style.shadow_color = Color(0, 0, 0, 0.4)
	board_style.shadow_size = 18
	panel.add_theme_stylebox_override(&"panel", board_style)
	_root.add_child(panel)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override(&"separation", 14)
	panel.add_child(layout)

	# Header: title, banked parts, wave timer, close.
	var header := HBoxContainer.new()
	header.add_theme_constant_override(&"separation", 18)
	layout.add_child(header)
	_title_label = _label(header, "THE PEGBOARD", 30)
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var parts_pill := _pill_box(header)
	parts_pill.add_theme_constant_override(&"separation", 14)
	for key in GameState.PART_KEYS:
		var coin := Hud.PartCoin.new()
		coin.color = Hud.PART_COLORS[key]
		coin.short = Hud.PART_SHORT[key]
		coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		coin.tooltip_text = GameState.PART_NAMES[key]
		parts_pill.add_child(coin)
		_part_labels[key] = _label(parts_pill, "0", 18)
	_timer_label = _label(_pill_box(header), "", 18)
	_timer_label.add_theme_color_override(&"font_color", Color(1.0, 0.85, 0.4))
	var close_button := Button.new()
	close_button.text = "Close"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.add_theme_font_size_override(&"font_size", 16)
	var close_style := _peg_style(Color(CARDBOARD_DARK, 0.9), Color(0, 0, 0, 0), 0)
	close_style.content_margin_left = 16
	close_style.content_margin_right = 16
	close_button.add_theme_stylebox_override(&"normal", close_style)
	var close_hover := close_style.duplicate() as StyleBoxFlat
	close_hover.bg_color = CARDBOARD_DARK.lightened(0.15)
	close_button.add_theme_stylebox_override(&"hover", close_hover)
	close_button.add_theme_stylebox_override(&"pressed", close_hover)
	close_button.pressed.connect(close)
	header.add_child(close_button)

	# Tabs, one per branch.
	var tab_row := HBoxContainer.new()
	tab_row.add_theme_constant_override(&"separation", 8)
	layout.add_child(tab_row)
	for branch in BRANCH_ORDER:
		var tab := Button.new()
		tab.focus_mode = Control.FOCUS_NONE
		tab.add_theme_font_size_override(&"font_size", 18)
		tab.pressed.connect(func() -> void:
			_show_branch(branch)
			_focus_peg(_first_peg(branch)))
		tab_row.add_child(tab)
		_tabs[branch] = tab

	# The board area: a pegboard backdrop with the current branch centred on it.
	var area := PanelContainer.new()
	area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var area_style := StyleBoxFlat.new()
	area_style.bg_color = CARDBOARD.darkened(0.08)
	area_style.set_corner_radius_all(14)
	area_style.set_content_margin_all(16)
	area.add_theme_stylebox_override(&"panel", area_style)
	area.clip_contents = true
	layout.add_child(area)
	var holes := Holes.new()
	holes.mouse_filter = Control.MOUSE_FILTER_IGNORE
	area.add_child(holes)

	var by_branch: Dictionary[int, Array] = {}
	for id in StatService.catalog:
		var node := StatService.catalog[id]
		if not by_branch.has(node.branch):
			by_branch[node.branch] = []
		by_branch[node.branch].append(node)
	for branch in BRANCH_ORDER:
		var center := CenterContainer.new()
		center.mouse_filter = Control.MOUSE_FILTER_IGNORE
		area.add_child(center)
		center.add_child(_build_branch(branch, by_branch.get(branch, [])))
	_link_focus()

	# Footer: the peg under the cursor, then the controls.
	var detail := PanelContainer.new()
	var detail_style := StyleBoxFlat.new()
	detail_style.bg_color = Color(CARDBOARD_DARK, 0.85)
	detail_style.set_corner_radius_all(14)
	detail_style.set_content_margin_all(14)
	detail_style.content_margin_left = 20
	detail.add_theme_stylebox_override(&"panel", detail_style)
	layout.add_child(detail)
	var detail_box := VBoxContainer.new()
	detail_box.add_theme_constant_override(&"separation", 2)
	detail.add_child(detail_box)
	var detail_top := HBoxContainer.new()
	detail_box.add_child(detail_top)
	_detail_name = _label(detail_top, "", 22)
	_detail_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hold_bar = ProgressBar.new()
	_hold_bar.show_percentage = false
	_hold_bar.max_value = 1.0
	_hold_bar.custom_minimum_size = Vector2(220.0, 14.0)
	_hold_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_hold_bar.visible = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = EDGE_BUY
	fill.set_corner_radius_all(7)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0, 0, 0, 0.4)
	track.set_corner_radius_all(7)
	_hold_bar.add_theme_stylebox_override(&"fill", fill)
	_hold_bar.add_theme_stylebox_override(&"background", track)
	detail_top.add_child(_hold_bar)
	_detail_text = _label(detail_box, "", 16)
	_detail_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_text.add_theme_constant_override(&"outline_size", 0)
	_detail_status = _label(detail_box, "", 16)
	_detail_status.add_theme_constant_override(&"outline_size", 0)
	var hint := _label(layout, "Hold A or click to buy     LB / RB or Tab: switch board     B or Esc: close", 14)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override(&"font_color", Color(CREAM, 0.7))
	hint.add_theme_constant_override(&"outline_size", 0)


## A dark rounded pill holding a row, for header readouts.
func _pill_box(parent: Control) -> HBoxContainer:
	var pill := PanelContainer.new()
	var style := _peg_style(Color(CARDBOARD_DARK, 0.85), Color(0, 0, 0, 0), 0)
	style.shadow_size = 0
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	pill.add_theme_stylebox_override(&"panel", style)
	parent.add_child(pill)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 6)
	pill.add_child(row)
	return row


func _build_branch(branch: int, nodes: Array) -> Control:
	var board := Board.new()
	var extent := Vector2i.ONE
	for item: UpgradeNode in nodes:
		extent = Vector2i(maxi(extent.x, item.board_position.x + 1), maxi(extent.y, item.board_position.y + 1))
	board.custom_minimum_size = Vector2(extent) * CELL - (CELL - PEG_SIZE)
	var rects: Dictionary[StringName, Rect2] = {}
	for item: UpgradeNode in nodes:
		var peg := Button.new()
		peg.position = Vector2(item.board_position) * CELL
		peg.size = PEG_SIZE
		peg.custom_minimum_size = PEG_SIZE
		# Every peg stays focusable, locked or not, so the player can read why it's unavailable.
		peg.focus_mode = Control.FOCUS_ALL
		# The focus ring is a separate outline, so the gold edge stays readable while the cursor is on it.
		peg.add_theme_stylebox_override(&"focus", StyleBoxEmpty.new())
		var id := item.id
		# Purchases come from _update_hold, not the Button's pressed signal, so a stray press can't buy.
		peg.gui_input.connect(_on_peg_gui_input.bind(id))
		peg.focus_entered.connect(_on_peg_focused.bind(id))
		peg.mouse_entered.connect(func() -> void: peg.grab_focus())
		board.add_child(peg)

		var content := VBoxContainer.new()
		content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.set_anchors_preset(Control.PRESET_FULL_RECT)
		content.offset_left = 14.0
		content.offset_right = -14.0
		content.offset_top = 10.0
		content.offset_bottom = -10.0
		peg.add_child(content)
		var name_label := Label.new()
		name_label.text = item.display_name
		name_label.add_theme_font_size_override(&"font_size", 17)
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(name_label)
		var bottom := HBoxContainer.new()
		bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bottom.size_flags_vertical = Control.SIZE_EXPAND_FILL
		content.add_child(bottom)
		var pips := Pips.new()
		pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pips.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pips.size_flags_vertical = Control.SIZE_SHRINK_END
		pips.custom_minimum_size = Vector2(0.0, 14.0)
		bottom.add_child(pips)
		var status := Label.new()
		status.add_theme_font_size_override(&"font_size", 15)
		status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		status.size_flags_vertical = Control.SIZE_SHRINK_END
		status.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bottom.add_child(status)
		_peg_parts[id] = {name = name_label, status = status, pips = pips}

		var cursor := Panel.new()
		cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cursor.set_anchors_preset(Control.PRESET_FULL_RECT)
		cursor.offset_left = -6.0
		cursor.offset_top = -6.0
		cursor.offset_right = 6.0
		cursor.offset_bottom = 6.0
		var cursor_style := StyleBoxFlat.new()
		cursor_style.draw_center = false
		cursor_style.border_color = CURSOR_COLOR
		cursor_style.set_border_width_all(3)
		cursor_style.set_corner_radius_all(14)
		cursor.add_theme_stylebox_override(&"panel", cursor_style)
		cursor.visible = false
		peg.add_child(cursor)
		_cursors[id] = cursor
		_pegs[id] = peg
		_peg_branch[id] = branch
		rects[id] = Rect2(peg.position, PEG_SIZE)
	for item: UpgradeNode in nodes:
		for requirement in item.prerequisites:
			if rects.has(requirement.node_id):
				board.links.append(rects[requirement.node_id])
				board.links.append(rects[item.id])
	_boards[branch] = board
	return board


func _label(parent: Control, text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", CREAM)
	label.add_theme_color_override(&"font_outline_color", Color(0.2, 0.13, 0.07))
	label.add_theme_constant_override(&"outline_size", 6 if font_size >= 20 else 3)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label
