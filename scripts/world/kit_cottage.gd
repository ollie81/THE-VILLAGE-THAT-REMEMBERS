class_name KitCottage
extends Node3D
## The visual pilot's cottage: a real, walk-in house built from the
## Medieval Village MegaKit (Quaternius, CC0) and furnished from the Fantasy
## Props MegaKit (CC0). Plaster and timber walls with brick bases, a round-tiled
## roof with brick gables, a chimney, windows with shutters and an opening
## door. Inside, with no loading screen: a living room at the front, a kitchen
## with a hearth and a bedroom at the back, lamps in every room.
##
## The house is 8 m wide and 10 m deep on the kit's 2 m grid; its front door
## faces local +Z, turned toward the meeting circle. While you're inside, the
## roof is hidden so the camera can see you.

static var instance: KitCottage

const KIT := "res://assets/quaternius/village/"
const PROPS := "res://assets/quaternius/props/"
const WIDTH := 8.0
const DEPTH := 10.0
const WALL_HEIGHT := 3.12
## Back rooms are behind a partition at this local z.
const PARTITION_Z := -1.0
const RADIUS := 7.0
const DOOR_X := 1.0

## Where the house stands (computed once from the village layout).
static var spot := Vector3.INF
static var yaw: float = 0.0
static var floor_y: float = 0.0
## Every cottage plot in the world: {spot, yaw, floor_y}. The first is the
## one by the meeting circle (spot/yaw/floor_y above); more stand on the
## south street.
static var plots: Array[Dictionary] = []
static var _all: Array[KitCottage] = []

## This cottage's own plot.
var plot: Dictionary = {}
var _floor: float = 0.0
var _yaw: float = 0.0

var roof: Node3D
var door_leaf: Node3D
var door_open: bool = true
var _door_shape: CollisionShape3D
var _body: StaticBody3D
var _rooms: Dictionary = {}
var _scenes: Dictionary = {}
var _inside: bool = false


## A free, fairly flat spot facing the meeting circle, clear of paths,
## buildings, the market and the river. INF if there's none.
static func find_spot() -> Vector3:
	if spot != Vector3.INF:
		return spot
	for radius in [20.0, 23.0, 26.0, 29.0, 32.0, 35.0]:
		var angle := 0.0
		while angle < TAU:
			var p := Vector3(cos(angle) * radius, 0, sin(angle) * radius)
			angle += 0.12
			if VillageLayout.blocking_reason(p.x, p.z, RADIUS, 0.6) != "":
				continue
			var facing := atan2(-p.x, -p.z)
			var heights := []
			for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1), Vector2.ZERO]:
				var c := p + Basis(Vector3.UP, facing) * Vector3(corner.x * WIDTH * 0.5, 0, corner.y * DEPTH * 0.5)
				heights.append(TerrainGenerator.get_height(c.x, c.z))
			if heights.max() - heights.min() > 1.1:
				continue
			spot = p
			yaw = facing
			floor_y = heights.max() + 0.18
			plots.insert(0, {"spot": spot, "yaw": yaw, "floor_y": floor_y})
			return spot
	return spot


## Reserves another cottage plot at `at`, its door facing `facing`.
static func add_plot(at: Vector3, facing: float) -> Dictionary:
	var top := -INF
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1), Vector2.ZERO]:
		var c := at + Basis(Vector3.UP, facing) * Vector3(corner.x * WIDTH * 0.5, 0, corner.y * DEPTH * 0.5)
		top = maxf(top, TerrainGenerator.get_height(c.x, c.z))
	var new_plot := {"spot": Vector3(at.x, 0, at.z), "yaw": facing, "floor_y": top + 0.18}
	plots.append(new_plot)
	return new_plot


## Forgets every plot (a new world is being built).
static func reset_plots() -> void:
	plots.clear()
	spot = Vector3.INF


