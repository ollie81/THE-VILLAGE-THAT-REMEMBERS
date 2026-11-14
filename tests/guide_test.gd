extends Node
## Headless test of the first-day guide: it points at the next thing to do
## for each objective (who to meet, which tree to chop, what to build and
## where the site is), the edge arrow appears when that's off-screen, the
## Build menu opens on what's wanted, and finished objectives give rewards.
## Run:  godot --headless --path . res://tests/guide_test.tscn

var _failures: int = 0
var _main = null


func _ready() -> void:
	SaveService.enabled = false
	PopulationDirector.auto_arrivals = false
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


func _run() -> void:
	print("== Guide test ==")
	WorldClock.day = 1
	WorldClock.set_time(9.0)
	WorldClock.set_time_scale(0.0)
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_main)
	await _frames(40)
	var guide := Guide.instance
	var player = GameManager.player
	var panels: GameplayPanels = _main.find_child("GameplayPanels", true, false)
	var arrow: GuideArrow = _main.find_child("GuideArrow", true, false)
	_check(guide != null and arrow != null, "the guide and its arrow are in the game")

	# --- Day 1: meet the villagers ---------------------------------------------------------
	guide.refresh()
	var first = null
	for v in GameManager.villagers:
		if guide.target_label == v.data.display_name:
			first = v
	_check(first != null and guide.step.contains(first.data.display_name), "it points to someone to meet: %s" % guide.step)
	await _frames(2)
	_check(panels._objective_hint.text == guide.step, "and says so under the objective")
	# Look away: the arrow shows at the screen edge, pointing the right way.
	var rig: CameraRig = _main.camera_rig
	var to: Vector3 = guide.target - player.global_position
	rig.yaw = atan2(to.x, to.z)  # facing away
	await _frames(5)
	_check(arrow.showing, "with an arrow at the edge of the screen when they're behind you")
	rig.yaw = atan2(-to.x, -to.z)
	await _frames(5)
	_check(not arrow.showing and guide._marker.visible, "and a marker over them when they're in view")
	first.mind.record_interaction(GameManager.PLAYER_ID, "talk", 1, 9.0)
	guide.refresh()
	_check(guide.target_label != first.data.display_name, "after meeting %s it points to the next person (%s)" % [first.data.display_name, guide.target_label])
	var food := GameState.count(&"food")
	for v in GameManager.villagers:
		if v.mind.get_familiarity(GameManager.PLAYER_ID) == 0:
			v.mind.record_interaction(GameManager.PLAYER_ID, "talk", 1, 9.0)
	GameState.check_objectives()
	await _frames(3)
	_check(String(GameState.current_objective()["id"]) == "gather" and GameState.count(&"food") == food + 3,
		"meeting everyone is rewarded (+3 food)")

	# --- Gathering ----------------------------------------------------------------------------
	guide.refresh()
	_check(guide.target_label == "Chop" and guide.target != Vector3.INF, "next it points to a tree: %s" % guide.step)
	var tree_at := guide.target
	var nearest := INF
	for entry: Dictionary in NatureSpawner._clearable:
		if NatureSpawner.is_workable(entry) and entry["kind"] != "rock":
			nearest = minf(nearest, player.global_position.distance_to(entry["pos"]))
	_check(player.global_position.distance_to(tree_at) <= nearest + 0.01, "the nearest one (%.0f m)" % player.global_position.distance_to(tree_at))
	GameState.add(&"wood", 10)
	guide.refresh()
	_check(guide.target_label == "Mine", "with enough wood, a rock: %s" % guide.step)
	GameState.add(&"stone", 6)
	await _frames(3)

	# --- Farm plot: the Build menu -------------------------------------------------------------
	guide.refresh()
	_check(String(GameState.current_objective()["id"]) == "farm_plot" and guide.wanted_build == &"farm_plot" and guide.step.contains("Build"),
		"then it says to tap Build and choose a farm plot")
	panels._category = "Homes"
	panels._toggle_build_menu()
	await _frames(2)
	var row: Button = panels._build_list.get_child(0)
	_check(panels._category == "Food" and row.text.contains("your next step"), "the Build menu opens on Food with the farm plot marked")
	panels._build_menu.visible = false
	var record := GameState.add_structure(&"farm_plot", VillageLayout.ground_point(-26.0, 30.0), 0.0)
	await _frames(3)
	guide.refresh()
	var site: PlacedStructure = null
	for s in get_tree().get_nodes_in_group("placed_structures"):
		if s.record == record:
			site = s
	_check(guide.target.distance_to(site.global_position) < 0.1 and guide.step.contains("Tap Build at the site"), "once placed, it points to the site: %s" % guide.step)
	while not site.is_complete():
		site.add_work(1.0)
	await _frames(3)
	guide.refresh()
	_check(String(GameState.current_objective()["id"]) == "harvest" and guide.step.contains("Plant"), "then: %s" % guide.step)

	# --- The house: not enough materials ---------------------------------------------------------
	GameState.objective_index = GameState.OBJECTIVES.map(func(o): return o["id"]).find("house")
	GameState.inventory[&"wood"] = 2
	GameState.inventory[&"stone"] = 0
	guide.refresh()
	_check(guide.wanted_build == &"" and guide.target_label == "Chop" and guide.step.contains("more wood"),
		"short of wood for a house, it sends you to a tree: %s" % guide.step)

	# --- The meeting -------------------------------------------------------------------------
	GameState.objective_index = GameState.OBJECTIVES.size() - 1
	guide.refresh()
	_check(guide.target.length() < 0.1 and guide.target_label == "Village fire", "for the meeting, the fire: %s" % guide.step)
	GameState.set_flag(&"meeting_held")
	GameState.check_objectives()
	await _frames(3)
	guide.refresh()
	_check(GameState.is_week_complete() and guide.target_label == "Workshop" and guide.step.begins_with("At the workshop"),
		"after the week, it points to the next adventure: %s" % guide.step)
	GameState.set_flag(&"has_sword")
	Thornwood.instance.mission_started = true
	guide.refresh()
	_check(guide.target_label == "Thornlings" and guide.target.distance_to(Thornwood.instance.center) < 0.1, "then to the thornlings in the west woods")
	Thornwood.instance.mission_done = true
	guide.refresh()
	await _frames(2)
	_check(guide.target == Vector3.INF and not arrow.showing, "and steps aside when there's nothing left to do")

	print("== %s: %d failure(s) ==" % ["PASSED" if _failures == 0 else "FAILED", _failures])
	get_tree().quit(0 if _failures == 0 else 1)
