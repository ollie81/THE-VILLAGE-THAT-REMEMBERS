extends Node
## Headless test of Stage 6 of the living world: village defence.
## Guards, the alarm bell, a raid with a warning, guards fighting it while
## everyone else gathers at the meeting circle, the player joining in for a
## reward, guards falling back hurt, a raid that gives up, raids staying rare,
## and saving.
## Run:  godot --headless --path . res://tests/defence_test.tscn

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
	print("== Defence test ==")
	WorldClock.set_time(17.0)
	WorldClock.set_time_scale(0.0)
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_main)
	await _frames(40)
	Weather.instance.set_weather(Weather.Kind.CLEAR, 400.0, true)
	MonsterSpawner.instance.set_process(false)
	var defence := VillageDefence.instance
	_check(defence != null, "the village has a defence")
	var guards := defence.guards()
	_check(guards.size() == 2, "it has two guards (%s)" % ", ".join(guards.map(func(g): return g.data.display_name)))
	_check(guards.any(func(g): return String(g.data.id) == "mara"), "Mara, the bravest, is one of them")
	var bell := defence.bell_position()
	_check(Vector2(bell.x, bell.z).length() < VillageLayout.PLAZA_RADIUS + 6.0 and VillageLayout.blocking_reason(bell.x, bell.z, 0.6, 0.0) == "", "an alarm bell stands by the meeting circle, on clear ground")
	await _warning(defence, guards)
	await _raid(defence, guards)
	await _guard_falls(defence)
	await _gives_up(defence)
	_rare(defence)
	print("== %s: %d failure(s) ==" % ["PASSED" if _failures == 0 else "FAILED", _failures])
	get_tree().quit(0 if _failures == 0 else 1)


func _warning(defence: VillageDefence, guards: Array) -> void:
	defence.schedule_raid("west road", WorldClock.time_of_day + 1.0)
	await _frames(3)
	_check(defence.phase == VillageDefence.Phase.WARNED, "an hour and a half before, you're warned a raid is coming")
	var geared := guards.all(func(g): return defence._gear.has(String(g.data.id)) and defence._gear[String(g.data.id)][0].visible)
	_check(geared, "the guards take up a sword and shield you can see")
	_check(guards.all(func(g): return g.has_task()), "and head out to the village edge to wait")


