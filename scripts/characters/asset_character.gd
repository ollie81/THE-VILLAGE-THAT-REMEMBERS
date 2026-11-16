class_name AssetCharacter
extends CharacterModel
## A person built from real, artist-made models (Quaternius Universal Base
## Characters + Modular Character Outfits, CC0) and animated with the
## Universal Animation Library (CC0, motion-capture-style clips).
##
##   AssetCharacter (scaled by the person's height)
##   ├─ Rig                    the outfit's scene: Armature/Skeleton3D (65 bones)
##   │  └─ Skeleton3D          outfit pieces + head (cut from the base
##   │                          character) + eyes + hair + eyebrows, all skinned
##   └─ AnimationPlayer        the animation library, converted once
##
## The CharacterAppearance still decides everything: woman or man, outfit,
## hairstyle, skin, hair and clothing colours, so the Wardrobe, villager
## generator and saves keep working. Same API as CharacterModel.

const DIR := "res://assets/quaternius/characters/"
## Game animation state -> library clip.
const CLIPS := {
	&"idle": "Idle", &"walk": "Walk", &"run": "Jog_Fwd", &"jump": "Jump", &"work": "Sword_Attack",
	&"gather": "PickUp_Table", &"talk": "Idle_Talking", &"wave": "Interact", &"sit": "Sitting_Idle",
	&"sit_ground": "Crouch_Idle", &"sleep": "Death01", &"cheer": "Spell_Simple_Shoot", &"dance": "Dance",
	&"bow": "Interact", &"slash": "Sword_Attack", &"block": "Sword_Idle", &"dodge": "Roll", &"hurt": "Hit_Chest",
	&"swim": "Swim_Fwd", &"swim_idle": "Swim_Idle", &"ride": "Driving",
}
const LOOPING := ["Idle", "Walk", "Jog_Fwd", "Jump", "Idle_Talking", "Sitting_Idle", "Crouch_Idle", "Dance",
	"Sword_Idle", "Sword_Attack", "PickUp_Table", "Swim_Fwd", "Swim_Idle", "Driving"]
## The animation clips' own ground speeds (m/s at speed 1).
const WALK_CLIP_SPEED := 1.45
const RUN_CLIP_SPEED := 3.6
## Hairstyle -> hair model (none = shaved).
const HAIR := {
	"short": "Hair_SimpleParted", "curly": "Hair_SimpleParted", "long": "Hair_Long", "braids": "Hair_Long",
	"locs": "Hair_Long", "ponytail": "Hair_Long", "bun": "Hair_Buns", "afro": "Hair_Buzzed",
	"balding": "Hair_Buzzed", "bald": "",
}
## The base character's body is cut just under the jaw: only the head is
## used, the outfit is the body.
const NECK_CUT := 1.47
## Height of the base models (top of the head), to scale to each person.
const MODEL_HEIGHT := 1.8

static var _library: AnimationLibrary
static var _scenes: Dictionary = {}
static var _heads: Dictionary = {}
static var _texture_means: Dictionary = {}
static var _sit_hips: float = 0.55
static var _ride_hips: float = 0.55

var female: bool = false
## Height of the hair above the head bone (0 without hair).
var _hair_top: float = 0.0
var outfit: String = ""
var _playing_clip: String = ""
var _meshes: Array[MeshInstance3D] = []
## The open mouth while speaking (these faces have no mouth shapes of their
## own): a dark opening over the lips that opens and closes with the words.
var _mouth: MeshInstance3D
var _jaw_shape: int = -1


## True when real character models are installed (else the drawn ones are used).
static func available() -> bool:
	return ResourceLoader.exists(DIR + "outfits/Male_Peasant.gltf") and ResourceLoader.exists(DIR + "anim/AL_Standard.fbx")


static func is_female(look: CharacterAppearance) -> bool:
	return look.chest_shape > 0.13


## Peasant clothes for villagers; the ranger's tunic, hood-free, for
## adventurers (anyone in a travelling cloak, like the player).
static func outfit_for(look: CharacterAppearance) -> String:
	return ("Female_" if is_female(look) else "Male_") + ("Ranger" if look.has_accessory("cloak") or look.has_accessory("tool_belt") else "Peasant")


func _ready() -> void:
	_build_asset()
	set_animation(&"idle")


static func _scene(path: String) -> PackedScene:
	if not _scenes.has(path):
		_scenes[path] = load(path)
	return _scenes[path]


