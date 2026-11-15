extends Node
## Headless test of Stage 2 of the living world: animals (real models with
## animations, saved records, no duplicates, bought one by one, never made by
## buildings), how they behave (wander, rest at night and in rain, flee,
## follow, milking), birds in the sky, and weather (rain, wet ground, wind).
## Run:  godot --headless --path . res://tests/animals_test.tscn

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


func _run() -> void:
	print("== Animals test ==")
	WorldClock.set_time(10.0)
	WorldClock.set_time_scale(0.0)
	_species()
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_main)
	await _frames(40)
	Weather.instance.set_weather(Weather.Kind.CLEAR, 48.0, true)
	_records()
	await _homes_and_buying()
	await _behaviour()
	await _birds()
	_weather()
	print("== %s: %d failure(s) ==" % ["PASSED" if _failures == 0 else "FAILED", _failures])
	get_tree().quit(0 if _failures == 0 else 1)


func _species() -> void:
	var ok := true
	var missing := []
	for species in AnimalSpecies.SPECIES:
		var info := AnimalSpecies.info(species)
		var scene := load(AnimalSpecies.DIR + String(info["model"]) + ".fbx") as PackedScene
		if scene == null:
			ok = false
			missing.append(species)
			continue
		var node := scene.instantiate()
		var players := node.find_children("*", "AnimationPlayer", true, false)
		var clips := []
		if not players.is_empty():
			for c in (players[0] as AnimationPlayer).get_animation_list():
				clips.append(String(c).get_slice("|", 1))
		for want in [String(info["idle"]), String(info["walk_anim"])]:
			if want != "" and not want in clips:
				ok = false
				missing.append("%s:%s" % [species, want])
		node.free()
	_check(ok, "all %d species load with their idle and walk animations %s" % [AnimalSpecies.SPECIES.size(), missing])


func _records() -> void:
	var manager := AnimalManager.instance
	_check(manager.records.size() == AnimalManager.VILLAGE_ANIMALS.size(), "the village's %d animals are created once (%d records)" % [AnimalManager.VILLAGE_ANIMALS.size(), manager.records.size()])
	var ids := {}
	for r in manager.records:
		ids[String(r["id"])] = true
	_check(ids.size() == manager.records.size(), "every animal has its own id")
	# Save and load (through JSON, as on disk) twice: no animal is doubled.
	var saved: Dictionary = JSON.parse_string(JSON.stringify(manager.to_dict()))
	manager.from_dict(saved)
	manager.from_dict(JSON.parse_string(JSON.stringify(manager.to_dict())))
	_check(manager.records.size() == AnimalManager.VILLAGE_ANIMALS.size(), "after saving and loading twice there are still %d animals (%d)" % [AnimalManager.VILLAGE_ANIMALS.size(), manager.records.size()])
	# A save with a duplicated record is cleaned up on load.
	var broken := manager.to_dict()
	(broken["records"] as Array).append((broken["records"] as Array)[0].duplicate())
	manager.from_dict(broken)
	_check(manager.records.size() == AnimalManager.VILLAGE_ANIMALS.size(), "a duplicated record in a save is dropped on load")
	# An older save (before animals) gets the village animals once.
	manager.from_dict({})
	_check(manager.records.size() == AnimalManager.VILLAGE_ANIMALS.size() and manager.village_seeded, "an old save without animals gets the village's animals, once")


func _structure_node(record: Dictionary) -> PlacedStructure:
	for s in get_tree().get_nodes_in_group("placed_structures"):
		if s.record == record:
			return s
	return null


func _finish(record: Dictionary) -> void:
	await _frames(3)
	var s := _structure_node(record)
	while not s.is_complete():
		s.add_work(1.0)
	await _frames(2)


