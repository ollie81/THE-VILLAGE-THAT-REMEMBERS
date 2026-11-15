class_name HouseBuilder
extends RefCounted
## Builds the outside of a player's house from its size and design, in the
## village's own low-poly style: a stone base, walls in the chosen style
## (timber-framed plaster, coursed stone or painted boards), windows in the
## chosen style that glow at night, a coloured door, a pitched roof and a
## chimney. Wider houses get more windows; the manor has two storeys, a
## pillared porch and a dormer. The front door faces local +Z.

const STOREY := 2.7


static func build(type: StringName, design: Dictionary) -> Node3D:
	var info := HouseDesigns.size_info(type)
	var d := HouseDesigns.normalized(design)
	var root := Node3D.new()
	root.name = "House"
	var kit := BuildingFactory.Kit.new(hash(String(type)) + hash(JSON.stringify(d)))
	_build(kit, float(info["w"]), float(info["d"]), int(info["storeys"]), d)
	kit.finish(root)
	return root


## Where the door is on the outside (local), for the "Enter" spot.
static func door_local(type: StringName) -> Vector3:
	return Vector3(0, 0, float(HouseDesigns.size_info(type)["d"]) * 0.5)


static func _build(kit, w: float, d: float, storeys: int, design: Dictionary) -> void:
	var m: MeshBuilder = kit.mesh
	var style := String(design["style"])
	var wall := HouseDesigns.wall_color(design)
	var roof := HouseDesigns.roof_color(design)
	var door := HouseDesigns.door_color(design)
	var trim := BuildingFactory.WOOD_DARK
	if style == "stone":
		wall = wall.lerp(BuildingFactory.STONE, 0.45)
	var h := STOREY * storeys
	# Base and walls.
	m.add_box_at(Vector3(0, -0.35, 0), Vector3(w + 0.4, 1.3, d + 0.4), BuildingFactory.STONE)
	m.add_box_at(Vector3(0, 0.3 + h * 0.5, 0), Vector3(w, h, d), wall)
	var top := 0.3 + h
	match style:
		"timber":
			_timber_frame(m, w, d, storeys, trim)
		"stone":
			_stone_courses(m, w, d, h, wall)
		"painted":
			_boards(m, w, d, h, wall)
	if storeys > 1:
		for sz: float in [-1.0, 1.0]:
			m.add_box_at(Vector3(0, 0.3 + STOREY, sz * (d * 0.5 + 0.04)), Vector3(w + 0.12, 0.2, 0.12), trim)
		for sx: float in [-1.0, 1.0]:
			m.add_box_at(Vector3(sx * (w * 0.5 + 0.04), 0.3 + STOREY, 0), Vector3(0.12, 0.2, d + 0.12), trim)
	# Windows: along the front either side of the door, along the back, on the sides.
	var front := d * 0.5
	for storey in storeys:
		var y := 0.3 + storey * STOREY + 1.45
		var count := maxi(1, int((w - 2.2) / 1.9))
		for i in count:
			var side := -1.0 if i % 2 == 0 else 1.0
			var x := side * (1.6 + float(i / 2) * 1.9)
			if absf(x) > w * 0.5 - 0.7:
				continue
			_window(kit, design, Vector3(x, y, front), 0.0)
			_window(kit, design, Vector3(x, y, -front), PI)
		if storey > 0 and w >= 8.0:
			_window(kit, design, Vector3(0, y, front), 0.0)  # over the door upstairs
		var side_count := 1 if d < 7.0 else 2
		for j in side_count:
			var z := 0.0 if side_count == 1 else (j - 0.5) * d * 0.45
			_window(kit, design, Vector3(w * 0.5, y, z), PI * 0.5)
			_window(kit, design, Vector3(-w * 0.5, y, z), -PI * 0.5)
	# The door: a single door, or double doors under a porch on the manor.
	var door_w := 1.1 if storeys == 1 else 1.8
	m.add_box_at(Vector3(0, 1.3, front + 0.04), Vector3(door_w, 1.95, 0.1), door)
	if storeys > 1:
		m.add_box_at(Vector3(0, 1.3, front + 0.1), Vector3(0.05, 1.9, 0.04), door.darkened(0.3))
	m.add_box_at(Vector3(0, 2.33, front + 0.06), Vector3(door_w + 0.3, 0.14, 0.14), trim)
	for sx: float in [-1.0, 1.0]:
		m.add_box_at(Vector3(sx * (door_w * 0.5 + 0.08), 1.3, front + 0.06), Vector3(0.12, 2.0, 0.12), trim)
	m.add_box_at(Vector3(door_w * 0.3, 1.3, front + 0.11), Vector3(0.08, 0.08, 0.06), Color(0.82, 0.7, 0.35))
	m.add_box_at(Vector3(0, 0.3, front + 0.55), Vector3(door_w + 0.6, 0.22, 0.8), BuildingFactory.STONE)
	if storeys > 1:
		# A pillared porch with a little roof.
		for sx: float in [-1.0, 1.0]:
			m.add_cylinder_at(Vector3(sx * 1.6, 0.3, front + 1.5), 0.16, 0.14, 2.5, 8, Color(0.92, 0.9, 0.85))
		m.add_box_at(Vector3(0, 2.85, front + 0.9), Vector3(3.8, 0.16, 1.9), trim)
		m.add_prism(Transform3D(Basis.IDENTITY, Vector3(0, 2.93, front + 0.9)), 4.0, 2.1, 0.7, roof)
		m.add_box_at(Vector3(0, 0.22, front + 1.1), Vector3(3.8, 0.12, 2.0), BuildingFactory.STONE.lightened(0.08))
	# Roof, ridge, chimney.
	var roof_h := clampf(w * 0.3, 1.8, 3.4)
	m.add_prism(Transform3D(Basis.IDENTITY, Vector3(0, top, 0)), w + 0.9, d + 1.3, roof_h, roof)
	if design["roof"] == 2:  # thatch: a thicker, rounder edge
		m.add_box_at(Vector3(0, top + 0.05, d * 0.5 + 0.55), Vector3(w + 0.95, 0.25, 0.3), roof.darkened(0.1))
		m.add_box_at(Vector3(0, top + 0.05, -d * 0.5 - 0.55), Vector3(w + 0.95, 0.25, 0.3), roof.darkened(0.1))
	m.add_box_at(Vector3(0, top + roof_h - 0.06, 0), Vector3(w + 1.0, 0.16, 0.32), roof.darkened(0.25))
	for gx: float in [-1.0, 1.0]:
		m.add_box_at(Vector3(gx * (w * 0.5 + 0.02), top + roof_h * 0.32, 0), Vector3(0.08, roof_h * 0.6, d * 0.55), wall.darkened(0.06))
	var chimney_h := roof_h + 0.9
	m.add_box_at(Vector3(w * 0.3, top + chimney_h * 0.5, -d * 0.18), Vector3(0.62, chimney_h, 0.62), BuildingFactory.STONE_DARK)
	if storeys > 1:
		# A dormer on the front slope, and a second chimney.
		m.add_box_at(Vector3(0, top + 0.6, d * 0.22), Vector3(1.4, 1.1, 1.2), wall)
		m.add_prism(Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0, top + 1.15, d * 0.22)), 1.5, 1.7, 0.7, roof)
		kit.glow.add_box_at(Vector3(0, top + 0.6, d * 0.22 + 0.61), Vector3(0.6, 0.55, 0.04), Color.WHITE)
		m.add_box_at(Vector3(-w * 0.32, top + chimney_h * 0.5, -d * 0.2), Vector3(0.62, chimney_h, 0.62), BuildingFactory.STONE_DARK)
	kit.box_collider(Vector3(0, 0.3 + h * 0.5, 0), Vector3(w + 0.4, h + 0.8, d + 0.4))


