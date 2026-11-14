class_name AppearanceGenerator
extends RefCounted
## Random but believable looks for newcomers: skin tone, hair, eyes, face
## shape, body, clothes and accessories. Several candidates are generated and
## the one that differs most from everyone already in the village is kept, so
## the village never fills up with lookalikes. Relatives start from a family
## member's look (skin tone, hair, face) and vary from there.

const SKIN_TONES: Array[Color] = [
	Color(0.33, 0.2, 0.14), Color(0.41, 0.26, 0.17), Color(0.5, 0.33, 0.22), Color(0.58, 0.39, 0.26),
	Color(0.66, 0.46, 0.31), Color(0.72, 0.53, 0.37), Color(0.7, 0.56, 0.4), Color(0.79, 0.6, 0.45),
	Color(0.85, 0.67, 0.53), Color(0.9, 0.74, 0.61), Color(0.94, 0.8, 0.69), Color(0.82, 0.63, 0.44),
]
const HAIR_COLORS := {
	"black": Color(0.07, 0.055, 0.05), "dark_brown": Color(0.18, 0.11, 0.07), "brown": Color(0.34, 0.21, 0.12),
	"chestnut": Color(0.45, 0.25, 0.13), "auburn": Color(0.52, 0.22, 0.1), "red": Color(0.66, 0.29, 0.12),
	"dark_blond": Color(0.6, 0.45, 0.25), "blond": Color(0.82, 0.66, 0.38), "pale_blond": Color(0.9, 0.8, 0.56),
}
const GREY_HAIR: Array[Color] = [Color(0.55, 0.53, 0.5), Color(0.7, 0.68, 0.65), Color(0.86, 0.85, 0.83)]
const EYE_COLORS: Array[Color] = [
	Color(0.16, 0.1, 0.06), Color(0.24, 0.15, 0.08), Color(0.35, 0.24, 0.12), Color(0.33, 0.33, 0.16),
	Color(0.24, 0.38, 0.26), Color(0.25, 0.4, 0.55), Color(0.38, 0.45, 0.5),
]
## Natural dyes: madder, woad, weld, walnut, lichen...
const DYES: Array[Color] = [
	Color(0.62, 0.22, 0.18), Color(0.26, 0.36, 0.58), Color(0.78, 0.6, 0.24), Color(0.4, 0.46, 0.24),
	Color(0.22, 0.4, 0.3), Color(0.66, 0.38, 0.2), Color(0.46, 0.26, 0.44), Color(0.36, 0.42, 0.48),
	Color(0.86, 0.82, 0.7), Color(0.46, 0.32, 0.2), Color(0.2, 0.46, 0.46), Color(0.74, 0.62, 0.3),
	Color(0.5, 0.16, 0.22), Color(0.2, 0.22, 0.4), Color(0.56, 0.62, 0.48), Color(0.28, 0.27, 0.26),
	Color(0.84, 0.48, 0.42), Color(0.92, 0.88, 0.8),
]
const PANTS: Array[Color] = [
	Color(0.3, 0.26, 0.22), Color(0.24, 0.22, 0.2), Color(0.36, 0.3, 0.22), Color(0.22, 0.26, 0.32),
	Color(0.38, 0.34, 0.28), Color(0.3, 0.32, 0.24), Color(0.18, 0.17, 0.16),
]
const SHOES: Array[Color] = [Color(0.3, 0.2, 0.12), Color(0.2, 0.14, 0.1), Color(0.4, 0.27, 0.16), Color(0.14, 0.12, 0.11)]
const HEADWEAR: Array[String] = ["straw_hat", "wide_hat", "headband", "headwrap", "cap", "flower_crown"]
const STYLES_FEMALE := {"long": 3.0, "bun": 2.0, "ponytail": 2.0, "curly": 2.0, "locs": 1.5, "short": 1.5, "braids": 2.0, "afro": 1.5}
const STYLES_MALE := {"short": 4.0, "curly": 2.0, "locs": 1.2, "ponytail": 0.8, "bun": 0.7, "long": 0.8, "balding": 0.0, "afro": 1.5, "braids": 0.5}
const CANDIDATES := 10


