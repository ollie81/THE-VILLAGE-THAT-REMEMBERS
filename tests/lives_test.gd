extends Node
## Headless test of Stage 4 of the living world: villagers' daily lives.
## Varied days shaped by job and personality (the big fields, the farm
## animals, fishing at the lake and pond, market, visiting friends, walks,
## cooking), the same plan for the same day, sheltering from rain, keeping
## away from thornlings and fights, and actually walking to the new places.
## Run:  godot --headless --path . res://tests/lives_test.tscn

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


func _adults() -> Array:
	return GameManager.villagers.filter(func(v):
		var p: Person = Population.get_person(String(v.data.id))
		return p != null and p.is_resident() and p.life_stage() in [Person.STAGE_ADULT, Person.STAGE_ELDER])


func _run() -> void:
	print("== Lives test ==")
	WorldClock.set_time(10.0)
	WorldClock.set_time_scale(0.0)
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_main)
	await _frames(40)
	Weather.instance.set_weather(Weather.Kind.CLEAR, 400.0, true)
	_check(GameManager.villagers.all(func(v): return v.brain is LifeBrain), "every villager lives by a daily-life brain (%d people)" % GameManager.villagers.size())
	_plans()
	_friends()
	await _rain()
	await _danger()
	await _walking()
	print("== %s: %d failure(s) ==" % ["PASSED" if _failures == 0 else "FAILED", _failures])
	get_tree().quit(0 if _failures == 0 else 1)


## Two weeks of plans for everyone: what they get up to.
func _plans() -> void:
	var labels := {}
	var locations := {}
	var differs := 0
	var adults := _adults()
	for v in adults:
		var brain: LifeBrain = v.brain
		var seen := {}
		for day in range(1, 15):
			brain.plan_day(day)
			seen[JSON.stringify(brain.plan)] = true
			for entry in brain.plan:
				labels[String(entry.get("label", ""))] = true
				locations[String(entry.get("location", ""))] = true
		if seen.size() > 1:
			differs += 1
	var text := " ".join(labels.keys())
	_check(differs >= adults.size() * 0.6, "most grown-ups' days vary from day to day (%d of %d)" % [differs, adults.size()])
	_check(locations.has("farmland"), "farmers work the big fields at the farmland")
	var care := ["pasture", "sheepfold", "sty", "paddock"].filter(func(l): return locations.has(l))
	_check(care.size() >= 2, "people look after the farm animals (%s)" % ", ".join(care))
	_check(locations.has("storage") or locations.has("market"), "people go shopping")
	_check(text.contains("Cooking"), "people cook (supper at home, stew for everyone)")
	var walks := ["windmill", "lake_shore", "pond", "south_street_east"].filter(func(l): return locations.has(l))
	_check(walks.size() >= 2, "people walk out into the wider world (%s)" % ", ".join(walks))
	# Every place they plan to go is a real place villagers can reach.
	var unknown := locations.keys().filter(func(l): return l != "" and l != "home" and not VillageLayout.get_locations().has(String(l)))
	_check(unknown.is_empty(), "every planned place exists %s" % str(unknown))
	# Same day, same plan.
	var brain0: LifeBrain = adults[0].brain
	brain0.plan_day(5)
	var a := JSON.stringify(brain0.plan)
	brain0.plan_day(6)
	brain0.plan_day(5)
	_check(JSON.stringify(brain0.plan) == a, "the same person makes the same plan for the same day (nothing extra to save)")
	# Children keep their own days.
	var kids := GameManager.villagers.filter(func(v):
		var p: Person = Population.get_person(String(v.data.id))
		return p != null and p.life_stage() == Person.STAGE_CHILD)
	if not kids.is_empty():
		var kb: LifeBrain = kids[0].brain
		kb.plan_day(3)
		_check(JSON.stringify(kb.plan) == JSON.stringify(kids[0].data.schedule), "children keep their own timetable")
	for v in adults:
		(v.brain as LifeBrain).plan_day(WorldClock.day)


## Friends visit each other at home.
func _friends() -> void:
	var adults := _adults()
	var a = adults[0]
	var visited := 0
	for b in adults.slice(1):
		var pb: Person = Population.get_person(String(b.data.id))
		if pb.home != "" and pb.home != Population.get_person(String(a.data.id)).home and VillageLayout.get_locations().has(pb.home):
			a.mind.adjust_opinion(String(b.data.id), 80.0, 40.0)
	var brain: LifeBrain = a.brain
	for day in range(20, 60):
		brain.plan_day(day)
		for entry in brain.plan:
			if String(entry["activity"]) == "visit":
				visited += 1
	_check(visited > 0, "a villager with friends goes to visit them at home (%d visits in 40 days)" % visited)
	brain.plan_day(WorldClock.day)


