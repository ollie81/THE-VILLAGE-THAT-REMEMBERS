class_name HouseInterior
extends RefCounted
## The inside of a player's house: real rooms divided by walls with doorways
## (all with collision, so nobody walks through them), windows, the floor
## from the house's design, a light in each room and, in the kitchen, a
## hearth to cook at. Furniture is separate (see Furnishings), so the same
## rooms can be arranged however the player likes.
##
## Layout, seen from above with the front door at the bottom (+Z):
##   small:  one room
##   medium: bedroom at the back, living room at the front
##   large:  kitchen | bedroom at the back, living room at the front
##   manor:  kitchen | bedroom | second bedroom at the back,
##           living room | hall | dining room at the front

const WALL_HEIGHT := 3.2
const WALL_THICK := 0.18
const DOOR_WIDTH := 1.3
## Kept clear in front of the way out, so you can always leave.
const ENTRANCE_DEPTH := 1.6

## Rooms (x, z, width, depth; z grows toward the front door), the inner walls
## as [ax, az, bx, bz, [doorway centres along the wall]], the kitchen's room
## and where its hearth stands against a wall (x, z, facing yaw).
static func layout(type: StringName) -> Dictionary:
	var size: Vector2 = HouseDesigns.size_info(type)["inside"]
	var hw := size.x * 0.5
	var hd := size.y * 0.5
	match type:
		&"house_medium":
			return {"size": size,
				"rooms": [["Living room", Rect2(-hw, -0.5, size.x, hd + 0.5)], ["Bedroom", Rect2(-hw, -hd, size.x, hd - 0.5)]],
				"walls": [[-hw, -0.5, hw, -0.5, [2.5]]],
				"hearth": [-hw + 0.5, 1.6, PI * 0.5], "kitchen": "Living room"}
		&"house_large":
			return {"size": size,
				"rooms": [["Living room", Rect2(-hw, 0.0, size.x, hd)], ["Kitchen", Rect2(-hw, -hd, hw, hd)], ["Bedroom", Rect2(0.0, -hd, hw, hd)]],
				"walls": [[-hw, 0.0, hw, 0.0, [-3.0, 3.0]], [0.0, -hd, 0.0, 0.0, []]],
				"hearth": [-hw * 0.5, -hd + 0.5, 0.0], "kitchen": "Kitchen"}
		&"manor":
			var t := size.x / 6.0
			return {"size": size,
				"rooms": [["Hall", Rect2(-2.0, 0.0, 4.0, hd)], ["Living room", Rect2(-hw, 0.0, hw - 2.0, hd)], ["Dining room", Rect2(2.0, 0.0, hw - 2.0, hd)],
					["Kitchen", Rect2(-hw, -hd, 2.0 * t, hd)], ["Bedroom", Rect2(-t, -hd, 2.0 * t, hd)], ["Second bedroom", Rect2(t, -hd, 2.0 * t, hd)]],
				"walls": [[-hw, 0.0, hw, 0.0, [-hw + t, 0.0, hw - t]], [-2.0, 0.0, -2.0, hd, [hd * 0.5]], [2.0, 0.0, 2.0, hd, [hd * 0.5]],
					[-t, -hd, -t, 0.0, []], [t, -hd, t, 0.0, []]],
				"hearth": [-hw + t, -hd + 0.5, 0.0], "kitchen": "Kitchen"}
	return {"size": size, "rooms": [["Living room", Rect2(-hw, -hd, size.x, size.y)]], "walls": [],
		"hearth": [-hw + 1.4, -hd + 0.5, 0.0], "kitchen": "Living room"}


