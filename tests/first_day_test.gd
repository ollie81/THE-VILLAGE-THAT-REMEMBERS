extends Node
## Headless test of a new player's first day, played the way a player does:
## say hello to two villagers, gather, build your own house (the starter kit
## and the first gathering are enough), go in and furnish it; each goal
## rewarded once, the last one inviting you back tomorrow. And older saves:
## their place in the old order is kept, nothing is rewarded twice.
## Run:  godot --headless --path . res://tests/first_day_test.tscn

var _failures: int = 0
var _main = null


func _ready() -> void:
	SaveService.enabled = false
	PopulationDirector.auto_arrivals = false
	DailyGift.persist = false
	Reminders.persist = false
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


func _id() -> String:
	return String(GameState.current_objective().get("id", ""))


func _run() -> void:
	print("== First day test ==")
	WorldClock.day = 1
	WorldClock.set_time(9.0)
	WorldClock.set_time_scale(0.0)
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_main)
	await _frames(40)
	await _first_day()
	await _reminders()
	_migration()
	print("== %s: %d failure(s) ==" % ["PASSED" if _failures == 0 else "FAILED", _failures])
	get_tree().quit(0 if _failures == 0 else 1)


func _first_day() -> void:
	print("-- a new player's first day")
	CreditRewards.enabled = true
	var gathered_before: Dictionary = CreditRewards.instance.gathered.duplicate()
	GameState.give_starter_kit()
	_check(CreditRewards.instance.gathered == gathered_before, "the starter kit doesn't count as gathering (no free daily challenge)")
	CreditRewards.enabled = false
	var credits := VillageCredits.instance
	var player: PlayerController = GameManager.player
	_check(_id() == "hello" and GameState.current_objective()["title"] == "Say hello", "the first goal is just to say hello")
	var order: Array = GameState.OBJECTIVES.map(func(o): return o["id"])
	_check(order.slice(0, 4) == ["hello", "gather", "house", "home"], "the first day: hello, gather, your own house, make it home (%s)" % str(order.slice(0, 4)))
	# Say hello to two founders (a real conversation each).
	var food := GameState.count(&"food")
	var before := credits.balance
	var met := 0
	for v in GameManager.villagers:
		if met < 2 and v.person and v.person.founder:
			GameManager.start_conversation(v)
			GameManager.end_conversation()
			await _frames(2)
			met += 1
	await _frames(2)
	_check(_id() == "gather", "two hellos and the goal is done: next, %s" % _id())
	_check(GameState.count(&"food") >= food + 2 and credits.balance == before + int(EconomyConfig.EARN["objective"]), "rewarded: food and %d credits" % int(EconomyConfig.EARN["objective"]))
	# Gather.
	Guide.instance.refresh()
	_check(Guide.instance.target_label == "Chop", "the guide points to a tree")
	GameState.add(&"wood", 10)
	GameState.add(&"stone", 6)
	await _frames(2)
	_check(_id() == "house", "then: build your own house")
	var cost: Dictionary = StructureCatalog.info(&"house")["cost"]
	_check(GameState.can_afford(cost), "the starter kit and the first gathering pay for it (%s)" % GameState.cost_text(cost))
	Guide.instance.refresh()
	_check(Guide.instance.wanted_build == &"house", "the guide says to choose a House in Build: %s" % Guide.instance.step)
	# Place it the way a player does, and build it.
	BuildMode.instance.start(&"house")
	await _frames(3)
	var why := BuildMode.instance.confirm()
	_check(why == "", "the house site is placed near you %s" % why)
	await _frames(3)
	var site: PlacedStructure = null
	for s in StructureManager.instance.structures():
		if HouseDesigns.is_house(s.get_type()):
			site = s
	Guide.instance.refresh()
	_check(site != null and Guide.instance.step.contains("Tap Build at the site"), "the guide points to the site")
	var taps := 0
	while site and not site.is_complete() and taps < 20:
		site.use(player)
		taps += 1
		await _frames(1)
	await _frames(3)
	_check(site.is_complete() and _id() == "home", "%d taps and it's built: next, make it home" % taps)
	# Go in and furnish.
	Guide.instance.refresh()
	_check(Guide.instance.target_label == "Your house", "the guide points to your front door")
	player.global_position = site.doorstep()
	site.use(player)
	await _seconds(Interiors.FADE_TIME * 2.0 + 0.4)
	Guide.instance.refresh()
	_check(Interiors.instance.is_inside() and Guide.instance.step.contains("Furnish"), "inside, it says to tap Furnish: %s" % Guide.instance.step)
	var notices: Array = []
	var listen := func(text): notices.append(text)
	GameManager.notice.connect(listen)
	_check(FurnishMode.instance.start_new(&"stool") == "", "choose a stool to place")
	await _frames(3)
	var err := FurnishMode.instance.confirm()
	await _frames(3)
	_check(err == "" and _id() == "meet", "placing it makes it home (%s): next, meet everyone" % err)
	_check(notices.any(func(t): return String(t).contains("tomorrow")), "and the village invites you back tomorrow")
	GameManager.notice.disconnect(listen)
	Interiors.instance.leave()
	await _seconds(Interiors.FADE_TIME * 2.0 + 0.4)
	# Each goal pays once, by name.
	var tokens := credits.paid.keys().filter(func(k): return String(k).begins_with("objective_"))
	_check(tokens.has("objective_hello") and tokens.has("objective_home") and tokens.size() == 4, "four goals, four payments: %s" % str(tokens))
	# Saved by name.
	var data: Dictionary = JSON.parse_string(JSON.stringify(GameState.to_dict()))
	_check(String(data.get("objective_id", "")) == "meet", "the save keeps the goal by name")