func _rain() -> void:
	WorldClock.set_time(10.0)
	await _frames(5)
	var outdoors := []
	for v in _adults():
		var act: VillagerActivity = v.brain.choose_activity(v, WorldClock.time_of_day)
		if act and not act.is_sleep() and not (v.brain as LifeBrain)._is_sheltered(act):
			outdoors.append(v)
	Weather.instance.set_weather(Weather.Kind.RAIN, 4.0, true)
	var sheltering := 0
	var working_on := 0
	var stable := true
	for v in outdoors:
		var act: VillagerActivity = v.brain.choose_activity(v, WorldClock.time_of_day)
		if act.kind == &"shelter" or act.kind == &"visit":
			sheltering += 1
		elif act.reason == "rain_work":
			working_on += 1
		if v.brain.choose_activity(v, WorldClock.time_of_day) != act:
			stable = false
	_check(outdoors.size() > 0 and sheltering >= outdoors.size() * 0.5, "when it rains most people outside go and shelter (%d of %d)" % [sheltering, outdoors.size()])
	_check(sheltering + working_on == outdoors.size(), "the rest are the dutiful sort who work on in the rain (%d)" % working_on)
	_check(stable, "each person's choice holds for the whole shower (no dithering)")
	# They actually go: shelterers head indoors, hurrying.
	await _frames(30)
	var hurrying := 0
	for v in outdoors:
		if v.current_activity and v.current_activity.reason in ["rain", "rain_visit"]:
			hurrying += 1
	_check(hurrying > 0, "villagers set off for shelter (%d hurrying)" % hurrying)
	var someone = outdoors.filter(func(v): return v.current_activity and v.current_activity.kind == &"shelter")
	if not someone.is_empty():
		var v = someone[0]
		var home: Vector3 = v.navigation.get_spot(v.data.home_location, 0)
		v.global_position = VillageLayout.ground_point(home.x + 1.0, home.z + 1.0)
		v.start_activity(v.current_activity)
		await get_tree().create_timer(2.5).timeout
		_check(v.state == v.State.INSIDE, "a villager sheltering from the rain goes inside")
	Weather.instance.set_weather(Weather.Kind.CLEAR, 400.0, true)
	await _frames(5)
	var back := 0
	for v in outdoors:
		var act: VillagerActivity = v.brain.choose_activity(v, WorldClock.time_of_day)
		if act.reason == "":
			back += 1
	_check(back == outdoors.size(), "when the rain stops everyone goes back to their day")


func _danger() -> void:
	var v = _adults()[0]
	var brain: LifeBrain = v.brain
	var act := VillagerActivity.from_entry({"activity": "work", "location": "plaza", "hour": 9.0})
	var player: PlayerController = GameManager.player
	# A fight near them sends them indoors.
	GameState.set_flag(&"has_sword", true)
	player.global_position = v.global_position + Vector3(3, 0.3, 0)
	var thorns := Thornling.new()
	thorns.home = player.global_position + Vector3(2, 0, 0)
	add_child(thorns)
	thorns.global_position = player.global_position + Vector3(2, 0, 0)
	await _frames(5)
	var fighting: bool = player.combat.in_fight()
	var reacted := brain._react(v, act)
	_check(fighting and reacted.kind == &"shelter", "with a fight nearby, people hurry indoors (fight: %s, chose: %s)" % [fighting, reacted.label])
	thorns.queue_free()
	await _frames(5)
	GameState.set_flag(&"has_sword", false)
	_check(brain._react(v, act) == act, "once it's over, they get on with their day")
	# Thornlings out in the woods: nobody goes near.
	var tw := Thornwood.instance
	var near := VillagerActivity.from_entry({"activity": "work", "location": "woodlot", "hour": 9.0})
	if tw and LifeBrain._near("woodlot", tw.center, LifeBrain.DANGER_RADIUS):
		var enemy := Thornling.new()
		tw.add_child(enemy)
		tw._spawned.append(enemy)
		await _frames(2)
		_check(brain._react(v, near).location_id == "plaza", "with thornlings out, nobody works near their clearing")
		tw._spawned.erase(enemy)
		enemy.queue_free()
	else:
		var safe := LifeBrain._near("woodlot", tw.center if tw else Vector3.ZERO, LifeBrain.DANGER_RADIUS)
		_check(not safe, "the woodlot is well away from the thornlings' clearing")


## Someone really walks out to tend the animals and gets there.
func _walking() -> void:
	var v = _adults()[0]
	var gate: Vector3 = VillageLayout.get_nav_nodes()["farmland_gate"]
	v.global_position = VillageLayout.ground_point(gate.x, gate.z)
	v.task = {}
	(v.brain as LifeBrain).use_plan([{"activity": "work", "location": "pasture", "label": "Feeding the cows at the pasture", "anim": "gather", "hour": 0.0}])
	v.start_activity(v.brain.choose_activity(v, WorldClock.time_of_day))
	Engine.time_scale = 6.0
	var t := 0.0
	while t < 40.0 and v.state != v.State.PERFORMING:  # game seconds: it walks ~1.7 m/s
		await get_tree().create_timer(0.5).timeout
		t += 0.5
	Engine.time_scale = 1.0
	var at: Vector3 = v.navigation.get_spot(v._location_id, v._spot_index)  # the spot they took
	var d := Vector2(v.global_position.x - at.x, v.global_position.z - at.z).length()
	_check(v.state == v.State.PERFORMING and v._location_id == "pasture" and d < 2.0, "a villager walks out to the pasture and tends the cows (%.1f m from the spot, %s)" % [d, v.get_activity_description()])