## A look for someone of this sex, age and profession that stands apart
## from `others` (CharacterAppearance list). With `family`, starts from a
## relative's look instead.
static func generate(rng: RandomNumberGenerator, sex: String, age: int, profession: String,
		others: Array, family: CharacterAppearance = null) -> CharacterAppearance:
	var best: CharacterAppearance = null
	var best_distance := -1.0
	for i in CANDIDATES:
		var look := _candidate(rng, sex, age, profession, family)
		var closest := INF
		for other in others:
			closest = minf(closest, distance(look, other))
		if closest > best_distance:
			best_distance = closest
			best = look
		if best_distance > 2.5:
			break
	return best


## How different two people look (0 = identical). Weighted towards what you
## notice first: skin, hair, clothes, silhouette, then the face.
static func distance(a: CharacterAppearance, b: CharacterAppearance) -> float:
	var d := 0.0
	d += _color_distance(a.skin_color, b.skin_color) * 2.5
	d += _color_distance(a.hair_color, b.hair_color) * 1.5
	d += 1.0 if a.hair_style != b.hair_style else 0.0
	d += _color_distance(a.shirt_color, b.shirt_color) * 1.5
	d += _color_distance(a.pants_color, b.pants_color) * 0.5
	d += _color_distance(a.skirt_color, b.skirt_color) * 0.5
	d += absf(a.tunic_length - b.tunic_length)
	d += absf(a.height_scale - b.height_scale) * 4.0
	d += absf(a.build_width - b.build_width) * 2.0
	d += absf(a.chest_shape - b.chest_shape) * 0.6
	d += (absf(a.face_width - b.face_width) + absf(a.jaw_width - b.jaw_width) + absf(a.eye_size - b.eye_size)
		+ absf(a.nose_length - b.nose_length) + absf(a.nose_width - b.nose_width) + absf(a.lip_fullness - b.lip_fullness)) * 1.5
	var shared := 0
	var union := {}
	for item in a.accessories:
		union[item] = true
		if b.accessories.has(item):
			shared += 1
	for item in b.accessories:
		union[item] = true
	if not union.is_empty():
		d += 1.0 - float(shared) / union.size()
	return d