## True if (x, z) is on the cottage's plot (plus `margin`). Works before the
## cottage is built, so the forest, grass, market and resources keep off it.
static func reserves(x: float, z: float, margin: float = 0.0) -> bool:
	for p: Dictionary in plots:
		var at: Vector3 = p["spot"]
		var local := Basis(Vector3.UP, -float(p["yaw"])) * Vector3(x - at.x, 0, z - at.z)
		if absf(local.x) < WIDTH * 0.5 + 0.6 + margin and absf(local.z) < DEPTH * 0.5 + 2.4 + margin:
			return true
	return false


## Height of the cottage floor at (x, z), or NAN outside it.
static func floor_at(x: float, z: float) -> float:
	for cottage in _all:
		var h := cottage.floor_here(x, z)
		if not is_nan(h):
			return h
	return NAN


## This cottage's floor height at (x, z), or NAN outside it.
func floor_here(x: float, z: float) -> float:
	if plot.is_empty():
		return NAN
	var at: Vector3 = plot["spot"]
	var local := Basis(Vector3.UP, -_yaw) * Vector3(x - at.x, 0, z - at.z)
	if absf(local.x) < WIDTH * 0.5 - 0.15 and absf(local.z) < DEPTH * 0.5 - 0.15:
		return _floor
	return NAN


## Why `at` is taken by the cottage (for building), or "".
static func blocking_reason(at: Vector3, radius: float) -> String:
	for p: Dictionary in plots:
		var s: Vector3 = p["spot"]
		if Vector2(at.x - s.x, at.z - s.z).length() < radius + RADIUS:
			return "Too close to the cottage"
	return ""


func _init(cottage_plot: Dictionary = {}) -> void:
	plot = cottage_plot


func _ready() -> void:
	if plot.is_empty():
		# The cottage by the meeting circle.
		name = "KitCottage"
		instance = self
		if find_spot() == Vector3.INF:
			push_warning("KitCottage: no free spot for the cottage.")
			return
		plot = plots[0]
	_all.append(self)
	_floor = float(plot["floor_y"])
	_yaw = float(plot["yaw"])
	var at: Vector3 = plot["spot"]
	position = Vector3(at.x, _floor, at.z)
	rotation.y = _yaw
	NatureSpawner.clear_area(global_position, RADIUS + 1.0)
	_body = StaticBody3D.new()
	_body.name = "CottageBody"
	_body.collision_layer = 1
	_body.collision_mask = 0
	add_child(_body)
	_build_foundation()
	_build_walls()
	_build_roof()
	_build_living_room()
	_build_kitchen()
	_build_bedroom()
	_build_lights()


func _exit_tree() -> void:
	if instance == self:
		instance = null
	_all.erase(self)


func _process(_delta: float) -> void:
	var player = GameManager.player
	if player == null or roof == null:
		return
	var p: Vector3 = player.global_position
	var inside := not is_nan(floor_here(p.x, p.z)) and absf(p.y - _floor) < 1.5
	if inside != _inside:
		_inside = inside
		roof.visible = not inside
		for rig in get_tree().root.find_children("*", "CameraRig", true, false):
			rig.overhead = inside


## True while the player is inside.
func is_player_inside() -> bool:
	return _inside


## A point on the path just outside the front door.
func door_outside() -> Vector3:
	return to_global(Vector3(DOOR_X, 0, DEPTH * 0.5 + 1.6))


## Where to stand and look from to see a room (for screenshots and tests).
func room_view(room: String) -> Dictionary:
	var r: Dictionary = _rooms.get(room, {})
	return {"player": to_global(r.get("stand", Vector3.ZERO)) + Vector3(0, 0.1, 0), "yaw": _yaw + float(r.get("look", 0.0)),
		"center": to_global(r.get("center", Vector3.ZERO))}


# --- Building blocks --------------------------------------------------------------------

func _scene(path: String) -> PackedScene:
	if not _scenes.has(path):
		_scenes[path] = load(path)
	return _scenes[path]


