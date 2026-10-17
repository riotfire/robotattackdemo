class_name RobotPalette
extends Resource
## A curated family palette (GDD 10.1 Layer 2). Eye glow is never part of a palette: it is locked to class.

## The palette word in family names: "The <Minty> Pirate Teapots" (Appendix B).
@export var adjective: String = ""
@export var primary: Color = Color.WHITE
@export var secondary: Color = Color.GRAY
@export var trim: Color = Color.WHITE


static func make(word: String, primary_color: Color, secondary_color: Color, trim_color: Color) -> RobotPalette:
	var palette := RobotPalette.new()
	palette.adjective = word
	palette.primary = primary_color
	palette.secondary = secondary_color
	palette.trim = trim_color
	return palette


## Perceptual distance between two colors in OKLab (GDD 10.2 asks for > 0.15 between waves).
static func oklab_distance(a: Color, b: Color) -> float:
	return to_oklab(a).distance_to(to_oklab(b))


static func to_oklab(c: Color) -> Vector3:
	var r := _linear(c.r)
	var g := _linear(c.g)
	var b := _linear(c.b)
	var l := pow(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b, 1.0 / 3.0)
	var m := pow(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b, 1.0 / 3.0)
	var s := pow(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b, 1.0 / 3.0)
	return Vector3(
		0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
		1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
		0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)


## Relative luminance contrast in [0, 1] (GDD 10.1 readability lock: >= 0.3 against the farm).
static func luminance_contrast(a: Color, b: Color) -> float:
	var la := a.get_luminance()
	var lb := b.get_luminance()
	return absf(la - lb) / maxf(maxf(la, lb), 0.001)


static func _linear(v: float) -> float:
	return v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4)
