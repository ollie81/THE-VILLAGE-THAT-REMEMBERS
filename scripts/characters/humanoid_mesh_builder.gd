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
const HEAD_SCALE := 1.12

## Head cross-sections relative to the Head joint: [y, half_width, front, back, z_offset].
const HEAD_PROFILE := [
	[-0.035, 0.03, 0.028, 0.02, 0.058],
	[0.0, 0.072, 0.07, 0.052, 0.032],
	[0.035, 0.085, 0.084, 0.074, 0.016],
	[0.075, 0.093, 0.094, 0.092, 0.006],
	[0.12, 0.095, 0.095, 0.104, 0.0],
	[0.16, 0.094, 0.09, 0.108, -0.005],
	[0.2, 0.086, 0.078, 0.1, -0.008],
	[0.235, 0.062, 0.052, 0.076, -0.012],
	[0.258, 0.022, 0.016, 0.026, -0.014],
]

var look: CharacterAppearance
var rig: HumanoidRig
var t: SkinnedMeshTool

var _skin: Color
var _shirt: Color
var _pants: Color
var _hair: Color
var _torso_rows: Array = []


func _init(appearance: CharacterAppearance, humanoid_rig: HumanoidRig) -> void:
	look = appearance
	rig = humanoid_rig
	t = SkinnedMeshTool.new(hash(appearance.skin_color) ^ hash(appearance.hair_style))
	_skin = look.skin_color
	_shirt = look.shirt_color
	_pants = look.pants_color
	_hair = look.hair_color


func build() -> ArrayMesh:
	_build_torso()
	_build_neck()
	for side in [1.0, -1.0]:
		_build_arm(side)
		_build_hand(side)
		_build_leg(side)
		_build_shoe(side)
	_build_head()
	_build_face()
	_build_hair()
	_build_clothing_details()
	_build_accessories()
	return t.build(Materials.vertex_color())


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
	return [y * HEAD_SCALE, row[1] * HEAD_SCALE, row[2] * HEAD_SCALE, row[3] * HEAD_SCALE, row[4] * HEAD_SCALE]


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
	for side in [1.0, -1.0]:
		var upper := HumanoidRig.sided(B.LEFT_UPPER_ARM, side)
		var shoulder := rig.joint(upper)
		t.loft([
			SkinnedMeshTool.ring(Vector3(side * 0.07, 1.445, -0.014), 0.045, 0.05, 0.055, _bind(B.CHEST), _sleeve_color(1.43)),
			SkinnedMeshTool.ring(Vector3(side * (shoulder.x * 0.6 + 0.03), 1.44, -0.015), 0.05, 0.055, 0.058, _blend(B.CHEST, upper, 0.3), _sleeve_color(1.43)),
			SkinnedMeshTool.ring(Vector3(side * shoulder.x, 1.42, -0.015), 0.052, 0.054, 0.054, _blend(B.CHEST, upper, 0.75), _sleeve_color(1.43)),
			SkinnedMeshTool.ring(Vector3(side * (shoulder.x + 0.008), 1.38, -0.015), 0.05, 0.05, 0.052, _bind(upper), _sleeve_color(1.43)),
		], 9, Vector3.BACK, true, false)


func _build_neck() -> void:
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


# --- Head and face --------------------------------------------------------------------

func _build_head() -> void:
	var rings: Array = []
	for row in HEAD_PROFILE:
		var s := _head_section(row[0])
		rings.append(SkinnedMeshTool.ring(_head_origin() + Vector3(0, s[0], s[4]), s[1], s[2], s[3], _bind(B.HEAD), _skin))
	t.loft(rings, 14)
	# Ears.
	for side in [1.0, -1.0]:
		var ear := _head_surface(0.105, PI if side > 0 else 0.0, -0.004)
		var ear_basis := Basis(Vector3.UP, side * 0.25).scaled(Vector3(0.014, 0.03, 0.021))
		t.ellipsoid(Transform3D(ear_basis, ear), _skin.darkened(0.04), _bind(B.HEAD), 7, 4)


