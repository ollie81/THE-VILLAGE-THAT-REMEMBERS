class_name HumanoidMeshBuilder
extends RefCounted
## Generates a complete skinned 3D person from a CharacterAppearance:
## anatomy (torso, limbs, hands with fingers, shoes, sculpted head and face),
## clothing layers, hair and accessories. Everything is one mesh, bound to a
## HumanoidRig skeleton, so it deforms with skeletal animation.
##
## Coordinates: model space in metres, feet on y = 0, facing +Z, character's
## left on +X.

const B := HumanoidRig.Bone
const LEATHER := Color(0.36, 0.23, 0.13)
## Stylised proportions: heads slightly larger than life read better from
## the high management camera and give faces room for expression.
const HEAD_SCALE := 1.15

## Head cross-sections relative to the Head joint: [y, half_width, front, back, z_offset].
const HEAD_PROFILE := [
	[-0.026, 0.048, 0.032, 0.024, 0.046],
	[0.0, 0.082, 0.068, 0.056, 0.028],
	[0.035, 0.093, 0.082, 0.076, 0.015],
	[0.075, 0.098, 0.094, 0.093, 0.006],
	[0.12, 0.099, 0.095, 0.104, 0.0],
	[0.16, 0.097, 0.09, 0.108, -0.005],
	[0.2, 0.086, 0.078, 0.1, -0.008],
	[0.235, 0.067, 0.057, 0.081, -0.012],
	[0.251, 0.045, 0.037, 0.054, -0.013],
	[0.262, 0.014, 0.011, 0.016, -0.014],
]

var look: CharacterAppearance
var rig: HumanoidRig
var t: SkinnedMeshTool

var _skin: Color
var _shirt: Color
var _pants: Color
var _hair: Color
var _torso_rows: Array = []
## Facial controls for the head currently being built (see FaceExpressions).
var _controls: Dictionary = {}

## Accessories that belong to the head mesh (and so follow expressions).
const HEAD_ACCESSORIES := ["beard", "long_beard", "glasses", "straw_hat", "wide_hat", "headband", "headwrap", "flower", "earrings"]
## Rows of the sculpted head grid, in unscaled profile units above the head
## joint. Dense around the eyes, nose and mouth where detail matters.
const SKIN_ROWS := [-0.042, -0.033, -0.022, -0.011, 0.0, 0.012, 0.023, 0.032, 0.039, 0.045, 0.051, 0.058,
	0.066, 0.075, 0.085, 0.095, 0.104, 0.112, 0.12, 0.128, 0.137, 0.146, 0.156, 0.168, 0.182, 0.198, 0.215,
	0.232, 0.246, 0.258]
const SKIN_SEGMENTS := 32
const MOUTH_Y := 0.044
const EYE_Y := 0.116


## Child proportions applied to the finished meshes (null for adults).
var _proportions: BodyProportions


func _init(appearance: CharacterAppearance, humanoid_rig: HumanoidRig) -> void:
	look = appearance
	# Everyone is modelled as an adult; children are reshaped afterwards.
	rig = humanoid_rig.adult()
	_proportions = appearance.proportions()
	t = SkinnedMeshTool.new(hash(appearance.skin_color) ^ hash(appearance.hair_style))
	_skin = look.skin_color
	_shirt = look.shirt_color
	_pants = look.pants_color
	_hair = look.hair_color
	t.skin_color = _skin


func build() -> ArrayMesh:
	_build_torso()
	for side: float in [1.0, -1.0]:
		_build_arm(side)
		_build_hand(side)
		_build_leg(side)
		_build_shoe(side)
	_build_clothing_details()
	_build_all_accessories(false)
	t.apply_proportions(_proportions)
	return t.build(Materials.character_body())


## The head as its own skinned mesh (same skeleton) with one blend shape per
## facial expression, plus "blink" and "talk".
func build_head() -> ArrayMesh:
	var body_tool := t
	var base := _build_head_tool(FaceExpressions.resting(look), PackedByteArray(), null)
	var shapes: Array = []
	for shape in FaceExpressions.SHAPES:
		shapes.append(_build_head_tool(FaceExpressions.controls_for(shape, look), base.flip_log, base))
	t = body_tool
	head_triangle_count = base.get_triangle_count()
	base.apply_proportions(_proportions)
	for shape: SkinnedMeshTool in shapes:
		shape.apply_proportions(_proportions)
	return base.build_with_shapes(Materials.character_face(), FaceExpressions.SHAPES, shapes)


var head_triangle_count: int = 0


func _build_head_tool(controls: Dictionary, replay: PackedByteArray, base: SkinnedMeshTool) -> SkinnedMeshTool:
	var tool := SkinnedMeshTool.new(hash(look.hair_style) ^ hash(look.skin_color) ^ 7919)
	tool.color_jitter = 0.0
	tool.replay_flips(replay)
	tool.static_source = base
	tool.skin_color = _skin
	tool.deformer = _face_deform
	t = tool
	_controls = controls
	# Parts that never change with expression are built once (static).
	if t.begin_static():
		_build_neck()
		_build_ears()
		_build_hair()
	t.end_static()
	# Same random sequence for the expression-dependent parts in every build.
	t.rng.seed = hash(look.skin_color) ^ 104729
	_build_head_skin()
	_build_eyes()
	_build_brows()
	_build_nose()
	_build_mouth()
	_build_skin_details()
	if look.has_accessory("beard") or look.has_accessory("long_beard"):
		_build_beard(look.has_accessory("long_beard"))
	if t.begin_static():
		_build_all_accessories(true)
	t.end_static()
	return tool


func get_triangle_count() -> int:
	return t.get_triangle_count()


# --- Helpers ------------------------------------------------------------------------

func _bind(bone: int) -> Vector3:
	return SkinnedMeshTool.bind(bone)


func _blend(a: int, b: int, w: float) -> Vector3:
	return SkinnedMeshTool.blend(a, b, w)


func _head_origin() -> Vector3:
	return rig.joint(B.HEAD)


## Head cross-section at profile height y (relative to the head joint, in
## unscaled profile units). Returns [y, half_width, front, back, z] in metres,
## with HEAD_SCALE applied.
func _head_section(y: float) -> Array:
	var row := _profile_raw(y)
	return [y * HEAD_SCALE, row[1] * HEAD_SCALE * look.face_width, row[2] * HEAD_SCALE, row[3] * HEAD_SCALE, row[4] * HEAD_SCALE]


## Unscaled profile row at height y: [y, half_width, front, back, z].
func _profile_raw(y: float) -> Array:
	var row: Array = HEAD_PROFILE[HEAD_PROFILE.size() - 1]
	var first: Array = HEAD_PROFILE[0]
	if y <= first[0]:
		row = first
	else:
		for i in HEAD_PROFILE.size() - 1:
			var a: Array = HEAD_PROFILE[i]
			var b: Array = HEAD_PROFILE[i + 1]
			if y <= b[0]:
				var k: float = (y - a[0]) / (b[0] - a[0])
				row = [y, lerpf(a[1], b[1], k), lerpf(a[2], b[2], k), lerpf(a[3], b[3], k), lerpf(a[4], b[4], k)]
				break
	return row


## Offset from the head joint, given in unscaled profile units.
func _head_point(local: Vector3) -> Vector3:
	return _head_origin() + local * HEAD_SCALE


## A ring that hugs the head at height y, pushed outward by `grow`.
func _head_ring(y: float, grow: float, binding: Vector3, color: Color) -> Dictionary:
	var s := _head_section(y)
	var center := _head_origin() + Vector3(0, s[0], s[4])
	return SkinnedMeshTool.ring(center, s[1] + grow, s[2] + grow, s[3] + grow, binding, color)


## Point on the head surface (for placing features) at height y, angle a
## (0 = character's right side, PI/2 = front, PI = left side).
func _head_surface(y: float, a: float, grow: float = 0.0) -> Vector3:
	var s := _head_section(y)
	var f := sin(a)
	var depth: float = f * ((s[2] if f > 0.0 else s[3]) + grow)
	return _head_origin() + Vector3(-cos(a) * (s[1] + grow), s[0], s[4] + depth)


## Torso half-width and front/back depth at height y.
func _torso_section(y: float) -> Array:
	var first: Array = _torso_rows[0]
	if y <= first[0]:
		return first
	for i in _torso_rows.size() - 1:
		var a: Array = _torso_rows[i]
		var b: Array = _torso_rows[i + 1]
		if y <= b[0]:
			var k: float = (y - a[0]) / (b[0] - a[0])
			return [y, lerpf(a[1], b[1], k), lerpf(a[2], b[2], k), lerpf(a[3], b[3], k), lerpf(a[4], b[4], k)]
	return _torso_rows[_torso_rows.size() - 1]


func _torso_front(y: float) -> float:
	var s := _torso_section(y)
	return s[4] + s[2]


func _torso_back(y: float) -> float:
	var s := _torso_section(y)
	return s[4] - s[3]


# --- Body ---------------------------------------------------------------------------

func _build_torso() -> void:
	t.material_id = SkinnedMeshTool.Surface.CLOTH
	var sw := rig.shoulder_half / 0.19
	var hw := rig.hip_half / 0.092
	var chest := look.chest_shape
	# [y, half_width, front, back, z]
	_torso_rows = [
		[0.86, 0.12 * hw, 0.075, 0.085, 0.0],
		[0.95, 0.152 * hw, 0.088, 0.104, 0.0],
		[1.03, 0.14 * lerpf(hw, sw, 0.35), 0.085, 0.088, 0.0],
		[1.13, 0.138 * lerpf(hw, sw, 0.6), 0.09, 0.084, -0.002],
		[1.24, 0.152 * sw, 0.095 + chest * 0.012, 0.088, -0.006],
		[1.33, 0.162 * sw, 0.098 + chest * 0.024, 0.09, -0.01],
		[1.405, 0.158 * sw, 0.084 + chest * 0.012, 0.085, -0.014],
		[1.445, 0.13 * sw, 0.064, 0.07, -0.016],
		[1.475, 0.056, 0.046, 0.05, -0.016],
	]
	var binds: Array[Vector3] = [
		_bind(B.HIPS), _bind(B.HIPS), _blend(B.HIPS, B.SPINE, 0.35), _bind(B.SPINE),
		_blend(B.SPINE, B.CHEST, 0.5), _bind(B.CHEST), _bind(B.CHEST), _bind(B.CHEST), _blend(B.CHEST, B.NECK, 0.3),
	]
	var rings: Array = []
	for i in _torso_rows.size():
		var row: Array = _torso_rows[i]
		var color := _shirt
		if i == 0 or (i == 1 and look.tunic_length < 0.3):
			color = _pants
		rings.append(SkinnedMeshTool.ring(Vector3(0, row[0], row[4]), row[1], row[2], row[3], binds[i], color))
	t.loft(rings, 12)

	# Shoulder caps: a short sleeve-coloured bridge from the collarbone into
	# the top of each arm, so the arms grow out of the body.
	for side: float in [1.0, -1.0]:
		var upper := HumanoidRig.sided(B.LEFT_UPPER_ARM, side)
		# Distance from the spine; the joint's x is already signed per side.
		var shoulder := Vector3(absf(rig.joint(upper).x), 0, 0)
		t.loft([
			SkinnedMeshTool.ring(Vector3(side * 0.07, 1.445, -0.014), 0.045, 0.05, 0.055, _bind(B.CHEST), _sleeve_color(1.43)),
			SkinnedMeshTool.ring(Vector3(side * (shoulder.x * 0.6 + 0.03), 1.44, -0.015), 0.05, 0.055, 0.058, _blend(B.CHEST, upper, 0.3), _sleeve_color(1.43)),
			SkinnedMeshTool.ring(Vector3(side * shoulder.x, 1.42, -0.015), 0.052, 0.054, 0.054, _blend(B.CHEST, upper, 0.75), _sleeve_color(1.43)),
			SkinnedMeshTool.ring(Vector3(side * (shoulder.x + 0.008), 1.38, -0.015), 0.05, 0.05, 0.052, _bind(upper), _sleeve_color(1.43)),
		], 9, Vector3.BACK, true, false)


