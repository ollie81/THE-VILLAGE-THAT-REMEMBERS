class_name BuildingFactory
extends RefCounted
## Procedurally assembles every structure in the village from low-poly
## primitives. Each building becomes one merged mesh (+ one glow mesh for
## windows) and a handful of simple box colliders.
##
## All local coordinates use +Z as the front of the building.

const WOOD := Color(0.47, 0.32, 0.19)
const WOOD_DARK := Color(0.3, 0.2, 0.12)
const WOOD_LIGHT := Color(0.66, 0.5, 0.32)
const STONE := Color(0.58, 0.57, 0.53)
const STONE_DARK := Color(0.42, 0.42, 0.4)
const SOIL := Color(0.34, 0.23, 0.15)
const THATCH := Color(0.76, 0.62, 0.34)
const LEAF := Color(0.3, 0.52, 0.26)
const HAY := Color(0.86, 0.74, 0.4)

## Each home reflects its owner.
const HOUSE_STYLES := {
	"mara": {"wall": Color(0.86, 0.8, 0.7), "roof": Color(0.64, 0.29, 0.2), "trim": Color(0.36, 0.24, 0.15), "accent": Color(0.75, 0.35, 0.2)},
	"elias": {"wall": Color(0.93, 0.87, 0.68), "roof": Color(0.76, 0.62, 0.34), "trim": Color(0.4, 0.3, 0.18), "accent": Color(0.35, 0.55, 0.3)},
	"nia": {"wall": Color(0.84, 0.89, 0.8), "roof": Color(0.36, 0.52, 0.4), "trim": Color(0.38, 0.28, 0.2), "accent": Color(0.6, 0.45, 0.75)},
	"tomas": {"wall": Color(0.8, 0.73, 0.62), "roof": Color(0.4, 0.37, 0.36), "trim": Color(0.28, 0.2, 0.14), "accent": Color(0.55, 0.4, 0.25)},
	"cottage": {"wall": Color(0.86, 0.8, 0.66), "roof": Color(0.55, 0.36, 0.22), "trim": Color(0.38, 0.27, 0.17), "accent": Color(0.42, 0.56, 0.36)},
	"player": {"wall": Color(0.9, 0.84, 0.74), "roof": Color(0.3, 0.52, 0.5), "trim": Color(0.34, 0.24, 0.16), "accent": Color(0.85, 0.55, 0.3)},
	"sera": {"wall": Color(0.93, 0.79, 0.63), "roof": Color(0.27, 0.46, 0.62), "trim": Color(0.36, 0.25, 0.16), "accent": Color(0.95, 0.72, 0.25)},
}


## Helper that collects geometry and colliders for one structure.
class Kit:
	var mesh: MeshBuilder
	var glow: MeshBuilder
	var body: StaticBody3D

	func _init(seed_value: int) -> void:
		mesh = MeshBuilder.new(seed_value)
		glow = MeshBuilder.new(seed_value + 1)
		glow.color_jitter = 0.0
		body = StaticBody3D.new()
		body.name = "Collision"
		body.collision_layer = 1
		body.collision_mask = 0

	func box_collider(center: Vector3, size: Vector3, yaw: float = 0.0) -> void:
		var box := BoxShape3D.new()
		box.size = size
		var shape := CollisionShape3D.new()
		shape.shape = box
		shape.transform = Transform3D(Basis(Vector3.UP, yaw), center)
		body.add_child(shape)

	func cylinder_collider(base: Vector3, radius: float, height: float) -> void:
		var cylinder := CylinderShape3D.new()
		cylinder.radius = radius
		cylinder.height = height
		var shape := CollisionShape3D.new()
		shape.shape = cylinder
		shape.position = base + Vector3(0.0, height * 0.5, 0.0)
		body.add_child(shape)

	func finish(root: Node3D) -> void:
		var main_mesh := mesh.build(Materials.vertex_color())
		if main_mesh:
			var instance := MeshInstance3D.new()
			instance.name = "Mesh"
			instance.mesh = main_mesh
			root.add_child(instance)
		var glow_mesh := glow.build(Materials.window_glow())
		if glow_mesh:
			var glow_instance := MeshInstance3D.new()
			glow_instance.name = "Windows"
			glow_instance.mesh = glow_mesh
			glow_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(glow_instance)
		if body.get_child_count() > 0:
			root.add_child(body)
		else:
			body.free()


## Builds the structure described by a VillageLayout building entry.
static func create(building: Dictionary) -> Node3D:
	var root := Node3D.new()
	var id: String = building["id"]
	root.name = id.to_pascal_case()
	var position: Vector3 = building["position"]
	var footprint: Vector2 = building["footprint"]
	var yaw: float = building["yaw"]
	root.position = Vector3(position.x, _base_height(position, footprint, yaw), position.z)
	root.rotation.y = yaw
	var kit := Kit.new(hash(id))
	match String(building["type"]):
		"house":
			_build_house(kit, building["owner"])
		"storage":
			_build_storage(kit)
		"workshop":
			_build_workshop(kit)
		"garden":
			_build_garden(kit)
		"farm":
			_build_farm(kit, position)
		"plaza":
			_build_plaza(kit, root)
		"memory_oak":
			_build_memory_oak(kit)
		"build_site":
			_build_construction_site(kit)
		"camp":
			_build_camp(kit, root)
	kit.finish(root)
	return root


## Highest ground under the footprint, so foundations never float.
static func _base_height(position: Vector3, footprint: Vector2, yaw: float) -> float:
	var best := TerrainGenerator.get_height(position.x, position.z)
	var basis := Basis(Vector3.UP, yaw)
	for corner in [Vector3(-0.5, 0, -0.5), Vector3(0.5, 0, -0.5), Vector3(-0.5, 0, 0.5), Vector3(0.5, 0, 0.5)]:
		var offset: Vector3 = basis * (corner * Vector3(footprint.x, 0.0, footprint.y))
		best = maxf(best, TerrainGenerator.get_height(position.x + offset.x, position.z + offset.z))
	return best


# --- Homes ----------------------------------------------------------------------

