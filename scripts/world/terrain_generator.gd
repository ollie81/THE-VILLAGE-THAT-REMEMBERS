class_name TerrainGenerator
extends RefCounted
## Deterministic terrain height + a flat-shaded terrain mesh and collision.
## The village area is nearly flat, the outskirts rise into soft hills, and a
## river valley is carved down the east side.

const CELL_SIZE := 2.0
## Visible ground is split into chunks of this many cells a side.
const CHUNK_CELLS := 25
const CHUNK_VIEW_DISTANCE := 230.0
const SEED := 1337

const COLOR_GRASS := Color(0.42, 0.62, 0.3)
const COLOR_GRASS_DRY := Color(0.58, 0.64, 0.33)
const COLOR_GRASS_DARK := Color(0.27, 0.45, 0.24)
const COLOR_FOREST_FLOOR := Color(0.25, 0.37, 0.2)
const COLOR_PATH := Color(0.62, 0.5, 0.35)
const COLOR_SAND := Color(0.74, 0.67, 0.5)
const COLOR_RIVERBED := Color(0.42, 0.4, 0.33)
const COLOR_ROCK := Color(0.5, 0.5, 0.48)

static var _noise: FastNoiseLite
static var _detail_noise: FastNoiseLite
static var _path_segments: Array = []
static var _path_bounds := Rect2()


static func _get_noise() -> FastNoiseLite:
	if _noise == null:
		_noise = FastNoiseLite.new()
		_noise.seed = SEED
		_noise.frequency = 0.018
		_noise.fractal_octaves = 3
		_detail_noise = FastNoiseLite.new()
		_detail_noise.seed = SEED + 1
		_detail_noise.frequency = 0.09
	return _noise


static func get_height(x: float, z: float) -> float:
	var noise := _get_noise()
	var distance := Vector2(x, z).length()
	var hills := smoothstep(30.0, 66.0, distance)
	var height := noise.get_noise_2d(x, z) * (0.35 + 6.0 * hills) + hills * 3.0
	# The wider world. Nothing here touches the original village square, so
	# its ground (and everything built on it) stays exactly as it was.
	var square := maxf(absf(x), absf(z))
	if square > VillageLayout.CORE_HALF_SIZE + 2.0:
		height = _outer_height(x, z, height, square)
	var river_distance := absf(x - VillageLayout.river_center_x(z))
	var carve := 1.0 - smoothstep(VillageLayout.RIVER_HALF_WIDTH - 1.0, VillageLayout.RIVER_HALF_WIDTH + 2.6, river_distance)
	return lerpf(height, VillageLayout.RIVER_BED_HEIGHT, carve)


static var _mountain_noise: FastNoiseLite

## Farmland and the south street flattened, a lake and a pond dug out, and
## mountains rising toward the edge of the world.
static func _outer_height(x: float, z: float, height: float, square: float) -> float:
	var blend := smoothstep(VillageLayout.CORE_HALF_SIZE + 2.0, VillageLayout.CORE_HALF_SIZE + 16.0, square)
	var p := Vector2(x, z)
	for area: Rect2 in [VillageLayout.FARMLAND, VillageLayout.SOUTH_STREET]:
		var inside := _rect_weight(area, p, 12.0)
		if inside > 0.0:
			height = lerpf(height, 2.4 + _noise.get_noise_2d(x, z) * 0.4, inside * blend)
	for water in [[VillageLayout.LAKE_CENTER, VillageLayout.LAKE_RADIUS, -2.9], [VillageLayout.POND_CENTER, VillageLayout.POND_RADIUS, -2.3]]:
		var center: Vector3 = water[0]
		var d := p.distance_to(Vector2(center.x, center.z))
		var r: float = water[1]
		# A sloping beach into deep water in the middle.
		var shore := 1.0 - smoothstep(r - 1.0, r + 7.0, d)
		height = lerpf(height, minf(height, 0.4), shore * blend)
		var bowl := 1.0 - smoothstep(r * 0.25, r + 0.5, d)
		height = lerpf(height, float(water[2]), bowl * blend)
	if _mountain_noise == null:
		_mountain_noise = FastNoiseLite.new()
		_mountain_noise.seed = SEED + 7
		_mountain_noise.frequency = 0.011
		_mountain_noise.fractal_octaves = 4
	var rise := smoothstep(VillageLayout.MOUNTAINS_FROM - 10.0, VillageLayout.WORLD_HALF_SIZE, square)
	height += rise * rise * (26.0 + _mountain_noise.get_noise_2d(x, z) * 22.0)
	return height


