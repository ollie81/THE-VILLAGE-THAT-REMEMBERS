class_name NatureSpawner
extends RefCounted
## Scatters trees, bushes, rocks, grass, flowers, reeds and mushrooms.
## Everything is drawn with chunked MultiMeshes: one draw call per mesh type
## per chunk, frustum-culled per chunk, with small details distance-culled.

const CHUNK_SIZE := 24.0
const SEED := 2024

var rng := RandomNumberGenerator.new()

var _batches: Dictionary = {}
var _meshes: Dictionary = {}
var _occupied: Dictionary = {}
var _tree_body: StaticBody3D
var _detail_range: float = 45.0
var _grass_density: float = 1.0
var _grass_root: Node3D


func spawn(parent: Node3D) -> void:
	rng.seed = SEED
	_detail_range = GameSettings.detail_view_distance()
	_grass_density = GameSettings.grass_density()
	_build_meshes()
	var root := Node3D.new()
	root.name = "Nature"
	parent.add_child(root)
	_tree_body = StaticBody3D.new()
	_tree_body.name = "TreeCollision"
	_tree_body.collision_layer = 1
	_tree_body.collision_mask = 0
	root.add_child(_tree_body)

	_scatter_forest()
	_scatter_outskirts()
	_scatter_village_trees()
	_scatter_rocks()
	_scatter_river_details()
	_flush(root, ["tree", "pine", "bush", "rock", "log"])

	# Small details live under their own node so quality changes can rebuild them.
	_grass_root = Node3D.new()
	_grass_root.name = "GroundDetail"
	root.add_child(_grass_root)
	_scatter_ground_detail()
	_flush(_grass_root, ["grass", "flower", "mushroom", "reed", "pebble"])


# --- Meshes ----------------------------------------------------------------------