static func _timber_frame(m: MeshBuilder, w: float, d: float, storeys: int, trim: Color) -> void:
	var h := STOREY * storeys
	for sz: float in [-1.0, 1.0]:
		var face := sz * (d * 0.5 + 0.03)
		var posts := int(w / 1.6)
		for i in posts + 1:
			var x := -w * 0.5 + w * float(i) / posts
			m.add_box_at(Vector3(x, 0.3 + h * 0.5, face), Vector3(0.18, h, 0.08), trim)
		for storey in storeys:
			var base := 0.3 + storey * STOREY
			m.add_box_at(Vector3(0, base + 0.12, face), Vector3(w + 0.1, 0.16, 0.08), trim)
			m.add_box_at(Vector3(0, base + STOREY - 0.12, face), Vector3(w + 0.1, 0.16, 0.08), trim)
			# Braces in the end bays.
			for side: float in [-1.0, 1.0]:
				var cx := side * (w * 0.5 - w / posts * 0.5)
				var brace := Transform3D(Basis(Vector3.BACK, side * 0.75), Vector3(cx, base + STOREY * 0.5, face))
				m.add_box(brace, Vector3(0.12, STOREY * 0.9, 0.06), trim)
	for sx: float in [-1.0, 1.0]:
		var face := sx * (w * 0.5 + 0.03)
		var posts := maxi(2, int(d / 1.6))
		for i in posts + 1:
			var z := -d * 0.5 + d * float(i) / posts
			m.add_box_at(Vector3(face, 0.3 + h * 0.5, z), Vector3(0.08, h, 0.18), trim)
		for storey in storeys:
			m.add_box_at(Vector3(face, 0.3 + storey * STOREY + STOREY - 0.12, 0), Vector3(0.08, 0.16, d + 0.1), trim)


