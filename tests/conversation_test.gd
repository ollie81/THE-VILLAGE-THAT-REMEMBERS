extends Node
## Headless test of conversations with villagers:
##  - typing your own messages (understood or honestly not understood);
##  - the answer buttons (words, actions and menus, by what they do);
##  - five founders who sound like themselves;
##  - memory: what you tell them (and only that), across save and load;
##  - friendship changes with consequences;
##  - one speaker at a time (mouths), "You" for the player;
##  - the panel on a phone screen, with the keyboard up; End chat.
## Run:  godot --headless --path . res://tests/conversation_test.tscn

var _failures: int = 0
var _main = null
var _panel: DialoguePanel


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


func _v(id: String):
	return GameManager.get_villager(StringName(id))


func _run() -> void:
	print("== Conversation test ==")
	WorldClock.day = 1
	WorldClock.set_time(10.0)
	WorldClock.set_time_scale(0.0)
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_main)
	await _frames(40)
	_panel = _main.find_child("DialoguePanel", true, false)
	_understanding()
	_personalities()
	_memory_and_feelings()
	await _panel_typing()
	await _buttons()
	await _speaking()
	await _layout()
	_saving()
	print("== %s: %d failure(s) ==" % ["PASSED" if _failures == 0 else "FAILED", _failures])
	get_tree().quit(0 if _failures == 0 else 1)


func _say(id: String, text: String) -> Dictionary:
	return TalkBrain.respond(_v(id), text, null)


func _text(answer: Dictionary) -> String:
	return " ".join(answer["lines"])


# --- What typed messages are understood as ---------------------------------------------

func _understanding() -> void:
	print("-- understanding typed messages")
	var cases := {
		"Hello!": "greeting", "hey there": "greeting", "How are you?": "how_are_you",
		"What's your name?": "ask_name", "What do you do for a living?": "ask_job",
		"What are you doing?": "ask_activity", "Do you have a family?": "ask_family",
		"Any news?": "ask_news", "What's wrong?": "ask_worries", "What's your favourite thing?": "ask_likes",
		"Do you like it here in the village?": "ask_village", "Thank you!": "thanks", "Sorry about that.": "apology",
		"You're really kind": "compliment", "You're stupid": "insult", "My name is Sam": "player_name",
		"I love fishing": "player_like", "I'm from the coast": "player_from", "I'm so tired": "player_feeling",
		"Can I help you?": "offer_help", "Could you help me?": "ask_help", "Is it raining?": "weather",
		"Tell me a joke": "joke", "Goodbye": "farewell", "What do you think of Tomas?": "ask_person",
		"Do you remember me?": "ask_recall", "What's my name?": "ask_player_name",
		"Purple elephants dance quietly?": "unknown_question", "zxqv blorp": "unknown",
	}
	var wrong: Array = []
	for text in cases:
		var got := String(TalkBrain.understand(text, _v("mara"))["intent"])
		if got != cases[text]:
			wrong.append("%s -> %s (wanted %s)" % [text, got, cases[text]])
	_check(wrong.is_empty(), "%d kinds of message are recognised %s" % [cases.size(), str(wrong)])
	_check(TalkBrain.clean("   hi\n\tthere  ") == "hi there" and TalkBrain.clean("x".repeat(400)).length() == TalkBrain.MAX_LENGTH,
		"messages are tidied and capped at %d characters" % TalkBrain.MAX_LENGTH)
	_check(TalkBrain.understand("", null)["intent"] == "empty", "an empty message is noticed")
	var unknown := _text(_say("elias", "zxqv blorp"))
	_check(unknown.to_lower().contains("follow") or unknown.to_lower().contains("catch") or unknown.to_lower().contains("not sure"),
		"something it can't interpret gets an honest 'I don't follow' with suggestions: %s" % unknown)
	_check(_text(_say("mara", "What are you doing?")).to_lower().contains(String(_v("mara").get_activity_description()).to_lower().rstrip(".").substr(0, 12)),
		"asked what she's doing, Mara says what she's really doing: %s" % _text(_say("mara", "What are you doing?")))
	_check(_text(_say("nia", "What do you think of Tomas?")).contains("Tomas"), "asked about someone, they talk about that person")
	_check(_text(_say("sera", "goodbye"))!= "" and bool(_say("sera", "see you")["end"]), "a typed goodbye ends the conversation")
	var several := _say("elias", "Hi Elias! My name is Robin. I love bread.")
	_check(several["lines"].size() >= 3 and TalkBrain.known_name(_v("elias")) == "Robin" and TalkBrain.facts(_v("elias"), "likes").has("bread"),
		"a message with several sentences gets an answer to each: %s" % _text(several))
	_check(_text(several).contains("Me too"), "and Elias, who loves bread, says so")