static func _build_house(kit: Kit, owner: String) -> void:
	var style: Dictionary = HOUSE_STYLES.get(owner, HOUSE_STYLES["mara"])
	var wall: Color = style["wall"]
	var roof: Color = style["roof"]
	var trim: Color = style["trim"]
	var accent: Color = style["accent"]
	var w := 6.0
	var d := 4.4
	var m := kit.mesh

	m.add_box_at(Vector3(0, -0.35, 0), Vector3(w + 0.4, 1.3, d + 0.4), STONE)
	m.add_box_at(Vector3(0, 1.6, 0), Vector3(w, 2.6, d), wall)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			m.add_box_at(Vector3(sx * w * 0.5, 1.6, sz * d * 0.5), Vector3(0.28, 2.7, 0.28), trim)
	for sz in [-1.0, 1.0]:
		m.add_box_at(Vector3(0, 2.85, sz * d * 0.5), Vector3(w + 0.1, 0.22, 0.26), trim)
		m.add_box_at(Vector3(0, 0.42, sz * d * 0.5), Vector3(w + 0.1, 0.18, 0.24), trim)
	m.add_prism(Transform3D(Basis.IDENTITY, Vector3(0, 2.9, 0)), w + 0.9, d + 1.3, 1.9, roof)
	m.add_box_at(Vector3(0, 4.82, 0), Vector3(w + 1.0, 0.14, 0.3), roof.darkened(0.25))
	m.add_box_at(Vector3(w * 0.3, 4.1, -d * 0.18), Vector3(0.62, 2.2, 0.62), STONE_DARK)

	# Front door, frame and step.
	m.add_box_at(Vector3(0, 1.3, d * 0.5 + 0.04), Vector3(1.1, 1.95, 0.1), WOOD_DARK)
	m.add_box_at(Vector3(0, 2.33, d * 0.5 + 0.06), Vector3(1.4, 0.14, 0.14), trim)
	m.add_box_at(Vector3(0.36, 1.3, d * 0.5 + 0.1), Vector3(0.08, 0.08, 0.06), accent)
	m.add_box_at(Vector3(0, 0.3, d * 0.5 + 0.55), Vector3(1.6, 0.22, 0.8), STONE)

	# Windows: glowing panes, shutters and flower boxes.
	for sx in [-1.0, 1.0]:
		var wx: float = sx * 1.9
		kit.glow.add_box_at(Vector3(wx, 1.75, d * 0.5 + 0.03), Vector3(0.85, 0.75, 0.06), Color.WHITE)
		m.add_box_at(Vector3(wx, 1.75, d * 0.5 + 0.07), Vector3(0.07, 0.75, 0.04), trim)
		m.add_box_at(Vector3(wx - 0.6, 1.75, d * 0.5 + 0.06), Vector3(0.3, 0.85, 0.05), accent)
		m.add_box_at(Vector3(wx + 0.6, 1.75, d * 0.5 + 0.06), Vector3(0.3, 0.85, 0.05), accent)
		m.add_box_at(Vector3(wx, 1.25, d * 0.5 + 0.2), Vector3(1.0, 0.22, 0.3), WOOD)
		for i in 4:
			var flower_color: Color = [Color(0.9, 0.35, 0.4), Color(0.95, 0.8, 0.3), Color(0.7, 0.45, 0.85)][i % 3]
			m.add_blob_at(Vector3(wx - 0.36 + i * 0.24, 1.43, d * 0.5 + 0.22), Vector3(0.13, 0.12, 0.13), flower_color, 5, 3)
		kit.glow.add_box_at(Vector3(sx * (w * 0.5 + 0.03), 1.75, 0), Vector3(0.06, 0.75, 0.85), Color.WHITE)
		m.add_box_at(Vector3(sx * (w * 0.5 + 0.06), 1.75, 0), Vector3(0.04, 0.75, 0.07), trim)
	kit.glow.add_box_at(Vector3(-1.4, 1.75, -d * 0.5 - 0.03), Vector3(0.85, 0.75, 0.06), Color.WHITE)

	kit.box_collider(Vector3(0, 1.3, 0), Vector3(w + 0.4, 3.4, d + 0.4))
	_add_house_details(kit, owner, w, d)


