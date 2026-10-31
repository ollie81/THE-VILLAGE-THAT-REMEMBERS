extends Node
## Headless test of the first gameplay loop: gathering, crafting, building,
## farming, villager tasks, objectives, the village meeting and saving.
## Run:  godot --headless --path . res://tests/gameplay_test.tscn

var _failures: int = 0
var _main = null


func _ready() -> void:
	SaveService.enabled = false
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
		await get_tree().physics_frame


func _nearest(kind: StringName) -> ResourceNode:
	var player = GameManager.player
	var best: ResourceNode = null
	for node in ResourceSpawner.nodes:
		if node.kind == kind and node.uses_left > 0 and (best == null or node.global_position.distance_to(player.global_position) < best.global_position.distance_to(player.global_position)):
			best = node
	return best


## Walks the player up to something and presses the action button.
func _use(target: Node3D, offset: Vector3 = Vector3(1.0, 0.0, 0.8)) -> bool:
	var player = GameManager.player
	player.global_position = target.global_position + offset + Vector3(0, 0.4, 0)
	player.velocity = Vector3.ZERO
	player.face_towards(target.global_position)
	await _frames(12)
	var ok: bool = player.detector.try_interact(player)
	await _frames(70)
	return ok


func _run() -> void:
	print("== Gameplay test ==")
	WorldClock.day = 1
	WorldClock.set_time(9.0)
	WorldClock.set_time_scale(0.0)
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_main)
	await _frames(40)
	var player = GameManager.player

	# --- Gathering -----------------------------------------------------------------
	var trees := ResourceSpawner.nodes.filter(func(n): return n.kind == &"tree").size()
	var rocks := ResourceSpawner.nodes.filter(func(n): return n.kind == &"rock").size()
	var herbs := ResourceSpawner.nodes.filter(func(n): return n.kind == &"herbs").size()
	_check(trees >= 12 and rocks >= 6 and herbs >= 4, "resources spawned (%d trees, %d rocks, %d herb patches)" % [trees, rocks, herbs])
	var tree := _nearest(&"tree")
	_check(await _use(tree), "the player can chop a tree")
	_check(GameState.count(&"wood") == 2, "chopping gives 2 wood (%d)" % GameState.count(&"wood"))
	_check(player.detector.focused != null and player.detector.focused.get_prompt().begins_with("Chop"), "an interaction prompt names the action")
	await _use(tree)
	await _use(tree)
	_check(tree.uses_left == 0 and not tree.interactable.is_available(), "a tree is spent after three chops")
	_check(not await _use(tree), "a spent tree can't be chopped again")
	for i in 4:
		await _use(_nearest(&"tree"))
	for i in 4:
		await _use(_nearest(&"rock"), Vector3(1.4, 0, 0.9))
	_check(GameState.count(&"stone") == 8, "mining rocks gives stone (%d)" % GameState.count(&"stone"))
	await _use(_nearest(&"herbs"))
	_check(GameState.count(&"herbs") == 2, "picking herbs gives herbs")
	WorldClock.day += 1
	WorldClock.set_time(6.5)
	await _frames(5)
	_check(tree.uses_left == 3, "the tree grows back the next morning")
	WorldClock.set_time(9.0)

	# --- Crafting --------------------------------------------------------------------
	var objects: WorldObjects = _main.find_child("WorldObjects", true, false)
	var bench: Node3D = objects.get_node("WorkshopBench")
	await _use(bench, Vector3(0.6, 0, 0.6))
	_check(GameState.get_flag(&"has_tools"), "crafting tools at the workshop bench")
	var wood_before := GameState.count(&"wood")
	await _use(_nearest(&"tree"))
	_check(GameState.count(&"wood") == wood_before + 3, "tools make each chop give one more wood")

	# --- Building ----------------------------------------------------------------------
	var build: BuildMode = BuildMode.instance
	var saved_wood := GameState.count(&"wood")
	GameState.add(&"wood", -saved_wood)
	player.global_position = VillageLayout.ground_point(-30, 6) + Vector3(0, 0.4, 0)
	player.model.rotation.y = -PI * 0.5
	await _frames(5)
	build.start(&"farm_plot")
	await _frames(3)
	_check(build.active and build.reason.begins_with("Need"), "placement says what is missing (%s)" % build.reason)
	_check(build.confirm() != "" and GameState.structures.is_empty(), "can't place without resources")
	GameState.add(&"wood", saved_wood + 40)
	GameState.add(&"stone", 20)
	_check(BuildMode.placement_reason(&"farm_plot", VillageLayout.ground_point(VillageLayout.river_center_x(20.0), 20.0), 0.0).contains("river"), "can't build in the river")
	_check(BuildMode.placement_reason(&"farm_plot", VillageLayout.ground_point(0, 2), 0.0) != "", "can't build in the meeting circle")
	build.cancel()
	_check(not build.active, "placement can be cancelled")
	build.start(&"farm_plot")
	await _frames(3)
	var wood_now := GameState.count(&"wood")
	_check(build.reason == "", "a clear spot is valid (%s)" % build.reason)
	_check(build.confirm() == "" and GameState.structures.size() == 1, "the farm plot is placed")
	_check(GameState.count(&"wood") == wood_now - 6, "placing spends the cost")
	await _frames(3)
	var plot: PlacedStructure = get_tree().get_nodes_in_group("placed_structures")[0]
	_check(not plot.is_complete(), "a placed structure starts as a construction site")
	await _use(plot, Vector3(2.4, 0, 2.0))
	await _use(plot, Vector3(2.4, 0, 2.0))
	_check(plot.is_complete(), "working on it finishes the farm plot")

	# --- Farming ------------------------------------------------------------------------
	await _use(plot, Vector3(2.4, 0, 2.0))
	_check(plot.is_planted() and not plot.is_ripe(), "seeds can be planted")
	WorldClock.advance(PlacedStructure.CROP_HOURS + 0.5)
	await _frames(3)
	_check(plot.is_ripe(), "crops grow as time passes")
	var food := GameState.count(&"food")
	await _use(plot, Vector3(2.4, 0, 2.0))
	_check(GameState.count(&"food") == food + PlacedStructure.HARVEST_FOOD, "harvesting gives food")
	WorldClock.set_time(9.0)

	# --- Villager tasks -----------------------------------------------------------------
	player.global_position = VillageLayout.ground_point(-30, -8) + Vector3(0, 0.4, 0)
	player.model.rotation.y = PI
	await _frames(3)
	build.start(&"house")
	await _frames(3)
	_check(build.confirm() == "", "the house is placed (%s)" % build.reason)
	await _frames(3)
	var house: PlacedStructure = null
	for s in get_tree().get_nodes_in_group("placed_structures"):
		if s.get_type() == &"house":
			house = s
	var mara = GameManager.get_villager(&"mara")
	var tomas = GameManager.get_villager(&"tomas")
	var asked := TaskSystem.request(mara, &"build")
	_check(asked["accepted"] and mara.has_task(), "Mara agrees to help build: %s" % asked["lines"][0])
	_check(String(asked["lines"][0]).contains("hammer"), "her answer fits her personality")
	_check(not TaskSystem.request(mara, &"wood")["accepted"], "she won't take a second job at once")
	_check(not TaskSystem.request(tomas, &"stone")["accepted"], "Tomas turns down the quarry (his knees)")
	await _frames(20)
	_check(mara.state == Villager.State.TRAVELING, "Mara walks to the building site")
	var before: float = house.record["work"]
	TaskSystem.instance.contribute(mara, 1.0)
	_check(float(house.record["work"]) > before, "a helping villager adds construction work")
	var elias = GameManager.get_villager(&"elias")
	var food_before := GameState.count(&"food")
	TaskSystem.request(elias, &"farm")
	TaskSystem.instance.contribute(elias, 2.0)
	_check(GameState.count(&"food") > food_before, "Elias tending crops adds food")
	var nia = GameManager.get_villager(&"nia")
	nia.mind.adjust_opinion(GameManager.PLAYER_ID, -60.0, 0.0)
	_check(not TaskSystem.request(nia, &"wood")["accepted"], "a villager who dislikes you refuses")
	nia.mind.adjust_opinion(GameManager.PLAYER_ID, 60.0, 0.0)
	WorldClock.set_time(21.0)
	_check(not TaskSystem.request(GameManager.get_villager(&"sera"), &"wood")["accepted"], "nobody works after dark")
	WorldClock.set_time(9.0)
	# Asking through conversation.
	var talk := Conversation.new(GameManager.get_villager(&"sera"), GameManager.PLAYER_ID)
	talk.choices = DialogueService.closing_menu()
	talk.choose(0)
	_check(talk.choice_texts().size() == 5 and talk.choice_texts()[0].contains("build"), "asking for help lists the jobs")
	talk.choose(1)
	_check(talk.has_lines() and GameManager.get_villager(&"sera").has_task(), "Sera answers and goes to gather wood")
	# Finish the house.
	while not house.is_complete():
		house.add_work(1.0)
	_check(GameState.completed_structures(&"house") == 1, "the house is finished")
	WorldClock.set_time(22.0)
	await _use(house, Vector3(0, 0, 4.0))
	_check(WorldClock.time_of_day > 6.0 and WorldClock.time_of_day < 7.0, "sleeping in the house skips to morning")

	# --- Meeting and objectives -----------------------------------------------------
	for v in GameManager.villagers:
		v.task = {}
		v.mind.record_interaction(GameManager.PLAYER_ID, "conversation", WorldClock.day, 9.0)
	GameState.check_objectives()
	WorldClock.set_time(18.0)
	await _frames(70)
	var fire: Node3D = objects.get_node("FirePit")
	_check(fire.get_interaction_prompt() == "Call a village meeting", "the fire offers a meeting in the evening")
	await _use(fire, Vector3(1.9, 0, 0.6))
	_check(objects.meeting.running, "calling a meeting gathers everyone")
	var closest := INF
	for a in GameManager.villagers.size():
		for b in range(a + 1, GameManager.villagers.size()):
			var pa: Vector3 = GameManager.villagers[a].task["point"]
			var pb: Vector3 = GameManager.villagers[b].task["point"]
			closest = minf(closest, Vector2(pa.x - pb.x, pa.z - pb.z).length())
	_check(closest > 1.2, "everyone gets their own place at the fire (closest %.1f m)" % closest)
	for v in GameManager.villagers:
		if v.has_task():
			v.global_position = VillageLayout.ground_point(v.task["point"].x, v.task["point"].z)
			v.assign_task(v.task)  # re-plan the route from the new position
	await _frames(130)
	_check(GameManager.is_in_conversation(), "the meeting begins once everyone has arrived")
	GameManager.end_conversation()
	await _frames(3)
	_check(GameState.get_flag(&"meeting_held"), "the meeting is remembered")
	_check(GameState.is_week_complete(), "all seven objectives are complete (%d / 7)" % GameState.objective_index)

	# --- Saving -------------------------------------------------------------------------
	var saved: Dictionary = JSON.parse_string(JSON.stringify(GameState.to_dict()))
	var inventory_before := GameState.count(&"wood")
	GameState.reset()
	GameState.from_dict(saved)
	_check(GameState.count(&"wood") == inventory_before and GameState.structures.size() == 2 and GameState.is_week_complete(),
		"inventory, structures and objectives survive save/load")

	print("== %s: %d failure(s) ==" % ["PASSED" if _failures == 0 else "FAILED", _failures])
	get_tree().quit(0 if _failures == 0 else 1)
