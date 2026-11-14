class_name PlacedStructure
extends Node3D
## A structure the player placed. Starts as a construction site that the
## player (or a villager asked to help) finishes by working on it; once done
## it becomes the real building, and some are usable: farm plots grow crops,
## the well waters them and a house is somewhere to sleep.

signal completed(structure: PlacedStructure)
signal moved(structure: PlacedStructure)
signal removed(structure: PlacedStructure)

## Game hours from planting to harvest.
const CROP_HOURS := 8.0
const HARVEST_FOOD := 4
## Fruit trees: days from planting until they bear fruit, and the fruit.
const FRUIT_TREE_DAYS := 2
const FRUIT_FOOD := 2
## Eggs the hens lay each morning: one each when they were fed the day
## before, otherwise one between them. Each egg is 1 food when collected.
const HENS := 3
const MAX_EGGS := 9
const FEED_COST := {&"herbs": 1}
## Kept for older saves and tests: what unfed hens leave (1) is the minimum.
const EGGS_FOOD := 1

var record: Dictionary
var interactable: Interactable

var _visual: Node3D
var _label: Label3D
var _crops: MeshInstance3D
var _crop_stage: int = -1
var _tree_shown: String = ""


static func create(structure_record: Dictionary) -> PlacedStructure:
	var structure := PlacedStructure.new()
	structure.record = structure_record
	return structure


func get_type() -> StringName:
	return StringName(String(record["type"]))


func is_complete() -> bool:
	return bool(record["complete"])


func get_info() -> Dictionary:
	return StructureCatalog.info(get_type())


func _ready() -> void:
	var p: Array = record["position"]
	position = Vector3(float(p[0]), float(p[1]), float(p[2]))
	rotation.y = float(record["yaw"])
	# Clear the trees and bushes where this goes.
	NatureSpawner.clear_area(position, StructureCatalog.radius(get_type()))
	name = "%s_%d" % [String(record["type"]).to_pascal_case(), int(record["uid"])]
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 40
	_label.outline_size = 12
	# Same size on screen at any distance, so it's readable on a phone.
	_label.fixed_size = true
	_label.pixel_size = 0.0011
	_label.no_depth_test = true
	_label.position = Vector3(0, 2.6 if get_type() == &"house" else 1.6, 0)
	add_child(_label)
	interactable = Interactable.new()
	interactable.radius = maxf(StructureCatalog.radius(get_type()) * 0.75, 1.2)
	interactable.handler = self
	interactable.interacted.connect(_on_interacted)
	add_child(interactable)
	_rebuild()


func _rebuild() -> void:
	if _visual:
		_visual.queue_free()
	if is_complete() and get_type() == &"fruit_tree":
		_visual = StructureCatalog.create_fruit_tree(tree_growth(), has_fruit())
		_label.visible = tree_growth() < 1.0
		_label.text = "Growing (%d%%)" % int(tree_growth() * 100.0)
		_tree_shown = "%.2f/%s" % [tree_growth(), has_fruit()]
	elif is_complete():
		_visual = StructureCatalog.create_finished(get_type())
		_label.visible = false
	else:
		_visual = StructureCatalog.create_construction(get_type(), work_fraction())
		_label.visible = true
		_label.text = construction_text()
	_update_progress_bar()
	add_child(_visual)
	if is_complete() and get_type() == &"chicken_coop":
		_spawn_hens.call_deferred()
		_update_nest.call_deferred()
	_crop_stage = -1
	_update_crops()
	interactable.enabled = true


## e.g. "Cottage: 2 of 6 done\nNext: upper walls (tap Build)".
func construction_text() -> String:
	var done := int(record["work"])
	var total := int(get_info()["work"])
	return "%s: %d of %d done\nNext: %s (tap Build)" % [get_info()["name"], done, total, StructureCatalog.stage_name(get_type(), done + 1)]


## A bar over a building site that fills as it's built (turned to the camera).
var _bar: Node3D
var _bar_fill: MeshInstance3D