## 1 inside the rectangle, fading to 0 over `fade` metres outside it.
static func _rect_weight(area: Rect2, p: Vector2, fade: float) -> float:
	var dx := maxf(maxf(area.position.x - p.x, p.x - area.end.x), 0.0)
	var dz := maxf(maxf(area.position.y - p.y, p.y - area.end.y), 0.0)
	return 1.0 - smoothstep(0.0, fade, Vector2(dx, dz).length())


## Builds the terrain mesh + collision under `parent`.
static func build(parent: Node3D) -> void:
	var path_segments := _get_path_segments()
	var half := VillageLayout.WORLD_HALF_SIZE
	var cells := int(half * 2.0 / CELL_SIZE)
	var heights: Array[PackedFloat32Array] = []
	for zi in cells + 1:
		var row := PackedFloat32Array()
		row.resize(cells + 1)
		for xi in cells + 1:
			row[xi] = get_height(-half + xi * CELL_SIZE, -half + zi * CELL_SIZE)
		heights.append(row)
	_get_noise()

	# What you see: the ground in chunks, so the camera only draws the near
	# ones and far chunks fade out behind the fog.
	var ground := Node3D.new()
	ground.name = "TerrainMesh"
	parent.add_child(ground)
	var chunk := CHUNK_CELLS
	for cz in range(0, cells, chunk):
		for cx in range(0, cells, chunk):
			var mi := MeshInstance3D.new()
			mi.name = "Chunk_%d_%d" % [cx / chunk, cz / chunk]
			mi.mesh = build_textured_mesh(heights, cells, path_segments, cx, cz, mini(chunk, cells - cx), mini(chunk, cells - cz))
			mi.visibility_range_end = CHUNK_VIEW_DISTANCE
			mi.visibility_range_end_margin = 10.0
			ground.add_child(mi)

	# Collision over the same grid (same triangle layout as always).
	var faces := PackedVector3Array()
	faces.resize(cells * cells * 6)
	var f := 0
	for zi in cells:
		for xi in cells:
			var x0 := -half + xi * CELL_SIZE
			var z0 := -half + zi * CELL_SIZE
			var p00 := Vector3(x0, heights[zi][xi], z0)
			var p10 := Vector3(x0 + CELL_SIZE, heights[zi][xi + 1], z0)
			var p01 := Vector3(x0, heights[zi + 1][xi], z0 + CELL_SIZE)
			var p11 := Vector3(x0 + CELL_SIZE, heights[zi + 1][xi + 1], z0 + CELL_SIZE)
			var tris: Array = [p00, p11, p10, p00, p01, p11] if (xi + zi) % 2 == 0 else [p00, p01, p10, p10, p01, p11]
			for v in tris:
				faces[f] = v
				f += 1
	var body := StaticBody3D.new()
	body.name = "TerrainBody"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var concave := ConcavePolygonShape3D.new()
	concave.backface_collision = true
	concave.set_faces(faces)
	shape.shape = concave
	body.add_child(shape)
	parent.add_child(body)

## The ground you see: shared, smooth-shaded vertices on the same 2 m grid,
## each carrying the old tint (COLOR) and how much path dirt and cobblestone
## it has (UV2), for the textured ground shader.
static func build_textured_mesh(heights: Array[PackedFloat32Array], cells: int, path_segments: Array,
		from_x: int = 0, from_z: int = 0, width: int = -1, depth: int = -1) -> ArrayMesh:
	var half := VillageLayout.WORLD_HALF_SIZE
	if width < 0:
		width = cells
	if depth < 0:
		depth = cells
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for zi in range(from_z, from_z + depth + 1):
		for xi in range(from_x, from_x + width + 1):
			var x := -half + xi * CELL_SIZE
			var z := -half + zi * CELL_SIZE
			var h: float = heights[zi][xi]
			var hl: float = heights[zi][maxi(xi - 1, 0)]
			var hr: float = heights[zi][mini(xi + 1, cells)]
			var hd: float = heights[maxi(zi - 1, 0)][xi]
			var hu: float = heights[mini(zi + 1, cells)][xi]
			var normal := Vector3(hl - hr, 2.0 * CELL_SIZE, hd - hu).normalized()
			var p := Vector3(x, h, z)
			var tint := _terrain_color(p, normal.y, path_segments)
			var plaza_distance := Vector2(x, z).length()
			var cobble := 1.0 - smoothstep(VillageLayout.PLAZA_RADIUS + 0.4, VillageLayout.PLAZA_RADIUS + 2.4, plaza_distance)
			var dirt := 1.0 - smoothstep(0.6, 1.9, _distance_to_segments(Vector2(x, z), path_segments))
			var river_distance := absf(x - VillageLayout.river_center_x(z))
			if h < VillageLayout.WATER_LEVEL + 0.6 and (river_distance < 8.0 or VillageLayout.is_water_area(x, z, 8.0)):
				dirt = maxf(dirt, 0.85)
			if normal.y < 0.82:
				dirt = maxf(dirt, 0.7)
			st.set_color(tint)
			st.set_uv(Vector2(x, z) * 0.1)
			st.set_uv2(Vector2(cobble, dirt))
			st.set_normal(normal)
			st.add_vertex(p)
	var row := width + 1
	for zi in depth:
		for xi in width:
			var i00 := zi * row + xi
			var i10 := i00 + 1
			var i01 := i00 + row
			var i11 := i01 + 1
			var order: Array = [i00, i10, i11, i00, i11, i01] if (xi + from_x + zi + from_z) % 2 == 0 else [i00, i10, i01, i10, i11, i01]
			for i in order:
				st.add_index(i)
	st.generate_tangents()
	var mesh := st.commit()
	mesh.surface_set_material(0, Materials.ground())
	return mesh