func _build_face() -> void:
	var head := _bind(B.HEAD)
	var white := Color(0.95, 0.94, 0.9)
	var lip := _skin.darkened(0.22).lerp(Color(0.72, 0.32, 0.3), 0.3)
	var brow := _hair.darkened(0.15) if look.hair_style != "balding" else _hair.darkened(0.35)
	for side in [1.0, -1.0]:
		var a: float = PI * 0.5 + side * 0.42
		var eye := _head_surface(0.115, a, -0.006)
		var outward := (eye - _head_point(Vector3(0, 0.115, 0))).normalized()
		var eye_basis := Basis.looking_at(-outward, Vector3.UP)
		t.ellipsoid(Transform3D(eye_basis.scaled(Vector3(0.019, 0.013, 0.008)), eye), white, head, 8, 4)
		t.ellipsoid(Transform3D(eye_basis.scaled(Vector3(0.009, 0.0105, 0.006)), eye + outward * 0.006), look.eye_color, head, 7, 4)
		t.ellipsoid(Transform3D(eye_basis.scaled(Vector3(0.004, 0.0045, 0.003)), eye + outward * 0.0105 + Vector3(0, 0.002, 0)), Color(0.05, 0.04, 0.04), head, 6, 3)
		# Upper eyelid and brow.
		var lid := _head_surface(0.127, a, 0.001)
		t.ellipsoid(Transform3D(eye_basis.scaled(Vector3(0.022, 0.006, 0.008)), lid), _skin.darkened(0.12), head, 7, 3)
		var brow_pos := _head_surface(0.148, a + side * 0.04, 0.002)
		var brow_basis := eye_basis * Basis(Vector3.BACK, -side * 0.12)
		t.ellipsoid(Transform3D(brow_basis.scaled(Vector3(0.026, 0.0065, 0.008)), brow_pos), brow, head, 7, 3)
		# A touch of warmth on the cheeks.
		var cheek := _head_surface(0.07, PI * 0.5 + side * 0.62, -0.003)
		t.ellipsoid(Transform3D(eye_basis.scaled(Vector3(0.02, 0.012, 0.004)), cheek), _skin.lerp(Color(0.9, 0.45, 0.42), 0.12), head, 7, 3)
	# Nose.
	var nose_root := _head_surface(0.11, PI * 0.5, -0.004)
	var nose_tip := _head_surface(0.082, PI * 0.5, 0.014)
	t.loft([
		SkinnedMeshTool.ring(nose_root, 0.008, 0.005, 0.005, head, _skin),
		SkinnedMeshTool.ring(nose_root.lerp(nose_tip, 0.6), 0.012, 0.01, 0.008, head, _skin),
		SkinnedMeshTool.ring(nose_tip, 0.016, 0.011, 0.01, head, _skin),
		SkinnedMeshTool.ring(nose_tip + Vector3(0, -0.009, -0.01), 0.012, 0.007, 0.007, head, _skin.darkened(0.04)),
	], 7, Vector3.BACK)
	# Lips.
	var mouth := _head_surface(0.043, PI * 0.5, 0.0)
	t.ellipsoid(Transform3D(Basis.from_scale(Vector3(0.026, 0.0065, 0.008)), mouth + Vector3(0, 0.004, 0)), lip, head, 8, 3)
	t.ellipsoid(Transform3D(Basis.from_scale(Vector3(0.022, 0.0075, 0.008)), mouth - Vector3(0, 0.006, 0.001)), lip.lightened(0.06), head, 8, 3)


# --- Hair ----------------------------------------------------------------------------

func _build_hair() -> void:
	var head := _bind(B.HEAD)
	match look.hair_style:
		"balding":
			_hair_back_shell(0.035, 0.16, 0.009, PI - 0.25, TAU + 0.25)
		"long":
			_hair_cap(0.016)
			_hair_long_drape()
			_hair_fringe(0.016, 5)
		"bun":
			_hair_cap(0.012)
			_hair_back_shell(0.075, 0.17, 0.012, PI + 0.35, TAU - 0.35)
			var bun := _head_point(Vector3(0, 0.24, -0.085))
			t.ellipsoid_at(bun, Vector3(0.056, 0.05, 0.052), _hair, head, 9, 6, 0.08)
			t.ellipsoid_at(bun + Vector3(0, -0.035, 0.03), Vector3(0.04, 0.012, 0.03), look.accent_color.darkened(0.3), head, 8, 3)
		"ponytail":
			_hair_cap(0.012)
			_hair_back_shell(0.04, 0.17, 0.012, PI + 0.1, TAU - 0.1)
			_hair_fringe(0.012, 4)
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
			_hair_cap(0.014)
			_hair_back_shell(0.04, 0.17, 0.014, PI + 0.1, TAU - 0.1)
			_hair_locs()
		"curly":
			_hair_cap(0.018)
			_hair_back_shell(0.03, 0.17, 0.018, PI - 0.1, TAU + 0.1)
			for i in 22:
				var y := 0.1 + float(i % 4) * 0.045 + t.rng.randf_range(-0.01, 0.01)
				var a := TAU * float(i) / 22.0 * 3.0 + t.rng.randf_range(-0.2, 0.2)
				var front := sin(a)
				if front > 0.55 and y < 0.17:
					continue
				var p := _head_surface(y, a, 0.02)
				t.ellipsoid_at(p, Vector3(0.042, 0.038, 0.042), _hair.lightened(t.rng.randf_range(0.0, 0.06)), head, 7, 4, 0.12)
		_:
			_hair_cap(0.012)
			_hair_back_shell(0.03, 0.17, 0.012, PI + 0.2, TAU - 0.2)
			_hair_fringe(0.012, 5)
			for side in [1.0, -1.0]:
				var burn := _head_surface(0.1, PI if side > 0 else 0.0, 0.004) + Vector3(0, 0, 0.022)
				t.ellipsoid_at(burn, Vector3(0.008, 0.026, 0.014), _hair, head, 6, 4)


