class_name AgeLook
extends RefCounted
## How someone looks at a given age. A person's stored appearance is how they
## look at `look_age` (their adult face and build); this derives:
## - children and teens: child proportions (BodyProportions), a rounder,
##   softer face with bigger eyes and a small nose, no beard, smaller clothes
##   details, no work tools.
## - growing older than `look_age`: greying hair, lines, and an old person's
##   stoop.

const GREY := Color(0.72, 0.7, 0.67)
const WHITE := Color(0.88, 0.87, 0.85)
const ADULT_ONLY := ["beard", "long_beard", "tool_belt", "apron", "glasses", "earrings"]


static func for_age(base: CharacterAppearance, age: int, look_age: int, sex: String = "") -> CharacterAppearance:
	var look: CharacterAppearance = base.duplicate(true)
	look.youth = BodyProportions.youth_for_age(age)
	if look.youth > 0.0:
		_make_young(look, look.youth)
	elif age > look_age:
		_make_older(look, age, look_age)
	return look


## A bucket that changes when someone's looks change enough to rebuild their
## character: every year while growing up, every five years after (once they
## are older than their stored look).
static func visual_stage(age: int, look_age: int) -> int:
	if age < 18:
		return age
	if age <= look_age:
		return 18
	return 100 + int(age / 5)


static func _make_young(look: CharacterAppearance, y: float) -> void:
	look.eye_size = clampf(look.eye_size * (1.0 + 0.24 * y), 0.8, 1.45)
	look.eye_spacing = clampf(look.eye_spacing * (1.0 + 0.04 * y), 0.9, 1.12)
	look.nose_length = look.nose_length * (1.0 - 0.32 * y)
	look.nose_width = look.nose_width * (1.0 - 0.2 * y)
	look.nose_upturn = clampf(look.nose_upturn + 0.5 * y, 0.0, 1.0)
	look.jaw_width = look.jaw_width * (1.0 - 0.16 * y)
	look.chin = look.chin * (1.0 - 0.3 * y)
	look.mouth_width = look.mouth_width * (1.0 - 0.12 * y)
	look.cheekbones = look.cheekbones * (1.0 - 0.6 * y)
	look.brow_ridge = look.brow_ridge * (1.0 - y)
	look.brow_thickness = look.brow_thickness * (1.0 - 0.35 * y)
	look.lip_fullness = look.lip_fullness * (1.0 - 0.1 * y)
	look.face_width = clampf(look.face_width * (1.0 + 0.08 * y), 0.85, 1.2)
	look.wrinkles = 0.0
	look.stoop = 0.0
	look.chest_shape = look.chest_shape * clampf(1.0 - y * 1.6, 0.0, 1.0)
	look.build_width = lerpf(look.build_width, 1.0, y * 0.6)
	look.work_tool = ""
	var items := PackedStringArray()
	for item in look.accessories:
		if item in ADULT_ONLY or (y > 0.5 and item in ["cloak", "scarf"]):
			continue
		items.append(item)
	look.accessories = items
	# Small children have a little smile most of the time.
	var resting: Dictionary = look.resting_face.duplicate()
	resting["smile"] = maxf(float(resting.get("smile", 0.0)), 0.25 * y)
	resting.erase("smirk")
	look.resting_face = resting


static func _make_older(look: CharacterAppearance, age: int, look_age: int) -> void:
	var years := float(age - look_age)
	look.wrinkles = clampf(look.wrinkles + years / 35.0, 0.0, 1.0)
	if age >= 45:
		var grey := clampf((age - 40.0) / 30.0, 0.0, 1.0)
		var target := WHITE if age >= 70 else GREY
		if look.hair_color.get_luminance() < target.get_luminance():
			look.hair_color = look.hair_color.lerp(target, grey)
		if look.brow_color.a > 0.0:
			look.brow_color = look.brow_color.lerp(target, grey * 0.6)
	if age >= 65:
		look.stoop = maxf(look.stoop, clampf((age - 62.0) / 40.0, 0.0, 0.3))
