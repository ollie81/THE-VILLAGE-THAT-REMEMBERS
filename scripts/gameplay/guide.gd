class_name Guide
extends Node3D
## Shows the way to the current objective: a marker floating over the next
## thing to do (a villager to meet, a tree to chop, your building site...),
## which the HUD turns into an arrow at the screen edge when it's off-screen,
## and which Build item to choose. Finished objectives give a small reward.

static var instance: Guide

## What finishing each objective gives (and the thank-you line).
const REWARDS := {
	"meet": {"items": {&"food": 3}, "text": "The villagers bring you a little food to welcome you."},
	"gather": {"items": {&"wood": 6, &"stone": 4}, "text": "Tomas adds some of his own wood and stone to your pile."},
	"farm_plot": {"items": {&"herbs": 2}, "text": "Nia gives you seedlings for the garden."},
	"harvest": {"items": {&"food": 4}, "text": "Your first harvest! Mara bakes bread with it."},
	"help": {"items": {&"wood": 8}, "text": "Elias drops off a bundle of planks."},
	"house": {"items": {&"food": 5, &"herbs": 2}, "text": "Everyone brings something for your new home."},
	"meeting": {"items": {&"wood": 10, &"stone": 10}, "text": "The village pools its supplies for whatever you build next."},
}

## Where to go: a world position (Vector3.INF if none) and what it is.
var target: Vector3 = Vector3.INF
var target_label: String = ""
## A thing to build from the Build menu ("" if none), e.g. &"farm_plot".
var wanted_build: StringName = &""
## The next step in a few words, shown under the objective.
var step: String = ""
var enabled: bool = true
## Tests that count resources exactly switch the objective rewards off.
static var rewards: bool = true

var _marker: Label3D
var _timer: float = 0.0
var _bob: float = 0.0


func _ready() -> void:
	name = "Guide"
	instance = self
	_marker = Label3D.new()
	_marker.name = "GuideMarker"
	_marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_marker.no_depth_test = true
	_marker.fixed_size = true
	_marker.pixel_size = 0.0012
	_marker.font_size = 40
	_marker.outline_size = 14
	_marker.modulate = Color(1.0, 0.86, 0.35)
	_marker.outline_modulate = Color(0.15, 0.1, 0.05, 0.9)
	_marker.render_priority = 10
	_marker.visible = false
	add_child(_marker)
	GameState.objective_completed.connect(_on_objective_completed)


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		_timer = 0.4
		refresh()
	_bob += delta
	var show := enabled and target != Vector3.INF and not GameManager.is_in_conversation() \
		and GameManager.camera_mode == GameManager.CameraMode.EXPLORATION
	_marker.visible = show and _near_enough()
	if _marker.visible:
		_marker.text = "%s\n▼" % target_label
		_marker.global_position = target + Vector3(0, 2.6 + sin(_bob * 3.0) * 0.12, 0)


func _near_enough() -> bool:
	var player = GameManager.player
	return player != null and player.global_position.distance_to(target) > 1.8


## Works out the next step for the current objective.
func refresh() -> void:
	target = Vector3.INF
	target_label = ""
	wanted_build = &""
	step = ""
	var player = GameManager.player
	if player == null:
		return
	if GameState.is_week_complete():
		_adventure(player.global_position)
		return
	var from: Vector3 = player.global_position
	match String(GameState.current_objective()["id"]):
		"meet":
			var who = _nearest_villager(from, true)
			if who:
				_aim(who.global_position, who.data.display_name, "Find %s and tap Talk." % who.data.display_name)
		"gather":
			var wood := int(GameState.collected[&"wood"])
			var stone := int(GameState.collected[&"stone"])
			if wood < 10:
				_aim_resource(from, "tree", "Walk up to the tree and tap Chop (%d / 10 wood)." % wood)
			elif stone < 6:
				_aim_resource(from, "rock", "Walk up to the rock and tap Mine (%d / 6 stone)." % stone)
		"farm_plot":
			_aim_build(from, &"farm_plot", "Farm plot")
		"harvest":
			var plot := _nearest_structure(from, &"farm_plot", true)
			if plot:
				var verb := "Harvest" if plot.is_ripe() else ("Wait for the crops to grow" if plot.is_planted() else "Plant seeds")
				_aim(plot.global_position, "Farm plot", "%s at your farm plot." % verb)
		"help":
			var helper = _nearest_villager(from, false)
			if helper:
				_aim(helper.global_position, helper.data.display_name, "Talk to %s and ask for help with a task." % helper.data.display_name)
		"house":
			_aim_build(from, &"house", "House")
		"meeting":
			var hour := WorldClock.time_of_day
			_aim(Vector3.ZERO, "Village fire", "Call a meeting at the fire%s." % ("" if hour >= 17.0 and hour < 21.5 else " between 17:00 and 21:30"))