## Floor areas taken by walls, the hearth and the entrance (furniture can't
## go there), as Rect2s in room space.
static func blocked(type: StringName) -> Array:
	var l := layout(type)
	var out: Array = []
	for w in l["walls"]:
		var a := Vector2(float(w[0]), float(w[1]))
		var b := Vector2(float(w[2]), float(w[3]))
		var rect := Rect2(a.min(b), (b - a).abs()).grow(WALL_THICK * 0.5 + 0.05)
		out.append(rect)
		# Keep doorways clear too, so a sofa never blocks a door.
		for c in w[4]:
			var along := absf(b.x - a.x) > absf(b.y - a.y)
			var centre := Vector2(float(c), a.y) if along else Vector2(a.x, float(c))
			out.append(Rect2(centre - Vector2(0.8, 0.8), Vector2(1.6, 1.6)))
	var h: Array = l["hearth"]
	var hearth_size := Vector2(2.2, 1.5) if absf(float(h[2])) < 0.1 else Vector2(1.5, 2.2)
	out.append(Rect2(Vector2(float(h[0]), float(h[1])) - hearth_size * 0.5, hearth_size))
	var size: Vector2 = l["size"]
	out.append(Rect2(-0.9, size.y * 0.5 - ENTRANCE_DEPTH, 1.8, ENTRANCE_DEPTH))
	return out


## The room a point (room space) is in, or "".
static func room_at(type: StringName, at: Vector2) -> String:
	for r in layout(type)["rooms"]:
		if (r[1] as Rect2).has_point(at):
			return String(r[0])
	return ""


## Where you stand when you come in.
static func spawn(type: StringName) -> Vector3:
	var size: Vector2 = HouseDesigns.size_info(type)["inside"]
	return Vector3(0, 0.05, size.y * 0.5 - 1.6)


