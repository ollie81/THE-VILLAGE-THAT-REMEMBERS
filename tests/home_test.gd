extends Node
## Headless test of what the owner hit on a real phone: building a cottage
## and going inside it, entering standing upright (never lying by the bed),
## walking round the furniture, sleeping in your own bed, saving indoors,
## moving and removing a cottage, a clearer Build menu and building site,
## and the village growing day by day.
## Run:  godot --headless --path . res://tests/home_test.tscn

var _failures: int = 0
var _main = null


func _ready() -> void:
	SaveService.enabled = false
	PopulationDirector.auto_arrivals = false
	Guide.rewards = false
	DailyGift.persist = false
	GameState.reset()
	_run.call_deferred()


func _check(condition: bool, description: String) -> void:
	if condition:
		print("  PASS  ", description)
	else:
		_failures += 1
		print("  FAIL  ", description)


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _fade() -> void:
	await get_tree().create_timer(Interiors.FADE_TIME * 2.0 + 0.3).timeout
	await _frames(3)


func _run() -> void:
	print("== Home test ==")
	WorldClock.day = 3
	WorldClock.set_time(10.0)
	WorldClock.set_time_scale(0.0)
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_main)
	await _frames(40)
	await _build_menu()
	var cottage := await _build_cottage()
	await _inside(cottage)
	await _own_house()
	await _move_and_remove(cottage)
	await _population()
	print("== %s: %d failure(s) ==" % ["PASSED" if _failures == 0 else "FAILED", _failures])
	get_tree().quit(0 if _failures == 0 else 1)


func _player() -> PlayerController:
	return GameManager.player


## True if the player is standing normally: no pose, no offset, on their feet.
func _standing() -> bool:
	var p := _player()
	return p.pose == &"" and p.model.position.length() < 0.01 and absf(p.model.rotation.x) < 0.01 and absf(p.model.rotation.z) < 0.01


# --- The Build menu and placing ---------------------------------------------------------

func _build_menu() -> void:
	var panels: GameplayPanels = _main.find_child("GameplayPanels", true, false)
	GameState.add(&"wood", 60)
	GameState.add(&"stone", 40)
	panels._category = "Homes"
	panels._toggle_build_menu()
	await _frames(3)
	var row: Button = panels._build_list.get_child(1)
	_check(row.icon != null, "every Build menu item has a picture of the real model")
	_check(row.text.contains("Cottage") and row.text.contains("Needs 18 wood, 8 stone") and row.text.contains("tap Build 6 times"),
		"and says exactly what it needs and what to do next: %s" % row.text.replace("\n", " / "))
	_check(panels._tab_buttons["Homes"].icon != null, "the tabs have pictures too")
	panels._build_menu.visible = false


func _build_cottage() -> PlacedStructure:
	var panels: GameplayPanels = _main.find_child("GameplayPanels", true, false)
	var player := _player()
	player.global_position = VillageLayout.ground_point(-30.0, 18.0) + Vector3(0, 0.5, 0)
	await _frames(10)
	BuildMode.instance.start(&"cottage")
	await _frames(3)
	_check(BuildMode.instance.active and BuildMode.instance.reason == "", "the cottage preview finds free ground near you")
	await _frames(2)
	_check(panels._placement_reason.text.contains("Good spot") and panels._placement_hint.text.contains("18 wood"),
		"the placing bar says it fits and what it costs: %s" % panels._placement_reason.text)
	var count := GameState.structures.size()
	BuildMode.instance.confirm()
	await _frames(4)
	_check(GameState.structures.size() == count + 1, "tapping Place puts down a building site")
	var site: PlacedStructure = null
	for s in get_tree().get_nodes_in_group("placed_structures"):
		if s.get_type() == &"cottage":
			site = s
	_check(site._label.text.contains("0 of 6 done") and site._label.text.contains("Next: corner posts") and site._bar != null,
		"the site shows its progress and the next stage: %s" % site._label.text.replace("\n", " / "))
	_check(site.get_interaction_verb() == "Build" and site.get_interaction_prompt().contains("corner posts"), "and the button says Build (%s)" % site.get_interaction_prompt())
	var fractions: Array = []
	for i in 6:
		site.use(player)
		await _frames(2)
		fractions.append(snappedf(site.work_fraction(), 0.01))
		if i == 2:
			_check(site._label.text.contains("3 of 6 done") and site._label.text.contains("roof beams") and site._bar_fill.scale.x > 0.45,
				"each tap adds a stage and fills the bar: %s" % site._label.text.replace("\n", " / "))
	_check(site.is_complete() and site._bar == null, "six taps finish the cottage (%s)" % str(fractions))
	_check(site.get_interaction_verb() == "Enter" and site.get_interaction_prompt().begins_with("Enter the cottage"), "a finished cottage has an entrance: %s" % site.get_interaction_prompt())
	return site