## After the first week: forge a sword, then chase the thornlings off.
func _adventure(_from: Vector3) -> void:
	if not PlayerCombat.is_armed():
		var bench := get_tree().current_scene.find_child("WorkshopBench", true, false) as Node3D
		if bench:
			_aim(bench.global_position, "Workshop", "Forge a sword and shield at the workshop (%s)." % GameState.cost_text(WorldObjects.SWORD_COST))
		return
	var woods := Thornwood.instance
	if woods and woods.mission_active():
		_aim(woods.center, "Thornlings", "Chase the thornlings out of the west woods.")


func _aim(at: Vector3, label: String, next_step: String) -> void:
	target = at
	target_label = label
	step = next_step


func _aim_resource(from: Vector3, kind: String, next_step: String) -> void:
	var best := Vector3.INF
	for node in ResourceSpawner.nodes:
		if is_instance_valid(node) and node.uses_left > 0 and (node.kind == &"rock") == (kind == "rock") and node.kind != &"herbs":
			if best == Vector3.INF or from.distance_to(node.global_position) < from.distance_to(best):
				best = node.global_position
	var wild := NatureSpawner.nearest_workable(from, 80.0, kind)
	if not wild.is_empty():
		var pos: Vector3 = wild["pos"]
		if best == Vector3.INF or from.distance_to(pos) < from.distance_to(best):
			best = pos
	if best != Vector3.INF:
		_aim(best, "Chop" if kind == "tree" else "Mine", next_step)


## Build something: gather what's missing, choose it in the Build menu, then
## work on the site until it's done.
func _aim_build(from: Vector3, type: StringName, name_text: String) -> void:
	var site := _nearest_structure(from, type, false)
	if site and not site.is_complete():
		_aim(site.global_position, name_text, "Tap Build at the site until your %s is finished." % name_text.to_lower())
		return
	var cost: Dictionary = StructureCatalog.info(type)["cost"]
	if not GameState.can_afford(cost):
		var short_wood := int(cost.get(&"wood", 0)) > GameState.count(&"wood")
		_aim_resource(from, "tree" if short_wood else "rock",
			"%s for a %s." % [GameState.missing_text(cost), name_text.to_lower()])
		return
	wanted_build = type
	step = "Tap Build and choose %s." % name_text


func _nearest_villager(from: Vector3, unmet_founders: bool):
	var best = null
	for villager in GameManager.villagers:
		if not is_instance_valid(villager) or not villager.visible:
			continue
		if unmet_founders:
			if villager.person and not villager.person.founder:
				continue
			if villager.mind.get_familiarity(GameManager.PLAYER_ID) > 0:
				continue
		if best == null or from.distance_to(villager.global_position) < from.distance_to(best.global_position):
			best = villager
	return best


func _nearest_structure(from: Vector3, type: StringName, complete: bool) -> PlacedStructure:
	var best: PlacedStructure = null
	for s in get_tree().get_nodes_in_group("placed_structures"):
		var structure := s as PlacedStructure
		if structure == null or structure.get_type() != type or (complete and not structure.is_complete()):
			continue
		if best == null or from.distance_to(structure.global_position) < from.distance_to(best.global_position):
			best = structure
	return best


func _on_objective_completed(index: int, _title: String) -> void:
	# After the objective check has finished (rewards add items, which checks again).
	_reward.call_deferred(index)


func _reward(index: int) -> void:
	if not rewards or index < 0 or index >= GameState.OBJECTIVES.size():
		return
	var done: Dictionary = GameState.OBJECTIVES[index]
	var reward: Dictionary = REWARDS.get(String(done["id"]), {})
	if reward.is_empty() or GameState.get_flag(StringName("rewarded_" + String(done["id"]))):
		return
	GameState.set_flag(StringName("rewarded_" + String(done["id"])))
	var items: Dictionary = reward["items"]
	for resource in items:
		GameState.add(resource, int(items[resource]))
	GameManager.notify("%s  (+%s)" % [reward["text"], GameState.cost_text(items)])
	Sounds.play("built", null, -4.0)
	refresh()
