class_name PlacedStructure
extends Node3D
## A structure the player placed. Starts as a construction site that the
## player (or a villager asked to help) finishes by working on it; once done
## it becomes the real building, and some are usable: farm plots grow crops,
## the well waters them and a house is somewhere to sleep.

signal completed(structure: PlacedStructure)

## Game hours from planting to harvest.
const CROP_HOURS := 8.0
const HARVEST_FOOD := 4

var record: Dictionary
var interactable: Interactable

var _visual: Node3D
var _label: Label3D
var _crops: MeshInstance3D
var _crop_stage: int = -1


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
	if is_complete():
		_visual = StructureCatalog.create_finished(get_type())
		_label.visible = false
	else:
		_visual = StructureCatalog.create_construction(get_type(), work_fraction())
		_label.visible = true
		_label.text = "%s  %d / %d" % [get_info()["name"], int(record["work"]), int(get_info()["work"])]
	add_child(_visual)
	_crop_stage = -1
	_update_crops()
	interactable.enabled = not (is_complete() and get_type() in [&"lantern"])


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


# --- Interaction ------------------------------------------------------------------------

func can_interact(_actor) -> bool:
	return true


func get_interaction_verb() -> String:
	if not is_complete():
		return "Build"
	match get_type():
		&"farm_plot":
			return "Harvest" if is_ripe() else ("Check" if is_planted() else "Plant")
		&"well":
			return "Water"
		&"house":
			return "Sleep"
		&"bench":
			return "Sit"
	return "Use"


func get_interaction_prompt() -> String:
	var info := get_info()
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
			return "Sleep until morning" if _is_night() else "Your house  (sleep here at night)"
		&"bench":
			return "Sit and rest"
	return String(info["name"])


func _on_interacted(actor: Node) -> void:
	use(actor)


## Does whatever this structure does for whoever used it.
## Returns a short description of what happened.
func use(actor: Node = null) -> String:
	if not is_complete():
		if actor and actor.has_method("perform_action"):
			actor.perform_action(&"work", 1.0, global_position)
		var finished := add_work(1.0)
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
			if _is_night():
				var next_day := WorldClock.day + (1 if WorldClock.time_of_day >= 12.0 else 0)
				WorldClock.day = next_day
				WorldClock.set_time(6.5)
				SaveService.save_game()
				_notify("You slept until morning. Day %d." % WorldClock.day)
				return "slept"
			_notify("Your own home in the village. Come back at night to sleep.")
			return "home"
		&"bench":
			_notify("You sit for a while and watch the village go by.")
			return "rest"
	return ""


static func _is_night() -> bool:
	return WorldClock.time_of_day >= 19.0 or WorldClock.time_of_day < 5.0


func _notify(message: String) -> void:
	if message != "":
		GameManager.notify(message)