static func _add_terrain_triangle(builder: MeshBuilder, a: Vector3, b: Vector3, c: Vector3,
		path_segments: Array) -> void:
	var centroid := (a + b + c) / 3.0
	var normal := (b - a).cross(c - a).normalized()
	builder.add_triangle_facing(a, b, c, _terrain_color(centroid, absf(normal.y), path_segments), Vector3.UP)


static func _terrain_color(p: Vector3, flatness: float, path_segments: Array) -> Color:
	var variation := _detail_noise.get_noise_2d(p.x, p.z)
	var river_distance := absf(p.x - VillageLayout.river_center_x(p.z))
	if p.y < VillageLayout.WATER_LEVEL - 0.1:
		return COLOR_RIVERBED.lerp(COLOR_SAND, 0.2 + variation * 0.2)
	if p.y < VillageLayout.WATER_LEVEL + 0.45 and river_distance < 8.0:
		return COLOR_SAND.lerp(COLOR_GRASS_DRY, clampf((p.y - VillageLayout.WATER_LEVEL) * 1.5, 0.0, 1.0) * 0.5)
	if flatness < 0.82:
		return COLOR_ROCK.lerp(COLOR_GRASS_DARK, 0.3 + variation * 0.2)

	var flat_distance := Vector2(p.x, p.z).length()
	if flat_distance < VillageLayout.PLAZA_RADIUS + 1.0:
		return COLOR_PATH.darkened(0.05)
	var path_distance := _distance_to_segments(Vector2(p.x, p.z), path_segments)
	if path_distance < 1.05:
		return COLOR_PATH.lerp(COLOR_GRASS_DRY, clampf(path_distance - 0.3, 0.0, 1.0) * 0.6 + variation * 0.1)

	var base := COLOR_GRASS.lerp(COLOR_GRASS_DRY, clampf(0.35 + variation * 0.8, 0.0, 1.0))
	if p.x > VillageLayout.river_center_x(p.z) + 8.0:
		base = base.lerp(COLOR_FOREST_FLOOR, 0.65)
	elif flat_distance > 42.0:
		base = base.lerp(COLOR_GRASS_DARK, clampf((flat_distance - 42.0) / 20.0, 0.0, 0.6))
	return base


static func _get_path_segments() -> Array:
	if _path_segments.is_empty():
		var nodes := VillageLayout.get_nav_nodes()
		for edge in VillageLayout.get_nav_edges():
			var a: Vector3 = nodes[edge[0]]
			var b: Vector3 = nodes[edge[1]]
			_path_segments.append([Vector2(a.x, a.z), Vector2(b.x, b.z)])
			if _path_bounds.size == Vector2.ZERO:
				_path_bounds = Rect2(Vector2(a.x, a.z), Vector2.ZERO)
			_path_bounds = _path_bounds.expand(Vector2(a.x, a.z)).expand(Vector2(b.x, b.z))
	return _path_segments


## Far from every path the exact distance doesn't matter; callers only test
## small thresholds, so points outside the padded bounds return early.
static func _distance_to_segments(point: Vector2, segments: Array) -> float:
	if not _path_bounds.grow(6.0).has_point(point):
		return 6.0
	var best := INF
	for segment in segments:
		var a: Vector2 = segment[0]
		var b: Vector2 = segment[1]
		var closest := Geometry2D.get_closest_point_to_segment(point, a, b)
		best = minf(best, point.distance_to(closest))
	return best


## Public helper for decoration placement: distance from the painted paths.
static func distance_to_paths(x: float, z: float) -> float:
	return _distance_to_segments(Vector2(x, z), _get_path_segments())
