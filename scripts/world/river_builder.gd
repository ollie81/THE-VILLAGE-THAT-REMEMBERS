class_name RiverBuilder
extends RefCounted
## The river, its bridge and the invisible walls that keep everyone out of the
## water and inside the world.

const WATER_HALF_WIDTH := 6.5
const BOUNDARY_LAYER := 16 # physics layer 5 "boundaries"


static func build(parent: Node3D) -> void:
	var root := Node3D.new()
	root.name = "River"
	parent.add_child(root)
	_build_water(root)
	_build_bank_walls(root)
	_build_world_bounds(root)
	root.add_child(_build_bridge())


static func _build_water(root: Node3D) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := VillageLayout.WORLD_HALF_SIZE
	var columns := 4
	var z := -half
	var step := 2.0
	while z < half:
		for c in columns:
			var u0 := float(c) / columns
			var u1 := float(c + 1) / columns
			var a := _water_point(z, u0)
			var b := _water_point(z, u1)
			var cc := _water_point(z + step, u1)
			var d := _water_point(z + step, u0)
			var v0 := (z + half) / (half * 2.0)
			var v1 := (z + step + half) / (half * 2.0)
			# Clockwise when seen from above (Godot front faces).
			for vertex in [[a, Vector2(u0, v0)], [b, Vector2(u1, v0)], [cc, Vector2(u1, v1)], [a, Vector2(u0, v0)], [cc, Vector2(u1, v1)], [d, Vector2(u0, v1)]]:
				st.set_normal(Vector3.UP)
				st.set_uv(vertex[1])
				st.add_vertex(vertex[0])
		z += step
	var mesh := st.commit()
	var instance := MeshInstance3D.new()
	instance.name = "Water"
	instance.mesh = mesh
	instance.material_override = Materials.water()
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(instance)


static func _water_point(z: float, u: float) -> Vector3:
	var x := VillageLayout.river_center_x(z) + lerpf(-WATER_HALF_WIDTH, WATER_HALF_WIDTH, u)
	return Vector3(x, VillageLayout.WATER_LEVEL, z)


## Walls along both banks, with a gap where the bridge lands.
static func _build_bank_walls(root: Node3D) -> void:
	var body := _make_boundary_body("RiverWalls")
	var gap := VillageLayout.BRIDGE_HALF_WIDTH + 0.3
	var segment := 4.0
	for direction in [-1.0, 1.0]:
		var z_start: float = VillageLayout.BRIDGE_Z + gap * direction
		var z_from := z_start
		while absf(z_from) < VillageLayout.WORLD_HALF_SIZE:
			var z_to: float = z_from + segment * direction
			for side in [-1.0, 1.0]:
				var a := Vector3(VillageLayout.river_center_x(z_from) + side * VillageLayout.RIVER_WALL_OFFSET, 0, z_from)
				var b := Vector3(VillageLayout.river_center_x(z_to) + side * VillageLayout.RIVER_WALL_OFFSET, 0, z_to)
				_add_wall_segment(body, a, b)
			z_from = z_to
	root.add_child(body)


static func _build_world_bounds(root: Node3D) -> void:
	var body := _make_boundary_body("WorldBounds")
	var h := VillageLayout.PLAYABLE_HALF_SIZE
	_add_wall_segment(body, Vector3(-h, 0, -h), Vector3(h, 0, -h))
	_add_wall_segment(body, Vector3(h, 0, -h), Vector3(h, 0, h))
	_add_wall_segment(body, Vector3(h, 0, h), Vector3(-h, 0, h))
	_add_wall_segment(body, Vector3(-h, 0, h), Vector3(-h, 0, -h))
	root.add_child(body)


static func _make_boundary_body(body_name: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = body_name
	body.collision_layer = BOUNDARY_LAYER
	body.collision_mask = 0
	return body


static func _add_wall_segment(body: StaticBody3D, a: Vector3, b: Vector3) -> void:
	var mid := (a + b) * 0.5
	var length := Vector2(b.x - a.x, b.z - a.z).length()
	var box := BoxShape3D.new()
	box.size = Vector3(0.6, 30.0, length + 0.4)
	var shape := CollisionShape3D.new()
	shape.shape = box
	var yaw := atan2(b.x - a.x, b.z - a.z)
	shape.transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(mid.x, 0.0, mid.z))
	body.add_child(shape)


