class_name PegboardUI
extends CanvasLayer
## The upgrade pegboard (GDD 13.1, 17.3), opened at the tool shed door during intermissions.
## One board per branch; each node is a peg showing its name, level pips and next cost (have/need), with
## red yarn to its prerequisites. Fill colour says what you have or can get (green owned, cream available,
## grey locked); the ring says whether you can afford the next level now (gold) or are short on parts (red).
## Controller: D-pad or left stick moves the cursor across every branch, A buys, B or Start closes.
## The intermission timer keeps running while it's open, and it closes itself when the shed shutters for
## the wave. Graybox 2D overlay; the 3D pegboard dolly comes later.

## The board was shut (by the player, or by the shutters coming down).
signal closed

const CELL := Vector2(158.0, 84.0)
const PEG_SIZE := Vector2(150.0, 74.0)
const BOARD_ROWS: Array[Array] = [
	[UpgradeNode.Branch.TRAVEL, UpgradeNode.Branch.ATTACK, UpgradeNode.Branch.REPAIR],
	[UpgradeNode.Branch.DEFEND, UpgradeNode.Branch.FARMHAND],
]
const PART_SHORT: Dictionary[StringName, String] = {&"al": "Al", &"cu": "Cu", &"au": "Au", &"pc": "PC"}
const CARDBOARD := Color(0.58, 0.44, 0.3)
const YARN := Color(0.85, 0.15, 0.12)
## Peg fill: what you have (owned), can get (available), or can't reach yet (locked).
const FILL_OWNED := Color(0.66, 0.84, 0.55)
const FILL_AVAILABLE := Color(0.95, 0.88, 0.72)
const FILL_LOCKED := Color(0.5, 0.47, 0.43)
## Peg ring: can you afford the next level right now.
const RING_AFFORDABLE := Color(1.0, 0.8, 0.2)
const RING_SHORT := Color(0.8, 0.18, 0.12)
const RING_NONE := Color(0.3, 0.22, 0.14)
const CURSOR_COLOR := Color(1.0, 1.0, 1.0)
const INK := Color(0.12, 0.08, 0.04)
const LOCKED_INK := Color(0.32, 0.28, 0.24)
## Hold A (or the mouse on a peg) this long to buy, the same as the dinner bell.
const HOLD_TIME: float = 1.0

@export var director: WaveDirector

var is_open: bool = false
var _farmer: Farmer = null
var _root: Control
var _title_label: Label
var _status_label: Label
var _detail_label: Label
var _pegs: Dictionary[StringName, Button] = {}
var _cursors: Dictionary[StringName, Panel] = {}
var _boards: Array[Board] = []
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


## Draws the red yarn between pegs and their prerequisites.
class Board:
	extends Control

	var links: Array[PackedVector2Array] = []

	func _draw() -> void:
		for link in links:
			draw_line(link[0], link[1], PegboardUI.YARN, 3.0, true)
			draw_circle(link[1], 4.0, PegboardUI.YARN)


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
	_refresh()
	# Let the containers lay the pegs out before measuring where each one sits for focus.
	await get_tree().process_frame
	if not is_open:
		return
	_link_focus()
	_focus_peg(_starting_peg())


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


func _set_player_input(enabled: bool) -> void:
	if _farmer != null and is_instance_valid(_farmer):
		_farmer.input.enabled = enabled


func _unhandled_input(event: InputEvent) -> void:
	if not is_open:
		return
	if event.is_action_pressed(&"pause") or event.is_action_pressed(&"interact") or event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


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
	var timer := ""
	if director != null and director.phase in [WaveDirector.Phase.INTERMISSION, WaveDirector.Phase.SIREN]:
		timer = "Next wave in %s" % Hud._clock(director.time_left)
	_status_label.text = "Al %d   Cu %d   Au %d   PC %d        %s" % [GameState.parts[&"al"], GameState.parts[&"cu"],
			GameState.parts[&"au"], GameState.parts[&"pc"], timer]


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
	_update_detail()


