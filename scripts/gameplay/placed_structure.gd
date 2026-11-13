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
const EGGS_FOOD := 2

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
	_label.font_size = 48
	_label.outline_size = 12
	_label.pixel_size = 0.005
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
		_label.text = "%s  %d / %d" % [get_info()["name"], int(record["work"]), int(get_info()["work"])]
	add_child(_visual)
	_crop_stage = -1
	_update_crops()
	interactable.enabled = true


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
			GameState.add(&"food", EGGS_FOOD)
			return EGGS_FOOD
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
			return "Visit"
		&"bench":
			return "Sit"
		&"fruit_tree":
			return "Pick" if has_fruit() else "Look"
		&"chicken_coop":
			return "Look"
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
		return "Build %s  (%d / %d)" % [String(info["name"]).to_lower(), int(record["work"]), int(info["work"])]
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
			return "Chicken coop  (+%d food every morning)" % EGGS_FOOD
		&"cottage":
			return "Cottage  (%d / %d living here)" % [Population.residents_of(home_id()).size(), Population.COTTAGE_CAPACITY]
	return String(info["name"])


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
			actor.perform_action(&"work", 1.0, global_position)
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
				actor.perform_action(&"gather", 1.0, global_position)
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
				actor.perform_action(&"work", 0.8, global_position)
			_notify("You watered %d farm plot%s." % [watered, "" if watered == 1 else "s"] if watered > 0 else "Fresh, cold water. Plant some crops and it will help them grow.")
			return "watered"
		&"house":
			if Interiors.instance and actor == GameManager.player:
				var front := global_transform.basis * Vector3(0, 0, 1)
				var info := get_info()
				var doorstep := global_position + front.normalized() * (float(info["footprint"].y) * 0.5 + 1.2)
				Interiors.instance.enter("player", doorstep, rotation.y)
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
			_notify("The hens cluck at you. They lay %d food's worth of eggs every morning." % EGGS_FOOD)
			return "hens"
		&"market_stall", &"flower_bed", &"statue", &"fence", &"stone_path", &"lantern":
			_notify("The village looks lovelier for it. (Village beauty: %d)" % int(GameState.beauty()))
			return "admired"
		&"cottage":
			var names := Population.residents_of(home_id()).map(func(id): return Population.get_person(String(id)).first_name)
			_notify("Nobody lives here yet." if names.is_empty() else "Home of %s." % ", ".join(names))
			return "visited"
	return ""


static func _is_night() -> bool:
	return WorldClock.time_of_day >= 19.0 or WorldClock.time_of_day < 5.0


func _notify(message: String) -> void:
	if message != "":
		GameManager.notify(message)
