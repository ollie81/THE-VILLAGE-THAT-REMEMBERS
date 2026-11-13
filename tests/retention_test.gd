extends Node
## Headless test of the reasons to come back: the daily welcome gift (save
## and load, coming back after several days, missed days, repeated claims,
## clock tricks, an edited save, starting the village over), weekly
## festivals, stories that grow from what happened between villagers and
## the player, the rewarded-ad rules, and how cheap all of it is to run.
## Run:  godot --headless --path . res://tests/retention_test.tscn

const DAY := 86400.0
## 2026-11-13 10:00 UTC.
const T0 := 1763028000.0

var _failures: int = 0
var _main = null


func _ready() -> void:
	SaveService.enabled = false
	PopulationDirector.auto_arrivals = false
	DailyGift.persist = false
	Guide.rewards = false
	AdRewards.reset_for_tests()
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


func _snapshot() -> Dictionary:
	var out := {}
	for r in GameState.RESOURCES:
		out[r] = GameState.count(r)
	return out


func _gained(before: Dictionary) -> Dictionary:
	var out := {}
	for r in GameState.RESOURCES:
		var d := GameState.count(r) - int(before[r])
		if d != 0:
			out[r] = d
	return out


func _run() -> void:
	print("== Retention test ==")
	WorldClock.day = 2
	WorldClock.set_time(10.0)
	WorldClock.set_time_scale(0.0)
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_main)
	await _frames(40)
	await _daily_gift()
	await _festivals()
	await _stories()
	await _ads()
	await _performance()
	print("== %s: %d failure(s) ==" % ["PASSED" if _failures == 0 else "FAILED", _failures])
	get_tree().quit(0 if _failures == 0 else 1)


# --- Daily welcome gift -------------------------------------------------------------

func _daily_gift() -> void:
	var gift := DailyGift.instance
	_check(gift != null, "the daily gift is in the game")
	gift.claims = 0
	gift.last_claim_day = -1
	gift.high_unix = 0.0
	var before := _snapshot()
	var first := gift.try_claim(T0)
	_check(not first.is_empty() and _gained(before) == {&"food": 3}, "the first visit of the day brings a gift: %s" % first.get("text", ""))
	before = _snapshot()
	var again := 0
	for i in 5:
		if not gift.try_claim(T0 + 600.0 * (i + 1)).is_empty():
			again += 1
	_check(again == 0 and _gained(before).is_empty() and gift.last_reason == "already claimed today", "coming back the same day gives nothing more (5 tries)")
	_check(gift.try_claim(T0 - 2.0 * DAY).is_empty() and gift.last_reason == "clock set back", "setting the clock back gives nothing")
	before = _snapshot()
	var next := gift.try_claim(T0 + DAY)
	_check(int(next.get("visit", 0)) == 2 and _gained(before) == {&"wood": 5}, "the next day brings the next gift (firewood)")
	# Away for four days: nothing lost, the gifts carry on in order.
	before = _snapshot()
	var after_break := gift.try_claim(T0 + 5.0 * DAY)
	_check(int(after_break.get("visit", 0)) == 3 and _gained(before) == {&"herbs": 3}, "after missing days nothing is lost: visit 3 brings visit 3's gift")
	# Clock pushed ahead to grab gifts, then put back: no gifts until real time catches up.
	gift.try_claim(T0 + 9.0 * DAY)
	_check(gift.try_claim(T0 + 6.0 * DAY).is_empty() and gift.try_claim(T0 + 8.5 * DAY).is_empty(),
		"after pushing the clock ahead and back, nothing more until that day really comes")
	_check(not gift.try_claim(T0 + 10.0 * DAY).is_empty(), "and then gifts carry on")
	# Seven visits make a week: a bigger basket.
	while gift.claims < 6:
		gift.try_claim(T0 + float(20 + gift.claims) * DAY)
	before = _snapshot()
	var seventh := gift.try_claim(T0 + 40.0 * DAY)
	_check(int(seventh.get("visit", 0)) == 7 and _gained(before) == {&"wood": 8, &"stone": 5, &"food": 4}, "every seventh visit, the whole village chips in")

	# Save and load.
	var saved := gift.to_dict()
	var loaded := DailyGift.new()
	loaded.from_dict(JSON.parse_string(JSON.stringify(saved)))
	_check(loaded.claims == 7 and loaded.last_claim_day == gift.last_claim_day and loaded.last_reason == "", "the record survives saving and loading (signature checks out)")
	_check(loaded.check(T0 + 40.0 * DAY + 3600.0).is_empty(), "after loading, the same day still gives nothing")
	_check(not loaded.check(T0 + 41.0 * DAY).is_empty(), "and the next day does")
	# Hand-edited save: no free gifts.
	var edited: Dictionary = gift.to_dict()
	edited["last_day"] = 0
	var cheat := DailyGift.new()
	cheat.from_dict(edited)
	_check(cheat.last_reason == "save edited" and cheat.check(Time.get_unix_time_from_system()).is_empty() and cheat.claims == 7,
		"an edited save gives nothing today, and keeps the visit count")
	# Starting the village over keeps today's claim (from the copy outside the save).
	var fresh := DailyGift.new()
	fresh._merge({"last_day": gift.last_claim_day, "last_unix": gift.last_claim_unix, "high_unix": gift.high_unix})
	_check(fresh.check(T0 + 40.0 * DAY + 7200.0).is_empty(), "\"Forget everything\" doesn't give a second gift the same day")
	loaded.free()
	cheat.free()
	fresh.free()
	# Days are UTC days: the same moment is the same day whatever the time zone.
	_check(DailyGift.day_number(T0) == DailyGift.day_number(T0 + 3600.0) and DailyGift.day_number(T0) + 1 == DailyGift.day_number(T0 + DAY),
		"days are counted in UTC (changing the time zone can't make a new day)")


