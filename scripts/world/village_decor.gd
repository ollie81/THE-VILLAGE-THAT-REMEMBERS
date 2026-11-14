class_name VillageDecor
extends RefCounted
## Small touches that make the village feel lived in: flower planters either
## side of each front door, an herb bed beside each home, and a market corner
## with two stalls by the meeting circle. Drawn as one mesh; only the stalls
## have collision, and they're kept clear of paths and building spots.

## Where the stalls stand (BuildMode keeps clear of them).
static var stalls: Array[Vector3] = []
const STALL_RADIUS := 1.8


static func build(parent: Node3D) -> void:
	var root := Node3D.new()
	root.name = "VillageDecor"
	parent.add_child(root)
	var m := MeshBuilder.new(31)
	var flower_colors := [Color(0.95, 0.4, 0.45), Color(0.98, 0.8, 0.25), Color(0.7, 0.45, 0.9), Color(1.0, 0.95, 0.9), Color(0.95, 0.55, 0.2)]
	for building in VillageLayout.get_buildings():
		if String(building["type"]) != "house" or String(building["owner"]) == "":
			continue
		var center: Vector3 = building["position"]
		var basis := Basis(Vector3.UP, float(building["yaw"]))
		var depth: float = building["footprint"].y
		var width: float = building["footprint"].x
		# Planters either side of the door.
		for side in [-1.0, 1.0]:
			var p: Vector3 = center + basis * Vector3(side * 1.25, 0, depth * 0.5 + 0.55)
			p.y = TerrainGenerator.get_height(p.x, p.z)
			m.add_box(Transform3D(basis, p + Vector3(0, 0.22, 0)), Vector3(0.55, 0.44, 0.55), BuildingFactory.WOOD)
			m.add_box(Transform3D(basis, p + Vector3(0, 0.45, 0)), Vector3(0.48, 0.04, 0.48), Color(0.35, 0.25, 0.16))
			for f in 5:
				var a: float = TAU * f / 5.0 + side
				var bloom: Vector3 = p + Vector3(cos(a) * 0.13, 0.62 + 0.05 * (f % 2), sin(a) * 0.13)
				m.add_blob_at(bloom, Vector3(0.09, 0.09, 0.09), flower_colors[(f + int(side + 1.0)) % flower_colors.size()], 6, 3, 0.1)
			m.add_blob_at(p + Vector3(0, 0.55, 0), Vector3(0.24, 0.12, 0.24), Color(0.35, 0.6, 0.3), 7, 3, 0.2)
		# An herb bed along one side wall.
		var bed: Vector3 = center + basis * Vector3(width * 0.5 + 0.9, 0, 0.6)
		bed.y = TerrainGenerator.get_height(bed.x, bed.z)
		m.add_box(Transform3D(basis, bed + Vector3(0, 0.1, 0)), Vector3(0.9, 0.2, 2.2), BuildingFactory.WOOD_DARK)
		m.add_box(Transform3D(basis, bed + Vector3(0, 0.2, 0)), Vector3(0.8, 0.04, 2.1), Color(0.33, 0.24, 0.15))
		for i in 6:
			var plant: Vector3 = bed + basis * Vector3(-0.2 + (i % 2) * 0.4, 0.32, -0.85 + (i / 2) * 0.85)
			m.add_blob_at(plant, Vector3(0.17, 0.15, 0.17), Color(0.32, 0.58, 0.3).lightened(0.06 * (i % 3)), 6, 3, 0.25)
	var mesh := MeshInstance3D.new()
	mesh.mesh = m.build(Materials.vertex_color())
	root.add_child(mesh)
	_build_market(root)


## Two stalls on a free spot beside the meeting circle.
static func _build_market(root: Node3D) -> void:
	stalls.clear()
	for radius in [VillageLayout.PLAZA_RADIUS + 3.6, VillageLayout.PLAZA_RADIUS + 5.5, VillageLayout.PLAZA_RADIUS + 7.5]:
		var angle := 0.0
		while angle < TAU and stalls.size() < 2:
			var p := Vector3(cos(angle) * radius, 0, sin(angle) * radius)
			angle += 0.1
			if VillageLayout.blocking_reason(p.x, p.z, STALL_RADIUS, 0.3) != "":
				continue
			if stalls.any(func(s): return s.distance_to(p) < STALL_RADIUS * 2.2) or (not stalls.is_empty() and stalls[0].distance_to(p) > 16.0):
				continue
			if ResourceSpawner.nodes.any(func(n): return is_instance_valid(n) and Vector2(n.global_position.x - p.x, n.global_position.z - p.z).length() < STALL_RADIUS + 1.0):
				continue
			stalls.append(p)
	for p in stalls:
		var stall := StructureCatalog.create_finished(&"market_stall")
		stall.position = VillageLayout.ground_point(p.x, p.z)
		stall.rotation.y = atan2(-p.x, -p.z)
		root.add_child(stall)
		NatureSpawner.clear_area(stall.position, STALL_RADIUS)
		var trader := UsableObject.new()
		trader.name = "MarketStall"
		trader.prompt = func(): return "Trade at the market" if TradePanel.is_open_today() else "Market stall  (the traders come from day %d)" % TradePanel.OPENS_DAY
		trader.verb = func(): return "Trade" if TradePanel.is_open_today() else "Look"
		trader.use = func(_actor):
			if not TradePanel.is_open_today():
				GameManager.notify("The stall is empty. Traders start coming on day %d." % TradePanel.OPENS_DAY)
			elif TradePanel.instance:
				TradePanel.instance.open()
		stall.add_child(trader)
		var interactable := Interactable.new()
		interactable.radius = 2.0
		interactable.handler = trader
		interactable.interacted.connect(func(actor): trader.use.call(actor))
		trader.add_child(interactable)


## Why `at` is taken by the market (for building), or "".
static func blocking_reason(at: Vector3, radius: float) -> String:
	for p in stalls:
		if Vector2(at.x - p.x, at.z - p.z).length() < radius + STALL_RADIUS:
			return "Too close to the market stalls"
	return ""