func _build_neck() -> void:
	t.material_id = SkinnedMeshTool.Surface.SKIN
	var neck := rig.joint(B.NECK)
	t.loft([
		SkinnedMeshTool.ring(Vector3(0, 1.42, neck.z), 0.05, 0.05, 0.048, _bind(B.CHEST), _skin),
		SkinnedMeshTool.ring(Vector3(0, 1.5, neck.z + 0.002), 0.046, 0.046, 0.046, _bind(B.NECK), _skin),
		SkinnedMeshTool.ring(Vector3(0, 1.6, neck.z + 0.004), 0.044, 0.044, 0.044, _bind(B.HEAD), _skin),
	], 9, Vector3.BACK, false, false)


func _sleeve_color(y: float) -> Color:
	var cuff_y := lerpf(1.25, 0.94, look.sleeve_length)
	var sleeve := look.accent_color if look.has_accessory("cloak") else _shirt
	return sleeve if y > cuff_y else _skin


func _build_arm(side: float) -> void:
	t.material_id = SkinnedMeshTool.Surface.CLOTH
	var upper := HumanoidRig.sided(B.LEFT_UPPER_ARM, side)
	var lower := HumanoidRig.sided(B.LEFT_LOWER_ARM, side)
	var hand := HumanoidRig.sided(B.LEFT_HAND, side)
	var shoulder := rig.joint(upper)
	var elbow := rig.joint(lower)
	var wrist := rig.joint(hand)
	# [y, half_width, front, back, binding]
	var rows := [
		[1.4, 0.05, 0.05, 0.052, _bind(upper)],
		[1.33, 0.049, 0.047, 0.049, _bind(upper)],
		[1.21, 0.046, 0.046, 0.044, _bind(upper)],
		[1.15, 0.043, 0.044, 0.045, _blend(upper, lower, 0.5)],
		[1.08, 0.044, 0.046, 0.042, _bind(lower)],
		[0.97, 0.036, 0.036, 0.034, _bind(lower)],
		[0.915, 0.029, 0.031, 0.029, _blend(lower, hand, 0.3)],
	]
	var cuff_y := lerpf(1.25, 0.94, look.sleeve_length)
	var rings: Array = []
	for row in rows:
		var y: float = row[0]
		var center := _limb_center(y, shoulder, elbow, wrist)
		var sleeve_grow := 0.004 if y > cuff_y else 0.0
		rings.append(SkinnedMeshTool.ring(center, row[1] + sleeve_grow, row[2] + sleeve_grow, row[3] + sleeve_grow, row[4], _sleeve_color(y)))
	t.loft(rings, 9)
	# Cuff band at the end of the sleeve.
	var cuff_center := _limb_center(cuff_y, shoulder, elbow, wrist)
	var radius := 0.05 if cuff_y > 1.15 else 0.042
	var cuff_bind := _bind(upper) if cuff_y > 1.15 else _bind(lower)
	var cuff_color := _sleeve_color(cuff_y + 0.01).darkened(0.15)
	t.loft([
		SkinnedMeshTool.ring(cuff_center + Vector3(0, 0.016, 0), radius + 0.01, radius + 0.01, radius + 0.01, cuff_bind, cuff_color),
		SkinnedMeshTool.ring(cuff_center - Vector3(0, 0.012, 0), radius + 0.008, radius + 0.008, radius + 0.008, cuff_bind, cuff_color),
	], 9, Vector3.BACK, false, false)


## Position along a two-segment limb at height y.
func _limb_center(y: float, top: Vector3, middle: Vector3, bottom: Vector3) -> Vector3:
	if y >= middle.y:
		return top.lerp(middle, clampf((top.y - y) / (top.y - middle.y), 0.0, 1.0)) + Vector3(0, y - top.lerp(middle, clampf((top.y - y) / (top.y - middle.y), 0.0, 1.0)).y, 0)
	var k := clampf((middle.y - y) / (middle.y - bottom.y), 0.0, 1.2)
	var p := middle.lerp(bottom, k)
	return Vector3(p.x, y, p.z)


func _build_hand(side: float) -> void:
	t.material_id = SkinnedMeshTool.Surface.SKIN
	var hand := HumanoidRig.sided(B.LEFT_HAND, side)
	var bind := _bind(hand)
	var w := rig.joint(hand)
	var inward := -side
	# Palm: thin side-to-side, wide front-to-back (palm faces the thigh).
	t.loft([
		SkinnedMeshTool.ring(w + Vector3(0, 0.005, 0), 0.02, 0.03, 0.028, bind, _skin),
		SkinnedMeshTool.ring(w + Vector3(inward * 0.002, -0.035, 0.003), 0.022, 0.042, 0.037, bind, _skin),
		SkinnedMeshTool.ring(w + Vector3(inward * 0.004, -0.075, 0.004), 0.018, 0.043, 0.04, bind, _skin),
	], 8)
	# Four fingers, gently curled toward the palm.
	var finger_z: Array[float] = [0.03, 0.011, -0.009, -0.028]
	var finger_len: Array[float] = [0.058, 0.064, 0.06, 0.05]
	for i in 4:
		var base := w + Vector3(inward * 0.004, -0.072, 0.004 + finger_z[i])
		var mid := base + Vector3(inward * 0.006, -finger_len[i] * 0.55, 0.0)
		var tip := base + Vector3(inward * 0.016, -finger_len[i], 0.0)
		var radius := 0.0095 if i < 3 else 0.0085
		t.loft([
			SkinnedMeshTool.ring(base, radius, radius, radius, bind, _skin),
			SkinnedMeshTool.ring(mid, radius * 0.92, radius * 0.92, radius * 0.92, bind, _skin),
			SkinnedMeshTool.ring(tip, radius * 0.7, radius * 0.7, radius * 0.7, bind, _skin),
		], 5)
	# Thumb, on the front edge of the palm, pointing forward and down.
	var thumb_base := w + Vector3(inward * 0.006, -0.022, 0.03)
	t.loft([
		SkinnedMeshTool.ring(thumb_base, 0.013, 0.013, 0.013, bind, _skin),
		SkinnedMeshTool.ring(thumb_base + Vector3(inward * 0.006, -0.03, 0.022), 0.011, 0.011, 0.011, bind, _skin),
		SkinnedMeshTool.ring(thumb_base + Vector3(inward * 0.011, -0.055, 0.028), 0.008, 0.008, 0.008, bind, _skin),
	], 5)


func _build_leg(side: float) -> void:
	t.material_id = SkinnedMeshTool.Surface.CLOTH
	var upper := HumanoidRig.sided(B.LEFT_UPPER_LEG, side)
	var lower := HumanoidRig.sided(B.LEFT_LOWER_LEG, side)
	var foot := HumanoidRig.sided(B.LEFT_FOOT, side)
	var hip := rig.joint(upper)
	var knee := rig.joint(lower)
	var ankle := rig.joint(foot)
	var hw := rig.hip_half / 0.092
	var rows := [
		[0.98, 0.088 * hw, 0.09, 0.095, _bind(upper)],
		[0.86, 0.083 * hw, 0.085, 0.088, _bind(upper)],
		[0.7, 0.07, 0.075, 0.072, _bind(upper)],
		[0.56, 0.056, 0.06, 0.058, _bind(upper)],
		[0.51, 0.053, 0.058, 0.054, _blend(upper, lower, 0.5)],
		[0.44, 0.054, 0.055, 0.062, _bind(lower)],
		[0.33, 0.056, 0.052, 0.07, _bind(lower)],
		[0.2, 0.042, 0.042, 0.045, _bind(lower)],
		[0.12, 0.036, 0.038, 0.04, _blend(lower, foot, 0.4)],
	]
	var rings: Array = []
	for row in rows:
		var y: float = row[0]
		var center := _limb_center(y, hip, knee, ankle)
		if y > hip.y:
			center = Vector3(hip.x, y, hip.z)
		rings.append(SkinnedMeshTool.ring(center, row[1], row[2], row[3], row[4], _pants))
	t.loft(rings, 9)
	# Boot shaft over the lower leg, with a turned-down cuff.
	t.material_id = SkinnedMeshTool.Surface.LEATHER
	var shoe := look.shoe_color
	var boot_rows := [
		[0.27, 0.058, 0.058, 0.066, _bind(lower), shoe.darkened(0.12)],
		[0.245, 0.054, 0.054, 0.062, _bind(lower), shoe],
		[0.17, 0.047, 0.047, 0.052, _bind(lower), shoe],
		[0.1, 0.044, 0.046, 0.048, _blend(lower, foot, 0.5), shoe],
		[0.07, 0.042, 0.046, 0.048, _bind(foot), shoe],
	]
	var boot_rings: Array = []
	for row in boot_rows:
		var y: float = row[0]
		boot_rings.append(SkinnedMeshTool.ring(_limb_center(y, hip, knee, ankle), row[1], row[2], row[3], row[4], row[5]))
	t.loft(boot_rings, 9, Vector3.BACK, false, true)


func _build_shoe(side: float) -> void:
	t.material_id = SkinnedMeshTool.Surface.LEATHER
	var foot := HumanoidRig.sided(B.LEFT_FOOT, side)
	var ankle := rig.joint(foot)
	var bind := _bind(foot)
	var shoe := look.shoe_color
	var x := ankle.x
	# Lofted from heel to toe; "front" radii point up, "back" radii point down.
	t.loft([
		SkinnedMeshTool.ring(Vector3(x, 0.045, ankle.z - 0.055), 0.034, 0.038, 0.045, bind, shoe),
		SkinnedMeshTool.ring(Vector3(x, 0.05, ankle.z - 0.01), 0.041, 0.045, 0.05, bind, shoe),
		SkinnedMeshTool.ring(Vector3(x + side * 0.003, 0.04, ankle.z + 0.06), 0.045, 0.032, 0.04, bind, shoe),
		SkinnedMeshTool.ring(Vector3(x + side * 0.004, 0.032, ankle.z + 0.12), 0.043, 0.024, 0.032, bind, shoe),
		SkinnedMeshTool.ring(Vector3(x + side * 0.004, 0.027, ankle.z + 0.152), 0.028, 0.016, 0.027, bind, shoe.darkened(0.05)),
	], 9, Vector3.UP)
	# Darker sole.
	t.box(Transform3D(Basis.IDENTITY, Vector3(x + side * 0.003, 0.006, ankle.z + 0.045)), Vector3(0.084, 0.012, 0.21), shoe.darkened(0.45), bind)


# --- Face ---------------------------------------------------------------------------
# Everything below works in "profile units": metres relative to the head joint
# before HEAD_SCALE is applied. _hp() converts a profile-space point to model
# space.