func _build_asset() -> void:
	female = is_female(appearance)
	outfit = outfit_for(appearance)
	var height_scale := clampf(appearance.standing_height() / MODEL_HEIGHT, 0.55, 1.15)
	# Slimmer or sturdier: a little wider or narrower, never distorted.
	var width := lerpf(0.93, 1.08, clampf((appearance.build_width - 0.8) / 0.5, 0.0, 1.0))
	scale = Vector3(height_scale * width, height_scale, height_scale * lerpf(0.97, 1.05, clampf((appearance.build_width - 0.8) / 0.5, 0.0, 1.0)))
	var rig := _scene(DIR + "outfits/%s.gltf" % outfit).instantiate() as Node3D
	rig.name = "Rig"
	add_child(rig)
	skeleton = rig.find_children("*", "Skeleton3D", true, false)[0]
	for mi in skeleton.find_children("*", "MeshInstance3D", false, false):
		# The ranger's hood stays down so faces and hair show.
		if String(mi.name).contains("Hood"):
			mi.queue_free()
			continue
		_meshes.append(mi)
		if String(mi.name).ends_with("_Body"):
			body = mi
	if body == null and not _meshes.is_empty():
		body = _meshes[0]
	# The head, face and eyes from the base character.
	var base_name := "Superhero_Female_FullBody" if female else "Superhero_Male_FullBody"
	var base := _scene(DIR + "base/%s.gltf" % base_name).instantiate()
	var base_skeleton: Skeleton3D = base.find_children("*", "Skeleton3D", true, false)[0]
	var head_rest := base_skeleton.get_bone_global_rest(base_skeleton.find_bone("Head")).origin
	for mi in base.find_children("*", "MeshInstance3D", true, false):
		var source := mi as MeshInstance3D
		var tris := source.mesh.get_faces().size() / 3
		if tris > 5000:
			head = _attach(_head_mesh(base_name, source.mesh, head_rest, female), source.skin, "Head")
			_jaw_shape = head.find_blend_shape_by_name(&"jaw_open")
		elif not String(source.name).to_lower().contains("brow") and String(source.name) != "Face":
			_attach(source.mesh, source.skin, "Eyes")
	base.free()
	# Hair, beard and eyebrows.
	var hair_model: String = HAIR.get(appearance.hair_style, "Hair_SimpleParted")
	if female and hair_model == "Hair_SimpleParted":
		hair_model = "Hair_Long" if appearance.hair_style != "short" else "Hair_BuzzedFemale"
	var hair_parts: Array[String] = []
	if hair_model != "":
		hair_parts.append(hair_model)
	if appearance.has_accessory("beard") or appearance.has_accessory("long_beard"):
		hair_parts.append("Hair_Beard")
	hair_parts.append("Eyebrows_Female" if female else "Eyebrows_Regular")
	for part in hair_parts:
		var scene := _scene(DIR + "hair/%s.gltf" % part).instantiate()
		var source: MeshInstance3D = scene.find_children("*", "MeshInstance3D", true, false)[0]
		_attach(source.mesh, source.skin, part)
		if part.begins_with("Hair_") and part != "Hair_Beard":
			# Hair is modelled on a head 5 cm lower than the men's; measure it
			# against its own head bone.
			var hair_skeleton: Skeleton3D = scene.find_children("*", "Skeleton3D", true, false)[0]
			var hair_head := hair_skeleton.get_bone_global_rest(hair_skeleton.find_bone("Head")).origin
			_hair_top = source.mesh.get_aabb().end.y - hair_head.y
		scene.free()
	_tint()
	_add_accessories()
	_add_mouth()
	# Animations.
	animation_player = AnimationPlayer.new()
	animation_player.name = "AnimationPlayer"
	add_child(animation_player)
	animation_player.root_node = animation_player.get_path_to(skeleton.get_parent())
	animation_player.mixer_applied.connect(_after_animation)
	animation_player.add_animation_library(&"", _get_library(skeleton))
	animation_player.playback_default_blend_time = BLEND_TIME
	# A villager's work tool in the hand.
	_tool = _create_tool(appearance.work_tool)
	if _tool:
		var attachment := BoneAttachment3D.new()
		attachment.name = "ToolAttachment"
		attachment.bone_name = bone_name(&"LeftHand" if appearance.work_tool == "basket" else &"RightHand")
		skeleton.add_child(attachment)
		attachment.add_child(_tool)
		_tool.visible = false


func _attach(mesh: Mesh, skin: Skin, part_name: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = part_name
	mi.mesh = mesh
	mi.skin = skin
	skeleton.add_child(mi)
	mi.skeleton = NodePath("..")
	_meshes.append(mi)
	return mi


## The base model's head and neck (triangles above the cut), shared by
## everyone with that base.
static func _head_mesh(key: String, mesh: Mesh, head_rest: Vector3 = Vector3.ZERO, is_female: bool = false) -> Mesh:
	if _heads.has(key):
		return _heads[key]
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var kept := PackedInt32Array()
	for i in range(0, indices.size(), 3):
		var a := indices[i]
		var b := indices[i + 1]
		var c := indices[i + 2]
		if minf(verts[a].y, minf(verts[b].y, verts[c].y)) > NECK_CUT:
			kept.append_array([a, b, c])
	arrays[Mesh.ARRAY_INDEX] = kept
	var result := ArrayMesh.new()
	var format: int = mesh.surface_get_format(0) & ~Mesh.ARRAY_FORMAT_BLEND_SHAPE_MASK & ~Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES
	var shapes: Array = []
	if head_rest != Vector3.ZERO:
		# Normalized: the shape holds the open face itself, blended in by weight.
		result.blend_shape_mode = Mesh.BLEND_SHAPE_MODE_NORMALIZED
		result.add_blend_shape(&"jaw_open")
		var lower := _split_lips(arrays, head_rest, is_female)
		shapes.append(_jaw_open(arrays, head_rest, is_female, lower))
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, shapes, {}, format)
	result.surface_set_material(0, mesh.surface_get_material(0))
	_heads[key] = result
	return result


