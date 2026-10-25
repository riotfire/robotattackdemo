class_name GeneLibrary
extends Resource
## Every gene option the genome roller can use (GDD 10.1) plus the novelty rules (GDD 10.2).
## M1 ships 3 themes (data/robots/themes) and 4 traits (data/robots/traits); M2-F2 has added Overcharged.

const BODY_PLURALS: Dictionary[StringName, String] = {
	&"tin_can": "Tin Cans", &"gumdrop": "Gumdrops", &"toaster": "Toasters",
	&"egg": "Eggs", &"barrel": "Barrels", &"lunchbox": "Lunchboxes",
}
const BODY_SINGULARS: Dictionary[StringName, String] = {
	&"tin_can": "Tin Can", &"gumdrop": "Gumdrop", &"toaster": "Toaster",
	&"egg": "Egg", &"barrel": "Barrel", &"lunchbox": "Lunchbox",
}
const HEAD_NAMES: Dictionary[StringName, String] = {
	&"dome": "Dome", &"bucket": "Bucket", &"light_bulb": "Bulb", &"old_tv": "Telly",
	&"teapot": "Teapot", &"mailbox": "Mailbox",
}
## Locomotion options by RobotArchetype.RobotType (readability lock: type -> locomotion family).
const LOCOMOTION: Array[Array] = [
	[&"unicycle", &"pogo"],
	[&"waddle_legs", &"mini_treads", &"tripod"],
	[&"treads", &"four_legs", &"giant_wheel"],
]
const WEARS: Array[StringName] = [&"fresh", &"scuffed", &"rusty", &"patched"]
const PERSONALITIES: Array[StringName] = [&"bouncy", &"sneaky", &"marching", &"wobbly", &"grumpy"]
## Base32 without 0/O/1/I (Appendix B).
const CODE_ALPHABET := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

@export var themes: Array[FamilyTheme] = []
@export var traits: Array[RobotTrait] = []
## The farm color families must contrast with (readability lock, GDD 10.1).
@export var farm_color: Color = Color(0.42, 0.58, 0.3)
@export var min_contrast: float = 0.3
## No theme repeats within this many waves. Capped at (theme count - 2), minimum 1, so a small library
## doesn't collapse into a fixed rotation (with M1's 3 themes it means "never twice in a row").
@export var theme_memory: int = 4
@export var min_palette_distance: float = 0.15
## At most this many of the 5 shape genes (body, head, eyes, antenna, scout locomotion) may match the
## previous wave.
@export var max_matching_shape_genes: int = 2


func pick_palette(theme: FamilyTheme, rng: RandomNumberGenerator) -> RobotPalette:
	var order := range(theme.palettes.size())
	_shuffle(order, rng)
	for i: int in order:
		var palette := theme.palettes[i]
		if RobotPalette.luminance_contrast(palette.primary, farm_color) >= min_contrast:
			return palette
	return theme.palettes[order[0]] if not order.is_empty() else RobotPalette.new()


func pick_traits(rng: RandomNumberGenerator, count: int, exclude: Array[RobotTrait] = []) -> Array[RobotTrait]:
	var pool: Array[RobotTrait] = []
	for robot_trait in traits:
		if robot_trait not in exclude:
			pool.append(robot_trait)
	_shuffle(pool, rng)
	var picked: Array[RobotTrait] = []
	for i in mini(count, pool.size()):
		picked.append(pool[i])
	return picked


## GDD 10.2 novelty rules against the waves rolled so far (oldest first).
func is_novel(genome: RobotGenome, history: Array[RobotGenome]) -> bool:
	if history.is_empty():
		return true
	var memory := clampi(mini(theme_memory, themes.size() - 2), 1, theme_memory)
	for i in range(maxi(0, history.size() - memory), history.size()):
		if history[i].theme == genome.theme:
			return false
	var last := history[history.size() - 1]
	if genome.palette == last.palette:
		return false
	if RobotPalette.oklab_distance(genome.palette.primary, last.palette.primary) <= min_palette_distance:
		return false
	return genome.matching_shape_genes(last) <= max_matching_shape_genes


## Six characters from a 30-bit value.
static func encode(value: int) -> String:
	var v := absi(value)
	var code := ""
	for i in 6:
		code += CODE_ALPHABET[v & 31]
		v = v >> 5
	return code


static func _shuffle(items: Array, rng: RandomNumberGenerator) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap: Variant = items[i]
		items[i] = items[j]
		items[j] = swap