## Small personal touches so each home tells you about its owner.
static func _add_house_details(kit: Kit, owner: String, w: float, d: float) -> void:
	var m := kit.mesh
	var side := w * 0.5 + 0.7
	match owner:
		"mara":
			# Builder: stacked lumber and a ladder against the wall.
			for i in 4:
				m.add_box_at(Vector3(side, 0.15 + i * 0.16, 0.3), Vector3(0.7, 0.14, 2.4), WOOD_LIGHT.darkened(i * 0.05))
			m.add_box_at(Vector3(-side + 0.45, 1.5, -0.8), Vector3(0.08, 3.0, 0.08), WOOD)
			m.add_box_at(Vector3(-side + 0.45, 1.5, -0.3), Vector3(0.08, 3.0, 0.08), WOOD)
			for i in 6:
				m.add_box_at(Vector3(-side + 0.45, 0.4 + i * 0.45, -0.55), Vector3(0.06, 0.06, 0.5), WOOD)
			kit.box_collider(Vector3(side, 0.4, 0.3), Vector3(0.8, 0.8, 2.5))
		"elias":
			# Farmer: hay bales and a sack of grain.
			m.add_cylinder(Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(side + 0.4, 0.45, 0.6)), 0.45, 0.45, 0.9, 8, HAY)
			m.add_box_at(Vector3(side, 0.35, -0.9), Vector3(0.9, 0.7, 0.7), HAY.darkened(0.08))
			m.add_blob_at(Vector3(-side + 0.2, 0.3, 1.4), Vector3(0.3, 0.35, 0.28), Color(0.8, 0.72, 0.55), 6, 4)
			kit.box_collider(Vector3(side + 0.2, 0.45, -0.1), Vector3(1.2, 0.9, 2.4))
		"nia":
			# Herbalist: potted plants and herbs hung to dry.
			for i in 3:
				var pz := -1.2 + i * 1.1
				m.add_cylinder_at(Vector3(side - 0.2, 0, pz), 0.22, 0.28, 0.4, 7, Color(0.72, 0.42, 0.3))
				m.add_blob_at(Vector3(side - 0.2, 0.62, pz), Vector3(0.3, 0.32, 0.3), LEAF.lightened(i * 0.08), 6, 3)
			m.add_box_at(Vector3(0, 2.6, d * 0.5 + 0.5), Vector3(2.2, 0.06, 0.06), WOOD)
			for i in 5:
				m.add_cylinder(Transform3D(Basis(Vector3.RIGHT, PI), Vector3(-0.9 + i * 0.45, 2.58, d * 0.5 + 0.5)), 0.02, 0.12, 0.45, 5, Color(0.45, 0.6, 0.35) if i % 2 == 0 else Color(0.6, 0.5, 0.7))
		"tomas":
			# Craftsman: a hand-made bench by the door, a carved post.
			m.add_box_at(Vector3(1.9, 0.5, d * 0.5 + 0.7), Vector3(1.6, 0.1, 0.45), WOOD_LIGHT)
			m.add_box_at(Vector3(1.3, 0.25, d * 0.5 + 0.7), Vector3(0.1, 0.5, 0.4), WOOD)
			m.add_box_at(Vector3(2.5, 0.25, d * 0.5 + 0.7), Vector3(0.1, 0.5, 0.4), WOOD)
			m.add_cylinder_at(Vector3(-side, 0, 1.2), 0.14, 0.12, 1.6, 6, WOOD_DARK)
			m.add_blob_at(Vector3(-side, 1.75, 1.2), Vector3(0.2, 0.2, 0.2), WOOD_LIGHT, 5, 3)
			kit.box_collider(Vector3(1.9, 0.3, d * 0.5 + 0.7), Vector3(1.6, 0.6, 0.45))
		"sera":
			# Trader: crates of goods and a colourful awning.
			m.add_box_at(Vector3(side, 0.35, 0.8), Vector3(0.7, 0.7, 0.7), WOOD_LIGHT)
			m.add_box_at(Vector3(side, 0.95, 0.75), Vector3(0.5, 0.5, 0.5), WOOD)
			m.add_cylinder_at(Vector3(side, 0, -0.5), 0.3, 0.3, 0.8, 8, WOOD_DARK)
			m.add_box_at(Vector3(0, 2.5, d * 0.5 + 0.55), Vector3(2.0, 0.06, 1.0), Color(0.85, 0.3, 0.28))
			for i in 4:
				var stripe := Color(0.95, 0.85, 0.5) if i % 2 == 0 else Color(0.85, 0.3, 0.28)
				m.add_box_at(Vector3(-0.75 + i * 0.5, 2.44, d * 0.5 + 1.05), Vector3(0.5, 0.14, 0.04), stripe)
			kit.box_collider(Vector3(side, 0.5, 0.2), Vector3(0.8, 1.0, 2.1))


# --- Shared buildings ---------------------------------------------------------------

static func _build_storage(kit: Kit) -> void:
	var m := kit.mesh
	var w := 7.0
	var d := 5.4
	var plank := Color(0.55, 0.36, 0.22)
	m.add_box_at(Vector3(0, -0.35, 0), Vector3(w + 0.4, 1.3, d + 0.4), STONE_DARK)
	m.add_box_at(Vector3(0, 1.8, 0), Vector3(w, 3.0, d), plank)
	# Vertical plank lines.
	for i in 13:
		var x := -w * 0.5 + 0.25 + i * 0.54
		m.add_box_at(Vector3(x, 1.8, d * 0.5 + 0.02), Vector3(0.05, 3.0, 0.04), plank.darkened(0.2))
	m.add_prism(Transform3D(Basis.IDENTITY, Vector3(0, 3.3, 0)), w + 1.0, d + 1.4, 2.3, Color(0.5, 0.25, 0.2))
	# Big double doors with cross braces.
	m.add_box_at(Vector3(0, 1.5, d * 0.5 + 0.05), Vector3(2.4, 2.5, 0.1), WOOD_DARK)
	for sx in [-0.6, 0.6]:
		m.add_box(Transform3D(Basis(Vector3.BACK, 0.75), Vector3(sx, 1.5, d * 0.5 + 0.11)), Vector3(0.1, 2.6, 0.04), WOOD_LIGHT)
		m.add_box(Transform3D(Basis(Vector3.BACK, -0.75), Vector3(sx, 1.5, d * 0.5 + 0.11)), Vector3(0.1, 2.6, 0.04), WOOD_LIGHT)
	m.add_box_at(Vector3(0, 2.85, d * 0.5 + 0.08), Vector3(2.7, 0.18, 0.14), WOOD_LIGHT)
	kit.glow.add_box_at(Vector3(0, 3.9, d * 0.5 + 0.55), Vector3(0.7, 0.6, 0.06), Color.WHITE)
	kit.box_collider(Vector3(0, 1.5, 0), Vector3(w + 0.4, 3.6, d + 0.4))

	# Goods stacked outside.
	var crate_area := Vector3(-w * 0.5 + 0.4, 0, d * 0.5 + 1.4)
	m.add_box_at(crate_area + Vector3(0, 0.4, 0), Vector3(0.8, 0.8, 0.8), WOOD_LIGHT)
	m.add_box_at(crate_area + Vector3(0.9, 0.35, 0.1), Vector3(0.7, 0.7, 0.7), WOOD)
	m.add_box_at(crate_area + Vector3(0.4, 1.1, 0.0), Vector3(0.6, 0.6, 0.6), WOOD_LIGHT.darkened(0.1), 0.3)
	kit.box_collider(crate_area + Vector3(0.45, 0.6, 0.05), Vector3(1.8, 1.2, 0.9))
	var barrel_area := Vector3(w * 0.5 - 0.4, 0, d * 0.5 + 1.2)
	for offset in [Vector3.ZERO, Vector3(-0.7, 0, 0.3), Vector3(-0.3, 0, -0.5)]:
		var p: Vector3 = barrel_area + offset
		m.add_cylinder_at(p, 0.32, 0.32, 0.9, 8, WOOD)
		m.add_cylinder_at(p + Vector3(0, 0.2, 0), 0.335, 0.335, 0.08, 8, STONE_DARK, false)
		m.add_cylinder_at(p + Vector3(0, 0.65, 0), 0.335, 0.335, 0.08, 8, STONE_DARK, false)
	kit.box_collider(barrel_area + Vector3(-0.35, 0.45, -0.05), Vector3(1.4, 0.9, 1.4))
	for i in 3:
		m.add_blob_at(Vector3(-w * 0.5 - 0.5, 0.3, -1.0 + i * 0.75), Vector3(0.32, 0.33, 0.3), Color(0.82, 0.74, 0.56), 6, 4)


