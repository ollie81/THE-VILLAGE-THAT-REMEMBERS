extends Node
## Headless test of Stage 5 of the living world: monsters.
## Danger zones; the right monsters in the right places at the right hours;
## a cap on how many are about; none in the village; they leave the unarmed
## alone; real fights (wind-up, strike, block, beat them for loot); the
## dragon's lair, its reward and its return; saving.
## Run:  godot --headless --path . res://tests/monsters_test.tscn

var _failures: int = 0
var _main = null


func _ready() -> void:
	SaveService.enabled = false
	CreditRewards.enabled = false  # counts credits exactly
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


func _put_player(at: Vector3) -> void:
	var player: PlayerController = GameManager.player
	player.global_position = Vector3(at.x, VillageLayout.get_walk_height(at.x, at.z) + 0.3, at.z)
	player.velocity = Vector3.ZERO


func _scan(times: int) -> void:
	var spawner := MonsterSpawner.instance
	for i in times:
		spawner._scan = 0.0
		spawner._process(0.01)
		await _frames(2)


func _clear() -> void:
	for m in MonsterSpawner.instance.active():
		m.free()
	MonsterSpawner.instance._dragon = null


func _run() -> void:
	print("== Monsters test ==")
	WorldClock.set_time(10.0)
	WorldClock.set_time_scale(0.0)
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_main)
	await _frames(40)
	Weather.instance.set_weather(Weather.Kind.CLEAR, 400.0, true)
	_zones()
	_kinds()
	await _spawning()
	await _unarmed()
	await _fight()
	await _safe_ground()
	await _dragon()
	print("== %s: %d failure(s) ==" % ["PASSED" if _failures == 0 else "FAILED", _failures])
	get_tree().quit(0 if _failures == 0 else 1)


func _zones() -> void:
	_check(MonsterZones.zone_at(0, 0) == MonsterZones.SAFE, "the village is safe")
	_check(MonsterZones.zone_at(-30, -120) == MonsterZones.SAFE and MonsterZones.zone_at(0, 115) == MonsterZones.SAFE, "the farmland and the south street are safe")
	var lake := VillageLayout.LAKE_CENTER
	_check(MonsterZones.zone_at(lake.x, lake.z) == MonsterZones.FOREST, "the forest lake is in the risky forest")
	var tower: Vector3 = VillageLayout.get_nav_nodes()["watchtower"]
	_check(MonsterZones.zone_at(tower.x, tower.z) == MonsterZones.WILDS, "the watchtower stands at the edge of the dangerous wilds")
	var lair := MonsterSpawner.DRAGON_LAIR
	var slope := 0.0
	for o in [Vector3(4, 0, 0), Vector3(-4, 0, 0), Vector3(0, 0, 4), Vector3(0, 0, -4)]:
		slope = maxf(slope, absf(TerrainGenerator.get_height(lair.x + o.x, lair.z + o.z) - TerrainGenerator.get_height(lair.x, lair.z)))
	_check(MonsterZones.zone_at(lair.x, lair.z) == MonsterZones.WILDS and slope < 2.5 and maxf(absf(lair.x), absf(lair.z)) < VillageLayout.MOUNTAINS_FROM - 8.0,
		"the dragon's lair is in the wilds, on ground you can reach (slope %.1f m over 4 m)" % slope)


func _kinds() -> void:
	var ok := true
	var bad := []
	for kind in Monster.KINDS:
		var info: Dictionary = Monster.KINDS[kind]
		var scene := load("res://assets/quaternius/%s.fbx" % info["model"]) as PackedScene
		if scene == null:
			ok = false
			bad.append(kind)
			continue
		var node := scene.instantiate()
		var ap: AnimationPlayer = node.find_children("*", "AnimationPlayer", true, false)[0]
		var clips := Array(ap.get_animation_list()).map(func(c): return String(c).get_slice("|", 1))
		for c in info["clips"]:
			if String(c) != "" and not String(c) in clips:
				ok = false
				bad.append("%s:%s" % [kind, c])
		node.free()
	_check(ok, "all %d monsters load with their animations %s" % [Monster.KINDS.size(), bad])