func _build_meshes() -> void:
	var material := Materials.vertex_color()
	var bark := Color(0.4, 0.28, 0.18)
	for v in 3:
		var b := MeshBuilder.new(SEED + v)
		var height := 1.8 + v * 0.4
		b.add_cylinder_at(Vector3(0, -0.3, 0), 0.26, 0.17, height + 0.6, 6, bark)
		var green := [Color(0.3, 0.52, 0.24), Color(0.38, 0.58, 0.26), Color(0.46, 0.6, 0.25)][v] as Color
		b.add_blob_at(Vector3(0, height + 1.2, 0), Vector3(1.8, 1.5, 1.8), green, 8, 4, 0.16)
		b.add_blob_at(Vector3(0.7, height + 0.6, 0.3), Vector3(1.1, 0.9, 1.1), green.darkened(0.08), 6, 4, 0.15)
		b.add_blob_at(Vector3(-0.6, height + 0.8, -0.4), Vector3(1.0, 0.9, 1.0), green.lightened(0.06), 6, 4, 0.15)
		_meshes["tree_%d" % v] = b.build(material)
	for v in 2:
		var b := MeshBuilder.new(SEED + 10 + v)
		b.add_cylinder_at(Vector3(0, -0.3, 0), 0.22, 0.15, 1.6, 6, bark.darkened(0.15))
		var pine := Color(0.2, 0.4, 0.27) if v == 0 else Color(0.24, 0.45, 0.3)
		for tier in 3:
			var radius := 1.6 - tier * 0.42
			b.add_cylinder_at(Vector3(0, 1.0 + tier * 1.05, 0), radius, 0.0, 1.9 - tier * 0.25, 7, pine.lightened(tier * 0.04))
		_meshes["pine_%d" % v] = b.build(material)
	var bush := MeshBuilder.new(SEED + 20)
	bush.add_blob_at(Vector3(0, 0.35, 0), Vector3(0.7, 0.55, 0.7), Color(0.32, 0.5, 0.25), 6, 3, 0.18)
	bush.add_blob_at(Vector3(0.45, 0.28, 0.2), Vector3(0.45, 0.4, 0.45), Color(0.36, 0.55, 0.27), 6, 3, 0.18)
	_meshes["bush_0"] = bush.build(material)
	for v in 2:
		var rock := MeshBuilder.new(SEED + 30 + v)
		rock.add_blob_at(Vector3(0, 0.15, 0), Vector3(0.7, 0.45, 0.6), Color(0.55, 0.55, 0.52).darkened(v * 0.1), 6, 4, 0.28)
		_meshes["rock_%d" % v] = rock.build(material)
	var log_builder := MeshBuilder.new(SEED + 40)
	log_builder.add_cylinder(Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(-1.4, 0.25, 0)), 0.28, 0.25, 2.8, 7, bark)
	log_builder.add_blob_at(Vector3(0.4, 0.5, 0.1), Vector3(0.25, 0.12, 0.25), Color(0.35, 0.5, 0.28), 5, 3)
	_meshes["log_0"] = log_builder.build(material)
	_meshes["grass_0"] = _build_grass_mesh()
	var flower_colors: Array[Color] = [Color(0.95, 0.85, 0.35), Color(0.9, 0.45, 0.6), Color(0.7, 0.6, 0.95), Color(0.98, 0.98, 0.95)]
	for v in flower_colors.size():
		var f := MeshBuilder.new(SEED + 50 + v)
		for i in 3:
			var offset := Vector3(rng.randf_range(-0.18, 0.18), 0, rng.randf_range(-0.18, 0.18))
			f.add_cylinder_at(offset, 0.015, 0.015, 0.3, 3, Color(0.3, 0.5, 0.25), false)
			f.add_blob_at(offset + Vector3(0, 0.33, 0), Vector3(0.07, 0.05, 0.07), flower_colors[v], 5, 3, 0.0)
		_meshes["flower_%d" % v] = f.build(material)
	var mushroom := MeshBuilder.new(SEED + 60)
	mushroom.add_cylinder_at(Vector3.ZERO, 0.04, 0.035, 0.16, 5, Color(0.92, 0.88, 0.8))
	mushroom.add_cylinder_at(Vector3(0, 0.14, 0), 0.13, 0.0, 0.1, 6, Color(0.78, 0.22, 0.18))
	_meshes["mushroom_0"] = mushroom.build(material)
	var reed := MeshBuilder.new(SEED + 70)
	for i in 5:
		var offset := Vector3(rng.randf_range(-0.2, 0.2), 0, rng.randf_range(-0.2, 0.2))
		reed.add_cylinder_at(offset, 0.03, 0.0, rng.randf_range(0.9, 1.4), 3, Color(0.45, 0.58, 0.3), false)
	reed.add_cylinder_at(Vector3(0.05, 0.8, 0), 0.045, 0.045, 0.25, 4, Color(0.42, 0.28, 0.18))
	_meshes["reed_0"] = reed.build(material)
	var pebble := MeshBuilder.new(SEED + 80)
	pebble.add_blob_at(Vector3(0, 0.03, 0), Vector3(0.12, 0.07, 0.1), Color(0.6, 0.6, 0.57), 5, 3, 0.2)
	pebble.add_blob_at(Vector3(0.18, 0.02, 0.08), Vector3(0.08, 0.05, 0.07), Color(0.5, 0.5, 0.48), 5, 3, 0.2)
	_meshes["pebble_0"] = pebble.build(material)


## A clump of grass blades, darker at the root and lighter at the tips.
func _build_grass_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var root_color := Color(0.3, 0.5, 0.22)
	var tip_color := Color(0.62, 0.78, 0.38)
	for i in 6:
		var angle := rng.randf() * TAU
		var offset := Vector3(rng.randf_range(-0.15, 0.15), 0, rng.randf_range(-0.15, 0.15))
		var side := Vector3(cos(angle), 0, sin(angle)) * 0.05
		var lean := Vector3(rng.randf_range(-0.1, 0.1), 0, rng.randf_range(-0.1, 0.1))
		var height := rng.randf_range(0.28, 0.48)
		var verts := [offset - side, offset + Vector3(0, height, 0) + lean, offset + side]
		var colors := [root_color, tip_color, root_color]
		for k in 3:
			st.set_normal(Vector3.UP)
			st.set_color(colors[k])
			st.add_vertex(verts[k])
	var mesh := st.commit()
	mesh.surface_set_material(0, Materials.grass())
	return mesh


