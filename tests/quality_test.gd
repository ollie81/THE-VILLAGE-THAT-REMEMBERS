extends Node
## Headless test of the owner's second phone report: hens that live and move,
## real tools in the hand, a journal and tutorial that say what to do next,
## new activities (fishing, trading, exploring) that open up over time, homes
## you can use, warmer rooms, and more varied newcomers.
## Run:  godot --headless --path . res://tests/quality_test.tscn

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


func _seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _run() -> void:
	print("== Quality test ==")
	WorldClock.day = 1
	WorldClock.set_time(9.0)
	WorldClock.set_time_scale(0.0)
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_main)
	await _frames(40)
	await _guidance()
	await _hens()
	await _tools()
	await _activities()
	await _rooms()
	await _characters()
	await _device_prep()
	print("== %s: %d failure(s) ==" % ["PASSED" if _failures == 0 else "FAILED", _failures])
	get_tree().quit(0 if _failures == 0 else 1)


# --- Journal and tutorial ---------------------------------------------------------------

func _guidance() -> void:
	var tips: TutorialTips = _main.find_child("TutorialTips", true, false)
	await _seconds(0.7)
	_check(tips.visible and tips.current == "move", "the first tip teaches moving and looking: %s" % tips._label.text)
	GameManager.player.global_position += Vector3(8, 0, 0)
	await _seconds(0.7)
	_check(tips.current == "talk", "after walking, the next tip: talking (%s)" % tips.current)
	tips.dismiss()
	_check(TutorialTips.seen("talk"), "\"Got it\" dismisses a tip for good")
	var journal: JournalPanel = _main.find_child("JournalPanel", true, false)
	var text := JournalPanel.build_text()
	_check(text.contains("Day 1") and text.contains("Next:") and text.contains("Reward: +3 food"), "the journal shows the goal, the next step and its reward")
	_check(text.contains("What you can do") and text.contains("Chop and mine") and text.contains("Coming later") and text.contains("Fish: Craft tools at the workshop first"),
		"it lists what you can do now and what opens later")
	_check(text.contains("Controls"), "and a reminder of the controls")
	var panels: GameplayPanels = _main.find_child("GameplayPanels", true, false)
	var tap := InputEventMouseButton.new()
	tap.button_index = MOUSE_BUTTON_LEFT
	tap.pressed = true
	panels._objective_box.gui_input.emit(tap)
	_check(journal.visible, "tapping the goal card opens the Journal")
	journal.visible = false
	await _frames(3)
	_check(panels._objective_details.text.contains("Reward") and panels._objective_details.text.contains("Journal"), "the goal card shows the reward and points to the Journal")
	# Gathering: the card says which tool.
	GameState.objective_index = 1
	Guide.instance.refresh()
	await _frames(3)
	_check(Guide.instance.tool == "Axe" and panels._objective_details.text.contains("Tool: Axe"), "and which tool the next step needs: %s" % panels._objective_details.text)
	GameState.objective_index = 0


# --- Hens ---------------------------------------------------------------------------------