## Kinds seen over several rounds of filling the area round `at` (cleared
## between rounds), so a check never hangs on one lucky or unlucky batch.
func _gather(at: Vector3, rounds: int) -> Dictionary:
	var kinds := {}
	_put_player(at)
	for r in rounds:
		_clear()
		await _scan(10)
		for m in MonsterSpawner.instance.active():
			kinds[m.kind] = int(kinds.get(m.kind, 0)) + 1
	return kinds


func _spawning() -> void:
	var spawner := MonsterSpawner.instance
	spawner._rng.seed = 2026  # the same monsters every run
	_put_player(Vector3(0, 0, 10))
	await _scan(6)
	_check(spawner.active().is_empty(), "no monsters appear while you're in the village")
	# The forest by day.
	var forest := VillageLayout.LAKE_CENTER + Vector3(30, 0, 30)
	_put_player(forest)
	await _scan(12)
	var kinds := {}
	var in_safe := false
	var nearest := INF
	for m in spawner.active():
		kinds[m.kind] = true
		in_safe = in_safe or MonsterZones.zone_at(m.global_position.x, m.global_position.z) == MonsterZones.SAFE
		nearest = minf(nearest, Vector2(m.global_position.x - forest.x, m.global_position.z - forest.z).length())
	_check(spawner.active().size() > 0, "out in the forest, monsters appear (%d)" % spawner.active().size())
	_check(kinds.keys().all(func(k): return k in [&"slime", &"bat"]), "by day the forest has slimes and bats (%s)" % str(kinds.keys()))
	_check(spawner.active().size() <= spawner.cap(), "never more than %d about at once" % spawner.cap())
	_check(nearest > 18.0, "they appear a little way off, not on top of you (nearest %.0f m)" % nearest)
	_check(not in_safe, "none appear on safe ground")
	# Night.
	_clear()
	WorldClock.set_time(23.0)
	await _scan(14)
	var skeletons := spawner.active().filter(func(m): return m.kind == &"skeleton").size()
	var night_kinds := await _gather(forest, 4)
	_check(skeletons > 0 and int(night_kinds.get(&"skeleton", 0)) > 0 and not night_kinds.has(&"slime"), "at night skeletons rise in the forest (%d; over 4 rounds %s)" % [skeletons, str(night_kinds)])
	WorldClock.set_time(10.0)
	_clear()
	# The wilds by day.
	var wilds := Vector3(112, 0, 30)
	var wild_kinds := await _gather(wilds, 5)
	_check(int(wild_kinds.get(&"wolf", 0)) > 0 and not wild_kinds.has(&"slime"), "wolves hunt in the wilds, and no forest slimes (over 5 rounds %s)" % str(wild_kinds))
	_put_player(wilds)
	await _scan(14)
	_check(spawner.active().filter(func(m): return m.kind != &"dragon").size() <= spawner.cap(), "the cap holds in the wilds too")
	# Going home tidies them away.
	_put_player(Vector3(0, 0, 10))
	await _scan(2)
	await _frames(3)
	_check(spawner.active().filter(func(m): return m.kind != &"dragon").is_empty(), "back in the village, the monsters left behind are gone")
	_clear()


func _unarmed() -> void:
	GameState.set_flag(&"has_sword", false)
	var spot := VillageLayout.LAKE_CENTER + Vector3(30, 0, 30)
	_put_player(spot)
	var m := MonsterSpawner.instance.spawn(&"wolf", Vector3(spot.x + 4, TerrainGenerator.get_height(spot.x + 4, spot.z) + 0.3, spot.z))
	var player: PlayerController = GameManager.player
	var health: float = player.combat.health
	await _seconds(2.5)
	_check(m.state == Monster.State.WARY, "without a sword a wolf watches you warily (state %d)" % m.state)
	_check(player.combat.health == health, "and doesn't attack someone unarmed")
	m.free()