func _style_peg(id: StringName, peg: Button) -> void:
	var node := StatService.catalog[id]
	var level := StatService.level_of(id)
	var maxed := StatService.is_maxed(id)
	var prereqs := StatService.prerequisites_met(id)
	var cost := StatService.next_cost(id)
	var affordable := StatService.can_afford(cost)
	var free_unlock := node.cost_curve == null
	var owned := level > 0
	var wave_locked := id == &"travel.jetpack" and GameState.wave < 3
	var locked := not owned and (free_unlock or not prereqs or wave_locked)
	var pips := ""
	if node.max_level > 1:
		pips = "[%s%s]" % ["#".repeat(level), "-".repeat(node.max_level - level)] if node.max_level <= 5 else "Lv %d / %d" % [level, node.max_level]
	var line2 := ""
	if maxed:
		line2 = "OWNED" if node.is_unlock() else "MAX"
	elif wave_locked:
		line2 = "Available at wave 3"
	elif free_unlock:
		line2 = "Free"
	elif not prereqs:
		line2 = "Needs " + _requirement_text(node)
	else:
		line2 = _cost_text(cost)
	peg.text = "%s\n%s\n%s" % [node.display_name, pips, line2]
	peg.tooltip_text = node.description
	peg.add_theme_color_override(&"font_color", LOCKED_INK if locked else INK)

	var fill := FILL_LOCKED if locked else (FILL_OWNED if owned else FILL_AVAILABLE)
	var ring := RING_NONE
	if not maxed and not free_unlock and prereqs and not wave_locked:
		ring = RING_AFFORDABLE if affordable else RING_SHORT
	var style := _peg_style(fill, ring)
	for state: StringName in [&"normal", &"hover", &"pressed", &"disabled"]:
		peg.add_theme_stylebox_override(state, style.duplicate())