func _hens() -> void:
	GameState.add(&"wood", 20)
	var spot := BuildMode.nearest_free_spot(&"chicken_coop", VillageLayout.ground_point(-28.0, 22.0), 0.0, Vector3(0, 0, 100))
	var record := GameState.add_structure(&"chicken_coop", spot, 0.0)
	await _frames(3)
	var coop: PlacedStructure = null
	for s in get_tree().get_nodes_in_group("placed_structures"):
		if s.record == record:
			coop = s
	while not coop.is_complete():
		coop.add_work(1.0)
	await _frames(5)
	var hens := coop.hens()
	_check(hens.size() == 3, "a coop has three real hens")
	GameManager.player.global_position = coop.run_center() + Vector3(0, 0.5, 15.0)
	var start: Array = hens.map(func(h): return h.global_position)
	var states := {}
	for i in 240:
		await get_tree().process_frame
		for h in hens:
			states[h.state] = true
	var moved := 0
	for i in hens.size():
		if hens[i].global_position.distance_to(start[i]) > 0.3:
			moved += 1
	_check(moved >= 2, "hens walk about (%d of 3 moved)" % moved)
	_check(states.size() >= 2, "doing different things: wander, peck, rest (%d kinds seen)" % states.size())
	var inside := hens.all(func(h): return Vector2(h.global_position.x - coop.run_center().x, h.global_position.z - coop.run_center().z).length() <= Chicken.RUN_RADIUS + 0.5)
	_check(inside, "and stay in their run")
	var hen: Chicken = hens[0]
	GameManager.player.global_position = hen.global_position + Vector3(0.8, 0.5, 0)
	await _seconds(0.4)
	_check(hen.state == Chicken.State.FLEE, "a hen scurries away when you come close")
	var before := hen.global_position
	await _seconds(0.6)
	_check(hen.global_position.distance_to(before) > 0.3, "(and really runs)")
	# Eggs and feeding survive closing the app (the save is JSON).
	record["eggs"] = 5
	record["fed_day"] = WorldClock.day
	var saved: Dictionary = JSON.parse_string(JSON.stringify(GameState.to_dict()))
	var saved_coop: Dictionary = {}
	for r: Dictionary in saved["structures"]:
		if int(r.get("uid", -1)) == int(record.get("uid", -2)):
			saved_coop = r
	_check(int(saved_coop.get("eggs", -1)) == 5 and int(saved_coop.get("fed_day", -1)) == WorldClock.day and coop.eggs() == 5 and coop.hens_fed_today(),
		"eggs in the nest and feeding are in the save (%s)" % str(saved_coop.get("eggs", "missing")))
	record["eggs"] = 0


# --- Tools in hand -------------------------------------------------------------------------

func _tools() -> void:
	var player: PlayerController = GameManager.player
	var tree: Dictionary = {}
	for entry: Dictionary in NatureSpawner._clearable:
		if NatureSpawner.is_workable(entry) and entry["kind"] == "tree":
			tree = entry
			break
	player.global_position = tree["pos"] + Vector3(1.4, 0.6, 0)
	player.face_towards(tree["pos"])
	await _frames(20)
	player.detector.try_interact(player)
	await _frames(2)
	_check(player.tools.current == &"axe" and player.tools._meshes[&"axe"].visible, "chopping, the player holds an axe")
	await _seconds(1.2)
	_check(player.tools.current == &"" and not player.tools._meshes[&"axe"].visible, "and puts it away after")
	var rock: Dictionary = {}
	for entry: Dictionary in NatureSpawner._clearable:
		if NatureSpawner.is_workable(entry) and entry["kind"] == "rock":
			rock = entry
			break
	player.global_position = rock["pos"] + Vector3(1.6, 0.6, 0)
	player.face_towards(rock["pos"])
	await _frames(20)
	player.detector.try_interact(player)
	await _frames(2)
	_check(player.tools.current == &"pickaxe", "mining, a pickaxe")
	await _seconds(1.2)
	for pair in [[&"hoe", "planting"], [&"watering_can", "watering"], [&"hammer", "building"], [&"fishing_rod", "fishing"]]:
		player.perform_action(&"work", 0.5, player.global_position + player.get_facing(), pair[0])
		await _frames(2)
		_check(player.tools.current == pair[0] and player.tools._meshes.has(pair[0]), "%s, a %s" % [pair[1], String(pair[0]).replace("_", " ")])
	await _seconds(0.7)


# --- New activities --------------------------------------------------------------------------