static func _color_distance(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()


static func _pick(rng: RandomNumberGenerator, list: Array) -> Variant:
	return list[rng.randi_range(0, list.size() - 1)]


static func _weighted(rng: RandomNumberGenerator, weights: Dictionary) -> String:
	var total := 0.0
	for key in weights:
		total += float(weights[key])
	var roll := rng.randf() * total
	for key in weights:
		roll -= float(weights[key])
		if roll <= 0.0:
			return String(key)
	return String(weights.keys()[0])


static func _vary(rng: RandomNumberGenerator, c: Color, amount: float) -> Color:
	return Color(clampf(c.r + rng.randf_range(-amount, amount), 0.0, 1.0),
		clampf(c.g + rng.randf_range(-amount, amount), 0.0, 1.0),
		clampf(c.b + rng.randf_range(-amount, amount), 0.0, 1.0))


## A dye that won't be mistaken for bare skin from a distance.
static func _cloth_dye(rng: RandomNumberGenerator, skin: Color) -> Color:
	for attempt in 12:
		var dye := _vary(rng, _pick(rng, DYES), 0.03)
		if _color_distance(dye, skin) > 0.22:
			return dye
	return _vary(rng, DYES[1], 0.03)


static func _hair_for_skin(rng: RandomNumberGenerator, skin: Color) -> Color:
	var lightness := skin.get_luminance()
	var weights := {"black": 3.0, "dark_brown": 3.0, "brown": 1.0}
	if lightness > 0.5:
		weights = {"black": 1.0, "dark_brown": 2.5, "brown": 2.5, "chestnut": 1.5, "dark_blond": 1.0}
	if lightness > 0.62:
		weights = {"black": 0.6, "dark_brown": 2.0, "brown": 2.0, "chestnut": 1.5, "auburn": 1.0, "red": 0.7,
			"dark_blond": 1.2, "blond": 1.2, "pale_blond": 0.6}
	return _vary(rng, HAIR_COLORS[_weighted(rng, weights)], 0.03)


static func _candidate(rng: RandomNumberGenerator, sex: String, age: int, profession: String,
		family: CharacterAppearance) -> CharacterAppearance:
	var look := CharacterAppearance.new()
	var female := sex == "female"
	var elder := age >= 58
	var teen := age < 18

	# --- Colouring ---
	if family:
		look.skin_color = _vary(rng, family.skin_color, 0.03)
		look.hair_color = _vary(rng, family.hair_color, 0.06)
		look.eye_color = family.eye_color if rng.randf() < 0.6 else _pick(rng, EYE_COLORS)
	else:
		look.skin_color = _vary(rng, _pick(rng, SKIN_TONES), 0.02)
		look.hair_color = _hair_for_skin(rng, look.skin_color)
		var dark_eyes := look.skin_color.get_luminance() < 0.55
		look.eye_color = _pick(rng, EYE_COLORS.slice(0, 3)) if dark_eyes or rng.randf() < 0.45 else _pick(rng, EYE_COLORS)
	if elder:
		look.hair_color = _pick(rng, GREY_HAIR)
	elif age > 45 and rng.randf() < 0.5:
		look.hair_color = look.hair_color.lerp(GREY_HAIR[0], 0.45)
	look.brow_color = look.hair_color.darkened(0.15) if rng.randf() < 0.7 else Color(0, 0, 0, 0)

	# --- Hair ---
	var styles: Dictionary = (STYLES_FEMALE if female else STYLES_MALE).duplicate()
	if not female and age > 40:
		styles["balding"] = 1.5 if elder else 0.6
	if family and rng.randf() < 0.35:
		styles[family.hair_style] = float(styles.get(family.hair_style, 1.0)) + 3.0
	look.hair_style = _weighted(rng, styles)

	# --- Body ---
	var height_mean := 0.97 if female else 1.03
	if teen:
		height_mean -= 0.07
	look.height_scale = clampf(height_mean + rng.randf_range(-0.07, 0.07), 0.87, 1.13)
	look.build_width = clampf(rng.randf_range(0.86, 1.2) + (0.04 if not female else 0.0) - (0.06 if teen else 0.0), 0.8, 1.28)
	look.shoulder_width = clampf((1.05 if not female else 0.93) + rng.randf_range(-0.08, 0.1), 0.82, 1.22)
	look.hip_width = clampf((1.05 if female else 0.95) + rng.randf_range(-0.08, 0.08), 0.82, 1.22)
	look.chest_shape = rng.randf_range(0.35, 0.8) if female and not teen else (rng.randf_range(0.15, 0.4) if female else rng.randf_range(0.0, 0.12))
	look.stoop = rng.randf_range(0.08, 0.28) if elder else 0.0

	# --- Face ---
	if family:
		look.face_width = clampf(family.face_width + rng.randf_range(-0.05, 0.05), 0.85, 1.15)
		look.jaw_width = clampf(family.jaw_width + rng.randf_range(-0.08, 0.08), 0.8, 1.25)
		look.nose_length = clampf(family.nose_length + rng.randf_range(-0.06, 0.06), 0.8, 1.25)
		look.nose_width = clampf(family.nose_width + rng.randf_range(-0.06, 0.06), 0.8, 1.3)
		look.eye_size = clampf(family.eye_size + rng.randf_range(-0.05, 0.05), 0.8, 1.3)
	else:
		look.face_width = rng.randf_range(0.9, 1.1)
		look.jaw_width = rng.randf_range(0.86, 1.0) if female else rng.randf_range(0.98, 1.2)
		look.nose_length = rng.randf_range(0.85, 1.18)
		look.nose_width = rng.randf_range(0.85, 1.25)
		look.eye_size = rng.randf_range(0.9, 1.12)
	look.chin = rng.randf_range(0.85, 1.25)
	look.cheekbones = rng.randf_range(0.2, 0.85)
	look.brow_ridge = rng.randf_range(0.15, 0.4) if female else rng.randf_range(0.35, 0.8)
	look.brow_thickness = rng.randf_range(0.7, 1.1) if female else rng.randf_range(0.95, 1.5)
	look.brow_arch = rng.randf_range(0.3, 0.9)
	look.eye_spacing = rng.randf_range(0.95, 1.05)
	look.eye_tilt = rng.randf_range(-0.1, 0.2)
	look.lash_weight = rng.randf_range(0.5, 0.9) if female else rng.randf_range(0.2, 0.5)
	look.nose_upturn = rng.randf_range(0.0, 0.6)
	look.lip_fullness = rng.randf_range(0.85, 1.3)
	look.mouth_width = rng.randf_range(0.92, 1.12)
	look.wrinkles = clampf(float(age - 35) / 35.0, 0.0, 1.0)
	look.freckles = rng.randf_range(0.4, 1.0) if look.skin_color.get_luminance() > 0.6 and rng.randf() < 0.3 else 0.0
	var resting := {}
	if rng.randf() < 0.6:
		resting["smile"] = snappedf(rng.randf_range(0.08, 0.3), 0.01)
	if rng.randf() < 0.25:
		resting["smirk"] = snappedf(rng.randf_range(0.2, 0.5), 0.01)
	if rng.randf() < 0.2:
		resting["brow_up"] = snappedf(rng.randf_range(0.1, 0.25), 0.01)
	look.resting_face = resting

	# --- Clothes ---
	look.shirt_color = _cloth_dye(rng, look.skin_color)
	look.accent_color = _cloth_dye(rng, look.skin_color)
	look.pants_color = _vary(rng, _pick(rng, PANTS), 0.02)
	look.shoe_color = _pick(rng, SHOES)
	look.sleeve_length = 1.0 if rng.randf() < 0.45 else rng.randf_range(0.3, 0.7)
	if female and rng.randf() < 0.65:
		look.tunic_length = rng.randf_range(0.7, 0.95)
		look.skirt_color = _cloth_dye(rng, look.skin_color)
	elif rng.randf() < 0.35:
		look.tunic_length = rng.randf_range(0.3, 0.5)
	else:
		look.tunic_length = 0.0

	# --- Accessories ---
	var items: Array[String] = []
	var job := Professions.info(profession)
	for item in job.get("accessories", []):
		if rng.randf() < 0.55:
			items.append(String(item))
	var extras: Array[String] = ["scarf", "satchel", "earrings", "flower", "backpack", "cloak", "glasses", "headband", "straw_hat", "wide_hat", "headwrap", "cap", "flower_crown", "necklace"]
	for i in rng.randi_range(0, 2):
		items.append(_pick(rng, extras))
	if elder and rng.randf() < 0.5:
		items.append("glasses")
	if not female and not teen:
		var beard := rng.randf()
		if beard < 0.12 or (elder and beard < 0.3):
			items.append("long_beard")
		elif beard < 0.5:
			items.append("beard")
	# One hat at most; flowers don't go under hats.
	var unique: Array[String] = []
	var has_hat := false
	for item in items:
		if unique.has(item):
			continue
		if item in HEADWEAR:
			if has_hat:
				continue
			has_hat = true
		unique.append(item)
	if has_hat:
		unique.erase("flower")
	# A full afro doesn't go under a hat or cap (a headband or flowers do).
	if look.hair_style == "afro":
		for hat in ["straw_hat", "wide_hat", "cap", "headwrap"]:
			unique.erase(hat)
	if look.hair_style == "balding" and not has_hat and rng.randf() < 0.3:
		unique.append("straw_hat")
	if unique.has("straw_hat") or unique.has("wide_hat"):
		look.hat_color = _vary(rng, Color(0.7, 0.55, 0.3) if unique.has("straw_hat") else _pick(rng, DYES), 0.04)
	look.accessories = PackedStringArray(unique)
	if unique.has("apron"):
		look.apron_color = _vary(rng, _pick(rng, [Color(0.86, 0.82, 0.72), Color(0.5, 0.4, 0.3), Color(0.4, 0.46, 0.34)]), 0.03)
	look.work_tool = String(job.get("tool", ""))
	return look