func _hp(local: Vector3) -> Vector3:
	return _head_origin() + local * HEAD_SCALE


func _c(control: String) -> float:
	return float(_controls.get(control, 0.0))


static func _gauss(dx: float, dy: float, radius: float) -> float:
	return exp(-(dx * dx + dy * dy) / (radius * radius))


## Head cross-section with this character's face proportions: [rx, front, back, z].
func _face_section(y: float) -> Array:
	var row := _profile_raw(y)
	var rx: float = row[1] * look.face_width * lerpf(look.jaw_width, 1.0, smoothstep(0.0, 0.085, y))
	var front: float = row[2]
	if y < 0.02:
		front += (look.chin - 1.0) * 0.012 * (1.0 - smoothstep(-0.04, 0.02, y))
	return [rx, front, row[3], row[4]]


## Point on the sculpted skin (profile units). a = 0 right side, PI/2 front.
func _skin_local(y: float, a: float, sculpt: bool = true) -> Vector3:
	var sec := _face_section(y)
	var f := sin(a)
	var y_out := y
	if y < 0.0:
		y_out -= (look.chin - 1.0) * 0.02 * smoothstep(0.0, -0.042, y)
	var p := Vector3(-cos(a) * float(sec[0]), y_out, float(sec[3]) + f * float(sec[1] if f > 0.0 else sec[2]))
	if sculpt:
		p += _sculpt(p, f)
	return p


## Anatomy layered over the base head shape: brow ridge, eye sockets,
## cheekbones, nose bridge, muzzle, chin.
func _sculpt(p: Vector3, facing: float) -> Vector3:
	var front := smoothstep(0.15, 0.7, facing)
	if front <= 0.0:
		return Vector3.ZERO
	var d := Vector3.ZERO
	var es := 0.036 * look.eye_spacing
	for s: float in [1.0, -1.0]:
		d.z -= 0.0075 * _gauss(p.x - s * es, (p.y - EYE_Y) * 1.15, 0.024) * front
		var cheek := _gauss(p.x - s * 0.058, p.y - 0.086, 0.024) * front * (0.4 + look.cheekbones)
		d += Vector3(s * 0.004, 0.0, 0.004) * cheek
		d.z -= 0.003 * look.wrinkles * _gauss(p.x - s * 0.055, p.y - 0.045, 0.02) * front
	d.z += 0.0045 * (0.4 + look.brow_ridge) * _gauss(p.x * 0.6, p.y - 0.15, 0.022) * front
	d.z += 0.005 * _gauss(p.x, p.y - 0.12, 0.012) * front
	d.z += 0.006 * _gauss(p.x * 0.8, p.y - 0.047, 0.03) * front
	d.z -= 0.0025 * _gauss(p.x * 0.5, p.y - 0.024, 0.01) * front
	d.z += 0.006 * look.chin * _gauss(p.x * 0.9, p.y + 0.012, 0.018) * front
	return d


## Skin point in front of the face at (x, y), pushed out by `grow`.
func _skin_xy(x: float, y: float, grow: float = 0.0) -> Vector3:
	var sec := _face_section(y)
	var a := acos(clampf(-x / float(sec[0]), -0.999, 0.999))
	var p := _skin_local(y, a)
	var outward := (p - Vector3(0, y, float(sec[3]))).normalized()
	return p + outward * grow


## Natural skin colour variation: warm cheeks, nose and chin, soft shadow
## around the eyes, a lighter forehead.
func _skin_tint(p: Vector3, facing: float) -> Color:
	var front := smoothstep(0.1, 0.6, facing)
	var es := 0.036 * look.eye_spacing
	var blush := 0.12 * _gauss(p.x, p.y - 0.085, 0.016) + 0.06 * _gauss(p.x, p.y, 0.025)
	var shade := 0.0
	for s: float in [1.0, -1.0]:
		blush += 0.16 * _gauss(p.x - s * 0.052, p.y - 0.074, 0.026)
		shade += 0.08 * _gauss(p.x - s * es, p.y - 0.1, 0.014)
		shade += 0.05 * _gauss(p.x - s * es * 1.05, p.y - 0.128, 0.012)
	var light := 0.035 * _gauss(p.x * 0.5, p.y - 0.18, 0.03)
	var warm := _skin.lerp(Color(0.86, 0.38, 0.34), 0.55)
	return _skin.lerp(warm, blush * front).darkened(shade * front).lightened(light * front)


func _face_deform(p: Vector3) -> Vector3:
	var q := (p - _head_origin()) / HEAD_SCALE
	var front := smoothstep(-0.03, 0.05, q.z)
	if front <= 0.0:
		return p
	var smile := _c("smile")
	var d := Vector3.ZERO
	var open := _c("open")
	if open > 0.0:
		var jaw := smoothstep(MOUTH_Y + 0.002, MOUTH_Y - 0.016, q.y) * front
		d.y -= 0.022 * open * jaw
		d.z -= 0.003 * open * jaw
	var mw := 0.024 * look.mouth_width
	for s: float in [1.0, -1.0]:
		var corner := _gauss(q.x - s * mw, q.y - MOUTH_Y, 0.017) * front
		var lift := 0.011 * smile - 0.01 * _c("frown") + (0.01 * _c("smirk") if s > 0.0 else 0.0)
		d += Vector3(s * (0.003 * smile - 0.006 * _c("round")), lift, -0.002 * smile) * corner
		var cheek := _gauss(q.x - s * 0.05, q.y - 0.074, 0.022) * front
		var raise := smile + 0.5 * _c("squint") + (0.5 * _c("smirk") if s > 0.0 else 0.0)
		d += Vector3(s * 0.0012, 0.0035, 0.0028) * cheek * raise
	var band := _gauss(0.0, q.y - 0.15, 0.022) * front * (1.0 - smoothstep(0.06, 0.1, absf(q.x)))
	d.y += 0.004 * _c("brow_up") * band
	var inner := _gauss(absf(q.x) - 0.018, q.y - 0.142, 0.016) * front
	d.y += inner * (0.004 * _c("brow_sad") - 0.0045 * _c("brow_down"))
	d.z += inner * 0.0015 * _c("brow_down")
	return p + d * HEAD_SCALE


func _build_head_skin() -> void:
	t.material_id = SkinnedMeshTool.Surface.SKIN
	var head := _bind(B.HEAD)
	var start := t.vertex_count()
	var grid: Array = []
	var tints: Array = []
	for y in SKIN_ROWS:
		var points: Array[Vector3] = []
		var colors: Array[Color] = []
		for k in SKIN_SEGMENTS:
			var a := TAU * float(k) / SKIN_SEGMENTS
			var local := _skin_local(y, a)
			points.append(_face_deform(_hp(local)))
			colors.append(_skin_tint(local, sin(a)))
		grid.append(points)
		tints.append(colors)
	for i in SKIN_ROWS.size() - 1:
		var y_mid: float = (SKIN_ROWS[i] + SKIN_ROWS[i + 1]) * 0.5
		var center := _hp(Vector3(0, y_mid, float(_face_section(y_mid)[3])))
		var lower: Array[Vector3] = grid[i]
		var upper: Array[Vector3] = grid[i + 1]
		var cl: Array[Color] = tints[i]
		var cu: Array[Color] = tints[i + 1]
		for k in SKIN_SEGMENTS:
			var k1 := (k + 1) % SKIN_SEGMENTS
			t.triangle_colors(lower[k], lower[k1], upper[k1], cl[k], cl[k1], cu[k1], center, head, head, head)
			t.triangle_colors(lower[k], upper[k1], upper[k], cl[k], cu[k1], cu[k], center, head, head, head)
	# Close the chin and the crown.
	var first: Array[Vector3] = grid[0]
	var first_c: Array[Color] = tints[0]
	var chin := _face_deform(_hp(Vector3(0, float(SKIN_ROWS[0]) - 0.008, float(_face_section(-0.04)[3]) + 0.01)))
	var last: Array[Vector3] = grid[SKIN_ROWS.size() - 1]
	var last_c: Array[Color] = tints[SKIN_ROWS.size() - 1]
	var crown := _hp(Vector3(0, 0.265, -0.014))
	for k in SKIN_SEGMENTS:
		var k1 := (k + 1) % SKIN_SEGMENTS
		t.triangle_colors(chin, first[k], first[k1], _skin, first_c[k], first_c[k1], chin + Vector3(0, 0.02, 0), head, head, head)
		t.triangle_colors(crown, last[k], last[k1], _skin, last_c[k], last_c[k1], crown - Vector3(0, 0.02, 0), head, head, head)
	t.smooth_from(start)


func _build_ears() -> void:
	t.material_id = SkinnedMeshTool.Surface.SKIN
	var head := _bind(B.HEAD)
	var warm := _skin.lerp(Color(0.86, 0.38, 0.34), 0.08)
	for s: float in [1.0, -1.0]:
		var sec := _face_section(0.105)
		var c := Vector3(s * (float(sec[0]) - 0.003), 0.103, float(sec[3]) - 0.012)
		var turn := Basis(Vector3.UP, s * 0.38)
		t.ellipsoid(Transform3D((turn * Basis.from_scale(Vector3(0.0075, 0.03, 0.019))).scaled(Vector3.ONE * HEAD_SCALE), _hp(c)), warm, head, 10, 6)
		t.ellipsoid(Transform3D((turn * Basis.from_scale(Vector3(0.0035, 0.017, 0.011))).scaled(Vector3.ONE * HEAD_SCALE),
			_hp(c + Vector3(s * 0.0045, -0.002, 0.002))), _skin.darkened(0.22), head, 8, 4)
		t.ellipsoid(Transform3D((turn * Basis.from_scale(Vector3(0.0055, 0.0075, 0.0065))).scaled(Vector3.ONE * HEAD_SCALE),
			_hp(c + Vector3(0, -0.025, 0.004))), warm, head, 7, 4)


## Eye placement in profile units: centre, radius and forward direction.
func _eye(s: float) -> Dictionary:
	var x := 0.036 * look.eye_spacing * s
	var r := 0.0172 * look.eye_size
	var sec := _face_section(EYE_Y)
	var a := acos(clampf(-x / float(sec[0]), -0.999, 0.999))
	var surface := _skin_local(EYE_Y, a, false)
	var forward := Vector3(s * 0.12, 0.0, 1.0).normalized()
	return {"c": Vector3(x, EYE_Y, surface.z - r * 0.58), "r": r, "fwd": forward}


