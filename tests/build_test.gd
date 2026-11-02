extends Node
## Headless test of building and voices: every buildable, the Build menu's
## tabs, staged house construction, chicken coops, fruit trees, village
## beauty, moving and removing, the starter kit, and giving villagers
## different voices from Android's voice list.
## Run:  godot --headless --path . res://tests/build_test.tscn

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


func _structure(record: Dictionary) -> PlacedStructure:
	for s in get_tree().get_nodes_in_group("placed_structures"):
		if s.record == record:
			return s
	return null


func _finish(record: Dictionary) -> PlacedStructure:
	await _frames(3)
	var s := _structure(record)
	while not s.is_complete():
		s.add_work(1.0)
	await _frames(2)
	return s


func _vertices(node: Node) -> int:
	var total := 0
	if node is MeshInstance3D and (node as MeshInstance3D).mesh:
		var mesh: Mesh = (node as MeshInstance3D).mesh
		for i in mesh.get_surface_count():
			total += (mesh.surface_get_arrays(i)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	for child in node.get_children():
		total += _vertices(child)
	return total


func _run() -> void:
	print("== Build test ==")
	WorldClock.day = 3
	WorldClock.set_time(10.0)
	WorldClock.set_time_scale(0.0)
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_main)
	await _frames(40)

	# --- The catalog ------------------------------------------------------------------
	var listed := 0
	for tab in StructureCatalog.CATEGORIES:
		for type in StructureCatalog.CATEGORIES[tab]:
			listed += 1
	_check(StructureCatalog.ORDER.size() >= 13 and listed == StructureCatalog.ORDER.size(), "%d things to build, all in the Build menu's tabs" % listed)
	var broken := []
	for type in StructureCatalog.ORDER:
		var node := StructureCatalog.create_finished(type) if type != &"fruit_tree" else StructureCatalog.create_fruit_tree(1.0, true)
		if _vertices(node) < 20:
			broken.append(type)
		node.free()
	_check(broken.is_empty(), "every one has a 3D model %s" % str(broken))
	var stages: Array[int] = []
	for p: float in [0.05, 0.3, 0.6, 0.8, 0.99]:
		var site := StructureCatalog.create_construction(&"house", p)
		stages.append(_vertices(site))
		site.free()
	_check(stages[0] < stages[1] and stages[1] < stages[2] and stages[2] < stages[3] and stages[3] < stages[4],
		"a house rises in stages as you work: %s vertices" % str(stages))

	# --- Build menu ---------------------------------------------------------------------
	var panels: GameplayPanels = _main.find_child("GameplayPanels", true, false)
	panels._toggle_build_menu()
	await _frames(3)
	_check(panels._tab_buttons.size() == 3 and panels._build_list.get_child_count() == StructureCatalog.CATEGORIES["Homes"].size(), "the Build menu opens on Homes")
	panels._category = "Village"
	panels._refresh_build_list()
	await _frames(3)
	_check(panels._build_list.get_child_count() == StructureCatalog.CATEGORIES["Village"].size(), "the Village tab lists %d things" % StructureCatalog.CATEGORIES["Village"].size())
	panels._build_menu.visible = false

	# --- Starter kit ----------------------------------------------------------------------
	var gathered := int(GameState.collected[&"wood"])
	GameState.give_starter_kit()
	_check(GameState.count(&"wood") == 15 and GameState.count(&"stone") == 8 and int(GameState.collected[&"wood"]) == gathered,
		"a new village starts with 15 wood and 8 stone (not counted as gathered)")
	GameState.add(&"wood", 60)
	GameState.add(&"stone", 40)
	GameState.add(&"herbs", 10)

	# --- Chicken coop ---------------------------------------------------------------------
	var coop := await _finish(GameState.add_structure(&"chicken_coop", VillageLayout.ground_point(-26.0, 30.0), 0.0))
	var food := GameState.count(&"food")
	WorldClock.advance(24.0)
	await _frames(2)
	_check(GameState.count(&"food") == food + PlacedStructure.EGGS_FOOD, "the hens lay %d food every morning" % PlacedStructure.EGGS_FOOD)
	_check(coop.get_interaction_prompt().contains("every morning"), "the coop says so: %s" % coop.get_interaction_prompt())

	# --- Fruit tree -------------------------------------------------------------------------
	var tree := await _finish(GameState.add_structure(&"fruit_tree", VillageLayout.ground_point(-22.0, 33.0), 0.0))
	_check(tree.tree_growth() == 0.0 and not tree.has_fruit(), "a fruit tree starts as a sapling")
	var small := _vertices(tree._visual)
	WorldClock.advance(24.0)
	await _frames(2)
	_check(tree.tree_growth() == 0.5 and not tree.has_fruit(), "after a day it's half grown")
	WorldClock.advance(24.0)
	await _frames(2)
	_check(tree.has_fruit() and _vertices(tree._visual) > small, "after two days it's grown and full of fruit")
	food = GameState.count(&"food")
	tree.use()
	_check(GameState.count(&"food") == food + PlacedStructure.FRUIT_FOOD and not tree.has_fruit(), "picking fruit gives %d food" % PlacedStructure.FRUIT_FOOD)
	WorldClock.advance(24.0)
	await _frames(2)
	_check(tree.has_fruit(), "and it fruits again the next day")

	# --- Beauty ---------------------------------------------------------------------------
	var before := GameState.beauty()
	await _finish(GameState.add_structure(&"flower_bed", VillageLayout.ground_point(-24.0, 22.0), 0.0))
	await _finish(GameState.add_structure(&"statue", VillageLayout.ground_point(-19.0, 25.0), 0.0))
	_check(GameState.beauty() >= before + 6.0, "flowers and the founders' stone make the village lovelier (beauty %.1f)" % GameState.beauty())
	var mara = GameManager.get_villager(&"mara")
	SocialLife.instance._update_happiness(mara, mara.person)
	var with_beauty: float = mara.person.happiness
	var saved_structures := GameState.structures.duplicate()
	GameState.structures = []
	SocialLife.instance._update_happiness(mara, mara.person)
	var without: float = mara.person.happiness
	GameState.structures = saved_structures
	_check(with_beauty > without, "villagers are happier in a beautiful village (%.0f vs %.0f)" % [with_beauty, without])

	# --- Moving -----------------------------------------------------------------------------
	var player = GameManager.player
	var bench := await _finish(GameState.add_structure(&"bench", VillageLayout.ground_point(-28.0, 20.0), 0.0))
	BuildMode.instance.set_edit_mode("move")
	_check(bench.get_interaction_verb() == "Move", "in move mode, built things say Move")
	player.global_position = VillageLayout.ground_point(-30.0, 10.0) + Vector3(0, 0.4, 0)
	player.model.rotation.y = PI
	await _frames(3)
	var wood := GameState.count(&"wood")
	bench._on_interacted(player)
	await _frames(3)
	_check(BuildMode.instance.active and BuildMode.instance.moving == bench and not bench.visible, "tapping it picks it up")
	var old_position := bench.global_position
	_check(BuildMode.instance.confirm() == "", "and it can be put down somewhere else (%s)" % BuildMode.instance.reason)
	_check(bench.visible and bench.global_position.distance_to(old_position) > 2.0 and GameState.count(&"wood") == wood,
		"the bench moved, for free")
	_check(Vector3(bench.record["position"][0], 0, bench.record["position"][2]).distance_to(Vector3(bench.global_position.x, 0, bench.global_position.z)) < 0.01,
		"and its new place is saved")

	# --- Removing -----------------------------------------------------------------------------
	BuildMode.instance.set_edit_mode("remove")
	_check(bench.get_interaction_verb() == "Remove", "in remove mode, built things say Remove")
	wood = GameState.count(&"wood")
	var count := GameState.structures.size()
	bench._on_interacted(player)
	await _frames(3)
	_check(GameState.count(&"wood") == wood + 2 and GameState.structures.size() == count - 1 and not is_instance_valid(bench),
		"removing gives back half the cost")
	bench = null
	_check(BuildMode.instance.edit_mode == "", "and leaves remove mode")
	# A cottage with people in it.
	var cottage := await _finish(GameState.add_structure(&"cottage", VillageLayout.ground_point(-26.0, -10.0), PI))
	var newcomer := PopulationDirector.instance.settle_newcomer()
	var cottage_home := cottage.home_id()
	Population._move_in(newcomer, cottage_home)
	BuildMode.instance.remove(cottage)
	cottage = null
	await _frames(3)
	_check(newcomer.home != cottage_home and newcomer.home != "", "when a cottage comes down, its people move elsewhere (%s)" % newcomer.home)
	_check(not VillageLayout.get_locations().has(cottage_home), "and nobody walks home to it any more")

	# --- Voices ----------------------------------------------------------------------------
	Voices._tts_voices = [
		{"id": "en-us-x-iob-local", "name": "en-us-x-iob-local", "language": "en_US"},
		{"id": "en-us-x-iol-local", "name": "en-us-x-iol-local", "language": "en_US"},
		{"id": "en-us-x-iom-local", "name": "en-us-x-iom-local", "language": "en_US"},
		{"id": "en-us-x-tpf-local", "name": "en-us-x-tpf-local", "language": "en_US"},
		{"id": "en-gb-x-gbb-local", "name": "en-gb-x-gbb-local", "language": "en_GB"},
		{"id": "en-gb-x-gba-local", "name": "en-gb-x-gba-local", "language": "en_GB"},
		{"id": "en-us-x-iom-network", "name": "en-us-x-iom-network", "language": "en_US"},
		{"id": "fr-fr-x-frc-local", "name": "fr-fr-x-frc-local", "language": "fr_FR"},
	]
	_check(Voices.voices_summary() == "6 voices found (3 women's, 3 men's).", "Android's voices are recognised: %s" % Voices.voices_summary())
	var ids := {}
	var right_sex := true
	for villager in GameManager.villagers:
		var id := Voices.tts_voice_id(villager)
		ids[id] = true
		var voice := {}
		for v in Voices._tts_voices:
			if v["id"] == id:
				voice = v
		if Voices.voice_sex(voice) != Voices.voice_of(villager)["sex"]:
			right_sex = false
		_check(not id.contains("network"), "%s speaks with %s (%s)" % [villager.data.display_name, id, Voices.voice_of(villager)["sex"]])
	_check(right_sex, "women get women's voices and men get men's")
	_check(ids.size() == 5, "the five founders each have a different voice (%d)" % ids.size())
	var pitches := GameManager.villagers.map(func(v): return snappedf(Voices.voice_of(v)["pitch"], 0.01))
	var unique_pitches := {}
	for p in pitches:
		unique_pitches[p] = true
	_check(unique_pitches.size() == pitches.size(), "and everyone has their own pitch too: %s" % str(pitches))
	Voices._tts_voices = []

	print("== %s: %d failure(s) ==" % ["PASSED" if _failures == 0 else "FAILED", _failures])
	get_tree().quit(0 if _failures == 0 else 1)
