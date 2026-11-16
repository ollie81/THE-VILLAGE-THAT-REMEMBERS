extends Node
## Headless test of Living Village stage B: giving houses to villagers.
##  - giving a house (the House panel: who can move in, where they live now,
##    whether it suits them, a confirmation), and no double assignments;
##  - walking home along the paths and up the front path, through the door;
##  - inside: in through the front door, room to room through doorways
##    (never through a wall), using furniture, sleeping in their own bed;
##  - leaving in the morning and coming back in the evening;
##  - visits: a friend visiting, the player visiting, inviting a friend over;
##  - saving and loading; expanding and removing a house someone lives in.
## Run:  godot --headless --path . res://tests/home_life_test.tscn

var _failures: int = 0
var _main = null
var _record: Dictionary = {}
var _house: PlacedStructure
var _home_id := ""


func _ready() -> void:
	SaveService.enabled = false
	PopulationDirector.auto_arrivals = false
	Guide.rewards = false
	DailyGift.persist = false
	CreditRewards.enabled = false
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
	await get_tree().create_timer(s, true, false, true).timeout


func _player() -> PlayerController:
	return GameManager.player


func _villager(id: String) -> Villager:
	return GameManager.get_villager(StringName(id))


## Waits (fast-forwarded) until `test` is true or `limit` real seconds pass.
func _until(test: Callable, limit: float, each: Callable = Callable()) -> bool:
	Engine.time_scale = 6.0
	var t := 0.0
	while t < limit:
		if test.call():
			Engine.time_scale = 1.0
			return true
		if each.is_valid():
			each.call()
		await get_tree().process_frame
		t += get_process_delta_time() / Engine.time_scale
	Engine.time_scale = 1.0
	return test.call()


func _open_ground(type: StringName, near: Vector3) -> Vector3:
	for ring in range(0, 40):
		for i in maxi(1, ring * 8):
			var a := TAU * i / maxi(1, ring * 8)
			var at := VillageLayout.ground_point(near.x + cos(a) * ring * 2.0, near.z + sin(a) * ring * 2.0)
			if BuildMode.placement_reason(type, at, 0.0, null, true) == "":
				return at
	return Vector3.INF


func _node_of(record: Dictionary) -> PlacedStructure:
	for s in get_tree().get_nodes_in_group("placed_structures"):
		if s.record == record:
			return s
	return null


func _build(type: StringName, near: Vector3, room_for: StringName = &"") -> Dictionary:
	var at := _open_ground(room_for if room_for != &"" else type, near)
	var record := GameState.add_structure(type, at, 0.0)
	await _frames(3)
	var s := _node_of(record)
	while not s.is_complete():
		s.add_work(1.0)
	await _frames(3)
	return record


func _enter_house() -> void:
	Interiors.instance.enter(Furnishings.place_of(_record), _house.doorstep(), _house.rotation.y)
	await _seconds(Interiors.FADE_TIME * 2.0 + 0.3)
	await _frames(3)


func _leave() -> void:
	Interiors.instance.leave()
	await _seconds(Interiors.FADE_TIME * 2.0 + 0.3)
	await _frames(3)


func _set_hour(h: float) -> void:
	WorldClock.set_time(h)
	for v in GameManager.villagers:
		v._decision_timer = 0.0


func _run() -> void:
	print("== Home life test ==")
	WorldClock.day = 1
	WorldClock.set_time(10.0)
	WorldClock.set_time_scale(0.0)
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_main)
	await _frames(40)
	if Weather.instance:
		Weather.instance.set_weather(Weather.Kind.CLEAR, 480.0, true)
	for r in GameState.RESOURCES:
		GameState.add(r, 500)
	# A medium house (living room in front, bedroom behind a wall with a doorway).
	var plaza: Vector3 = VillageLayout.get_nav_nodes().get("plaza", Vector3.ZERO)
	_record = await _build(&"house_medium", plaza + Vector3(14, 0, 14), &"house_large")
	_house = _node_of(_record)
	_home_id = Population.cottage_home_id(_record)
	await _assigning()
	await _no_duplicates()
	await _walking_home()
	await _sleeping()
	await _indoors_and_out()
	await _morning_and_evening()
	await _visits()
	await _saving()
	await _expand_and_remove()
	Engine.time_scale = 1.0
	print("== %s: %d failure(s) ==" % ["PASSED" if _failures == 0 else "FAILED", _failures])
	get_tree().quit(0 if _failures == 0 else 1)