# --- Festivals ----------------------------------------------------------------------

func _festivals() -> void:
	var festival := Festival.instance
	_check(festival != null, "festivals are in the game")
	var first_week_free := true
	for d in range(1, 12):
		if not Festival.festival_on(d).is_empty():
			first_week_free = false
	_check(first_week_free, "the first week and a half is for settling in")
	var order := [String(Festival.festival_on(12)["id"]), String(Festival.festival_on(19)["id"]), String(Festival.festival_on(26)["id"]),
		String(Festival.festival_on(33)["id"]), String(Festival.festival_on(40)["id"])]
	_check(order == ["harvest", "lanterns", "builders", "stories", "harvest"], "a different festival each week, in turn: %s" % str(order))
	_check(not Festival.festival_on(13).is_empty() and Festival.festival_on(14).is_empty(), "each lasts two village days")
	_check(String(Festival.festival_tomorrow(11).get("id", "")) == "harvest", "and is announced the day before")

	var panel: FestivalPanel = _main.find_child("FestivalPanel", true, false)
	WorldClock.day = 11
	WorldClock.set_time(9.0)
	festival.refresh()
	await _frames(2)
	_check(festival.announced_week == 1 and panel.visible and panel._title.text.begins_with("Tomorrow"), "the day before: \"%s\"" % panel._title.text)

	# Harvest Festival.
	WorldClock.day = 12
	WorldClock.set_time(9.0)
	festival.refresh()
	await _frames(2)
	_check(festival.is_active() and festival._decorations != null, "the Harvest Festival begins and the meeting circle is decorated")
	_check(panel.visible and panel._goals.text.contains("Bring in 12 food"), "its goals are on screen")
	var before := _snapshot()
	GameState.add(&"food", 12)
	_check(festival.done.has("food") and _gained(before) == {&"food": 12, &"herbs": 3, &"wood": 5}, "bringing in 12 food completes a goal and pays its reward")
	var mara = GameManager.get_villager(&"mara")
	var tomas = GameManager.get_villager(&"tomas")
	before = _snapshot()
	Deeds.perform(mara, "gift", "food")
	Deeds.perform(tomas, "gift", "food")
	_check(festival.done.has("gifts") and festival.bonus_given, "giving two gifts completes the festival")
	_check(int(_gained(before).get(&"wood", 0)) == 10, "with a bonus for doing it all (+10 wood and more)")
	mara.mind.record_interaction(GameManager.PLAYER_ID, "conversation", 1, 9.0)
	var greeting := festival.greeting_for(mara)
	_check(greeting != "" and festival.greeting_for(mara) == "", "villagers greet you with festival talk, once: %s" % greeting)
	WorldClock.set_time(18.5)
	festival.refresh()
	await _frames(2)
	var dancing := GameManager.villagers.filter(func(v): return v.has_task() and String(v.task.get("kind", "")) == "festival")
	_check(dancing.size() >= 3 and String(dancing[0].current_activity.animation) == "dance", "in the evening they gather at the fire and dance (%d)" % dancing.size())
	for v in dancing:
		v.task["until"] = 0.0
	# Saving mid-festival.
	var saved := festival.to_dict()
	var copy := Festival.new()
	copy.from_dict(JSON.parse_string(JSON.stringify(saved)))
	_check(copy.week == festival.week and copy.done.has("food") and copy.bonus_given and copy.goal_progress("food") == 12, "festival progress is saved and loaded")
	copy.free()
	# After the festival.
	WorldClock.day = 14
	WorldClock.set_time(9.0)
	festival.refresh()
	await _frames(2)
	_check(not festival.is_active() and festival._decorations == null and festival.history.size() == 1 and festival.history[0]["all_done"],
		"when it ends the decorations come down and the village remembers it")
	var topics: Array = Chatter._topics(mara)
	_check(topics.any(func(t): return String(t["key"]).begins_with("festival_past")), "and villagers talk about it afterwards")

	# Lantern Night: build a lantern, join the fire after dark.
	WorldClock.day = 19
	WorldClock.set_time(10.0)
	festival.refresh()
	GameState.add(&"wood", 10)
	GameState.add(&"stone", 10)
	var record := GameState.add_structure(&"lantern", VillageLayout.ground_point(-24.0, 26.0), 0.0)
	await _frames(3)
	for s in get_tree().get_nodes_in_group("placed_structures"):
		if s.record == record:
			while not s.is_complete():
				s.add_work(1.0)
	await _frames(2)
	_check(String(festival.current()["id"]) == "lanterns" and festival.done.has("lantern"), "Lantern Night: building a lantern counts")
	WorldClock.set_time(20.0)
	GameManager.player.global_position = Vector3(2.5, VillageLayout.plaza_floor_height() + 0.3, 2.5)
	festival._fire_timer = 0.0
	festival._process(0.1)
	_check(festival.done.has("fire") and festival.bonus_given, "and so does joining everyone at the fire after dark")
	for v in GameManager.villagers:
		if v.has_task():
			v.task["until"] = 0.0

	# Story Night: talking with four villagers.
	WorldClock.day = 33
	WorldClock.set_time(10.0)
	festival.refresh()
	var talked := 0
	for v in GameManager.villagers:
		if talked < 4:
			festival._on_conversation_started(v, null)
			festival._on_conversation_started(v, null)  # the same person twice counts once
			talked += 1
	_check(String(festival.current()["id"]) == "stories" and festival.done.has("talk"), "Story Night: talking with four different villagers")
	WorldClock.day = 35
	festival.refresh()


