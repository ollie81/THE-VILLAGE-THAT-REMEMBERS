class_name TerrainGenerator
extends RefCounted
## Deterministic terrain height + a flat-shaded terrain mesh and collision.
## The village area is nearly flat, the outskirts rise into soft hills, and a
## river valley is carved down the east side.

const CELL_SIZE := 2.0
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
	var river_distance := absf(x - VillageLayout.river_center_x(z))
	var carve := 1.0 - smoothstep(VillageLayout.RIVER_HALF_WIDTH - 1.0, VillageLayout.RIVER_HALF_WIDTH + 2.6, river_distance)
	return lerpf(height, VillageLayout.RIVER_BED_HEIGHT, carve)


## Builds the terrain mesh + collision under `parent`.
static func build(parent: Node3D) -> void:
	var path_segments := _get_path_segments()
	var builder := MeshBuilder.new(SEED)
	builder.color_jitter = 0.0
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
	for zi in cells:
		for xi in cells:
			var x0 := -half + xi * CELL_SIZE
			var z0 := -half + zi * CELL_SIZE
			var p00 := Vector3(x0, heights[zi][xi], z0)
			var p10 := Vector3(x0 + CELL_SIZE, heights[zi][xi + 1], z0)
			var p01 := Vector3(x0, heights[zi + 1][xi], z0 + CELL_SIZE)
			var p11 := Vector3(x0 + CELL_SIZE, heights[zi + 1][xi + 1], z0 + CELL_SIZE)
			# Alternate the diagonal for a less grid-like look.
			if (xi + zi) % 2 == 0:
				_add_terrain_triangle(builder, p00, p10, p11, path_segments)
				_add_terrain_triangle(builder, p00, p11, p01, path_segments)
			else:
				_add_terrain_triangle(builder, p00, p10, p01, path_segments)
				_add_terrain_triangle(builder, p10, p11, p01, path_segments)

	var mesh := builder.build(Materials.vertex_color())
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "TerrainMesh"
	mesh_instance.mesh = mesh
	parent.add_child(mesh_instance)

	var body := StaticBody3D.new()
	body.name = "TerrainBody"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	shape.shape = mesh.create_trimesh_shape()
	body.add_child(shape)
	parent.add_child(body)


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