func _homes_and_buying() -> void:
	var manager := AnimalManager.instance
	var credits := VillageCredits.instance
	var before := manager.records.size()
	_check(manager.cannot_buy(&"cow") != "", "a cow can't be bought without a pen (\"%s\")" % manager.cannot_buy(&"cow"))
	_check(manager.cannot_buy(&"horse") != "", "a horse can't be bought without a stable")
	GameState.add(&"wood", 60)
	GameState.add(&"stone", 20)
	var pen_at := BuildMode.nearest_free_spot(&"animal_pen", VillageLayout.ground_point(-30.0, 30.0), 0.0, Vector3(0, 0, 100))
	var pen := GameState.add_structure(&"animal_pen", pen_at, 0.0)
	await _finish(pen)
	var stable_at := BuildMode.nearest_free_spot(&"stable", pen_at + Vector3(11, 0, 0), 0.0, Vector3(0, 0, 100))
	var stable := GameState.add_structure(&"stable", stable_at, 0.0)
	await _finish(stable)
	await _frames(30)
	_check(_structure_node(pen).is_complete() and _structure_node(stable).is_complete(), "an animal pen and a stable can be built")
	_check(manager.records.size() == before, "building a pen and a stable makes no animals (%d → %d)" % [before, manager.records.size()])
	_check(manager.cannot_buy(&"cow").begins_with("Needs"), "with a pen but no credits, a cow needs credits (\"%s\")" % manager.cannot_buy(&"cow"))
	credits.earn(300, "animals_test")
	var balance := credits.balance
	var cow := manager.buy(&"cow")
	_check(not cow.is_empty() and String(cow["home"]) == "pen:%d" % int(pen["uid"]), "buying a cow puts it in the pen (%s)" % cow.get("home", ""))
	_check(credits.balance == balance - int(AnimalSpecies.info(&"cow")["price"]), "the cow costs %d credits" % int(AnimalSpecies.info(&"cow")["price"]))
	_check(manager.records.size() == before + 1, "buying adds exactly one animal")
	var h1 := manager.buy(&"horse")
	var h2 := manager.buy(&"horse")
	_check(not h1.is_empty() and not h2.is_empty() and String(h1["home"]).begins_with("stable:"), "two horses fit in the stable")
	_check(manager.cannot_buy(&"horse") != "", "a third horse needs another stable (\"%s\")" % manager.cannot_buy(&"horse"))
	for i in 3:
		manager.buy(&"sheep")
	_check(manager.cannot_buy(&"pig") != "", "a pen holds 4 animals: no room for a pig (\"%s\")" % manager.cannot_buy(&"pig"))
	var dog := manager.buy(&"dog")
	_check(not dog.is_empty() and String(dog["home"]) == "house", "a dog lives by your home")
	var ids := {}
	for r in manager.records:
		ids[String(r["id"])] = true
	_check(ids.size() == manager.records.size(), "bought animals have unique ids too")
	# Saved and loaded, the bought animals keep their homes and nothing doubles.
	var count := manager.records.size()
	manager.from_dict(JSON.parse_string(JSON.stringify(manager.to_dict())))
	var cow_again := manager.records.filter(func(r): return String(r["id"]) == String(cow["id"]))
	_check(manager.records.size() == count and cow_again.size() == 1 and String(cow_again[0]["home"]) == String(cow["home"]), "after a save and load: %d animals, the cow still in its pen" % manager.records.size())
	# Near the pen, its animals have real bodies; far away they're removed.
	var player: PlayerController = GameManager.player
	player.global_position = Vector3(pen_at.x, VillageLayout.get_walk_height(pen_at.x, pen_at.z) + 0.3, pen_at.z + 9.0)
	await _frames(45)
	var body := manager.node_of(String(cow_again[0]["id"]))
	_check(body != null and body.player_anim != null and body.player_anim.is_playing(), "the cow appears near the player with an animation playing")
	var spawned_ids := {}
	var doubled := false
	for a in get_tree().get_nodes_in_group("animals"):
		if spawned_ids.has(String(a.record["id"])):
			doubled = true
		spawned_ids[String(a.record["id"])] = true
	_check(not doubled, "no animal is spawned twice (%d bodies)" % spawned_ids.size())
	# Every animal has two eyes, and none is left plain white by a model with
	# no colours of its own (dogs and cats get coats).
	var eyeless := []
	var white := []
	for a in get_tree().get_nodes_in_group("animals"):
		if a.find_child("EyeL", true, false) == null or a.find_child("EyeR", true, false) == null:
			eyeless.append(a.species)
		if a.species in [&"dog", &"cat"]:
			var coat_mesh: MeshInstance3D = a.model.find_children("*", "MeshInstance3D", true, false)[0]
			var colour: Color = (coat_mesh.get_active_material(0) as BaseMaterial3D).albedo_color
			if colour.is_equal_approx(Color(0.9063, 0.9063, 0.9063, 1.0)):
				white.append(a.species)
	_check(eyeless.is_empty(), "every animal has two eyes %s" % str(eyeless))
	_check(white.is_empty(), "dogs and cats have coats, not plain white %s" % str(white))
	_check(manager.spawned_count() < manager.records.size(), "only nearby animals are spawned (%d of %d)" % [manager.spawned_count(), manager.records.size()])


