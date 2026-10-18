class_name WeaponWheel
extends Control
## The weapon wheel (GDD 5.2), drawn while a WeaponHolder's wheel is open: six pegs round the crosshair,
## slot 1 at the top and clockwise, matching the number keys. Locked weapons show dimmed; the pointed-at
## one grows. Graybox drawing like the rest of the HUD; the cardboard look comes in M3-C.

const RADIUS: float = 175.0
const PEG_RADIUS: float = 60.0

var holder: WeaponHolder = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func _process(_delta: float) -> void:
	var open := holder != null and is_instance_valid(holder) and holder.wheel_open
	if open != visible:
		visible = open
	if open:
		queue_redraw()


func _draw() -> void:
	var font := get_theme_default_font()
	draw_circle(Vector2.ZERO, RADIUS + PEG_RADIUS + 14.0, Color(0.1, 0.07, 0.05, 0.55))
	for slot in range(1, WeaponHolder.WHEEL_SLOTS + 1):
		var angle := TAU * float(slot - 1) / WeaponHolder.WHEEL_SLOTS
		var at := Vector2(sin(angle), -cos(angle)) * RADIUS
		var weapon := holder.in_slot(slot)
		if weapon == null:
			draw_circle(at, 8.0, Color(1, 1, 1, 0.18))
			continue
		var chosen := weapon == holder.wheel_choice
		var available := weapon.is_available()
		var radius := PEG_RADIUS * (1.15 if chosen else 1.0)
		var fill := Color(1.0, 0.8, 0.35) if chosen else Color(0.95, 0.9, 0.8)
		if not available:
			fill = Color(0.45, 0.42, 0.4)
		draw_circle(at, radius, Color(fill, 0.92))
		if weapon == holder.current:
			draw_arc(at, radius + 5.0, 0.0, TAU, 40, Color(1, 1, 1, 0.9), 3.0, true)
		var text := "%d\n%s" % [slot, weapon.display_name]
		if not available:
			text += "\n(buy at shed)"
		_draw_centered(font, at, text, 17, Color(0.12, 0.08, 0.05))
	if holder.wheel_choice != null:
		_draw_centered(font, Vector2(0.0, 34.0), holder.wheel_choice.display_name, 22, Color(1.0, 0.95, 0.8))


func _draw_centered(font: Font, at: Vector2, text: String, size: int, color: Color) -> void:
	var lines := text.split("\n")
	var line_height := font.get_height(size)
	var y := at.y - line_height * lines.size() * 0.5 + font.get_ascent(size)
	for line in lines:
		var width := font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		draw_string_outline(font, Vector2(at.x - width * 0.5, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4, Color(1, 1, 1, 0.6))
		draw_string(font, Vector2(at.x - width * 0.5, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
		y += line_height