func _raid(defence: VillageDefence, guards: Array) -> void:
	var edge := defence.edge_point()
	# Fast-forward the walk: the guards are at the edge when it starts.
	for g in guards:
		g.global_position = VillageLayout.ground_point(edge.x + 1.0, edge.z + randf_range(-2, 2))
	WorldClock.set_time(WorldClock.time_of_day + 1.05)
	await _frames(3)
	_check(defence.is_raid(), "at the hour, the raid begins")
	_check(defence._bell_swing > 0.0, "the alarm bell rings")
	var raiders := defence.raiders_left()
	_check(raiders.size() >= 3 and raiders.all(func(m): return m.raider), "raiders come down the road (%d)" % raiders.size())
	# Everyone else gathers at the meeting circle.
	var others := GameManager.villagers.filter(func(v): return not defence.is_guard(v))
	var gathering := 0
	for v in others:
		var act: VillagerActivity = v.brain.choose_activity(v, WorldClock.time_of_day)
		if act and act.reason == "raid" and act.location_id == "plaza":
			gathering += 1
	_check(gathering == others.size(), "everyone else gathers at the meeting circle (%d of %d)" % [gathering, others.size()])
	# You're there with your sword from the start; the guards fight alongside.
	GameState.set_flag(&"has_sword", true)
	var player: PlayerController = GameManager.player
	player.global_position = VillageLayout.ground_point(edge.x + 6.0, edge.z) + Vector3(0, 0.3, 0)
	player.combat.heal_full()
	var credits := VillageCredits.instance.balance
	Engine.time_scale = 4.0
	await _seconds(6.0)
	Engine.time_scale = 1.0
	player.combat.heal_full()
	var hurt := raiders.filter(func(m): return not is_instance_valid(m) or m.health < m.max_health).size()
	_check(hurt > 0, "the guards fight the raiders (%d of %d hurt or beaten)" % [hurt, raiders.size()])
	var deepest := 0.0
	for m in defence.raiders_left():
		deepest = maxf(deepest, Vector2(m.global_position.x - edge.x, m.global_position.z - edge.z).length())
	_check(defence.raiders_left().all(func(m): return Vector2(m.global_position.x, m.global_position.z).length() > 40.0), "the raiders get no further than the village edge")
	# And you finish it.
	_check(defence.is_raid() and not defence.raiders_left().is_empty(), "the raid is still on when you step in (%d left)" % defence.raiders_left().size())
	var mine := 0
	for m in defence.raiders_left():
		while m.is_alive():
			m.take_hit(1, player.global_position)
		mine += 1
	await _frames(3)
	_check(not defence.is_raid() and defence.raids_repelled == 1, "when the last raider falls, the raid is over")
	var expected := VillageDefence.REWARD_HELPED + VillageDefence.REWARD_PER_RAIDER * mine
	_check(VillageCredits.instance.balance == credits + expected, "helping earns %d credits (%d → %d)" % [expected, credits, VillageCredits.instance.balance])
	_check(guards.all(func(g): return not g.has_task() and not defence._gear[String(g.data.id)][0].visible), "the guards put their swords away and go back to their day")
	var back := 0
	for v in others:
		var act: VillagerActivity = v.brain.choose_activity(v, WorldClock.time_of_day)
		if act == null or act.reason != "raid":
			back += 1
	_check(back == others.size(), "and so does everyone else")
	_check(defence.next_raid_day >= WorldClock.day + VillageDefence.DAYS_BETWEEN.x, "the next raid is days away (day %d)" % defence.next_raid_day)
	GameState.set_flag(&"has_sword", false)


func _guard_falls(defence: VillageDefence) -> void:
	defence.start_raid("north road")
	var g = defence.guards()[0]
	for i in 10:
		defence.guard_hit(g, 12.0, g.global_position + Vector3(1, 0, 0))
	_check(not defence.fighting_guards().has(g), "a guard knocked down stops fighting")
	_check(g.has_task() and String(g.current_activity.label).contains("falling back"), "and falls back to the meeting circle, hurt")
	defence._end_raid(false, true)


func _gives_up(defence: VillageDefence) -> void:
	defence.start_raid("east woods")
	var raiders := defence.raiders_left()
	WorldClock.set_time(WorldClock.time_of_day + VillageDefence.RAID_HOURS + 0.2)
	await _frames(3)
	await _frames(2)
	_check(not defence.is_raid() and raiders.all(func(m): return not is_instance_valid(m) or m.is_queued_for_deletion()), "a raid nobody beats melts back into the woods after a while")


func _rare(defence: VillageDefence) -> void:
	defence.next_raid_day = VillageDefence.FIRST_RAID_DAY
	var raids := 0
	var first := -1
	var day0 := WorldClock.day
	for day in range(1, 31):
		defence.raid_hour = -1.0
		defence.phase = VillageDefence.Phase.QUIET
		defence._on_new_day(day)
		if defence.raid_hour > 0.0:
			raids += 1
			if first < 0:
				first = day
			defence.next_raid_day = day + defence._rng.randi_range(VillageDefence.DAYS_BETWEEN.x, VillageDefence.DAYS_BETWEEN.y)
	_check(first >= VillageDefence.FIRST_RAID_DAY, "no raid before day %d (first on day %d)" % [VillageDefence.FIRST_RAID_DAY, first])
	_check(raids >= 2 and raids <= 7, "raids are rare: %d in a month" % raids)
	defence.raid_hour = -1.0
	var saved: Dictionary = JSON.parse_string(JSON.stringify(defence.to_dict()))
	defence.from_dict({})
	defence.from_dict(saved)
	_check(defence.raids_repelled == 1 and defence.next_raid_day == int(saved["next_raid_day"]), "saved: raids driven off and when the next may come")