static func _build_workshop(kit: Kit) -> void:
	var m := kit.mesh
	var w := 6.4
	var d := 4.2
	# Stone floor slab, posts, back + side wall and a lean-to roof.
	m.add_box_at(Vector3(0, -0.2, 0), Vector3(w + 0.3, 0.5, d + 0.3), STONE)
	for sx in [-1.0, 1.0]:
		m.add_box_at(Vector3(sx * w * 0.5, 1.45, d * 0.5), Vector3(0.26, 2.9, 0.26), WOOD_DARK)
		m.add_box_at(Vector3(sx * w * 0.5, 1.2, -d * 0.5), Vector3(0.26, 2.4, 0.26), WOOD_DARK)
		kit.box_collider(Vector3(sx * w * 0.5, 1.4, d * 0.5), Vector3(0.3, 2.8, 0.3))
	m.add_box_at(Vector3(0, 1.2, -d * 0.5 + 0.08), Vector3(w, 2.4, 0.16), WOOD)
	m.add_box_at(Vector3(-w * 0.5 + 0.08, 1.2, 0), Vector3(0.16, 2.4, d), WOOD)
	kit.box_collider(Vector3(0, 1.2, -d * 0.5 + 0.08), Vector3(w, 2.4, 0.3))
	kit.box_collider(Vector3(-w * 0.5 + 0.08, 1.2, 0), Vector3(0.3, 2.4, d))
	var roof_tilt := atan2(0.6, d + 1.0)
	m.add_box(Transform3D(Basis(Vector3.RIGHT, roof_tilt), Vector3(0, 2.75, 0.1)), Vector3(w + 1.0, 0.16, d + 1.4), Color(0.45, 0.35, 0.3))
	# Tools on the back wall.
	for i in 5:
		m.add_box_at(Vector3(-1.6 + i * 0.55, 1.75, -d * 0.5 + 0.2), Vector3(0.06, 0.7, 0.04), WOOD_LIGHT)
		m.add_box_at(Vector3(-1.6 + i * 0.55, 2.05, -d * 0.5 + 0.22), Vector3(0.22, 0.12, 0.05), STONE_DARK)
	# Workbench (back right).
	var bench := Vector3(1.0, 0, -1.2)
	m.add_box_at(bench + Vector3(0, 0.92, 0), Vector3(2.2, 0.12, 0.85), WOOD_LIGHT)
	for sx in [-0.95, 0.95]:
		for sz in [-0.32, 0.32]:
			m.add_box_at(bench + Vector3(sx, 0.43, sz), Vector3(0.1, 0.86, 0.1), WOOD_DARK)
	m.add_box_at(bench + Vector3(-0.5, 1.05, 0.1), Vector3(0.7, 0.14, 0.2), WOOD)
	kit.box_collider(bench + Vector3(0, 0.5, 0), Vector3(2.2, 1.0, 0.85))
	# Anvil on a stump.
	var anvil := Vector3(-1.4, 0, -0.4)
	m.add_cylinder_at(anvil, 0.38, 0.34, 0.55, 8, WOOD)
	m.add_box_at(anvil + Vector3(0, 0.66, 0), Vector3(0.6, 0.22, 0.28), STONE_DARK.darkened(0.3))
	m.add_box_at(anvil + Vector3(0.38, 0.7, 0), Vector3(0.22, 0.12, 0.16), STONE_DARK.darkened(0.3))
	kit.cylinder_collider(anvil, 0.4, 0.8)
	# Chopping block and firewood outside the front.
	var block := Vector3(-2.2, 0, 2.0)
	m.add_cylinder_at(block, 0.4, 0.38, 0.5, 8, WOOD_LIGHT)
	m.add_box(Transform3D(Basis(Vector3.BACK, 0.5), block + Vector3(0.1, 0.75, 0)), Vector3(0.06, 0.6, 0.06), WOOD_DARK)
	for i in 6:
		var row := i / 3
		var col := i % 3
		m.add_cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(w * 0.5 + 0.7, 0.2 + row * 0.36, -1.2 + col * 0.38 + row * 0.19)),
			0.18, 0.18, 1.2, 6, WOOD.lightened(0.05 * col))
	kit.box_collider(Vector3(w * 0.5 + 0.7, 0.4, -0.6), Vector3(1.3, 0.8, 1.4))


