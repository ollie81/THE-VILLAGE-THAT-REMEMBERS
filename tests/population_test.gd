extends Node
## Headless test of population growth in the real main scene: generating
## newcomers, travellers arriving, welcoming and turning away, homes and the
## camp, cottages, friendships and partnerships, leaving, invitations, the
## family architecture (marriage, births, adoption, trees, inheritance,
## aging), statistics, performance features and saving.
## Run:  godot --headless --path . res://tests/population_test.tscn

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


func _wait_for_spawns(director: PopulationDirector) -> void:
	for i in 1200:
		if not director.is_spawning():
			return
		await get_tree().process_frame


func _run() -> void:
	print("== Population test ==")
	WorldClock.day = 1
	WorldClock.set_time(9.0)
	WorldClock.set_time_scale(0.0)
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_main)
	await _frames(30)
	var director: PopulationDirector = PopulationDirector.instance
	var rng := RandomNumberGenerator.new()
	rng.seed = 7

	# --- Founders ---------------------------------------------------------------------
	_check(Population.count() == 5 and GameManager.villagers.size() == 5, "the village starts with the five founders")
	var mara: Person = Population.get_person("mara")
	_check(mara != null and mara.founder and mara.first_name == "Mara" and mara.age() == 29 and mara.home == "home_mara",
		"Mara keeps her identity (name, age 29, her own house)")
	var mara_villager = GameManager.get_villager(&"mara")
	var authored := load("res://data/villagers/mara.tres") as VillagerData
	_check(mara_villager.person == mara and mara_villager.data.biography == authored.biography
		and AppearanceGenerator.distance(mara_villager.data.appearance, authored.appearance) < 0.001,
		"founders still use their hand-written character data")

	# --- Generation -----------------------------------------------------------------
	var generated: Array = []
	var looks: Array = Population.appearances()
	var names := Population.taken_first_names()
	for i in 45:
		var p := PersonGenerator.create(rng, "gen%d" % i, names, looks)
		generated.append(p)
		names[p.first_name.to_lower()] = true
		looks.append(AppearanceCodec.from_dict(p.appearance))
	var full_names := {}
	var styles := {}
	var skins := {}
	for p: Person in generated:
		full_names[p.full_name()] = true
		styles[String(p.appearance["hair_style"])] = true
		var skin: Dictionary = p.appearance["skin_color"]
		skins["%.2f" % float(skin["color"][0])] = true
	_check(full_names.size() == 45, "45 newcomers have 45 different names")
	var closest := INF
	for a in looks.size():
		for b in range(a + 1, looks.size()):
			closest = minf(closest, AppearanceGenerator.distance(looks[a], looks[b]))
	_check(closest > 1.2, "no two of 50 people look alike (closest difference %.2f)" % closest)
	_check(styles.size() >= 6 and skins.size() >= 8, "varied hair (%d styles) and skin tones (%d)" % [styles.size(), skins.size()])
	var skin_like := 0
	for look: CharacterAppearance in looks:
		if AppearanceGenerator._color_distance(look.shirt_color, look.skin_color) < 0.2:
			skin_like += 1
	_check(skin_like == 0, "nobody wears a shirt that looks like bare skin (%d)" % skin_like)
	var first: Person = generated[0]
	_check(first.age() >= 15 and first.profession != "" and first.traits.size() == 3 and not first.ambition.is_empty() \
		and first.skills.size() == Professions.SKILLS.size() and first.biography.contains(first.first_name),
		"a newcomer has an age, profession, traits, skills, ambition and story: %s" % first.biography)
	var copy := AppearanceCodec.from_dict(first.appearance)
	_check(AppearanceGenerator.distance(copy, AppearanceCodec.from_dict(AppearanceCodec.to_dict(copy))) < 0.0001,
		"appearance survives a save round trip exactly")
	var data := PersonGenerator.make_data(first)
	_check(data.schedule.size() >= 5 and data.first_meeting_lines.size() >= 2, "a newcomer gets a daily timetable and their own lines")

	# --- A traveller arrives ------------------------------------------------------------
	WorldClock.day = 2
	WorldClock.set_time(10.0)
	var traveller := director.bring_traveller()
	_check(traveller.status == Person.STATUS_VISITOR and Population.visitors().size() == 1, "a traveller arrives: %s" % traveller.full_name())
	_check(not GameManager.get_villager(StringName(traveller.id)), "their body is built in the background, not instantly")
	await _wait_for_spawns(director)
	var visitor = GameManager.get_villager(StringName(traveller.id))
	_check(visitor != null and visitor.is_visitor(), "the traveller appears in the village")
	_check(visitor.global_position.x > 50.0, "they walk in from the road past the bridge (x = %.0f)" % visitor.global_position.x)
	_check(visitor.model.skeleton.get_bone_count() == 19 and visitor.model.animation_player.has_animation(&"walk"),
		"they use the shared 19-bone skeleton and animations")
	var talk := DialogueService.build_conversation(visitor, GameManager.PLAYER_ID)
	_check(talk.lines[0].contains(traveller.first_name) and talk.choice_texts().size() == 3 and talk.choice_texts()[0].begins_with("Welcome"),
		"talking to them: they introduce themselves and ask to stay")
	talk.choose(1)
	_check(talk.has_lines() and talk.choices.size() == 2, "asking about them tells you more")

	# Welcome.
	var houses_before := Population.housing_summary()
	while talk.has_lines():
		talk.next_line()
	talk.choose(0)
	_check(traveller.status == Person.STATUS_RESIDENT and Population.count() == 6, "welcoming them makes them a villager (population 6)")
	_check(traveller.home != "" and traveller.home != Population.CAMP_ID and int(Population.housing_summary()["used"]) == int(houses_before["used"]) + 1,
		"they get a bed: %s" % VillageLayout.get_location_label(traveller.home))
	_check(not visitor.is_visitor() and visitor.data.schedule.size() >= 5, "they start living by their own timetable")
	_check(visitor.mind.get_affection(GameManager.PLAYER_ID) > 20.0, "they're grateful to the player")
	_check(visitor.mind.memory.has_detail("deed", GameManager.PLAYER_ID, DialogueService.pack_deed("welcomed me into the village", 25.0)),
		"they remember being welcomed")

	# Turn one away.
	var second := director.bring_traveller()
	await _wait_for_spawns(director)
	var second_villager = GameManager.get_villager(StringName(second.id))
	var sera = GameManager.get_villager(&"sera")
	var sera_before: float = sera.mind.get_affection(GameManager.PLAYER_ID)
	var refusal := DialogueService.build_conversation(second_villager, GameManager.PLAYER_ID)
	refusal.lines.clear()
	refusal.choose(2)
	_check(second.status == Person.STATUS_LEFT and int(Population.counters["rejected"]) == 1, "turning a traveller away is recorded")
	_check(second_villager.is_leaving(), "they walk away")
	_check(sera.mind.get_affection(GameManager.PLAYER_ID) < sera_before, "kind-hearted Sera thinks less of you for it")
	second_villager.global_position = PopulationDirector.ENTRY_POINT
	await _frames(70)
	_check(GameManager.get_villager(StringName(second.id)) == null, "they disappear down the road")

	# --- Housing and the camp -----------------------------------------------------------
	var arrivals: Array = []
	for i in 6:
		var p := director.bring_traveller()
		Population.make_resident(p)
		arrivals.append(p)
	await _wait_for_spawns(director)
	var housing := Population.housing_summary()
	_check(int(housing["capacity"]) == 10 and int(housing["used"]) == 10, "the five founders' houses hold ten (%d / %d)" % [int(housing["used"]), int(housing["capacity"])])
	_check(int(housing["camping"]) == 2, "with the houses full, newcomers sleep at the camp (%d)" % int(housing["camping"]))
	_check(GameManager.villagers.size() == 12, "everyone has a body, one at a time (%d)" % GameManager.villagers.size())
	WorldClock.day = 3
	_check(director.arrival_chance() < 0.5, "a full village attracts fewer travellers (%.2f)" % director.arrival_chance())
	# Build a cottage: campers move in.
	GameState.add(&"wood", 40)
	GameState.add(&"stone", 20)
	var player = GameManager.player
	player.global_position = VillageLayout.ground_point(-30, -8) + Vector3(0, 0.4, 0)
	player.model.rotation.y = PI
	await _frames(3)
	BuildMode.instance.start(&"cottage")
	await _frames(3)
	_check(BuildMode.instance.confirm() == "", "a cottage can be placed (%s)" % BuildMode.instance.reason)
	await _frames(3)
	var cottage: PlacedStructure = null
	for s in get_tree().get_nodes_in_group("placed_structures"):
		if s.get_type() == &"cottage":
			cottage = s
	while not cottage.is_complete():
		cottage.add_work(1.0)
	await _frames(3)
	housing = Population.housing_summary()
	_check(int(housing["capacity"]) == 14 and int(housing["camping"]) == 0, "a finished cottage adds four beds and the campers move in")
	_check(VillageLayout.get_locations().has(cottage.home_id()), "the cottage is a place villagers walk home to")

	# --- Population management --------------------------------------------------------
	var stats := Population.stats()
	_check(int(stats["total"]) == 12 and int(stats["adults"]) + int(stats["teens"]) + int(stats["elders"]) + int(stats["children"]) == 12,
		"statistics count everyone by age group")
	var jobs := 0
	for job in stats["occupations"]:
		jobs += int(stats["occupations"][job])
	_check(jobs + int(stats["apprentices"]) + int(stats["children"]) == 12 and int(stats["counters"]["arrivals"]) == 7,
		"occupations (with apprentices) and arrivals add up")
	var panel: PopulationPanel = _main.find_child("PopulationPanel", true, false)
	panel.toggle()
	await _frames(3)
	_check(panel.is_open(), "the population panel opens")
	panel.toggle()

	# --- Friendships and partnerships -------------------------------------------------
	var a_person: Person = arrivals[0]
	var b_person: Person = arrivals[1]
	a_person.birth_day = WorldClock.day - 30 * Person.year_days
	b_person.birth_day = WorldClock.day - 32 * Person.year_days
	var a = GameManager.get_villager(StringName(a_person.id))
	var b = GameManager.get_villager(StringName(b_person.id))
	var social: SocialLife = SocialLife.instance
	social.rng.seed = 3
	for hour in 60:
		social.spend_time(a, b, 1.0)
		if a_person.partner != "":
			break
	_check(a.mind.get_affection(b_person.id) >= SocialLife.FRIEND_AFFECTION, "spending time together makes friends")
	if a_person.partner == "":
		Population.form_partnership(a_person, b_person)
	_check(a_person.partner == b_person.id and b_person.partner == a_person.id, "two single adults can become partners")
	_check(a_person.home == b_person.home, "partners move in together (%s)" % VillageLayout.get_location_label(a_person.home))
	_check(Population.marry(a_person, b_person) and a_person.married, "partners can marry")
	_check(not Population.can_partner(a_person, arrivals[2]), "a married person isn't looking for a partner")

	# --- Leaving ---------------------------------------------------------------------------
	var unhappy: Person = arrivals[3]
	# Only adults decide to leave on their own (newcomers can be teenagers).
	unhappy.birth_day = WorldClock.day - 30 * Person.year_days
	var unhappy_villager = GameManager.get_villager(StringName(unhappy.id))
	unhappy_villager.mind.adjust_opinion(GameManager.PLAYER_ID, -60.0, -40.0)
	unhappy.unhappy_days = 5
	social.rng.seed = 1
	for attempt in 6:
		social._decide(unhappy_villager, unhappy)
		if unhappy.leaving:
			break
	_check(unhappy.leaving, "an unhappy villager decides to leave")
	var plea := DialogueService.build_conversation(unhappy_villager, GameManager.PLAYER_ID)
	_check(plea.choice_texts()[0].begins_with("Please stay"), "you can ask them to stay")
	WorldClock.set_time(6.5)
	director._on_hour_changed(7)
	_check(unhappy.status == Person.STATUS_LEFT and unhappy_villager.is_leaving() and int(Population.counters["departures"]) == 1,
		"they set off in the morning and the departure is counted")
	var stayer: Person = arrivals[4]
	var stayer_villager = GameManager.get_villager(StringName(stayer.id))
	stayer.leaving = true
	var please := DialogueService.build_conversation(stayer_villager, GameManager.PLAYER_ID)
	please.lines.clear()
	please.choose(0)
	_check(not stayer.leaving, "a villager who likes you can be talked into staying")

	# --- Invitations -----------------------------------------------------------------------
	var inviter: Person = arrivals[2]
	director.queue_invitation(inviter, "sibling")
	_check(director.arrival_chance() == 1.0, "a relative who was sent for is sure to come")
	var sibling := director.bring_traveller()
	var inviter_look := AppearanceCodec.from_dict(inviter.appearance)
	var sibling_look := AppearanceCodec.from_dict(sibling.appearance)
	_check(sibling.family_name == inviter.family_name and sibling.relatives.get(inviter.id) == "sibling",
		"%s's sibling %s shares the family name" % [inviter.first_name, sibling.full_name()])
	_check(AppearanceGenerator._color_distance(inviter_look.skin_color, sibling_look.skin_color) < 0.1, "and has a family resemblance")
	await _wait_for_spawns(director)
	var sibling_talk := DialogueService.build_conversation(GameManager.get_villager(StringName(sibling.id)), GameManager.PLAYER_ID)
	_check(sibling_talk.lines[1].contains(inviter.first_name), "they mention who invited them")
	sibling_talk.lines.clear()
	sibling_talk.choose(0)

	# --- Families (architecture) -----------------------------------------------------------
	var baby := Population.register_birth(a_person, b_person, rng)
	_check(baby.parents == [a_person.id, b_person.id] and a_person.children.has(baby.id) and baby.life_stage() == Person.STAGE_CHILD,
		"a birth links child and parents")
	_check(baby.family_name == a_person.family_name and baby.home == a_person.home, "the child takes a family name and lives with the parents")
	_check(Population.ancestors(baby).size() == 2 and Population.descendants(a_person).has(baby.id), "family trees go up and down")
	var orphan := PersonGenerator.create(rng, Population.new_id(), Population.taken_first_names(), [])
	orphan.birth_day = WorldClock.day - 6 * Person.year_days
	Population.add(orphan)
	orphan.status = Person.STATUS_RESIDENT
	Population.adopt([a_person, b_person], orphan)
	_check(Population.siblings(baby).has(orphan.id) and orphan.family_name == a_person.family_name, "adoption makes siblings")
	var tree := Population.family_tree(a_person)
	_check((tree["children"] as Array).size() == 2, "the family tree lists both children")
	_check(Population.BIRTHS_ENABLED, "births are on (children are real 3D characters)")
	Population.home_owners[a_person.home] = a_person.id
	Population.die(a_person, "test")
	_check(a_person.status == Person.STATUS_DEAD and Population.home_owners.get(b_person.home, "") == b_person.id and b_person.partner == "",
		"when someone dies, their partner inherits the home")
	_check(int(Population.counters["deaths"]) == 1 and int(Population.counters["births"]) == 1, "births and deaths are counted")
	var teen := Person.new()
	teen.birth_day = WorldClock.day - 17 * Person.year_days - (Person.year_days - 1)
	_check(teen.life_stage() == Person.STAGE_TEEN and teen.life_stage(WorldClock.day + 1) == Person.STAGE_ADULT, "people age and come of age")

	# --- Performance ------------------------------------------------------------------------
	var far_villager = GameManager.get_villager(StringName((arrivals[5] as Person).id))
	far_villager.global_position = player.global_position + Vector3(60, 0, 0)
	await _frames(25)
	var far_model: CharacterModel = far_villager.model
	_check(far_model.detail != CharacterModel.Detail.FULL and not far_model.head.visible and far_model._proxy_head.visible,
		"distant villagers swap to a simple head")
	far_villager.global_position = player.global_position + Vector3(2.0, 0, 0)
	await _frames(25)
	_check(far_model.detail == CharacterModel.Detail.FULL and far_model.head.visible, "and get their full face back up close")
	var shared: bool = GameManager.get_villager(StringName(traveller.id)).model.body.get_active_material(0) == mara_villager.model.body.get_active_material(0)
	_check(shared, "everyone shares the same character materials")
	_check(Population.MAX_POPULATION == 50, "the village is capped at 50 for phones")

	# --- Saving -----------------------------------------------------------------------------
	var saved: Dictionary = JSON.parse_string(JSON.stringify(Population.to_dict()))
	var count_before := Population.count()
	var names_before := Population.residents().map(func(p): return p.full_name())
	names_before.sort()
	Population.from_dict(saved)
	var names_after := Population.residents().map(func(p): return p.full_name())
	names_after.sort()
	_check(Population.count() == count_before and names_after == names_before,
		"the whole population survives save and load")
	_check(Population.get_person(b_person.id).married == false and Population.get_person(baby.id).parents.size() == 2,
		"families survive save and load")

	await _generations(director, rng)

	print("== %s: %d failure(s) ==" % ["PASSED" if _failures == 0 else "FAILED", _failures])
	get_tree().quit(0 if _failures == 0 else 1)