func _behaviour() -> void:
	var manager := AnimalManager.instance
	var player: PlayerController = GameManager.player
	var cow_record: Dictionary = manager.owned().filter(func(r): return String(r["species"]) == "cow")[0]
	var cow := manager.node_of(String(cow_record["id"]))
	# Milking: once a day.
	var food := GameState.count(&"food")
	var verb := cow.interact(player)
	_check(verb == "Milk" and GameState.count(&"food") == food + 2, "milking your cow gives 2 food")
	_check(cow._verb() != "Milk", "a cow can only be milked once a day (next: %s)" % cow._verb())
	# Wandering within home.
	var start := cow.global_position
	cow.state = Animal.State.WANDER
	cow._target = manager.home_area(cow_record)["center"] + Vector3(2.5, 0, 0)
	cow._timer = 10.0
	player.global_position += Vector3(0, 0, 4)
	await get_tree().create_timer(1.5).timeout
	_check(cow.global_position.distance_to(start) > 0.3, "an animal walks about (moved %.2f m)" % cow.global_position.distance_to(start))
	var area := manager.home_area(cow_record)
	var off := cow.global_position - Vector3(area["center"])
	off.y = 0
	_check(off.length() < float(area["radius"]) + 1.5, "and keeps to its pen (%.1f m from the middle)" % off.length())
	# Night and rain: rest.
	WorldClock.set_time(23.0)
	cow._choose_next()
	_check(cow.state == Animal.State.REST or cow.state == Animal.State.WANDER, "at night an animal rests (or heads to the middle of home to rest)")
	WorldClock.set_time(10.0)
	Weather.instance.set_weather(Weather.Kind.RAIN, 3.0, true)
	cow.global_position = Vector3(area["center"]) + Vector3(0, cow.global_position.y, 0)
	cow._choose_next()
	_check(cow.state == Animal.State.REST, "in the rain an animal rests")
	Weather.instance.set_weather(Weather.Kind.CLEAR, 48.0, true)
	# A skittish sheep runs from someone running at it.
	var sheep: Animal = null
	for a in get_tree().get_nodes_in_group("animals"):
		if a.species == &"sheep":
			sheep = a
	if sheep:
		sheep.state = Animal.State.IDLE
		player.global_position = sheep.global_position + Vector3(1.2, 0.3, 0)
		player.velocity = Vector3(-6, 0, 0)
		sheep._react(player, 0.15)
		player.velocity = Vector3.ZERO
		_check(sheep.state == Animal.State.FLEE, "a sheep runs from someone who comes running")
	else:
		_check(false, "a sheep is spawned near the pen")
	# The dog follows when asked, and goes home when told to stay.
	var dog_record: Dictionary = manager.owned().filter(func(r): return String(r["species"]) == "dog")[0]
	var home := manager.home_area(dog_record)["center"] as Vector3
	player.global_position = Vector3(home.x + 3, VillageLayout.get_walk_height(home.x + 3, home.z) + 0.3, home.z)
	await _frames(45)
	var dog := manager.node_of(String(dog_record["id"]))
	_check(dog != null, "the dog appears by your home")
	if dog:
		_check(dog._verb() == "Follow", "you can ask your dog to follow")
		dog.interact(player)
		player.global_position += Vector3(12, 0, 0)
		player.global_position.y = VillageLayout.get_walk_height(player.global_position.x, player.global_position.z) + 0.3
		await get_tree().create_timer(4.0).timeout  # real seconds: it runs at 5 m/s
		var d := Vector2(dog.global_position.x - player.global_position.x, dog.global_position.z - player.global_position.z).length()
		_check(bool(dog_record["follow"]) and d < 6.0, "the dog follows you (%.1f m behind)" % d)
		# Boxed in behind a house, it still finds you (catches up after a moment).
		var house: Dictionary = VillageLayout.get_building("house_mara")
		var hp: Vector3 = house["position"]
		var back: Vector3 = hp + Basis(Vector3.UP, float(house["yaw"])) * Vector3(0, 0, -float(house["footprint"].y) * 0.5 - 0.8)
		var front: Vector3 = hp + Basis(Vector3.UP, float(house["yaw"])) * Vector3(0, 0, float(house["footprint"].y) * 0.5 + 3.0)
		dog.global_position = VillageLayout.ground_point(back.x, back.z)
		player.global_position = VillageLayout.ground_point(front.x, front.z) + Vector3(0, 0.3, 0)
		await get_tree().create_timer(4.0).timeout
		var d2 := Vector2(dog.global_position.x - player.global_position.x, dog.global_position.z - player.global_position.z).length()
		_check(d2 < 6.0, "boxed in behind a house, the dog still gets back to you (%.1f m)" % d2)
		# A follower stays spawned even far away.
		player.global_position += Vector3(0, 0, 150)
		await get_tree().create_timer(0.7).timeout
		_check(manager.node_of(String(dog_record["id"])) != null, "a following dog isn't removed when you go far")
		dog.interact(player)
		_check(not bool(dog_record["follow"]), "asked to stay, the dog heads home")


