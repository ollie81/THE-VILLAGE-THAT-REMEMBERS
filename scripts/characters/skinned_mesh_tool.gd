class_name SkinnedMeshTool
extends RefCounted
## Builds a flat-shaded, vertex-coloured, skinned ArrayMesh from rounded
## primitives. Every vertex is bound to up to two skeleton bones, so joints
## bend smoothly instead of breaking apart.
##
## A binding is packed into a Vector3: (bone_a, bone_b, weight_of_b).
## Use bind(bone) for rigid parts and blend(a, b, t) across joints.

var rng := RandomNumberGenerator.new()
## Subtle brightness variation per face for the hand-made low-poly look.
var color_jitter: float = 0.006
## When true, each primitive gets soft (averaged) normals: rounded, sculpted
## shading instead of hard facets. Boxes always stay flat.
var smooth: bool = true

var _positions := PackedVector3Array()
var _normals := PackedVector3Array()
var _colors := PackedColorArray()
var _bones := PackedInt32Array()
var _weights := PackedFloat32Array()


func _init(seed_value: int = 0) -> void:
	rng.seed = seed_value


static func bind(bone: int) -> Vector3:
	return Vector3(bone, bone, 0.0)


static func blend(bone_a: int, bone_b: int, weight_b: float) -> Vector3:
	return Vector3(bone_a, bone_b, clampf(weight_b, 0.0, 1.0))


## Averages normals of coincident vertices from `start` to the end of the
## arrays, so one primitive shades smoothly without blending into others.
func _smooth_from(start: int) -> void:
	if not smooth:
		return
	var sums: Dictionary = {}
	for i in range(start, _positions.size()):
		var key := _positions[i].snapped(Vector3.ONE * 0.0001)
		sums[key] = sums.get(key, Vector3.ZERO) + _normals[i]
	for i in range(start, _positions.size()):
		var key := _positions[i].snapped(Vector3.ONE * 0.0001)
		var n: Vector3 = sums[key]
		if n.length_squared() > 1e-10:
			_normals[i] = n.normalized()


func get_triangle_count() -> int:
	return _positions.size() / 3


func build(material: Material) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _positions
	arrays[Mesh.ARRAY_NORMAL] = _normals
	arrays[Mesh.ARRAY_COLOR] = _colors
	arrays[Mesh.ARRAY_BONES] = _bones
	arrays[Mesh.ARRAY_WEIGHTS] = _weights
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	return mesh


# --- Triangles ---------------------------------------------------------------------

## Triangle facing away from `center`. Godot front faces are clockwise, so the
## vertices are emitted a, c, b relative to the counter-clockwise normal.
func triangle(a: Vector3, b: Vector3, c: Vector3, color: Color, center: Vector3,
		bind_a: Vector3, bind_b: Vector3, bind_c: Vector3) -> void:
	var normal := (b - a).cross(c - a)
	if normal.length_squared() < 1e-14:
		return
	if normal.dot((a + b + c) / 3.0 - center) < 0.0:
		normal = -normal
		var swap_p := b
		b = c
		c = swap_p
		var swap_b := bind_b
		bind_b = bind_c
		bind_c = swap_b
	normal = normal.normalized()
	var face_color := _jitter(color)
	_vertex(a, normal, face_color, bind_a)
	_vertex(c, normal, face_color, bind_c)
	_vertex(b, normal, face_color, bind_b)


func _vertex(p: Vector3, n: Vector3, c: Color, binding: Vector3) -> void:
	_positions.append(p)
	_normals.append(n)
	_colors.append(c)
	_bones.append_array(PackedInt32Array([int(binding.x), int(binding.y), 0, 0]))
	if int(binding.x) == int(binding.y):
		_weights.append_array(PackedFloat32Array([1.0, 0.0, 0.0, 0.0]))
	else:
		_weights.append_array(PackedFloat32Array([1.0 - binding.z, binding.z, 0.0, 0.0]))


func _jitter(color: Color) -> Color:
	var amount := rng.randf_range(-color_jitter, color_jitter)
	return Color(clampf(color.r + amount, 0, 1), clampf(color.g + amount, 0, 1), clampf(color.b + amount, 0, 1), color.a)


# --- Lofts --------------------------------------------------------------------------

## Creates a ring description for loft().
## center: ring centre. rx: half-width along the side axis.
## front / back: half-depth toward / away from the loft's front direction.
## color: colour of the band from this ring to the next.
static func ring(center: Vector3, rx: float, front: float, back: float, binding: Vector3, color: Color) -> Dictionary:
	return {"c": center, "rx": rx, "f": front, "b": back, "bind": binding, "color": color}