## Children and generations: a couple has a baby, the baby stays home,
## grows into a 3D child, learns a trade, comes of age; adoption, old age,
## mourning and the length of a year.
func _generations(director: PopulationDirector, rng: RandomNumberGenerator) -> void:
	print("-- Generations --")
	# Room for a family: another cottage.
	var record := GameState.add_structure(&"cottage", VillageLayout.ground_point(-22.0, 28.0), 0.0)
	await _frames(3)
	for structure in get_tree().get_nodes_in_group("placed_structures"):
		if structure.record == record:
			while not structure.is_complete():
				structure.add_work(1.0)
	await _frames(3)
	var mum := director.settle_newcomer()
	var dad := director.settle_newcomer()
	await _wait_for_spawns(director)
	mum.sex = "female"
	dad.sex = "male"
	mum.birth_day = WorldClock.day - 27 * Person.year_days
	dad.birth_day = WorldClock.day - 29 * Person.year_days
	mum.partner = ""
	dad.partner = ""
	_check(Population.form_partnership(mum, dad) and mum.home == dad.home, "a new couple sets up home together")
	_check(Population.can_conceive(mum, dad), "a young couple with room can have a baby")
	Population.start_expecting(mum, dad)
	_check(mum.expecting_day == WorldClock.day + Population.PREGNANCY_DAYS and Population.stats()["expecting"] == 1, "they're expecting")
	for day in Population.PREGNANCY_DAYS:
		WorldClock.day += 1
		Population.advance_day(rng)
	var baby := Population.get_person(mum.children[-1]) if not mum.children.is_empty() else null
	_check(baby != null and baby.parents.has(dad.id) and baby.generation == 2 and baby.is_baby(), "the baby is born: %s" % (baby.full_name() if baby else "none"))
	director.update_bodies()
	await _frames(5)
	_check(GameManager.get_villager(StringName(baby.id)) == null and Population.stats()["babies"] >= 1, "a baby stays at home, without a body")
	_check(not Population.can_conceive(mum, dad), "no second baby while the first is so small")
	# Grow up: age three.
	baby.birth_day = WorldClock.day - 3 * Person.year_days
	director.update_bodies()
	await _wait_for_spawns(director)
	var toddler = GameManager.get_villager(StringName(baby.id))
	_check(toddler != null, "at three they get their own 3D body")
	var height: float = toddler.data.appearance.standing_height()
	var adult_height: float = AppearanceCodec.from_dict(baby.appearance).standing_height()
	_check(height / adult_height > 0.5 and height / adult_height < 0.6,
		"a three-year-old is just over half their adult height (%.2f m of %.2f m)" % [height, adult_height])
	_check(toddler.model.skeleton.get_bone_count() == 19 and toddler.model.animation_player.has_animation(&"walk"), "children use the same skeleton and animations")
	var foot: Transform3D = toddler.model.skeleton.get_bone_global_pose(HumanoidRig.Bone.LEFT_FOOT)
	_check(foot.origin.y < 0.12, "a child's feet are on the ground (%.2f m)" % foot.origin.y)
	_check(toddler.data.role == "Child" and String(toddler.data.schedule[0]["label"]).length() > 0, "children have their own day: %s" % toddler.data.schedule[0]["label"])
	_check(not TaskSystem.request(toddler, &"wood")["accepted"], "children aren't given jobs")
	var talk := DialogueService.build_conversation(toddler, GameManager.PLAYER_ID)
	_check(talk.lines.size() >= 2 and talk.lines[1].contains("3"), "they talk like a child: %s" % talk.lines[1])
	var parent_talk := DialogueService.build_conversation(GameManager.get_villager(StringName(mum.id)), GameManager.PLAYER_ID)
	_check(Population.family_summary(mum).contains(baby.first_name), "the family card lists the child: %s" % Population.family_summary(mum))
	# Birthdays rebuild the body as they grow.
	var first_model: CharacterModel = toddler.model
	baby.birth_day -= 4 * Person.year_days
	director.update_bodies()
	await _wait_for_spawns(director)
	_check(toddler.model != first_model and toddler.data.appearance.standing_height() > height + 0.1,
		"each year they grow (now %d, %.2f m)" % [baby.age(), toddler.data.appearance.standing_height()])
	# Thirteen: an apprentice.
	baby.birth_day = WorldClock.day - 13 * Person.year_days
	Population._birthday(baby, 13, 12, rng)
	_check(baby.profession != "" and Population.stats()["apprentices"] >= 1, "at thirteen they start learning a trade (%s)" % baby.profession)
	director.update_bodies()
	await _wait_for_spawns(director)
	_check(toddler.data.role.begins_with("Apprentice"), "and spend their days learning it (%s)" % toddler.data.role)
	# Eighteen: grown up.
	baby.birth_day = WorldClock.day - 18 * Person.year_days
	Population._birthday(baby, 18, 17, rng)
	director.update_bodies()
	await _wait_for_spawns(director)
	_check(baby.life_stage() == Person.STAGE_ADULT and not toddler.data.role.begins_with("Apprentice") and toddler.data.schedule.size() >= 5,
		"at eighteen they're an adult with a job (%s)" % toddler.data.role)
	_check(absf(toddler.data.appearance.standing_height() - adult_height) < 0.01, "and look like the adult they grew into")
	# Adoption.
	var a := director.settle_newcomer()
	var b := director.settle_newcomer()
	await _wait_for_spawns(director)
	a.sex = "male"
	b.sex = "male"
	a.birth_day = WorldClock.day - 34 * Person.year_days
	b.birth_day = WorldClock.day - 36 * Person.year_days
	Population.form_partnership(a, b)
	# A cottage of their own, with room for a child.
	var second := GameState.add_structure(&"cottage", VillageLayout.ground_point(-22.0, 38.0), 0.0)
	await _frames(3)
	for structure in get_tree().get_nodes_in_group("placed_structures"):
		if structure.record == second:
			while not structure.is_complete():
				structure.add_work(1.0)
	await _frames(3)
	var family_home := Population.cottage_home_id(second)
	Population._move_in(a, family_home)
	Population._move_in(b, family_home)
	_check(not Population.can_conceive(a, b) and Population.can_adopt(a, b), "a couple who can't have a baby together can adopt")
	var adopted := director.bring_child_for_adoption(a, b)
	_check(adopted.parents.size() == 2 and adopted.home == a.home and adopted.generation == 2 and adopted.age() >= 4, "%s is adopted" % adopted.first_name)
	await _wait_for_spawns(director)
	_check(GameManager.get_villager(StringName(adopted.id)) != null, "and walks in to their new home")
	# Old age and mourning.
	var elder := director.settle_newcomer()
	await _wait_for_spawns(director)
	var elder_child := director.settle_newcomer()
	await _wait_for_spawns(director)
	elder.children.append(elder_child.id)
	elder_child.parents.append(elder.id)
	elder.birth_day = WorldClock.day - 80 * Person.year_days
	Population.die(elder)
	var grieving := DialogueService.build_conversation(GameManager.get_villager(StringName(elder_child.id)), GameManager.PLAYER_ID)
	_check(grieving.lines[0].contains(elder.first_name), "family mourn: %s" % grieving.lines[0])
	_check(Population.remembered().has(elder), "the village remembers those who died")
	# Growing older changes how founders look.
	var founder: Person = Population.get_person("mara")
	var old_look := founder.current_look()
	founder.birth_day -= 25 * Person.year_days
	var older := founder.current_look()
	_check(older.wrinkles > old_look.wrinkles and older.hair_color.get_luminance() > old_look.hair_color.get_luminance(),
		"people grey and wrinkle as they age (Mara at %d)" % founder.age())
	founder.birth_day += 25 * Person.year_days
	# The length of a year.
	var age_before := mum.age()
	Population.set_year_days(4)
	_check(mum.age() == age_before and Person.year_days == 4, "changing how fast years pass keeps everyone's age")
	Population.set_year_days(Population.DEFAULT_YEAR_DAYS)
	var stats := Population.stats()
	_check(int(stats["generations"]) >= 2 and int(stats["counters"]["births"]) >= 2, "statistics count generations and births")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(Population.to_dict()))
	Population.from_dict(saved)
	var reloaded := Population.get_person(baby.id)
	_check(reloaded.generation == 2 and reloaded.look_age == 18 and reloaded.parents.size() == 2, "generations survive save and load")
