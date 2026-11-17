class_name AnimalSpecies
extends RefCounted
## Every kind of animal: its model (Quaternius Farm Animals and Animal Pack
## Vol.2, CC0), how big it is in the world, which way the model faces, its
## animations, how it moves, where it lives and what it costs.
##
## scale/yaw were measured (the horse is a little bigger than its model's
## proportions suggest, so a grown rider looks right on it) from each model's skeleton: the farm animals face
## +Z, the dog, cat and wolf face +X (so they're turned a quarter).
## Animals without a walk animation (sheep, pig, pug) walk with a bobbing,
## swaying gait done in code.

const DIR := "res://assets/quaternius/animals/"

const SPECIES := {
	&"horse": {"eyes": [0.2, -0.1, 0.22, 0.075], "name": "Horse", "model": "Horse", "scale": 0.31, "yaw": 0.0, "walk": 1.4, "run": 5.5,
		"idle": "Idle", "walk_anim": "Walk", "run_anim": "Run", "home": "stable", "price": 40,
		"eats": true, "skittish": 0.2, "sound": "neigh", "names": ["Bramble", "Clover", "Juniper", "Ember", "Willow"],
		"radius": 0.7, "about": "A horse you can ride. Needs a stable.",
		"rideable": true, "ride_walk": 3.4, "ride_run": 9.5,
		# Where the saddle sits on the model (metres, in the animal's space)
		# and the bone it moves with.
		"saddle": Vector3(0.0, 1.5, -0.1), "saddle_bone": "Torso"},
	&"cow": {"eyes": [0.2, -0.12, 0.28, 0.08], "name": "Cow", "model": "Cow", "scale": 0.26, "yaw": 0.0, "walk": 0.9, "run": 3.0,
		"idle": "Idle", "walk_anim": "WalkSlow", "run_anim": "Run", "home": "pen", "price": 25,
		"eats": true, "skittish": 0.1, "sound": "moo", "milk": true, "names": ["Daisy", "Buttercup", "Bella", "Hazel", "Poppy"],
		"radius": 0.7, "about": "Gives milk every day (2 food). Lives in a pen."},
	&"sheep": {"eyes": [0.3, -0.05, 0.25, 0.09], "name": "Sheep", "model": "Sheep", "scale": 0.22, "yaw": 0.0, "walk": 0.8, "run": 3.2,
		"idle": "Idle", "walk_anim": "", "run_anim": "Jump", "home": "pen", "price": 15,
		"eats": true, "skittish": 0.7, "sound": "baa", "names": ["Woolly", "Cotton", "Fluff", "Nimbus", "Pebble"],
		"radius": 0.5, "about": "A friendly sheep. Lives in a pen."},
	&"pig": {"eyes": [0.3, 0.12, 0.38, 0.075], "name": "Pig", "model": "Pig", "scale": 0.17, "yaw": 0.0, "walk": 0.8, "run": 2.8,
		"idle": "Idle", "walk_anim": "", "run_anim": "Jump", "home": "pen", "price": 15,
		"eats": true, "skittish": 0.4, "sound": "oink", "names": ["Truffle", "Rosie", "Biscuit", "Porky", "Acorn"],
		"radius": 0.5, "about": "Roots about happily. Lives in a pen."},
	&"dog": {"coats": {"Dog": [Color(0.45, 0.3, 0.18), Color(0.52, 0.5, 0.47), Color(0.86, 0.76, 0.56), Color(0.16, 0.15, 0.14), Color(0.62, 0.34, 0.16)]}, "eyes": [0.3, 0.12, 0.36, 0.085], "head_bone": "Bone.003", "name": "Dog", "model": "Dog", "scale": 0.14, "yaw": -PI * 0.5, "walk": 1.6, "run": 5.0,
		"idle": "Idle", "walk_anim": "Walking", "run_anim": "Walking", "home": "house", "price": 12,
		"eats": false, "skittish": 0.0, "sound": "bark", "follows": true, "names": ["Rufus", "Scout", "Biscuit", "Pepper", "Max"],
		"radius": 0.4, "about": "Follows you when you ask. Lives by your home."},
	&"pug": {"eyes": [0.9, 0.35, 0.45, 0.12], "name": "Small dog", "model": "Pug", "scale": 0.19, "yaw": 0.0, "walk": 1.2, "run": 3.5,
		"idle": "Idle", "walk_anim": "", "run_anim": "Jump", "home": "house", "price": 10,
		"eats": false, "skittish": 0.0, "sound": "bark", "follows": true, "names": ["Pip", "Bean", "Nugget", "Toffee"],
		"radius": 0.3, "about": "A small dog. Follows you when you ask."},
	&"cat": {"coats": {"Grey": [Color(0.22, 0.22, 0.24), Color(0.85, 0.48, 0.2), Color(0.52, 0.5, 0.48), Color(0.12, 0.11, 0.11)], "White": [Color(0.95, 0.94, 0.92)], "Pink": [Color(0.95, 0.62, 0.68)]}, "coat_names": {"Ginger": 1, "Shadow": 3, "Misty": 2}, "eyes": [0.4, 0.14, 0.42, 0.1], "head_bone": "Bone.003", "name": "Cat", "model": "Cat", "scale": 0.092, "yaw": -PI * 0.5, "walk": 1.0, "run": 4.0,
		"idle": "Idle", "walk_anim": "Walking", "run_anim": "Walking", "home": "house", "price": 10,
		"eats": false, "skittish": 0.6, "sound": "meow", "names": ["Misty", "Tabby", "Shadow", "Ginger", "Socks"],
		"radius": 0.3, "about": "Comes and goes as it pleases. Lives by your home."},
}