# --- Giving a house ---------------------------------------------------------------------

func _assigning() -> void:
	print("-- giving a house")
	_check(HomeLife.instance != null and VillageLayout.get_locations().has(_home_id), "a finished house is a place villagers can walk to")
	var mara := _villager("mara")
	var person := Population.get_person("mara")
	var old_home := person.home
	await _enter_house()
	_check(HousePanel.instance._button.visible, "inside a house you built there's a House button")
	HousePanel.instance._button.pressed.emit()
	await _frames(2)
	_check(HousePanel.instance.is_open(), "it opens the House panel")
	var give: Button = HousePanel.instance.find_child("Give_mara", true, false)
	_check(give != null and not give.disabled, "Mara can be chosen")
	_check(give != null and give.text.contains("lives at") and give.text.contains("Suitable"), "it shows where she lives now and that the house suits her: %s" % (give.text.replace("\n", " / ") if give else ""))
	give.pressed.emit()
	await _frames(2)
	var confirm: PanelContainer = HousePanel.instance._confirm
	_check(confirm.visible and HousePanel.instance._confirm_text.text.contains("Mara"), "a confirmation comes first: %s" % HousePanel.instance._confirm_text.text)
	_check(person.home == old_home, "nothing changes before confirming")
	(HousePanel.instance.find_child("ConfirmYes", true, false) as Button).pressed.emit()
	await _frames(2)
	_check(person.home == _home_id and Population.is_given_house(_record), "confirmed: the house is Mara's")
	_check(mara.data.home_location == _home_id, "and she knows it's her home now")
	_check(Population.residents_of(old_home).find("mara") < 0, "she no longer lives at her old home")
	_check(Population.homes().any(func(h): return h["id"] == _home_id and h["kind"] == "house"), "the house counts as a home in the village")
	HousePanel.instance.close_panel()
	await _leave()
	_check(_house.get_interaction_verb() in ["Enter", "Knock"] and _house.get_interaction_prompt().contains("Mara"), "outside, the door says whose home it is: %s" % _house.get_interaction_prompt())


func _no_duplicates() -> void:
	print("-- no double assignments")
	var elias := Population.get_person("elias")
	var before := elias.home
	var why := Population.house_unsuitable_reason(_record, elias)
	_check(why.contains("Mara already lives here"), "a house with someone in it can't go to another household: %s" % why)
	_check(Population.give_house(_record, elias) != "" and elias.home == before, "and giving it anyway does nothing")
	# A second house for Mara: she moves, she never has two.
	var second := await _build(&"house", VillageLayout.get_nav_nodes().get("plaza", Vector3.ZERO) + Vector3(-16, 0, 16))
	var err := Population.give_house(second, Population.get_person("mara"))
	_check(err == "" and Population.get_person("mara").home == Population.cottage_home_id(second), "Mara can move to another house")
	_check(Population.residents_of(_home_id).is_empty() and not Population.is_given_house(_record), "her first house is empty and yours again")
	err = Population.give_house(_record, Population.get_person("mara"))
	_check(err == "" and Population.get_person("mara").home == _home_id and not Population.is_given_house(second), "and back again (the other house is yours again)")
	_check(Population.residents_of(_home_id) == ["mara"], "one household per house: %s" % str(Population.residents_of(_home_id)))
	# Unfinished or bed-less houses aren't suitable.
	var unfinished := GameState.add_structure(&"house", _open_ground(&"house", Vector3(40, 0, 40)), 0.0)
	_check(Population.house_unsuitable_reason(unfinished, elias).contains("finished"), "an unfinished house can't be given")
	GameState.remove_structure(unfinished)


# --- Walking home -------------------------------------------------------------------------

func _walking_home() -> void:
	print("-- walking home")
	var mara := _villager("mara")
	_set_hour(19.6)
	await _until(func(): return mara.state == Villager.State.PERFORMING and mara.get_location_id() != _home_id, 30.0)
	_set_hour(22.2)
	var door := HomeLife.door_of(_home_id)
	var through_wall := [0]
	var max_near := [0.0]
	var footprint: Vector2 = _house.get_info()["footprint"]
	var watch := func():
		# Never walking through the house: inside its footprint only at the door.
		var local := _house.global_transform.affine_inverse() * mara.global_position
		if absf(local.x) < footprint.x * 0.5 - 0.3 and absf(local.z) < footprint.y * 0.5 - 0.6 and mara.visible:
			through_wall[0] += 1
	var arrived := await _until(func(): return mara.state == Villager.State.INSIDE, 120.0, watch)
	_check(arrived, "at bedtime Mara walks home and goes in (state %d, at %s)" % [mara.state, mara.get_location_id()])
	_check(mara.get_location_id() == _home_id, "into her new house, not her old one")
	_check(through_wall[0] == 0, "she never walks through the house's walls (%d frames inside)" % through_wall[0])
	var threshold: Vector3 = door["threshold"]
	_check(Vector2(mara.global_position.x - threshold.x, mara.global_position.z - threshold.z).length() < 0.5,
		"she went in through the front door")
	_check(mara.current_activity.is_sleep(), "to sleep")