# --- Placement rules ---------------------------------------------------------------

## True if something large may stand here (keeps paths, buildings and water clear).
func _is_clear(x: float, z: float, path_margin: float, building_margin: float) -> bool:
	if absf(x) > VillageLayout.WORLD_HALF_SIZE - 1.0 or absf(z) > VillageLayout.WORLD_HALF_SIZE - 1.0:
		return false
	if Vector2(x, z).length() < VillageLayout.PLAZA_RADIUS + building_margin:
		return false
	var river_distance := absf(x - VillageLayout.river_center_x(z))
	if river_distance < VillageLayout.RIVER_WALL_OFFSET + 0.6:
		return false
	if TerrainGenerator.distance_to_paths(x, z) < path_margin:
		return false
	for building in VillageLayout.get_buildings():
		var center: Vector3 = building["position"]
		var footprint: Vector2 = building["footprint"]
		var radius := footprint.length() * 0.5 + building_margin
		if Vector2(x - center.x, z - center.z).length() < radius:
			return false
	for node in VillageLayout.get_nav_nodes().values():
		var p: Vector3 = node
		if Vector2(x - p.x, z - p.z).length() < path_margin + 1.0:
			return false
	return true


func _has_neighbor(x: float, z: float, spacing: float) -> bool:
	var cx := int(floor(x / 4.0))
	var cz := int(floor(z / 4.0))
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var key := Vector2i(cx + dx, cz + dz)
			if not _occupied.has(key):
				continue
			for other in _occupied[key]:
				var o: Vector2 = other
				if o.distance_to(Vector2(x, z)) < spacing:
					return true
	return false


func _mark_occupied(x: float, z: float) -> void:
	var key := Vector2i(int(floor(x / 4.0)), int(floor(z / 4.0)))
	if not _occupied.has(key):
		_occupied[key] = []
	_occupied[key].append(Vector2(x, z))


func _random_xform(x: float, z: float, scale_min: float, scale_max: float, sink: float = 0.0) -> Transform3D:
	var s := rng.randf_range(scale_min, scale_max)
	var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.9, 1.15), s))
	return Transform3D(basis, Vector3(x, TerrainGenerator.get_height(x, z) - sink, z))


func _add_instance(kind: String, variant: int, xform: Transform3D) -> void:
	var cx := int(floor(xform.origin.x / CHUNK_SIZE))
	var cz := int(floor(xform.origin.z / CHUNK_SIZE))
	var key := "%s_%d|%d|%d" % [kind, variant, cx, cz]
	if not _batches.has(key):
		_batches[key] = {"kind": kind, "mesh": "%s_%d" % [kind, variant], "transforms": []}
	_batches[key]["transforms"].append(xform)


func _add_tree(x: float, z: float, prefer_pine: bool) -> void:
	var pine := rng.randf() < (0.7 if prefer_pine else 0.25)
	var xform := _random_xform(x, z, 0.85, 1.35)
	if pine:
		_add_instance("pine", rng.randi_range(0, 1), xform)
	else:
		_add_instance("tree", rng.randi_range(0, 2), xform)
	_mark_occupied(x, z)
	if absf(x) < VillageLayout.PLAYABLE_HALF_SIZE + 1.0 and absf(z) < VillageLayout.PLAYABLE_HALF_SIZE + 1.0:
		var cylinder := CylinderShape3D.new()
		cylinder.radius = 0.32 * xform.basis.get_scale().x
		cylinder.height = 3.0
		var shape := CollisionShape3D.new()
		shape.shape = cylinder
		shape.position = xform.origin + Vector3(0, 1.4, 0)
		_tree_body.add_child(shape)


# --- Scatter passes -----------------------------------------------------------------

