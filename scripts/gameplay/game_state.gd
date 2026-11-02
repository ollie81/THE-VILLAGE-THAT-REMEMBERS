extends Node
## The player's progress in the village: shared stockpile, built structures,
## depleted resource spots, the introductory week of objectives and a few
## story flags. Saved with the rest of the game by SaveService.

signal inventory_changed(resource: StringName, amount: int, total: int)
signal objective_changed(index: int)
signal objective_completed(index: int, title: String)
signal structure_added(record: Dictionary)

const RESOURCES: Array[StringName] = [&"wood", &"stone", &"food", &"herbs"]
const RESOURCE_NAMES := {&"wood": "Wood", &"stone": "Stone", &"food": "Food", &"herbs": "Herbs"}

## The introductory week. Each objective is a suggestion: everything stays
## available whether or not it is done, and they can be finished early.
const OBJECTIVES := [
	{"id": "meet", "day": 1, "title": "Meet the villagers",
		"hint": "Walk up to each villager and talk to them."},
	{"id": "gather", "day": 2, "title": "Gather supplies",
		"hint": "Chop trees west of the village and break rocks in the quarry to the north."},
	{"id": "farm_plot", "day": 3, "title": "Prepare a farm plot",
		"hint": "Open Build and place a Farm plot, then work on it until it's finished."},
	{"id": "harvest", "day": 4, "title": "Plant and harvest crops",
		"hint": "Plant seeds in your farm plot and come back when they've grown."},
	{"id": "help", "day": 5, "title": "Ask a villager for help",
		"hint": "Talk to someone and ask them to help with a task."},
	{"id": "house", "day": 6, "title": "Raise a new house",
		"hint": "Place a House and build it. Mara and Tomas are good builders."},
	{"id": "meeting", "day": 7, "title": "Hold a village meeting",
		"hint": "In the evening, call a meeting at the fire in the meeting circle."},
]

var inventory: Dictionary = {}
## Lifetime totals, for objectives and the story stone.
var collected: Dictionary = {}
## Placed structures: { uid, type, position: [x, y, z], yaw, work, complete,
## crop_planted_day, crop_planted_hour }.
var structures: Array = []
## resource spot id -> day it grows back.
var depleted: Dictionary = {}
var objective_index: int = 0
var flags: Dictionary = {}
var _next_uid: int = 1


func _ready() -> void:
	reset()


func reset() -> void:
	inventory = {}
	collected = {}
	for resource in RESOURCES:
		inventory[resource] = 0
		collected[resource] = 0
	structures = []
	depleted = {}
	objective_index = 0
	flags = {}
	_next_uid = 1


# --- Inventory ----------------------------------------------------------------------

func count(resource: StringName) -> int:
	return int(inventory.get(resource, 0))


func add(resource: StringName, amount: int) -> void:
	if amount == 0:
		return
	inventory[resource] = maxi(count(resource) + amount, 0)
	if amount > 0:
		collected[resource] = int(collected.get(resource, 0)) + amount
	inventory_changed.emit(resource, amount, count(resource))
	check_objectives()


## What a new village starts with, so you can build straight away. Not
## counted as gathered (the "gather supplies" goal still needs gathering).
## Enough for your own house straight away.
const STARTER_KIT := {&"wood": 20, &"stone": 10, &"food": 4, &"herbs": 3}


func give_starter_kit() -> void:
	for resource in STARTER_KIT:
		inventory[resource] = count(resource) + int(STARTER_KIT[resource])
		inventory_changed.emit(resource, int(STARTER_KIT[resource]), count(resource))


func can_afford(cost: Dictionary) -> bool:
	for resource in cost:
		if count(resource) < int(cost[resource]):
			return false
	return true


## "Need 4 more stone" style explanation, or "" when affordable.
func missing_text(cost: Dictionary) -> String:
	var parts := PackedStringArray()
	for resource in cost:
		var missing := int(cost[resource]) - count(resource)
		if missing > 0:
			parts.append("%d more %s" % [missing, String(RESOURCE_NAMES.get(resource, resource)).to_lower()])
	return "" if parts.is_empty() else "Need " + " and ".join(parts)


func spend(cost: Dictionary) -> bool:
	if not can_afford(cost):
		return false
	for resource in cost:
		add(resource, -int(cost[resource]))
	return true


static func cost_text(cost: Dictionary) -> String:
	var parts := PackedStringArray()
	for resource in cost:
		parts.append("%d %s" % [int(cost[resource]), String(RESOURCE_NAMES.get(resource, resource)).to_lower()])
	return ", ".join(parts) if not parts.is_empty() else "free"


# --- Structures ----------------------------------------------------------------------

func add_structure(type: StringName, position: Vector3, yaw: float) -> Dictionary:
	var record := {
		"uid": _next_uid, "type": String(type), "position": [position.x, position.y, position.z],
		"yaw": yaw, "work": 0.0, "complete": false, "crop_planted_day": -1, "crop_planted_hour": 0.0,
	}
	_next_uid += 1
	structures.append(record)
	structure_added.emit(record)
	return record