# --- Five founders, five voices ------------------------------------------------------------

func _personalities() -> void:
	print("-- different villagers, different voices")
	var ids := ["mara", "elias", "nia", "tomas", "sera"]
	for question in ["How are you?", "What do you do?", "What do you like?", "Hello"]:
		var replies := {}
		for id in ids:
			replies[_text(_say(id, question))] = id
		_check(replies.size() == ids.size(), "\"%s\": five different answers" % question)
	_check(_text(_say("tomas", "What's your name?")).contains("Tomas") and _text(_say("sera", "Who are you?")).contains("Sera"), "each introduces themselves in their own words")
	var styles := ids.map(func(id): return TalkBrain.style_of(_v(id)))
	_check(styles == ids, "each founder has their own voice: %s" % str(styles))
	# Mood changes the answer.
	var elias = _v("elias")
	elias.person.happiness = 90.0
	var happy := _text(_say("elias", "how are you"))
	elias.person.happiness = 20.0
	var sad := _text(_say("elias", "how are you"))
	elias.person.happiness = 70.0
	_check(happy != sad and (sad.contains("heavy") or sad.contains("best day") or sad.contains("pass")), "their mood shows: happy \"%s\" / low \"%s\"" % [happy, sad])


# --- Memory and feelings ------------------------------------------------------------------------

func _memory_and_feelings() -> void:
	print("-- memory and friendship")
	var nia = _v("nia")
	var me := GameManager.PLAYER_ID
	_check(_text(_say("nia", "What's my name?")).contains("haven't told me"), "she doesn't pretend to know a name she was never told")
	_check(_text(_say("nia", "Do you remember me?")).contains("don't know much") or _text(_say("nia", "Do you remember me?")).contains("haven't told me much"),
		"nor anything else about you")
	_say("nia", "My name is Sam")
	_check(TalkBrain.known_name(nia) == "Sam" and _text(_say("nia", "what's my name?")).contains("Sam"), "told your name, she remembers it")
	_say("nia", "I love flowers")
	_check(TalkBrain.facts(nia, "likes").has("flowers"), "and what you like")
	_say("nia", "I'm from the coast")
	var recall := _text(_say("nia", "what do you remember about me?"))
	_check(recall.contains("Sam") and recall.contains("flowers") and recall.contains("Coast"), "and tells you what she remembers: %s" % recall)
	_check(_text(_say("nia", "hello")).contains("Sam"), "she greets you by name now")
	_check(TalkBrain.known_name(_v("mara")) == "", "Mara wasn't told, so she doesn't know it")
	# Feelings.
	var before: float = nia.mind.get_affection(me)
	_say("nia", "You're really clever")
	var after_one: float = nia.mind.get_affection(me)
	_say("nia", "You're really clever")
	_say("nia", "You're really clever")
	var after_three: float = nia.mind.get_affection(me)
	_check(after_one > before and after_three - after_one < after_one - before + 0.01, "a compliment warms her; saying it over and over counts for less")
	var tomas = _v("tomas")
	var t0: float = tomas.mind.get_affection(me)
	var insult := _say("tomas", "You're useless")
	_check(tomas.mind.get_affection(me) < t0 - 5.0, "an insult hurts the friendship")
	_check(tomas.mind.memory.find("deed", me).any(func(e): return String(e["detail"]).contains("hurtful")), "and is remembered (it can come up later, and spread as gossip)")
	for i in 6:
		_say("tomas", "You're stupid")
	_check(tomas.mind.is_hostile(me), "keep it up and he won't talk to you")
	_check(_text(_say("tomas", "How are you?")) in TalkBrain.VOICES["tomas"]["cool"], "he answers coldly to anything but an apology")
	var t1: float = tomas.mind.get_affection(me)
	_check(_text(_say("tomas", "I'm sorry")).length() > 0 and tomas.mind.get_affection(me) > t1, "an apology helps")
	tomas.mind.relationships.erase(me)