func _update_progress_bar() -> void:
	if is_complete():
		if _bar:
			_bar.queue_free()
			_bar = null
		return
	if _bar == null:
		_bar = Node3D.new()
		_bar.name = "ProgressBar"
		_bar.position = _label.position + Vector3(0, 0.95, 0)
		add_child(_bar)
		var back := MeshInstance3D.new()
		var back_mesh := BoxMesh.new()
		back_mesh.size = Vector3(2.4, 0.28, 0.02)
		back.mesh = back_mesh
		back.material_override = _flat(Color(0.12, 0.09, 0.06))
		_bar.add_child(back)
		_bar_fill = MeshInstance3D.new()
		var fill_mesh := BoxMesh.new()
		fill_mesh.size = Vector3(2.25, 0.18, 0.02)
		_bar_fill.mesh = fill_mesh
		_bar_fill.material_override = _flat(Color(0.45, 0.85, 0.35))
		_bar_fill.position = Vector3(0, 0, 0.015)
		_bar.add_child(_bar_fill)
	var fraction := maxf(work_fraction(), 0.02)
	_bar_fill.scale = Vector3(fraction, 1, 1)
	_bar_fill.position.x = -1.125 * (1.0 - fraction)


func _process(_delta: float) -> void:
	if _bar == null:
		return
	var camera := get_viewport().get_camera_3d()
	if camera:
		var to := camera.global_position - _bar.global_position
		to.y = 0.0
		if to.length() > 0.1:
			_bar.global_rotation = Vector3(0, atan2(to.x, to.z), 0)


