class_name MeshBuilder
extends RefCounted
## Accumulates flat-shaded, vertex-coloured low-poly primitives into a single
## ArrayMesh. Merging a whole building into one mesh keeps draw calls low,
## which matters far more on mobile GPUs than triangle count.
##
## Conventions:
## - Boxes and blobs are centred on their transform origin.
## - Cylinders, cones and prisms (roofs) start at their origin and grow upward.
## - Triangle winding is fixed automatically, so primitives always face out.

var rng := RandomNumberGenerator.new()
## Random brightness variation per face, gives the hand-made low-poly look.
var color_jitter: float = 0.035

var _st := SurfaceTool.new()
var _triangle_count: int = 0


func _init(seed_value: int = 0) -> void:
	rng.seed = seed_value
	_st.begin(Mesh.PRIMITIVE_TRIANGLES)


func is_empty() -> bool:
	return _triangle_count == 0


func get_triangle_count() -> int:
	return _triangle_count


## Commits all geometry. Returns null when nothing was added.
func build(material: Material = null) -> ArrayMesh:
	if _triangle_count == 0:
		return null
	_st.index()
	var mesh := _st.commit()
	if material:
		mesh.surface_set_material(0, material)
	return mesh


# --- Triangles ------------------------------------------------------------------

## Adds a triangle whose front face points away from `center`.
func add_triangle_outward(a: Vector3, b: Vector3, c: Vector3, color: Color, center: Vector3) -> void:
	var normal := (b - a).cross(c - a)
	if normal.length_squared() < 1e-12:
		return
	if normal.dot((a + b + c) / 3.0 - center) < 0.0:
		_emit(a, c, b, -normal, color)
	else:
		_emit(a, b, c, normal, color)


## Adds a triangle whose front face points toward `direction` (e.g. UP for terrain).
func add_triangle_facing(a: Vector3, b: Vector3, c: Vector3, color: Color, direction: Vector3) -> void:
	var normal := (b - a).cross(c - a)
	if normal.length_squared() < 1e-12:
		return
	if normal.dot(direction) < 0.0:
		_emit(a, c, b, -normal, color)
	else:
		_emit(a, b, c, normal, color)


func add_quad_outward(a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color, center: Vector3) -> void:
	add_triangle_outward(a, b, c, color, center)
	add_triangle_outward(a, c, d, color, center)


## `normal` is counter-clockwise when looking at the face from the outside.
## Godot treats clockwise winding as front-facing, so vertices are emitted a, c, b.
func _emit(a: Vector3, b: Vector3, c: Vector3, normal: Vector3, color: Color) -> void:
	var n := normal.normalized()
	var face_color := jitter(color)
	for vertex in [a, c, b]:
		_st.set_color(face_color)
		_st.set_normal(n)
		_st.add_vertex(vertex)
	_triangle_count += 1


func jitter(color: Color) -> Color:
	if color_jitter <= 0.0:
		return color
	var amount := rng.randf_range(-color_jitter, color_jitter)
	return Color(
		clampf(color.r + amount, 0.0, 1.0),
		clampf(color.g + amount, 0.0, 1.0),
		clampf(color.b + amount, 0.0, 1.0),
		color.a)


# --- Primitives -------------------------------------------------------------------

func add_box(xform: Transform3D, size: Vector3, color: Color) -> void:
	var h := size * 0.5
	var p: Array[Vector3] = []
	for corner in [
		Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, -h.y, h.z), Vector3(-h.x, -h.y, h.z),
		Vector3(-h.x, h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z),
	]:
		p.append(xform * corner)
	var center := xform.origin
	add_quad_outward(p[0], p[1], p[2], p[3], color, center) # bottom
	add_quad_outward(p[4], p[5], p[6], p[7], color, center) # top
	add_quad_outward(p[0], p[1], p[5], p[4], color, center) # back
	add_quad_outward(p[3], p[2], p[6], p[7], color, center) # front
	add_quad_outward(p[0], p[3], p[7], p[4], color, center) # left
	add_quad_outward(p[1], p[2], p[6], p[5], color, center) # right


## Convenience: axis-aligned box at a position with an optional yaw.
func add_box_at(position: Vector3, size: Vector3, color: Color, yaw: float = 0.0) -> void:
	add_box(Transform3D(Basis(Vector3.UP, yaw), position), size, color)


