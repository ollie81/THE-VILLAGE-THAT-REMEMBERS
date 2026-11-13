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
		"description": "Lights the way at night.", "beauty": 1.0},
	&"chicken_coop": {"name": "Chicken coop", "cost": {&"wood": 8}, "work": 2, "footprint": Vector2(2.6, 2.0),
		"description": "Hens lay eggs: 2 food every morning."},
	&"fruit_tree": {"name": "Fruit tree", "cost": {&"wood": 1, &"herbs": 1}, "work": 1, "footprint": Vector2(1.6, 1.6),
		"description": "A sapling. In two days it bears fruit to pick every day.", "beauty": 1.0},
	&"market_stall": {"name": "Market stall", "cost": {&"wood": 10, &"stone": 2}, "work": 3, "footprint": Vector2(3.0, 2.0),
		"description": "A place to trade. A market makes the whole village livelier.", "beauty": 3.0},
	&"flower_bed": {"name": "Flower bed", "cost": {&"herbs": 2}, "work": 1, "footprint": Vector2(1.8, 1.0),
		"description": "Flowers make everyone a little happier.", "beauty": 1.5},
	&"fence": {"name": "Fence", "cost": {&"wood": 2}, "work": 1, "footprint": Vector2(3.0, 0.3),
		"description": "A length of fence. Place several to make a yard.", "beauty": 0.3},
	&"stone_path": {"name": "Stone path", "cost": {&"stone": 2}, "work": 1, "footprint": Vector2(2.0, 2.0),
		"description": "Paving stones. Lay them in a row to make a path.", "beauty": 0.4},
	&"statue": {"name": "Founders' stone", "cost": {&"stone": 12}, "work": 4, "footprint": Vector2(1.4, 1.4),
		"description": "A carved stone honouring the five founders. Everyone is proud of it.", "beauty": 5.0},
}
## Shown in the Build menu, by tab.
const CATEGORIES := {
	"Homes": [&"house", &"cottage"],
	"Food": [&"farm_plot", &"chicken_coop", &"fruit_tree", &"well"],
	"Village": [&"bench", &"lantern", &"flower_bed", &"fence", &"stone_path", &"market_stall", &"statue"],
}
const ORDER: Array[StringName] = [&"farm_plot", &"house", &"cottage", &"well", &"bench", &"lantern",
	&"chicken_coop", &"fruit_tree", &"market_stall", &"flower_bed", &"fence", &"stone_path", &"statue"]
## Homes rise wall by wall; everything else appears as a frame.
const HOMES: Array[StringName] = [&"house", &"cottage"]