# --- Colours ----------------------------------------------------------------------------

## Average colour of a texture (cached), to tint it toward a wanted colour.
static func _mean(texture: Texture2D) -> Color:
	if texture == null:
		return Color(0.5, 0.5, 0.5)
	var key := texture.resource_path
	if not _texture_means.has(key):
		var image := texture.get_image()
		if image == null:
			return Color(0.5, 0.5, 0.5)
		image = image.duplicate()
		if image.is_compressed():
			image.decompress()
		image.resize(1, 1, Image.INTERPOLATE_BILINEAR)
		_texture_means[key] = image.get_pixel(0, 0)
	return _texture_means[key]


static func _ratio(want: Color, have: Color, strength: float = 1.0) -> Color:
	var r := Color(want.r / maxf(have.r, 0.05), want.g / maxf(have.g, 0.05), want.b / maxf(have.b, 0.05))
	return Color(1, 1, 1).lerp(r, strength)


## Tints skin, hair and clothes toward the appearance's colours, each
## character with its own copies of the materials.
func _tint() -> void:
	for mi in _meshes:
		for s in mi.mesh.get_surface_count():
			var material := mi.get_active_material(s) as BaseMaterial3D
			if material == null:
				continue
			var m := material.duplicate() as BaseMaterial3D
			var mat_name := material.resource_name.to_lower()
			var base := _mean(m.albedo_texture)
			if mat_name.contains("hair") or String(mi.name).begins_with("Hair") or String(mi.name).begins_with("Eyebrows"):
				m.albedo_color = _ratio(appearance.hair_color, base)
			elif mat_name.contains("superhero") or mat_name.contains("regular"):
				m.albedo_color = _ratio(appearance.skin_color, base, 0.9)
			elif mat_name.contains("peasant") or mat_name.contains("ranger"):
				# Two weaves of each outfit, then a gentle dye of the shirt colour.
				if absi(hash(appearance.shirt_color)) % 2 == 1:
					var alt := DIR + "outfits/" + ("T_Peasant_2_BaseColor.png" if mat_name.contains("peasant") else "T_Ranger_3_BaseColor.png")
					if ResourceLoader.exists(alt):
						m.albedo_texture = load(alt)
						base = _mean(m.albedo_texture)
				# Each part of the outfit takes its own colour: shirt and sleeves,
				# trousers or skirt, shoes, and the trim pieces.
				var part := String(mi.name)
				var dye := appearance.shirt_color
				if part.contains("Legs"):
					dye = appearance.skirt_color if appearance.skirt_color.a > 0.0 else appearance.pants_color
				elif part.contains("Feet") or part.contains("Boots"):
					dye = appearance.shoe_color
				elif part.contains("Acc_"):
					dye = appearance.accent_color
				var strength := 0.35 + 0.3 * float(absi(hash(appearance.pants_color)) % 100) / 100.0
				m.albedo_color = _ratio(dye.lightened(0.15), base, strength)
			elif mat_name.contains("eye"):
				pass
			mi.set_surface_override_material(s, m)


# --- Animation ------------------------------------------------------------------------------

## The animation library converted once to these characters: same bones,
## but the source is in centimetres with Z up, so the root is left alone and
## the hips' movement is rescaled.
static func _get_library(target: Skeleton3D) -> AnimationLibrary:
	if _library:
		return _library
	var source := _scene(DIR + "anim/AL_Standard.fbx").instantiate()
	var player: AnimationPlayer = source.find_children("*", "AnimationPlayer", true, false)[0]
	var source_skeleton: Skeleton3D = source.find_children("*", "Skeleton3D", true, false)[0]
	var pelvis_from := source_skeleton.get_bone_rest(source_skeleton.find_bone("pelvis")).origin
	var pelvis_to := target.get_bone_rest(target.find_bone("pelvis")).origin
	var hips_scale := pelvis_to.length() / maxf(pelvis_from.length(), 0.00001)
	_library = AnimationLibrary.new()
	var wanted := {}
	for clip in CLIPS.values():
		wanted[clip] = true
	for clip: String in wanted:
		var source_name := "Rig|" + clip
		if not player.has_animation(source_name):
			push_warning("AssetCharacter: animation %s missing" % clip)
			continue
		var animation := player.get_animation(source_name).duplicate(true) as Animation
		for t in range(animation.get_track_count() - 1, -1, -1):
			var path := String(animation.track_get_path(t))
			var bone := path.get_slice(":", 1)
			var type := animation.track_get_type(t)
			if bone == "root" or bone == "" or type == Animation.TYPE_SCALE_3D:
				animation.remove_track(t)
				continue
			if type == Animation.TYPE_POSITION_3D:
				if bone != "pelvis":
					animation.remove_track(t)
					continue
				for k in animation.track_get_key_count(t):
					var v: Vector3 = animation.track_get_key_value(t, k)
					animation.track_set_key_value(t, k, pelvis_to + (v - pelvis_from) * hips_scale)
				if clip == "Sitting_Idle" and animation.track_get_key_count(t) > 0:
					_sit_hips = (animation.track_get_key_value(t, 0) as Vector3).z
				if clip == "Driving" and animation.track_get_key_count(t) > 0:
					_ride_hips = (animation.track_get_key_value(t, 0) as Vector3).z
			animation.track_set_path(t, NodePath("Skeleton3D:" + bone))
		animation.loop_mode = Animation.LOOP_LINEAR if LOOPING.has(clip) else Animation.LOOP_NONE
		_library.add_animation(StringName(clip), animation)
	source.free()
	return _library