func _build_eyes() -> void:
	t.material_id = SkinnedMeshTool.Surface.DETAIL
	var head := _bind(B.HEAD)
	var lid_skin := _skin.darkened(0.05)
	var lash := Color(0.07, 0.05, 0.04).lerp(_hair.darkened(0.5), 0.3)
	for s: float in [1.0, -1.0]:
		var e := _eye(s)
		var c := _hp(e["c"])
		var r: float = float(e["r"]) * HEAD_SCALE
		var fwd: Vector3 = e["fwd"]
		var x_axis := Vector3.UP.cross(fwd).normalized()
		var y_axis := fwd.cross(x_axis).normalized()
		var basis := Basis(x_axis, y_axis, fwd)
		# Eyeball, iris (darker rim), pupil and a catchlight.
		t.ellipsoid(Transform3D(basis.scaled(Vector3.ONE * r), c), Color(0.95, 0.93, 0.89), head, 14, 9)
		var iris := look.eye_color
		var rings: Array = []
		for step in [[0.72, iris.darkened(0.6)], [0.64, iris.darkened(0.1)], [0.46, iris.lightened(0.22)], [0.29, Color(0.03, 0.03, 0.03)], [0.0, Color(0.03, 0.03, 0.03)]]:
			var psi: float = step[0]
			var radius := r * sin(psi)
			rings.append(SkinnedMeshTool.ring(c + fwd * r * (cos(psi) + 0.03), radius, radius, radius, head, step[1]))
		t.loft(rings, 14, y_axis, false, true)
		t.ellipsoid_at(c + fwd * r * 1.06 + y_axis * r * 0.3 - x_axis * r * 0.25 * s, Vector3.ONE * r * 0.09, Color(1, 1, 1), head, 6, 4)
		t.ellipsoid_at(c - x_axis * r * 0.92 * s - y_axis * r * 0.05 + fwd * r * 0.25, Vector3(r * 0.2, r * 0.15, r * 0.15), Color(0.86, 0.55, 0.52), head, 6, 4)
		# Eyelids: caps around the eyeball whose opening follows the expression.
		var tilt := s * (0.5 * look.eye_tilt + 0.32 * _c("brow_down") - 0.28 * _c("brow_sad"))
		var lid_basis := Basis(fwd, tilt) * basis
		var upper := clampf(0.78 - 0.3 * _c("wide") + 0.32 * _c("squint") + 0.18 * _c("brow_sad") + 0.12 * _c("brow_down"), 0.5, 2.0)
		upper = lerpf(upper, 2.24, _c("blink"))
		var lower := clampf(0.56 + 0.45 * _c("squint") + 0.15 * _c("smile") - 0.15 * _c("wide"), 0.4, 1.3)
		lower = lerpf(lower, 0.98, _c("blink"))
		_lid(c, lid_basis, r, upper, true, lid_skin, lash)
		_lid(c, lid_basis, r, lower, false, lid_skin, _skin.darkened(0.2))
		t.material_id = SkinnedMeshTool.Surface.DETAIL


## One eyelid: a cap around the eyeball from its pole down to `extent`
## radians, with a darker rolled edge (the lash line).
func _lid(c: Vector3, basis: Basis, r: float, extent: float, upper: bool, skin: Color, edge: Color) -> void:
	t.material_id = SkinnedMeshTool.Surface.SKIN
	var head := _bind(B.HEAD)
	var start := t.vertex_count()
	var pole := basis.y if upper else -basis.y
	var ax := basis.x
	var az := basis.z
	var radius := r * (1.1 if upper else 1.07)
	var lash_width := (0.06 + 0.1 * look.lash_weight) if upper else 0.05
	var rows := [
		[0.0, radius, skin], [extent * 0.4, radius, skin], [extent * 0.72, radius * 1.01, skin.darkened(0.06 if upper else 0.0)],
		[extent - lash_width, radius * 1.02, edge], [extent - 0.02, radius * 1.07, edge], [extent, radius * 1.0, edge],
	]
	var segments := 16
	var grid: Array = []
	for row in rows:
		var phi: float = row[0]
		var rr: float = row[1]
		var points: Array[Vector3] = []
		for k in segments:
			var theta := TAU * float(k) / segments
			points.append(c + (pole * cos(phi) + (ax * cos(theta) + az * sin(theta)) * sin(phi)) * rr)
		grid.append(points)
	for i in rows.size() - 1:
		var a: Array[Vector3] = grid[i]
		var b: Array[Vector3] = grid[i + 1]
		var color: Color = rows[i + 1][2]
		for k in segments:
			var k1 := (k + 1) % segments
			t.triangle(a[k], a[k1], b[k1], color, c, head, head, head)
			t.triangle(a[k], b[k1], b[k], color, c, head, head, head)
	t.smooth_from(start)


func _build_brows() -> void:
	t.material_id = SkinnedMeshTool.Surface.DETAIL
	var head := _bind(B.HEAD)
	var color := look.brow_color if look.brow_color.a > 0.0 else _hair.darkened(0.15)
	var up := 0.012 * _c("brow_up")
	var sad := _c("brow_sad")
	var angry := _c("brow_down")
	for s: float in [1.0, -1.0]:
		var inner := Vector2(s * (0.015 - 0.005 * angry), 0.15 + up + 0.012 * sad - 0.011 * angry)
		var peak := Vector2(s * 0.04, 0.158 + 0.006 * look.brow_arch + up + 0.005 * sad - 0.003 * angry)
		var outer := Vector2(s * 0.066, 0.149 + up * 0.8 - 0.005 * sad + 0.004 * angry)
		var rings: Array = []
		var samples := 6
		for i in samples:
			var k := float(i) / (samples - 1)
			var q := inner.lerp(peak, k).lerp(peak.lerp(outer, k), k)
			var thick := lerpf(0.0078, 0.0036, pow(k, 1.3)) * look.brow_thickness
			var p := _hp(_skin_xy(q.x, q.y, 0.0022))
			rings.append(SkinnedMeshTool.ring(p, thick * HEAD_SCALE, 0.0024 * HEAD_SCALE, 0.0016 * HEAD_SCALE, head, color))
		t.loft(rings, 6, Vector3.BACK)


func _build_nose() -> void:
	t.material_id = SkinnedMeshTool.Surface.SKIN
	var head := _bind(B.HEAD)
	var length := look.nose_length
	var width := look.nose_width
	var lift := 0.002 * _c("smile")
	var root := _skin_xy(0.0, 0.122)
	var tip := _skin_xy(0.0, 0.122 - 0.035 * length) + Vector3(0, 0.003 * look.nose_upturn + lift, 0.012 * length)
	var bridge := root.lerp(tip, 0.45) + Vector3(0, 0, 0.003)
	t.loft([
		SkinnedMeshTool.ring(_hp(root), 0.0055 * width * HEAD_SCALE, 0.003 * HEAD_SCALE, 0.004 * HEAD_SCALE, head, _skin),
		SkinnedMeshTool.ring(_hp(bridge), 0.0068 * width * HEAD_SCALE, 0.0045 * HEAD_SCALE, 0.005 * HEAD_SCALE, head, _skin),
		SkinnedMeshTool.ring(_hp(root.lerp(tip, 0.82)), 0.0095 * width * HEAD_SCALE, 0.0065 * HEAD_SCALE, 0.007 * HEAD_SCALE, head, _skin),
		SkinnedMeshTool.ring(_hp(tip), 0.006 * width * HEAD_SCALE, 0.004 * HEAD_SCALE, 0.004 * HEAD_SCALE, head, _skin),
	], 9, Vector3.BACK)
	var tip_color := _skin.lerp(Color(0.86, 0.38, 0.34), 0.1)
	t.ellipsoid_at(_hp(tip + Vector3(0, -0.002, -0.002)), Vector3(0.0095 * width, 0.0085, 0.0085) * HEAD_SCALE, tip_color, head, 10, 6)
	var flare := 1.0 + 0.15 * _c("brow_down") + 0.1 * _c("smile")
	for s: float in [1.0, -1.0]:
		t.ellipsoid_at(_hp(tip + Vector3(s * 0.0092 * width * flare, -0.0035 + lift, -0.007)), Vector3(0.0062, 0.0056, 0.007) * HEAD_SCALE, tip_color.darkened(0.04), head, 8, 5)
		t.ellipsoid_at(_hp(tip + Vector3(s * 0.0052 * width, -0.0082, -0.004)), Vector3(0.0034, 0.0015, 0.0026) * HEAD_SCALE, _skin.darkened(0.5), head, 6, 3)


func _build_mouth() -> void:
	t.material_id = SkinnedMeshTool.Surface.DETAIL
	var head := _bind(B.HEAD)
	var smile := _c("smile")
	var open := _c("open")
	var round := _c("round")
	var full := look.lip_fullness
	var half := 0.027 * look.mouth_width * (1.0 + 0.12 * smile - 0.28 * round)
	var corner_left := MOUTH_Y + 0.011 * smile - 0.01 * _c("frown") + 0.01 * _c("smirk")
	var corner_right := MOUTH_Y + 0.011 * smile - 0.01 * _c("frown")
	var upper_y := MOUTH_Y + 0.0025 + 0.003 * open + 0.001 * round
	var lower_y := MOUTH_Y - 0.0015 - 0.022 * open - 0.002 * round
	var lip := _skin.darkened(0.12).lerp(Color(0.72, 0.3, 0.3), 0.32)
	# Mouth interior and teeth sit just over the skin, hidden until the lips part.
	var mouth_z := _skin_xy(0.0, MOUTH_Y).z
	t.ellipsoid_at(_hp(Vector3(0, (upper_y + lower_y) * 0.5, mouth_z + 0.0012)), Vector3(half * 0.92, 0.002 + 0.5 * (upper_y - lower_y), 0.004) * HEAD_SCALE,
		Color(0.24, 0.07, 0.07), head, 12, 5)
	t.ellipsoid_at(_hp(Vector3(0, upper_y - 0.0016, mouth_z + 0.002)), Vector3(half * 0.7, 0.0028, 0.003) * HEAD_SCALE, Color(0.95, 0.94, 0.88), head, 10, 4)
	t.ellipsoid_at(_hp(Vector3(0, lower_y + 0.0022, mouth_z + 0.0016)), Vector3(half * 0.6, 0.0022, 0.0028) * HEAD_SCALE, Color(0.93, 0.92, 0.86), head, 10, 4)
	for upper: bool in [true, false]:
		var rings: Array = []
		var samples := 9
		for i in samples:
			var k := float(i) / (samples - 1)
			var x := lerpf(-half, half, k)
			var center_weight := pow(maxf(1.0 - pow(2.0 * k - 1.0, 2.0), 0.0), 0.75)
			var corner_y := lerpf(corner_right, corner_left, k)
			var line_y := lerpf(corner_y, upper_y if upper else lower_y, center_weight)
			var thick := 0.0013 + (0.0052 if upper else 0.0066) * full * center_weight
			if upper:
				line_y += 0.0008 * (_gauss(k - 0.36, 0.0, 0.08) + _gauss(k - 0.64, 0.0, 0.08))
			var y := line_y + (thick * 0.6 if upper else -thick * 0.6)
			var z := _skin_xy(x, y).z + 0.003 + 0.002 * center_weight * full + 0.004 * round * center_weight
			var depth := (0.0012 + 0.0035 * full * center_weight) * HEAD_SCALE
			rings.append(SkinnedMeshTool.ring(_hp(Vector3(x, y, z)), thick * HEAD_SCALE, depth, 0.002 * HEAD_SCALE, head,
				lip.darkened(0.06) if upper else lip.lightened(0.04)))
		t.loft(rings, 8, Vector3.BACK)
	for corner: Vector3 in [Vector3(half, corner_left, 0.0), Vector3(-half, corner_right, 0.0)]:
		var p := _skin_xy(corner.x, corner.y, 0.0018)
		t.ellipsoid_at(_hp(p), Vector3(0.0018, 0.0018, 0.0012) * HEAD_SCALE, lip.darkened(0.3), head, 6, 3)