func _activities() -> void:
	var player: PlayerController = GameManager.player
	_check(not Activities.unlocked("fish") and not Activities.unlocked("trade"), "fishing and trading aren't open on day 1")
	WorldClock.day = 3
	GameState.set_flag(&"has_tools")
	_check(Activities.unlocked("fish") and Activities.unlocked("trade") and Activities.unlocked("explore"), "they open up as the days go by")
	# Fishing.
	var fishing := Fishing.instance
	var bank_z := 20.0
	var bank := Vector3(VillageLayout.river_center_x(bank_z) - VillageLayout.RIVER_HALF_WIDTH - 0.8, 0, bank_z)
	player.global_position = VillageLayout.ground_point(bank.x, bank.z) + Vector3(0, 0.5, 0)
	await _seconds(0.6)
	_check(fishing.interactable.enabled and fishing.get_interaction_prompt().contains("make a fishing rod"), "on the river bank without a rod: %s" % fishing.get_interaction_prompt())
	GameState.set_flag(&"has_rod")
	var food := GameState.count(&"food")
	fishing.use(player)
	_check(fishing.stage == Fishing.Stage.WAITING and player.tools.current == &"fishing_rod", "with a rod you cast and wait")
	fishing._timer = 0.0
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(fishing.stage == Fishing.Stage.BITE and fishing.get_interaction_verb() == "Reel", "a bite! Reel")
	var touch: Array = _main.find_children("*", "TouchControls", true, false)
	await get_tree().process_frame
	_check(not touch.is_empty() and player.detector.focused == fishing.interactable and touch[0]._shown_verb == "Reel",
		"the action button changes to Reel too (it used to keep the old verb)")
	fishing.use(player)
	_check(GameState.count(&"food") == food + Fishing.CATCH_FOOD and fishing.stage == Fishing.Stage.IDLE, "reeling in catches a fish (+%d food)" % Fishing.CATCH_FOOD)
	fishing.use(player)
	fishing._timer = 0.0
	await get_tree().physics_frame
	await get_tree().physics_frame
	fishing._timer = 0.0
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(fishing.stage == Fishing.Stage.IDLE and GameState.count(&"food") == food + Fishing.CATCH_FOOD, "too slow, and it gets away")
	# Trading.
	var trade: TradePanel = _main.find_child("TradePanel", true, false)
	_check(_main.find_children("MarketStall", "", true, false).size() == 2, "the market stalls have a trader")
	GameState.add(&"wood", 4)
	var stone := GameState.count(&"stone")
	trade.open()
	_check(trade.trade(0) and GameState.count(&"stone") == stone + 2, "trading 4 wood for 2 stone")
	trade.visible = false
	# Treasure.
	_check(Treasure.instance.spots.size() == 3, "three old chests are hidden in the woods")
	var chest: UsableObject = _main.find_child("Chest_0", true, false)
	var wood_before := GameState.count(&"wood")
	chest.use.call(player)
	_check(Treasure.found() == 1 and GameState.count(&"stone") > stone, "opening one finds something useful (1 / 3)")
	chest.use.call(player)
	_check(Treasure.found() == 1 and GameState.count(&"wood") == wood_before, "and it's empty the second time (saved)")


# --- Rooms -----------------------------------------------------------------------------------

func _rooms() -> void:
	var player: PlayerController = GameManager.player
	Interiors.instance.enter("mara", player.global_position, 0.0)
	await _seconds(Interiors.FADE_TIME * 2.0 + 0.3)
	var room: Node3D = Interiors.instance._room
	var names: Array = room.find_children("*", "UsableObject", true, false).map(func(n): return String(n.name))
	_check(names.has("WindowSeat") and names.has("Books") and names.filter(func(n): return n.begins_with("Chair")).size() == 2, "a home has a window seat, books and chairs to use: %s" % str(names))
	_check(DayNightCycle.indoor, "inside, the light is warm and the sun shut out")
	var books: UsableObject = room.find_child("Books", true, false)
	books.use.call(player)
	_check(int(GameState.get_flag(&"pages_read", 0)) == 1, "reading tells a piece of the village's story")
	var seat: UsableObject = room.find_child("WindowSeat", true, false)
	seat.use.call(player)
	await _frames(2)
	_check(player.pose == &"sit", "sitting by the window")
	player.stand_up()
	Interiors.instance.leave()
	await _seconds(Interiors.FADE_TIME * 2.0 + 0.3)
	_check(not DayNightCycle.indoor, "outside, daylight again")


# --- Characters ------------------------------------------------------------------------------

