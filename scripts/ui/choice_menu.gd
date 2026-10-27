class_name ChoiceMenu
extends CanvasLayer
## A small in-world menu: a title, a line of status and a short list of choices. The build menu (Tab) and a
## placed defense's options use it. The game keeps running while it is open (the intermission clock never
## stops for shopping or building); the farmer just stops taking input.
## W/S, the arrows, the D-pad or the left stick move the cursor; hold Interact, Enter or A (or the mouse on a
## row) for HOLD_TIME to choose; Esc, B or the key that opened it closes it. Walking it away from its anchor
## closes it too. Entries are dictionaries: {text, detail?, enabled, reason?, action: Callable}.

signal closed
signal chosen(index: int)

const HOLD_TIME: float = 0.45
## Distance from its anchor (a defense site) at which it closes by itself.
const ANCHOR_RANGE: float = 3.2
const INK := Color(1.0, 0.96, 0.86)
const INK_DIM := Color(0.93, 0.87, 0.74, 0.65)
const CARD := Color(0.13, 0.09, 0.06, 0.88)
const PICK := Color(1.0, 0.8, 0.3)

## Extra actions that close it, besides ui_cancel and pause (the build menu's own key, Build).
var close_actions: Array[StringName] = []
var farmer: Farmer = null

var _entries: Array[Dictionary] = []
var _rows: Array[Label] = []
var _cursor: int = 0
var _root: PanelContainer
var _title: Label
var _subtitle: Label
var _list: VBoxContainer
var _detail: Label
var _hold_bar: ProgressBar
var _hold: float = 0.0
var _needs_release: bool = true
var _anchor: Node3D = null
var _opened_frame: int = 0
var _nav_cooldown: float = 0.0
var _mouse_row: int = -1


func _ready() -> void:
	layer = 6
	_build()
	_root.visible = false


func is_open() -> bool:
	return _root != null and _root.visible


func open(owner_farmer: Farmer, title: String, entries: Array[Dictionary], anchor: Node3D = null) -> void:
	farmer = owner_farmer
	_anchor = anchor
	_title.text = title
	_cursor = 0
	_hold = 0.0
	_needs_release = true
	_opened_frame = Engine.get_process_frames()
	set_entries(entries)
	_root.visible = true
	if farmer != null and is_instance_valid(farmer):
		farmer.input.enabled = false


func close() -> void:
	if not is_open():
		return
	_root.visible = false
	_hold_bar.visible = false
	if farmer != null and is_instance_valid(farmer):
		farmer.input.enabled = true
	closed.emit()


func set_subtitle(text: String) -> void:
	if _subtitle != null:
		_subtitle.text = text
		_subtitle.visible = not text.is_empty()


## Replaces the choices, keeping the cursor on the same row where it can.
func set_entries(entries: Array[Dictionary]) -> void:
	_entries = entries
	if _rows.size() != entries.size():
		for row in _rows:
			row.queue_free()
		_rows.clear()
		for i in entries.size():
			var row := Label.new()
			row.add_theme_font_size_override(&"font_size", 18)
			row.add_theme_color_override(&"font_outline_color", Color(0.1, 0.07, 0.05))
			row.add_theme_constant_override(&"outline_size", 4)
			row.mouse_filter = Control.MOUSE_FILTER_STOP
			row.gui_input.connect(_on_row_input.bind(i))
			row.mouse_entered.connect(func() -> void: _cursor = i)
			_list.add_child(row)
			_rows.append(row)
	_cursor = clampi(_cursor, 0, maxi(0, entries.size() - 1))
	_restyle()


func _restyle() -> void:
	for i in _rows.size():
		var entry := _entries[i]
		var enabled := bool(entry.get("enabled", true)) and entry.has("action")
		var picked := i == _cursor
		_rows[i].text = ("> " if picked else "   ") + String(entry.get("text", ""))
		var color := PICK if picked and enabled else (INK if enabled else INK_DIM)
		_rows[i].add_theme_color_override(&"font_color", color)
	if _entries.is_empty():
		_detail.text = ""
		return
	var current := _entries[_cursor]
	var enabled := bool(current.get("enabled", true)) and current.has("action")
	_detail.text = String(current.get("detail", "")) if enabled else String(current.get("reason", current.get("detail", "")))
	_detail.visible = not _detail.text.is_empty()