func _birds() -> void:
	var birds := BirdFlocks.instance
	_check(birds != null and birds.flocks.size() == BirdFlocks.FLOCKS, "there are %d flocks of birds" % BirdFlocks.FLOCKS)
	var player: PlayerController = GameManager.player
	player.global_position = Vector3(0, VillageLayout.get_walk_height(0, 20) + 0.3, 20)
	await _frames(120)
	var lowest := INF
	for flock in birds.flocks:
		for bird: Dictionary in flock["birds"]:
			var n: Node3D = bird["node"]
			lowest = minf(lowest, n.global_position.y - TerrainGenerator.get_height(n.global_position.x, n.global_position.z))
	_check(birds.visible and lowest > 3.0, "by day the birds fly high above the ground (lowest %.1f m)" % lowest)
	var anim: AnimationPlayer = birds.flocks[0]["birds"][0]["anim"]
	_check(anim.is_playing() and String(anim.current_animation).ends_with("Flying"), "birds beat their wings (%s)" % anim.current_animation)
	# A flock lands near the player, then takes off when they come close.
	var flock: Dictionary = birds.flocks[0]
	flock["timer"] = 0.0
	await _frames(5)
	_check(int(flock["mode"]) == BirdFlocks.Mode.LANDING, "a flock comes down to land")
	var spot: Vector3 = flock["spot"]
	for bird: Dictionary in flock["birds"]:
		(bird["node"] as Node3D).global_position = spot + Vector3(0, 1, 0)
	await _frames(30)
	_check(int(flock["mode"]) == BirdFlocks.Mode.LANDED, "the flock settles on the ground")
	player.global_position = Vector3(spot.x + 2, VillageLayout.get_walk_height(spot.x + 2, spot.z) + 0.3, spot.z)
	await _frames(5)
	_check(int(flock["mode"]) == BirdFlocks.Mode.TAKING_OFF, "walk up and the birds fly off")
	WorldClock.set_time(23.0)
	await _frames(3)
	_check(not birds.visible, "at night the birds are gone to roost")
	WorldClock.set_time(10.0)


func _weather() -> void:
	var weather := Weather.instance
	weather.set_weather(Weather.Kind.RAIN, 4.0, true)
	var rain: CPUParticles3D = weather.find_child("Rain", true, false)
	var ground := Materials.ground()
	_check(weather.is_raining() and rain != null and rain.emitting, "rain falls when it's raining")
	_check(float(ground.get_shader_parameter("wetness")) > 0.5, "the ground gets wet (%.2f)" % float(ground.get_shader_parameter("wetness")))
	_check(DayNightCycle.overcast > 0.5, "the sky clouds over (%.2f)" % DayNightCycle.overcast)
	var grass_wind := 0.0
	for m in Materials.foliage_materials.values():
		grass_wind = maxf(grass_wind, float((m as ShaderMaterial).get_shader_parameter("wind_strength")))
	_check(grass_wind > 0.012, "the wind blows harder in the rain (leaves %.3f)" % grass_wind)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(weather.to_dict()))
	weather.set_weather(Weather.Kind.CLEAR, 4.0, true)
	_check(not rain.emitting and float(ground.get_shader_parameter("wetness")) < 0.05, "clear weather: no rain, dry ground")
	weather.from_dict(saved)
	_check(weather.is_raining(), "the weather is saved and loaded")
	weather.set_weather(Weather.Kind.CLEAR, 48.0, true)