## Skins a tube through a list of rings (a limb, torso, head, shoe...).
## front_dir is the direction "front" radii point to (+Z for upright parts).
## arc_from / arc_to (radians, 0 = side, PI/2 = front) limit the tube to a
## partial shell (used for hair); a full turn closes the tube.
func loft(rings: Array, segments: int, front_dir: Vector3 = Vector3.BACK,
		cap_start: bool = true, cap_end: bool = true,
		arc_from: float = 0.0, arc_to: float = TAU) -> void:
	if rings.size() < 2:
		return
	var start := _positions.size()
	var full := absf(arc_to - arc_from - TAU) < 0.001
	var points_per_ring := segments if full else segments + 1
	var grid: Array = []
	var tangents: Array[Vector3] = []
	for i in rings.size():
		var prev: Vector3 = rings[maxi(i - 1, 0)]["c"]
		var next: Vector3 = rings[mini(i + 1, rings.size() - 1)]["c"]
		var tangent := (next - prev).normalized()
		if tangent.length_squared() < 0.5:
			tangent = Vector3.DOWN
		tangents.append(tangent)
		var front := (front_dir - tangent * front_dir.dot(tangent)).normalized()
		var side := front.cross(tangent).normalized()
		var r: Dictionary = rings[i]
		var center: Vector3 = r["c"]
		var points: Array[Vector3] = []
		for k in points_per_ring:
			var a := arc_from + (arc_to - arc_from) * float(k) / float(segments)
			var f := sin(a)
			var depth: float = f * (r["f"] if f > 0.0 else r["b"])
			points.append(center + side * cos(a) * float(r["rx"]) + front * depth)
		grid.append(points)

	var span := segments if full else segments
	for i in rings.size() - 1:
		var ra: Dictionary = rings[i]
		var rb: Dictionary = rings[i + 1]
		var lower: Array[Vector3] = grid[i]
		var upper: Array[Vector3] = grid[i + 1]
		var mid: Vector3 = (ra["c"] + rb["c"]) * 0.5
		var color: Color = ra["color"]
		var bind_a: Vector3 = ra["bind"]
		var bind_b: Vector3 = rb["bind"]
		for k in span:
			var k1 := (k + 1) % points_per_ring if full else k + 1
			triangle(lower[k], lower[k1], upper[k1], color, mid, bind_a, bind_a, bind_b)
			triangle(lower[k], upper[k1], upper[k], color, mid, bind_a, bind_b, bind_b)

	if not full:
		_smooth_from(start)
		return
	if cap_start:
		var r0: Dictionary = rings[0]
		var c0: Vector3 = r0["c"]
		var inside0 := c0 + tangents[0] * 0.01
		var ring0: Array[Vector3] = grid[0]
		for k in segments:
			triangle(c0, ring0[k], ring0[(k + 1) % segments], r0["color"], inside0, r0["bind"], r0["bind"], r0["bind"])
	if cap_end:
		var last := rings.size() - 1
		var rl: Dictionary = rings[last]
		var cl: Vector3 = rl["c"]
		var inside_l := cl - tangents[last] * 0.01
		var ring_l: Array[Vector3] = grid[last]
		var end_color: Color = rings[last - 1]["color"]
		for k in segments:
			triangle(cl, ring_l[k], ring_l[(k + 1) % segments], end_color, inside_l, rl["bind"], rl["bind"], rl["bind"])
	_smooth_from(start)


# --- Solids --------------------------------------------------------------------------

## Low-poly ellipsoid; scale and orient it with the transform basis.
func ellipsoid(xform: Transform3D, color: Color, binding: Vector3, segments: int = 8, rings: int = 5,
		lumpiness: float = 0.0) -> void:
	var start := _positions.size()
	var grid: Array = []
	for r in rings + 1:
		var phi := PI * float(r) / float(rings)
		var row: Array[Vector3] = []
		for s in segments:
			var theta := TAU * float(s) / float(segments)
			var radius := 1.0
			if lumpiness > 0.0 and r != 0 and r != rings:
				radius += rng.randf_range(-lumpiness, lumpiness)
			row.append(xform * (Vector3(sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta)) * radius))
		grid.append(row)
	var center := xform.origin
	for r in rings:
		var upper: Array[Vector3] = grid[r]
		var lower: Array[Vector3] = grid[r + 1]
		for s in segments:
			var s1 := (s + 1) % segments
			if r == 0:
				triangle(upper[0], lower[s], lower[s1], color, center, binding, binding, binding)
			elif r == rings - 1:
				triangle(upper[s], upper[s1], lower[0], color, center, binding, binding, binding)
			else:
				triangle(upper[s], upper[s1], lower[s1], color, center, binding, binding, binding)
				triangle(upper[s], lower[s1], lower[s], color, center, binding, binding, binding)
	_smooth_from(start)


func ellipsoid_at(position: Vector3, radii: Vector3, color: Color, binding: Vector3, segments: int = 8,
		rings: int = 5, lumpiness: float = 0.0) -> void:
	ellipsoid(Transform3D(Basis.from_scale(radii), position), color, binding, segments, rings, lumpiness)


func box(xform: Transform3D, size: Vector3, color: Color, binding: Vector3) -> void:
	var h := size * 0.5
	var p: Array[Vector3] = []
	for corner in [
		Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, -h.y, h.z), Vector3(-h.x, -h.y, h.z),
		Vector3(-h.x, h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z),
	]:
		p.append(xform * corner)
	var c := xform.origin
	for face in [[0, 1, 2, 3], [4, 5, 6, 7], [0, 1, 5, 4], [3, 2, 6, 7], [0, 3, 7, 4], [1, 2, 6, 5]]:
		triangle(p[face[0]], p[face[1]], p[face[2]], color, c, binding, binding, binding)
		triangle(p[face[0]], p[face[2]], p[face[3]], color, c, binding, binding, binding)


## A tapered tube between two points (fingers, straps, ponytails, tool handles).
func tube(from: Vector3, to: Vector3, radius_from: float, radius_to: float, color: Color,
		bind_from: Vector3, bind_to: Vector3, segments: int = 6, front_dir: Vector3 = Vector3.BACK) -> void:
	var axis := (to - from).normalized()
	var front := front_dir if absf(axis.dot(front_dir)) < 0.95 else Vector3.UP
	loft([
		ring(from, radius_from, radius_from, radius_from, bind_from, color),
		ring(to, radius_to, radius_to, radius_to, bind_to, color),
	], segments, front)