## Hair covering the crown, from just above the brow line to the top.
func _hair_cap(thickness: float) -> void:
	var rings: Array = []
	for y in [0.152, 0.175, 0.2, 0.222, 0.242, 0.258]:
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


## Tufts along the hairline so the hair has a soft front edge.
func _hair_fringe(thickness: float, count: int) -> void:
	for i in count:
		var a := lerpf(PI * 0.5 - 0.75, PI * 0.5 + 0.75, float(i) / maxf(count - 1, 1))
		var p := _head_surface(0.162, a, thickness * 0.8)
		var outward := (p - _head_point(Vector3(0, 0.162, 0))).normalized()
		var basis := Basis.looking_at(-outward, Vector3.UP).scaled(Vector3(0.03, 0.017, 0.012))
		t.ellipsoid(Transform3D(basis, p), _hair.lightened(0.03 * (i % 2)), _bind(B.HEAD), 7, 4, 0.08)


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
			t.ellipsoid_at(Vector3(0, y, _torso_front(y) + 0.003), Vector3(0.007, 0.007, 0.004), _shirt.darkened(0.35), _bind(B.SPINE if y < 1.2 else B.CHEST), 6, 3)
	if look.tunic_length >= 0.3:
		_build_tunic_skirt()
	_build_belt(LEATHER)


func _build_belt(color: Color) -> void:
	var rings: Array = []
	for y in [1.065, 1.025]:
		var s := _torso_section(y)
		rings.append(SkinnedMeshTool.ring(Vector3(0, y, s[4]), s[1] + 0.007, s[2] + 0.007, s[3] + 0.007, _blend(B.HIPS, B.SPINE, 0.3), color))
	t.loft(rings, 12, Vector3.BACK, false, false)
	var buckle_z := _torso_front(1.045) + 0.008
	t.box(Transform3D(Basis.IDENTITY, Vector3(0, 1.045, buckle_z)), Vector3(0.04, 0.034, 0.008), Color(0.72, 0.62, 0.38), _bind(B.HIPS))


## Shirt tails / dress skirt. Lower vertices follow the thigh on their side,
## so a long skirt swings with the legs instead of letting knees poke through.
func _build_tunic_skirt() -> void:
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
	var segments := 16
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
			var x := cos(a) * float(row[1])
			points.append(Vector3(x, y, f * (row[2] if f > 0.0 else row[3])))
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