## Age lines and freckles, drawn as fine creases and dots on the skin.
func _build_skin_details() -> void:
	t.material_id = SkinnedMeshTool.Surface.DETAIL
	t.deform = true
	var w := look.wrinkles
	if w > 0.0:
		var crease := _skin.darkened(0.2 + 0.1 * w)
		for i in 2:
			var y := 0.17 + i * 0.011
			_skin_crease([Vector2(-0.04, y + 0.002), Vector2(0.0, y - 0.001), Vector2(0.04, y + 0.002)], 0.0011 * w, crease)
		for s: float in [1.0, -1.0]:
			var corner := Vector2(s * 0.057 * look.eye_spacing, 0.118)
			for angle: float in [-0.5, 0.0, 0.45]:
				var dir := Vector2(s * cos(angle), sin(angle))
				_skin_crease([corner, corner + dir * 0.006, corner + dir * 0.013], 0.0008 * w, crease)
			_skin_crease([Vector2(s * 0.016, 0.076), Vector2(s * 0.029, 0.056), Vector2(s * 0.031, 0.034)], 0.0012 * w, crease)
			_skin_crease([Vector2(s * 0.027, 0.102), Vector2(s * 0.038, 0.098), Vector2(s * 0.05, 0.102)], 0.001 * w, crease)
	if look.freckles > 0.0:
		var dot := _skin.darkened(0.16).lerp(Color(0.55, 0.32, 0.2), 0.3)
		var count := int(34 * look.freckles)
		for i in count:
			var x := t.rng.randf_range(-0.058, 0.058)
			var y := t.rng.randf_range(0.072, 0.112)
			var near_eye := absf(absf(x) - 0.036 * look.eye_spacing) < 0.016 and y > 0.1
			if near_eye or (absf(x) < 0.012 and y < 0.08):
				continue
			var p := _skin_xy(x, y, 0.0004)
			t.ellipsoid_at(_hp(p), Vector3(0.0015, 0.0015, 0.0005) * HEAD_SCALE, dot, _bind(B.HEAD), 5, 2)
	t.deform = false


func _skin_crease(points: Array, radius: float, color: Color) -> void:
	var rings: Array = []
	for i in 5:
		var k := float(i) / 4.0
		var a: Vector2 = points[0]
		var b: Vector2 = points[1]
		var c: Vector2 = points[2]
		var q := a.lerp(b, k).lerp(b.lerp(c, k), k)
		var r := radius * sin(PI * (0.15 + 0.7 * k)) * HEAD_SCALE
		rings.append(SkinnedMeshTool.ring(_hp(_skin_xy(q.x, q.y, 0.0003)), r, r * 0.6, r * 0.6, _bind(B.HEAD), color))
	t.loft(rings, 4, Vector3.BACK)


# --- Hair ----------------------------------------------------------------------------

func _build_hair() -> void:
	t.material_id = SkinnedMeshTool.Surface.HAIR
	var head := _bind(B.HEAD)
	match look.hair_style:
		"balding":
			_hair_shell(0.3, 0.135, 0.03, 0.009, 0.17)
		"long":
			_hair_shell(0.196, 0.04, 0.0, 0.014)
			_hair_long_drape()
		"bun":
			_hair_shell(0.2, 0.15, 0.07, 0.008)
			var bun := _head_point(Vector3(0, 0.24, -0.085))
			t.ellipsoid_at(bun, Vector3(0.056, 0.05, 0.052), _hair, head, 10, 7, 0.06)
			t.ellipsoid_at(bun + Vector3(0, -0.035, 0.03), Vector3(0.04, 0.012, 0.03), look.accent_color.darkened(0.3), head, 8, 3)
		"ponytail":
			_hair_shell(0.198, 0.14, 0.06, 0.01)
			var root := _head_point(Vector3(0, 0.17, -0.112))
			t.ellipsoid_at(root, Vector3(0.03, 0.022, 0.026), look.accent_color.darkened(0.2), head, 8, 4)
			t.loft([
				SkinnedMeshTool.ring(root + Vector3(0, 0.0, -0.015), 0.03, 0.03, 0.03, head, _hair),
				SkinnedMeshTool.ring(root + Vector3(0, -0.08, -0.055), 0.04, 0.036, 0.04, head, _hair),
				SkinnedMeshTool.ring(root + Vector3(0, -0.18, -0.06), 0.033, 0.03, 0.033, _blend(B.HEAD, B.NECK, 0.6), _hair),
				SkinnedMeshTool.ring(root + Vector3(0, -0.28, -0.04), 0.018, 0.016, 0.018, _blend(B.NECK, B.CHEST, 0.6), _hair),
				SkinnedMeshTool.ring(root + Vector3(0, -0.32, -0.03), 0.004, 0.004, 0.004, _bind(B.CHEST), _hair),
			], 8)
		"locs":
			_hair_shell(0.19, 0.13, 0.04, 0.012)
			_hair_locs()
		"curly":
			_hair_shell(0.19, 0.13, 0.03, 0.014)
			for i in 44:
				var y := 0.13 + float(i % 5) * 0.03 + t.rng.randf_range(-0.008, 0.008)
				var a := TAU * float(i) / 44.0 * 4.0 + t.rng.randf_range(-0.15, 0.15)
				var front := sin(a)
				if front > 0.35 and y < 0.21:
					continue
				var p := _head_surface(y, a, 0.013)
				var outward := (p - _head_point(Vector3(0, y, 0))).normalized()
				var basis := Basis.looking_at(-outward, Vector3.UP).scaled(Vector3(0.026, 0.022, 0.008))
				t.ellipsoid(Transform3D(basis, p - outward * 0.003), _hair.lightened(t.rng.randf_range(-0.03, 0.06)), head, 7, 4, 0.12)
		_:
			_hair_shell(0.196, 0.135, 0.02, 0.012)


## Hair grown over the sculpted scalp. Coverage is defined by a hairline
## height at the front, sides (above the ears) and nape; the layer thins to
## nothing at the hairline so it blends into the skin, and fine colour
## variation suggests strands. `crown` > 0 leaves the top bare (balding).
func _hair_shell(front_line: float, side_line: float, nape_line: float, thickness: float, crown: float = 0.0) -> void:
	var head := _bind(B.HEAD)
	var start := t.vertex_count()
	var rows: Array[float] = []
	var y := minf(nape_line, side_line) - 0.012
	while y < 0.26:
		rows.append(y)
		y += 0.011
	rows.append(0.262)
	var segments := SKIN_SEGMENTS
	var grid: Array = []
	var masks: Array = []
	var colors: Array = []
	for row_y in rows:
		var points: Array[Vector3] = []
		var row_mask: Array[float] = []
		var row_colors: Array[Color] = []
		for k in segments:
			var a := TAU * float(k) / segments
			var f := sin(a)
			var line := side_line
			if f > 0.0:
				line = lerpf(side_line, front_line, smoothstep(0.25, 0.85, f))
			else:
				line = lerpf(side_line, nape_line, smoothstep(0.0, 0.6, -f))
			# Vertices outside the hair are snapped onto the hairline, so the
			# edge is a smooth curve rather than a staircase of grid cells.
			var inside := 1.0 if row_y >= line else 0.0
			var sample_y := maxf(row_y, line)
			if crown > 0.0:
				inside *= 1.0 if row_y <= crown else 0.0
				sample_y = minf(sample_y, crown)
			var m := smoothstep(line, line + 0.016, sample_y)
			if crown > 0.0:
				m *= 1.0 - smoothstep(crown - 0.016, crown, sample_y)
			var local := _skin_local(sample_y, a)
			# Grow hair away from the middle of the skull so the crown stays round.
			var outward := (local - Vector3(0, 0.12, -0.01)).normalized()
			var volume := 0.6 + 0.4 * smoothstep(0.12, 0.2, sample_y) - 0.3 * smoothstep(0.225, 0.258, sample_y)
			points.append(_hp(local + outward * (0.0012 + thickness * m * volume)))
			row_mask.append(inside)
			var strand := 0.035 * sin(a * 23.0 + row_y * 40.0) + 0.02 * sin(a * 57.0)
			row_colors.append(_hair.lightened(maxf(strand, 0.0)).darkened(maxf(-strand, 0.0)))
		grid.append(points)
		masks.append(row_mask)
		colors.append(row_colors)
	for i in rows.size() - 1:
		var lower: Array[Vector3] = grid[i]
		var upper: Array[Vector3] = grid[i + 1]
		var ml: Array[float] = masks[i]
		var mu: Array[float] = masks[i + 1]
		var cl: Array[Color] = colors[i]
		var cu: Array[Color] = colors[i + 1]
		var y_mid := (rows[i] + rows[i + 1]) * 0.5
		var center := _hp(Vector3(0, y_mid, float(_face_section(y_mid)[3])))
		for k in segments:
			var k1 := (k + 1) % segments
			if ml[k] + ml[k1] + mu[k] + mu[k1] < 0.5:
				continue
			t.triangle_colors(lower[k], lower[k1], upper[k1], cl[k], cl[k1], cu[k1], center, head, head, head)
			t.triangle_colors(lower[k], upper[k1], upper[k], cl[k], cu[k1], cu[k], center, head, head, head)
	if crown <= 0.0:
		var top_row: Array[Vector3] = grid[rows.size() - 1]
		var top_colors: Array[Color] = colors[rows.size() - 1]
		var top := _hp(Vector3(0, 0.265, -0.014)) + Vector3(0, thickness * 0.55 * HEAD_SCALE, 0)
		for k in segments:
			var k1 := (k + 1) % segments
			t.triangle_colors(top, top_row[k], top_row[k1], _hair, top_colors[k], top_colors[k1], top - Vector3(0, 0.03, 0), head, head, head)
	t.smooth_from(start)


## Hair at the temples, between the hairline and the ears, so the hairline
## follows a natural curve instead of a straight helmet edge.
func _hair_temples(thickness: float) -> void:
	for side: float in [1.0, -1.0]:
		var from := PI - 0.62 if side > 0.0 else 0.2
		var to := PI - 0.2 if side > 0.0 else 0.62
		var rings: Array = []
		for y in [0.14, 0.165, 0.188, 0.21]:
			rings.append(_head_ring(y, thickness, _bind(B.HEAD), _hair))
		t.loft(rings, 6, Vector3.BACK, false, false, from, to)


## Hair covering the crown, from just above the brow line to the top.
func _hair_cap(thickness: float) -> void:
	_hair_temples(thickness)
	var rings: Array = []
	for y in [0.196, 0.212, 0.228, 0.244, 0.258]:
		rings.append(_head_ring(y, thickness, _bind(B.HEAD), _hair))
	var top := _head_point(Vector3(0, 0.258, -0.014)) + Vector3(0, thickness * 0.9, 0)
	rings.append(SkinnedMeshTool.ring(top, 0.003, 0.003, 0.003, _bind(B.HEAD), _hair))
	t.loft(rings, 14, Vector3.BACK, false, true)


## Hair on the back and sides of the head (open shell, behind the ears).
func _hair_back_shell(y_from: float, y_to: float, thickness: float, arc_from: float, arc_to: float) -> void:
	var rings: Array = []
	var steps := 5
	for i in steps + 1:
		var y := lerpf(y_from, y_to, float(i) / steps)
		rings.append(_head_ring(y, thickness + 0.004 * (1.0 - float(i) / steps), _bind(B.HEAD), _hair))
	t.loft(rings, 12, Vector3.BACK, false, false, arc_from, arc_to)


