extends Node
## Headless test of the reasons to come back every day: villagers' daily
## requests (fetch, message, check on someone), remembering requests you
## forgot, and the village living on while you're away ("While you were
## away..."), including saving.
## Run:  godot --headless --path . res://tests/hooks_test.tscn

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


func _request_of(kind: String) -> Dictionary:
	for request: Dictionary in RequestBoard.instance.open_requests():
		if String(request["kind"]) == kind:
			return request
	return {}


## Makes sure there's an open request of `kind` (new days until one appears).
func _ensure(kind: String) -> Dictionary:
	for attempt in 30:
		var request := _request_of(kind)
		if not request.is_empty():
			return request
		RequestBoard.instance.new_day()
	return {}


func _talk(villager) -> Conversation:
	var c := DialogueService.build_conversation(villager, GameManager.PLAYER_ID)
	villager.mind.record_interaction(GameManager.PLAYER_ID, "conversation", WorldClock.day, WorldClock.time_of_day)
	return c


## Plays a conversation through the topic to the closing menu.
func _to_menu(c: Conversation) -> void:
	for step in 4:
		c.lines.clear()
		if c.choice_texts().has("Goodbye."):
			return
		if c.choices.is_empty():
			return
		c.choose(0)


static func _find_prefix(texts: PackedStringArray, prefix: String) -> int:
	for i in texts.size():
		if texts[i].begins_with(prefix):
			return i
	return -1


