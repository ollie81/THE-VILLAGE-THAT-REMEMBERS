class_name WorldExpansion
extends Node3D
## The wider world around the original village: a second street of walk-in
## cottages to the south (by the pond), the farmland to the north with its
## windmill and fields, the forest lake with a dock, old ruins hiding a chest
## in the western forest, a watchtower at the edge of the eastern wilds, and
## signposts where the roads fork. Built from the Medieval Village MegaKit
## (CC0) where it can be.
##
## plan() runs before trees, rocks and resources are placed, so they keep off
## everything here.

static var instance: WorldExpansion

const KIT := "res://assets/quaternius/village/"
const VIEW_DISTANCE := 160.0
## Cottages on the south street (their doors face the road).
const STREET_COTTAGES := [Vector3(-8.0, 0.0, 121.0), Vector3(14.0, 0.0, 121.0), Vector3(-58.0, 0.0, 118.0)]
const WINDMILL := Vector3(-12.0, 0.0, -138.0)
const WATCHTOWER := Vector3(124.0, 0.0, -28.0)
const RUINS := Vector3(-150.0, 0.0, -62.0)
const RUINS_REWARD := {&"stone": 10, &"wood": 6, &"herbs": 3}
const FIELDS := Rect2(-78.0, -162.0, 46.0, 40.0)
const SIGNS := {
	"west_road": ["Farmland", "Forest lake", "Village"],
	"south_road": ["South street", "Pond", "Village"],
	"wilds_road": ["Watchtower", "The wilds", "Village"],
}

## Things here, for placement: {center, radius}.
static var _reserved: Array[Dictionary] = []

var _scenes: Dictionary = {}
var _body: StaticBody3D
var _sails: Node3D


## Reserves every plot of the wider world (call before trees are placed).
static func plan() -> void:
	_reserved.clear()
	for at in STREET_COTTAGES:
		KitCottage.add_plot(at, PI)
	_reserved.append({"center": WINDMILL, "radius": 6.0})
	_reserved.append({"center": WATCHTOWER, "radius": 5.0})
	_reserved.append({"center": RUINS, "radius": 10.0})
	_reserved.append({"center": Vector3(FIELDS.get_center().x, 0.0, FIELDS.get_center().y), "radius": 26.0})
	_reserved.append({"center": dock_position(), "radius": 4.0})
	var nodes := VillageLayout.get_nav_nodes()
	for sign_at in SIGNS:
		_reserved.append({"center": nodes[sign_at] + Vector3(2.2, 0, 2.2), "radius": 1.0})


static func reserves(x: float, z: float, margin: float = 0.0) -> bool:
	for r: Dictionary in _reserved:
		var c: Vector3 = r["center"]
		if Vector2(x - c.x, z - c.z).length() < float(r["radius"]) + margin:
			return true
	return false


## Where the dock starts, on the lake's eastern shore.
static func dock_position() -> Vector3:
	return VillageLayout.LAKE_CENTER + Vector3(VillageLayout.LAKE_RADIUS + 1.0, 0, 4.0)


func _ready() -> void:
	name = "WorldExpansion"
	instance = self
	_body = StaticBody3D.new()
	_body.name = "ExpansionBody"
	_body.collision_layer = 1
	_body.collision_mask = 0
	add_child(_body)
	for i in range(1, KitCottage.plots.size()):
		var cottage := KitCottage.new(KitCottage.plots[i])
		cottage.name = "StreetCottage%d" % i
		add_child(cottage)
		_limit_view(cottage, 140.0)
	_build_windmill()
	_build_fields()
	_build_watchtower()
	_build_ruins()
	_build_dock()
	_build_signs()


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _process(delta: float) -> void:
	if _sails:
		_sails.rotate_object_local(Vector3.FORWARD, delta * 0.5)


# --- Helpers ----------------------------------------------------------------------------

func _ground(at: Vector3) -> Vector3:
	return Vector3(at.x, TerrainGenerator.get_height(at.x, at.z), at.z)


func _kit(parent: Node3D, piece: String, at: Vector3, turn: float = 0.0) -> Node3D:
	if not _scenes.has(piece):
		_scenes[piece] = load(KIT + piece + ".gltf")
	var packed: PackedScene = _scenes[piece]
	if packed == null:
		return null
	var node := packed.instantiate() as Node3D
	for child in node.find_children("*", "", true, false):
		child.name = "Kit" + String(child.name)
	node.name = "Kit" + String(node.name)
	node.position = at
	node.rotation.y = turn
	parent.add_child(node)
	return node


## A solid box at `center` (in `space`'s frame when given, else the world's).
func _box(center: Vector3, size: Vector3, turn: float = 0.0, space: Node3D = null) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	var local := Transform3D(Basis(Vector3.UP, turn), center)
	shape.transform = space.transform * local if space else local
	_body.add_child(shape)