## Triangular prism roof. Ridge runs along local X, slopes face +Z / -Z.
func add_prism(xform: Transform3D, width: float, depth: float, height: float, color: Color) -> void:
	var w := width * 0.5
	var d := depth * 0.5
	var bl := xform * Vector3(-w, 0.0, -d)
	var br := xform * Vector3(w, 0.0, -d)
	var fl := xform * Vector3(-w, 0.0, d)
	var fr := xform * Vector3(w, 0.0, d)
	var rl := xform * Vector3(-w, height, 0.0)
	var rr := xform * Vector3(w, height, 0.0)
	var center := xform * Vector3(0.0, height * 0.33, 0.0)
	add_quad_outward(fl, fr, rr, rl, color, center)
	add_quad_outward(bl, br, rr, rl, color, center)
	add_triangle_outward(bl, fl, rl, color.darkened(0.08), center)
	add_triangle_outward(br, fr, rr, color.darkened(0.08), center)
	add_quad_outward(bl, br, fr, fl, color.darkened(0.3), center)


## Cylinder (or cone/frustum) from the origin upward along local Y.
func add_cylinder(xform: Transform3D, radius_bottom: float, radius_top: float, height: float,
		sides: int, color: Color, caps: bool = true) -> void:
	sides = maxi(sides, 3)
	var center := xform * Vector3(0.0, height * 0.5, 0.0)
	var bottom_center := xform * Vector3.ZERO
	var top_center := xform * Vector3(0.0, height, 0.0)
	for i in sides:
		var a0 := TAU * float(i) / float(sides)
		var a1 := TAU * float(i + 1) / float(sides)
		var b0 := xform * Vector3(cos(a0) * radius_bottom, 0.0, sin(a0) * radius_bottom)
		var b1 := xform * Vector3(cos(a1) * radius_bottom, 0.0, sin(a1) * radius_bottom)
		if radius_top <= 0.001:
			add_triangle_outward(b0, b1, top_center, color, center)
		else:
			var t0 := xform * Vector3(cos(a0) * radius_top, height, sin(a0) * radius_top)
			var t1 := xform * Vector3(cos(a1) * radius_top, height, sin(a1) * radius_top)
			add_quad_outward(b0, b1, t1, t0, color, center)
			if caps:
				add_triangle_outward(top_center, t0, t1, color, center)
		if caps:
			add_triangle_outward(bottom_center, b0, b1, color.darkened(0.2), center)


func add_cylinder_at(position: Vector3, radius_bottom: float, radius_top: float, height: float,
		sides: int, color: Color, caps: bool = true) -> void:
	add_cylinder(Transform3D(Basis.IDENTITY, position), radius_bottom, radius_top, height, sides, color, caps)


## Lumpy low-poly sphere (foliage, rocks, heads of cabbage). Scale with the basis.
func add_blob(xform: Transform3D, color: Color, segments: int = 7, rings: int = 4, lumpiness: float = 0.12) -> void:
	segments = maxi(segments, 4)
	rings = maxi(rings, 3)
	var grid: Array = []
	for r in rings + 1:
		var phi := PI * float(r) / float(rings)
		var row: Array[Vector3] = []
		for s in segments:
			var theta := TAU * float(s) / float(segments) + (0.5 if r % 2 == 1 else 0.0) * TAU / float(segments)
			var radius := 1.0
			if r != 0 and r != rings:
				radius += rng.randf_range(-lumpiness, lumpiness)
			var local := Vector3(sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta)) * radius
			row.append(xform * local)
		grid.append(row)
	var center := xform.origin
	for r in rings:
		var upper: Array[Vector3] = grid[r]
		var lower: Array[Vector3] = grid[r + 1]
		for s in segments:
			var s1 := (s + 1) % segments
			if r == 0:
				add_triangle_outward(upper[0], lower[s], lower[s1], color, center)
			elif r == rings - 1:
				add_triangle_outward(upper[s], upper[s1], lower[0], color, center)
			else:
				add_triangle_outward(upper[s], upper[s1], lower[s1], color, center)
				add_triangle_outward(upper[s], lower[s1], lower[s], color, center)


func add_blob_at(position: Vector3, scale: Vector3, color: Color, segments: int = 7, rings: int = 4,
		lumpiness: float = 0.12) -> void:
	add_blob(Transform3D(Basis.from_scale(scale), position), color, segments, rings, lumpiness)