## Soft clumps over the crown and back so short hair has volume and texture.
func _hair_clumps(count: int, thickness: float) -> void:
	for i in count:
		var a := lerpf(PI * 0.5 + 0.9, PI * 0.5 + TAU - 0.9, float(i) / maxf(count - 1, 1))
		var y := 0.2 + 0.035 * float(i % 3) - 0.05 * absf(sin(a)) * float(sin(a) < 0.0)
		var p := _head_surface(y, a, thickness * 0.9)
		var outward := (p - _head_point(Vector3(0, y, 0))).normalized()
		var basis := Basis.looking_at(-outward, Vector3.UP).scaled(Vector3(0.034, 0.024, 0.01))
		t.ellipsoid(Transform3D(basis, p), _hair.lightened(0.04 * float(i % 3) - 0.02), _bind(B.HEAD), 7, 4, 0.1)


## Tufts along the hairline so the hair has a soft front edge.
func _hair_fringe(thickness: float, count: int) -> void:
	for i in count:
		var a := lerpf(PI * 0.5 - 0.75, PI * 0.5 + 0.75, float(i) / maxf(count - 1, 1))
		var p := _head_surface(0.2, a, thickness * 0.8)
		var outward := (p - _head_point(Vector3(0, 0.2, 0))).normalized()
		var basis := Basis.looking_at(-outward, Vector3.UP).scaled(Vector3(0.028, 0.011, 0.007))
		t.ellipsoid(Transform3D(basis, p - outward * 0.004), _hair.lightened(0.03 * (i % 2)), _bind(B.HEAD), 7, 4, 0.06)


## Long hair falling over the back and framing the face.
func _hair_long_drape() -> void:
	var rows := [
		[0.17, _bind(B.HEAD)],
		[0.11, _bind(B.HEAD)],
		[0.05, _bind(B.HEAD)],
		[-0.02, _blend(B.HEAD, B.NECK, 0.5)],
		[-0.1, _blend(B.NECK, B.CHEST, 0.5)],
		[-0.19, _bind(B.CHEST)],
		[-0.25, _bind(B.CHEST)],
	]
	var rings: Array = []
	for row in rows:
		var y: float = row[0]
		var s := _head_section(maxf(y, 0.09))
		var drop := maxf(0.0, 0.05 - y)
		var center := _head_origin() + Vector3(0, y * HEAD_SCALE, s[4] - drop * 0.35)
		var width: float = s[1] + 0.02 - drop * 0.06
		var back: float = s[3] + 0.02 + drop * 0.25
		rings.append(SkinnedMeshTool.ring(center, width, s[2] * 0.5, back, row[1], _hair))
	t.loft(rings, 12, Vector3.BACK, false, false, PI - 0.55, TAU + 0.55)


# --- Clothing ----------------------------------------------------------------------

func _build_clothing_details() -> void:
	t.material_id = SkinnedMeshTool.Surface.CLOTH
	var chest := _bind(B.CHEST)
	# Collar.
	var collar := _shirt.darkened(0.12)
	t.loft([
		SkinnedMeshTool.ring(Vector3(0, 1.448, -0.014), 0.074, 0.064, 0.07, chest, collar),
		SkinnedMeshTool.ring(Vector3(0, 1.478, -0.016), 0.064, 0.056, 0.062, chest, collar),
	], 12, Vector3.BACK, false, false)
	# Button placket down the front of the shirt.
	if not look.has_accessory("apron"):
		var top := 1.43
		var bottom := 1.06 if look.tunic_length < 0.3 else 0.98
		for i in 4:
			var y := lerpf(top - 0.04, bottom + 0.04, float(i) / 3.0)
			t.material_id = SkinnedMeshTool.Surface.DETAIL
			t.ellipsoid_at(Vector3(0, y, _torso_front(y) + 0.003), Vector3(0.007, 0.007, 0.004), _shirt.darkened(0.35), _bind(B.SPINE if y < 1.2 else B.CHEST), 6, 3)
			t.material_id = SkinnedMeshTool.Surface.CLOTH
	if look.tunic_length >= 0.3:
		_build_tunic_skirt()
	_build_belt(LEATHER)


func _build_belt(color: Color) -> void:
	t.material_id = SkinnedMeshTool.Surface.LEATHER
	var rings: Array = []
	for y in [1.065, 1.025]:
		var s := _torso_section(y)
		rings.append(SkinnedMeshTool.ring(Vector3(0, y, s[4]), s[1] + 0.007, s[2] + 0.007, s[3] + 0.007, _blend(B.HIPS, B.SPINE, 0.3), color))
	t.loft(rings, 12, Vector3.BACK, false, false)
	var buckle_z := _torso_front(1.045) + 0.008
	t.material_id = SkinnedMeshTool.Surface.METAL
	t.box(Transform3D(Basis.IDENTITY, Vector3(0, 1.045, buckle_z)), Vector3(0.04, 0.034, 0.008), Color(0.72, 0.62, 0.38), _bind(B.HIPS))


## Shirt tails / dress skirt. Lower vertices follow the thigh on their side,
## so a long skirt swings with the legs instead of letting knees poke through.
func _build_tunic_skirt() -> void:
	t.material_id = SkinnedMeshTool.Surface.CLOTH
	var hem_y := lerpf(0.9, 0.42, look.tunic_length)
	var top := _torso_section(1.0)
	var hw := rig.hip_half / 0.092
	var cloth := _skirt_color()
	var flare := lerpf(1.0, 1.35, look.tunic_length)
	# [y, half_width, front, back]
	var rows := [
		[1.0, top[1] + 0.006, top[2] + 0.006, top[3] + 0.006],
		[0.9, 0.168 * hw, 0.104, 0.118],
	]
	var steps := 4
	for i in range(1, steps + 1):
		var k := float(i) / steps
		var y := lerpf(0.9, hem_y, k)
		rows.append([y, lerpf(0.168 * hw, 0.19 * hw * flare, k), lerpf(0.104, 0.12 * flare, k), lerpf(0.118, 0.132 * flare, k)])
	var segments := 27
	var grid: Array = []
	var binds: Array = []
	for row in rows:
		var y: float = row[0]
		var follow := clampf((0.95 - y) / 0.5, 0.0, 1.0) * 0.6
		var points: Array[Vector3] = []
		var ring_binds: Array[Vector3] = []
		for k in segments:
			var a := TAU * float(k) / segments
			var f := sin(a)
			# Soft vertical folds that deepen toward the hem.
			var fold := 1.0 + 0.06 * clampf((0.95 - y) / 0.4, 0.0, 1.0) * sin(a * 9.0 + 0.6)
			var x := cos(a) * float(row[1]) * fold
			points.append(Vector3(x, y, f * (row[2] if f > 0.0 else row[3]) * fold))
			var side_weight := clampf(absf(cos(a)) * 1.6, 0.0, 1.0) * follow
			var leg := B.LEFT_UPPER_LEG if x > 0.0 else B.RIGHT_UPPER_LEG
			ring_binds.append(_blend(B.HIPS, leg, side_weight))
		grid.append(points)
		binds.append(ring_binds)
	var start_color := cloth
	for i in rows.size() - 1:
		var lower: Array[Vector3] = grid[i]
		var upper: Array[Vector3] = grid[i + 1]
		var lb: Array[Vector3] = binds[i]
		var ub: Array[Vector3] = binds[i + 1]
		var center := Vector3(0, (float(rows[i][0]) + float(rows[i + 1][0])) * 0.5, 0)
		var color := start_color if i < rows.size() - 2 else cloth.darkened(0.1)
		for k in segments:
			var k1 := (k + 1) % segments
			t.triangle(lower[k], lower[k1], upper[k1], color, center, lb[k], lb[k1], ub[k1])
			t.triangle(lower[k], upper[k1], upper[k], color, center, lb[k], ub[k1], ub[k])


func _skirt_color() -> Color:
	return look.skirt_color if look.skirt_color.a > 0.0 else _shirt


func _apron_color() -> Color:
	return look.apron_color if look.apron_color.a > 0.0 else look.accent_color


# --- Accessories ---------------------------------------------------------------------

func _part(accessory: String, head_part: bool) -> bool:
	return look.has_accessory(accessory) and HEAD_ACCESSORIES.has(accessory) == head_part