func set_animation(state: StringName, speed: float = 0.0) -> void:
	if not CLIPS.has(state):
		state = &"idle"
	if state == &"walk" or state == &"run":
		var fallback := HumanoidAnimations.RUN_SPEED if state == &"run" else HumanoidAnimations.WALK_SPEED
		_target_speed = speed if speed > 0.0 else fallback
	else:
		_target_speed = 0.0
	_state = state
	if _tool:
		_tool.visible = state in WORK_ANIMATIONS
	_update_clip()


## Pose touches after the animation: legs astride a horse when riding.
func _after_animation() -> void:
	if _state == &"ride" and skeleton:
		RidingPose.apply(skeleton, self)


func _update_clip() -> void:
	if animation_player == null:
		return
	var clip: String = CLIPS.get(_state, "Idle")
	if _state == &"idle" and _talking:
		clip = "Idle_Talking"
	var rate := 1.0
	if _state == &"walk":
		rate = clampf(_target_speed / WALK_CLIP_SPEED, 0.6, 1.8)
	elif _state == &"run":
		rate = clampf(_target_speed / RUN_CLIP_SPEED, 0.7, 1.8)
	if clip != _playing_clip:
		_playing_clip = clip
		if animation_player.has_animation(clip):
			animation_player.play(clip, BLEND_TIME)
	animation_player.speed_scale = rate


func set_talking(talking: bool) -> void:
	if talking == _talking:
		return
	_talking = talking
	_update_clip()


func set_expression(expression: StringName, _weight: float = 1.0, _fade: float = EXPRESSION_FADE) -> void:
	# These faces have no expression shapes yet; remember it for the game.
	_expression = expression if FaceExpressions.EXPRESSIONS.has(expression) else &"neutral"


## The hip bone sits this far above the seat (the thighs and bottom are
## under it); without it a sitting person sinks into the chair.
const SEAT_CLEARANCE := 0.12


func hip_clearance() -> float:
	return SEAT_CLEARANCE * scale.y


func seat_offset(seat_height: float) -> float:
	return seat_height + hip_clearance() - _sit_hips * scale.y


## How far to raise the model so the riding pose sits in a saddle this high.
func ride_offset(saddle_height: float) -> float:
	return saddle_height + hip_clearance() - _ride_hips * scale.y


func get_face_position() -> Vector3:
	if skeleton == null:
		return global_position + Vector3(0, 1.65, 0)
	var bone := skeleton.find_bone("Head")
	var pose := skeleton.get_bone_global_pose(bone)
	return skeleton.global_transform * (pose.origin + Vector3(0, 0.09, 0.07))


## The asset rig names hands "hand_r" / "hand_l".
func bone_name(generic: StringName) -> StringName:
	match generic:
		&"RightHand":
			return &"hand_r"
		&"LeftHand":
			return &"hand_l"
		&"Head":
			return &"Head"
		&"Hips":
			return &"pelvis"
		&"LeftFoot":
			return &"foot_l"
		&"RightFoot":
			return &"foot_r"
		&"Spine":
			return &"spine_01"
		&"Neck":
			return &"neck_01"
	return generic


func _process(delta: float) -> void:
	if detail == Detail.FULL:
		_update_mouth(delta)
		return
	if _talk_weight > 0.0 and head and _jaw_shape >= 0:
		_talk_weight = 0.0
		head.set_blend_shape_value(_jaw_shape, 0.0)
	if animation_player == null:
		return
	_animation_delta += delta
	_animation_frame += 1
	if not _on_screen or _animation_frame < ANIMATION_STRIDE[detail]:
		return
	_animation_frame = 0
	animation_player.advance(minf(_animation_delta, 0.5))
	_animation_delta = 0.0