## Places kit piece `piece_name` at local `at`, turned by `turn`.
func _piece(parent: Node3D, piece_name: String, at: Vector3, turn: float = 0.0, folder: String = KIT) -> Node3D:
	var packed := _scene(folder + piece_name + ".gltf")
	if packed == null:
		push_error("KitCottage: missing asset %s" % piece_name)
		return null
	var node := packed.instantiate() as Node3D
	# Model names ("Door_1_Round") mustn't look like the game's own nodes.
	for child in node.find_children("*", "", true, false):
		child.name = "Kit" + String(child.name)
	node.name = "Kit" + String(node.name)
	node.position = at
	node.rotation.y = turn
	parent.add_child(node)
	return node


## A furniture piece from the props kit, with a box collider around it
## (unless it's small enough to walk past).
func _prop(parent: Node3D, prop_name: String, at: Vector3, turn: float = 0.0, solid: bool = true) -> Node3D:
	var node := _piece(parent, prop_name, at, turn, PROPS)
	if node and solid:
		var box := _local_bounds(node)
		if box.size.x * box.size.z > 0.06:
			var center := box.get_center()
			_box(Vector3(center.x, box.position.y + box.size.y * 0.5, center.z), Vector3(maxf(box.size.x, 0.2), box.size.y, maxf(box.size.z, 0.2)))
	return node


