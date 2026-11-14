class_name WildHarvest
extends Node3D
## Lets the player chop any tree and mine any rock out in the world, not just
## the marked ones. A single interaction point follows the player and sits on
## the nearest wild tree or rock. A tree takes three chops to fall (two wood
## each), a rock three blows; they grow back after a few days.

const REACH := 3.2
const HITS := 3
const YIELD := 2
const REGROW_DAYS := 3
const REGROW_HOUR := 6

var interactable: Interactable
var _entry: Dictionary = {}
var _search_timer: float = 0.0


func _ready() -> void:
	name = "WildHarvest"
	interactable = Interactable.new()
	interactable.radius = 1.1
	interactable.handler = self
	interactable.interacted.connect(_on_interacted)
	add_child(interactable)
	WorldClock.hour_changed.connect(_on_hour_changed)
	WorldClock.day_changed.connect(func(_d): _on_hour_changed(WorldClock.get_hour()))


func _physics_process(delta: float) -> void:
	_search_timer -= delta
	if _search_timer > 0.0:
		return
	_search_timer = 0.2
	var player = GameManager.player
	if player == null:
		return
	_entry = NatureSpawner.nearest_workable(player.global_position, REACH)
	if not _entry.is_empty():
		global_position = _entry["pos"]


func _is_tree() -> bool:
	return not _entry.is_empty() and String(_entry["kind"]) != "rock"


func can_interact(_actor) -> bool:
	return not _entry.is_empty() and NatureSpawner.is_workable(_entry)


func amount() -> int:
	return YIELD + (1 if GameState.get_flag(&"has_tools") else 0)


func get_interaction_verb() -> String:
	return "Chop" if _is_tree() else "Mine"


func get_interaction_prompt() -> String:
	var left := HITS - int(_entry.get("hits", 0))
	if _is_tree():
		return "Chop tree  (+%d wood%s)" % [amount(), ", it falls" if left <= 1 else ""]
	return "Mine rock  (+%d stone%s)" % [amount(), ", it breaks up" if left <= 1 else ""]


func _on_interacted(actor: Node) -> void:
	harvest(actor)


## One chop or blow. Returns the amount gathered.
func harvest(actor: Node = null) -> int:
	if not can_interact(actor):
		return 0
	var entry := _entry
	var tree := _is_tree()
	var at: Vector3 = entry["pos"]
	if actor and actor.has_method("perform_action"):
		actor.perform_action(&"work", 0.9 if tree else 1.0, at, &"axe" if tree else &"pickaxe")
	var resource: StringName = &"wood" if tree else &"stone"
	var gained := amount()
	GameState.add(resource, gained)
	if is_inside_tree():
		get_tree().create_timer(0.6).timeout.connect(func():
			Sounds.play("chop" if tree else "stone", at)
			Sounds.play("pickup", at, -8.0))
		FloatingText.spawn(get_parent(), at + Vector3(0, 2.2 if tree else 1.2, 0),
			"+%d %s" % [gained, GameState.RESOURCE_NAMES[resource]])
	entry["hits"] = int(entry.get("hits", 0)) + 1
	if int(entry["hits"]) >= HITS:
		NatureSpawner.fell(entry, WorldClock.day + REGROW_DAYS)
		GameManager.notify("The tree comes down. It'll grow back in a few days." if tree
			else "The rock breaks apart. The ground will turn up more stone in a few days.")
		_entry = {}
	return gained


## From the morning on (also after time jumps such as sleeping or being away).
func _on_hour_changed(hour: int) -> void:
	if hour >= REGROW_HOUR:
		NatureSpawner.regrow(WorldClock.day)