# --- The panel: typing -------------------------------------------------------------------------

func _start(id: String) -> void:
	var v = _v(id)
	GameManager.player.global_position = v.global_position + Vector3(1.5, 0, 0)
	GameManager.start_conversation(v)
	await _frames(3)
	var guard := 0
	while not _panel._choice_box.visible and _panel.visible and guard < 30:
		_panel.advance()
		await _frames(2)
		guard += 1


func _panel_typing() -> void:
	print("-- typing in the conversation")
	await _start("sera")
	_check(_panel.visible and _panel._input_row.visible, "on your turn there's a box to type in (and the answers)")
	_check(_panel._input.placeholder_text.contains("Sera") and _panel._input.placeholder_text.contains("simple"), "it says who you're talking to, and that simple sentences work best")
	_panel._input.text = "   "
	_check(not _panel.send_typed() and _panel._hint.visible and _panel._input_row.visible, "an empty message isn't sent; it says why: %s" % _panel._hint.text)
	_panel._input.text = "What's your job?"
	_check(_panel.send_typed(), "a message is sent")
	await _frames(1)
	_check(_panel._name_label.text == "You" and _panel._text_label.text == "What's your job?" and _panel.speaker_role == "player", "it appears under \"You\"")
	_panel.advance()
	_panel.advance()
	await _frames(2)
	_check(_panel._name_label.text == "Sera" and (_panel._text_label.text.contains("trade") or _panel._text_label.text.contains("Trader")), "Sera answers what you asked: %s" % _panel._text_label.text)
	var guard := 0
	while not _panel._choice_box.visible and guard < 10:
		_panel.advance()
		await _frames(1)
		guard += 1
	_check(_panel._choice_box.visible and _panel._input_row.visible, "then it's your turn again (answers or typing)")
	_panel._input.text = "bye for now"
	_panel.send_typed()
	for i in 6:
		_panel.advance()
		await _frames(1)
	_check(not GameManager.is_in_conversation(), "typing goodbye ends the conversation after her farewell")


# --- The panel: buttons ------------------------------------------------------------------------

func _buttons() -> void:
	print("-- answer buttons")
	await _start("elias")
	var conv: Conversation = _panel._conversation
	var say := -1
	for i in conv.choices.size():
		if Conversation.kind_of(conv.choices[i]) == "say":
			say = i
			break
	var text := String(conv.choices[say]["text"]) if say >= 0 else ""
	_panel._choose(say)
	await _frames(1)
	_check(say >= 0 and _panel.speaker_role == "player" and _panel._text_label.text == text, "a spoken answer is said by \"You\": %s" % text)
	var guard := 0
	while not _panel._choice_box.visible and guard < 20:
		_panel.advance()
		await _frames(1)
		guard += 1
	# "Be kind..." is a menu: nothing is said.
	conv = _panel._conversation
	var kind_i := -1
	for i in conv.choices.size():
		if String(conv.choices[i].get("action", "")) in ["kind", "more"]:
			kind_i = i
	if kind_i >= 0:
		var was_more := String(conv.choices[kind_i]["action"]) == "more"
		_panel._choose(kind_i)
		await _frames(1)
		_check(_panel.speaker_role == "" and _panel._choice_box.visible, "a menu button just opens the next answers (nothing said)")
		if was_more:
			for i in _panel._conversation.choices.size():
				if String(_panel._conversation.choices[i].get("action", "")) == "kind":
					_panel._choose(i)
					await _frames(1)
					break
		var deed := -1
		for i in _panel._conversation.choices.size():
			if Conversation.kind_of(_panel._conversation.choices[i]) == "do":
				deed = i
				break
		var deed_text := String(_panel._conversation.choices[deed]["text"]) if deed >= 0 else ""
		_panel._choose(deed)
		await _frames(1)
		_check(deed >= 0 and _panel.speaker_role == "action" and _panel._text_label.text.begins_with("You ") and _panel._text_label.text.contains("Elias"),
			"an action is told as something you do, not words: \"%s\" -> \"%s\"" % [deed_text, _panel._text_label.text])
		_check(not GameManager.player.model._talking, "and nobody's mouth moves for it")
	else:
		_check(false, "the menu offers kindness")
	_panel.end_chat()
	await _frames(2)
	_check(not GameManager.is_in_conversation() and not _panel.visible, "End chat leaves at any time")