static func _build_garden(kit: Kit) -> void:
	var m := kit.mesh
	var half := Vector2(4.5, 3.5)
	# Low woven fence with a gap at the front gate.
	for i in 19:
		var x := -half.x + i * 0.5
		m.add_box_at(Vector3(x, 0.2, half.y), Vector3(0.08, 1.0, 0.08), WOOD) # back
		if absf(x) > 0.9:
			m.add_box_at(Vector3(x, 0.2, -half.y), Vector3(0.08, 1.0, 0.08), WOOD)
	for i in 15:
		var z := -half.y + i * 0.5
		m.add_box_at(Vector3(-half.x, 0.2, z), Vector3(0.08, 1.0, 0.08), WOOD)
		m.add_box_at(Vector3(half.x, 0.2, z), Vector3(0.08, 1.0, 0.08), WOOD)
	for h in [0.3, 0.58]:
		m.add_box_at(Vector3(0, h, half.y), Vector3(half.x * 2.0, 0.06, 0.05), WOOD_LIGHT)
		m.add_box_at(Vector3(-half.x, h, 0), Vector3(0.05, 0.06, half.y * 2.0), WOOD_LIGHT)
		m.add_box_at(Vector3(half.x, h, 0), Vector3(0.05, 0.06, half.y * 2.0), WOOD_LIGHT)
		for sx in [-1.0, 1.0]:
			m.add_box_at(Vector3(sx * (half.x + 0.9) * 0.5, h, -half.y), Vector3(half.x - 0.9, 0.06, 0.05), WOOD_LIGHT)
	kit.box_collider(Vector3(0, 0.4, half.y), Vector3(half.x * 2.0, 0.8, 0.2))
	kit.box_collider(Vector3(-half.x, 0.4, 0), Vector3(0.2, 0.8, half.y * 2.0))
	kit.box_collider(Vector3(half.x, 0.4, 0), Vector3(0.2, 0.8, half.y * 2.0))
	for sx in [-1.0, 1.0]:
		kit.box_collider(Vector3(sx * (half.x + 0.9) * 0.5, 0.4, -half.y), Vector3(half.x - 0.9, 0.8, 0.2))

	# Arched trellis over the gate with climbing flowers.
	for sx in [-0.85, 0.85]:
		m.add_box_at(Vector3(sx, 1.1, -half.y), Vector3(0.1, 2.2, 0.1), WOOD_LIGHT)
	m.add_box_at(Vector3(0, 2.25, -half.y), Vector3(1.9, 0.1, 0.25), WOOD_LIGHT)
	for i in 7:
		var t := float(i) / 6.0
		var p := Vector3(lerpf(-0.85, 0.85, t), 1.0 + sin(t * PI) * 1.3, -half.y)
		m.add_blob_at(p, Vector3(0.22, 0.22, 0.22), Color(0.85, 0.4, 0.6) if i % 2 == 0 else LEAF, 5, 3)

	# Four raised beds of herbs and flowers.
	var bed_colors: Array[Color] = [
		Color(0.62, 0.48, 0.8), # lavender
		Color(0.95, 0.62, 0.2), # marigold
		Color(0.55, 0.68, 0.5), # sage
		Color(0.92, 0.42, 0.45), # rose
	]
	var beds: Array[Vector3] = [Vector3(-2.4, 0, -1.4), Vector3(2.4, 0, -1.4), Vector3(-2.4, 0, 1.6), Vector3(2.4, 0, 1.6)]
	for b in beds.size():
		var center := beds[b]
		m.add_box_at(center + Vector3(0, 0.08, 0), Vector3(3.0, 0.56, 1.3), WOOD)
		m.add_box_at(center + Vector3(0, 0.37, 0), Vector3(2.8, 0.04, 1.1), SOIL)
		for i in 10:
			var px := center.x - 1.2 + (i % 5) * 0.6
			var pz := center.z - 0.28 + (i / 5) * 0.56
			m.add_blob_at(Vector3(px, 0.52, pz), Vector3(0.24, 0.2, 0.24), LEAF.lightened(0.05 * (i % 3)), 5, 3)
			m.add_blob_at(Vector3(px + 0.05, 0.7, pz), Vector3(0.11, 0.12, 0.11), bed_colors[b], 5, 3)
		kit.box_collider(center + Vector3(0, 0.25, 0), Vector3(3.0, 0.5, 1.3))

	# Watering can and a little drying rack.
	m.add_cylinder_at(Vector3(0.6, 0, 2.9), 0.16, 0.14, 0.32, 7, Color(0.45, 0.55, 0.6))
	m.add_box(Transform3D(Basis(Vector3.BACK, -0.8), Vector3(0.82, 0.25, 2.9)), Vector3(0.05, 0.35, 0.05), Color(0.45, 0.55, 0.6))
	for sx in [-3.6, -2.0]:
		m.add_box_at(Vector3(sx, 0.7, 3.0), Vector3(0.08, 1.4, 0.08), WOOD)
	m.add_box_at(Vector3(-2.8, 1.35, 3.0), Vector3(1.7, 0.06, 0.06), WOOD)
	for i in 4:
		m.add_cylinder(Transform3D(Basis(Vector3.RIGHT, PI), Vector3(-3.4 + i * 0.4, 1.33, 3.0)), 0.02, 0.1, 0.4, 5, Color(0.5, 0.62, 0.4))