## The node's meshes' bounds in this cottage's local space.
func _local_bounds(node: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for mesh_instance in node.find_children("*", "MeshInstance3D", true, false):
		var mi := mesh_instance as MeshInstance3D
		var to_local := global_transform.affine_inverse() * mi.global_transform
		var box: AABB = to_local * mi.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result


func _box(center: Vector3, size: Vector3, turn: float = 0.0) -> CollisionShape3D:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = center
	shape.rotation.y = turn
	_body.add_child(shape)
	return shape


func _stone_material() -> StandardMaterial3D:
	var material := Materials.cobblestone().duplicate() as StandardMaterial3D
	material.albedo_color = Color(0.82, 0.8, 0.76)
	material.uv1_scale = Vector3.ONE * 0.6
	return material


# --- Shell ---------------------------------------------------------------------------------

func _build_foundation() -> void:
	# Stone plinth from below the lowest ground up to the floor.
	var plinth := MeshInstance3D.new()
	plinth.name = "Foundation"
	var box := BoxMesh.new()
	var lowest := _floor
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var c := to_global(Vector3(corner.x * WIDTH * 0.5, 0, corner.y * DEPTH * 0.5))
		lowest = minf(lowest, TerrainGenerator.get_height(c.x, c.z))
	var height := _floor - lowest + 0.6
	box.size = Vector3(WIDTH + 0.5, height, DEPTH + 0.5)
	plinth.mesh = box
	plinth.material_override = _stone_material()
	plinth.position = Vector3(0, -height * 0.5 - 0.005, 0)
	add_child(plinth)
	_box(Vector3(0, -0.25, 0), Vector3(WIDTH + 0.5, 0.5, DEPTH + 0.5))
	# Wooden floorboards.
	var floor_root := Node3D.new()
	floor_root.name = "Floor"
	add_child(floor_root)
	for xi in 4:
		for zi in 5:
			_piece(floor_root, "Floor_WoodDark", Vector3(-3.0 + xi * 2.0, 0.01, -4.0 + zi * 2.0))
	# Two stone steps up to the door, with a gentle ramp for walking.
	var step_rise := _floor - TerrainGenerator.get_height(door_outside().x, door_outside().z)
	if step_rise > 0.05:
		for i in 2:
			# The step by the door is level with the floor, the outer one halfway.
			var top := -step_rise * 0.5 * i
			var step := MeshInstance3D.new()
			var step_box := BoxMesh.new()
			step_box.size = Vector3(1.8, top + step_rise + 0.3, 0.45)
			step.mesh = step_box
			step.material_override = _stone_material()
			step.position = Vector3(DOOR_X, top - step_box.size.y * 0.5, DEPTH * 0.5 + 0.45 + i * 0.45)
			add_child(step)
		var ramp_length := 1.4
		var angle := atan2(step_rise, ramp_length)
		var ramp := _box(Vector3(DOOR_X, -step_rise * 0.5 - 0.1, DEPTH * 0.5 + 0.25 + ramp_length * 0.5), Vector3(1.8, 0.2, sqrt(ramp_length * ramp_length + step_rise * step_rise)))
		ramp.rotation = Vector3(angle, 0, 0)


func _wall(parent: Node3D, kind: String, center: Vector3, turn: float, with_extras: bool = true) -> void:
	_piece(parent, kind, center, turn)
	var outward := Basis(Vector3.UP, turn) * Vector3.BACK
	var along := Basis(Vector3.UP, turn) * Vector3.RIGHT
	var middle := center + outward * -0.11 + Vector3(0, WALL_HEIGHT * 0.5, 0)
	if kind.contains("Door"):
		for side in [-1.0, 1.0]:
			_box(middle + along * side * 0.78, Vector3(0.44, WALL_HEIGHT, 0.32), turn)
		_box(middle + Vector3(0, 1.3, 0), Vector3(2.0, 0.5, 0.32), turn)
	else:
		_box(middle, Vector3(2.0, WALL_HEIGHT, 0.32), turn)
	if with_extras and kind.contains("Window"):
		_piece(parent, "Window_Wide_Round1", center, turn)
		_piece(parent, "WindowShutters_Wide_Round_Open", center, turn)


func _build_walls() -> void:
	var walls := Node3D.new()
	walls.name = "Walls"
	add_child(walls)
	var hw := WIDTH * 0.5
	var hd := DEPTH * 0.5
	# Front (+Z): window, window, door, window.
	for x in [-3.0, -1.0, 1.0, 3.0]:
		var kind := "Wall_Plaster_Door_Round" if x == DOOR_X else "Wall_Plaster_Window_Wide_Round"
		_wall(walls, kind, Vector3(x, 0, hd), 0.0)
	door_leaf = _piece(walls, "Door_1_Round", Vector3(DOOR_X - 0.55, 0, hd - 0.05), 0.0)
	_door_shape = _box(Vector3(DOOR_X, 1.2, hd - 0.1), Vector3(1.1, 2.4, 0.12))
	_set_door(true)
	_usable("Door", Vector3(DOOR_X, 0, hd + 0.5), 1.3, func(): return "Close the door" if door_open else "Open the door",
		func(): return "Close" if door_open else "Open", func(_a): toggle_door())
	# Back (-Z).
	for x in [-3.0, -1.0, 1.0, 3.0]:
		_wall(walls, "Wall_Plaster_Window_Wide_Round" if absf(x) > 2.0 else "Wall_UnevenBrick_Straight", Vector3(x, 0, -hd), PI)
	# Sides: a window into each room.
	for z in [-4.0, -2.0, 0.0, 2.0, 4.0]:
		var kind := "Wall_Plaster_Window_Wide_Round" if z == -2.0 or z == 2.0 else "Wall_Plaster_WoodGrid"
		_wall(walls, kind, Vector3(hw, 0, z), PI * 0.5)
		_wall(walls, kind, Vector3(-hw, 0, z), -PI * 0.5)
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		_piece(walls, "Corner_Exterior_Wood", Vector3(corner.x * hw, 0, corner.y * hd))
	# Inside: a wall across behind the living room, with a doorway into
	# the kitchen and one into the bedroom, and one between those two rooms.
	for x in [-3.0, -1.0, 1.0, 3.0]:
		_wall(walls, "Wall_Plaster_Door_Flat" if absf(x) < 2.0 else "Wall_Plaster_Straight", Vector3(x, 0, PARTITION_Z), 0.0, false)
	for z in [-4.0, -2.0]:
		_wall(walls, "Wall_Plaster_Straight", Vector3(0.1, 0, z), PI * 0.5, false)
	# Climbing vines on the front.
	_piece(walls, "Prop_Vine2", Vector3(-hw + 0.2, 0, hd + 0.05), 0.0)
	_piece(walls, "Prop_Vine4", Vector3(hw - 0.4, 0, hd + 0.05), 0.0)
	_rooms["living"] = {"center": Vector3(0, 0, 2.0), "stand": Vector3(DOOR_X, 0, 3.6), "look": 0.0}
	_rooms["kitchen"] = {"center": Vector3(-2.0, 0, -3.0), "stand": Vector3(-1.0, 0, -1.6), "look": 0.0}
	_rooms["bedroom"] = {"center": Vector3(2.0, 0, -3.0), "stand": Vector3(1.0, 0, -1.6), "look": 0.0}


func _build_roof() -> void:
	roof = Node3D.new()
	roof.name = "Roof"
	add_child(roof)
	_piece(roof, "Roof_RoundTiles_8x10", Vector3(0, WALL_HEIGHT, 0))
	_piece(roof, "Roof_Front_Brick8", Vector3(0, WALL_HEIGHT, DEPTH * 0.5))
	_piece(roof, "Roof_Front_Brick8", Vector3(0, WALL_HEIGHT, -DEPTH * 0.5), PI)
	_piece(roof, "Prop_Chimney", Vector3(-2.2, WALL_HEIGHT + 1.2, -3.6))


func _set_door(open: bool) -> void:
	door_open = open
	if door_leaf:
		door_leaf.rotation.y = -1.9 if open else 0.0
	if _door_shape:
		_door_shape.disabled = open


# --- Rooms ----------------------------------------------------------------------------------

func _build_living_room() -> void:
	var room := Node3D.new()
	room.name = "LivingRoom"
	add_child(room)
	_prop(room, "Table_Large", Vector3(-1.6, 0, 2.2), PI * 0.5)
	_prop(room, "Chair_1", Vector3(-2.6, 0, 2.2), PI * 0.5)
	_prop(room, "Chair_1", Vector3(-0.6, 0, 2.2), -PI * 0.5)
	_prop(room, "CandleStick_Triple", Vector3(-1.6, 0.86, 2.2), 0.0, false)
	_prop(room, "Table_Plate", Vector3(-1.9, 0.86, 2.0), 0.0, false)
	_prop(room, "Mug", Vector3(-1.2, 0.86, 2.4), 0.0, false)
	_prop(room, "Bookcase_2", Vector3(-3.35, 0, 0.2), PI * 0.5)
	_prop(room, "Bench", Vector3(2.6, 0, 3.6), -PI * 0.5)
	_prop(room, "Chest_Wood", Vector3(3.2, 0, 0.0), -PI * 0.5)
	_prop(room, "Barrel", Vector3(3.2, 0, 4.4))
	_prop(room, "Peg_Rack", Vector3(-0.3, 1.6, DEPTH * 0.5 - 0.25), PI, false)
	_prop(room, "Banner_1", Vector3(3.68, 1.4, 1.8), -PI * 0.5, false)
	_prop(room, "Vase_4", Vector3(-3.3, 0, 4.4))
	_seat("Sit at the table", Vector3(-2.6, 0, 2.2), PI * 0.5)
	_usable("Bookcase", Vector3(-2.8, 0, 0.2), 1.4, func(): return "Read a book", func(): return "Read",
		func(_a): if Interiors.instance: Interiors.instance._read_book(_a))


func _build_kitchen() -> void:
	var room := Node3D.new()
	room.name = "Kitchen"
	add_child(room)
	# Stone hearth against the back wall, a fire and a cauldron.
	var hearth := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.6, 0.5, 0.9)
	hearth.mesh = box
	hearth.material_override = _stone_material()
	hearth.position = Vector3(-2.2, 0.25, -4.25)
	room.add_child(hearth)
	_box(hearth.position, box.size)
	var fire := Node3D.new()
	fire.position = Vector3(-2.2, 0.5, -4.25)
	room.add_child(fire)
	BuildingFactory._add_fire(fire)
	_prop(room, "Cauldron", Vector3(-2.2, 0.5, -4.25), 0.0, false)
	_prop(room, "Table_Large", Vector3(-1.4, 0, -2.4), 0.0)
	_prop(room, "Pot_1", Vector3(-1.5, 0.86, -2.3), 0.0, false)
	_prop(room, "Carrot", Vector3(-1.2, 0.86, -2.5), 0.5, false)
	_prop(room, "Shelf_Small_Bottles", Vector3(-3.6, 1.3, -2.4), PI * 0.5, false)
	_prop(room, "Barrel_Apples", Vector3(-3.3, 0, -1.6))
	_prop(room, "FarmCrate_Carrot", Vector3(-0.6, 0, -4.3))
	_prop(room, "Bucket_Wooden_1", Vector3(-3.4, 0, -4.4))
	_prop(room, "Stool", Vector3(-2.4, 0, -2.4))
	_usable("Hearth", Vector3(-2.2, 0, -3.6), 1.4, func(): return "Warm your hands at the hearth", func(): return "Warm up",
		func(_a): GameManager.notify("The fire crackles. Something good is bubbling in the cauldron."))


