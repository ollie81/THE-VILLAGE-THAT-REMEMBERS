extends Node
## Headless test of milestone 1: walking into homes (doors, furniture, your
## bed and hearth, saving indoors), the livelier village (planters, market,
## trees that step out of the camera's way) and the first fight (forging a
## sword and shield, attack, block, dodge, eating stew, thornlings that
## notice, wind up, lunge and are beaten, the Thornwood mission and its save,
## being knocked out).
## Run:  godot --headless --path . res://tests/adventure_test.tscn

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


func _seconds(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _run() -> void:
	print("== Adventure test ==")
	WorldClock.day = 3
	WorldClock.set_time(10.0)
	WorldClock.set_time_scale(0.0)
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_main)
	await _frames(40)
	await _homes()
	await _village()
	await _combat()
	print("== %s: %d failure(s) ==" % ["PASSED" if _failures == 0 else "FAILED", _failures])
	get_tree().quit(0 if _failures == 0 else 1)


# --- Homes ----------------------------------------------------------------------------

func _homes() -> void:
	var interiors := Interiors.instance
	var player: PlayerController = GameManager.player
	var doors: Array = _main.find_children("Door_*", "", true, false)
	_check(doors.size() == 5, "every founder's home has a front door (%d)" % doors.size())
	var mara_door: UsableObject = _main.find_child("Door_mara", true, false)
	_check(mara_door.verb.call() == "Enter" and String(mara_door.prompt.call()).contains("Mara"), "by day: \"%s\"" % mara_door.prompt.call())
	WorldClock.set_time(23.0)
	_check(mara_door.verb.call() == "Knock", "at night you can only knock (everyone's asleep)")
	mara_door.use.call(player)
	await _frames(3)
	_check(not interiors.is_inside(), "and knocking doesn't let you in")
	WorldClock.set_time(10.0)
	var outside := player.global_position
	mara_door.use.call(player)
	await _seconds(Interiors.FADE_TIME * 2.0 + 0.3)
	_check(interiors.is_inside() and interiors.current == "mara", "walking in through Mara's door")
	_check(player.global_position.distance_to(Interiors.ROOM_ORIGIN) < 6.0 and is_equal_approx(VillageLayout.get_walk_height(player.global_position.x, player.global_position.z), Interiors.ROOM_ORIGIN.y),
		"you stand on her floor (no loading, same scene)")
	_check(_main.camera_rig.indoor and not Guide.instance.enabled and Sounds.indoor, "indoors the camera comes closer, the guide waits and the wind is muffled")
	await _frames(20)
	var room: Node3D = interiors._room
	var furniture: Array = room.find_children("*", "UsableObject", true, false).map(func(n): return String(n.name))
	_check(furniture.has("ExitDoor") and furniture.filter(func(n): return n.begins_with("Chair")).size() == 2 and not furniture.has("Bed") and not furniture.has("Hearth"),
		"her room has chairs to sit on and a way out (her bed and hearth are hers): %s" % str(furniture))
	var chair: UsableObject = room.find_child("Chair", true, false)
	chair.use.call(player)
	await _frames(3)
	_check(player.pose == &"sit", "sitting at her table")
	player.stand_up()
	# Saving indoors saves the doorstep.
	var saved := player.get_save_data()
	var at := Vector3(saved["position"][0], saved["position"][1], saved["position"][2])
	_check(at.distance_to(mara_door.global_position) < 2.5 and at.distance_to(Interiors.ROOM_ORIGIN) > 100.0, "saving indoors saves the doorstep, never the room")
	var exit: UsableObject = room.find_child("ExitDoor", true, false)
	exit.use.call(player)
	await _seconds(Interiors.FADE_TIME * 2.0 + 0.3)
	await _frames(5)
	_check(not interiors.is_inside() and player.global_position.distance_to(mara_door.global_position) < 2.5 and not is_instance_valid(room), "leaving puts you back on her doorstep and frees the room")
	_check(player.detector.focused == null or is_instance_valid(player.detector.focused), "nothing from the room lingers as a prompt")
	# Distinct homes.
	var looks := {}
	for owner in ["mara", "elias", "nia", "tomas", "sera"]:
		var r := interiors._build_room(owner)
		looks[owner] = r.find_children("*", "MeshInstance3D", true, false).map(func(m): return m.mesh.get_faces().size() if m.mesh else 0)
		r.free()
	var unique := {}
	for owner in looks:
		unique[str(looks[owner])] = true
	_check(unique.size() == 5, "each founder's home has its own layout and belongings")
	# Your own house: bed and hearth.
	interiors.enter("player", outside, 0.0)
	await _seconds(Interiors.FADE_TIME * 2.0 + 0.3)
	room = interiors._room
	var hearth: UsableObject = room.find_child("Hearth", true, false)
	var bed: UsableObject = room.find_child("Bed", true, false)
	_check(hearth != null and bed != null, "your house has your bed and a hearth")
	GameState.add(&"food", 4)
	GameState.add(&"herbs", 2)
	hearth.use.call(player)
	_check(PlayerCombat.stews() == 1 and GameState.count(&"food") == 2 and GameState.count(&"herbs") == 1, "cooking a stew at the hearth (2 food, 1 herb)")
	WorldClock.set_time(22.0)
	var day := WorldClock.day
	bed.use.call(player)
	_check(WorldClock.day == day + 1 and WorldClock.time_of_day < 8.0, "sleeping in your bed until morning")
	interiors.leave()
	await _seconds(Interiors.FADE_TIME * 2.0 + 0.3)
	WorldClock.set_time(10.0)