static func _build_farm(kit: Kit, world_origin: Vector3) -> void:
	var m := kit.mesh
	var half := Vector2(7.0, 5.5)
	var gate_min := -6.0
	var gate_max := -4.0
	# Rail fence, following the ground, with a gate gap on the north side.
	var posts: Array[Vector3] = []
	var x := -half.x
	while x <= half.x + 0.01:
		posts.append(Vector3(x, 0, -half.y))
		posts.append(Vector3(x, 0, half.y))
		x += 1.75
	var z := -half.y + 1.833
	while z < half.y - 0.01:
		posts.append(Vector3(-half.x, 0, z))
		posts.append(Vector3(half.x, 0, z))
		z += 1.833
	for post in posts:
		if post.z < 0.0 and absf(post.z + half.y) < 0.01 and post.x > gate_min + 0.1 and post.x < gate_max - 0.1:
			continue
		var h := _local_ground(world_origin, post)
		m.add_box_at(Vector3(post.x, h + 0.55, post.z), Vector3(0.14, 1.2, 0.14), WOOD_DARK)
	for rail_y in [0.45, 0.85]:
		_fence_rail(m, world_origin, Vector3(-half.x, 0, half.y), Vector3(half.x, 0, half.y), rail_y)
		_fence_rail(m, world_origin, Vector3(-half.x, 0, -half.y), Vector3(-half.x, 0, half.y), rail_y)
		_fence_rail(m, world_origin, Vector3(half.x, 0, -half.y), Vector3(half.x, 0, half.y), rail_y)
		_fence_rail(m, world_origin, Vector3(-half.x, 0, -half.y), Vector3(gate_min, 0, -half.y), rail_y)
		_fence_rail(m, world_origin, Vector3(gate_max, 0, -half.y), Vector3(half.x, 0, -half.y), rail_y)
	kit.box_collider(Vector3(0, 0.6, half.y), Vector3(half.x * 2.0, 1.6, 0.2))
	kit.box_collider(Vector3(-half.x, 0.6, 0), Vector3(0.2, 1.6, half.y * 2.0))
	kit.box_collider(Vector3(half.x, 0.6, 0), Vector3(0.2, 1.6, half.y * 2.0))
	kit.box_collider(Vector3((-half.x + gate_min) * 0.5, 0.6, -half.y), Vector3(gate_min + half.x, 1.6, 0.2))
	kit.box_collider(Vector3((gate_max + half.x) * 0.5, 0.6, -half.y), Vector3(half.x - gate_max, 1.6, 0.2))

	# Tilled rows: wheat in the west, cabbages in the middle, carrots in the east.
	var row_z := -4.3
	var row_index := 0
	while row_z < 4.8:
		var row_h := _local_ground(world_origin, Vector3(0, 0, row_z))
		m.add_box_at(Vector3(0, row_h + 0.04, row_z), Vector3(half.x * 2.0 - 0.8, 0.22, 0.75), SOIL)
		var cx := -half.x + 0.8
		while cx < half.x - 0.6:
			var ground := _local_ground(world_origin, Vector3(cx, 0, row_z)) + 0.14
			var jitter := Vector3(m.rng.randf_range(-0.08, 0.08), 0, m.rng.randf_range(-0.1, 0.1))
			var p := Vector3(cx, ground, row_z) + jitter
			if cx < -2.2:
				for s in 3:
					var stalk := p + Vector3(m.rng.randf_range(-0.14, 0.14), 0, m.rng.randf_range(-0.14, 0.14))
					m.add_cylinder_at(stalk, 0.05, 0.0, m.rng.randf_range(0.7, 0.95), 4, Color(0.6, 0.66, 0.3))
					m.add_cylinder_at(stalk + Vector3(0, 0.55, 0), 0.07, 0.0, 0.4, 4, HAY)
			elif cx < 2.6:
				m.add_blob_at(p + Vector3(0, 0.15, 0), Vector3(0.28, 0.22, 0.28), Color(0.45, 0.68, 0.35), 6, 3)
				m.add_blob_at(p + Vector3(0, 0.28, 0), Vector3(0.16, 0.14, 0.16), Color(0.62, 0.8, 0.45), 5, 3)
			else:
				for s in 2:
					var leaf := p + Vector3(s * 0.2 - 0.1, 0, 0)
					m.add_cylinder_at(leaf, 0.08, 0.0, 0.35, 4, Color(0.35, 0.65, 0.3))
			cx += 0.6
		row_z += 1.5
		row_index += 1

	# Scarecrow wearing Elias's old shirt.
	var sc := Vector3(0.6, _local_ground(world_origin, Vector3(0.6, 0, 0.8)), 0.8)
	m.add_box_at(sc + Vector3(0, 1.0, 0), Vector3(0.1, 2.0, 0.1), WOOD)
	m.add_box_at(sc + Vector3(0, 1.45, 0), Vector3(1.4, 0.08, 0.08), WOOD)
	m.add_box_at(sc + Vector3(0, 1.35, 0), Vector3(0.5, 0.6, 0.3), Color(0.7, 0.35, 0.3))
	m.add_blob_at(sc + Vector3(0, 1.9, 0), Vector3(0.22, 0.24, 0.22), Color(0.88, 0.8, 0.6), 6, 4)
	m.add_cylinder_at(sc + Vector3(0, 2.05, 0), 0.42, 0.0, 0.32, 8, HAY)
	kit.cylinder_collider(sc, 0.2, 2.0)

	# Hay bales and a water trough outside the field.
	for i in 3:
		var bale := Vector3(half.x + 1.2, 0, -3.0 + i * 1.1)
		bale.y = _local_ground(world_origin, bale)
		m.add_cylinder(Transform3D(Basis(Vector3.FORWARD, PI * 0.5), bale + Vector3(0.45, 0.48, 0)), 0.48, 0.48, 0.9, 8, HAY.darkened(i * 0.04))
	kit.box_collider(Vector3(half.x + 1.2, 0.5, -1.9), Vector3(1.0, 1.0, 3.3))
	var trough := Vector3(-half.x - 1.0, _local_ground(world_origin, Vector3(-half.x - 1.0, 0, 2.0)), 2.0)
	m.add_box_at(trough + Vector3(0, 0.3, 0), Vector3(0.8, 0.5, 1.8), WOOD)
	m.add_box_at(trough + Vector3(0, 0.52, 0), Vector3(0.6, 0.04, 1.6), Color(0.35, 0.55, 0.7))
	kit.box_collider(trough + Vector3(0, 0.3, 0), Vector3(0.8, 0.6, 1.8))


## Farm-local ground height (the farm is not rotated, only translated).
static func _local_ground(world_origin: Vector3, local: Vector3) -> float:
	var base := _base_height(world_origin, Vector2(14.0, 11.0), 0.0)
	return TerrainGenerator.get_height(world_origin.x + local.x, world_origin.z + local.z) - base


static func _fence_rail(m: MeshBuilder, world_origin: Vector3, from: Vector3, to: Vector3, height: float) -> void:
	var a := Vector3(from.x, _local_ground(world_origin, from) + height, from.z)
	var b := Vector3(to.x, _local_ground(world_origin, to) + height, to.z)
	var mid := (a + b) * 0.5
	var direction := b - a
	var length := direction.length()
	var basis := Basis.looking_at(direction.normalized(), Vector3.UP)
	m.add_box(Transform3D(basis, mid), Vector3(0.07, 0.1, length), WOOD_LIGHT)


# --- Meeting circle -----------------------------------------------------------------