func set_detail(level: int, on_screen: bool = true) -> void:
	_on_screen = on_screen
	if level == detail or animation_player == null:
		return
	detail = level
	animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE if level == Detail.FULL \
		else AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_animation_frame = 0
	_animation_delta = 0.0
	# Apply the current pose now (a paused, far-away person mustn't stand in
	# the bind pose).
	animation_player.advance(0.0)
	for mi in _meshes:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if level == Detail.FAR \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_ON


# --- Accessories --------------------------------------------------------------------------

const STRAW := Color(0.86, 0.74, 0.45)
const LEATHER := Color(0.42, 0.28, 0.16)
const METAL := Color(0.75, 0.72, 0.6)

## Where the head is, measured on this model (relative to the head bone,
## in skeleton space): eye centre, top of the head, half its width.
func _head_metrics() -> Dictionary:
	var head_rest := skeleton.get_bone_global_rest(skeleton.find_bone("Head")).origin
	var eye := Vector3(0, 0.1, 0.09)
	for mi in _meshes:
		if String(mi.name) == "Eyes":
			eye = mi.mesh.get_aabb().get_center() - head_rest
	var top := 0.215
	if head:
		top = head.mesh.get_aabb().end.y - head_rest.y
	return {"eye": eye, "top": maxf(top, _hair_top - 0.02), "skull": top, "radius": 0.105 if not female else 0.1}


## The mouth (measured on both base heads, relative to the head bone): the
## lips meet 7.5 cm below the eyes, the man's at y 0.024, z 0.106, the
## woman's at y 0.032, z 0.100. Talking opens the jaw: the lower lip, chin
## and jaw turn down around a hinge by the ears, fading out towards the
## cheeks and the neck so nothing tears; a dark mouth inside shows through.
const LIP_LINE := {false: Vector2(0.024, 0.106), true: Vector2(0.032, 0.100)}
const JAW_ANGLE := 0.1
## How far behind the lips' front a triangle crossing between the lips is
## "inside the mouth" (removed when splitting). The two heads are built
## differently: the woman's lips curl back further, and all her crossing
## triangles close the lips at the front.
const INNER_STRADDLE_DEPTH := {false: 0.006, true: 1.0}
## Half the width of the mouth opening (the corners stay joined).
const MOUTH_HALF_WIDTH := 0.021
## The base models' head bones (rest positions).
const BASE_HEAD_REST := {false: Vector3(0, 1.5998, -0.0174), true: Vector3(0, 1.5496, -0.0109)}


## Where the lips meet, the upper and lower lip share vertices, so opening
## the jaw would only stretch them. This gives the lower lip's triangles
## their own copies of those vertices (across the mouth, not the corners),
## so the lips part. Returns per-vertex: 1 lower lip, -1 upper lip, 0 other.
static func _split_lips(arrays: Array, head_rest: Vector3, is_female: bool) -> PackedInt32Array:
	var lip: Vector2 = LIP_LINE[is_female]
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var count := verts.size()
	var side := PackedInt32Array()
	side.resize(count)
	# Behind each lip the surface curls about 2 cm inward; the two inner rows
	# (upper and lower) are joined by a thin strip deep in the mouth. Per
	# 2 mm column: the front of the lips, and the middle of that deep strip.
	var front := {}
	for v in verts:
		var r := v - head_rest
		if absf(r.x) <= MOUTH_HALF_WIDTH + 0.004 and absf(r.y - lip.x) <= 0.012:
			var k := int(round(r.x / 0.002))
			front[k] = maxf(float(front.get(k, -1.0)), r.z)
	var is_deep := func(r: Vector3) -> bool:
		var k := int(round(r.x / 0.002))
		return absf(r.x) <= MOUTH_HALF_WIDTH + 0.004 and absf(r.y - lip.x) <= 0.007 and front.has(k) and r.z < float(front[k]) - 0.012
	var deep_low := {}
	var deep_high := {}
	for v in verts:
		var r := v - head_rest
		if is_deep.call(r):
			var k := int(round(r.x / 0.002))
			deep_low[k] = minf(float(deep_low.get(k, 1.0)), r.y)
			deep_high[k] = maxf(float(deep_high.get(k, -1.0)), r.y)
	var crease_at := func(x: float) -> float:
		var k := int(round(x / 0.002))
		for d in [0, 1, -1, 2, -2]:
			if deep_low.has(k + d):
				return (float(deep_low[k + d]) + float(deep_high[k + d])) * 0.5
		return lip.x
	# The strip itself goes (it would stretch across the opening; the dark
	# mouth inside shows instead, and with the lips together it's hidden).
	var kept := PackedInt32Array()
	for t in range(0, indices.size(), 3):
		if is_deep.call(verts[indices[t]] - head_rest) and is_deep.call(verts[indices[t + 1]] - head_rest) and is_deep.call(verts[indices[t + 2]] - head_rest):
			continue
		kept.append_array([indices[t], indices[t + 1], indices[t + 2]])
	indices = kept
	# Each lip vertex is above or below the middle of the strip. Triangles
	# with corners on both sides close the lips at the front: they go with
	# the lower lip (so with the mouth shut they sit exactly where they were,
	# and open they come down with it instead of stretching).
	var in_zone := func(r: Vector3) -> bool:
		return absf(r.x) <= MOUTH_HALF_WIDTH and absf(r.y - lip.x) <= 0.014 and r.z > lip.y - 0.035
	var lower_tris: Array = []
	var upper_use := {}
	var cleaned := PackedInt32Array()
	for t in range(0, indices.size(), 3):
		var c := (verts[indices[t]] + verts[indices[t + 1]] + verts[indices[t + 2]]) / 3.0 - head_rest
		if not in_zone.call(c):
			cleaned.append_array([indices[t], indices[t + 1], indices[t + 2]])
			continue
		var ups := 0
		for k in 3:
			var r := verts[indices[t + k]] - head_rest
			if r.y > float(crease_at.call(r.x)):
				ups += 1
		if ups != 0 and ups != 3:
			# Inside the mouth (any corner well behind the lips' front): it
			# would zigzag across the opening; the dark inside shows instead.
			var inner := false
			for k in 3:
				var r := verts[indices[t + k]] - head_rest
				var col := int(round(r.x / 0.002))
				if front.has(col) and r.z < float(front[col]) - float(INNER_STRADDLE_DEPTH[is_female]):
					inner = true
			if inner:
				continue
		var at := cleaned.size()
		cleaned.append_array([indices[t], indices[t + 1], indices[t + 2]])
		if ups < 3:
			lower_tris.append(at)
		else:
			for k in 3:
				upper_use[indices[t + k]] = true
	indices = cleaned
	# Copy every attribute of each shared vertex once, for the lower lip.
	var copies := {}
	for t in lower_tris:
		for k in 3:
			var v := indices[t + k]
			if upper_use.has(v):
				if not copies.has(v):
					copies[v] = count + copies.size()
				indices[t + k] = copies[v]
	var order: Array = copies.keys()
	order.sort_custom(func(a, b): return copies[a] < copies[b])
	for a in Mesh.ARRAY_MAX:
		if a == Mesh.ARRAY_INDEX or arrays[a] == null:
			continue
		var data = arrays[a]
		var stride: int = data.size() / count
		for v in order:
			for s in stride:
				data.append(data[v * stride + s])
		arrays[a] = data
	arrays[Mesh.ARRAY_INDEX] = indices
	side.resize(count + order.size())
	for v in upper_use:
		side[v] = -1
	for t in lower_tris:
		for k in 3:
			side[indices[t + k]] = 1
	return side