# --- The village ------------------------------------------------------------------------

func _village() -> void:
	_check(VillageDecor.stalls.size() == 2, "a market corner with two stalls by the meeting circle (%d)" % VillageDecor.stalls.size())
	_check(BuildMode.placement_reason(&"bench", VillageDecor.stalls[0], 0.0) != "", "and you can't build on top of them")
	# A tree between the camera and the player steps out of the view.
	var tree: Dictionary = {}
	for entry: Dictionary in NatureSpawner._clearable:
		if NatureSpawner.is_workable(entry) and entry["kind"] == "tree":
			tree = entry
			break
	var crown: Vector3 = tree["pos"] + Vector3(0, 3.0 * float(tree["scale"]), 0)
	var camera := crown + Vector3(4.0, 0.0, 0.0)
	var target := crown - Vector3(4.0, 2.0, 0.0)
	var hidden := NatureSpawner.update_view(camera, target)
	_check(hidden >= 1 and tree.get("view_hidden", false), "a tree in the way of the camera is hidden")
	NatureSpawner.update_view(Vector3(0, -1000, 0), Vector3(0, -1000, 0))
	_check(not tree.get("view_hidden", false) and NatureSpawner.is_workable(tree), "and comes back when it's no longer in the way")


# --- Combat -----------------------------------------------------------------------------