## Builds the accessories that belong to the head mesh (head_part) or body.
func _build_all_accessories(head_part: bool) -> void:
	var accent := look.accent_color
	var head := _bind(B.HEAD)
	var chest := _bind(B.CHEST)
	var hips := _bind(B.HIPS)
	if _part("glasses", head_part):
		t.material_id = SkinnedMeshTool.Surface.METAL
		# Thin round wire frames: each rim is a loop of short tubes.
		var frame := Color(0.3, 0.21, 0.12)
		var wire := 0.0016 * HEAD_SCALE
		var inner_ends: Array[Vector3] = []
		for side: float in [1.0, -1.0]:
			var e := _eye(side)
			var r: float = e["r"]
			var fwd: Vector3 = e["fwd"]
			var lens := _hp(Vector3(e["c"]) + fwd * (r + 0.012))
			var x_axis := Vector3.UP.cross(fwd).normalized()
			var size := r * 1.6 * HEAD_SCALE
			var points: Array[Vector3] = []
			for k in 14:
				var angle := TAU * float(k) / 14.0
				points.append(lens + x_axis * cos(angle) * size + Vector3.UP * sin(angle) * size * 0.85)
			for k in 14:
				t.tube(points[k], points[(k + 1) % 14], wire, wire, frame, head, head, 4)
			inner_ends.append(lens - x_axis * size * side)
			var ear := _hp(Vector3(side * (float(_face_section(0.11)[0]) + 0.003), 0.114, -0.02))
			t.tube(lens + x_axis * size * side, ear, wire, wire, frame, head, head, 4)
		t.tube(inner_ends[0], inner_ends[1] , wire, wire, frame, head, head, 4)
	if _part("straw_hat", head_part):
		t.material_id = SkinnedMeshTool.Surface.STRAW
		var straw := Color(0.88, 0.76, 0.46)
		var o := _head_point(Vector3(0, 0.2, -0.008))
		t.loft([
			SkinnedMeshTool.ring(o, 0.205, 0.205, 0.205, head, straw),
			SkinnedMeshTool.ring(o + Vector3(0, 0.012, 0), 0.2, 0.2, 0.2, head, straw),
		], 16)
		t.loft([
			SkinnedMeshTool.ring(o, 0.104, 0.1, 0.112, head, accent),
			SkinnedMeshTool.ring(o + Vector3(0, 0.035, 0), 0.102, 0.098, 0.11, head, straw.darkened(0.05)),
			SkinnedMeshTool.ring(o + Vector3(0, 0.1, 0), 0.088, 0.082, 0.09, head, straw.darkened(0.05)),
			SkinnedMeshTool.ring(o + Vector3(0, 0.11, 0), 0.06, 0.055, 0.062, head, straw),
		], 14)
	if _part("headband", head_part):
		t.material_id = SkinnedMeshTool.Surface.CLOTH
		t.loft([_head_ring(0.205, 0.016, head, accent), _head_ring(0.18, 0.018, head, accent)], 14, Vector3.BACK, false, false)
	if _part("flower", head_part):
		t.material_id = SkinnedMeshTool.Surface.DETAIL
		var flower := _head_surface(0.2, PI * 0.5 + 0.9, 0.03)
		for i in 5:
			var a := TAU * float(i) / 5.0
			t.ellipsoid_at(flower + Vector3(cos(a) * 0.016, sin(a) * 0.016, 0.004), Vector3(0.012, 0.012, 0.006), accent, head, 6, 3)
		t.ellipsoid_at(flower + Vector3(0, 0, 0.008), Vector3(0.008, 0.008, 0.006), Color(1.0, 0.88, 0.35), head, 6, 3)
	if _part("scarf", head_part):
		t.material_id = SkinnedMeshTool.Surface.CLOTH
		t.loft([
			SkinnedMeshTool.ring(Vector3(0, 1.425, -0.012), 0.092, 0.085, 0.085, chest, accent),
			SkinnedMeshTool.ring(Vector3(0, 1.47, -0.014), 0.08, 0.075, 0.078, chest, accent),
			SkinnedMeshTool.ring(Vector3(0, 1.505, -0.012), 0.068, 0.064, 0.066, _blend(B.CHEST, B.NECK, 0.5), accent.darkened(0.08)),
		], 12, Vector3.BACK, false, false)
		var knot := Vector3(0.035, 1.43, _torso_front(1.43) + 0.02)
		t.ellipsoid_at(knot, Vector3(0.028, 0.025, 0.02), accent.darkened(0.1), chest, 7, 4)
		t.box(Transform3D(Basis(Vector3.BACK, 0.12), knot + Vector3(0.012, -0.09, 0.004)), Vector3(0.042, 0.16, 0.012), accent, chest)
	if _part("apron", head_part):
		_build_apron()
	if _part("tool_belt", head_part):
		t.material_id = SkinnedMeshTool.Surface.LEATHER
		for side: float in [1.0, -1.0]:
			var pouch := Vector3(side * 0.13, 0.99, _torso_front(0.99) - 0.01)
			t.box(Transform3D(Basis(Vector3.UP, side * 0.5), pouch), Vector3(0.07, 0.085, 0.045), LEATHER.lightened(0.08), hips)
		var loop := Vector3(0.16, 0.92, -0.03)
		t.tube(loop + Vector3(0, 0.08, 0), loop - Vector3(0, 0.12, 0), 0.011, 0.011, Color(0.55, 0.4, 0.25), hips, hips, 5)
		t.material_id = SkinnedMeshTool.Surface.METAL
		t.box(Transform3D(Basis.IDENTITY, loop + Vector3(0, 0.09, 0)), Vector3(0.03, 0.03, 0.09), Color(0.45, 0.45, 0.48), hips)
	if _part("satchel", head_part):
		t.material_id = SkinnedMeshTool.Surface.LEATHER
		var strap := accent.darkened(0.35)
		var shoulder := Vector3(0.1, 1.468, -0.015)
		t.tube(shoulder, Vector3(0.0, 1.3, _torso_front(1.3) + 0.008), 0.013, 0.013, strap, chest, chest, 5)
		t.tube(Vector3(0.0, 1.3, _torso_front(1.3) + 0.008), Vector3(-0.14, 1.04, _torso_front(1.04) + 0.01), 0.013, 0.013, strap, chest, hips, 5)
		t.tube(shoulder, Vector3(0.0, 1.3, _torso_back(1.3) - 0.008), 0.013, 0.013, strap, chest, chest, 5)
		t.tube(Vector3(0.0, 1.3, _torso_back(1.3) - 0.008), Vector3(-0.15, 1.04, _torso_back(1.04) - 0.01), 0.013, 0.013, strap, chest, hips, 5)
		var bag := Vector3(-0.185 * rig.hip_half / 0.092, 0.95, 0.0)
		t.loft([
			SkinnedMeshTool.ring(bag + Vector3(0, 0.07, 0), 0.03, 0.085, 0.085, hips, accent.darkened(0.2)),
			SkinnedMeshTool.ring(bag, 0.036, 0.095, 0.095, hips, accent.darkened(0.2)),
			SkinnedMeshTool.ring(bag - Vector3(0, 0.065, 0), 0.032, 0.088, 0.088, hips, accent.darkened(0.28)),
		], 8)
		t.box(Transform3D(Basis.IDENTITY, bag + Vector3(-0.036, 0.04, 0)), Vector3(0.012, 0.06, 0.15), accent.darkened(0.1), hips)
	if _part("suspenders", head_part):
		_build_suspenders()
	if _part("wide_hat", head_part):
		_build_wide_hat()
	if _part("headwrap", head_part):
		_build_headwrap()
	if _part("earrings", head_part):
		t.material_id = SkinnedMeshTool.Surface.METAL
		for side: float in [1.0, -1.0]:
			var lobe := _head_surface(0.075, PI if side > 0 else 0.0, 0.004)
			t.loft([
				SkinnedMeshTool.ring(lobe + Vector3(side * 0.006, -0.012, 0), 0.0, 0.012, 0.012, head, Color(0.95, 0.75, 0.3)),
				SkinnedMeshTool.ring(lobe + Vector3(side * 0.006, -0.03, 0), 0.0, 0.012, 0.012, head, Color(0.95, 0.75, 0.3)),
			], 8, Vector3.BACK)
	if _part("cloak", head_part):
		_build_cloak()
	if _part("backpack", head_part):
		_build_backpack()


## Beard grown from the sculpted skin: a layer that follows the jaw and
## cheeks, thickest on the chin and thinning to nothing at its edges.
func _build_beard(long_beard: bool) -> void:
	t.material_id = SkinnedMeshTool.Surface.HAIR
	var head := _bind(B.HEAD)
	var beard := _hair
	var start := t.vertex_count()
	var rows := [-0.046, -0.036, -0.024, -0.012, 0.0, 0.012, 0.022, 0.031, 0.04, 0.05, 0.06, 0.07, 0.08, 0.09, 0.1]
	var segments := SKIN_SEGMENTS
	var grid: Array = []
	var masks: Array = []
	var tints: Array = []
	for y in rows:
		var points: Array[Vector3] = []
		var row_mask: Array[float] = []
		var row_tint: Array[Color] = []
		for k in segments:
			var a := TAU * float(k) / segments
			var local := _skin_local(y, a)
			var m := _beard_mask(local, sin(a), cos(a))
			row_tint.append(_skin_tint(local, sin(a)).lerp(beard, smoothstep(0.0, 0.45, m)))
			var outward := (local - Vector3(0, y, float(_face_section(y)[3]))).normalized()
			var taper := lerpf(0.45, 1.0, smoothstep(-0.046, -0.024, float(y)))
			points.append(_face_deform(_hp(local + outward * (0.0006 + 0.0075 * m * taper))))
			row_mask.append(m)
		grid.append(points)
		masks.append(row_mask)
		tints.append(row_tint)
	for i in rows.size() - 1:
		var lower: Array[Vector3] = grid[i]
		var upper: Array[Vector3] = grid[i + 1]
		var ml: Array[float] = masks[i]
		var mu: Array[float] = masks[i + 1]
		var cl: Array[Color] = tints[i]
		var cu: Array[Color] = tints[i + 1]
		var y_mid: float = (rows[i] + rows[i + 1]) * 0.5
		var center := _hp(Vector3(0, y_mid, float(_face_section(y_mid)[3])))
		for k in segments:
			var k1 := (k + 1) % segments
			if ml[k] + ml[k1] + mu[k] + mu[k1] < 0.02:
				continue
			t.triangle_colors(lower[k], lower[k1], upper[k1], cl[k], cl[k1], cu[k1], center, head, head, head)
			t.triangle_colors(lower[k], upper[k1], upper[k], cl[k], cu[k1], cu[k], center, head, head, head)
	t.smooth_from(start)
	# Moustache over the upper lip.
	var rings: Array = []
	var half := 0.027 * look.mouth_width
	for i in 7:
		var k := float(i) / 6.0
		var x := lerpf(-half - 0.006, half + 0.006, k)
		var droop := 0.006 * pow(2.0 * k - 1.0, 2.0)
		var y := MOUTH_Y + 0.011 - droop
		var p := _skin_xy(x, y, 0.004)
		var thick := 0.0035 + 0.0025 * (1.0 - pow(2.0 * k - 1.0, 2.0))
		rings.append(SkinnedMeshTool.ring(_face_deform(_hp(p)), thick * HEAD_SCALE, 0.004 * HEAD_SCALE, 0.002 * HEAD_SCALE, head, beard.darkened(0.05)))
	t.loft(rings, 6, Vector3.BACK)
	if long_beard:
		var chin := _face_deform(_hp(_skin_xy(0.0, -0.035, 0.008)))
		t.loft([
			SkinnedMeshTool.ring(chin + Vector3(0, 0.02, -0.02), 0.06, 0.03, 0.03, head, beard),
			SkinnedMeshTool.ring(chin + Vector3(0, -0.06, 0.0), 0.05, 0.032, 0.03, _blend(B.HEAD, B.NECK, 0.5), beard),
			SkinnedMeshTool.ring(chin + Vector3(0, -0.14, 0.012), 0.032, 0.024, 0.022, _blend(B.NECK, B.CHEST, 0.5), beard),
			SkinnedMeshTool.ring(chin + Vector3(0, -0.19, 0.016), 0.006, 0.006, 0.006, _bind(B.CHEST), beard),
		], 9, Vector3.BACK, true, true)


## 0..1 beard coverage at a skin point (profile units).
func _beard_mask(p: Vector3, facing: float, side: float) -> float:
	if facing < -0.35:
		return 0.0
	var mouth := _gauss(p.x / (0.032 * look.mouth_width), (p.y - MOUTH_Y) / 0.012, 1.0)
	var jaw := 1.0 - smoothstep(0.02, 0.05, p.y)
	var cheek := smoothstep(0.35, 0.75, absf(side)) * (1.0 - smoothstep(0.075, 0.098, p.y))
	var chin_sides := (1.0 - smoothstep(0.045, 0.07, p.y)) * smoothstep(0.012, 0.03, absf(p.x))
	var m := maxf(jaw, maxf(cheek, chin_sides))
	m *= 1.0 - smoothstep(0.35, 0.8, mouth)
	m *= smoothstep(-0.35, 0.0, facing)
	return clampf(m, 0.0, 1.0)


func _build_apron() -> void:
	t.material_id = SkinnedMeshTool.Surface.CLOTH
	var cloth := _apron_color()
	var rows := [
		[1.36, 0.1, _bind(B.CHEST)],
		[1.2, 0.11, _blend(B.SPINE, B.CHEST, 0.5)],
		[1.06, 0.13, _bind(B.SPINE)],
		[0.92, 0.155, _bind(B.HIPS)],
		[0.62, 0.165, _bind(B.HIPS)],
	]
	var rings: Array = []
	for row in rows:
		var y: float = row[0]
		var z := _torso_front(maxf(y, 0.95)) + 0.013
		if y < 0.95:
			z = lerpf(_torso_front(0.95) + 0.013, 0.118, (0.95 - y) / 0.33)
		rings.append(SkinnedMeshTool.ring(Vector3(0, y, z), row[1], 0.005, 0.005, row[2], cloth))
	t.loft(rings, 8)
	# Pocket and neck strap.
	t.box(Transform3D(Basis.IDENTITY, Vector3(0, 0.84, 0.125)), Vector3(0.16, 0.08, 0.008), cloth.darkened(0.15), _bind(B.HIPS))
	for side: float in [1.0, -1.0]:
		t.tube(Vector3(side * 0.085, 1.36, _torso_front(1.36) + 0.012), Vector3(side * 0.05, 1.47, -0.03), 0.008, 0.008, cloth.darkened(0.2), _bind(B.CHEST), _bind(B.CHEST), 4)


