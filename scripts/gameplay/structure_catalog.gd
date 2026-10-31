class_name StructureCatalog
extends RefCounted
## Everything the player can build: cost, how much work it takes, its
## footprint, and how it looks while under construction and when finished.

const STRUCTURES := {
	&"farm_plot": {"name": "Farm plot", "cost": {&"wood": 6}, "work": 2, "footprint": Vector2(4.0, 3.0),
		"description": "Plant seeds and harvest food."},
	&"house": {"name": "House", "cost": {&"wood": 20, &"stone": 10}, "work": 6, "footprint": Vector2(6.2, 4.8),
		"description": "A home of your own. Sleep here at night."},
	&"cottage": {"name": "Cottage", "cost": {&"wood": 18, &"stone": 8}, "work": 6, "footprint": Vector2(6.2, 4.8),
		"description": "A home for up to four newcomers. Travellers move in from the camp."},
	&"well": {"name": "Well", "cost": {&"stone": 10, &"wood": 2}, "work": 3, "footprint": Vector2(2.2, 2.2),
		"description": "Draw water to help crops grow faster."},
	&"bench": {"name": "Bench", "cost": {&"wood": 4}, "work": 1, "footprint": Vector2(2.0, 0.9),
		"description": "A place to sit and watch the village."},
	&"lantern": {"name": "Lantern", "cost": {&"wood": 3, &"stone": 2}, "work": 1, "footprint": Vector2(0.9, 0.9),
		"description": "Lights the way at night."},
}
const ORDER: Array[StringName] = [&"farm_plot", &"house", &"cottage", &"well", &"bench", &"lantern"]


static func info(type: StringName) -> Dictionary:
	return STRUCTURES.get(type, {})


static func radius(type: StringName) -> float:
	var footprint: Vector2 = info(type).get("footprint", Vector2.ONE)
	return footprint.length() * 0.5


## The finished structure, built at the origin facing +Z.
static func create_finished(type: StringName) -> Node3D:
	match type:
		&"house":
			var root := BuildingFactory.create({"id": "player_house", "type": "house", "position": Vector3.ZERO,
				"yaw": 0.0, "footprint": Vector2(6.2, 4.8), "owner": "player"})
			root.position = Vector3.ZERO
			root.rotation = Vector3.ZERO
			return root
		&"cottage":
			var cottage := BuildingFactory.create({"id": "cottage", "type": "house", "position": Vector3.ZERO,
				"yaw": 0.0, "footprint": Vector2(6.2, 4.8), "owner": "cottage"})
			cottage.position = Vector3.ZERO
			cottage.rotation = Vector3.ZERO
			return cottage
		&"lantern":
			var lantern := BuildingFactory.create_lantern(Vector3.ZERO)
			return lantern
	var node := Node3D.new()
	var kit := BuildingFactory.Kit.new(hash(String(type)))
	var m := kit.mesh
	match type:
		&"farm_plot":
			for side: float in [-1.0, 1.0]:
				m.add_box_at(Vector3(side * 1.95, 0.1, 0), Vector3(0.12, 0.35, 3.0), BuildingFactory.WOOD)
				m.add_box_at(Vector3(0, 0.1, side * 1.45), Vector3(4.0, 0.35, 0.12), BuildingFactory.WOOD)
			for row in 3:
				m.add_box_at(Vector3(0, 0.12, -0.9 + row * 0.9), Vector3(3.6, 0.2, 0.55), BuildingFactory.SOIL)
		&"well":
			m.add_cylinder_at(Vector3(0, -0.2, 0), 0.95, 0.95, 1.05, 12, BuildingFactory.STONE)
			m.add_cylinder_at(Vector3(0, 0.84, 0), 0.75, 0.75, 0.02, 12, Color(0.2, 0.3, 0.38))
			for side: float in [-1.0, 1.0]:
				m.add_box_at(Vector3(side * 0.85, 1.5, 0), Vector3(0.14, 1.6, 0.14), BuildingFactory.WOOD_DARK)
			m.add_box_at(Vector3(0, 2.25, 0), Vector3(1.9, 0.1, 0.1), BuildingFactory.WOOD)
			m.add_prism(Transform3D(Basis.IDENTITY, Vector3(0, 2.3, 0)), 2.2, 1.6, 0.6, Color(0.5, 0.28, 0.2))
			m.add_cylinder_at(Vector3(0.3, 1.55, 0), 0.16, 0.18, 0.28, 8, BuildingFactory.WOOD_LIGHT)
			kit.cylinder_collider(Vector3(0, -0.2, 0), 1.0, 1.2)
		&"bench":
			m.add_box_at(Vector3(0, 0.48, 0), Vector3(1.9, 0.1, 0.5), BuildingFactory.WOOD_LIGHT)
			m.add_box_at(Vector3(0, 0.85, -0.22), Vector3(1.9, 0.3, 0.07), BuildingFactory.WOOD_LIGHT)
			for side: float in [-0.8, 0.8]:
				m.add_box_at(Vector3(side, 0.22, 0), Vector3(0.1, 0.5, 0.45), BuildingFactory.WOOD)
			kit.box_collider(Vector3(0, 0.4, 0), Vector3(1.9, 0.8, 0.5))
	kit.finish(node)
	return node


## A foundation and frame sized to the footprint; more of it appears as work
## progresses (0..1).
static func create_construction(type: StringName, progress: float) -> Node3D:
	var node := Node3D.new()
	var footprint: Vector2 = info(type).get("footprint", Vector2.ONE)
	var kit := BuildingFactory.Kit.new(hash(String(type)) + 7)
	var m := kit.mesh
	var hw := footprint.x * 0.5
	var hd := footprint.y * 0.5
	var stone := BuildingFactory.STONE.darkened(0.05)
	for side: float in [-1.0, 1.0]:
		m.add_box_at(Vector3(0, 0.05, side * hd), Vector3(footprint.x, 0.2, 0.25), stone)
		m.add_box_at(Vector3(side * hw, 0.05, 0), Vector3(0.25, 0.2, footprint.y), stone)
	var height := 0.4 + 2.2 * progress if type == &"house" else 0.3 + 0.8 * progress
	if progress > 0.0:
		for sx: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				m.add_box_at(Vector3(sx * (hw - 0.1), height * 0.5, sz * (hd - 0.1)), Vector3(0.16, height, 0.16), BuildingFactory.WOOD_LIGHT)
	if progress > 0.4:
		m.add_box_at(Vector3(0, height, -hd + 0.1), Vector3(footprint.x, 0.14, 0.14), BuildingFactory.WOOD_LIGHT)
		m.add_box_at(Vector3(0, height, hd - 0.1), Vector3(footprint.x, 0.14, 0.14), BuildingFactory.WOOD_LIGHT)
	# Stack of materials waiting to be used.
	for i in 3:
		m.add_box_at(Vector3(hw + 0.6, 0.08 + i * 0.12, 0.2), Vector3(0.5, 0.1, 1.4), BuildingFactory.WOOD_LIGHT.darkened(0.04 * i))
	kit.finish(node)
	return node