func _combat() -> void:
	var player: PlayerController = GameManager.player
	var combat := player.combat
	var woods := Thornwood.instance
	_check(combat != null and combat.health == PlayerCombat.MAX_HEALTH and not PlayerCombat.is_armed(), "you start unarmed, at full health")
	# Unarmed, the thornlings don't come out.
	player.global_position = woods.center + Vector3(6.0, 0.6, 0.0)
	await _seconds(0.7)
	_check(get_tree().get_nodes_in_group("enemies").is_empty(), "unarmed, the thornlings stay hidden")
	player.global_position = VillageLayout.ground_point(-4.0, 9.0) + Vector3(0, 0.5, 0)
	await _frames(5)
	# Forging a sword and shield at the workshop.
	var bench: UsableObject = _main.find_child("WorkshopBench", true, false)
	GameState.set_flag(&"has_tools")
	GameState.add(&"wood", 8)
	GameState.add(&"stone", 6)
	_check(String(bench.prompt.call()).begins_with("Forge a sword and shield"), "the workshop offers: %s" % bench.prompt.call())
	bench.use.call(player)
	await _frames(3)
	_check(PlayerCombat.is_armed() and combat._sword != null and combat._sword.visible and combat._shield.visible, "you forge a sword and shield and carry them")
	_check(woods.mission_active(), "and Tomas asks you to chase the thornlings out of the west woods")
	GameState.objective_index = GameState.OBJECTIVES.size()
	Guide.instance.enabled = true
	Guide.instance.refresh()
	_check(Guide.instance.target_label == "Thornlings", "the guide points the way")
	# To the woods.
	player.global_position = woods.center + Vector3(9.0, 0.8, 0.0)
	player.face_towards(woods.center)
	await _seconds(0.7)
	var enemies: Array = get_tree().get_nodes_in_group("enemies")
	_check(enemies.size() == Thornwood.COUNT, "%d thornlings live in the clearing" % enemies.size())
	var touch: TouchControls = _main.find_child("TouchControls", true, false)
	await _frames(2)
	_check(combat.in_fight() and touch.fighting, "the fight buttons appear on a phone (Attack, Block, Dodge)")
	for e in enemies:
		e.set_physics_process(false)
	var thornling: Thornling = enemies[0]
	# They notice you, wind up, then lunge.
	thornling.set_physics_process(true)
	thornling.global_position = player.global_position + player.get_facing() * 5.0
	await _frames(5)
	_check(thornling.state == Thornling.State.CHASE, "a thornling notices you and gives chase")
	thornling.global_position = player.global_position + player.get_facing() * 2.0
	await _frames(4)
	_check(thornling.state == Thornling.State.WINDUP, "close up it winds up first (a clear warning)")
	# Blocking while facing it takes the sting out.
	combat.blocking = true
	var taken := combat.take_hit(Thornling.DAMAGE, thornling.global_position)
	_check(is_equal_approx(taken, Thornling.DAMAGE * (1.0 - PlayerCombat.BLOCK_REDUCTION)), "blocking with the shield takes the sting out (%.1f of %d)" % [taken, int(Thornling.DAMAGE)])
	combat.blocking = false
	combat._grace = 0.0
	taken = combat.take_hit(Thornling.DAMAGE, thornling.global_position)
	_check(is_equal_approx(taken, Thornling.DAMAGE) and combat._grace > 0.0, "an open hit costs %d health, and gives a moment's grace" % int(taken))
	_check(combat.take_hit(Thornling.DAMAGE, thornling.global_position) == 0.0, "(so two hits can't land at once)")
	combat._grace = 0.0
	combat._dodge_cooldown = 0.0
	_check(combat.dodge() and combat.take_hit(Thornling.DAMAGE, thornling.global_position) == 0.0, "a dodge slips past a blow")
	await _seconds(PlayerCombat.DODGE_TIME + PlayerCombat.DODGE_COOLDOWN + 0.1)
	# Striking it.
	thornling.set_physics_process(false)
	thornling.state = Thornling.State.RECOVER
	thornling.global_position = player.global_position + player.get_facing() * 1.6
	var herbs := GameState.count(&"herbs")
	for i in Thornling.MAX_HEALTH:
		combat._attack_timer = 0.0
		_check(combat.attack(), "swing %d" % (i + 1)) if i == 0 else combat.attack()
		await _seconds(PlayerCombat.HIT_DELAY + 0.1)
		thornling.global_position = player.global_position + player.get_facing() * 1.6 if is_instance_valid(thornling) else Vector3.ZERO
	_check(not is_instance_valid(thornling) or thornling.state == Thornling.State.DEFEATED, "three sword hits beat a thornling")
	_check(GameState.count(&"herbs") > herbs, "it leaves a little behind")
	# A miss: an enemy behind you isn't hit.
	var other: Thornling = get_tree().get_nodes_in_group("enemies")[0]
	other.global_position = player.global_position - player.get_facing() * 1.5
	other.set_physics_process(false)
	_check(combat._strike() == 0, "a blade only hits what's in front of you")
	other.global_position = player.global_position + player.get_facing() * 1.5
	_check(combat._strike() == 1, "(and does hit what is)")
	other.health = Thornling.MAX_HEALTH
	# Eating stew.
	var hurt := combat.health
	combat.eat()
	_check(combat.health > hurt and PlayerCombat.stews() == 0, "eating a stew heals you")
	# Clearing the woods.
	var wood := GameState.count(&"wood")
	for e in get_tree().get_nodes_in_group("enemies"):
		while is_instance_valid(e) and e.is_alive():
			e.take_hit(1, player.global_position)
	await _frames(3)
	_check(woods.mission_done and woods.times_cleared == 1 and GameState.count(&"wood") >= wood + 12, "chasing them all off completes the mission (+12 wood and more)")
	var tomas = GameManager.get_villager(&"tomas")
	_check(tomas.mind.memory.find("deed", GameManager.PLAYER_ID).any(func(e): return String(e["detail"]).contains("thornlings")), "and Tomas remembers it")
	_check(not woods.is_infested(), "the clearing is quiet for now")
	WorldClock.day += Thornwood.RESPAWN_DAYS
	_check(woods.is_infested(), "they come back after %d days" % Thornwood.RESPAWN_DAYS)
	# The steel edge.
	GameState.add(&"wood", 6)
	GameState.add(&"stone", 12)
	_check(String(bench.prompt.call()).contains("steel edge"), "after the mission the workshop offers a steel edge")
	bench.use.call(player)
	_check(combat.damage() == 2, "which makes the sword hit twice as hard")
	# Saved.
	var copy := Thornwood.new()
	copy.from_dict(JSON.parse_string(JSON.stringify(woods.to_dict())))
	_check(copy.mission_done and copy.times_cleared == 1 and copy.last_cleared_day == woods.last_cleared_day, "the mission is saved")
	copy.free()
	# Thornlings take turns: never two attacking at once.
	player.global_position = woods.center + Vector3(5.0, 0.8, 0.0)
	await _frames(3)
	var pack: Array = []
	for i in 3:
		var t := Thornling.new()
		t.home = player.global_position + Vector3(cos(i * 2.1), 0, sin(i * 2.1)) * 2.0
		t.position = t.home + Vector3(0, 0.3, 0)
		get_tree().current_scene.add_child(t)
		t.state = Thornling.State.CHASE
		pack.append(t)
	combat._grace = 10.0  # don't get knocked out while counting
	var most := 0
	for f in 90:
		await get_tree().physics_frame
		most = maxi(most, pack.filter(func(t): return t.state in [Thornling.State.WINDUP, Thornling.State.LUNGE]).size())
	_check(most == 1, "thornlings take turns: one attacks while the others circle (at most %d at once)" % most)
	for t in pack:
		t.queue_free()
	combat._grace = 0.0
	await _frames(2)
	# Knocked out: home again, nothing lost.
	await _seconds(0.6)
	var stores := GameState.count(&"wood")
	player.global_position = woods.center + Vector3(4.0, 0.8, 0.0)
	combat._grace = 0.0
	combat.health = 5.0
	combat.take_hit(20.0, woods.center)
	_check(combat.health == PlayerCombat.MAX_HEALTH and player.global_position.distance_to(woods.center) > 25.0 and GameState.count(&"wood") == stores,
		"knocked out, you wake up at home with nothing lost")