## The "jaw_open" shape for the head mesh `arrays` (absolute positions).
## `lower`: from _split_lips (1 lower lip, -1 upper lip).
static func _jaw_open(arrays: Array, head_rest: Vector3, is_female: bool, lower: PackedInt32Array = PackedInt32Array()) -> Array:
	var lip: Vector2 = LIP_LINE[is_female]
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
	var tangents = arrays[Mesh.ARRAY_TANGENT]
	var pivot := head_rest + Vector3(0, lip.x + 0.025, -0.005)
	var moved := verts.duplicate()
	var moved_normals := normals.duplicate()
	for i in verts.size():
		var r := verts[i] - head_rest
		# Below the line where the lips meet (a soft edge 3 mm wide; across
		# the mouth the lips are split, so the lower lip moves and the upper
		# doesn't)...
		var w := clampf((lip.x + 0.0005 - r.y) / 0.003, 0.0, 1.0)
		if i < lower.size() and lower[i] != 0:
			w = 1.0 if lower[i] > 0 else 0.0
		# ...across the jaw, fading towards the cheeks...
		w *= 1.0 - smoothstep(0.03, 0.062, absf(r.x))
		# ...the front of the face, not the back of the jaw or the neck.
		w *= smoothstep(-0.01, 0.04, r.z)
		w *= clampf((r.y - (lip.x - 0.115)) / 0.03, 0.0, 1.0)  # not under the chin
		if w <= 0.0:
			continue
		var turn := Basis(Vector3.RIGHT, JAW_ANGLE * w)
		moved[i] = pivot + turn * (verts[i] - pivot)
		if i < normals.size():
			moved_normals[i] = (turn * normals[i]).normalized()
	var shape := []
	shape.resize(Mesh.ARRAY_MAX)
	shape[Mesh.ARRAY_VERTEX] = moved
	if not normals.is_empty():
		shape[Mesh.ARRAY_NORMAL] = moved_normals
	if tangents != null:
		shape[Mesh.ARRAY_TANGENT] = tangents
	return shape