## How much a finished structure brightens the village (see GameState.beauty).
static func beauty(type: StringName) -> float:
	return float(info(type).get("beauty", 0.0))


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
		&"chicken_coop":
			m.add_box_at(Vector3(0, 0.55, 0), Vector3(2.2, 0.9, 1.5), BuildingFactory.WOOD_LIGHT)
			for sx: float in [-1.0, 1.0]:
				for sz: float in [-1.0, 1.0]:
					m.add_box_at(Vector3(sx * 1.0, 0.25, sz * 0.65), Vector3(0.12, 0.5, 0.12), BuildingFactory.WOOD_DARK)
			m.add_prism(Transform3D(Basis.IDENTITY, Vector3(0, 1.0, 0)), 2.5, 1.8, 0.6, Color(0.62, 0.3, 0.2))
			m.add_box_at(Vector3(0, 0.45, 0.76), Vector3(0.4, 0.45, 0.04), Color(0.2, 0.14, 0.1))
			m.add_box_at(Vector3(0, 0.2, 1.05), Vector3(0.35, 0.04, 0.7), BuildingFactory.WOOD, 0.0)
			# A few hens pecking about.
			for i in 3:
				var at := Vector3(-0.8 + i * 0.7, 0.13, 1.35 + (i % 2) * 0.25)
				m.add_blob_at(at, Vector3(0.14, 0.12, 0.18), Color(0.95, 0.92, 0.85) if i != 1 else Color(0.6, 0.38, 0.22), 6, 4, 0.0)
				m.add_blob_at(at + Vector3(0, 0.1, 0.12), Vector3(0.06, 0.07, 0.06), Color(0.95, 0.92, 0.85) if i != 1 else Color(0.6, 0.38, 0.22), 5, 3, 0.0)
				m.add_box_at(at + Vector3(0, 0.17, 0.13), Vector3(0.02, 0.05, 0.05), Color(0.85, 0.15, 0.12))
			kit.box_collider(Vector3(0, 0.6, 0), Vector3(2.3, 1.2, 1.6))
		&"fruit_tree":
			pass  # grows: see create_fruit_tree()
		&"market_stall":
			for sx: float in [-1.0, 1.0]:
				for sz: float in [-1.0, 1.0]:
					m.add_box_at(Vector3(sx * 1.35, 1.0, sz * 0.85), Vector3(0.12, 2.0, 0.12), BuildingFactory.WOOD_DARK)
			m.add_box_at(Vector3(0, 0.85, 0.55), Vector3(2.8, 0.1, 0.8), BuildingFactory.WOOD_LIGHT)
			m.add_box_at(Vector3(0, 0.45, 0.55), Vector3(2.6, 0.8, 0.06), BuildingFactory.WOOD)
			for i in 6:
				var stripe := Color(0.82, 0.24, 0.2) if i % 2 == 0 else Color(0.95, 0.9, 0.8)
				m.add_box_at(Vector3(-1.25 + i * 0.5, 2.1, 0.0), Vector3(0.5, 0.06, 2.0), stripe)
			# Goods for sale.
			var goods: Array[Color] = [Color(0.85, 0.3, 0.2), Color(0.95, 0.75, 0.2), Color(0.4, 0.62, 0.25), Color(0.6, 0.4, 0.75)]
			for i in 8:
				m.add_blob_at(Vector3(-1.1 + i * 0.32, 0.97, 0.45 + (i % 2) * 0.2), Vector3(0.12, 0.1, 0.12), goods[i % goods.size()], 6, 4, 0.05)
			kit.box_collider(Vector3(0, 0.5, 0.55), Vector3(2.8, 1.0, 0.8))
		&"flower_bed":
			m.add_box_at(Vector3(0, 0.08, 0), Vector3(1.8, 0.16, 1.0), BuildingFactory.WOOD)
			m.add_box_at(Vector3(0, 0.12, 0), Vector3(1.65, 0.14, 0.85), BuildingFactory.SOIL)
			var petals: Array[Color] = [Color(0.95, 0.4, 0.55), Color(0.98, 0.85, 0.3), Color(0.65, 0.45, 0.9), Color(0.98, 0.6, 0.3), Color(0.95, 0.95, 0.95)]
			for i in 14:
				var at := Vector3(-0.7 + (i % 7) * 0.23, 0.2, -0.22 + (i / 7) * 0.42 + (i % 2) * 0.05)
				m.add_box_at(at + Vector3(0, 0.12, 0), Vector3(0.02, 0.25, 0.02), BuildingFactory.LEAF)
				m.add_blob_at(at + Vector3(0, 0.28, 0), Vector3(0.08, 0.06, 0.08), petals[i % petals.size()], 5, 3, 0.0)
		&"fence":
			for x: float in [-1.4, 0.0, 1.4]:
				m.add_box_at(Vector3(x, 0.5, 0), Vector3(0.12, 1.0, 0.12), BuildingFactory.WOOD_DARK)
			for y: float in [0.4, 0.8]:
				m.add_box_at(Vector3(0, y, 0), Vector3(3.0, 0.1, 0.06), BuildingFactory.WOOD)
			kit.box_collider(Vector3(0, 0.5, 0), Vector3(3.0, 1.0, 0.2))
		&"stone_path":
			var rng := RandomNumberGenerator.new()
			rng.seed = 77
			for i in 7:
				var at := Vector3(rng.randf_range(-0.7, 0.7), 0.03, rng.randf_range(-0.7, 0.7))
				m.add_box_at(at, Vector3(rng.randf_range(0.45, 0.65), 0.08, rng.randf_range(0.4, 0.55)), BuildingFactory.STONE.lightened(rng.randf_range(-0.05, 0.12)), rng.randf() * PI)
		&"statue":
			m.add_box_at(Vector3(0, 0.15, 0), Vector3(1.3, 0.3, 1.3), BuildingFactory.STONE_DARK)
			m.add_box_at(Vector3(0, 1.25, 0), Vector3(0.7, 1.9, 0.45), BuildingFactory.STONE)
			m.add_box_at(Vector3(0, 2.3, 0), Vector3(0.85, 0.2, 0.55), BuildingFactory.STONE_DARK)
			# Five carved marks, one for each founder.
			for i in 5:
				m.add_box_at(Vector3(-0.24 + i * 0.12, 1.35, 0.235), Vector3(0.05, 0.6, 0.02), Color(0.3, 0.29, 0.27))
			kit.box_collider(Vector3(0, 1.1, 0), Vector3(0.8, 2.2, 0.6))
		&"bench":
			m.add_box_at(Vector3(0, 0.48, 0), Vector3(1.9, 0.1, 0.5), BuildingFactory.WOOD_LIGHT)
			m.add_box_at(Vector3(0, 0.85, -0.22), Vector3(1.9, 0.3, 0.07), BuildingFactory.WOOD_LIGHT)
			for side: float in [-0.8, 0.8]:
				m.add_box_at(Vector3(side, 0.22, 0), Vector3(0.1, 0.5, 0.45), BuildingFactory.WOOD)
			kit.box_collider(Vector3(0, 0.4, 0), Vector3(1.9, 0.8, 0.5))
	kit.finish(node)
	return node