# --- Sleeping -----------------------------------------------------------------------------

func _sleeping() -> void:
	print("-- sleeping in her own bed")
	var mara := _villager("mara")
	var bed := HomeLife.bed_for("mara", _home_id)
	_check(not bed.is_empty() and String(bed["type"]) in ["bed", "bed_double"] and String(bed["place"]) == Furnishings.place_of(_record),
		"she has a bed in her house")
	await _enter_house()
	_check(mara.state == Villager.State.HOME and mara.visible, "seen inside: she's there")
	var piece = Furnishings.instance.body_of(bed)
	var mattress: Vector3 = piece.global_transform * FurnitureCatalog.mattress(piece.type)
	_check(Vector2(mara.global_position.x - mattress.x, mara.global_position.z - mattress.z).length() < 0.3, "lying in her bed")
	await _frames(5)
	_check(mara.model.current_animation() == &"sleep" if mara.model.has_method("current_animation") else true, "asleep")
	_check(HomeLife.instance._agents[mara]["plan"]["kind"] == "sleep", "her plan is to sleep until morning")
	await _leave()
	_check(mara.state == Villager.State.INSIDE and not mara.visible, "when you leave she's still at home, out of sight")


# --- Inside: in, room to room, out ------------------------------------------------------------

func _wall_crossings(samples: Array) -> int:
	var l := HouseInterior.layout(&"house_medium")
	var bad := 0
	for i in range(1, samples.size()):
		var a: Vector2 = samples[i - 1]
		var b: Vector2 = samples[i]
		for w in l["walls"]:
			var y := float(w[1])
			if (a.y - y) * (b.y - y) < 0.0:
				var x := a.x + (b.x - a.x) * (y - a.y) / (b.y - a.y)
				var through := false
				for c in w[4]:
					if absf(x - float(c)) < 0.8:
						through = true
				if not through:
					bad += 1
	return bad


func _indoors_and_out() -> void:
	print("-- inside: coming home, room to room, going out")
	var mara := _villager("mara")
	# Morning: she leaves while you watch from inside.
	await _enter_house()
	_set_hour(5.6)
	var samples: Array = []
	var record_pos := func():
		if mara.state == Villager.State.HOME:
			var p := mara.global_position - Interiors.ROOM_ORIGIN
			samples.append(Vector2(p.x, p.z))
	var left := await _until(func(): return mara.state != Villager.State.HOME and mara.state != Villager.State.INTERACTING, 60.0, record_pos)
	_check(left and mara.visible and mara.state == Villager.State.TRAVELING, "in the morning she gets up and walks out (state %d)" % mara.state)
	var size: Vector2 = HouseDesigns.size_info(&"house_medium")["inside"]
	_check(not samples.is_empty() and samples.all(func(p): return absf(p.x) <= size.x * 0.5 and absf(p.y) <= size.y * 0.5), "always inside the rooms")
	_check(_wall_crossings(samples) == 0, "from the bedroom to the front door through the doorway, never a wall")
	var exit: Vector2 = HomeLife.instance.entry_point() if HomeLife.instance.room_home != "" else Vector2(0, size.y * 0.5 - 0.75)
	_check(not samples.is_empty() and (samples[-1] as Vector2).distance_to(exit) < 0.6, "out by the front door")
	var door := HomeLife.door_of(_home_id)
	var step: Vector3 = door["step"]
	_check(mara.global_position.distance_to(VillageLayout.ground_point(step.x, step.z)) < 3.0 or mara.global_position.distance_to(door["threshold"]) < 3.0,
		"and she's outside her front door")
	# Coming home while you're inside: in through the door, to her bed.
	_set_hour(22.2)
	samples.clear()
	var came := await _until(func(): return mara.state == Villager.State.HOME and (HomeLife.instance._agents.get(mara, {"i": 0, "path": [1]})["i"] >= (HomeLife.instance._agents[mara]["path"] as PackedVector2Array).size()), 150.0, record_pos)
	_check(came, "at night she comes home and walks in while you're there")
	_check(samples.size() > 5 and (samples[0] as Vector2).distance_to(Vector2(0, size.y * 0.5 - 0.75)) < 0.6, "through the front door, not appearing in a room")
	_check(_wall_crossings(samples) == 0, "and through the doorway to the bedroom")
	_check(HomeLife.instance._agents[mara]["plan"]["kind"] == "sleep", "to sleep in her bed")
	await _leave()


