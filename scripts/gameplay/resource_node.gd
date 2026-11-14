class_name ResourceNode
extends Node3D
## A tree, rock or herb patch the player can harvest. Each gives a few loads
## before it is spent; it grows back the next morning.

const KINDS := {
	&"tree": {"resource": &"wood", "verb": "Chop", "name": "tree", "uses": 3, "yield": 2, "anim": &"work", "time": 0.9},
	&"rock": {"resource": &"stone", "verb": "Mine", "name": "rock", "uses": 3, "yield": 2, "anim": &"work", "time": 1.0},
	&"herbs": {"resource": &"herbs", "verb": "Pick", "name": "herbs", "uses": 1, "yield": 2, "anim": &"gather", "time": 0.8},
}
const REGROW_HOUR := 6

var kind: StringName = &"tree"
var spot_id: String = ""
var uses_left: int = 0
var interactable: Interactable

var _full: Node3D
var _spent: Node3D
var _collision: CollisionShape3D


func _ready() -> void:
	var info: Dictionary = KINDS[kind]
	_full = _build_full()
	add_child(_full)
	_spent = _build_spent()
	add_child(_spent)
	_build_collision()
	interactable = Interactable.new()
	interactable.prompt_verb = String(info["verb"])
	interactable.display_name = String(info["name"])
	interactable.radius = 1.3
	interactable.handler = self
	interactable.interacted.connect(_on_interacted)
	add_child(interactable)
	uses_left = int(info["uses"])
	var regrow_day := int(GameState.depleted.get(spot_id, -1))
	_set_spent(regrow_day >= 0 and not _should_regrow(regrow_day))
	WorldClock.hour_changed.connect(_on_hour_changed)


func can_interact(_actor) -> bool:
	return uses_left > 0


func get_interaction_prompt() -> String:
	var info: Dictionary = KINDS[kind]
	return "%s %s  (+%d %s)" % [info["verb"], info["name"], harvest_amount(), String(GameState.RESOURCE_NAMES[info["resource"]]).to_lower()]


func get_interaction_verb() -> String:
	return String(KINDS[kind]["verb"])


func harvest_amount() -> int:
	var amount := int(KINDS[kind]["yield"])
	if GameState.get_flag(&"has_tools") and kind != &"herbs":
		amount += 1
	return amount


func _on_interacted(actor: Node) -> void:
	harvest(actor)


## Gives the resource to the village stockpile. Returns the amount gathered.
func harvest(actor: Node = null) -> int:
	if uses_left <= 0:
		return 0
	var info: Dictionary = KINDS[kind]
	var amount := harvest_amount()
	if actor and actor.has_method("perform_action"):
		actor.perform_action(info["anim"], float(info["time"]), global_position, {&"tree": &"axe", &"rock": &"pickaxe"}.get(kind, &""))
	# The sound lands when the axe or pick strikes (the swing's downstroke).
	var sound: String = {&"tree": "chop", &"rock": "stone"}.get(kind, "gather")
	var at := global_position
	if is_inside_tree():
		get_tree().create_timer(0.0 if sound == "gather" else 0.6).timeout.connect(func():
			Sounds.play(sound, at)
			Sounds.play("pickup", at, -8.0))
	GameState.add(info["resource"], amount)
	FloatingText.spawn(get_parent(), global_position + Vector3(0, 2.2 if kind == &"tree" else 1.2, 0),
		"+%d %s" % [amount, GameState.RESOURCE_NAMES[info["resource"]]])
	uses_left -= 1
	if uses_left <= 0:
		GameState.depleted[spot_id] = WorldClock.day + 1
		_set_spent(true)
	return amount


func _should_regrow(regrow_day: int) -> bool:
	return WorldClock.day > regrow_day or (WorldClock.day == regrow_day and WorldClock.time_of_day >= REGROW_HOUR)


func _on_hour_changed(_hour: int) -> void:
	if uses_left > 0 or not GameState.depleted.has(spot_id):
		return
	if _should_regrow(int(GameState.depleted[spot_id])):
		GameState.depleted.erase(spot_id)
		uses_left = int(KINDS[kind]["uses"])
		_set_spent(false)


## Hidden while it stands between the camera and the player (see
## NatureSpawner.update_view). Only the full tree hides; a stump stays.
var _view_hidden: bool = false


func set_view_hidden(hidden: bool) -> void:
	if hidden == _view_hidden:
		return
	_view_hidden = hidden
	if _full:
		_full.visible = not hidden and uses_left > 0