func _build_cloak() -> void:
	t.material_id = SkinnedMeshTool.Surface.CLOTH
	var cloth := look.accent_color
	# [y, half_width, z, bone]: a sheet hanging down the back. Below the hips
	# each side follows the thigh behind it, so the cloak swings with the
	# stride instead of hiding the legs like a board.
	var rows := [
		[1.46, 0.13, -0.06, B.CHEST, 0.0],
		[1.3, 0.19, _torso_back(1.3) - 0.02, B.CHEST, 0.0],
		[1.1, 0.205, _torso_back(1.1) - 0.03, B.SPINE, 0.0],
		[0.9, 0.22, -0.15, B.HIPS, 0.15],
		[0.72, 0.232, -0.165, B.HIPS, 0.45],
		[0.58, 0.238, -0.175, B.HIPS, 0.62],
		[0.48, 0.24, -0.18, B.HIPS, 0.7],
	]
	var segments := 10
	var grid: Array = []
	var binds: Array = []
	for row in rows:
		var points: Array[Vector3] = []
		var row_binds: Array[Vector3] = []
		for k in segments + 1:
			var a := lerpf(PI + 0.25, TAU - 0.25, float(k) / segments)
			var x := cos(a) * float(row[1])
			points.append(Vector3(x, row[0], float(row[2]) + sin(a) * 0.02))
			var bone: int = row[3]
			var follow: float = row[4] * clampf(absf(x) / 0.12, 0.0, 1.0)
			if follow > 0.0:
				var leg := B.LEFT_UPPER_LEG if x > 0.0 else B.RIGHT_UPPER_LEG
				row_binds.append(_blend(bone, leg, follow))
			elif bone == B.SPINE:
				row_binds.append(_blend(B.SPINE, B.CHEST, 0.4))
			else:
				row_binds.append(_bind(bone))
		grid.append(points)
		binds.append(row_binds)
	for i in rows.size() - 1:
		var lower: Array[Vector3] = grid[i]
		var upper: Array[Vector3] = grid[i + 1]
		var lb: Array[Vector3] = binds[i]
		var ub: Array[Vector3] = binds[i + 1]
		var center := Vector3(0, (float(rows[i][0]) + float(rows[i + 1][0])) * 0.5, 0.2)
		for k in segments:
			# Both faces, so the inside of the cloak is visible when it swings.
			for side: float in [1.0, -1.0]:
				var c := center if side > 0.0 else Vector3(center.x, center.y, -1.0)
				t.triangle(lower[k], lower[k + 1], upper[k + 1], cloth.darkened(0.0 if side > 0.0 else 0.2), c, lb[k], lb[k + 1], ub[k + 1])
				t.triangle(lower[k], upper[k + 1], upper[k], cloth.darkened(0.0 if side > 0.0 else 0.2), c, lb[k], ub[k + 1], ub[k])
	# Gathered hood around the neck.
	t.loft([
		SkinnedMeshTool.ring(Vector3(0, 1.44, -0.03), 0.12, 0.085, 0.11, _bind(B.CHEST), cloth.darkened(0.1)),
		SkinnedMeshTool.ring(Vector3(0, 1.5, -0.04), 0.095, 0.07, 0.1, _bind(B.CHEST), cloth.darkened(0.1)),
	], 12, Vector3.BACK, false, false, PI - 0.6, TAU + 0.6)
	# Clasp.
	t.ellipsoid_at(Vector3(0, 1.445, _torso_front(1.445) + 0.012), Vector3(0.016, 0.016, 0.008), Color(0.8, 0.7, 0.4), _bind(B.CHEST), 7, 4)


func _build_backpack() -> void:
	t.material_id = SkinnedMeshTool.Surface.CLOTH
	var pack := look.accent_color.lightened(0.15).lerp(Color(0.55, 0.42, 0.28), 0.6)
	var z := _torso_back(1.25) - 0.075
	var chest := _bind(B.CHEST)
	t.loft([
		SkinnedMeshTool.ring(Vector3(0, 1.06, z), 0.12, 0.055, 0.06, _blend(B.SPINE, B.CHEST, 0.5), pack),
		SkinnedMeshTool.ring(Vector3(0, 1.2, z - 0.005), 0.13, 0.06, 0.068, chest, pack),
		SkinnedMeshTool.ring(Vector3(0, 1.36, z), 0.12, 0.055, 0.06, chest, pack),
		SkinnedMeshTool.ring(Vector3(0, 1.39, z), 0.1, 0.045, 0.05, chest, pack),
	], 10)
	t.box(Transform3D(Basis(Vector3.RIGHT, 0.2), Vector3(0, 1.33, z - 0.05)), Vector3(0.22, 0.12, 0.02), pack.darkened(0.15), chest)
	t.box(Transform3D(Basis.IDENTITY, Vector3(0, 1.15, z - 0.07)), Vector3(0.14, 0.09, 0.03), pack.darkened(0.08), chest)
	for side: float in [1.0, -1.0]:
		var back_top := Vector3(side * 0.09, 1.39, z + 0.05)
		var over := Vector3(side * 0.1, 1.47, -0.012)
		var front := Vector3(side * 0.1, 1.37, _torso_front(1.37) + 0.008)
		var low := Vector3(side * 0.12, 1.15, _torso_front(1.15) + 0.008)
		t.tube(back_top, over, 0.012, 0.012, pack.darkened(0.3), chest, chest, 5)
		t.tube(over, front, 0.012, 0.012, pack.darkened(0.3), chest, chest, 5)
		t.tube(front, low, 0.012, 0.012, pack.darkened(0.3), chest, _blend(B.SPINE, B.CHEST, 0.5), 5)


## Long locs falling from the crown over the back and shoulders.
func _hair_locs() -> void:
	t.material_id = SkinnedMeshTool.Surface.HAIR
	var count := 22
	for i in count:
		# Spread around the back half of the head, a few framing the face.
		var a := lerpf(PI - 0.35, TAU + 0.35, float(i) / (count - 1))
		var y0 := 0.13 + 0.03 * float(i % 2)
		var root := _head_surface(y0, a, 0.012)
		var outward := Vector3(root.x, 0, root.z - _head_origin().z).normalized()
		var length := 0.32 + 0.06 * float(i % 3) - (0.12 if absf(sin(a)) < 0.4 else 0.0)
		var mid := root + outward * 0.04 + Vector3(0, -length * 0.45, 0)
		var tip := root + outward * 0.06 + Vector3(0, -length, -0.02)
		var color := _hair.lightened(0.04 * float(i % 3))
		t.loft([
			SkinnedMeshTool.ring(root, 0.013, 0.013, 0.013, _bind(B.HEAD), color),
			SkinnedMeshTool.ring(mid, 0.012, 0.012, 0.012, _blend(B.HEAD, B.NECK, 0.6), color),
			SkinnedMeshTool.ring(tip, 0.009, 0.009, 0.009, _blend(B.NECK, B.CHEST, 0.7), color),
		], 5)


func _build_suspenders() -> void:
	t.material_id = SkinnedMeshTool.Surface.LEATHER
	var strap := LEATHER.lightened(0.05)
	var chest := _bind(B.CHEST)
	for side: float in [1.0, -1.0]:
		var front_low := Vector3(side * 0.085, 1.07, _torso_front(1.07) + 0.006)
		var front_high := Vector3(side * 0.095, 1.36, _torso_front(1.36) + 0.006)
		var over := Vector3(side * 0.095, 1.468, -0.015)
		var back_high := Vector3(side * 0.07, 1.36, _torso_back(1.36) - 0.006)
		var back_low := Vector3(side * 0.03, 1.08, _torso_back(1.08) - 0.006)
		t.tube(front_low, front_high, 0.011, 0.011, strap, _blend(B.SPINE, B.CHEST, 0.3), chest, 4)
		t.tube(front_high, over, 0.011, 0.011, strap, chest, chest, 4)
		t.tube(over, back_high, 0.011, 0.011, strap, chest, chest, 4)
		t.tube(back_high, back_low, 0.011, 0.011, strap, chest, _bind(B.SPINE), 4)
		t.box(Transform3D(Basis.IDENTITY, front_low + Vector3(0, 0.005, 0.004)), Vector3(0.026, 0.022, 0.006), Color(0.72, 0.62, 0.38), _bind(B.SPINE))


func _build_wide_hat() -> void:
	t.material_id = SkinnedMeshTool.Surface.CLOTH
	var head := _bind(B.HEAD)
	var felt := look.hat_color if look.hat_color.a > 0.0 else LEATHER.lightened(0.15)
	var o := _head_point(Vector3(0, 0.19, -0.01))
	# Brim curls up slightly at the edge.
	t.loft([
		SkinnedMeshTool.ring(o + Vector3(0, 0.016, 0), 0.1, 0.1, 0.11, head, felt),
		SkinnedMeshTool.ring(o + Vector3(0, 0.0, 0), 0.2, 0.2, 0.2, head, felt),
		SkinnedMeshTool.ring(o + Vector3(0, 0.022, 0), 0.25, 0.25, 0.25, head, felt.darkened(0.08)),
		SkinnedMeshTool.ring(o + Vector3(0, 0.03, 0), 0.248, 0.248, 0.248, head, felt.darkened(0.08)),
		SkinnedMeshTool.ring(o + Vector3(0, 0.016, 0), 0.1, 0.1, 0.11, head, felt),
	], 18, Vector3.BACK, false, false)
	t.loft([
		SkinnedMeshTool.ring(o, 0.112, 0.106, 0.118, head, felt.darkened(0.35)),
		SkinnedMeshTool.ring(o + Vector3(0, 0.03, 0), 0.11, 0.104, 0.116, head, felt.darkened(0.35)),
		SkinnedMeshTool.ring(o + Vector3(0, 0.05, 0), 0.106, 0.1, 0.112, head, felt),
		SkinnedMeshTool.ring(o + Vector3(0, 0.12, -0.005), 0.094, 0.086, 0.1, head, felt),
		SkinnedMeshTool.ring(o + Vector3(0, 0.138, -0.005), 0.06, 0.04, 0.07, head, felt),
	], 14)


## A wrapped headscarf with a knot on top (Nia).
func _build_headwrap() -> void:
	t.material_id = SkinnedMeshTool.Surface.CLOTH
	var head := _bind(B.HEAD)
	var cloth := look.accent_color
	var rings: Array = []
	for y in [0.15, 0.185, 0.22, 0.245]:
		rings.append(_head_ring(y, 0.03, head, cloth))
	t.loft(rings, 14, Vector3.BACK, false, false)
	var stripe_rings: Array = [_head_ring(0.18, 0.033, head, cloth.darkened(0.25)), _head_ring(0.172, 0.033, head, cloth.darkened(0.25))]
	t.loft(stripe_rings, 14, Vector3.BACK, false, false)
	var knot := _head_point(Vector3(0.02, 0.27, 0.03))
	t.ellipsoid_at(knot, Vector3(0.045, 0.035, 0.04), cloth.lightened(0.05), head, 8, 5, 0.1)
	t.ellipsoid_at(knot + Vector3(-0.045, 0.01, -0.005), Vector3(0.035, 0.022, 0.03), cloth, head, 7, 4, 0.1)