# --- Inside a cottage -------------------------------------------------------------------

func _inside(cottage: PlacedStructure) -> void:
	var player := _player()
	var interiors := Interiors.instance
	# Even after lying down outside, you walk in on your feet.
	player.global_position = cottage.doorstep() + Vector3(0, 0.4, 0)
	await _frames(5)
	player.lie_down()
	_check(player.pose == &"sleep", "(lying down outside first)")
	cottage.use(player)
	await _fade()
	_check(interiors.is_inside() and interiors.current == "cottage_%d" % int(cottage.record["uid"]), "using the cottage takes you inside it")
	_check(_standing(), "you come in standing upright, not lying down")
	var spawn := Interiors.ROOM_ORIGIN + Interiors.SPAWN
	_check(Vector2(player.global_position.x - spawn.x, player.global_position.z - spawn.z).length() < 0.3, "just inside the door")
	_check(_clear_of_furniture(player.global_position), "with nothing in the way: no furniture or wall where you stand")
	var room: Node3D = interiors._room
	_check(room.find_children("*", "MeshInstance3D", true, false).size() >= 1 and room.find_children("*", "OmniLight3D", true, false).size() == 2,
		"a furnished room, lit by the hearth and a lamp")
	var config := interiors.home_config(interiors.current)
	var again := interiors.home_config(interiors.current)
	_check(config == again, "each cottage always gets its own same layout (saved through its number)")
	# Walk round the room.
	var chair: UsableObject = room.find_child("Chair", true, false)
	var reached := await _walk_to(chair.global_position)
	_check(reached, "you can walk to the table")
	reached = await _walk_to(room.find_child("ExitDoor", true, false).global_position + Vector3(0, 0, -0.6))
	_check(reached, "and back to the door")
	# Lying down here isn't allowed (not your home).
	var actions: ActionsMenu = _main.find_child("ActionsMenu", true, false)
	actions.do(&"sleep")
	await _frames(3)
	_check(player.pose == &"", "you don't lie on someone else's floor")
	# Saving indoors.
	var saved := player.get_save_data()
	var at := Vector3(saved["position"][0], saved["position"][1], saved["position"][2])
	_check(at.distance_to(cottage.doorstep()) < 0.5, "saving indoors saves the cottage's doorstep")
	interiors.leave()
	await _fade()
	_check(not interiors.is_inside() and _standing() and player.global_position.distance_to(cottage.doorstep()) < 1.0, "leaving puts you on the doorstep, standing")
	# In and out again and again.
	var ok := true
	for i in 4:
		cottage.use(player)
		await _fade()
		ok = ok and interiors.is_inside() and _standing() and _clear_of_furniture(player.global_position)
		interiors.leave()
		await _fade()
		ok = ok and not interiors.is_inside() and _standing()
	_check(ok and interiors.find_children("Room_*", "", false, false).is_empty(), "in and out four more times: always standing, nothing left behind")


## No furniture or wall within the player's reach at `at`.
func _clear_of_furniture(at: Vector3) -> bool:
	var space := get_viewport().world_3d.direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.6
	query.shape = capsule
	query.transform = Transform3D(Basis.IDENTITY, Vector3(at.x, Interiors.ROOM_ORIGIN.y + 0.9, at.z))
	query.collision_mask = 1
	return space.intersect_shape(query, 4).is_empty()


## Steers the player with the touch stick until close to `target`.
func _walk_to(target: Vector3) -> bool:
	var player := _player()
	for f in 400:
		var to := target - player.global_position
		to.y = 0.0
		if to.length() < 0.9:
			InputRouter.touch_move = Vector2.ZERO
			return true
		var basis: Basis = get_viewport().get_camera_3d().global_transform.basis
		var fwd := -basis.z
		fwd.y = 0
		fwd = fwd.normalized()
		var right := basis.x
		right.y = 0
		right = right.normalized()
		var dir := to.normalized()
		InputRouter.touch_move = Vector2(dir.dot(right), -dir.dot(fwd)) * 0.7
		await get_tree().physics_frame
	InputRouter.touch_move = Vector2.ZERO
	return false


# --- Your own house: bed, hearth, chest ---------------------------------------------------