# --- One speaker at a time -----------------------------------------------------------------------

func _speaking() -> void:
	print("-- who's speaking")
	await _start("nia")
	var nia = _v("nia")
	var player = GameManager.player
	_check(nia.state == Villager.State.INTERACTING and nia.model._state != &"talk", "while you talk, she listens (not stuck in a talking loop)")
	_panel._input.text = "How are you?"
	_panel.send_typed()
	await _frames(2)
	_check(player.model._talking and not nia.model._talking, "your line: your mouth moves, hers doesn't")
	_panel.advance()
	_panel.advance()
	await _frames(2)
	_check(nia.model._talking and not player.model._talking and _panel.speaker_role == "villager", "her line: her mouth moves, yours doesn't")
	_panel.advance()
	await _frames(2)
	_check(not nia.model._talking and not player.model._talking, "line finished: both quiet")
	_panel.end_chat()
	await _frames(2)


# --- On a phone screen ---------------------------------------------------------------------------

func _layout() -> void:
	print("-- phone layout")
	await _start("mara")
	await _frames(3)
	var screen := _panel.get_viewport_rect().size
	var rect := _panel.get_global_rect()
	_check(rect.position.y >= 0.0 and rect.end.y <= screen.y and rect.position.x >= 0.0 and rect.end.x <= screen.x, "the conversation fits the screen (%s in %s)" % [rect, screen])
	var small := _panel._choice_buttons.filter(func(b): return b.visible and b.size.y < 44.0)
	_check(small.is_empty() and _panel._send.size.y >= 44.0 and _panel._end_button.size.y >= 44.0, "buttons are big enough to tap")
	_panel._input.grab_focus()
	_panel.keyboard_height_override = 320.0
	await _frames(3)
	rect = _panel.get_global_rect()
	_check(rect.end.y <= screen.y - 320.0 + 1.0 and rect.position.y >= 0.0, "with the keyboard up, the panel moves above it (bottom %d)" % int(rect.end.y))
	_check(not _panel._choice_box.visible and _panel._input_row.visible, "and the answer buttons step aside while you type")
	_panel._input.release_focus()
	_panel.keyboard_height_override = -1.0
	await _frames(3)
	_check(_panel._choice_box.visible, "they come back when you stop typing")
	_panel.end_chat()
	await _frames(2)


# --- Saving -------------------------------------------------------------------------------------

func _saving() -> void:
	print("-- save and load")
	var nia = _v("nia")
	var data: Dictionary = JSON.parse_string(JSON.stringify(nia.get_save_data()))
	var affection: float = nia.mind.get_affection(GameManager.PLAYER_ID)
	nia.mind.memory.entries.clear()
	nia.mind.relationships.clear()
	_check(TalkBrain.known_name(nia) == "", "(forgotten for the test)")
	nia.apply_save_data(data)
	_check(TalkBrain.known_name(nia) == "Sam" and TalkBrain.facts(nia, "likes").has("flowers"), "after loading she still knows your name and what you like")
	_check(absf(nia.mind.get_affection(GameManager.PLAYER_ID) - affection) < 0.01, "and how she feels about you")