func _fight() -> void:
	GameState.set_flag(&"has_sword", true)
	var spot := VillageLayout.LAKE_CENTER + Vector3(30, 0, 30)
	_put_player(spot)
	var player: PlayerController = GameManager.player
	player.combat.heal_full()
	var m := MonsterSpawner.instance.spawn(&"slime", Vector3(spot.x + 3, TerrainGenerator.get_height(spot.x + 3, spot.z) + 0.3, spot.z))
	var saw_windup := false
	var t := 0.0
	var health: float = player.combat.health
	while t < 6.0 and player.combat.health >= health:
		await _frames(1)
		t += get_process_delta_time()
		saw_windup = saw_windup or m.state == Monster.State.WINDUP
	_check(saw_windup, "an armed player gets chased, and the slime clearly winds up before it strikes")
	_check(player.combat.health < health, "its strike hurts if you don't block (%.0f → %.0f)" % [health, player.combat.health])
	var herbs := GameState.count(&"herbs")
	var hits := 0
	while m.is_alive() and hits < 10:
		m.take_hit(player.combat.damage(), player.global_position)
		hits += 1
	_check(not m.is_alive() and hits == Monster.KINDS[&"slime"]["health"], "%d sword hits beat a slime" % hits)
	_check(GameState.count(&"herbs") == herbs + 1, "and it leaves an herb behind")
	await _seconds(2.0)
	_check(not is_instance_valid(m), "then fades away")
	player.combat.heal_full()


func _safe_ground() -> void:
	# Stand just inside the village edge: a skeleton outside won't follow you in.
	var edge := Vector3(-MonsterZones.SAFE_HALF + 2.0, 0, 20)
	_put_player(edge)
	var outside := Vector3(-MonsterZones.SAFE_HALF - 6.0, 0, 20)
	var m := MonsterSpawner.instance.spawn(&"skeleton", Vector3(outside.x, TerrainGenerator.get_height(outside.x, outside.z) + 0.3, outside.z))
	await _seconds(3.0)
	_check(MonsterZones.zone_at(m.global_position.x, m.global_position.z) != MonsterZones.SAFE, "monsters never set foot on the village's safe ground (skeleton at x %.1f)" % m.global_position.x)
	_check(m.state != Monster.State.STRIKE and m.state != Monster.State.WINDUP, "and won't fight you there")
	m.free()


func _dragon() -> void:
	var spawner := MonsterSpawner.instance
	var lair := MonsterSpawner.DRAGON_LAIR
	_put_player(lair + Vector3(-20, 0, 0))
	await _scan(2)
	var dragon: Monster = spawner._dragon
	_check(dragon != null and dragon.kind == &"dragon", "a dragon waits at its lair in the wilds")
	if dragon == null:
		return
	var credits := VillageCredits.instance.balance
	var hits := 0
	while dragon.is_alive() and hits < 40:
		dragon.take_hit(1, dragon.global_position + Vector3(-3, 0, 0))
		hits += 1
	_check(hits == 20, "the dragon is tough (%d hits)" % hits)
	_check(VillageCredits.instance.balance == credits + 40, "driving it off earns 40 credits")
	_check(spawner.dragon_beaten_day == WorldClock.day, "the day is remembered")
	await _seconds(2.0)
	await _scan(2)
	_check(spawner._dragon == null or not is_instance_valid(spawner._dragon) or not spawner._dragon.is_alive(), "it doesn't come straight back")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(spawner.to_dict()))
	spawner.from_dict({})
	spawner.from_dict(saved)
	_check(spawner.dragon_beaten_day == WorldClock.day and not spawner.dragon_due(), "saved: it stays away for a few days after loading")
	WorldClock.day += MonsterSpawner.DRAGON_DAYS
	_check(spawner.dragon_due(), "and returns %d days later" % MonsterSpawner.DRAGON_DAYS)
	WorldClock.day -= MonsterSpawner.DRAGON_DAYS
	_clear()