# --- Bridge -------------------------------------------------------------------

static func _build_bridge() -> Node3D:
	var root := Node3D.new()
	root.name = "Bridge"
	var kit := BuildingFactory.Kit.new(4242)
	var m := kit.mesh
	var span := VillageLayout.bridge_x_range()
	var z0 := VillageLayout.BRIDGE_Z
	var half_w := VillageLayout.BRIDGE_HALF_WIDTH
	var segments := 14
	var deck_faces := PackedVector3Array()
	var plank := BuildingFactory.WOOD_LIGHT
	for i in segments:
		var xa := lerpf(span.x, span.y, float(i) / segments)
		var xb := lerpf(span.x, span.y, float(i + 1) / segments)
		var ya := VillageLayout.bridge_deck_height(xa)
		var yb := VillageLayout.bridge_deck_height(xb)
		var mid := Vector3((xa + xb) * 0.5, (ya + yb) * 0.5 - 0.08, z0)
		var tilt := atan2(yb - ya, xb - xa)
		m.add_box(Transform3D(Basis(Vector3.BACK, tilt), mid), Vector3((xb - xa) * 1.04, 0.16, half_w * 2.0 + 0.2),
			plank.darkened(0.06 * (i % 2)))
		# Walkable surface for collision, a smooth ramp with no seams.
		var a := Vector3(xa, ya, z0 - half_w - 0.1)
		var b := Vector3(xb, yb, z0 - half_w - 0.1)
		var c := Vector3(xb, yb, z0 + half_w + 0.1)
		var d := Vector3(xa, ya, z0 + half_w + 0.1)
		deck_faces.append_array(PackedVector3Array([a, b, c, a, c, d]))
		# Railing posts and rails.
		for side in [-1.0, 1.0]:
			var pz: float = z0 + side * (half_w - 0.05)
			if i % 2 == 0:
				m.add_box_at(Vector3(xa, ya + 0.45, pz), Vector3(0.14, 0.95, 0.14), BuildingFactory.WOOD_DARK)
			m.add_box(Transform3D(Basis(Vector3.BACK, tilt), Vector3((xa + xb) * 0.5, (ya + yb) * 0.5 + 0.9, pz)),
				Vector3((xb - xa) * 1.05, 0.1, 0.1), BuildingFactory.WOOD)
	for side in [-1.0, 1.0]:
		m.add_box_at(Vector3(span.y, VillageLayout.bridge_deck_height(span.y) + 0.45, z0 + side * (half_w - 0.05)),
			Vector3(0.14, 0.95, 0.14), BuildingFactory.WOOD_DARK)
	# Support piles into the riverbed.
	for t in [0.32, 0.68]:
		var x := lerpf(span.x, span.y, t)
		var top := VillageLayout.bridge_deck_height(x) - 0.15
		for side in [-1.0, 1.0]:
			m.add_cylinder_at(Vector3(x, VillageLayout.RIVER_BED_HEIGHT - 0.3, z0 + side * (half_w - 0.2)), 0.2, 0.18,
				top - VillageLayout.RIVER_BED_HEIGHT + 0.3, 6, BuildingFactory.WOOD_DARK)
		m.add_box_at(Vector3(x, top - 0.1, z0), Vector3(0.25, 0.2, half_w * 2.0 + 0.3), BuildingFactory.WOOD_DARK)

	var deck_shape := ConcavePolygonShape3D.new()
	deck_shape.backface_collision = true
	deck_shape.set_faces(deck_faces)
	var deck_collider := CollisionShape3D.new()
	deck_collider.shape = deck_shape
	kit.body.add_child(deck_collider)
	# Railings: tall straight walls so nobody falls in.
	var length := span.y - span.x
	for side in [-1.0, 1.0]:
		kit.box_collider(Vector3((span.x + span.y) * 0.5, 0.0, z0 + side * (half_w + 0.05)), Vector3(length, 4.0, 0.2))
	kit.finish(root)

	root.add_child(BuildingFactory.create_lantern(VillageLayout.ground_point(span.x - 0.9, z0 - 2.1)))
	root.add_child(BuildingFactory.create_lantern(VillageLayout.ground_point(span.y + 0.9, z0 + 2.1)))
	return root