## A fruit tree at `growth` (0 sapling .. 1 grown), with fruit when ripe.
static func create_fruit_tree(growth: float, has_fruit: bool) -> Node3D:
	var node := Node3D.new()
	var kit := BuildingFactory.Kit.new(4242)
	var m := kit.mesh
	var size := lerpf(0.35, 1.0, clampf(growth, 0.0, 1.0))
	m.add_cylinder_at(Vector3.ZERO, 0.12 * size, 0.08 * size, 1.6 * size, 6, BuildingFactory.WOOD)
	m.add_blob_at(Vector3(0, 1.9 * size, 0), Vector3(0.9, 0.75, 0.9) * size, BuildingFactory.LEAF.lightened(0.08), 8, 5, 0.15)
	m.add_blob_at(Vector3(0.35, 1.6 * size, 0.2), Vector3(0.55, 0.45, 0.55) * size, BuildingFactory.LEAF, 7, 4, 0.15)
	if has_fruit:
		for i in 9:
			var a := TAU * i / 9.0
			m.add_blob_at(Vector3(cos(a) * 0.7, 1.75 + 0.25 * sin(a * 2.0), sin(a) * 0.7) * Vector3(size, size, size),
				Vector3(0.09, 0.09, 0.09), Color(0.88, 0.2, 0.15) if i % 3 != 0 else Color(0.95, 0.7, 0.15), 5, 3, 0.0)
	if growth >= 1.0:
		kit.cylinder_collider(Vector3.ZERO, 0.2, 1.6)
	kit.finish(node)
	return node


## A foundation and frame sized to the footprint; more of it appears as work
## progresses (0..1).
## What each tap of Build adds to a home (6 stages), shown on the site.
const HOME_STAGES: Array[String] = ["corner posts", "lower walls", "upper walls", "roof beams", "thatched roof", "door and windows"]


## The name of construction stage `step` (1-based) of `type`.
static func stage_name(type: StringName, step: int) -> String:
	if type == &"house" or type == &"cottage":
		return HOME_STAGES[clampi(step - 1, 0, HOME_STAGES.size() - 1)]
	return "stage %d" % step


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
	if type in HOMES:
		_home_stages(m, footprint, progress)
		for i in 3:
			m.add_box_at(Vector3(hw + 0.6, 0.08 + i * 0.12, 0.2), Vector3(0.5, 0.1, 1.4), BuildingFactory.WOOD_LIGHT.darkened(0.04 * i))
		kit.finish(node)
		return node
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


## A home going up: posts, then walls rising plank by plank, then the roof
## beams, then the thatch.
static func _home_stages(m: MeshBuilder, footprint: Vector2, progress: float) -> void:
	var hw := footprint.x * 0.5 - 0.1
	var hd := footprint.y * 0.5 - 0.1
	var wall_height := 2.4
	var wall := BuildingFactory.WOOD_LIGHT
	var posts := smoothstep(0.0, 0.2, progress)
	if posts > 0.0:
		for sx: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				m.add_box_at(Vector3(sx * hw, wall_height * posts * 0.5, sz * hd), Vector3(0.2, wall_height * posts, 0.2), BuildingFactory.WOOD_DARK)
	# Walls rise in courses of planks.
	var walls := clampf((progress - 0.15) / 0.5, 0.0, 1.0)
	var courses := int(walls * 8.0)
	for c in courses:
		var y := 0.2 + c * 0.28
		var shade := wall.darkened(0.05 * (c % 2))
		m.add_box_at(Vector3(0, y, -hd), Vector3(hw * 2.0, 0.26, 0.12), shade)
		m.add_box_at(Vector3(-hw, y, 0), Vector3(0.12, 0.26, hd * 2.0), shade)
		m.add_box_at(Vector3(hw, y, 0), Vector3(0.12, 0.26, hd * 2.0), shade)
		# The front leaves a gap for the door.
		m.add_box_at(Vector3(-hw * 0.6, y, hd), Vector3(hw * 0.8, 0.26, 0.12), shade)
		if y > 1.9:
			m.add_box_at(Vector3(0, y, hd), Vector3(hw * 2.0, 0.26, 0.12), shade)
		else:
			m.add_box_at(Vector3(hw * 0.6, y, hd), Vector3(hw * 0.8, 0.26, 0.12), shade)
	# Roof beams, then thatch.
	if progress > 0.65:
		var top := wall_height + 1.3
		for x: float in [-hw, 0.0, hw]:
			for side: float in [-1.0, 1.0]:
				var from := Vector3(x, wall_height, side * (hd + 0.2))
				var to := Vector3(x, top, 0)
				var mid := (from + to) * 0.5
				var length := from.distance_to(to)
				var tilt := atan2(to.y - from.y, absf(to.z - from.z)) * -side
				m.add_box(Transform3D(Basis(Vector3.RIGHT, tilt), mid), Vector3(0.12, 0.12, length), BuildingFactory.WOOD_DARK)
		m.add_box_at(Vector3(0, top, 0), Vector3(hw * 2.0 + 0.3, 0.14, 0.14), BuildingFactory.WOOD_DARK)
	var thatch := clampf((progress - 0.82) / 0.18, 0.0, 1.0)
	if thatch > 0.0:
		m.add_prism(Transform3D(Basis.IDENTITY, Vector3(-(hw + 0.3) + (hw + 0.3) * thatch, wall_height, 0)),
			(hw * 2.0 + 0.6) * thatch, hd * 2.0 + 0.6, 1.35, BuildingFactory.THATCH)