## How lovely the village is: flowers, lanterns, the market, the
## founders' stone... Villagers are happier in a beautiful village.
func beauty() -> float:
	var total := 0.0
	for record in structures:
		if bool(record["complete"]):
			total += StructureCatalog.beauty(StringName(String(record["type"])))
	return total


func remove_structure(record: Dictionary) -> void:
	structures.erase(record)


func completed_structures(type: StringName) -> int:
	var total := 0
	for record in structures:
		if record["type"] == String(type) and bool(record["complete"]):
			total += 1
	return total


# --- Flags and objectives -------------------------------------------------------------

func set_flag(flag: StringName, value: Variant = true) -> void:
	flags[String(flag)] = value
	check_objectives()


func get_flag(flag: StringName, default: Variant = false) -> Variant:
	return flags.get(String(flag), default)


func increment(flag: StringName, amount: int = 1) -> void:
	set_flag(flag, int(get_flag(flag, 0)) + amount)


func current_objective() -> Dictionary:
	return OBJECTIVES[objective_index] if objective_index < OBJECTIVES.size() else {}


func is_week_complete() -> bool:
	return objective_index >= OBJECTIVES.size()


## Progress text for the current objective, e.g. "3 / 5 villagers".
func objective_progress() -> String:
	var objective := current_objective()
	if objective.is_empty():
		return ""
	match String(objective["id"]):
		"meet":
			return "%d / 5 villagers met" % villagers_met()
		"gather":
			return "Wood %d / 10   Stone %d / 6" % [mini(int(collected[&"wood"]), 10), mini(int(collected[&"stone"]), 6)]
		"farm_plot":
			return "Farm plots built: %d / 1" % completed_structures(&"farm_plot")
		"harvest":
			return "Harvests: %d / 1" % int(get_flag(&"harvests", 0))
		"help":
			return "Villagers helping: %d / 1" % int(get_flag(&"tasks_accepted", 0))
		"house":
			return "Houses built: %d / 1" % completed_structures(&"house")
		"meeting":
			return "Meeting held" if get_flag(&"meeting_held") else "Call it at the fire, 17:00-21:30"
	return ""


## Founders met (the first objective is about the five who were here first).
func villagers_met() -> int:
	var met := 0
	for villager in GameManager.villagers:
		if villager.person and not villager.person.founder:
			continue
		if villager.mind.get_familiarity(GameManager.PLAYER_ID) > 0:
			met += 1
	return met


func _objective_done(id: String) -> bool:
	match id:
		"meet":
			return villagers_met() >= 5
		"gather":
			return int(collected[&"wood"]) >= 10 and int(collected[&"stone"]) >= 6
		"farm_plot":
			return completed_structures(&"farm_plot") >= 1
		"harvest":
			return int(get_flag(&"harvests", 0)) >= 1
		"help":
			return int(get_flag(&"tasks_accepted", 0)) >= 1
		"house":
			return completed_structures(&"house") >= 1
		"meeting":
			return bool(get_flag(&"meeting_held"))
	return false


## Advances through every objective that is already satisfied.
func check_objectives() -> void:
	while not is_week_complete() and _objective_done(String(current_objective()["id"])):
		var title := String(current_objective()["title"])
		objective_index += 1
		objective_completed.emit(objective_index - 1, title)
	objective_changed.emit(objective_index)


# --- Persistence ---------------------------------------------------------------------

func to_dict() -> Dictionary:
	var inv := {}
	var col := {}
	for resource in RESOURCES:
		inv[String(resource)] = count(resource)
		col[String(resource)] = int(collected.get(resource, 0))
	return {
		"inventory": inv, "collected": col, "structures": structures.duplicate(true),
		"depleted": depleted.duplicate(), "objective_index": objective_index,
		"flags": flags.duplicate(true), "next_uid": _next_uid,
	}


func from_dict(data: Dictionary) -> void:
	reset()
	var inv: Dictionary = data.get("inventory", {})
	var col: Dictionary = data.get("collected", {})
	for resource in RESOURCES:
		inventory[resource] = int(inv.get(String(resource), 0))
		collected[resource] = int(col.get(String(resource), 0))
	var saved_structures: Variant = data.get("structures", [])
	structures = saved_structures.duplicate(true) if saved_structures is Array else []
	var saved_depleted: Variant = data.get("depleted", {})
	depleted = saved_depleted.duplicate() if saved_depleted is Dictionary else {}
	objective_index = int(data.get("objective_index", 0))
	var saved_flags: Variant = data.get("flags", {})
	flags = saved_flags.duplicate(true) if saved_flags is Dictionary else {}
	_next_uid = int(data.get("next_uid", structures.size() + 1))