static func _stone_courses(m: MeshBuilder, w: float, d: float, h: float, wall: Color) -> void:
	var rows := int(h / 0.5)
	for r in rows:
		var y := 0.55 + r * 0.5
		var offset := 0.45 if r % 2 == 1 else 0.0
		for sz: float in [-1.0, 1.0]:
			var x := -w * 0.5 + offset
			var i := 0
			while x < w * 0.5 - 0.3:
				var shade := wall.darkened(0.06 + 0.05 * float((i + r) % 3))
				m.add_box_at(Vector3(x + 0.42, y, sz * (d * 0.5 + 0.03)), Vector3(0.8, 0.42, 0.06), shade)
				x += 0.9
				i += 1
		for sx: float in [-1.0, 1.0]:
			var z := -d * 0.5 + offset
			var j := 0
			while z < d * 0.5 - 0.3:
				m.add_box_at(Vector3(sx * (w * 0.5 + 0.03), y, z + 0.42), Vector3(0.06, 0.42, 0.8), wall.darkened(0.06 + 0.05 * float((j + r) % 3)))
				z += 0.9
				j += 1
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			m.add_box_at(Vector3(sx * w * 0.5, 0.3 + h * 0.5, sz * d * 0.5), Vector3(0.34, h, 0.34), BuildingFactory.STONE_DARK)


static func _boards(m: MeshBuilder, w: float, d: float, h: float, wall: Color) -> void:
	for sz: float in [-1.0, 1.0]:
		var x := -w * 0.5 + 0.3
		while x < w * 0.5:
			m.add_box_at(Vector3(x, 0.3 + h * 0.5, sz * (d * 0.5 + 0.03)), Vector3(0.04, h, 0.05), wall.darkened(0.18))
			x += 0.42
	for sx: float in [-1.0, 1.0]:
		var z := -d * 0.5 + 0.3
		while z < d * 0.5:
			m.add_box_at(Vector3(sx * (w * 0.5 + 0.03), 0.3 + h * 0.5, z), Vector3(0.05, h, 0.04), wall.darkened(0.18))
			z += 0.42
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			m.add_box_at(Vector3(sx * w * 0.5, 0.3 + h * 0.5, sz * d * 0.5), Vector3(0.22, h, 0.22), Color(0.95, 0.94, 0.9))


## A window at `at` on a wall facing `yaw` (0 = +Z): a glowing pane and the
## chosen style's frame.
static func _window(kit, design: Dictionary, at: Vector3, yaw: float) -> void:
	var m: MeshBuilder = kit.mesh
	var b := Basis(Vector3.UP, yaw)
	var out := b * Vector3(0, 0, 1)
	var right := b * Vector3(1, 0, 0)
	var trim := BuildingFactory.WOOD_DARK
	var accent := HouseDesigns.door_color(design)
	var pane := at + out * 0.035
	var size := Vector3(0.85, 0.85, 0.05)
	match String(design["window"]):
		"arched":
			size = Vector3(0.75, 1.0, 0.05)
			kit.glow.add_box(Transform3D(b, pane), size, Color.WHITE)
			for side: float in [-1.0, 1.0]:
				m.add_box(Transform3D(b, at + out * 0.07 + right * side * 0.46 + Vector3(0, 0.05, 0)), Vector3(0.16, 1.25, 0.1), BuildingFactory.STONE.lightened(0.1))
			m.add_box(Transform3D(b, at + out * 0.075), Vector3(0.05, 1.0, 0.03), trim)
			kit.glow.add_box(Transform3D(b, pane + Vector3(0, 0.55, 0)), Vector3(0.5, 0.18, 0.05), Color.WHITE)
			m.add_box(Transform3D(b, at + out * 0.06 + Vector3(0, 0.7, 0)), Vector3(0.95, 0.14, 0.08), BuildingFactory.STONE.lightened(0.1))
			m.add_box(Transform3D(b, at + out * 0.06 + Vector3(0, -0.55, 0)), Vector3(0.95, 0.1, 0.12), BuildingFactory.STONE.lightened(0.1))
		"lattice":
			kit.glow.add_box(Transform3D(b, pane), size, Color.WHITE)
			for i in 3:
				m.add_box(Transform3D(b, at + out * 0.065 + right * (-0.28 + i * 0.28)), Vector3(0.035, 0.85, 0.03), trim)
				m.add_box(Transform3D(b, at + out * 0.065 + Vector3(0, -0.28 + i * 0.28, 0)), Vector3(0.85, 0.035, 0.03), trim)
			m.add_box(Transform3D(b, at + out * 0.06 + Vector3(0, -0.5, 0)), Vector3(1.0, 0.1, 0.12), trim)
		_:
			kit.glow.add_box(Transform3D(b, pane), size, Color.WHITE)
			m.add_box(Transform3D(b, at + out * 0.065), Vector3(0.06, 0.85, 0.03), trim)
			for side: float in [-1.0, 1.0]:
				m.add_box(Transform3D(b, at + out * 0.06 + right * side * 0.6), Vector3(0.3, 0.9, 0.05), accent)
			m.add_box(Transform3D(b, at + out * 0.15 + Vector3(0, -0.52, 0)), Vector3(1.0, 0.2, 0.28), BuildingFactory.WOOD)
			for i in 4:
				m.add_blob_at(at + out * 0.17 + right * (-0.36 + i * 0.24) + Vector3(0, -0.34, 0), Vector3(0.12, 0.11, 0.12),
					[Color(0.9, 0.35, 0.4), Color(0.95, 0.8, 0.3), Color(0.7, 0.45, 0.85)][i % 3], 5, 3)