static func _flat(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material


func work_fraction() -> float:
	return clampf(float(record["work"]) / float(get_info()["work"]), 0.0, 1.0)


## Adds construction work (the player gives 1 per action; helpers give a
## little per game hour). Returns true when this finishes the structure.
func add_work(amount: float) -> bool:
	if is_complete():
		return false
	var before := int(record["work"])
	record["work"] = minf(float(record["work"]) + amount, float(get_info()["work"]))
	if float(record["work"]) >= float(get_info()["work"]) - 0.001:
		record["complete"] = true
		if get_type() == &"fruit_tree":
			record["planted_day"] = WorldClock.day
		_rebuild()
		completed.emit(self)
		GameState.check_objectives()
		return true
	if int(record["work"]) != before or amount >= 1.0:
		_rebuild()
	return false


# --- Crops -----------------------------------------------------------------------------

func crop_hours() -> float:
	return float(record.get("crop_hours", -1.0))


func is_planted() -> bool:
	return crop_hours() >= 0.0


func is_ripe() -> bool:
	return crop_hours() >= CROP_HOURS


## Called as game time passes (and by watering or a helping farmer).
func grow(hours: float) -> void:
	if get_type() != &"farm_plot" or not is_complete() or not is_planted() or is_ripe():
		return
	record["crop_hours"] = minf(crop_hours() + hours, CROP_HOURS)
	_update_crops()


func _update_crops() -> void:
	var stage := -1
	if get_type() == &"farm_plot" and is_complete() and is_planted():
		stage = clampi(int(crop_hours() / CROP_HOURS * 3.0), 0, 3)
	if stage == _crop_stage:
		return
	_crop_stage = stage
	if _crops:
		_crops.queue_free()
		_crops = null
	if stage < 0:
		return
	var b := MeshBuilder.new(int(record["uid"]))
	var height: float = [0.12, 0.3, 0.5, 0.7][stage]
	for row in 3:
		for col in 6:
			var p := Vector3(-1.5 + col * 0.6, 0.2, -0.9 + row * 0.9)
			if stage < 3:
				b.add_cylinder_at(p, 0.06, 0.0, height, 4, Color(0.42, 0.68, 0.3))
			else:
				b.add_blob_at(p + Vector3(0, 0.15, 0), Vector3(0.22, 0.18, 0.22), Color(0.48, 0.7, 0.36), 6, 3)
				b.add_blob_at(p + Vector3(0, 0.3, 0), Vector3(0.12, 0.1, 0.12), Color(0.95, 0.65, 0.25), 5, 3)
	_crops = MeshInstance3D.new()
	_crops.mesh = b.build(Materials.vertex_color())
	add_child(_crops)


# --- Moving and removing --------------------------------------------------------------

func move_to(at: Vector3, yaw: float) -> void:
	record["position"] = [at.x, at.y, at.z]
	record["yaw"] = yaw
	position = at
	rotation.y = yaw
	NatureSpawner.clear_area(position, StructureCatalog.radius(get_type()))
	_move_hens()
	if get_type() == &"cottage" and is_complete():
		moved.emit(self)


## Takes the structure down for good. People living in a cottage move out
## (to another home or the camp).
func take_down() -> void:
	GameState.remove_structure(record)
	removed.emit(self)
	queue_free()


# --- Fruit trees and hens --------------------------------------------------------------

## 0 (just planted) .. 1 (grown).
func tree_growth() -> float:
	var planted := int(record.get("planted_day", WorldClock.day))
	return clampf(float(WorldClock.day - planted) / FRUIT_TREE_DAYS, 0.0, 1.0)


func has_fruit() -> bool:
	return tree_growth() >= 1.0 and int(record.get("picked_day", -1)) != WorldClock.day


## Called each morning: trees grow a little, hens lay.
func new_day() -> int:
	if not is_complete():
		return 0
	match get_type():
		&"fruit_tree":
			_refresh_tree()
		&"chicken_coop":
			var laid := HENS if int(record.get("fed_day", -10)) >= WorldClock.day - 1 else 1
			record["eggs"] = mini(int(record.get("eggs", 0)) + laid, MAX_EGGS)
			_update_nest()
			return laid
	return 0


func _refresh_tree() -> void:
	if get_type() == &"fruit_tree" and is_complete() and _tree_shown != "%.2f/%s" % [tree_growth(), has_fruit()]:
		_rebuild()


# --- Interaction ------------------------------------------------------------------------

func can_interact(_actor) -> bool:
	return true


func _edit_mode() -> String:
	return BuildMode.instance.edit_mode if BuildMode.instance else ""


func get_interaction_verb() -> String:
	match _edit_mode():
		"move":
			return "Move"
		"remove":
			return "Remove"
	if not is_complete():
		return "Build"
	match get_type():
		&"farm_plot":
			return "Harvest" if is_ripe() else ("Check" if is_planted() else "Plant")
		&"well":
			return "Water"
		&"house":
			return "Enter"
		&"cottage":
			return "Enter"
		&"bench":
			return "Sit"
		&"fruit_tree":
			return "Pick" if has_fruit() else "Look"
		&"chicken_coop":
			if eggs() > 0:
				return "Collect"
			return "Feed" if not hens_fed_today() else "Look"
		&"market_stall", &"flower_bed", &"statue", &"fence", &"stone_path", &"lantern":
			return "Admire"
	return "Use"


func get_interaction_prompt() -> String:
	var info := get_info()
	match _edit_mode():
		"move":
			return "Move this %s" % String(info["name"]).to_lower()
		"remove":
			return "Remove this %s (get half back)" % String(info["name"]).to_lower()
	if not is_complete():
		return "Build %s: next, %s  (%d / %d)" % [String(info["name"]).to_lower(), StructureCatalog.stage_name(get_type(), int(record["work"]) + 1), int(record["work"]), int(info["work"])]
	match get_type():
		&"farm_plot":
			if is_ripe():
				return "Harvest crops  (+%d food)" % HARVEST_FOOD
			if is_planted():
				return "Crops growing  (%d%%)" % int(crop_hours() / CROP_HOURS * 100.0)
			return "Plant seeds"
		&"well":
			return "Draw water for the crops"
		&"house":
			return "Enter your house" + ("  (bed's inside)" if _is_night() else "")
		&"bench":
			return "Sit and rest"
		&"fruit_tree":
			if has_fruit():
				return "Pick fruit  (+%d food)" % FRUIT_FOOD
			return "Fruit tree (growing, %d%%)" % int(tree_growth() * 100.0) if tree_growth() < 1.0 else "Fruit tree (picked today)"
		&"chicken_coop":
			if eggs() > 0:
				return "Collect %d egg%s  (+%d food)" % [eggs(), "" if eggs() == 1 else "s", eggs()]
			if not hens_fed_today():
				return "Feed the hens  (%s; fed hens lay %d eggs every morning, unfed just 1)" % [GameState.cost_text(FEED_COST), HENS]
			return "Chicken coop  (the hens are fed and happy; eggs in the morning)"
		&"cottage":
			var names := Population.residents_of(home_id()).map(func(id): return Population.get_person(String(id)).first_name)
			if names.is_empty():
				return "Enter the cottage  (nobody lives here yet; room for %d)" % Population.COTTAGE_CAPACITY
			return "Enter the cottage  (home of %s)" % ", ".join(names)
	return String(info["name"])


## The room behind this home's door ("player", or "cottage_<uid>": every
## cottage keeps its own layout, saved through its uid).
func interior_id() -> String:
	return "player" if get_type() == &"house" else "cottage_%d" % int(record["uid"])


## Just outside the front door (where you come back out), wherever the home
## has been moved to.
func doorstep() -> Vector3:
	var front := (global_transform.basis * Vector3(0, 0, 1)).normalized()
	var at := global_position + front * (float(get_info()["footprint"].y) * 0.5 + 1.2)
	at.y = VillageLayout.get_walk_height(at.x, at.z)
	return at


# --- Hens ------------------------------------------------------------------------

func eggs() -> int:
	return int(record.get("eggs", 0))


func hens_fed_today() -> bool:
	return int(record.get("fed_day", -10)) == WorldClock.day


var _hens: Array = []
var _nest: Node3D


## The run's middle and the feeder, in the world.
func run_center() -> Vector3:
	return global_transform * Vector3(0, 0, StructureCatalog.COOP_RUN_Z)


func _spawn_hens() -> void:
	if get_type() != &"chicken_coop" or not is_complete() or not _hens.is_empty() or not is_inside_tree():
		return
	for i in HENS:
		var hen := Chicken.new()
		hen.brown = i == 1
		hen.coop = self
		hen.home = run_center()
		hen.feeder = global_transform * (Vector3(0, 0, StructureCatalog.COOP_RUN_Z) + StructureCatalog.COOP_FEEDER)
		add_child(hen)
		hen.global_position = run_center() + Vector3(cos(i * 2.1), 0, sin(i * 2.1)) * 1.0
		_hens.append(hen)
	_update_nest()


func hens() -> Array:
	return _hens.filter(func(h): return is_instance_valid(h))


## The run follows the coop when it's moved.
func _move_hens() -> void:
	for hen in hens():
		hen.home = run_center()
		hen.feeder = global_transform * (Vector3(0, 0, StructureCatalog.COOP_RUN_Z) + StructureCatalog.COOP_FEEDER)
		hen.global_position = run_center()


## Eggs you can see waiting in the nest box.
func _update_nest() -> void:
	if not is_inside_tree() or get_type() != &"chicken_coop":
		return
	if _nest:
		_nest.queue_free()
		_nest = null
	if eggs() <= 0 or not is_complete():
		return
	var b := MeshBuilder.new(5)
	b.color_jitter = 0.0
	for i in eggs():
		var at := Vector3(1.35 - 0.12 + (i % 3) * 0.12, 0.66 + (i / 3) * 0.05, StructureCatalog.COOP_HOUSE_Z + 0.2 + (i % 2) * 0.1)
		b.add_blob_at(at, Vector3(0.04, 0.05, 0.04), Color(0.98, 0.94, 0.85) if i % 2 == 0 else Color(0.85, 0.68, 0.5), 6, 4, 0.0)
	var mesh := MeshInstance3D.new()
	mesh.mesh = b.build(Materials.vertex_color())
	_nest = mesh
	add_child(mesh)


## The home location id of a finished cottage.
func home_id() -> String:
	return Population.cottage_home_id(record)


## Where residents go in and out (just in front of the door).
func door_point() -> Vector3:
	return global_transform * Vector3(0, 0, 3.3)


func _on_interacted(actor: Node) -> void:
	match _edit_mode():
		"move":
			BuildMode.instance.start_move(self)
			return
		"remove":
			BuildMode.instance.remove(self)
			return
	use(actor)


## Does whatever this structure does for whoever used it.
## Returns a short description of what happened.
func use(actor: Node = null) -> String:
	if not is_complete():
		if actor and actor.has_method("perform_action"):
			actor.perform_action(&"work", 1.0, global_position, &"hammer")
		var finished := add_work(1.0)
		var at := global_position
		get_tree().create_timer(0.55).timeout.connect(func(): Sounds.play("hammer", at))
		if finished:
			get_tree().create_timer(0.8).timeout.connect(func(): Sounds.play("built", at))
		var message := "%s finished!" % get_info()["name"] if finished else ""
		FloatingText.spawn(get_parent(), global_position + Vector3(0, 2.0, 0), "Built!" if finished else "+1 work")
		return message
	match get_type():
		&"farm_plot":
			if is_ripe():
				if actor and actor.has_method("perform_action"):
					actor.perform_action(&"gather", 1.2, global_position)
				record["crop_hours"] = -1.0
				_update_crops()
				GameState.add(&"food", HARVEST_FOOD)
				Sounds.play("pickup", global_position)
				GameState.increment(&"harvests")
				FloatingText.spawn(get_parent(), global_position + Vector3(0, 1.4, 0), "+%d Food" % HARVEST_FOOD)
				return "harvested"
			if is_planted():
				_notify("The crops are %d%% grown. Water from a well makes them grow faster." % int(crop_hours() / CROP_HOURS * 100.0))
				return "growing"
			if actor and actor.has_method("perform_action"):
				actor.perform_action(&"work", 1.0, global_position, &"hoe")
			record["crop_hours"] = 0.0
			_update_crops()
			_notify("Seeds planted. They'll be ready in about %d hours." % int(CROP_HOURS))
			return "planted"
		&"well":
			var watered := 0
			for structure in get_tree().get_nodes_in_group("placed_structures"):
				if structure.get_type() == &"farm_plot" and structure.is_planted() and not structure.is_ripe():
					structure.grow(3.0)
					watered += 1
			if actor and actor.has_method("perform_action"):
				actor.perform_action(&"gather", 1.0, global_position, &"watering_can")
			_notify("You watered %d farm plot%s." % [watered, "" if watered == 1 else "s"] if watered > 0 else "Fresh, cold water. Plant some crops and it will help them grow.")
			return "watered"
		&"house":
			if Interiors.instance and actor == GameManager.player:
				Interiors.instance.enter("player", doorstep(), rotation.y)
				return "entered"
			if _is_night():
				WorldClock.day += 1 if WorldClock.time_of_day >= 12.0 else 0
				WorldClock.set_time(6.5)
				_notify("You slept until morning. Day %d." % WorldClock.day)
				return "slept"
			_notify("Your own home in the village. Come back at night to sleep.")
			return "home"
		&"bench":
			if actor and actor.has_method("sit"):
				actor.sit({"position": global_transform * Vector3(0, 0, 0.12), "yaw": rotation.y, "height": 0.53})
			else:
				_notify("You sit for a while and watch the village go by.")
			return "rest"
		&"fruit_tree":
			if has_fruit():
				if actor and actor.has_method("perform_action"):
					actor.perform_action(&"gather", 1.0, global_position)
				record["picked_day"] = WorldClock.day
				GameState.add(&"food", FRUIT_FOOD)
				Sounds.play("pickup", global_position)
				FloatingText.spawn(get_parent(), global_position + Vector3(0, 2.0, 0), "+%d Food" % FRUIT_FOOD)
				_rebuild()
				return "picked"
			_notify("It's still growing. Come back in a day or two." if tree_growth() < 1.0 else "You picked it clean today. More tomorrow.")
			return "growing"
		&"chicken_coop":
			if eggs() > 0:
				var n := eggs()
				if actor and actor.has_method("perform_action"):
					actor.perform_action(&"gather", 1.0, global_position)
				record["eggs"] = 0
				GameState.add(&"food", n)
				_update_nest()
				Sounds.play("pickup", global_position)
				FloatingText.spawn(get_parent(), global_position + Vector3(0, 1.4, 0), "+%d Food (eggs)" % n)
				return "collected"
			if not hens_fed_today():
				if not GameState.spend(FEED_COST):
					_notify("%s to feed the hens. (Pick herbs in the meadows.)" % GameState.missing_text(FEED_COST))
					return "no_feed"
				record["fed_day"] = WorldClock.day
				if actor and actor.has_method("perform_action"):
					actor.perform_action(&"gather", 1.0, global_position)
				Sounds.play("cluck", global_position, -4.0)
				_notify("You scatter feed for the hens. They'll lay %d eggs tomorrow morning." % HENS)
				return "fed"
			_notify("The hens are fed. Come back in the morning for their eggs.")
			return "hens"
		&"market_stall", &"flower_bed", &"statue", &"fence", &"stone_path", &"lantern":
			_notify("The village looks lovelier for it. (Village beauty: %d)" % int(GameState.beauty()))
			return "admired"
		&"cottage":
			if Interiors.instance and actor == GameManager.player:
				Interiors.instance.enter(interior_id(), doorstep(), rotation.y)
				return "entered"
			var names := Population.residents_of(home_id()).map(func(id): return Population.get_person(String(id)).first_name)
			_notify("Nobody lives here yet." if names.is_empty() else "Home of %s." % ", ".join(names))
			return "visited"
	return ""


static func _is_night() -> bool:
	return WorldClock.time_of_day >= 19.0 or WorldClock.time_of_day < 5.0


func _notify(message: String) -> void:
	if message != "":
		GameManager.notify(message)
