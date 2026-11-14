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
}
const LOOPING := ["Idle", "Walk", "Jog_Fwd", "Jump", "Idle_Talking", "Sitting_Idle", "Crouch_Idle", "Dance",
	"Sword_Idle", "Sword_Attack", "PickUp_Table"]
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

var female: bool = false
var outfit: String = ""
var _playing_clip: String = ""
var _meshes: Array[MeshInstance3D] = []


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
	scale = Vector3.ONE * clampf(appearance.standing_height() / MODEL_HEIGHT, 0.55, 1.15)
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
	for mi in base.find_children("*", "MeshInstance3D", true, false):
		var source := mi as MeshInstance3D
		var tris := source.mesh.get_faces().size() / 3
		if tris > 5000:
			head = _attach(_head_mesh(base_name, source.mesh), source.skin, "Head")
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
		scene.free()
	_tint()
	# Animations.
	animation_player = AnimationPlayer.new()
	animation_player.name = "AnimationPlayer"
	add_child(animation_player)
	animation_player.root_node = animation_player.get_path_to(skeleton.get_parent())
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
static func _head_mesh(key: String, mesh: Mesh) -> Mesh:
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
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, mesh.surface_get_format(0) & ~Mesh.ARRAY_FORMAT_BLEND_SHAPE_MASK)
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
				m.albedo_color = _ratio(appearance.shirt_color.lightened(0.15), base, 0.45)
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


func seat_offset(seat_height: float) -> float:
	return seat_height - _sit_hips * scale.y


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
	if detail == Detail.FULL or animation_player == null:
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