func _reminders() -> void:
	print("-- the daily reminder")
	var r := Reminders.instance
	_check(r != null and not r.enabled, "reminders are off until the player says yes")
	await _seconds(4.5)
	_check(r.is_asking(), "after making it home, the game asks once")
	(r.find_child("Yes", true, false) as Button).pressed.emit()
	await _frames(2)
	_check(r.enabled and r.asked and not r.is_asking(), "saying yes turns the reminder on")
	# Put away at 21:00 UTC on some day.
	var now := 20000.0 * 86400.0 + 21.0 * 3600.0
	DailyGift.instance.streak = 0
	var plan := r.schedule_next(now)
	var hour := Reminders.local_hour(float(plan["at"]))
	_check(not plan.is_empty() and float(plan["at"]) >= now + Reminders.MIN_GAP_HOURS * 3600.0, "one reminder, not before the next day (%d h later)" % int(float(plan["delay"]) / 3600.0))
	_check(float(plan["at"]) >= (floor(now / 86400.0) + 1.0) * 86400.0, "and never before the next daily gift is ready")
	_check(hour >= Reminders.EARLIEST_HOUR and hour < Reminders.LATEST_HOUR + 0.01, "at a friendly local hour (%.1f)" % hour)
	_check(String(plan["text"]).length() > 20 and String(plan["title"]) != "", "with a friendly message: %s" % plan["text"])
	var texts := {}
	for d in 3:
		texts[r.message(20001 + d)] = true
	_check(texts.size() >= 2, "that changes from day to day")
	DailyGift.instance.streak = 4
	_check(r.message(20001).contains("5-day streak"), "a streak to keep comes first: %s" % r.message(20001))
	DailyGift.instance.streak = 0
	r.set_enabled(false)
	_check(r.schedule_next(now).is_empty(), "switched off: nothing is planned")
	var settings: SettingsPanel = _main.find_child("SettingsPanel", true, false) as SettingsPanel
	if settings:
		settings.visible = true
		await _frames(2)
		var toggle: CheckButton = settings.find_child("ReminderToggle", true, false)
		_check(toggle != null and not toggle.button_pressed, "Settings shows the reminder switch (off)")
		toggle.button_pressed = true
		await _frames(1)
		_check(r.enabled, "and turns it on")
		settings.visible = false
	r.set_enabled(false)


func _migration() -> void:
	print("-- older saves")
	var keep: Dictionary = JSON.parse_string(JSON.stringify(GameState.to_dict()))
	# An old save part way through (old order: meet, gather, farm plot, harvest...).
	var old := keep.duplicate(true)
	old.erase("objective_id")
	old["objective_index"] = 3  # was on "harvest"
	old["flags"] = {}
	GameState.from_dict(old)
	var done: Array = GameState.get_flag(&"objectives_done", [])
	_check(done.has("meet") and done.has("gather") and done.has("farm_plot") and done.has("hello") and not done.has("harvest"),
		"what an old save had done counts as done: %s" % str(done))
	var credits := VillageCredits.instance
	var before := credits.balance
	var paid_before: Dictionary = credits.paid.duplicate()
	var completed: Array = []
	var listen := func(i, _t): completed.append(GameState.objective_id(i))
	GameState.objective_completed.connect(listen)
	GameState.check_objectives()
	_check(not completed.has("meet") and not completed.has("gather") and not completed.has("farm_plot"), "and isn't rewarded again: %s" % str(completed))
	var new_goals := completed.filter(func(id): return not paid_before.has("objective_" + String(id)))
	_check(credits.balance - before == new_goals.size() * int(EconomyConfig.EARN["objective"]), "only goals never paid before pay (%s)" % str(new_goals))
	GameState.objective_completed.disconnect(listen)
	# An old save that had finished the week.
	old["objective_index"] = 7
	GameState.from_dict(old)
	GameState.check_objectives()
	_check(GameState.is_week_complete(), "an old save that had finished stays finished")
	# A new save comes back where it was.
	GameState.from_dict(keep)
	_check(_id() == "meet", "a new save comes back on the same goal")