## The inside of the mouth: dark, behind the lips, only seen when they part.
func _add_mouth() -> void:
	var lip: Vector2 = LIP_LINE[female]
	var head_rest := skeleton.get_bone_global_rest(skeleton.find_bone("Head")).origin
	# The outfit skeleton's head bone can sit a little apart from the base
	# model's; the lips are where the base head put them.
	var base_rest: Vector3 = BASE_HEAD_REST[female]
	var offset := base_rest + Vector3(0, lip.x - 0.006, lip.y - 0.024) - head_rest
	var b := MeshBuilder.new(1)
	b.color_jitter = 0.0
	b.add_blob_at(Vector3.ZERO, Vector3(0.021, 0.013, 0.014), Color(0.16, 0.04, 0.05), 10, 6, 0.0)
	_mouth = _on_bone("Head", offset, _built(b), "MouthInside")
	if _mouth:
		_mouth.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _update_mouth(delta: float) -> void:
	if head == null or _jaw_shape < 0:
		return
	var speaking := _talking or _state == &"talk"
	if speaking:
		_talk_phase += delta * 11.0
		_talk_weight = clampf(0.3 + 0.35 * sin(_talk_phase) + 0.2 * sin(_talk_phase * 1.7 + 0.4), 0.0, 0.85)
	else:
		_talk_weight = move_toward(_talk_weight, 0.0, delta * 6.0)
	head.set_blend_shape_value(_jaw_shape, _talk_weight)


## A mesh following bone `bone`, placed at skeleton-space `offset` from that
## bone's rest position.
func _on_bone(bone: String, offset: Vector3, mesh: Mesh, part_name: String) -> MeshInstance3D:
	var index := skeleton.find_bone(bone)
	if index < 0:
		return null
	var attachment := BoneAttachment3D.new()
	attachment.name = "Acc_" + part_name
	attachment.bone_name = bone
	skeleton.add_child(attachment)
	var rest := skeleton.get_bone_global_rest(index)
	var holder := Node3D.new()
	holder.transform = rest.affine_inverse() * Transform3D(Basis(), rest.origin + offset)
	attachment.add_child(holder)
	var mi := MeshInstance3D.new()
	mi.name = part_name
	mi.mesh = mesh
	holder.add_child(mi)
	_meshes.append(mi)
	return mi


func _built(builder: MeshBuilder) -> ArrayMesh:
	return builder.build(Materials.vertex_color())