func _scatter_forest() -> void:
	var forest_node: Vector3 = VillageLayout.get_nav_nodes()["forest_edge"]
	for i in 1400:
		var z := rng.randf_range(-VillageLayout.WORLD_HALF_SIZE, VillageLayout.WORLD_HALF_SIZE)
		var x := rng.randf_range(VillageLayout.river_center_x(z) + 7.0, VillageLayout.WORLD_HALF_SIZE)
		if Vector2(x - forest_node.x, z - forest_node.z).length() < 6.5:
			continue
		if not _is_clear(x, z, 2.2, 1.0) or _has_neighbor(x, z, 2.6):
			continue
		_add_tree(x, z, x > forest_node.x + 10.0)
		if rng.randf() < 0.25:
			_add_instance("bush", 0, _random_xform(x + rng.randf_range(-1.5, 1.5), z + rng.randf_range(-1.5, 1.5), 0.8, 1.3))
	for i in 10:
		var z := rng.randf_range(-50.0, 50.0)
		var x := rng.randf_range(VillageLayout.river_center_x(z) + 10.0, 60.0)
		if _is_clear(x, z, 2.5, 1.0) and not _has_neighbor(x, z, 2.0):
			_add_instance("log", 0, _random_xform(x, z, 0.9, 1.2, 0.05))


func _scatter_outskirts() -> void:
	for i in 1600:
		var x := rng.randf_range(-VillageLayout.WORLD_HALF_SIZE, VillageLayout.WORLD_HALF_SIZE)
		var z := rng.randf_range(-VillageLayout.WORLD_HALF_SIZE, VillageLayout.WORLD_HALF_SIZE)
		if x > VillageLayout.river_center_x(z):
			continue
		var distance := Vector2(x, z).length()
		var density := smoothstep(32.0, 58.0, distance)
		if rng.randf() > density:
			continue
		if not _is_clear(x, z, 2.5, 2.0) or _has_neighbor(x, z, 3.0):
			continue
		_add_tree(x, z, distance > 55.0)
		if rng.randf() < 0.3:
			_add_instance("bush", 0, _random_xform(x + rng.randf_range(-2.0, 2.0), z + rng.randf_range(-2.0, 2.0), 0.7, 1.2))


## A few shade trees inside the village so it doesn't feel like a clearing.
func _scatter_village_trees() -> void:
	var placed := 0
	var attempts := 0
	while placed < 14 and attempts < 400:
		attempts += 1
		var angle := rng.randf() * TAU
		var distance := rng.randf_range(12.0, 30.0)
		var x := cos(angle) * distance
		var z := sin(angle) * distance
		if not _is_clear(x, z, 3.0, 2.5) or _has_neighbor(x, z, 6.0):
			continue
		_add_tree(x, z, false)
		placed += 1
	for i in 60:
		var x := rng.randf_range(-30.0, 28.0)
		var z := rng.randf_range(-30.0, 30.0)
		if _is_clear(x, z, 1.6, 1.0) and not _has_neighbor(x, z, 1.5):
			_add_instance("bush", 0, _random_xform(x, z, 0.6, 1.1))


func _scatter_rocks() -> void:
	for i in 160:
		var x := rng.randf_range(-VillageLayout.WORLD_HALF_SIZE, VillageLayout.WORLD_HALF_SIZE)
		var z := rng.randf_range(-VillageLayout.WORLD_HALF_SIZE, VillageLayout.WORLD_HALF_SIZE)
		if Vector2(x, z).length() < 22.0 or not _is_clear(x, z, 2.0, 1.5) or _has_neighbor(x, z, 1.5):
			continue
		var big := rng.randf() < 0.3
		var xform := _random_xform(x, z, 1.4 if big else 0.4, 2.4 if big else 1.0, 0.1)
		_add_instance("rock", rng.randi_range(0, 1), xform)
		if big:
			var sphere := SphereShape3D.new()
			sphere.radius = 0.5 * xform.basis.get_scale().x
			var shape := CollisionShape3D.new()
			shape.shape = sphere
			shape.position = xform.origin + Vector3(0, 0.05, 0)
			_tree_body.add_child(shape)


