extends Node
## Developer tool: Stage B in pictures. The House panel (giving a house, with
## the confirmation), a villager walking up to the door, inside: sitting,
## a friend visiting, and asleep in bed at night.
## Run: godot --path . --resolution 1612x720 res://tools/home_life_screenshots.tscn -- --out=/some/dir
var _out := "user://screenshots"
var _main
var _record: Dictionary
var _house: PlacedStructure

func _ready() -> void:
	SaveService.enabled = false
	PopulationDirector.auto_arrivals = false
	DailyGift.persist = false
	CreditRewards.enabled = false
	AdRewards.reset_for_tests()
	GameState.reset()
	GameSettings.touch_mode = 1
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.substr(6)
	DirAccess.make_dir_recursive_absolute(_out)
	_run.call_deferred()

func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _secs(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("saved ", name)

func _open_ground(type: StringName, near: Vector3) -> Vector3:
	for ring in range(0, 40):
		for i in maxi(1, ring * 8):
			var a := TAU * i / maxi(1, ring * 8)
			var at := VillageLayout.ground_point(near.x + cos(a) * ring * 2.0, near.z + sin(a) * ring * 2.0)
			if BuildMode.placement_reason(type, at, 0.0, null, true) == "":
				return at
	return Vector3.INF

func _hour(h: float) -> void:
	WorldClock.set_time(h)
	for v in GameManager.villagers:
		v._decision_timer = 0.0

func _until(test: Callable, limit: float) -> void:
	Engine.time_scale = 6.0
	var t := 0.0
	while t < limit and not test.call():
		await get_tree().process_frame
		t += get_process_delta_time() / Engine.time_scale
	Engine.time_scale = 1.0

func _run() -> void:
	WorldClock.set_time(15.0)
	WorldClock.set_time_scale(0.0)
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_main)
	await _wait(60)
	Weather.instance.set_weather(Weather.Kind.CLEAR, 480.0, true)
	for tip in _main.find_children("TutorialTips", "", true, false):
		tip.visible = false
		tip.set_process(false)
	for r in GameState.RESOURCES:
		GameState.add(r, 500)
	var plaza: Vector3 = VillageLayout.get_nav_nodes().get("plaza", Vector3.ZERO)
	_record = GameState.add_structure(&"house_medium", _open_ground(&"house_large", plaza + Vector3(14, 0, 14)), 0.0)
	await _wait(3)
	for s in StructureManager.instance.structures():
		if s.record == _record:
			_house = s
	while not _house.is_complete():
		_house.add_work(1.0)
	await _wait(5)
	var player: PlayerController = GameManager.player
	# The House panel.
	Interiors.instance.enter(Furnishings.place_of(_record), _house.doorstep(), _house.rotation.y)
	await _secs(1.0)
	HousePanel.instance.open_for(_record)
	await _wait(10)
	await _wait(30)
	await _shot("1_house_panel")
	(HousePanel.instance.find_child("Give_mara", true, false) as Button).pressed.emit()
	await _wait(6)
	await _shot("2_confirm")
	(HousePanel.instance.find_child("ConfirmYes", true, false) as Button).pressed.emit()
	await _wait(3)
	HousePanel.instance.close_panel()
	Interiors.instance.leave()
	await _secs(1.0)
	# Mara walking up to her door.
	var mara: Villager = GameManager.get_villager(&"mara")
	mara.brain.use_plan([{"hour": 0.0, "activity": "rest", "location": "home", "label": "Going home"}])
	mara._decision_timer = 0.0
	var door := HomeLife.door_of(Population.cottage_home_id(_record))
	await _until(func(): return mara.global_position.distance_to(door["approach"]) < 2.5 or mara.state == Villager.State.INSIDE, 60.0)
	var step: Vector3 = door["step"]
	player.global_position = VillageLayout.ground_point(step.x + 5.0, step.z + 6.0)
	player.model.rotation.y = atan2(step.x - player.global_position.x, step.z - player.global_position.z)
	player.camera_rig.yaw = player.model.rotation.y + PI
	await _wait(8)
	await _shot("3_walking_home")
	await _until(func(): return mara.state == Villager.State.INSIDE, 60.0)
	# Inside: Mara at home, then Nia visiting.
	Interiors.instance.enter(Furnishings.place_of(_record), _house.doorstep(), _house.rotation.y)
	await _secs(1.2)
	await _until(func(): return HomeLife.instance._agents.has(mara) and HomeLife.instance._agents[mara]["i"] >= (HomeLife.instance._agents[mara]["path"] as PackedVector2Array).size(), 20.0)
	await _wait(20)
	await _shot("4_at_home")
	var nia: Villager = GameManager.get_villager(&"nia")
	nia.brain.use_plan([{"hour": 0.0, "activity": "visit", "location": Population.cottage_home_id(_record), "label": "Visiting Mara"}])
	nia._decision_timer = 0.0
	await _until(func(): return nia.state == Villager.State.HOME, 120.0)
	await _wait(30)
	await _shot("5_friend_arrives")
	await _until(func(): return HomeLife.instance._agents.has(nia) and HomeLife.instance._agents[nia]["i"] >= (HomeLife.instance._agents[nia]["path"] as PackedVector2Array).size(), 20.0)
	await _wait(40)
	await _shot("6_visiting")
	nia.brain.plan_day(WorldClock.day)
	# Night: asleep in her bed.
	mara.brain.plan_day(WorldClock.day)
	_hour(22.5)
	await _until(func(): return HomeLife.instance._agents.has(mara) and String(HomeLife.instance._agents[mara]["plan"].get("kind", "")) == "sleep" \
		and HomeLife.instance._agents[mara]["i"] >= (HomeLife.instance._agents[mara]["path"] as PackedVector2Array).size(), 60.0)
	var bed = Furnishings.instance.body_of(HomeLife.bed_for("mara", Population.cottage_home_id(_record)))
	if bed:
		player.global_position = Interiors.ROOM_ORIGIN + Vector3(-1.0, 0.05, -2.6)
		var to: Vector3 = bed.global_position - player.global_position
		player.model.rotation.y = atan2(to.x, to.z)
		player.camera_rig.yaw = player.model.rotation.y + PI
	await _wait(30)
	print("SLEEP state=", mara.state, " plan=", HomeLife.instance._agents.get(mara, {}).get("plan", {}).get("kind", "-"), " i=", HomeLife.instance._agents.get(mara, {}).get("i", -1), " pos=", mara.global_position - Interiors.ROOM_ORIGIN)
	await _shot("7_asleep")
	# The player lying down in a bed too (same pose), for comparison.
	var spot := Furnishings.instance.free_spot(&"bed", Furnishings.place_of(_record), Vector3(-2.6, 0, -2.4), 0.0)
	var spare := Furnishings.instance.add(&"bed", Furnishings.place_of(_record), spot, 0.0)
	Interiors.instance.leave()
	await _secs(1.0)
	_hour(15.0)
	Interiors.instance.enter(Furnishings.place_of(_record), _house.doorstep(), _house.rotation.y)
	await _secs(1.2)
	var spare_piece = Furnishings.instance.body_of(spare)
	if spare_piece == null:
		print("no spare bed")
		get_tree().quit()
		return
	_record["owner"] = "player"
	player.global_position = spare_piece.global_position + Vector3(1.2, 0, 0)
	Interiors.instance._sleep(player, spare_piece)
	await _secs(0.6)
	player.camera_rig.yaw = -PI * 0.5
	await _wait(5)
	await _shot("8_player_in_bed")
	get_tree().quit()