## Hats, glasses, flowers, earrings, scarves, necklaces, bags, aprons and
## tool belts, made to fit these heads and bodies.
func _add_accessories() -> void:
	var h := _head_metrics()
	var r: float = h["radius"]
	var top: float = h["top"]
	var eye: Vector3 = h["eye"]
	var hat_color := appearance.hat_color if appearance.hat_color.a > 0.0 else Color(0, 0, 0, 0)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(appearance.skin_color) ^ hash(appearance.accent_color)
	for accessory in appearance.accessories:
		var b := MeshBuilder.new(rng.randi())
		b.color_jitter = 0.0
		match String(accessory):
			"straw_hat":
				var c := hat_color if hat_color.a > 0.0 else STRAW
				b.add_cylinder_at(Vector3(0, -0.01, 0), r * 2.3, r * 2.25, 0.02, 14, c)
				b.add_cylinder_at(Vector3(0, 0.0, 0), r * 1.05, r * 0.95, 0.09, 12, c.darkened(0.05))
				b.add_cylinder_at(Vector3(0, 0.0, 0), r * 1.07, r * 1.07, 0.025, 12, LEATHER)
				_on_bone("Head", Vector3(0, top - 0.035, -0.01), _built(b), "Hat")
			"wide_hat":
				var c := hat_color if hat_color.a > 0.0 else Color(0.3, 0.24, 0.2)
				b.add_cylinder_at(Vector3(0, -0.01, 0), r * 2.6, r * 2.5, 0.02, 16, c)
				b.add_cylinder_at(Vector3(0, 0.0, 0), r * 1.05, r * 0.85, 0.13, 12, c.lightened(0.05))
				b.add_cylinder_at(Vector3(0, 0.0, 0), r * 1.06, r * 1.02, 0.03, 12, appearance.accent_color)
				_on_bone("Head", Vector3(0, top - 0.035, -0.01), _built(b), "Hat")
			"cap":
				var c := hat_color if hat_color.a > 0.0 else appearance.accent_color
				b.add_blob_at(Vector3(0, 0.0, 0), Vector3(r * 1.08, r * 0.62, r * 1.1), c, 10, 5, 0.0)
				b.add_box_at(Vector3(0, -0.02, r * 1.05), Vector3(r * 1.3, 0.012, r * 0.8), c.darkened(0.15))
				_on_bone("Head", Vector3(0, top - 0.05, 0.0), _built(b), "Hat")
			"headband":
				b.add_cylinder_at(Vector3(0, 0, 0), r * 1.04, r * 1.04, 0.03, 14, appearance.accent_color)
				_on_bone("Head", Vector3(0, eye.y + 0.06, -0.005), _built(b), "Headband")
			"headwrap":
				var c := hat_color if hat_color.a > 0.0 else appearance.accent_color
				b.add_blob_at(Vector3(0, 0, 0), Vector3(r * 1.12, r * 0.85, r * 1.15), c, 10, 5, 0.06)
				_on_bone("Head", Vector3(0, top - 0.06, -0.01), _built(b), "Headwrap")
			"flower_crown":
				var colors := [Color(0.95, 0.45, 0.55), Color(1.0, 0.85, 0.35), Color(0.75, 0.55, 0.95), Color(1, 1, 1)]
				for i in 10:
					var a := TAU * i / 10.0
					var p := Vector3(cos(a) * r * 1.0, 0, sin(a) * r * 1.0)
					b.add_blob_at(p, Vector3(0.022, 0.022, 0.022), colors[i % colors.size()], 6, 3, 0.0)
					b.add_blob_at(p + Vector3(0, -0.012, 0), Vector3(0.018, 0.01, 0.018), Color(0.3, 0.55, 0.28), 5, 2, 0.0)
				_on_bone("Head", Vector3(0, top - 0.045, -0.01), _built(b), "FlowerCrown")
			"flower":
				b.add_blob_at(Vector3.ZERO, Vector3(0.028, 0.028, 0.022), Color(0.95, 0.5, 0.6), 7, 3, 0.0)
				b.add_blob_at(Vector3(0, 0, 0.012), Vector3(0.012, 0.012, 0.01), Color(1.0, 0.85, 0.3), 5, 2, 0.0)
				_on_bone("Head", Vector3(r * 0.95, eye.y + 0.02, eye.z - 0.07), _built(b), "Flower")
			"glasses":
				for side in [-1.0, 1.0]:
					b.add_cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(side * 0.03, 0, 0)), 0.02, 0.02, 0.004, 10, Color(0.2, 0.15, 0.12))
					b.add_box_at(Vector3(side * 0.06, 0.003, -0.04), Vector3(0.004, 0.004, 0.08), Color(0.2, 0.15, 0.12))
				b.add_box_at(Vector3(0, 0.004, 0), Vector3(0.02, 0.004, 0.004), Color(0.2, 0.15, 0.12))
				_on_bone("Head", Vector3(0, eye.y, eye.z + 0.025), _built(b), "Glasses")
			"earrings":
				for side in [-1.0, 1.0]:
					b.add_blob_at(Vector3(side * r * 0.82, 0, 0), Vector3(0.008, 0.012, 0.008), Color(0.95, 0.8, 0.35), 6, 3, 0.0)
				_on_bone("Head", Vector3(0, eye.y - 0.05, eye.z - 0.075), _built(b), "Earrings")
			"scarf":
				b.add_cylinder_at(Vector3(0, -0.03, 0), 0.085, 0.095, 0.08, 12, appearance.accent_color)
				b.add_box_at(Vector3(0.03, -0.12, 0.08), Vector3(0.05, 0.14, 0.02), appearance.accent_color.darkened(0.08))
				_on_bone("neck_01", Vector3(0, 0.0, 0.02), _built(b), "Scarf")
			"necklace":
				b.add_cylinder_at(Vector3(0, 0, 0), 0.075, 0.09, 0.006, 14, METAL)
				b.add_blob_at(Vector3(0, -0.06, 0.09), Vector3(0.012, 0.016, 0.006), Color(0.6, 0.3, 0.7), 6, 3, 0.0)
				_on_bone("neck_01", Vector3(0, -0.03, 0.02), _built(b), "Necklace")
			"backpack":
				b.add_box_at(Vector3.ZERO, Vector3(0.28, 0.34, 0.14), LEATHER.lightened(0.1))
				b.add_box_at(Vector3(0, 0.12, 0.0), Vector3(0.3, 0.06, 0.16), LEATHER)
				b.add_box_at(Vector3(0, -0.06, -0.075), Vector3(0.18, 0.12, 0.03), LEATHER.darkened(0.1))
				_on_bone("spine_03", Vector3(0, -0.05, -0.2), _built(b), "Backpack")
			"satchel":
				b.add_box_at(Vector3.ZERO, Vector3(0.06, 0.18, 0.22), LEATHER.lightened(0.05))
				_on_bone("pelvis", Vector3(0.2, 0.02, 0.02), _built(b), "Satchel")
			"apron":
				var c := appearance.apron_color if appearance.apron_color.a > 0.0 else Color(0.9, 0.88, 0.8)
				b.add_box_at(Vector3(0, -0.12, 0), Vector3(0.3, 0.36, 0.012), c)
				_on_bone("pelvis", Vector3(0, 0.05, 0.16), _built(b), "Apron")
			"tool_belt":
				b.add_cylinder_at(Vector3(0, 0, 0), 0.19, 0.19, 0.05, 14, LEATHER)
				b.add_box_at(Vector3(0.15, -0.06, 0.08), Vector3(0.06, 0.1, 0.05), LEATHER.lightened(0.1))
				b.add_box_at(Vector3(-0.15, -0.08, 0.06), Vector3(0.02, 0.16, 0.02), METAL)
				_on_bone("pelvis", Vector3(0, 0.06, 0.0), _built(b), "ToolBelt")