func _set_spent(spent: bool) -> void:
	if spent:
		uses_left = 0
	_full.visible = not spent and not _view_hidden
	_spent.visible = spent
	if _collision:
		_collision.set_deferred("disabled", spent and kind != &"tree")


# --- Looks ----------------------------------------------------------------------------

func _mesh_node(builder: MeshBuilder) -> Node3D:
	var instance := MeshInstance3D.new()
	instance.mesh = builder.build(Materials.vertex_color())
	return instance


func _build_full() -> Node3D:
	var b := MeshBuilder.new(hash(spot_id))
	match kind:
		&"tree":
			var bark := Color(0.44, 0.31, 0.2)
			b.add_cylinder_at(Vector3(0, -0.2, 0), 0.3, 0.2, 2.6, 7, bark)
			var green := Color(0.34, 0.56, 0.26).lightened(b.rng.randf_range(-0.05, 0.08))
			b.add_blob_at(Vector3(0, 3.2, 0), Vector3(1.6, 1.4, 1.6), green, 8, 4, 0.16)
			b.add_blob_at(Vector3(0.6, 2.6, 0.3), Vector3(1.0, 0.85, 1.0), green.darkened(0.08), 6, 4, 0.15)
			b.add_blob_at(Vector3(-0.55, 2.8, -0.35), Vector3(0.95, 0.8, 0.95), green.lightened(0.05), 6, 4, 0.15)
			# A notch cut into the trunk marks trees that are free to fell.
			b.add_box_at(Vector3(0, 0.55, 0.24), Vector3(0.22, 0.14, 0.06), Color(0.85, 0.7, 0.45))
		&"rock":
			var grey := Color(0.56, 0.55, 0.52)
			b.add_blob_at(Vector3(0, 0.45, 0), Vector3(0.9, 0.62, 0.8), grey, 7, 4, 0.25)
			b.add_blob_at(Vector3(0.55, 0.25, 0.35), Vector3(0.45, 0.32, 0.42), grey.lightened(0.06), 6, 3, 0.25)
			b.add_blob_at(Vector3(-0.2, 0.75, -0.1), Vector3(0.28, 0.12, 0.3), Color(0.72, 0.68, 0.6), 5, 3, 0.2)
		&"herbs":
			for i in 7:
				var a := TAU * float(i) / 7.0
				var p := Vector3(cos(a) * 0.35, 0.18, sin(a) * 0.35)
				b.add_blob_at(p, Vector3(0.22, 0.2, 0.22), Color(0.38, 0.62, 0.32), 5, 3, 0.1)
				b.add_blob_at(p + Vector3(0, 0.2, 0), Vector3(0.07, 0.07, 0.07), Color(0.68, 0.52, 0.86), 5, 3, 0.0)
	return _mesh_node(b)


func _build_spent() -> Node3D:
	var b := MeshBuilder.new(hash(spot_id) + 1)
	match kind:
		&"tree":
			b.add_cylinder_at(Vector3(0, -0.2, 0), 0.32, 0.3, 0.6, 7, Color(0.44, 0.31, 0.2))
			b.add_cylinder_at(Vector3(0, 0.39, 0), 0.29, 0.29, 0.02, 7, Color(0.85, 0.72, 0.5))
		&"rock":
			for i in 4:
				b.add_blob_at(Vector3(randf_range(-0.4, 0.4), 0.08, randf_range(-0.4, 0.4)), Vector3(0.18, 0.1, 0.16), Color(0.55, 0.54, 0.5), 5, 3, 0.2)
		&"herbs":
			b.add_blob_at(Vector3(0, 0.05, 0), Vector3(0.35, 0.06, 0.35), Color(0.4, 0.5, 0.28), 6, 3, 0.1)
	return _mesh_node(b)


func _build_collision() -> void:
	if kind == &"herbs":
		return
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	_collision = CollisionShape3D.new()
	if kind == &"tree":
		var cylinder := CylinderShape3D.new()
		cylinder.radius = 0.32
		cylinder.height = 2.5
		_collision.shape = cylinder
		_collision.position = Vector3(0, 1.1, 0)
	else:
		var sphere := SphereShape3D.new()
		sphere.radius = 0.75
		_collision.shape = sphere
		_collision.position = Vector3(0, 0.35, 0)
	body.add_child(_collision)
	add_child(body)
