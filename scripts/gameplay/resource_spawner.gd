class_name ResourceSpawner
extends RefCounted
## Places harvestable resources: a grove of trees west of the village, a rocky
## quarry to the north and herb patches along the river.

const AREAS := [
	{"kind": &"tree", "count": 16, "from": Vector2(-50, -20), "to": Vector2(-33, 24), "spacing": 3.4},
	{"kind": &"rock", "count": 9, "from": Vector2(-14, -42), "to": Vector2(14, -30), "spacing": 3.0},
	{"kind": &"herbs", "count": 7, "from": Vector2(18, -26), "to": Vector2(27, 26), "spacing": 3.0},
]

static var nodes: Array[ResourceNode] = []


static func spawn(parent: Node3D) -> void:
	nodes.clear()
	var root := Node3D.new()
	root.name = "Resources"
	parent.add_child(root)
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210
	var placed: Array[Vector2] = []
	for area in AREAS:
		var kind: StringName = area["kind"]
		var from: Vector2 = area["from"]
		var to: Vector2 = area["to"]
		var made := 0
		var attempts := 0
		while made < int(area["count"]) and attempts < 600:
			attempts += 1
			var p := Vector2(rng.randf_range(from.x, to.x), rng.randf_range(from.y, to.y))
			if VillageLayout.blocking_reason(p.x, p.y, 1.0, 1.4) != "":
				continue
			var crowded := false
			for other in placed:
				if other.distance_to(p) < float(area["spacing"]):
					crowded = true
					break
			if crowded:
				continue
			placed.append(p)
			var node := ResourceNode.new()
			node.kind = kind
			node.spot_id = "%s_%d" % [kind, made]
			node.name = node.spot_id.to_pascal_case()
			node.position = VillageLayout.ground_point(p.x, p.y)
			node.rotation.y = rng.randf() * TAU
			root.add_child(node)
			nodes.append(node)
			made += 1
