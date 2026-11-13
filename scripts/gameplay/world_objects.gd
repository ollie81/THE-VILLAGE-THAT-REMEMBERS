class_name WorldObjects
extends Node3D
## Things in the village the player can use: the fire (call a village
## meeting), the workshop bench (craft tools) and the storehouse door (check
## the village stores).

const TOOLS_COST := {&"wood": 4, &"stone": 3}
const SWORD_COST := {&"wood": 8, &"stone": 6}
const EDGE_COST := {&"wood": 6, &"stone": 12}

var meeting: VillageMeeting


func _ready() -> void:
	name = "WorldObjects"
	meeting = VillageMeeting.new()
	add_child(meeting)
	_add_object("FirePit", Vector3.ZERO, 2.0, _fire_prompt, _fire_verb, _use_fire)
	# The fire crackles; you hear it as you come near.
	var crackle := AudioStreamPlayer3D.new()
	crackle.name = "FireSound"
	crackle.stream = Sounds.fire_stream()
	crackle.bus = Sounds.BUS_AMBIENCE
	crackle.unit_size = 3.0
	crackle.max_distance = 28.0
	crackle.volume_db = -4.0
	crackle.autoplay = true
	get_node("FirePit").add_child(crackle)
	crackle.position = Vector3(0, 0.5, 0)
	var workshop := VillageLayout.get_building("workshop")
	# The bench itself (where villagers working at the workshop look), not
	# the spot where they stand.
	var bench: Vector3 = VillageLayout.get_locations()["workshop"]["looks"][0]
	_add_object("WorkshopBench", bench, 1.3, _bench_prompt, func(): return "Craft", _use_bench)
	var storage_door: Vector3 = VillageLayout.get_nav_nodes()["storage_door"]
	_add_object("StorehouseDoor", storage_door, 1.4, func(): return "Check the village stores", func(): return "Open", _use_storage)
	if workshop.is_empty():
		push_warning("No workshop in the layout")
	# The logs around the fire: sit down.
	var seats := VillageLayout.plaza_seats()
	for i in range(0, seats.size(), 2):
		var pair: Array = [seats[i], seats[i + 1]]
		var middle: Vector3 = (pair[0]["position"] + pair[1]["position"]) * 0.5
		_add_object("Log%d" % (i / 2), middle, 1.3, func(): return "Sit on the log", func(): return "Sit",
			func(actor): _sit_on(actor, pair))


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


## Sits on whichever seat is nearest (and free of villagers).
func _sit_on(actor, seats: Array) -> void:
	if actor == null or not actor.has_method("sit"):
		return
	var best: Dictionary = {}
	var best_distance := INF
	for seat: Dictionary in seats:
		var at: Vector3 = seat["position"]
		var taken := false
		for villager in GameManager.villagers:
			if villager.visible and Vector2(villager.global_position.x - at.x, villager.global_position.z - at.z).length() < 0.4:
				taken = true
		var distance: float = actor.global_position.distance_to(at)
		if not taken and distance < best_distance:
			best_distance = distance
			best = seat
	if best.is_empty():
		GameManager.notify("Someone's already sitting there.")
		return
	actor.sit(best)


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

## The bench's recipes, in order: tools, then a sword and shield, then (after
## the thornlings are chased off) a steel edge for the sword.
func _next_recipe() -> String:
	if not GameState.get_flag(&"has_tools"):
		return "tools"
	if not GameState.get_flag(&"has_sword"):
		return "sword"
	if not GameState.get_flag(&"sword_upgraded") and Thornwood.instance and Thornwood.instance.mission_done:
		return "edge"
	return ""


func _bench_prompt() -> String:
	match _next_recipe():
		"tools":
			return "Craft better tools  (%s)" % GameState.cost_text(TOOLS_COST)
		"sword":
			return "Forge a sword and shield  (%s)" % GameState.cost_text(SWORD_COST)
		"edge":
			return "Put a steel edge on your sword  (%s; hits twice as hard)" % GameState.cost_text(EDGE_COST)
	return "Workshop bench  (your tools and sword are ready)"


func _use_bench(actor) -> void:
	match _next_recipe():
		"sword":
			if not GameState.spend(SWORD_COST):
				GameManager.notify(GameState.missing_text(SWORD_COST) + " to forge a sword and shield.")
				return
			if actor and actor.has_method("perform_action"):
				actor.perform_action(&"work", 1.5, global_position)
			GameState.set_flag(&"has_sword")
			if actor and actor.get("combat") and actor.combat:
				actor.combat.refresh_equipment()
			GameManager.notify("You forged a sword and a shield. (F or Attack to swing, Q or Block to guard, C or Dodge to dodge.)")
			if Thornwood.instance:
				Thornwood.instance.start_mission()
			return
		"edge":
			if not GameState.spend(EDGE_COST):
				GameManager.notify(GameState.missing_text(EDGE_COST) + " for a steel edge.")
				return
			if actor and actor.has_method("perform_action"):
				actor.perform_action(&"work", 1.5, global_position)
			GameState.set_flag(&"sword_upgraded")
			GameManager.notify("A steel edge! Your sword now hits twice as hard.")
			return
		"":
			GameManager.notify("Your tools are sharp and your sword is ready.")
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