func _scatter_river_details() -> void:
	for i in 120:
		var z := rng.randf_range(-VillageLayout.WORLD_HALF_SIZE, VillageLayout.WORLD_HALF_SIZE)
		if absf(z - VillageLayout.BRIDGE_Z) < 3.0:
			continue
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var x := VillageLayout.river_center_x(z) + side * rng.randf_range(2.6, 5.0)
		_add_instance("rock", rng.randi_range(0, 1), _random_xform(x, z, 0.4, 1.0, 0.15))


func _scatter_ground_detail() -> void:
	var grass_attempts := int(14000 * _grass_density)
	for i in grass_attempts:
		var x := rng.randf_range(-58.0, 58.0)
		var z := rng.randf_range(-58.0, 58.0)
		if not _is_ground_detail_spot(x, z):
			continue
		_add_instance("grass", 0, _random_xform(x, z, 0.7, 1.4, 0.02))
	for i in int(1800 * _grass_density):
		var x := rng.randf_range(-50.0, 50.0)
		var z := rng.randf_range(-50.0, 50.0)
		if x > VillageLayout.river_center_x(z) + 9.0 or not _is_ground_detail_spot(x, z):
			continue
		_add_instance("flower", rng.randi_range(0, 3), _random_xform(x, z, 0.8, 1.2))
	for i in 260:
		var z := rng.randf_range(-58.0, 58.0)
		var x := rng.randf_range(VillageLayout.river_center_x(z) + 8.0, 62.0)
		if _is_ground_detail_spot(x, z):
			_add_instance("mushroom", 0, _random_xform(x, z, 0.7, 1.5))
	for i in 220:
		var z := rng.randf_range(-62.0, 62.0)
		if absf(z - VillageLayout.BRIDGE_Z) < 3.0:
			continue
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var x := VillageLayout.river_center_x(z) + side * rng.randf_range(4.3, 5.6)
		_add_instance("reed", 0, _random_xform(x, z, 0.8, 1.2, 0.05))
	for i in 500:
		var x := rng.randf_range(-40.0, 40.0)
		var z := rng.randf_range(-40.0, 40.0)
		if TerrainGenerator.distance_to_paths(x, z) < 1.4 and Vector2(x, z).length() > VillageLayout.PLAZA_RADIUS:
			_add_instance("pebble", 0, _random_xform(x, z, 0.8, 1.4))


func _is_ground_detail_spot(x: float, z: float) -> bool:
	var height := TerrainGenerator.get_height(x, z)
	if height < VillageLayout.WATER_LEVEL + 0.35:
		return false
	if Vector2(x, z).length() < VillageLayout.PLAZA_RADIUS + 0.8:
		return false
	if TerrainGenerator.distance_to_paths(x, z) < 1.3:
		return false
	for building in VillageLayout.get_buildings():
		var center: Vector3 = building["position"]
		var footprint: Vector2 = building["footprint"]
		if absf(x - center.x) < footprint.x * 0.5 + 0.6 and absf(z - center.z) < footprint.y * 0.5 + 0.6:
			if building["type"] != "memory_oak":
				return false
	return true


# --- Output -----------------------------------------------------------------------

func _flush(parent: Node3D, kinds: Array) -> void:
	for key in _batches.keys():
		var batch: Dictionary = _batches[key]
		if not kinds.has(batch["kind"]):
			continue
		var transforms: Array = batch["transforms"]
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = _meshes[batch["mesh"]]
		multimesh.instance_count = transforms.size()
		for i in transforms.size():
			multimesh.set_instance_transform(i, transforms[i])
		var instance := MultiMeshInstance3D.new()
		instance.name = String(key).replace("|", "_")
		instance.multimesh = multimesh
		match String(batch["kind"]):
			"grass", "flower", "mushroom", "pebble":
				instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				instance.visibility_range_end = _detail_range
				instance.visibility_range_end_margin = 4.0
				instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
			"reed", "rock":
				instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				instance.visibility_range_end = _detail_range * 1.6
		parent.add_child(instance)
		_batches.erase(key)