## Builds the rooms (no furniture). `interiors` provides the shared hearth
## and exit-door behaviour.
static func build(type: StringName, design: Dictionary, interiors) -> Node3D:
	var d := HouseDesigns.normalized(design)
	var l := layout(type)
	var size: Vector2 = l["size"]
	var hw := size.x * 0.5
	var hd := size.y * 0.5
	var room := Node3D.new()
	var kit := BuildingFactory.Kit.new(hash(String(type)) + 17)
	var m: MeshBuilder = kit.mesh
	var wall := HouseDesigns.wall_color(d).lightened(0.08)
	var trim := BuildingFactory.WOOD_DARK
	var wood := BuildingFactory.WOOD
	if String(d["style"]) == "stone":
		wall = wall.lerp(BuildingFactory.STONE.lightened(0.15), 0.35)
	# Floor.
	_floor(m, String(d["floor"]), size)
	kit.box_collider(Vector3(0, -0.25, 0), Vector3(size.x + 1.0, 0.5, size.y + 1.0))
	# Outer walls, a wooden dado, corner posts.
	var h := WALL_HEIGHT
	for side: float in [-1.0, 1.0]:
		m.add_box_at(Vector3(side * hw, h * 0.5, 0), Vector3(0.2, h, size.y + 0.2), wall)
		m.add_box_at(Vector3(side * (hw - 0.11), 0.5, 0), Vector3(0.04, 1.0, size.y - 0.2), wood.darkened(0.1))
		kit.box_collider(Vector3(side * (hw + 0.1), h * 0.5, 0), Vector3(0.4, h, size.y + 0.4))
		m.add_box_at(Vector3(0, h * 0.5, side * hd), Vector3(size.x + 0.2, h, 0.2), wall)
		m.add_box_at(Vector3(0, 0.5, side * (hd - 0.11)), Vector3(size.x - 0.2, 1.0, 0.04), wood.darkened(0.1))
		kit.box_collider(Vector3(0, h * 0.5, side * (hd + 0.1)), Vector3(size.x + 0.4, h, 0.4))
		for s2: float in [-1.0, 1.0]:
			m.add_box_at(Vector3(side * (hw - 0.15), h * 0.5, s2 * (hd - 0.15)), Vector3(0.24, h, 0.24), trim)
	# Ceiling and beams.
	m.add_box_at(Vector3(0, h + 0.05, 0), Vector3(size.x + 0.2, 0.1, size.y + 0.2), wood.darkened(0.45))
	var beams := int(size.y / 2.0)
	for i in beams:
		m.add_box_at(Vector3(0, h - 0.13, -hd + (float(i) + 0.5) * size.y / beams), Vector3(size.x, 0.2, 0.22), trim)
	# Inner walls with doorways.
	for w in l["walls"]:
		_inner_wall(m, kit, Vector2(float(w[0]), float(w[1])), Vector2(float(w[2]), float(w[3])), w[4], wall, trim)
	# The front door and the way out.
	var door_z := hd - 0.12
	m.add_box_at(Vector3(0, 1.1, door_z), Vector3(1.15, 2.2, 0.08), HouseDesigns.door_color(d))
	for sx: float in [-1.0, 1.0]:
		m.add_box_at(Vector3(sx * 0.66, 1.15, door_z - 0.03), Vector3(0.14, 2.3, 0.12), trim)
	m.add_box_at(Vector3(0, 2.33, door_z - 0.03), Vector3(1.46, 0.14, 0.12), trim)
	m.add_box_at(Vector3(0.4, 1.05, door_z - 0.07), Vector3(0.08, 0.08, 0.06), Color(0.82, 0.7, 0.35))
	m.add_box_at(Vector3(0, 0.015, door_z - 0.8), Vector3(1.3, 0.02, 0.8), Color(0.62, 0.48, 0.3))
	interiors._usable(room, "ExitDoor", Vector3(0, 0, door_z - 0.55), 1.0,
		func(): return "Go outside", func(): return "Leave", func(_a): interiors.leave())
	# Windows round the outside walls (not where an inner wall meets them).
	var walls_x: Array = []
	var walls_z: Array = []
	for w in l["walls"]:
		if absf(float(w[0]) - float(w[2])) < 0.01:
			walls_x.append(float(w[0]))
		else:
			walls_z.append(float(w[1]))
	var x := -hw + 1.6
	while x < hw - 1.0:
		if absf(x) > 1.4 and not walls_x.any(func(v): return absf(v - x) < 1.0):
			_window(m, Vector3(x, 1.7, hd - 0.12), 0.0, trim)
		if not walls_x.any(func(v): return absf(v - x) < 1.0):
			_window(m, Vector3(x, 1.7, -hd + 0.12), PI, trim)
		x += 3.2
	var z := -hd + 1.6
	while z < hd - 1.0:
		if not walls_z.any(func(v): return absf(v - z) < 1.0):
			_window(m, Vector3(hw - 0.12, 1.7, z), PI * 0.5, trim)
			_window(m, Vector3(-hw + 0.12, 1.7, z), -PI * 0.5, trim)
		z += 3.2
	# The hearth, in the kitchen.
	var hp: Array = l["hearth"]
	_hearth(room, m, kit, Vector3(float(hp[0]), 0, float(hp[1])), float(hp[2]), interiors)
	# A light in each room (warm, like lamplight).
	for r in l["rooms"]:
		var rect: Rect2 = r[1]
		var lamp := OmniLight3D.new()
		lamp.name = "Light_" + String(r[0]).replace(" ", "")
		lamp.position = Vector3(rect.get_center().x, h - 0.6, rect.get_center().y)
		lamp.light_color = Color(1.0, 0.86, 0.66)
		lamp.light_energy = 0.9
		lamp.omni_range = maxf(rect.size.x, rect.size.y) * 0.9 + 2.0
		room.add_child(lamp)
	kit.finish(room)
	return room


