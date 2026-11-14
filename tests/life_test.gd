extends Node
## Headless test of village life around the player: actions (wave, bow,
## cheer, dance), sitting on logs, benches and the ground, lying down and
## sleeping outside, villagers reacting and greeting, good and bad deeds,
## varied conversation, and voices.
## Run:  godot --headless --path . res://tests/life_test.tscn

var _failures: int = 0
var _main = null


func _ready() -> void:
	SaveService.enabled = false
	PopulationDirector.auto_arrivals = false
	Guide.rewards = false  # this test counts resources exactly
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
		await get_tree().physics_frame


func _talk_to(villager) -> Conversation:
	var conversation := DialogueService.build_conversation(villager, GameManager.PLAYER_ID)
	villager.mind.record_interaction(GameManager.PLAYER_ID, "conversation", WorldClock.day, WorldClock.time_of_day)
	return conversation


func _run() -> void:
	print("== Life test ==")
	WorldClock.day = 2
	WorldClock.set_time(10.0)
	WorldClock.set_time_scale(0.0)
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_main)
	await _frames(40)
	var player: PlayerController = GameManager.player
	var actions: ActionsMenu = _main.find_child("ActionsMenu", true, false)
	var mara = GameManager.get_villager(&"mara")
	var sera = GameManager.get_villager(&"sera")
	for v in GameManager.villagers:
		v.mind.record_interaction(GameManager.PLAYER_ID, "conversation", 1, 9.0)

	# --- Actions ---------------------------------------------------------------------
	_check(actions != null and actions._buttons.size() == 7 and actions._buttons[6].text == "Wardrobe", "an Actions menu with six actions and the Wardrobe")
	player.global_position = mara.global_position + Vector3(2.5, 0.4, 0)
	await _frames(10)
	var before: float = mara.mind.get_affection(GameManager.PLAYER_ID)
	actions.do(&"wave")
	await _frames(5)
	_check(player.model.get_animation() == &"wave", "the player waves")
	_check(mara.is_reacting() and mara.model.get_animation() == &"wave", "Mara waves back")
	_check(mara._bubble != null and mara._bubble.visible and mara._bubble.text != "", "and says something: %s" % (mara._bubble.text if mara._bubble else ""))
	_check(mara.mind.get_affection(GameManager.PLAYER_ID) > before, "a friendly wave warms her a little")
	var after_wave: float = mara.mind.get_affection(GameManager.PLAYER_ID)
	await _frames(160)
	actions.do(&"wave")
	_check(is_equal_approx(mara.mind.get_affection(GameManager.PLAYER_ID), after_wave), "but waving all day doesn't keep earning goodwill")
	await _frames(160)
	actions.do(&"dance")
	await _frames(5)
	_check(player.model.get_animation() == &"dance", "the player dances")
	var dancing := 0
	for v in GameManager.villagers:
		if v.is_reacting():
			dancing += 1
	_check(dancing >= 1, "nearby villagers react to the dancing (%d)" % dancing)
	await _frames(400)
	actions.do(&"bow")
	await _frames(5)
	_check(player.model.get_animation() == &"bow", "the player bows")
	await _frames(150)
	actions.do(&"cheer")
	await _frames(5)
	_check(player.model.get_animation() == &"cheer", "the player cheers")
	await _frames(160)

	# --- Sitting -------------------------------------------------------------------
	var objects: WorldObjects = _main.find_child("WorldObjects", true, false)
	var log_object: Node3D = objects.get_node("Log0")
	player.global_position = log_object.global_position + Vector3(0.8, 0.4, 0.8)
	await _frames(10)
	_check(player.detector.focused != null and player.detector.focused.get_verb() == "Sit", "the logs round the fire offer a seat")
	player.detector.try_interact(player)
	await _frames(40)
	_check(player.is_resting() and player.model.get_animation() == &"sit", "the player sits on the log")
	var seat_height := player.model.global_position.y - VillageLayout.get_walk_height(player.global_position.x, player.global_position.z)
	_check(seat_height > 0.05 and seat_height < 0.35, "raised onto the seat (%.2f m)" % seat_height)
	var hips_y := player.model.skeleton.global_transform * player.model.skeleton.get_bone_global_pose(HumanoidRig.Bone.HIPS).origin
	var ground := VillageLayout.get_walk_height(player.global_position.x, player.global_position.z)
	var log_top := VillageLayout.plaza_floor_height() + VillageLayout.PLAZA_SEAT_HEIGHT
	_check(absf(hips_y.y - log_top) < 0.06, "hips rest on the log top (hips %.2f m, log top %.2f m)" % [hips_y.y, log_top])
	var sit_pos := player.global_position
	Input.action_press("move_forward")
	await _frames(20)
	Input.action_release("move_forward")
	await _frames(5)
	_check(not player.is_resting() and player.model.position.y == 0.0 and player.global_position.distance_to(sit_pos) > 0.3,
		"moving stands up and steps off")
	actions.do(&"sit")
	await _frames(5)
	_check(player.model.get_animation() == &"sit_ground", "sitting anywhere else sits on the grass")
	player.stand_up()

	# Villagers sit on the logs in the evening.
	var seated_once := false
	var navigation: VillageNavigation = _main.navigation
	for v in GameManager.villagers:
		v._location_id = ""
	WorldClock.set_time(19.5)
	var nia = GameManager.get_villager(&"nia")
	nia._travel_to("plaza_seats")
	nia.global_position = VillageLayout.ground_point(navigation.get_spot("plaza_seats", nia._spot_index).x, navigation.get_spot("plaza_seats", nia._spot_index).z)
	nia._route = PackedVector3Array()
	var chat := VillagerActivity.new()
	chat.kind = &"socialize"
	chat.location_id = "plaza"
	nia.current_activity = chat
	nia._decision_timer = 1000.0
	nia._begin_performing()
	await _frames(40)
	seated_once = nia.model.get_animation() == &"sit" and nia.model.position.y > 0.05
	nia.react(&"wave", 1.0, player.global_position, "Hello!")
	await _frames(5)
	_check(nia.model.get_animation() == &"sit", "a seated villager stays seated when greeting you")
	_check(seated_once, "villagers sit on the logs when chatting by the fire")

	# --- Sleeping outside ---------------------------------------------------------------
	WorldClock.set_time(22.0)
	var day := WorldClock.day
	player.global_position = VillageLayout.ground_point(10, 10) + Vector3(0, 0.4, 0)
	await _frames(5)
	actions.do(&"sleep")
	_check(player.model.get_animation() == &"sleep", "the player lies down")
	await _frames(int(PlayerController.FALL_ASLEEP_TIME * 60.0) + 30)
	_check(WorldClock.day == day + 1 and WorldClock.time_of_day < 7.0, "and at night sleeps until morning")
	_check(GameState.get_flag(&"slept_outside"), "sleeping under the stars is noticed")
	player.stand_up()
	# The next villager you pass mentions it.
	var social: PlayerSocial = PlayerSocial.instance
	social._last_greeting_msec = -100000
	for v in GameManager.villagers:
		v.last_spoke_msec = -1000000
	var greeter = GameManager.get_villager(&"elias")
	greeter.visible = true
	greeter.state = Villager.State.IDLE
	for v in GameManager.villagers:
		if v._bubble:
			v._bubble.visible = false
		v._reaction_time = 0.0
	player.global_position = greeter.global_position + Vector3(1.5, 0.4, 0)
	# Greetings are checked twice a second; give a slow machine time.
	for i in 600:
		await _frames(1)
		if not GameState.get_flag(&"slept_outside"):
			break
	_check(greeter._bubble != null and greeter._bubble.visible, "villagers greet you as you pass: \"%s\"" % (greeter._bubble.text if greeter._bubble else ""))
	_check(not GameState.get_flag(&"slept_outside"), "someone mentions you slept outside")

	# --- Good deeds -------------------------------------------------------------------
	WorldClock.set_time(11.0)
	GameState.add(&"herbs", 3)
	var talk := _talk_to(mara)
	talk.lines.clear()
	talk.choices = DialogueService.closing_menu()
	_check(talk.choice_texts().size() == 5 and talk.choice_texts().has("Be kind...") and talk.choice_texts().has("Be unkind..."),
		"conversations offer kind and unkind things to do")
	talk.choose(2)
	_check(talk.choice_texts().size() >= 3 and talk.choice_texts()[0].begins_with("Give"), "being kind: %s" % ", ".join(talk.choice_texts()))
	var warmth: float = mara.mind.get_affection(GameManager.PLAYER_ID)
	talk.choose(0)
	_check(GameState.count(&"herbs") == 2 and mara.mind.get_affection(GameManager.PLAYER_ID) > warmth, "giving a gift: %s" % talk.lines[0])
	_check(mara.mind.memory.find("deed", GameManager.PLAYER_ID).any(func(e): return String(e["detail"]).begins_with("gave me")), "she remembers the gift")
	talk.lines.clear()
	talk.choices = Deeds.kind_menu(mara)
	var joke_index := 1 if talk.choice_texts()[0].begins_with("Give") else 0
	talk.choose(joke_index + 1)
	_check(talk.has_lines() and not talk.lines[0].is_empty(), "jokes land (or don't): %s" % talk.lines[0])

	# --- Bad deeds ---------------------------------------------------------------------
	var witness = GameManager.get_villager(&"tomas")
	witness.visible = true
	witness.state = Villager.State.IDLE
	witness.global_position = sera.global_position + Vector3(2.0, 0, 0)
	var witness_before: float = witness.mind.get_affection(GameManager.PLAYER_ID)
	var sera_before: float = sera.mind.get_affection(GameManager.PLAYER_ID)
	var rude := _talk_to(sera)
	rude.lines.clear()
	rude.choices = Deeds.unkind_menu(sera)
	_check(rude.choice_texts().size() == 4, "being unkind: %s" % ", ".join(rude.choice_texts()))
	rude.choose(1)
	_check(sera.mind.get_affection(GameManager.PLAYER_ID) < sera_before - 10.0, "insulting Sera hurts her feelings: %s" % rude.lines[0])
	_check(sera.mind.memory.find("deed", GameManager.PLAYER_ID).any(func(e): return String(e["detail"]).begins_with("insulted me")), "she remembers it")
	_check(witness.mind.get_affection(GameManager.PLAYER_ID) < witness_before, "Tomas saw it and thinks less of you")
	var speaker = null
	for v in GameManager.villagers:
		if v.has_meta("pending_line"):
			speaker = v
	_check(speaker != null, "a witness will say something about it")
	await _frames(5)
	_check(speaker != null and speaker._bubble != null and speaker._bubble.visible,
		"%s: \"%s\"" % [speaker.data.display_name if speaker else "?", speaker._bubble.text if speaker and speaker._bubble else ""])
	for i in 3:
		var again := _talk_to(sera)
		again.lines.clear()
		again.choices = Deeds.unkind_menu(sera)
		again.choose(1)
	_check(sera.mind.is_hostile(GameManager.PLAYER_ID), "keep insulting her and she won't talk to you")
	var cold := DialogueService.build_conversation(sera, GameManager.PLAYER_ID)
	_check(cold.topic_id == "apology", "until you apologise")
	var mark := GameState.count(&"food") + GameState.count(&"wood") + GameState.count(&"stone") + GameState.count(&"herbs")
	var thefts := 0
	var caught := 0
	for i in 12:
		var target = GameManager.get_villager(&"elias")
		var before_trust: float = target.mind.get_trust(GameManager.PLAYER_ID)
		var steal := _talk_to(target)
		steal.lines.clear()
		steal.choices = Deeds.unkind_menu(target)
		steal.choose(2)
		thefts += 1
		if target.mind.get_trust(GameManager.PLAYER_ID) < before_trust - 20.0:
			caught += 1
	var after := GameState.count(&"food") + GameState.count(&"wood") + GameState.count(&"stone") + GameState.count(&"herbs")
	_check(caught > 0 and caught < thefts and after > mark, "stealing: caught %d of %d times, loot otherwise" % [caught, thefts])

	# --- Conversation variety -------------------------------------------------------
	Population.log_event("marriage", "test", ["p_test_a", "p_test_b"])
	var nia_lines := {}
	var repeats := 0
	var previous := ""
	nia.mind.adjust_opinion(GameManager.PLAYER_ID, 30.0 - nia.mind.get_affection(GameManager.PLAYER_ID), 0.0)
	for i in 8:
		WorldClock.set_time(9.0 + i)
		var c := _talk_to(nia)
		var heard: Array[String] = []
		# Play it through like a player: answer the topic, then ask for news.
		for step in 6:
			while c.has_lines():
				heard.append(c.next_line())
			if c.choices.is_empty():
				break
			var texts := c.choice_texts()
			var news := Array(texts).find("What's new?")
			if news >= 0 and step > 0:
				c.choose(news)
				while c.has_lines():
					heard.append(c.next_line())
				break
			c.choose(news if news >= 0 else 0)
		var once := {}
		for line in heard:
			if once.has(line):
				repeats += 1
			once[line] = true
		var text := " / ".join(heard)
		if text == previous:
			repeats += 1
		previous = text
		for line in heard:
			nia_lines[line] = true
	_check(nia_lines.size() >= 14 and repeats == 0, "eight chats with Nia in one day: %d different lines, nothing said twice in a conversation" % nia_lines.size())
	var baby := Population.get_person(Population.get_person("mara").id)
	var news_villager = GameManager.get_villager(&"elias")
	Population.log_event("birth", "A baby", ["mara"])
	var found_news := false
	for i in 6:
		var n := _talk_to(news_villager)
		n.lines.clear()
		n.choices = DialogueService.closing_menu()
		n.choose(0)
		for line in n.lines:
			if line.contains("baby"):
				found_news = true
	_check(found_news, "villagers pass on village news")

	# --- Voices -----------------------------------------------------------------------
	var voice_mara := Voices.voice_of(mara)
	var voice_elias := Voices.voice_of(GameManager.get_villager(&"elias"))
	_check(float(voice_mara["pitch"]) > float(voice_elias["pitch"]), "everyone has their own voice (Mara %.2f, Elias %.2f)" % [voice_mara["pitch"], voice_elias["pitch"]])
	var short := Voices.babble(mara, "Hi!")
	var long := Voices.babble(mara, "I've been thinking about the river all morning, and the bridge too.")
	_check(short.get_length() > 0.05 and long.get_length() > short.get_length() * 2.0,
		"babble voices follow the length of the line (%.2f s / %.2f s)" % [short.get_length(), long.get_length()])
	_check(not Voices.has_speech() and Voices.mode != Voices.Mode.SPOKEN, "without text-to-speech (headless) voices fall back to babble")
	_check(bool(ProjectSettings.get_setting("audio/general/text_to_speech", false)), "text-to-speech is enabled for devices that have it")
	_check(Voices.clean_text("[happy]Hello... there") == "Hello,  there", "expression tags aren't read out")

	await _gifts()

	print("== %s: %d failure(s) ==" % ["PASSED" if _failures == 0 else "FAILED", _failures])
	get_tree().quit(0 if _failures == 0 else 1)


