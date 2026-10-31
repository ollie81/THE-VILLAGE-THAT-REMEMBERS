class_name WorldObjects
extends Node3D
## Things in the village the player can use: the fire (call a village
## meeting), the workshop bench (craft tools) and the storehouse door (check
## the village stores).

const TOOLS_COST := {&"wood": 4, &"stone": 3}

var meeting: VillageMeeting


func _ready() -> void:
	name = "WorldObjects"
	meeting = VillageMeeting.new()
	add_child(meeting)
	_add_object("FirePit", Vector3.ZERO, 2.0, _fire_prompt, _fire_verb, _use_fire)
	var workshop := VillageLayout.get_building("workshop")
	# The bench itself (where villagers working at the workshop look), not
	# the spot where they stand.
	var bench: Vector3 = VillageLayout.get_locations()["workshop"]["looks"][0]
	_add_object("WorkshopBench", bench, 1.3, _bench_prompt, func(): return "Craft", _use_bench)
	var storage_door: Vector3 = VillageLayout.get_nav_nodes()["storage_door"]
	_add_object("StorehouseDoor", storage_door, 1.4, func(): return "Check the village stores", func(): return "Open", _use_storage)
	if workshop.is_empty():
		push_warning("No workshop in the layout")


## A small object with an interaction area and callables for its behaviour.
func _add_object(object_name: String, at: Vector3, radius: float, prompt: Callable, verb: Callable, use: Callable) -> void:
	var holder := UsableObject.new()
	holder.name = object_name
	holder.prompt = prompt
	holder.verb = verb
	holder.use = use
	holder.position = VillageLayout.ground_point(at.x, at.z)
	add_child(holder)
	var interactable := Interactable.new()
	interactable.radius = radius
	interactable.handler = holder
	interactable.interacted.connect(func(actor): use.call(actor))
	holder.add_child(interactable)


# --- Fire: village meeting --------------------------------------------------------

func _fire_prompt() -> String:
	if meeting.running:
		return "The village is gathering..."
	if not VillageMeeting.is_meeting_time():
		return "Village fire  (call a meeting in the evening)"
	return "Call a village meeting"


func _fire_verb() -> String:
	return "Meet" if VillageMeeting.is_meeting_time() else "Look"


func _use_fire(_actor) -> void:
	if meeting.running:
		GameManager.notify("Everyone is on their way to the fire.")
	elif not VillageMeeting.is_meeting_time():
		GameManager.notify("Meetings are held in the evening, between 17:00 and 21:30.")
	else:
		meeting.call_meeting()


# --- Workshop: tools -------------------------------------------------------------

func _bench_prompt() -> String:
	if GameState.get_flag(&"has_tools"):
		return "Workshop bench  (your tools are ready)"
	return "Craft better tools  (%s)" % GameState.cost_text(TOOLS_COST)


func _use_bench(actor) -> void:
	if GameState.get_flag(&"has_tools"):
		GameManager.notify("Your axe and pick are sharp. Every chop and strike gives one more.")
		return
	if not GameState.spend(TOOLS_COST):
		GameManager.notify(GameState.missing_text(TOOLS_COST) + " to craft tools.")
		return
	if actor and actor.has_method("perform_action"):
		actor.perform_action(&"work", 1.5, global_position)
	GameState.set_flag(&"has_tools")
	GameManager.notify("You crafted an axe and a pick. Trees and rocks now give one more each time.")


# --- Storehouse --------------------------------------------------------------------

func _use_storage(_actor) -> void:
	var parts := PackedStringArray()
	for resource in GameState.RESOURCES:
		parts.append("%s %d" % [GameState.RESOURCE_NAMES[resource], GameState.count(resource)])
	GameManager.notify("Village stores: " + ", ".join(parts))
