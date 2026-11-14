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
	# Too poor for a home: the menu opens where you can build something,
	# rows say what's missing, and tapping one explains it in the menu.
	GameState.inventory[&"wood"] = 5
	GameState.inventory[&"stone"] = 0
	panels._category = "Homes"
	panels._toggle_build_menu()
	await _frames(2)
	_check(panels._category != "Homes", "with 5 wood the Build menu opens on %s, where something is affordable" % panels._category)
	panels._category = "Homes"
	panels._refresh_build_list()
	await _frames(2)
	var house_row: Button = panels._build_list.get_child(0)
	_check(house_row.text.contains("need 15 more wood and 10 more stone"), "a house you can't afford says what's missing")
	panels._choose_structure(&"house")
	_check(panels._build_menu.visible and not BuildMode.instance.active and panels._menu_message.text.begins_with("Need 15 more wood"),
		"tapping it explains, inside the menu: %s" % panels._menu_message.text)
	panels._build_menu.visible = false
	GameState.inventory[&"wood"] = 0

	# --- Starter kit ----------------------------------------------------------------------
	var gathered := int(GameState.collected[&"wood"])
	GameState.give_starter_kit()
	_check(GameState.count(&"wood") == 20 and GameState.count(&"stone") == 10 and int(GameState.collected[&"wood"]) == gathered,
		"a new village starts with 20 wood and 10 stone, enough for a house (not counted as gathered)")
	GameState.add(&"wood", 60)
	GameState.add(&"stone", 40)
	GameState.add(&"herbs", 10)

	# --- Chicken coop ---------------------------------------------------------------------
	var coop := await _finish(GameState.add_structure(&"chicken_coop", VillageLayout.ground_point(-26.0, 30.0), 0.0))
	await _frames(3)
	_check(coop.hens().size() == PlacedStructure.HENS, "a finished coop has %d hens" % coop.hens().size())
	_check(coop.get_interaction_verb() == "Feed" and coop.get_interaction_prompt().contains("every morning"), "the coop offers: %s" % coop.get_interaction_prompt())
	GameState.add(&"herbs", 1)
	coop.use(GameManager.player)
	_check(coop.hens_fed_today(), "feeding the hens (1 herb)")
	WorldClock.advance(24.0)
	await _frames(2)
	_check(coop.eggs() == PlacedStructure.HENS and coop.get_interaction_verb() == "Collect", "fed hens lay %d eggs by morning" % coop.eggs())
	var food := GameState.count(&"food")
	coop.use(GameManager.player)
	_check(GameState.count(&"food") == food + PlacedStructure.HENS and coop.eggs() == 0, "collecting them gives %d food" % PlacedStructure.HENS)
	WorldClock.advance(24.0)
	await _frames(2)
	_check(coop.eggs() == 1, "unfed, they lay just 1 egg")

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

	# --- Finding room, clearing the land ----------------------------------------------------
	GameState.add(&"wood", 20)
	GameState.add(&"stone", 10)
	var blocked_at: Vector3 = ResourceSpawner.nodes[0].global_position
	_check(BuildMode.placement_reason(&"house", blocked_at, 0.0) != "", "a house can't go right on top of a tree")
	var free := BuildMode.nearest_free_spot(&"house", blocked_at, 0.0, blocked_at + Vector3(20, 0, 0))
	_check(free != Vector3.INF and BuildMode.placement_reason(&"house", free, 0.0) == "" and free.distance_to(blocked_at) <= BuildMode.SEARCH_RADIUS + 0.5,
		"so the preview moves to the nearest free spot (%.1f m away)" % (free.distance_to(blocked_at) if free != Vector3.INF else -1.0))
	var wild: Dictionary = {}
	for entry: Dictionary in NatureSpawner._clearable:
		if entry["kind"] == "tree" and entry.has("shape") and not entry.get("gone", false):
			wild = entry
			break
	var cleared := NatureSpawner.clear_area(wild["pos"], 0.5)
	await _frames(2)
	_check(cleared >= 1 and wild.get("gone", false) and (wild["shape"] as CollisionShape3D).disabled,
		"building somewhere clears the trees there, trunks and all (%d)" % cleared)

	# --- Chopping any tree, mining any rock ----------------------------------------------------
	var trees := 0
	var rocks := 0
	for entry: Dictionary in NatureSpawner._clearable:
		if NatureSpawner.is_workable(entry):
			if entry["kind"] == "rock":
				rocks += 1
			else:
				trees += 1
	_check(trees > 100 and rocks > 10, "every tree and rock around the village can be worked (%d trees, %d rocks)" % [trees, rocks])
	var wild_tree: Dictionary = {}
	for entry: Dictionary in NatureSpawner._clearable:
		var pos: Vector3 = entry["pos"]
		if NatureSpawner.is_workable(entry) and entry["kind"] != "rock" and pos.length() > 30.0 \
				and ResourceSpawner.nodes.all(func(n): return n.global_position.distance_to(pos) > 6.0):
			wild_tree = entry
			break
	var tree_at: Vector3 = wild_tree["pos"]
	player.global_position = tree_at + Vector3(1.4, 0.6, 0.0)
	player.face_towards(tree_at)
	await _frames(30)
	var detector: InteractionDetector = player.detector
	_check(detector.focused != null and detector.focused.handler is WildHarvest and detector.focused.get_verb() == "Chop",
		"walking up to an ordinary tree offers Chop (%s)" % (detector.focused.get_verb() if detector.focused else "nothing"))
	var wood_before := GameState.count(&"wood")
	for i in WildHarvest.HITS:
		detector.try_interact(player)
		await _frames(3)
	_check(GameState.count(&"wood") == wood_before + WildHarvest.HITS * WildHarvest.YIELD, "three chops give %d wood" % (WildHarvest.HITS * WildHarvest.YIELD))
	_check(wild_tree.get("felled", false) and not NatureSpawner.is_workable(wild_tree) and GameState.depleted.has("wild_%d" % int(wild_tree["id"])),
		"and the tree comes down")
	WorldClock.advance(24.0 * WildHarvest.REGROW_DAYS)
	await _frames(3)
	_check(NatureSpawner.is_workable(wild_tree), "it grows back after %d days" % WildHarvest.REGROW_DAYS)
	var wild_rock: Dictionary = {}
	for entry: Dictionary in NatureSpawner._clearable:
		if NatureSpawner.is_workable(entry) and entry["kind"] == "rock":
			wild_rock = entry
			break
	var rock_at: Vector3 = wild_rock["pos"]
	player.global_position = rock_at + Vector3(1.6, 0.6, 0.0)
	player.face_towards(rock_at)
	await _frames(30)
	var stone_before := GameState.count(&"stone")
	detector.try_interact(player)
	await _frames(3)
	_check(GameState.count(&"stone") == stone_before + WildHarvest.YIELD, "and any rock can be mined for stone (%s)" % (detector.focused.get_verb() if detector.focused else "nothing"))

	# --- The meeting circle and the camera ----------------------------------------------------
	player.global_position = Vector3(0.0, 1.0, 3.0)
	await _frames(30)
	_check(absf(player.global_position.y - VillageLayout.plaza_floor_height()) < 0.05,
		"the player stands on the meeting circle's floor, not sunk into it (%.2f vs %.2f)" % [player.global_position.y, VillageLayout.plaza_floor_height()])
	var rig: CameraRig = _main.camera_rig
	var low := INF
	for yaw in [0.0, 1.6, 3.2, 4.8]:
		rig.yaw = yaw
		rig.pitch = 1.0  # past the limit: looking up as far as possible
		rig._process(0.016)
		var cam := rig.camera.global_position
		low = minf(low, cam.y - VillageLayout.get_walk_height(cam.x, cam.z))
	_check(rig.pitch <= 0.35 and low >= 0.3, "looking up, the camera stays above the ground (%.2f m)" % low)
	rig.pitch = -0.3
	player.global_position = VillageLayout.ground_point(-30.0, 10.0) + Vector3(0, 0.4, 0)
	await _frames(10)

	# --- The player speaks their answers ------------------------------------------------------
	_check(DialoguePanel.is_spoken_answer("I'll keep watch with you tonight.") and not DialoguePanel.is_spoken_answer("Pay them a compliment.")
		and not DialoguePanel.is_spoken_answer("Be kind..."), "answers in words are spoken; actions aren't")
	var dialogue: DialoguePanel = _main.find_child("DialoguePanel", true, false)
	var talk_to = GameManager.get_villager(&"nia")
	talk_to.global_position = player.global_position + Vector3(1.5, 0, 0)
	await _frames(3)
	GameManager.start_conversation(talk_to)
	await _frames(3)
	var guard := 0
	while not dialogue._choice_box.visible and dialogue.visible and guard < 20:
		dialogue.advance()
		await _frames(2)
		guard += 1
	var spoken := -1
	for i in dialogue._conversation.choices.size():
		if DialoguePanel.is_spoken_answer(dialogue._conversation.choice_texts()[i]):
			spoken = i
			break
	if spoken >= 0:
		var said := dialogue._conversation.choice_texts()[spoken]
		dialogue._choose(spoken)
		await _frames(2)
		_check(dialogue._name_label.text == "You" and dialogue._text_label.text == said, "choosing an answer, you say it: \"%s\"" % said)
		dialogue.advance()
		dialogue.advance()
		await _frames(2)
		_check(dialogue._name_label.text != "You" or not dialogue.visible, "then they reply (%s)" % dialogue._name_label.text)
	else:
		_check(false, "the conversation offered an answer in words")
	if GameManager.is_in_conversation():
		GameManager.end_conversation()
	await _frames(3)

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
	# 3 women's and 3 men's voices: everyone differs while there are enough.
	var women := GameManager.villagers.filter(func(v): return Voices.voice_of(v)["sex"] == "female").size()
	var possible := mini(women, 3) + mini(GameManager.villagers.size() - women, 3)
	_check(ids.size() == possible, "the villagers each have a different voice (%d of %d)" % [ids.size(), possible])
	var pitches := GameManager.villagers.map(func(v): return snappedf(Voices.voice_of(v)["pitch"], 0.01))
	var unique_pitches := {}
	for p in pitches:
		unique_pitches[p] = true
	_check(unique_pitches.size() == pitches.size(), "and everyone has their own pitch too: %s" % str(pitches))
	Voices._tts_voices = []

	# Quit straight away, possibly while the newcomer's character is still
	# being built on a worker thread: that must not hang (it used to).
	print("== %s: %d failure(s) ==" % ["PASSED" if _failures == 0 else "FAILED", _failures])
	get_tree().quit(0 if _failures == 0 else 1)