# --- Stories ------------------------------------------------------------------------

func _stories() -> void:
	var stories := VillageStories.instance
	_check(stories != null, "villager stories are in the game")
	var player := GameManager.PLAYER_ID
	WorldClock.day = 40
	WorldClock.set_time(10.0)
	# Remembering the day you met.
	var nia = GameManager.get_villager(&"nia")
	nia.mind.memory.entries = nia.mind.memory.entries.filter(func(e): return e["subject"] != player)
	nia.mind.record_interaction(player, "conversation", 30, 10.0)
	nia.mind.record_interaction(player, "conversation", 34, 10.0)
	nia.mind.adjust_opinion(player, 20.0, 5.0)
	var lines: Array = stories.story_lines(nia)
	_check(lines.size() == 1 and String(lines[0]).contains("10 days since you first came to talk"), "a villager remembers the day you met: %s" % (lines[0] if lines.size() else ""))
	_check(stories.story_lines(nia).is_empty() or not String(stories.story_lines(nia)[0]).contains("since you first came"), "and only once")
	# Repaying a kindness.
	var elias = GameManager.get_villager(&"elias")
	elias.mind.adjust_opinion(player, 45.0, 10.0)
	elias.mind.memory.add("deed", player, 38, 10.0, DialogueService.pack_deed("helped me fix the barn roof", 8.0))
	stories.done["anniversary:elias"] = true
	var before := _snapshot()
	lines = stories.story_lines(elias)
	_check(lines.size() == 2 and String(lines[0]).contains("helped me fix the barn roof") and not _gained(before).is_empty(),
		"a villager who remembers your kindness thanks you with a gift: %s" % (lines[0] if lines.size() else ""))
	_check(stories.story_lines(elias).is_empty(), "the thank-you happens once")
	# Making peace.
	for v in GameManager.villagers:
		for w in GameManager.villagers:
			if v != w:
				v.mind.relationships[String(w.get_villager_id())] = {"affection": 10.0, "trust": 0.0, "familiarity": 3}
	var sera = GameManager.get_villager(&"sera")
	var tomas = GameManager.get_villager(&"tomas")
	stories.peace = {}
	for v in GameManager.villagers:
		if v != sera:
			v.mind.relationships[player] = {"affection": 0.0, "trust": 0.0, "familiarity": 3}
	sera.mind.relationships[player] = {"affection": 25.0, "trust": 0.0, "familiarity": 3}
	sera.mind.relationships["tomas"] = {"affection": -25.0, "trust": 0.0, "familiarity": 3}
	stories.daily()
	_check(stories.peace.get("from", "") == "sera" and stories.peace.get("to", "") == "tomas", "Sera, a friend of yours, has fallen out with Tomas")
	lines = stories.story_lines(sera)
	_check(lines.size() == 2 and String(lines[1]).contains("make peace"), "she asks you to carry a peace offer: %s" % (lines[1] if lines.size() > 1 else ""))
	var menu: Array = DialogueService.menu_for(tomas)
	_check(menu.size() <= DialoguePanel.MAX_CHOICES and String(menu[0]["text"]).contains("Sera would like to make peace"), "talking to Tomas, you can pass it on (%d answers, all on screen)" % menu.size())
	# However many errands there are, the menu fits and Goodbye stays.
	var crowded: Array = [{"text": "a", "action": "request"}, {"text": "b", "action": "request"}, {"text": "c", "action": "request"}] + menu
	var fitted := DialogueService.fit_menu(crowded)
	_check(fitted.size() <= DialoguePanel.MAX_CHOICES and String(fitted[-1]["action"]) == "bye" and fitted.any(func(c): return c["action"] == "more"),
		"with many errands the menu still fits: kind, unkind and help fold into \"Something else...\" (%d answers)" % fitted.size())
	var more := Conversation.new(tomas, player)
	more.choices = fitted
	more.choose(fitted.find(fitted.filter(func(c): return c["action"] == "more")[0]))
	_check(more.choice_texts().has("Be kind...") and more.choice_texts().has("Never mind."), "and \"Something else...\" opens them")
	var talk := Conversation.new(tomas, player)
	talk.choices = menu
	talk.choose(0)
	_check(talk.lines.size() == 2 and tomas.mind.get_affection("sera") > 30.0 and sera.mind.get_affection("tomas") > 5.0, "Tomas trusts you, so he makes peace: %s" % (talk.lines[1] if talk.lines.size() > 1 else ""))
	var warmth: float = sera.mind.get_affection(player)
	lines = stories.story_lines(sera)
	_check(lines.size() == 2 and String(lines[0]).contains("came and found me") and sera.mind.get_affection(player) > warmth, "Sera thanks you")
	_check(Population.events.any(func(e): return e["type"] == "reconciled"), "the village hears about it")
	var gossip: Array = Chatter._topics(nia)
	_check(gossip.any(func(t): return String(t["line"]).contains("are talking again")), "and talks about it")
	stories.daily()
	_check(stories.peace.is_empty(), "the same pair isn't asked about twice")
	# A villager who doesn't trust you won't listen.
	stories.peace = {"from": "nia", "to": "mara", "day": WorldClock.day, "stage": "asked"}
	var mara = GameManager.get_villager(&"mara")
	mara.mind.relationships[player] = {"affection": -15.0, "trust": 0.0, "familiarity": 3}
	lines = stories.carry_peace(mara)
	_check(String(lines[0]).contains("not ready") and stories.peace["stage"] == "refused", "someone who distrusts you refuses: %s" % (lines[0] if lines.size() else ""))
	lines = stories.story_lines(nia)
	_check(lines.size() == 1 and String(lines[0]).contains("Thank you for trying") and stories.peace.is_empty(), "and the asker thanks you for trying")
	# An errand for someone who's gone is dropped (no talk about people who aren't here).
	stories.peace = {"from": "nia", "to": "nobody_here", "day": WorldClock.day, "stage": "asked"}
	stories.daily()
	_check(stories.peace.get("to", "") != "nobody_here", "an errand involving someone who's gone is dropped")
	# Saved.
	var copy := VillageStories.new()
	copy.from_dict(JSON.parse_string(JSON.stringify(stories.to_dict())))
	_check(copy.done.has("anniversary:nia") and copy.done.has("repay:elias") and copy.done.has(VillageStories._pair_key("sera", "tomas")), "stories told are saved")
	copy.free()
	# Hostile villagers don't tell stories.
	stories.done.erase("anniversary:mara")
	mara.mind.relationships[player] = {"affection": -60.0, "trust": 0.0, "familiarity": 3}
	_check(stories.story_lines(mara).is_empty(), "someone hostile to you doesn't tell you warm stories")
	mara.mind.relationships[player] = {"affection": 10.0, "trust": 0.0, "familiarity": 3}