func _characters() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var styles := {}
	var extras := {}
	for i in 60:
		var look := AppearanceGenerator.generate(rng, "female" if i % 2 == 0 else "male", 25, ["farmer", "herbalist", "fisher", "weaver"][i % 4], [])
		styles[look.hair_style] = true
		for item in look.accessories:
			extras[item] = true
		if look.hair_style == "afro":
			_check(not look.accessories.has("cap") and not look.accessories.has("straw_hat"), "an afro never gets squashed under a hat") if i < 20 else null
	_check(styles.has("afro") and styles.has("braids"), "newcomers can have afros and braids too: %s" % str(styles.keys()))
	_check(extras.has("flower_crown") and extras.has("cap") and extras.has("necklace"), "and wear flower crowns, caps and necklaces")
	var look := AppearanceGenerator.generate(rng, "female", 30, "herbalist", [])
	look.hair_style = "braids"
	look.accessories = PackedStringArray(["flower_crown", "necklace"])
	var meshes := CharacterModel.build_meshes(look, null, false)
	_check(meshes["head"] != null and meshes["body"] != null, "a newcomer with braids, a flower crown and a necklace builds fine")


# --- Real-device testing support ------------------------------------------------------------

func _device_prep() -> void:
	var player: PlayerController = GameManager.player
	# Saves can't be lost if the phone kills the app mid-write.
	var path := "user://quality_test_save.json"
	var first := {"version": SaveService.SAVE_VERSION, "n": 1}
	var second := {"version": SaveService.SAVE_VERSION, "n": 2}
	_check(SaveService.write_safely(path, JSON.stringify(first)) and SaveService.write_safely(path, JSON.stringify(second)),
		"saves are written through a temporary file")
	_check(int(SaveService.read_safely(path).get("n", 0)) == 2 and FileAccess.file_exists(path + ".bak"), "the newest save loads, the previous one is kept as a backup")
	var cut := FileAccess.open(path, FileAccess.WRITE)
	cut.store_string(JSON.stringify(second).left(12))  # as if the write was cut off
	cut.close()
	_check(int(SaveService.read_safely(path).get("n", 0)) == 1, "a cut-off save falls back to the backup instead of starting over")
	for f in [path, path + ".bak", path + ".tmp"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	# Report a problem.
	var report := ReportPanel.build_report()
	_check(report.contains(BuildInfo.text()) and report.contains("Device:") and report.contains("Renderer:") and report.contains("FPS:")
		and report.contains("Goal:") and report.contains("Villagers:") and report.contains("Recent errors"), "the problem report has the build, phone, renderer, FPS and game state")
	var settings: Node = _main.find_child("SettingsPanel", true, false)
	var button: Button = settings.find_child("ReportButton", true, false) if settings else null
	_check(button != null, "Settings has a Report a problem button")
	if button:
		button.pressed.emit()
		_check(ReportPanel.instance.visible and ReportPanel.instance._text.text.contains("Device:"), "which opens the report")
		ReportPanel.instance.visible = false
	# Tapping the goal card opens the Journal (a touch arrives as a mouse click).
	var panels: Node = _main.find_child("GameplayPanels", true, false)
	var card: Control = panels._objective_box if panels else null
	var journal := JournalPanel.instance
	journal.visible = false
	if card:
		var tap := InputEventMouseButton.new()
		tap.button_index = MOUSE_BUTTON_LEFT
		tap.pressed = true
		card.gui_input.emit(tap)
	_check(card != null and card.mouse_filter == Control.MOUSE_FILTER_STOP and journal.visible, "tapping the goal card opens the Journal")
	journal.visible = false
	# Tools are held on the right hand bone.
	player.tools.hold(&"axe", 1.0)
	var hand := player.tools._attachment
	_check(hand != null and hand.bone_name == "RightHand" and hand.get_bone_idx() >= 0 and player.tools._meshes[&"axe"].get_parent() == hand,
		"tools are attached to the right hand bone")
	player.tools.hold(&"", 0.0)