static func _build_plaza(kit: Kit, root: Node3D) -> void:
	var m := kit.mesh
	var r := VillageLayout.PLAZA_RADIUS
	m.add_cylinder_at(Vector3(0, -0.58, 0), r, r, 0.62, 24, Color(0.5, 0.48, 0.44))
	m.add_cylinder_at(Vector3(0, -0.58, 0), r * 0.62, r * 0.62, 0.645, 18, Color(0.56, 0.52, 0.46))
	# Paving stones dotted over the surface.
	for i in 36:
		var angle := m.rng.randf() * TAU
		var dist := m.rng.randf_range(2.0, r - 0.4)
		m.add_box_at(Vector3(cos(angle) * dist, 0.05, sin(angle) * dist), Vector3(0.6, 0.04, 0.45), STONE.lightened(m.rng.randf_range(-0.05, 0.12)), m.rng.randf() * PI)
	# Fire pit: ring of stones, logs and ash.
	for i in 12:
		var a := TAU * i / 12.0
		m.add_blob_at(Vector3(cos(a) * 1.0, 0.25, sin(a) * 1.0), Vector3(0.28, 0.24, 0.28), STONE_DARK.lightened(0.05 * (i % 3)), 6, 3)
	m.add_cylinder_at(Vector3(0, 0.08, 0), 0.8, 0.8, 0.08, 10, Color(0.2, 0.18, 0.17))
	for i in 4:
		var a := i * PI * 0.5 + 0.4
		m.add_cylinder(Transform3D(Basis(Vector3.UP, a) * Basis(Vector3.FORWARD, 1.2), Vector3(0, 0.2, 0)), 0.1, 0.08, 0.8, 6, WOOD_DARK)
	kit.cylinder_collider(Vector3(0, 0.1, 0), 1.25, 0.6)
	_add_fire(root)

	# Log benches between the walking spots.
	for i in 4:
		var angle := deg_to_rad(22.5 + i * 90.0)
		var center := Vector3(cos(angle) * 4.6, 0, sin(angle) * 4.6)
		var tangent_yaw := atan2(center.x, center.z)
		var log_basis := Basis(Vector3.UP, tangent_yaw) * Basis(Vector3.FORWARD, PI * 0.5)
		m.add_cylinder(Transform3D(log_basis, center + Vector3(0, 0.45, 0) + Basis(Vector3.UP, tangent_yaw) * Vector3(-1.1, 0, 0)), 0.26, 0.26, 2.2, 8, WOOD)
		for s in [-0.75, 0.75]:
			var stump: Vector3 = center + Basis(Vector3.UP, tangent_yaw) * Vector3(s, 0, 0)
			m.add_cylinder_at(stump + Vector3(0, 0.1, 0), 0.2, 0.2, 0.22, 6, WOOD_DARK)
		kit.box_collider(center + Vector3(0, 0.4, 0), Vector3(2.2, 0.75, 0.55), tangent_yaw)

	# A carved story stone: the village's first memory.
	var stone_pos := Vector3(0, 0, -r + 0.6)
	m.add_box_at(stone_pos + Vector3(0, 0.8, 0), Vector3(1.0, 1.6, 0.35), STONE.darkened(0.1), 0.0)
	m.add_box_at(stone_pos + Vector3(0, 1.66, 0), Vector3(0.8, 0.18, 0.3), STONE.darkened(0.15))
	for i in 3:
		m.add_box_at(stone_pos + Vector3(0, 0.5 + i * 0.3, 0.18), Vector3(0.6, 0.05, 0.02), Color(0.3, 0.3, 0.3))
	kit.box_collider(stone_pos + Vector3(0, 0.8, 0), Vector3(1.0, 1.6, 0.4))

	for angle_deg in [112.5, 337.5]:
		var a := deg_to_rad(angle_deg)
		root.add_child(create_lantern(Vector3(cos(a) * (r + 0.6), 0, sin(a) * (r + 0.6))))


static func _add_fire(root: Node3D) -> void:
	var builder := MeshBuilder.new(7)
	builder.color_jitter = 0.0
	builder.add_cylinder_at(Vector3(0, 0.15, 0), 0.45, 0.0, 1.0, 6, Color.WHITE)
	builder.add_cylinder_at(Vector3(0.22, 0.15, 0.1), 0.25, 0.0, 0.7, 5, Color.WHITE)
	builder.add_cylinder_at(Vector3(-0.2, 0.15, -0.12), 0.25, 0.0, 0.6, 5, Color.WHITE)
	var flames := MeshInstance3D.new()
	flames.name = "Flames"
	flames.mesh = builder.build(Materials.flame())
	flames.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flames.set_script(load("res://scripts/world/fire_flicker.gd"))
	root.add_child(flames)

	var light := OmniLight3D.new()
	light.name = "FireLight"
	light.position = Vector3(0, 1.2, 0)
	light.light_color = Color(1.0, 0.6, 0.3)
	light.omni_range = 11.0
	light.light_energy = 1.6
	light.shadow_enabled = false
	light.set_meta("base_energy", 1.6)
	light.set_meta("always_on", true)
	light.add_to_group("night_lights")
	root.add_child(light)


## Canvas tents around a camp fire, for travellers who have no home yet.
static func _build_camp(kit: Kit, root: Node3D) -> void:
	var m := kit.mesh
	var canvas: Array[Color] = [Color(0.82, 0.76, 0.62), Color(0.7, 0.58, 0.42), Color(0.58, 0.64, 0.56), Color(0.76, 0.66, 0.5)]
	for i in VillageLayout.CAMP_TENTS:
		var a := TAU * float(i) / VillageLayout.CAMP_TENTS
		var outward := Vector3(cos(a), 0, sin(a))
		var centre := outward * 3.7
		var yaw := atan2(outward.x, outward.z)
		var basis := Basis(Vector3.UP, yaw)
		# The prism's ridge runs along its local X: point it at the fire so
		# the open end (and its door mat) faces inward.
		m.add_prism(Transform3D(Basis(Vector3.UP, yaw + PI * 0.5), centre), 2.1, 1.7, 1.35, canvas[i % canvas.size()])
		m.add_box(Transform3D(basis, centre + basis * Vector3(0, 0.02, -1.3)), Vector3(0.9, 0.04, 0.45), Color(0.4, 0.3, 0.2))
		m.add_cylinder_at(centre + basis * Vector3(0, 0, -1.05), 0.04, 0.04, 1.45, 4, WOOD_DARK)
	for i in 9:
		var a := TAU * float(i) / 9.0
		m.add_blob_at(Vector3(cos(a), 0.08, sin(a)) * 0.75, Vector3(0.22, 0.14, 0.2), STONE)
	for i in 4:
		m.add_box_at(Vector3(0, 0.1, 0), Vector3(0.9, 0.12, 0.12), WOOD_DARK, float(i) * PI * 0.25)
	for i in 3:
		var a := TAU * float(i) / 3.0 + 0.4
		m.add_box_at(Vector3(cos(a), 0.22, sin(a)) * 1.7, Vector3(1.3, 0.3, 0.32), WOOD, a + PI * 0.5)
	_add_fire(root)