func _own_house() -> void:
	var player := _player()
	var interiors := Interiors.instance
	interiors.enter("player", player.global_position, 0.0)
	await _fade()
	var room: Node3D = interiors._room
	_check(room.find_child("Bed", false, false) != null and room.find_child("Hearth", false, false) != null and room.find_child("Chest", false, false) != null,
		"your house has your bed, a hearth to cook at and a chest")
	var reached := await _walk_to(room.find_child("Bed", false, false).global_position)
	_check(reached, "you can walk to your bed")
	_check(_standing(), "walking up to the bed doesn't make you lie down (only tapping Sleep does)")
	WorldClock.set_time(22.0)
	var day := WorldClock.day
	var bed: UsableObject = room.find_child("Bed", false, false)
	bed.use.call(player)
	await _frames(5)
	var on_mattress := player.pose == &"sleep" and player.model.position.y > 0.4
	_check(on_mattress, "tapping Sleep lies you down on the mattress")
	await get_tree().create_timer(1.0 + Interiors.FADE_TIME * 2.0 + 0.4).timeout
	await _frames(3)
	_check(WorldClock.day == day + 1 and WorldClock.time_of_day < 8.0, "and you wake up the next morning")
	_check(_standing() and _clear_of_furniture(player.global_position), "standing beside the bed, not in it")
	# The actions menu's Sleep at home also means your bed.
	WorldClock.set_time(22.0)
	var actions: ActionsMenu = _main.find_child("ActionsMenu", true, false)
	actions.do(&"sleep")
	await _frames(5)
	_check(player.pose == &"sleep" and player.model.position.y > 0.4, "choosing Sleep from Actions at home puts you in your bed too")
	await get_tree().create_timer(1.0 + Interiors.FADE_TIME * 2.0 + 0.4).timeout
	await _frames(3)
	_check(_standing() and not GameState.get_flag(&"slept_outside"), "(and nobody thinks you slept outside)")
	interiors.leave()
	await _fade()
	WorldClock.set_time(10.0)


# --- Moving and removing a cottage --------------------------------------------------------

func _move_and_remove(cottage: PlacedStructure) -> void:
	var player := _player()
	var old_step := cottage.doorstep()
	var id := cottage.interior_id()
	cottage.move_to(cottage.global_position + Vector3(0, 0, -9.0), cottage.rotation.y)
	await _frames(3)
	_check(cottage.doorstep().distance_to(old_step) > 5.0 and cottage.interior_id() == id, "a moved cottage takes its door (and its room) with it")
	cottage.use(player)
	await _fade()
	Interiors.instance.leave()
	await _fade()
	_check(player.global_position.distance_to(cottage.doorstep()) < 1.0, "and you come out at its new door")
	BuildMode.instance.remove(cottage)
	await _frames(3)
	_check(not is_instance_valid(cottage) and not GameState.structures.any(func(r): return r["type"] == "cottage"), "a removed cottage is gone, door and all")


# --- The village grows ----------------------------------------------------------------------

func _population() -> void:
	var director := PopulationDirector.instance
	var start := Population.count()
	_check(director.arrival_chance() == 1.0, "while the village is small, a traveller is sure to come each day")
	var traveller := director.bring_traveller()
	await _frames(5)
	_check(traveller.status == Person.STATUS_VISITOR, "a traveller arrives: %s" % traveller.full_name())
	# Nobody talks to them: next morning a founder offers them a place.
	WorldClock.advance(24.0)
	await _frames(3)
	_check(traveller.is_resident() and Population.count() == start + 1, "if you're busy, a founder welcomes them the next day (they don't just leave)")
	var arrived := 0
	for d in 4:
		var settle := 0
		while director.is_spawning() and settle < 3000:
			await _frames(1)
			settle += 1
		if director.arrival_chance() > 0.0:
			director.bring_traveller()
			arrived += 1
		await _frames(3)
		WorldClock.advance(24.0)
		await _frames(3)
	var wait := 0
	while director.is_spawning() and wait < 3000:
		await _frames(1)
		wait += 1
	_check(arrived == 4 and Population.count() >= start + 5, "day after day the village grows (%d people now)" % Population.count())
	var looks := {}
	var jobs := {}
	for person: Person in Population.residents():
		if not person.founder:
			looks[str(person.appearance)] = true
			jobs[person.profession] = true
	_check(looks.size() == Population.residents().filter(func(p): return not p.founder).size(), "no two newcomers look the same")
	_check(jobs.size() >= 3, "and they do different jobs: %s" % str(jobs.keys()))