# --- Morning and evening (outside) ----------------------------------------------------------

func _morning_and_evening() -> void:
	print("-- morning departure, evening return")
	var mara := _villager("mara")
	_set_hour(5.6)
	var out := await _until(func(): return mara.state == Villager.State.PERFORMING, 120.0)
	_check(out and mara.get_location_id() != _home_id, "in the morning she goes out to her day (%s)" % mara.get_activity_description())
	_set_hour(13.5)
	await _until(func(): return mara.state == Villager.State.PERFORMING and mara.get_location_id() != _home_id, 60.0)
	_check(mara.get_location_id() != _home_id, "she spends the day out: %s" % mara.get_activity_description())
	_set_hour(22.2)
	var back := await _until(func(): return mara.state == Villager.State.INSIDE, 120.0)
	_check(back and mara.get_location_id() == _home_id, "and comes back to her house in the evening")


# --- Visits ------------------------------------------------------------------------------------

func _visits() -> void:
	print("-- visits")
	var mara := _villager("mara")
	var nia := _villager("nia")
	# Mara at home in the afternoon; Nia comes to visit her.
	_set_hour(15.0)
	mara.brain.use_plan([{"hour": 0.0, "activity": "rest", "location": "home", "label": "Resting at home"}])
	var home := await _until(func(): return mara.state == Villager.State.INSIDE and mara.get_location_id() == _home_id, 120.0)
	_check(home, "Mara spends the afternoon at home")
	await _enter_house()
	_check(mara.state == Villager.State.HOME, "you visit her: she's in (state %d at %s, %s)" % [mara.state, mara.get_location_id(), mara.get_activity_description()])
	await _frames(5)
	_check(mara.is_reacting() or (mara._bubble != null and mara._bubble.visible), "she greets you")
	var before: float = mara.mind.get_affection(GameManager.PLAYER_ID)
	_check(before > 0.0 or mara.mind.get_familiarity(GameManager.PLAYER_ID) > 0, "visiting a friend at home warms your friendship (%.1f)" % before)
	var resting := await _until(func(): return HomeLife.instance._agents.has(mara) and not (HomeLife.instance._agents[mara]["plan"] as Dictionary).is_empty() \
		and HomeLife.instance._agents[mara]["i"] >= (HomeLife.instance._agents[mara]["path"] as PackedVector2Array).size(), 30.0)
	var kind := String(HomeLife.instance._agents[mara]["plan"].get("kind", ""))
	_check(resting and kind in ["sit", "read", "tidy", "relax", "cook", "chat"], "she's doing something at home: %s" % kind)
	nia.brain.use_plan([{"hour": 0.0, "activity": "visit", "location": _home_id, "label": "Visiting Mara"}])
	nia._decision_timer = 0.0
	var arrived := await _until(func(): return nia.state == Villager.State.HOME, 150.0)
	_check(arrived, "Nia walks over and comes in to visit")
	_check(HomeLife.instance.is_guest(nia), "as a guest")
	var host_plan: Dictionary = HomeLife.instance._agents[mara]["plan"]
	_check(String(host_plan.get("kind", "")) == "chat" and host_plan.get("with") == nia, "Mara comes to welcome her")
	var talking := await _until(func(): return String(HomeLife.instance._agents.get(nia, {"plan": {}})["plan"].get("kind", "")) in ["sit", "chat"], 40.0)
	_check(talking, "Nia sits down or chats")
	var aff0: float = nia.mind.get_affection("mara")
	if SocialLife.instance:
		SocialLife.instance.spend_time(nia, mara, 1.0)
	_check(nia.mind.get_affection("mara") > aff0, "time together makes them closer friends")
	nia.brain.plan_day(WorldClock.day)
	await _leave()
	# Inviting a friend to your own house.
	var own := await _build(&"house", VillageLayout.get_nav_nodes().get("plaza", Vector3.ZERO) + Vector3(18, 0, -18))
	var own_home := Population.cottage_home_id(own)
	var tomas := _villager("tomas")
	_set_hour(14.0)
	var t_before: float = tomas.mind.get_affection(GameManager.PLAYER_ID)
	_check(HomeLife.instance.invite_reason(tomas, _home_id) != "", "you can't invite people to someone else's house")
	_check(HomeLife.instance.invite(tomas, own_home) == "", "you can invite Tomas to your own house")
	_check(HomeLife.instance.invite(tomas, own_home) != "", "but not twice at once")
	var came := await _until(func(): return tomas.state == Villager.State.INSIDE and tomas.get_location_id() == own_home, 150.0)
	_check(came, "he walks over and comes in")
	_check(tomas.mind.get_affection(GameManager.PLAYER_ID) >= t_before + HomeLife.INVITE_AFFECTION - 0.01, "being invited makes him like you more")
	HomeLife.instance.invites.clear()
	_set_hour(22.5)
	_check(HomeLife.instance.invite_reason(tomas, own_home).contains("late"), "no invitations late at night")
	mara.brain.plan_day(WorldClock.day)