## A peg's box: the fill is what you have or can get, the ring is whether you can afford the next level.
func _peg_style(fill: Color, ring: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.set_corner_radius_all(8)
	style.border_color = ring
	style.set_border_width_all(2 if ring == RING_NONE else 4)
	return style


func _cost_text(cost: Dictionary[StringName, int]) -> String:
	var parts := PackedStringArray()
	for part in cost:
		parts.append("%d/%d %s" % [mini(GameState.parts.get(part, 0), cost[part]), cost[part], PART_SHORT.get(part, part)])
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
	return "Press A to %s for %s" % ["buy" if StatService.level_of(id) == 0 else "upgrade", _cost_text(cost)]


func _update_detail() -> void:
	if _detail_label == null:
		return
	if _focus_id == &"" or not StatService.catalog.has(_focus_id):
		_detail_label.text = ""
		return
	var node := StatService.catalog[_focus_id]
	_detail_label.text = "%s: %s\n%s" % [node.display_name, node.description, _status_text(_focus_id)]


# --- Controller focus -----------------------------------------------------------------------------

## Points each peg's focus neighbours at the nearest peg in each direction, across every branch,
## so the D-pad and stick walk the whole board rather than stopping at the edge of one branch.
func _link_focus() -> void:
	var centers: Dictionary[StringName, Vector2] = {}
	for id in _pegs:
		centers[id] = _pegs[id].get_global_rect().get_center()
	for id in _pegs:
		var peg := _pegs[id]
		peg.focus_neighbor_left = _nearest_in_direction(id, centers, Vector2.LEFT)
		peg.focus_neighbor_right = _nearest_in_direction(id, centers, Vector2.RIGHT)
		peg.focus_neighbor_top = _nearest_in_direction(id, centers, Vector2.UP)
		peg.focus_neighbor_bottom = _nearest_in_direction(id, centers, Vector2.DOWN)


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
	var ids := _pegs.keys()
	return ids[0] if not ids.is_empty() else &""


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
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 40.0
	panel.offset_top = 30.0
	panel.offset_right = -40.0
	panel.offset_bottom = -30.0
	var board_style := StyleBoxFlat.new()
	board_style.bg_color = CARDBOARD
	board_style.set_corner_radius_all(18)
	board_style.set_content_margin_all(18)
	board_style.border_color = Color(0.35, 0.25, 0.16)
	board_style.set_border_width_all(6)
	panel.add_theme_stylebox_override(&"panel", board_style)
	_root.add_child(panel)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override(&"separation", 10)
	panel.add_child(layout)
	var header := HBoxContainer.new()
	layout.add_child(header)
	_title_label = _label(header, "THE PEGBOARD", 28)
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_label = _label(header, "", 18)
	var close_button := Button.new()
	close_button.text = "  Close (Esc / E / B)  "
	close_button.pressed.connect(close)
	header.add_child(close_button)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# Keep the cursor's peg on screen as the D-pad moves it through the lower rows.
	scroll.follow_focus = true
	layout.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override(&"separation", 14)
	scroll.add_child(rows)

	var by_branch: Dictionary[int, Array] = {}
	for id in StatService.catalog:
		var node := StatService.catalog[id]
		if not by_branch.has(node.branch):
			by_branch[node.branch] = []
		by_branch[node.branch].append(node)

	for row in BOARD_ROWS:
		var row_box := HBoxContainer.new()
		row_box.add_theme_constant_override(&"separation", 18)
		rows.add_child(row_box)
		for branch: int in row:
			row_box.add_child(_build_branch(branch, by_branch.get(branch, [])))

	var footer := VBoxContainer.new()
	footer.add_theme_constant_override(&"separation", 6)
	layout.add_child(footer)
	_detail_label = _label(footer, "", 18)
	_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_label.custom_minimum_size = Vector2(0.0, 56.0)
	_hold_bar = ProgressBar.new()
	_hold_bar.show_percentage = false
	_hold_bar.custom_minimum_size = Vector2(0.0, 16.0)
	_hold_bar.visible = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = RING_AFFORDABLE
	fill.set_corner_radius_all(6)
	_hold_bar.add_theme_stylebox_override(&"fill", fill)
	footer.add_child(_hold_bar)
	_build_legend(footer)
	_label(footer, "Controller: D-pad or left stick to move   Hold A to buy   B or Start to close        Mouse: hold click on a peg to buy", 14)


func _build_legend(parent: Control) -> void:
	var legend := HBoxContainer.new()
	legend.add_theme_constant_override(&"separation", 22)
	parent.add_child(legend)
	_legend_item(legend, "Owned", FILL_OWNED, RING_NONE)
	_legend_item(legend, "Available", FILL_AVAILABLE, RING_NONE)
	_legend_item(legend, "Locked", FILL_LOCKED, RING_NONE)
	_legend_item(legend, "Gold ring: you can afford it", FILL_AVAILABLE, RING_AFFORDABLE)
	_legend_item(legend, "Red ring: short on parts", FILL_AVAILABLE, RING_SHORT)


func _legend_item(parent: Control, text: String, fill: Color, ring: Color) -> void:
	var item := HBoxContainer.new()
	item.add_theme_constant_override(&"separation", 6)
	parent.add_child(item)
	var swatch := Panel.new()
	swatch.custom_minimum_size = Vector2(26.0, 18.0)
	swatch.add_theme_stylebox_override(&"panel", _peg_style(fill, ring))
	item.add_child(swatch)
	_label(item, text, 15)


func _build_branch(branch: int, nodes: Array) -> Control:
	var column := VBoxContainer.new()
	_label(column, UpgradeNode.BRANCH_NAMES[branch].to_upper(), 20)
	var board := Board.new()
	var extent := Vector2i.ONE
	for item: UpgradeNode in nodes:
		extent = Vector2i(maxi(extent.x, item.board_position.x + 1), maxi(extent.y, item.board_position.y + 1))
	board.custom_minimum_size = Vector2(extent) * CELL
	column.add_child(board)
	var centers: Dictionary[StringName, Vector2] = {}
	for item: UpgradeNode in nodes:
		var peg := Button.new()
		peg.position = Vector2(item.board_position) * CELL
		peg.size = PEG_SIZE
		peg.custom_minimum_size = PEG_SIZE
		peg.add_theme_font_size_override(&"font_size", 12)
		for color_name: StringName in [&"font_color", &"font_hover_color", &"font_focus_color", &"font_pressed_color", &"font_hover_pressed_color"]:
			peg.add_theme_color_override(color_name, INK)
		peg.add_theme_color_override(&"font_disabled_color", LOCKED_INK)
		peg.clip_text = true
		# Every peg stays focusable, locked or not, so the player can read why it's unavailable.
		peg.focus_mode = Control.FOCUS_ALL
		# The focus ring is a separate outline, so the state ring stays readable while the cursor is on it.
		peg.add_theme_stylebox_override(&"focus", StyleBoxEmpty.new())
		var id := item.id
		# Purchases come from _update_hold, not the Button's pressed signal, so a stray press can't buy.
		peg.gui_input.connect(_on_peg_gui_input.bind(id))
		peg.focus_entered.connect(_on_peg_focused.bind(id))
		board.add_child(peg)
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
		cursor_style.set_border_width_all(4)
		cursor_style.set_corner_radius_all(11)
		cursor.add_theme_stylebox_override(&"panel", cursor_style)
		cursor.visible = false
		peg.add_child(cursor)
		_cursors[id] = cursor
		_pegs[id] = peg
		centers[id] = peg.position + PEG_SIZE * 0.5
	for item: UpgradeNode in nodes:
		for requirement in item.prerequisites:
			if centers.has(requirement.node_id):
				board.links.append(PackedVector2Array([centers[requirement.node_id], centers[item.id]]))
	_boards.append(board)
	return column


func _label(parent: Control, text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", Color(1.0, 0.95, 0.85))
	label.add_theme_color_override(&"font_outline_color", Color(0.2, 0.13, 0.07))
	label.add_theme_constant_override(&"outline_size", 6)
	parent.add_child(label)
	return label