# --- Rewarded ads -------------------------------------------------------------------

func _ads() -> void:
	_check(not ResourceLoader.exists(AdRewards.ADMOB_API + "MobileAds.gd") and AdRewards.provider == AdRewards.Provider.SIMULATED,
		"the AdMob plugin isn't installed: debug builds use a simulated ad")
	_check(AdRewards.rewarded_unit_id(true) == AdRewards.TEST_REWARDED_UNIT_ID, "debug builds always use Google's test ad unit")
	_check(AdRewards.PRODUCTION_REWARDED_UNIT_ID != "" or AdRewards.rewarded_unit_id(false) == AdRewards.TEST_REWARDED_UNIT_ID,
		"release builds use test ads until a real unit ID is supplied")
	var granted: Array = []
	var record := func(r): granted.append(r)
	AdRewards.reward_granted.connect(record)
	AdRewards._pending_reward = &"caravan"
	AdRewards._earned = false
	AdRewards.on_ad_dismissed()
	await get_tree().create_timer(AdRewards.LATE_REWARD_WAIT + 0.3, true, false, true).timeout
	_check(granted.is_empty(), "an ad closed early gives nothing")
	AdRewards._pending_reward = &"caravan"
	AdRewards._earned = false
	AdRewards.on_ad_dismissed()
	AdRewards.on_user_earned_reward()
	_check(granted == [&"caravan"], "the reward comes only when the ad SDK confirms it (even a moment after closing)")
	granted.clear()
	AdRewards._pending_reward = &"feast"
	AdRewards._earned = false
	AdRewards.on_user_earned_reward()
	AdRewards.on_ad_dismissed()
	_check(granted == [&"feast"], "confirmed, then closed: rewarded once")
	AdRewards.reward_granted.disconnect(record)
	AdRewards.reset_for_tests()


# --- Cost ---------------------------------------------------------------------------

func _performance() -> void:
	# A grown village: 30 people.
	for i in 30 - GameManager.villagers.size():
		PopulationDirector.instance.settle_newcomer()
	var wait := 0
	while (PopulationDirector.instance.is_spawning() or GameManager.villagers.size() < 30) and wait < 6000:
		await _frames(1)
		wait += 1
	var t0 := Time.get_ticks_usec()
	for i in 200:
		Festival.instance.refresh()
	var festival_us := (Time.get_ticks_usec() - t0) / 200.0
	t0 = Time.get_ticks_usec()
	for i in 200:
		VillageStories.instance.daily()
	var stories_us := (Time.get_ticks_usec() - t0) / 200.0
	t0 = Time.get_ticks_usec()
	for i in 200:
		DailyGift.instance.check(T0)
	var gift_us := (Time.get_ticks_usec() - t0) / 200.0
	print("  (festival refresh %.0f us, stories daily %.0f us, gift check %.1f us, %d villagers)" % [festival_us, stories_us, gift_us, GameManager.villagers.size()])
	_check(festival_us < 2000.0 and stories_us < 5000.0, "all of it is cheap: it runs hourly or daily, never every frame")
