class_name VillageLife
extends Node3D
## Small signs of life: butterflies fluttering round the flowers by day (only
## near the player, a dozen at most), and smoke curling from the founders'
## chimneys in the morning and evening.

const BUTTERFLIES := 12
const RANGE := 18.0

var _flies: Array = []  # {node, wings, center, phase, speed}
var _smoke: Array[CPUParticles3D] = []
var _check: float = 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	name = "VillageLife"
	_rng.seed = 404
	for i in BUTTERFLIES:
		_flies.append(_make_butterfly(i))
	for building in VillageLayout.get_buildings():
		if String(building["type"]) == "house" and String(building["owner"]) != "":
			_add_smoke(building)


func _make_butterfly(i: int) -> Dictionary:
	var node := Node3D.new()
	add_child(node)
	var colors := [Color(0.98, 0.75, 0.2), Color(0.95, 0.95, 0.98), Color(0.55, 0.65, 0.98), Color(0.98, 0.5, 0.35)]
	var wings: Array = []
	for side in [-1.0, 1.0]:
		var wing := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(0.09, 0.07)
		wing.mesh = quad
		var material := StandardMaterial3D.new()
		material.albedo_color = colors[i % colors.size()]
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		wing.material_override = material
		wing.position = Vector3(side * 0.045, 0, 0)
		wing.rotation = Vector3(-PI * 0.5, 0, 0)
		var pivot := Node3D.new()
		pivot.add_child(wing)
		node.add_child(pivot)
		wings.append(pivot)
	return {"node": node, "wings": wings, "center": Vector3.ZERO, "phase": _rng.randf() * TAU, "speed": _rng.randf_range(0.6, 1.1)}


func _add_smoke(building: Dictionary) -> void:
	var center: Vector3 = building["position"]
	var basis := Basis(Vector3.UP, float(building["yaw"]))
	var depth: float = building["footprint"].y
	var width: float = building["footprint"].x
	var chimney: Vector3 = center + basis * Vector3(width * 0.3, 0, -depth * 0.18)
	chimney.y = BuildingFactory._base_height(center, building["footprint"], float(building["yaw"])) + 5.3
	var smoke := CPUParticles3D.new()
	smoke.position = chimney
	smoke.amount = 10
	smoke.lifetime = 4.0
	smoke.direction = Vector3(0.2, 1, 0)
	smoke.spread = 12.0
	smoke.initial_velocity_min = 0.4
	smoke.initial_velocity_max = 0.7
	smoke.gravity = Vector3(0.15, 0.05, 0)
	smoke.scale_amount_min = 0.4
	smoke.scale_amount_max = 0.8
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.4))
	curve.add_point(Vector2(1, 1.6))
	smoke.scale_amount_curve = curve
	var mesh := SphereMesh.new()
	mesh.radius = 0.25
	mesh.height = 0.5
	mesh.radial_segments = 6
	mesh.rings = 3
	smoke.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.85, 0.85, 0.88, 0.35)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = material
	add_child(smoke)
	_smoke.append(smoke)


func _process(delta: float) -> void:
	var player = GameManager.player
	if player == null:
		return
	var hour := WorldClock.time_of_day
	var indoor: bool = Interiors.instance != null and Interiors.instance.is_inside()
	_check -= delta
	if _check <= 0.0:
		_check = 1.0
		var smoky := (hour >= 6.0 and hour < 9.5) or (hour >= 17.0 and hour < 22.0)
		for smoke in _smoke:
			smoke.emitting = smoky and not indoor
	var day := hour >= 7.0 and hour < 18.5 and not indoor
	for fly: Dictionary in _flies:
		var node: Node3D = fly["node"]
		node.visible = day
		if not day:
			continue
		var center: Vector3 = fly["center"]
		if center == Vector3.ZERO or center.distance_to(player.global_position) > RANGE:
			# Settle near the player, over open grass.
			var a := _rng.randf() * TAU
			var r := _rng.randf_range(4.0, RANGE * 0.8)
			center = player.global_position + Vector3(cos(a) * r, 0, sin(a) * r)
			center.y = VillageLayout.get_walk_height(center.x, center.z) + 0.6
			fly["center"] = center
		fly["phase"] = float(fly["phase"]) + delta * float(fly["speed"])
		var t: float = fly["phase"]
		node.position = center + Vector3(sin(t) * 1.2, 0.3 * sin(t * 2.7), cos(t * 0.8) * 1.2)
		node.rotation.y = t + PI * 0.5
		var flap := sin(Time.get_ticks_msec() * 0.03 + t * 10.0) * 0.9
		(fly["wings"][0] as Node3D).rotation.z = flap
		(fly["wings"][1] as Node3D).rotation.z = -flap