func _build_bedroom() -> void:
	var room := Node3D.new()
	room.name = "Bedroom"
	add_child(room)
	_prop(room, "Bed_Twin1", Vector3(2.4, 0, -4.0), 0.0)
	_prop(room, "Nightstand_Shelf", Vector3(3.5, 0, -4.4))
	_prop(room, "CandleStick", Vector3(3.5, 0.62, -4.4), 0.0, false)
	_prop(room, "Chest_Wood", Vector3(2.4, 0, -2.3), PI)
	_prop(room, "Cabinet", Vector3(0.6, 0, -4.4))
	_prop(room, "Vase_2", Vector3(3.5, 0, -1.6))
	_usable("Bed", Vector3(2.4, 0, -3.2), 1.5, func(): return "Lie down on the bed", func(): return "Lie down",
		func(actor):
			if actor and actor.has_method("lie_down"):
				actor.global_position = to_global(Vector3(2.4, 0.1, -3.8))
				actor.lie_down())


func _build_lights() -> void:
	for spot_info in [[Vector3(-0.5, 2.6, 2.2), 6.5], [Vector3(-2.0, 2.4, -3.0), 4.5], [Vector3(2.0, 2.4, -3.0), 4.5]]:
		var lamp := OmniLight3D.new()
		lamp.position = spot_info[0]
		lamp.omni_range = float(spot_info[1])
		lamp.light_color = Color(1.0, 0.78, 0.5)
		lamp.light_energy = 1.3
		lamp.shadow_enabled = false
		add_child(lamp)
	_prop(self, "Chandelier", Vector3(-1.6, 2.2, 2.2), 0.0, false)


func _seat(prompt_text: String, at: Vector3, facing: float) -> void:
	_usable("Seat", at, 1.0, func(): return prompt_text, func(): return "Sit",
		func(actor):
			if actor and actor.has_method("sit"):
				actor.sit({"position": to_global(at), "yaw": _yaw + facing, "height": 0.48}))


func _usable(object_name: String, at: Vector3, radius: float, prompt: Callable, verb: Callable, use: Callable) -> void:
	var usable := UsableObject.new()
	usable.name = object_name
	usable.prompt = prompt
	usable.verb = verb
	usable.use = use
	usable.position = at
	add_child(usable)
	var interactable := Interactable.new()
	interactable.radius = radius
	interactable.handler = usable
	interactable.interacted.connect(func(actor): usable.use.call(actor))
	usable.add_child(interactable)


## The front door opens and closes.
func toggle_door() -> void:
	_set_door(not door_open)
	Sounds.play("click", global_position)