static func _build_memory_oak(kit: Kit) -> void:
	var m := kit.mesh
	var bark := Color(0.38, 0.28, 0.2)
	m.add_cylinder_at(Vector3(0, -0.2, 0), 0.85, 0.5, 3.6, 8, bark)
	for i in 5:
		var a := TAU * i / 5.0 + 0.3
		m.add_box(Transform3D(Basis(Vector3.UP, -a) * Basis(Vector3.BACK, 0.5), Vector3(cos(a) * 0.75, 0.15, sin(a) * 0.75)), Vector3(0.9, 0.25, 0.3), bark.darkened(0.1))
	for i in 4:
		var a := TAU * i / 4.0
		var dir := Vector3(cos(a), 0, sin(a))
		var tilt := Basis(dir.cross(Vector3.UP).normalized(), -0.8)
		m.add_cylinder(Transform3D(tilt, Vector3(0, 3.0, 0)), 0.3, 0.16, 2.2, 6, bark)
	var greens: Array[Color] = [Color(0.27, 0.48, 0.22), Color(0.33, 0.55, 0.25), Color(0.4, 0.6, 0.28)]
	m.add_blob_at(Vector3(0, 5.6, 0), Vector3(3.4, 2.4, 3.4), greens[0], 9, 5, 0.14)
	for i in 6:
		var a := TAU * i / 6.0
		m.add_blob_at(Vector3(cos(a) * 2.6, 4.7 + (i % 2) * 0.7, sin(a) * 2.6), Vector3(1.9, 1.5, 1.9), greens[i % 3], 7, 4, 0.15)
	# Ring of memorial pebbles around the roots.
	for i in 14:
		var a := TAU * i / 14.0
		m.add_blob_at(Vector3(cos(a) * 1.7, 0.1, sin(a) * 1.7), Vector3(0.18, 0.12, 0.18), STONE.lightened(0.1 * (i % 2)), 5, 3)
	kit.cylinder_collider(Vector3(0, -0.2, 0), 0.85, 3.6)


static func _build_construction_site(kit: Kit) -> void:
	var m := kit.mesh
	var w := 5.0
	var d := 4.0
	m.add_box_at(Vector3(0, -0.12, 0), Vector3(w + 0.3, 0.5, d + 0.3), STONE)
	m.add_box_at(Vector3(0, 0.15, 0), Vector3(w - 0.2, 0.06, d - 0.2), WOOD_LIGHT.darkened(0.15))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			m.add_box_at(Vector3(sx * w * 0.5, 1.75, sz * d * 0.5), Vector3(0.22, 3.0, 0.22), WOOD_LIGHT)
			kit.box_collider(Vector3(sx * w * 0.5, 1.6, sz * d * 0.5), Vector3(0.3, 3.0, 0.3))
	m.add_box_at(Vector3(0, 3.2, -d * 0.5), Vector3(w + 0.2, 0.2, 0.22), WOOD_LIGHT)
	m.add_box_at(Vector3(-w * 0.5, 3.2, 0), Vector3(0.22, 0.2, d + 0.2), WOOD_LIGHT)
	# Half-finished plank walls.
	for i in 4:
		m.add_box_at(Vector3(0, 0.5 + i * 0.26, -d * 0.5), Vector3(w, 0.22, 0.08), WOOD_LIGHT.darkened(0.05 * (i % 2)))
		m.add_box_at(Vector3(-w * 0.5, 0.5 + i * 0.26, 0.4), Vector3(0.08, 0.22, d - 0.8), WOOD_LIGHT.darkened(0.05 * (i % 2)))
	kit.box_collider(Vector3(0, 0.9, -d * 0.5), Vector3(w, 1.2, 0.2))
	kit.box_collider(Vector3(-w * 0.5, 0.9, 0.4), Vector3(0.2, 1.2, d - 0.8))
	# Diagonal brace and a ladder.
	m.add_box(Transform3D(Basis(Vector3.RIGHT, 0.85), Vector3(w * 0.5, 1.6, 0)), Vector3(0.12, 3.6, 0.12), WOOD)
	# Plank pile and stones waiting to be used.
	for i in 5:
		m.add_box_at(Vector3(w * 0.5 + 1.4, 0.1 + i * 0.13, -0.6), Vector3(0.6, 0.11, 2.6), WOOD_LIGHT.darkened(0.03 * i), 0.05 * i)
	kit.box_collider(Vector3(w * 0.5 + 1.4, 0.4, -0.6), Vector3(0.8, 0.8, 2.6))
	for i in 7:
		m.add_blob_at(Vector3(-w * 0.5 - 1.2 + (i % 3) * 0.4, 0.2 + (i / 3) * 0.25, -1.0 + (i % 2) * 0.4), Vector3(0.28, 0.22, 0.26), STONE, 5, 3)
	# Sawhorse.
	m.add_box_at(Vector3(1.0, 0.7, d * 0.5 + 1.6), Vector3(1.4, 0.12, 0.12), WOOD)
	for sx in [0.45, 1.55]:
		m.add_box(Transform3D(Basis(Vector3.RIGHT, 0.35), Vector3(sx, 0.35, d * 0.5 + 1.75)), Vector3(0.08, 0.75, 0.08), WOOD_DARK)
		m.add_box(Transform3D(Basis(Vector3.RIGHT, -0.35), Vector3(sx, 0.35, d * 0.5 + 1.45)), Vector3(0.08, 0.75, 0.08), WOOD_DARK)


# --- Small reusable props -------------------------------------------------------------

## Lantern post with a warm light that switches on at dusk.
static func create_lantern(position: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = "Lantern"
	root.position = position
	var kit := Kit.new(int(position.x * 13.0 + position.z * 7.0))
	kit.mesh.add_box_at(Vector3(0, 0.0, 0), Vector3(0.4, 0.6, 0.4), STONE_DARK)
	kit.mesh.add_box_at(Vector3(0, 1.2, 0), Vector3(0.14, 2.2, 0.14), WOOD_DARK)
	kit.mesh.add_box_at(Vector3(0.25, 2.2, 0), Vector3(0.55, 0.08, 0.08), WOOD_DARK)
	kit.mesh.add_box_at(Vector3(0.5, 1.98, 0), Vector3(0.3, 0.06, 0.3), WOOD_DARK)
	kit.mesh.add_cylinder_at(Vector3(0.5, 2.12, 0), 0.22, 0.0, 0.18, 4, WOOD_DARK)
	kit.glow.add_box_at(Vector3(0.5, 1.8, 0), Vector3(0.24, 0.32, 0.24), Color.WHITE)
	kit.box_collider(Vector3(0, 1.1, 0), Vector3(0.3, 2.2, 0.3))
	kit.finish(root)
	var light := OmniLight3D.new()
	light.position = Vector3(0.5, 1.7, 0)
	light.light_color = Color(1.0, 0.75, 0.45)
	light.omni_range = 7.0
	light.light_energy = 0.0
	light.shadow_enabled = false
	light.set_meta("base_energy", 1.1)
	light.add_to_group("night_lights")
	root.add_child(light)
	return root