static func _floor(m: MeshBuilder, floor_kind: String, size: Vector2) -> void:
	var hw := size.x * 0.5
	var hd := size.y * 0.5
	match floor_kind:
		"stone":
			var row := 0
			var zz := -hd
			while zz < hd - 0.01:
				var xx := -hw + (0.4 if row % 2 == 1 else 0.0)
				m.add_box_at(Vector3(-hw + 0.2, -0.05, zz + 0.4), Vector3(0.4, 0.1, 0.78), Color(0.6, 0.58, 0.54))
				while xx < hw - 0.01:
					var wdt := minf(0.8, hw - xx)
					m.add_box_at(Vector3(xx + wdt * 0.5, -0.05, zz + 0.4), Vector3(wdt - 0.04, 0.1, 0.76), Color(0.62, 0.6, 0.56).darkened(0.05 * float((row + int(xx * 2.0)) % 3)))
					xx += 0.8
				zz += 0.8
				row += 1
		"tiles":
			var i := 0
			var zt := -hd
			while zt < hd - 0.01:
				var xt := -hw
				var j := 0
				while xt < hw - 0.01:
					m.add_box_at(Vector3(xt + 0.25, -0.05, zt + 0.25), Vector3(0.48, 0.1, 0.48), Color(0.7, 0.36, 0.26) if (i + j) % 2 == 0 else Color(0.84, 0.74, 0.6))
					xt += 0.5
					j += 1
				zt += 0.5
				i += 1
		"carpet":
			m.add_box_at(Vector3(0, -0.05, 0), Vector3(size.x, 0.1, size.y), Color(0.58, 0.42, 0.27))
			m.add_box_at(Vector3(0, 0.005, 0), Vector3(size.x - 0.6, 0.02, size.y - 0.6), Color(0.52, 0.22, 0.24))
			m.add_box_at(Vector3(0, 0.01, 0), Vector3(size.x - 1.0, 0.02, size.y - 1.0), Color(0.6, 0.3, 0.28))
		_:
			var boards := int(size.x / 0.8)
			for b in boards:
				var bx := -hw + (float(b) + 0.5) * size.x / boards
				m.add_box_at(Vector3(bx, -0.05, 0), Vector3(size.x / boards - 0.02, 0.1, size.y), Color(0.58, 0.42, 0.27).lightened(0.035 * float(b % 3)))


static func _inner_wall(m: MeshBuilder, kit, a: Vector2, b: Vector2, doors: Array, wall: Color, trim: Color) -> void:
	var along_x := absf(b.x - a.x) > absf(b.y - a.y)
	var start := minf(a.x, b.x) if along_x else minf(a.y, b.y)
	var finish := maxf(a.x, b.x) if along_x else maxf(a.y, b.y)
	var fixed := a.y if along_x else a.x
	var cuts: Array = []
	for c in doors:
		cuts.append([float(c) - DOOR_WIDTH * 0.5, float(c) + DOOR_WIDTH * 0.5])
	cuts.sort_custom(func(p, q): return p[0] < q[0])
	var pieces: Array = []
	var cursor := start
	for c in cuts:
		if c[0] > cursor:
			pieces.append([cursor, c[0]])
		cursor = c[1]
	if cursor < finish:
		pieces.append([cursor, finish])
	var h := WALL_HEIGHT
	for p in pieces:
		var length := float(p[1]) - float(p[0])
		var mid := (float(p[0]) + float(p[1])) * 0.5
		var centre := Vector3(mid, h * 0.5, fixed) if along_x else Vector3(fixed, h * 0.5, mid)
		var size := Vector3(length, h, WALL_THICK) if along_x else Vector3(WALL_THICK, h, length)
		m.add_box_at(centre, size, wall)
		var dado := Vector3(length, 1.0, WALL_THICK + 0.04) if along_x else Vector3(WALL_THICK + 0.04, 1.0, length)
		m.add_box_at(Vector3(centre.x, 0.5, centre.z), dado, BuildingFactory.WOOD.darkened(0.1))
		kit.box_collider(centre, size)
	for c in doors:
		var centre := Vector3(float(c), 0, fixed) if along_x else Vector3(fixed, 0, float(c))
		var lintel := Vector3(DOOR_WIDTH, h - 2.3, WALL_THICK) if along_x else Vector3(WALL_THICK, h - 2.3, DOOR_WIDTH)
		m.add_box_at(centre + Vector3(0, 2.3 + (h - 2.3) * 0.5, 0), lintel, wall)
		var frame_top := Vector3(DOOR_WIDTH + 0.2, 0.14, WALL_THICK + 0.06) if along_x else Vector3(WALL_THICK + 0.06, 0.14, DOOR_WIDTH + 0.2)
		m.add_box_at(centre + Vector3(0, 2.3, 0), frame_top, trim)
		for s: float in [-1.0, 1.0]:
			var off := Vector3(s * (DOOR_WIDTH * 0.5 + 0.05), 1.15, 0) if along_x else Vector3(0, 1.15, s * (DOOR_WIDTH * 0.5 + 0.05))
			var post := Vector3(0.12, 2.3, WALL_THICK + 0.06) if along_x else Vector3(WALL_THICK + 0.06, 2.3, 0.12)
			m.add_box_at(centre + off, post, trim)