## Rewarded ads: optional gifts for the village (simulated ad in tests).
func _gifts() -> void:
	print("-- Gifts (rewarded ads) --")
	AdRewards.reset_for_tests()
	var panel: GiftsPanel = _main.find_child("GiftsPanel", true, false)
	_check(AdRewards.provider == AdRewards.Provider.SIMULATED, "on desktop debug builds a simulated ad stands in for AdMob")
	_check(panel != null and panel._button.visible, "a Gifts button is on screen")
	panel.toggle()
	await _frames(3)
	_check(panel.is_open() and panel._list.get_child_count() == AdRewards.REWARDS.size(), "the panel lists %d gifts" % AdRewards.REWARDS.size())
	var wood := GameState.count(&"wood")
	var granted: Array = []
	AdRewards.reward_granted.connect(func(r): granted.append(r))
	AdRewards.show_for(&"caravan")
	_check(get_tree().paused, "the game pauses while the ad plays")
	await get_tree().create_timer(AdRewards.SIMULATED_AD_SECONDS + 0.5, true, false, true).timeout
	await _frames(3)
	_check(not get_tree().paused and granted == [&"caravan"], "after the ad the game resumes and the gift is given")
	_check(GameState.count(&"wood") == wood + 8, "the caravan brought 8 wood")
	_check(not AdRewards.is_available() and AdRewards.cooldown_left() > 0.0, "there's a short wait before the next ad: %s" % AdRewards.unavailable_reason())
	AdRewards._last_shown_msec = -10000000
	_check(VillageGifts.blocked_reason(&"harvest") != "", "a blessed harvest needs planted crops first")
	var happy_before := 0.0
	for p: Person in Population.residents():
		p.happiness = 40.0
	AdRewards.show_for(&"feast")
	await get_tree().create_timer(AdRewards.SIMULATED_AD_SECONDS + 0.5, true, false, true).timeout
	await _frames(3)
	_check(Population.residents().all(func(p): return p.happiness >= 55.0), "a village feast makes everyone happier")
	AdRewards.watched_today = AdRewards.MAX_PER_DAY
	AdRewards._last_shown_msec = -10000000
	_check(AdRewards.remaining_today() == 0 and AdRewards.unavailable_reason().contains("tomorrow"), "at most %d gifts a day" % AdRewards.MAX_PER_DAY)
	var before := GameState.count(&"wood")
	AdRewards.show_for(&"caravan")
	await _frames(5)
	_check(GameState.count(&"wood") == before and not get_tree().paused, "no ad and no gift once the daily limit is reached")
	panel.toggle()