func _material(texture_base: String, tint: Color = Color.WHITE, scale_uv: float = 0.5) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(KIT + texture_base + "_BaseColor.png")
	m.albedo_color = tint
	if ResourceLoader.exists(KIT + texture_base + "_Normal.png"):
		m.normal_enabled = true
		m.normal_texture = load(KIT + texture_base + "_Normal.png")
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * scale_uv
	return m


func _mesh(parent: Node3D, mesh: Mesh, at: Vector3, material: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = at
	mi.rotation = rot
	parent.add_child(mi)
	return mi


func _limit_view(node: Node, distance: float) -> void:
	for g in node.find_children("*", "GeometryInstance3D", true, false):
		var geometry := g as GeometryInstance3D
		if geometry.visibility_range_end == 0.0:
			geometry.visibility_range_end = distance
			geometry.visibility_range_end_margin = 8.0


# --- Landmarks -------------------------------------------------------------------------------

## A stone windmill with turning sails, seen from all over the farmland.
func _build_windmill() -> void:
	var root := Node3D.new()
	root.name = "Windmill"
	root.position = _ground(WINDMILL)
	add_child(root)
	var stone := _material("T_UnevenBrick", Color(0.95, 0.93, 0.88), 0.45)
	var tower := CylinderMesh.new()
	tower.top_radius = 2.6
	tower.bottom_radius = 3.4
	tower.height = 10.0
	tower.radial_segments = 16
	_mesh(root, tower, Vector3(0, 4.6, 0), stone)
	var cap := CylinderMesh.new()
	cap.top_radius = 0.2
	cap.bottom_radius = 3.1
	cap.height = 3.4
	cap.radial_segments = 16
	_mesh(root, cap, Vector3(0, 11.3, 0), _material("T_RoundTiles", Color(0.9, 0.55, 0.42), 0.6))
	_kit(root, "Door_1_Round", Vector3(-0.55, 0.0, 3.25), 0.0)
	_box(Vector3(0, 4.6, 0), Vector3(5.6, 10.0, 5.6), 0.0, root)
	_sails = Node3D.new()
	_sails.name = "Sails"
	_sails.position = Vector3(0, 9.6, 3.0)
	root.add_child(_sails)
	var wood := _material("T_WoodTrim", Color.WHITE, 0.8)
	var hub := CylinderMesh.new()
	hub.top_radius = 0.35
	hub.bottom_radius = 0.35
	hub.height = 0.6
	_mesh(_sails, hub, Vector3.ZERO, wood, Vector3(PI * 0.5, 0, 0))
	for i in 4:
		var arm := Node3D.new()
		arm.rotation.z = i * PI * 0.5
		_sails.add_child(arm)
		var beam := BoxMesh.new()
		beam.size = Vector3(0.25, 6.0, 0.18)
		_mesh(arm, beam, Vector3(0, 3.2, 0), wood)
		var cloth := BoxMesh.new()
		cloth.size = Vector3(1.4, 4.6, 0.05)
		var canvas := StandardMaterial3D.new()
		canvas.albedo_color = Color(0.92, 0.88, 0.78)
		_mesh(arm, cloth, Vector3(0.8, 3.6, 0.05), canvas)


## Fenced fields of crops on the farmland.
func _build_fields() -> void:
	var root := Node3D.new()
	root.name = "Fields"
	add_child(root)
	var m := MeshBuilder.new(77)
	m.color_jitter = 0.0
	var soil := Color(0.36, 0.25, 0.16)
	var crops := [Color(0.42, 0.62, 0.26), Color(0.78, 0.68, 0.3), Color(0.3, 0.5, 0.24)]
	var field_index := 0
	for fx in 2:
		for fz in 2:
			var origin := Vector2(FIELDS.position.x + 2.0 + fx * 23.0, FIELDS.position.y + 2.0 + fz * 20.0)
			var crop: Color = crops[field_index % crops.size()]
			field_index += 1
			for row in 9:
				var z := origin.y + row * 2.0
				for step in 10:
					var x := origin.x + step * 2.0
					var g := TerrainGenerator.get_height(x, z)
					m.add_box_at(Vector3(x, g + 0.05, z), Vector3(2.0, 0.14, 1.1), soil)
					m.add_blob_at(Vector3(x, g + 0.32, z), Vector3(0.38, 0.32, 0.38), crop.lightened(0.04 * (step % 3)), 6, 3, 0.2)
	var fields := MeshInstance3D.new()
	fields.mesh = m.build(Materials.vertex_color())
	root.add_child(fields)
	# A fence round all four fields.
	var r := FIELDS
	var x := r.position.x
	while x < r.end.x:
		for z in [r.position.y, r.end.y]:
			_kit(root, "Prop_WoodenFence_Single", _ground(Vector3(x + 1.0, 0, z)), 0.0)
		x += 2.0
	var z2 := r.position.y
	while z2 < r.end.y:
		for xx in [r.position.x, r.end.x]:
			if absf(z2 - (r.position.y + r.size.y * 0.5)) > 2.0:  # a gate in each side
				_kit(root, "Prop_WoodenFence_Single", _ground(Vector3(xx, 0, z2 + 1.0)), PI * 0.5)
		z2 += 2.0
	_limit_view(root, VIEW_DISTANCE)


## A wooden watchtower with a tiled roof, looking over the eastern wilds.
func _build_watchtower() -> void:
	var root := Node3D.new()
	root.name = "Watchtower"
	root.position = _ground(WATCHTOWER)
	add_child(root)
	var wood := _material("T_WoodTrim", Color.WHITE, 0.8)
	var post := BoxMesh.new()
	post.size = Vector3(0.35, 7.0, 0.35)
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var at := Vector3(corner.x * 1.7, 3.5, corner.y * 1.7)
		_mesh(root, post, at, wood)
		_box(at, post.size, 0.0, root)
	for y in [2.4, 6.0]:
		for xi in 2:
			for zi in 2:
				_kit(root, "Floor_WoodDark", Vector3(-1.0 + xi * 2.0, y, -1.0 + zi * 2.0))
	_kit(root, "Roof_Tower_RoundTiles", Vector3(0, 7.0, 0))
	# A ladder up the front.
	for i in 14:
		var rung := BoxMesh.new()
		rung.size = Vector3(0.8, 0.06, 0.06)
		_mesh(root, rung, Vector3(0, 0.4 + i * 0.42, 2.1), wood)
	var rail := BoxMesh.new()
	rail.size = Vector3(0.08, 6.2, 0.08)
	for side in [-0.42, 0.42]:
		_mesh(root, rail, Vector3(side, 3.1, 2.1), wood)
	_limit_view(root, VIEW_DISTANCE + 40.0)


## Old ruins in the deep forest: broken brick walls, vines, rubble, and a
## chest someone forgot.
func _build_ruins() -> void:
	var root := Node3D.new()
	root.name = "Ruins"
	root.position = _ground(RUINS)
	root.rotation.y = 0.4
	add_child(root)
	var walls := [
		["Wall_UnevenBrick_Straight", Vector3(-3, 0, -4), 0.0], ["Wall_UnevenBrick_Window_Wide_Round", Vector3(-1, 0, -4), 0.0],
		["Wall_UnevenBrick_Straight", Vector3(3, 0, -4), 0.0], ["Wall_UnevenBrick_Straight", Vector3(-4, 0, -3), -PI * 0.5],
		["Wall_UnevenBrick_Window_Wide_Round", Vector3(-4, 0, 1), -PI * 0.5], ["Wall_UnevenBrick_Straight", Vector3(4, 0, -1), PI * 0.5],
		["Wall_UnevenBrick_Door_Round", Vector3(1, 0, 4), PI],
	]
	for w in walls:
		var piece := _kit(root, String(w[0]), w[1], float(w[2]))
		if piece:
			piece.rotation.z = randf_range(-0.04, 0.04)
		var outward := Basis(Vector3.UP, float(w[2])) * Vector3.BACK
		_box(Vector3(w[1]) + outward * -0.11 + Vector3(0, 1.56, 0), Vector3(2.0, 3.12, 0.32), float(w[2]), root)
	for vine in [["Prop_Vine5", Vector3(-3, 0, -3.8)], ["Prop_Vine6", Vector3(-3.8, 0, 1)], ["Prop_Vine9", Vector3(3, 0, -3.8)]]:
		_kit(root, String(vine[0]), vine[1], 0.0)
	var rubble := MeshBuilder.new(5)
	rubble.color_jitter = 0.0
	for i in 18:
		var p := Vector3(randf_range(-4.5, 4.5), 0.12, randf_range(-4.5, 4.5))
		rubble.add_blob_at(p, Vector3(0.3, 0.2, 0.25) * randf_range(0.6, 1.4), Color(0.55, 0.5, 0.45), 6, 3, 0.25)
	var rubble_mesh := MeshInstance3D.new()
	rubble_mesh.mesh = rubble.build(Materials.vertex_color())
	root.add_child(rubble_mesh)
	# The forgotten chest.
	var chest_scene := load("res://assets/quaternius/props/Chest_Wood.gltf") as PackedScene
	if chest_scene:
		var chest := chest_scene.instantiate() as Node3D
		chest.position = Vector3(1.8, 0, -2.6)
		root.add_child(chest)
	var usable := UsableObject.new()
	usable.name = "RuinsChest"
	usable.position = Vector3(1.8, 0, -2.6)
	usable.prompt = func(): return "An old chest in the ruins" if not GameState.get_flag(&"ruins_chest") else "The chest is empty now"
	usable.verb = func(): return "Open" if not GameState.get_flag(&"ruins_chest") else "Look"
	usable.use = func(_actor): open_ruins_chest()
	root.add_child(usable)
	var interactable := Interactable.new()
	interactable.radius = 1.6
	interactable.handler = usable
	interactable.interacted.connect(func(actor): usable.use.call(actor))
	usable.add_child(interactable)
	_limit_view(root, VIEW_DISTANCE)


## The chest in the ruins: supplies and credits, once.
func open_ruins_chest() -> bool:
	if GameState.get_flag(&"ruins_chest"):
		GameManager.notify("Only dust and an old key-shaped mark where something used to be.")
		return false
	GameState.set_flag(&"ruins_chest")
	for resource in RUINS_REWARD:
		GameState.add(resource, int(RUINS_REWARD[resource]))
	VillageCredits.award("chest", "chest_ruins", "finding the chest in the ruins")
	Sounds.play("built", null, -2.0)
	GameManager.notify("Hidden in the ruins: %s!" % GameState.cost_text(RUINS_REWARD))
	return true


## A wooden dock out into the lake, to jump in from.
func _build_dock() -> void:
	var root := Node3D.new()
	root.name = "Dock"
	var start := dock_position()
	root.position = Vector3(start.x, VillageLayout.WATER_LEVEL + 0.55, start.z)
	root.rotation.y = -PI * 0.5  # pointing west, into the lake
	add_child(root)
	var wood := _material("T_WoodTrim", Color(0.9, 0.85, 0.78), 0.8)
	for i in 4:
		_kit(root, "Floor_WoodLight", Vector3(0, 0, 1.0 + i * 2.0))
		_box(Vector3(0, -0.1, 1.0 + i * 2.0), Vector3(2.0, 0.2, 2.0), 0.0, root)
		var post := CylinderMesh.new()
		post.top_radius = 0.12
		post.bottom_radius = 0.12
		post.height = 3.0
		for side in [-0.9, 0.9]:
			_mesh(root, post, Vector3(side, -1.4, 1.0 + i * 2.0), wood)
	# A ramp up from the shore.
	var ground := TerrainGenerator.get_height(start.x, start.z)
	var rise := root.position.y - ground
	if rise > 0.05:
		var ramp := BoxMesh.new()
		ramp.size = Vector3(2.0, 0.15, 2.2)
		var tilt := atan2(rise, 2.2)
		_mesh(root, ramp, Vector3(0, -rise * 0.5, -1.0), wood, Vector3(-tilt, 0, 0))
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(2.0, 0.2, 2.3)
		shape.shape = box
		shape.transform = root.transform * Transform3D(Basis(Vector3.RIGHT, -tilt), Vector3(0, -rise * 0.5, -1.0))
		_body.add_child(shape)
	_limit_view(root, VIEW_DISTANCE)


## Signposts where the roads fork, pointing the way.
func _build_signs() -> void:
	var nodes := VillageLayout.get_nav_nodes()
	var wood := _material("T_WoodTrim", Color.WHITE, 0.8)
	for at in SIGNS:
		var root := Node3D.new()
		root.name = "Sign_" + at
		root.position = _ground(nodes[at] + Vector3(2.2, 0, 2.2))
		add_child(root)
		var post := BoxMesh.new()
		post.size = Vector3(0.14, 2.2, 0.14)
		_mesh(root, post, Vector3(0, 1.1, 0), wood)
		var lines: Array = SIGNS[at]
		for i in lines.size():
			var board := BoxMesh.new()
			board.size = Vector3(1.3, 0.28, 0.06)
			var y := 1.9 - i * 0.36
			var turn := float(i) * 0.9 - 0.9
			_mesh(root, board, Vector3(0, y, 0), wood, Vector3(0, turn, 0))
			var label := Label3D.new()
			label.text = String(lines[i])
			label.font_size = 36
			label.pixel_size = 0.004
			label.modulate = Color(0.15, 0.1, 0.05)
			label.outline_size = 0
			label.position = Vector3(0, y, 0) + Basis(Vector3.UP, turn) * Vector3(0, 0, 0.04)
			label.rotation.y = turn
			root.add_child(label)
		_box(Vector3(0, 1.1, 0) + root.position, Vector3(0.2, 2.2, 0.2))
		_limit_view(root, 60.0)