static func _window(m: MeshBuilder, at: Vector3, yaw: float, trim: Color) -> void:
	var b := Basis(Vector3.UP, yaw)
	var inward := b * Vector3(0, 0, -1)
	m.add_box(Transform3D(b, at + inward * 0.02), Vector3(0.95, 0.95, 0.04), Color(0.78, 0.88, 0.95))
	m.add_box(Transform3D(b, at + inward * 0.05), Vector3(0.06, 0.95, 0.04), trim)
	m.add_box(Transform3D(b, at + inward * 0.05), Vector3(0.95, 0.06, 0.04), trim)
	m.add_box(Transform3D(b, at + inward * 0.05), Vector3(1.1, 1.1, 0.02), trim.lightened(0.15))
	m.add_box(Transform3D(b, at + inward * 0.1 + Vector3(0, -0.55, 0)), Vector3(1.15, 0.07, 0.2), trim)
	for s: float in [-1.0, 1.0]:
		m.add_box(Transform3D(b, at + inward * 0.08 + b * Vector3(s * 0.68, 0, 0)), Vector3(0.28, 1.15, 0.03), Color(0.75, 0.32, 0.25))


## A stone hearth with a fire, a cooking pot and a worktop beside it.
static func _hearth(room: Node3D, m: MeshBuilder, kit, at: Vector3, yaw: float, interiors) -> void:
	var b := Basis(Vector3.UP, yaw)
	var t := func(local: Vector3) -> Vector3: return at + b * local
	m.add_box(Transform3D(b, t.call(Vector3(0, 0.75, 0))), Vector3(1.9, 1.5, 0.9), BuildingFactory.STONE)
	m.add_box(Transform3D(b, t.call(Vector3(0, 0.55, 0.41))), Vector3(1.0, 0.72, 0.1), Color(0.12, 0.1, 0.09))
	m.add_box(Transform3D(b, t.call(Vector3(0, 1.55, 0.05))), Vector3(2.1, 0.12, 1.0), BuildingFactory.WOOD_DARK)
	m.add_box(Transform3D(b, t.call(Vector3(0, 2.4, -0.05))), Vector3(1.0, 1.7, 0.7), BuildingFactory.STONE_DARK)
	m.add_cylinder_at(t.call(Vector3(0, 0.32, 0.55)), 0.24, 0.2, 0.3, 9, Color(0.2, 0.2, 0.22))
	kit.box_collider(t.call(Vector3(0, 0.75, 0.2)), Vector3(1.9, 1.5, 1.3), yaw)
	var fire := OmniLight3D.new()
	fire.name = "HearthFire"
	fire.position = t.call(Vector3(0, 0.6, 0.9))
	fire.light_color = Color(1.0, 0.6, 0.3)
	fire.light_energy = 1.4
	fire.omni_range = 6.0
	room.add_child(fire)
	var flames := MeshBuilder.new(5)
	flames.color_jitter = 0.0
	flames.add_cylinder_at(Vector3.ZERO, 0.22, 0.0, 0.45, 6, Color.WHITE)
	flames.add_cylinder_at(Vector3(0.15, 0, 0.05), 0.12, 0.0, 0.3, 5, Color.WHITE)
	var flame := MeshInstance3D.new()
	flame.mesh = flames.build(Materials.flame())
	flame.position = t.call(Vector3(0, 0.22, 0.3))
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	room.add_child(flame)
	interiors._usable(room, "Hearth", t.call(Vector3(0, 0, 1.45)), 0.9, interiors._cook_prompt, func(): return "Cook", interiors._cook)