## The order they're offered in the Shop.
const SHOP_ORDER: Array[StringName] = [&"dog", &"cat", &"pug", &"sheep", &"pig", &"cow", &"horse"]
## How many animals each home holds.
const CAPACITY := {"pen": 4, "stable": 2, "house": 3}


## Where an animal's eyes go, in its own space (facing +Z, metres), from its
## head bone and the bone at the tip of its snout and the species' "eyes"
## numbers: [how far along the head, how far up, how far out to each side,
## eye radius], all as fractions of the head's length. Returns
## [left eye centre, right eye centre, radius, head bone index], or [] if it
## has no eyes. (Some heads sit a little to one side in the rest pose, so the
## eyes are placed either side of the head's own middle.)
static func eye_points(info: Dictionary, skeleton: Skeleton3D, to_holder: Transform3D) -> Array:
	var e: Array = info.get("eyes", [])
	var head := skeleton.find_bone(String(info.get("head_bone", "Head")))
	if e.size() < 4 or head < 0:
		return []
	var tips := skeleton.get_bone_children(head)
	if tips.is_empty():
		return []
	var h := to_holder * skeleton.get_bone_global_rest(head).origin
	# The snout is the child bone furthest forward (others are ears).
	var snout := Vector3(0, 0, -INF)
	for tip in tips:
		var p := to_holder * skeleton.get_bone_global_rest(tip).origin
		if p.z > snout.z:
			snout = p
	var length := h.distance_to(snout)
	var at := h.lerp(snout, float(e[0])) + Vector3(0, float(e[1]) * length, 0)
	var side := Vector3(float(e[2]) * length, 0, 0)
	return [at + side, at - side, float(e[3]) * length, head]


## One eye, `r` across: a pale rim, a dark pupil looking outward (+X), and a
## tiny shine, so it reads on light and dark faces alike.
static func make_eye(r: float, side: float) -> Node3D:
	var eye := Node3D.new()
	eye.name = "Eye"
	var parts := [[r, Vector3.ZERO, Color(0.93, 0.9, 0.84), 0.4], [r * 0.78, Vector3(side * r * 0.32, 0, r * 0.08), Color(0.06, 0.05, 0.05), 0.15],
		[r * 0.22, Vector3(side * r * 0.95, r * 0.3, r * 0.3), Color(1, 1, 1), 0.1]]
	for part in parts:
		var mesh := SphereMesh.new()
		mesh.radius = part[0]
		mesh.height = float(part[0]) * 2.0
		mesh.radial_segments = 10
		mesh.rings = 6
		var material := StandardMaterial3D.new()
		material.albedo_color = part[2]
		material.roughness = part[3]
		mesh.material = material
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.position = part[1]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		eye.add_child(mi)
	return eye


## The hawks' colours (the model's own come through as plain white).
const EAGLE_COLOURS := {"Wings": Color(0.3, 0.17, 0.09), "Head": Color(0.95, 0.94, 0.9), "Beak": Color(0.95, 0.74, 0.2), "Claws": Color(0.95, 0.74, 0.2)}


## Gives a model's materials these colours, by material name.
static func paint(model: Node3D, colours: Dictionary) -> void:
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for i in mi.mesh.get_surface_count():
			var source := mi.get_active_material(i) as BaseMaterial3D
			if source == null or not colours.has(source.resource_name):
				continue
			var m := source.duplicate() as BaseMaterial3D
			m.albedo_color = colours[source.resource_name]
			mi.set_surface_override_material(i, m)


## This animal's coat: one colour from each of the species' palettes, picked
## by its name (some names suit a coat) or else by its id, so it stays the same.
static func coat_for(info: Dictionary, animal_id: String, animal_name: String) -> Dictionary:
	var coats: Dictionary = info.get("coats", {})
	var pick := int(info.get("coat_names", {}).get(animal_name, absi(hash(animal_id))))
	var out := {}
	for material in coats:
		var options: Array = coats[material]
		out[material] = options[pick % options.size()]
	return out


## Adds the eyes to a model in `holder` (the animal's own space), riding on
## the head bone so they follow its head.
static func add_eyes(info: Dictionary, model: Node3D, holder: Node3D) -> void:
	var skeletons := model.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		return
	var skeleton: Skeleton3D = skeletons[0]
	var to_holder := holder.global_transform.affine_inverse() * skeleton.global_transform
	var pts := eye_points(info, skeleton, to_holder)
	if pts.is_empty():
		return
	var attach := BoneAttachment3D.new()
	attach.name = "Eyes"
	attach.bone_name = skeleton.get_bone_name(int(pts[3]))
	skeleton.add_child(attach)
	var bone_in_holder := to_holder * skeleton.get_bone_global_rest(int(pts[3]))
	for i in 2:
		var eye := make_eye(float(pts[2]), 1.0 if i == 0 else -1.0)
		eye.name = "EyeL" if i == 0 else "EyeR"
		attach.add_child(eye)
		eye.transform = bone_in_holder.affine_inverse() * Transform3D(Basis(), pts[i])


static func info(species: StringName) -> Dictionary:
	return SPECIES.get(species, {})


static func home_label(home_kind: String) -> String:
	return {"pen": "an animal pen", "stable": "a stable", "house": "your home"}.get(home_kind, home_kind)