func _run() -> void:
	print("== Hooks test ==")
	WorldClock.day = 3
	WorldClock.set_time(9.0)
	WorldClock.set_time_scale(0.0)
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_main)
	await _frames(40)
	var board: RequestBoard = RequestBoard.instance
	var panel: RequestsPanel = _main.find_child("RequestsPanel", true, false)
	for v in GameManager.villagers:
		v.mind.record_interaction(GameManager.PLAYER_ID, "conversation", 1, 9.0)
		for topic in ConversationLibrary.topics_for(v.data.id):
			v.mind.memory.add("topic", GameManager.PLAYER_ID, 1, 9.0, String(topic["id"]))

	# --- Requests ------------------------------------------------------------------
	_check(board != null and board.requests.size() >= 2 and board.requests.size() <= 4, "each morning brings %d requests" % board.requests.size())
	for request: Dictionary in board.requests:
		print("    - %s" % request["text"])
	var askers := {}
	for request: Dictionary in board.requests:
		askers[request["from"]] = true
	_check(askers.size() == board.requests.size(), "from different villagers")
	await _frames(40)
	_check(panel._card.visible and panel._list.get_child_count() == board.requests.size(), "a 'Today's requests' card lists them")
	var first = GameManager.get_villager(StringName(String(board.requests[0]["from"])))
	_check(first._marker != null and first._marker.visible and first._marker.text == "!", "a ! above %s's head" % first.data.display_name)

	# Fetch.
	var fetch := _ensure("fetch")
	var asker = GameManager.get_villager(StringName(String(fetch["from"])))
	var resource := StringName(String(fetch["resource"]))
	var c := _talk(asker)
	var all_lines := " ".join(c.lines)
	_check(all_lines.contains(String(fetch["ask"]).substr(String(fetch["ask"]).find("]") + 1, 20)), "%s asks: %s" % [asker.data.display_name, fetch["ask"]])
	_to_menu(c)
	_check(_find_prefix(c.choice_texts(), "Here are") < 0, "no 'here you are' until you have the %s" % resource)
	GameState.add(resource, int(fetch["amount"]))
	var warmth: float = asker.mind.get_affection(GameManager.PLAYER_ID)
	var before := GameState.count(resource)
	c = _talk(asker)
	_check(" ".join(c.lines).contains("Any luck"), "they ask how it's going if you come back")
	_to_menu(c)
	var index := _find_prefix(c.choice_texts(), "Here are")
	_check(index >= 0, "with the %s, you can hand them over: %s" % [resource, c.choice_texts()[index] if index >= 0 else "?"])
	c.choose(index)
	_check(bool(fetch["done"]) and GameState.count(resource) <= before - int(fetch["amount"]) + 3, "the request is done")
	_check(asker.mind.get_affection(GameManager.PLAYER_ID) >= warmth + 9.0, "and %s is grateful: %s" % [asker.data.display_name, " / ".join(c.lines)])
	_check(asker.mind.memory.find("deed", GameManager.PLAYER_ID).any(func(e): return String(e["detail"]).begins_with("helped me with")), "and remembers it")

	# Message.
	var message := _ensure("message")
	if message.is_empty():
		_check(false, "a message request appears within a few days")
	else:
		var from = GameManager.get_villager(StringName(String(message["from"])))
		var to = GameManager.get_villager(StringName(String(message["to"])))
		await _frames(35)
		var expected := "!" if not board.asked_by(to).is_empty() else "…"
		_check(to._marker != null and to._marker.visible and to._marker.text == expected,
			"a %s above %s, who the message is for" % [expected, to.data.display_name])
		var between: float = from.mind.get_affection(String(to.get_villager_id()))
		var m := _talk(to)
		_to_menu(m)
		var at := Array(m.choice_texts()).find(String(message["line_to"]))
		_check(at >= 0, "passing it on: \"%s\"" % message["line_to"])
		m.choose(at)
		_check(bool(message["done"]) and from.mind.get_affection(String(to.get_villager_id())) > between, "%s replies: %s" % [to.data.display_name, m.lines[0] if m.has_lines() else ""])
		_check(from.has_meta("pending_line"), "and %s will thank you" % from.data.display_name)

	# Check on someone.
	var check := _ensure("check")
	if check.is_empty():
		_check(false, "a check-on-someone request appears within a few days")
	else:
		var friend = GameManager.get_villager(StringName(String(check["to"])))
		var k := _talk(friend)
		_to_menu(k)
		var at := Array(k.choice_texts()).find(String(check["line_to"]))
		k.choose(at)
		_check(at >= 0 and bool(check["done"]), "checking on %s for someone worried about them" % friend.data.display_name)

	# Forgetting.
	board.new_day()
	var forgotten: Dictionary = board.requests[0]
	var forgetful = GameManager.get_villager(StringName(String(forgotten["from"])))
	var trust: float = forgetful.mind.get_trust(GameManager.PLAYER_ID)
	WorldClock.day += 1
	board.new_day()
	_check(forgetful.mind.get_trust(GameManager.PLAYER_ID) < trust, "a request left undone is remembered (a little less trust)")
	var next := _talk(forgetful)
	var mention := ""
	for line in next.lines:
		if line.contains("yesterday") and line.contains(String(forgotten["reason"])):
			mention = line
	_check(mention != "", "and gently mentioned: %s" % mention)
	var again := _talk(forgetful)
	_check(not " ".join(again.lines).contains(String(forgotten["reason"]) + " yesterday") and not again.lines.has(mention), "but only once")

	# Help everyone.
	for request: Dictionary in board.open_requests():
		var who = GameManager.get_villager(StringName(String(request["from"] if String(request["kind"]) == "fetch" else request["to"])))
		if String(request["kind"]) == "fetch":
			GameState.add(StringName(String(request["resource"])), int(request["amount"]))
		board.fulfil(int(request["id"]), who)
	_check(board.open_requests().is_empty() and board.completed_total >= 4, "helping everyone in a day (%d requests done so far)" % board.completed_total)

	# --- While you were away --------------------------------------------------------
	var away: AwayTime = AwayTime.instance
	_check(is_equal_approx(AwayTime.seconds_to_hours(WorldClock.real_seconds_per_day), 24.0), "a real day-length absence is one village day")
	_check(AwayTime.seconds_to_hours(7 * 24 * 3600.0) == AwayTime.MAX_HOURS, "a week away still only moves the village on one day")
	# Plant a field so there's something to come back to.
	GameState.add(&"wood", 20)
	var record := GameState.add_structure(&"farm_plot", VillageLayout.ground_point(-30.0, 8.0), 0.0)
	await _frames(3)
	for s in get_tree().get_nodes_in_group("placed_structures"):
		if s.record == record:
			while not s.is_complete():
				s.add_work(1.0)
			s.use()
	WorldClock.set_time(20.0)
	var day_before := WorldClock.day
	var events_before := Population.events.size()
	var shown: Array = []
	away.caught_up.connect(func(summary): shown.append(summary))
	var summary := away.catch_up(16.0)
	await _frames(5)
	_check(WorldClock.day == day_before + 1 and absf(WorldClock.time_of_day - 12.0) < 0.01, "16 hours later it's the next day at noon")
	_check(not shown.is_empty() and panel.is_story_open(), "a 'While you were away...' story opens")
	print("    %s / %s" % [summary["title"], summary["subtitle"]])
	for line in summary["lines"]:
		print("      • %s" % line)
	_check(summary["lines"].size() >= 2, "it tells what happened (%d things)" % summary["lines"].size())
	_check(" ".join(summary["lines"]).contains("crops are ready"), "the crops ripened while you were away")
	_check(" ".join(summary["lines"]).contains("something to ask you"), "it mentions who has something to ask you today")
	_check(Population.events.size() > events_before, "villagers lived their lives (new events)")
	_check(board.day == WorldClock.day and not board.requests.is_empty(), "the new day brought new requests")
	var placed := 0
	for v in GameManager.villagers:
		if v.current_activity:
			placed += 1
	_check(placed == GameManager.villagers.size(), "everyone is where their day puts them now")
	panel._away.visible = false

	# --- Saving -----------------------------------------------------------------------
	var saved: Dictionary = JSON.parse_string(JSON.stringify(board.to_dict()))
	var count := board.requests.size()
	var total := board.completed_total
	board.from_dict(saved)
	_check(board.requests.size() == count and board.completed_total == total and board.day == WorldClock.day, "requests survive save and load")
	board.start()
	_check(board.requests.size() == count, "loading the same day doesn't ask new requests")

	print("== %s: %d failure(s) ==" % ["PASSED" if _failures == 0 else "FAILED", _failures])
	get_tree().quit(0 if _failures == 0 else 1)