func _build_accessories() -> void:
	var accent := look.accent_color
	var head := _bind(B.HEAD)
	var chest := _bind(B.CHEST)
	var hips := _bind(B.HIPS)
	if look.has_accessory("beard") or look.has_accessory("long_beard"):
		_build_beard(look.has_accessory("long_beard"))
	if look.has_accessory("glasses"):
		var frame := Color(0.3, 0.22, 0.14)
		for side in [1.0, -1.0]:
			var c := _head_surface(0.115, PI * 0.5 + side * 0.42, 0.012)
			var lens_basis := Basis.looking_at(-(c - _head_point(Vector3(0, 0.115, 0))).normalized(), Vector3.UP)
			t.loft([
				SkinnedMeshTool.ring(c, 0.026, 0.02, 0.02, head, frame),
				SkinnedMeshTool.ring(c + lens_basis.z * -0.004, 0.026, 0.02, 0.02, head, frame),
			], 8, lens_basis.y, false, false)
			var temple_end := _head_surface(0.115, PI if side > 0 else 0.0, 0.006) + Vector3(0, 0, -0.01)
			t.tube(c + Vector3(side * 0.024, 0, -0.006), temple_end, 0.003, 0.003, frame, head, head, 4)
		t.tube(_head_surface(0.118, PI * 0.5 + 0.14, 0.012), _head_surface(0.118, PI * 0.5 - 0.14, 0.012), 0.003, 0.003, frame, head, head, 4)
	if look.has_accessory("straw_hat"):
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
	if look.has_accessory("headband"):
		t.loft([_head_ring(0.205, 0.016, head, accent), _head_ring(0.18, 0.018, head, accent)], 14, Vector3.BACK, false, false)
	if look.has_accessory("flower"):
		var flower := _head_surface(0.2, PI * 0.5 + 0.9, 0.03)
		for i in 5:
			var a := TAU * float(i) / 5.0
			t.ellipsoid_at(flower + Vector3(cos(a) * 0.016, sin(a) * 0.016, 0.004), Vector3(0.012, 0.012, 0.006), accent, head, 6, 3)
		t.ellipsoid_at(flower + Vector3(0, 0, 0.008), Vector3(0.008, 0.008, 0.006), Color(1.0, 0.88, 0.35), head, 6, 3)
	if look.has_accessory("scarf"):
		t.loft([
			SkinnedMeshTool.ring(Vector3(0, 1.425, -0.012), 0.092, 0.085, 0.085, chest, accent),
			SkinnedMeshTool.ring(Vector3(0, 1.47, -0.014), 0.08, 0.075, 0.078, chest, accent),
			SkinnedMeshTool.ring(Vector3(0, 1.505, -0.012), 0.068, 0.064, 0.066, _blend(B.CHEST, B.NECK, 0.5), accent.darkened(0.08)),
		], 12, Vector3.BACK, false, false)
		var knot := Vector3(0.035, 1.43, _torso_front(1.43) + 0.02)
		t.ellipsoid_at(knot, Vector3(0.028, 0.025, 0.02), accent.darkened(0.1), chest, 7, 4)
		t.box(Transform3D(Basis(Vector3.BACK, 0.12), knot + Vector3(0.012, -0.09, 0.004)), Vector3(0.042, 0.16, 0.012), accent, chest)
	if look.has_accessory("apron"):
		_build_apron()
	if look.has_accessory("tool_belt"):
		for side in [1.0, -1.0]:
			var pouch := Vector3(side * 0.13, 0.99, _torso_front(0.99) - 0.01)
			t.box(Transform3D(Basis(Vector3.UP, side * 0.5), pouch), Vector3(0.07, 0.085, 0.045), LEATHER.lightened(0.08), hips)
		var loop := Vector3(0.16, 0.92, -0.03)
		t.tube(loop + Vector3(0, 0.08, 0), loop - Vector3(0, 0.12, 0), 0.011, 0.011, Color(0.55, 0.4, 0.25), hips, hips, 5)
		t.box(Transform3D(Basis.IDENTITY, loop + Vector3(0, 0.09, 0)), Vector3(0.03, 0.03, 0.09), Color(0.45, 0.45, 0.48), hips)
	if look.has_accessory("satchel"):
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
	if look.has_accessory("suspenders"):
		_build_suspenders()
	if look.has_accessory("wide_hat"):
		_build_wide_hat()
	if look.has_accessory("headwrap"):
		_build_headwrap()
	if look.has_accessory("earrings"):
		for side in [1.0, -1.0]:
			var lobe := _head_surface(0.075, PI if side > 0 else 0.0, 0.004)
			t.loft([
				SkinnedMeshTool.ring(lobe + Vector3(side * 0.006, -0.012, 0), 0.0, 0.012, 0.012, head, Color(0.95, 0.75, 0.3)),
				SkinnedMeshTool.ring(lobe + Vector3(side * 0.006, -0.03, 0), 0.0, 0.012, 0.012, head, Color(0.95, 0.75, 0.3)),
			], 8, Vector3.BACK)
	if look.has_accessory("cloak"):
		_build_cloak()
	if look.has_accessory("backpack"):
		_build_backpack()