func _process(delta: float) -> void:
	if not is_open():
		return
	if _anchor != null and is_instance_valid(_anchor) and farmer != null and is_instance_valid(farmer) \
			and farmer.global_position.distance_to(_anchor.global_position) > ANCHOR_RANGE:
		close()
		return
	if Engine.get_process_frames() > _opened_frame + 1:
		for action: StringName in [&"ui_cancel", &"pause"] + close_actions:
			if InputMap.has_action(action) and Input.is_action_just_pressed(action):
				close()
				return
	_nav_cooldown = maxf(0.0, _nav_cooldown - delta)
	var step := 0
	if Input.is_action_just_pressed(&"ui_down") or Input.is_action_just_pressed(&"move_back"):
		step = 1
	elif Input.is_action_just_pressed(&"ui_up") or Input.is_action_just_pressed(&"move_forward"):
		step = -1
	if step != 0 and not _entries.is_empty():
		_cursor = posmod(_cursor + step, _entries.size())
		_hold = 0.0
		_restyle()
	_update_hold(delta)


func _update_hold(delta: float) -> void:
	var held := Input.is_action_pressed(&"interact") or Input.is_action_pressed(&"ui_accept") \
			or (_mouse_row >= 0 and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT))
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_mouse_row = -1
	if not held:
		_needs_release = false
		_hold = 0.0
		_hold_bar.visible = false
		return
	if _needs_release or _entries.is_empty():
		return
	var entry := _entries[_cursor]
	if not bool(entry.get("enabled", true)) or not entry.has("action"):
		_hold_bar.visible = false
		return
	_hold += delta
	_hold_bar.visible = true
	_hold_bar.value = minf(1.0, _hold / HOLD_TIME)
	if _hold >= HOLD_TIME:
		_hold = 0.0
		_needs_release = true
		_hold_bar.visible = false
		var action: Callable = entry["action"]
		var index := _cursor
		action.call()
		chosen.emit(index)


func _on_row_input(event: InputEvent, index: int) -> void:
	var mouse := event as InputEventMouseButton
	if mouse != null and mouse.button_index == MOUSE_BUTTON_LEFT and mouse.pressed:
		_cursor = index
		_mouse_row = index
		_restyle()


func _build() -> void:
	_root = PanelContainer.new()
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = CARD
	style.border_color = Color(1.0, 0.78, 0.35, 0.8)
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(14)
	_root.add_theme_stylebox_override(&"panel", style)
	add_child(_root)
	_root.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_root.offset_left = -330.0
	_root.offset_right = 330.0
	_root.offset_top = -420.0
	_root.offset_bottom = -190.0
	_root.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 6)
	_root.add_child(box)
	_title = _label(box, 22, INK)
	_subtitle = _label(box, 14, INK_DIM)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override(&"separation", 4)
	box.add_child(_list)
	_detail = _label(box, 14, INK_DIM)
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.custom_minimum_size = Vector2(620.0, 0.0)
	_hold_bar = ProgressBar.new()
	_hold_bar.show_percentage = false
	_hold_bar.max_value = 1.0
	_hold_bar.custom_minimum_size = Vector2(0.0, 8.0)
	var fill := StyleBoxFlat.new()
	fill.bg_color = PICK
	fill.set_corner_radius_all(4)
	_hold_bar.add_theme_stylebox_override(&"fill", fill)
	_hold_bar.visible = false
	box.add_child(_hold_bar)
	var hint := _label(box, 13, INK_DIM)
	hint.text = "W/S choose   ·   hold E / (A) or click to pick   ·   Esc / (B) close   ·   the clock keeps running"


func _label(parent: Control, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", color)
	label.add_theme_color_override(&"font_outline_color", Color(0.1, 0.07, 0.05))
	label.add_theme_constant_override(&"outline_size", 4 if font_size >= 18 else 2)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label