# --- Saving -------------------------------------------------------------------------------------

func _saving() -> void:
	print("-- saving and loading")
	var pop: Dictionary = JSON.parse_string(JSON.stringify(Population.to_dict()))
	var gs: Dictionary = JSON.parse_string(JSON.stringify(GameState.to_dict()))
	HomeLife.instance.invites["tomas"] = {"home": "home_s1", "until": 99.0, "arrived": false}
	var hl: Dictionary = JSON.parse_string(JSON.stringify(HomeLife.instance.to_dict()))
	Population.get_person("mara").home = "home_mara"
	HomeLife.instance.invites.clear()
	Population.from_dict(pop)
	HomeLife.instance.from_dict(hl)
	for v in GameManager.villagers:
		v.person = Population.get_person(String(v.data.id))
	var saved_house: Array = (gs.get("structures", []) as Array).filter(func(r): return int(r.get("uid", -1)) == int(_record["uid"]))
	_check(Population.get_person("mara").home == _home_id, "Mara's home survives a save")
	_check(saved_house.size() == 1 and Population.is_given_house(saved_house[0]), "and so does who the house belongs to")
	_check(Population.residents_of(_home_id) == ["mara"] and String(Population.home_owners.get(_home_id, "")) == "mara", "and who lives in it")
	_check(HomeLife.instance.invites.has("tomas"), "invitations survive a save")
	HomeLife.instance.invites.clear()
	# Reopening at night: she's placed at home, inside.
	await _frames(5)
	HomeLife.instance.register_all()
	var mara := _villager("mara")
	mara.brain.plan_day(WorldClock.day)
	_set_hour(23.0)
	mara._place_for_current_time()
	_check(mara.state == Villager.State.INSIDE and mara.get_location_id() == _home_id, "reopened at night, she's asleep in her house (state %d at %s)" % [mara.state, mara.get_location_id()])
	_check(not HomeLife.bed_for("mara", _home_id).is_empty(), "with her bed")


# --- Expanding and removing ------------------------------------------------------------------

func _expand_and_remove() -> void:
	print("-- expanding and removing")
	var mara := _villager("mara")
	var house := _node_of(_record)
	var why := BuildMode.instance.upgrade(house)
	_check(why == "", "Mara's house can be expanded %s" % why)
	_check(not HomeLife.home_available(_home_id) and Population.get_person("mara").home == _home_id, "while it's being built she keeps it")
	_set_hour(23.0)
	await _until(func(): return mara.get_location_id() != _home_id, 30.0)
	_check(mara.get_location_id() != _home_id, "but stays somewhere else meanwhile (%s)" % mara.get_location_id())
	while not house.is_complete():
		house.add_work(1.0)
	await _frames(3)
	_check(HomeLife.home_available(_home_id), "finished: the bigger house is her home again")
	mara._decision_timer = 0.0
	var back := await _until(func(): return mara.state == Villager.State.INSIDE and mara.get_location_id() == _home_id, 150.0)
	_check(back, "and she goes back to it")
	BuildMode.instance.remove(house)
	await _frames(3)
	var person := Population.get_person("mara")
	_check(person.home != _home_id and person.home != "", "removing the house: she moves back to her old home (%s)" % person.home)
	_check(not VillageLayout.get_locations().has(_home_id), "and nobody walks to it any more")