func _build_beard(long_beard: bool) -> void:
	var head := _bind(B.HEAD)
	var beard := _hair
	var rings: Array = []
	for y in [-0.048, -0.02, 0.01, 0.03]:
		rings.append(_head_ring(y, 0.014, head, beard))
	t.loft(rings, 12, Vector3.BACK, false, false, -0.25, PI + 0.25)
	# Cheeks and jawline up to the sideburns.
	for side in [1.0, -1.0]:
		var from := PI + 0.25 if side > 0 else -0.25
		var to := PI - 0.75 if side > 0 else 0.75
		var cheek_rings: Array = []
		for y in [0.0, 0.05, 0.1]:
			cheek_rings.append(_head_ring(y, 0.009, head, beard))
		t.loft(cheek_rings, 4, Vector3.BACK, false, false, minf(from, to), maxf(from, to))
	# Moustache.
	for side in [1.0, -1.0]:
		var m := _head_surface(0.058, PI * 0.5 + side * 0.2, 0.008)
		t.ellipsoid(Transform3D(Basis(Vector3.BACK, side * 0.25).scaled(Vector3(0.026, 0.009, 0.01)), m), beard, head, 7, 3)
	if long_beard:
		var chin := _head_surface(-0.03, PI * 0.5, 0.01)
		t.loft([
			SkinnedMeshTool.ring(chin + Vector3(0, 0.02, -0.02), 0.06, 0.03, 0.03, head, beard),
			SkinnedMeshTool.ring(chin + Vector3(0, -0.06, 0.0), 0.05, 0.032, 0.03, _blend(B.HEAD, B.NECK, 0.5), beard),
			SkinnedMeshTool.ring(chin + Vector3(0, -0.14, 0.012), 0.032, 0.024, 0.022, _blend(B.NECK, B.CHEST, 0.5), beard),
			SkinnedMeshTool.ring(chin + Vector3(0, -0.19, 0.016), 0.006, 0.006, 0.006, _bind(B.CHEST), beard),
		], 9, Vector3.BACK, true, true)


func _build_apron() -> void:
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
	for side in [1.0, -1.0]:
		t.tube(Vector3(side * 0.085, 1.36, _torso_front(1.36) + 0.012), Vector3(side * 0.05, 1.47, -0.03), 0.008, 0.008, cloth.darkened(0.2), _bind(B.CHEST), _bind(B.CHEST), 4)


func _build_cloak() -> void:
	var cloth := look.accent_color
	var rows := [
		[1.46, 0.13, -0.06, _bind(B.CHEST)],
		[1.3, 0.19, _torso_back(1.3) - 0.02, _bind(B.CHEST)],
		[1.1, 0.205, _torso_back(1.1) - 0.03, _blend(B.SPINE, B.CHEST, 0.4)],
		[0.9, 0.22, -0.15, _bind(B.HIPS)],
		[0.65, 0.235, -0.17, _bind(B.HIPS)],
		[0.48, 0.24, -0.18, _bind(B.HIPS)],
	]
	var rings: Array = []
	for row in rows:
		rings.append(SkinnedMeshTool.ring(Vector3(0, row[0], row[2]), row[1], 0.01, 0.01, row[3], cloth))
	t.loft(rings, 10)
	# Gathered hood around the neck.
	t.loft([
		SkinnedMeshTool.ring(Vector3(0, 1.44, -0.03), 0.12, 0.085, 0.11, _bind(B.CHEST), cloth.darkened(0.1)),
		SkinnedMeshTool.ring(Vector3(0, 1.5, -0.04), 0.095, 0.07, 0.1, _bind(B.CHEST), cloth.darkened(0.1)),
	], 12, Vector3.BACK, false, false, PI - 0.6, TAU + 0.6)
	# Clasp.
	t.ellipsoid_at(Vector3(0, 1.445, _torso_front(1.445) + 0.012), Vector3(0.016, 0.016, 0.008), Color(0.8, 0.7, 0.4), _bind(B.CHEST), 7, 4)


func _build_backpack() -> void:
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
	for side in [1.0, -1.0]:
		var back_top := Vector3(side * 0.09, 1.39, z + 0.05)
		var over := Vector3(side * 0.1, 1.47, -0.012)
		var front := Vector3(side * 0.1, 1.37, _torso_front(1.37) + 0.008)
		var low := Vector3(side * 0.12, 1.15, _torso_front(1.15) + 0.008)
		t.tube(back_top, over, 0.012, 0.012, pack.darkened(0.3), chest, chest, 5)
		t.tube(over, front, 0.012, 0.012, pack.darkened(0.3), chest, chest, 5)
		t.tube(front, low, 0.012, 0.012, pack.darkened(0.3), chest, _blend(B.SPINE, B.CHEST, 0.5), 5)


## Long locs falling from the crown over the back and shoulders.
func _hair_locs() -> void:
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
	var strap := LEATHER.lightened(0.05)
	var chest := _bind(B.CHEST)
	for side in [1.0, -1.0]:
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
