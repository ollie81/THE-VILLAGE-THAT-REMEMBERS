extends Node
## Headless test of every villager's own dialogue:
##  - counts each founder's own spoken words (lines no other villager has,
##    shared pools left out) and checks the 2,500-word target;
##  - builds many generated newcomers and checks each has an own library of
##    at least 1,500 words, made from their style, trade, origin, ambition,
##    traits and a personal sheet, and that they differ from each other;
##  - dialogue that follows the time, weather, activity, mood and friendship;
##  - no repeats; stories; opinions; life events; the player's deeds;
##  - questions villagers ask, answered by button or typing, remembered and
##    brought up later; facts passed between villagers with their source;
##  - all of it across save and load; profile building is cheap.
## Prints a table of words per character.
## Run:  godot --headless --path . res://tests/dialogue_content_test.tscn

const FOUNDER_TARGET := 2500
const NEWCOMER_TARGET := 1500
const CHILD_TARGET := 1000
const SAMPLE := 80
const TOPICS := ["childhood", "family", "background", "work", "skills", "hobbies", "ambitions", "home", "furniture",
	"village", "friendship", "disagreements", "animals", "nature", "seasons", "mornings", "evenings", "events",
	"worries", "hopes", "surprises", "funny"]
const ALLOWED_PLACEHOLDERS := ["{you}", "{thing}", "{answer}", "{name}", "{job}"]

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


func _v(id: String):
	return GameManager.get_villager(StringName(id))


func _run() -> void:
	print("== Dialogue content test ==")
	WorldClock.day = 1
	WorldClock.set_time(10.0)
	WorldClock.set_time_scale(0.0)
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_main)
	await _frames(40)
	_founder_counts()
	_newcomer_counts()
	_situations()
	_variety_and_topics()
	_questions()
	_sharing()
	_life_and_deeds()
	await _real_newcomer()
	_saving()
	_performance()
	print("== %s: %d failure(s) ==" % ["PASSED" if _failures == 0 else "FAILED", _failures])
	get_tree().quit(0 if _failures == 0 else 1)


static func _strip(line: String) -> String:
	return RegEx.create_from_string("^\\[[a-z]+\\]").sub(line, "")


func _in(line: String, lines: Array) -> bool:
	var plain := _strip(line)
	for l in lines:
		var candidate := _strip(String(l))
		if candidate == plain:
			return true
		# Placeholders filled in ({you}, {thing}...): compare the fixed parts.
		if candidate.contains("{"):
			var pattern := "^" + RegEx.create_from_string("\\\\\\{[a-z_]+\\\\\\}").sub(_escape(candidate), ".*", true) + "$"
			if RegEx.create_from_string(pattern).search(plain):
				return true
	return false


static func _escape(text: String) -> String:
	var out := ""
	for c in text:
		out += ("\\" + c) if c in ".^$*+?()[]{}|\\" else c
	return out


## Lines a founder had before this stage (topic scenes, typed voice, .tres).
func _old_own_lines(id: String) -> Array:
	var out: Array = []
	for kind in TalkBrain.VOICES.get(id, {}):
		out.append_array(TalkBrain.VOICES[id][kind])
	for topic in ConversationLibrary.topics_for(StringName(id)):
		out.append_array(topic["lines"])
		for choice in topic["choices"]:
			out.append(String(choice.get("text", "")))
			out.append_array(choice.get("reply", []))
	var v = _v(id)
	if v:
		out.append_array(Array(v.data.first_meeting_lines))
		out.append_array(Array(v.data.returning_lines))
		for key in v.data.activity_comments:
			var c: Variant = v.data.activity_comments[key]
			if c is String:
				out.append(c)
			else:
				out.append_array(Array(c))
	return out


# --- Founders ----------------------------------------------------------------------

func _founder_counts() -> void:
	print("-- founders: own words, counted one by one")
	var libs := {}
	for id in DialogueLibrary.FOUNDERS:
		libs[id] = DialogueLibrary.spoken_lines(DialogueLibrary.profile(_v(id)))
	var shared_pool: Array = []
	for key in LineBank.LINES:
		var by_style: Dictionary = LineBank.LINES[key]
		for style in by_style:
			shared_pool.append_array(by_style[style])
	print("   %-8s %7s %7s %7s %9s %9s" % ["", "lines", "words", "shared", "old own", "total own"])
	for id in DialogueLibrary.FOUNDERS:
		var own: Array = []
		var shared := 0
		for l in libs[id]:
			var elsewhere := false
			for other in DialogueLibrary.FOUNDERS:
				if other != id and (libs[other] as Array).has(l):
					elsewhere = true
			if elsewhere or shared_pool.has(l):
				shared += 1
			else:
				own.append(l)
		var words := DialogueLibrary.word_count(own)
		var old := _old_own_lines(id)
		var total := DialogueLibrary.word_count(own + old)
		print("   %-8s %7d %7d %7d %9d %9d" % [id, own.size(), words, shared, DialogueLibrary.word_count(old), total])
		_check(words >= FOUNDER_TARGET, "%s has %d own words in their library (target %d+), %d lines shared with anyone" % [id, words, FOUNDER_TARGET, shared])
		var p := DialogueLibrary.profile(_v(id))
		var missing: Array = TOPICS.filter(func(t): return (p["topics"] as Dictionary).get(t, []).is_empty())
		_check(missing.is_empty(), "%s talks about every topic %s" % [id, str(missing)])
		var ok: bool = (p["greetings"] as Dictionary).size() == 4 and (p["weather"] as Dictionary).size() == 3 \
			and (p["activity"] as Dictionary).size() == 7 and (p["mood"] as Dictionary).size() == 4 and (p["relationship"] as Dictionary).size() == 4
		_check(ok, "%s has lines for each time of day, weather, activity, mood and friendship level" % id)
		_check((p["stories"] as Array).size() >= 3 and (p["questions"] as Array).size() >= 3 and (p["opinions"] as Dictionary).size() == 4,
			"%s has %d stories, %d questions and opinions of all four other founders" % [id, p["stories"].size(), p["questions"].size()])


# --- Newcomers ----------------------------------------------------------------------

func _person(rng: RandomNumberGenerator, i: int) -> Person:
	return PersonGenerator.create(rng, "dlg%d" % i, {}, [])


func _newcomer_counts() -> void:
	print("-- newcomers: each gets their own library")
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var people: Array = []
	var styles := {}
	var i := 0
	while (people.size() < SAMPLE or styles.size() < 8) and i < 2000:
		var p := _person(rng, i)
		i += 1
		if p.age() < 13:
			continue
		var style := DialogueLibrary.style_for(p)
		if people.size() >= SAMPLE and styles.has(style):
			continue
		styles[style] = int(styles.get(style, 0)) + 1
		people.append(p)
	_check(styles.size() == 8, "all 8 speaking styles occur among %d newcomers: %s" % [people.size(), str(styles)])
	var lines_of := {}
	var counts := {}
	for p: Person in people:
		var lines := DialogueLibrary.spoken_lines(DialogueLibrary.build_newcomer(p))
		lines_of[p.id] = lines
		for l in lines:
			counts[l] = int(counts.get(l, 0)) + 1
	var low: Array = []
	var min_words := 1 << 30
	var min_own := 1 << 30
	var total_own := 0
	var leftovers: Array = []
	print("   %-10s %-8s %-11s %-34s %7s %6s" % ["newcomer", "style", "trade", "origin", "words", "own"])
	var shown := 0
	for p: Person in people:
		var lines: Array = lines_of[p.id]
		var words := DialogueLibrary.word_count(lines)
		var own := DialogueLibrary.word_count(lines.filter(func(l): return int(counts[l]) == 1))
		min_words = mini(min_words, words)
		min_own = mini(min_own, own)
		total_own += own
		if words < NEWCOMER_TARGET:
			low.append("%s %d" % [p.id, words])
		for l in lines:
			for m in RegEx.create_from_string("\\{[a-z_]+\\}").search_all(String(l)):
				if not m.get_string() in ALLOWED_PLACEHOLDERS and not leftovers.has(m.get_string()):
					leftovers.append(m.get_string())
		if shown < 12:
			shown += 1
			print("   %-10s %-8s %-11s %-34s %7d %6d" % [p.first_name, DialogueLibrary.style_for(p), p.profession,
				DialogueLibrary.origin_key(p), words, own])
	_check(low.is_empty(), "every newcomer has %d+ words of their own library (lowest %d) %s" % [NEWCOMER_TARGET, min_words, str(low)])
	_check(min_own > 0, "every newcomer has lines no other newcomer says (personal sheet): lowest %d, average %d words" % [min_own, total_own / people.size()])
	_check(leftovers.is_empty(), "no unfilled placeholders %s" % str(leftovers))

	# Not just a sample: every style with every trade and every origin.
	var presets := {
		"warm": {}, "blunt": {"agreeableness": 0.2}, "anxious": {"neuroticism": 0.9}, "lively": {"extraversion": 0.9},
		"shy": {"extraversion": 0.1}, "dreamy": {"openness": 0.9}, "proud": {"conscientiousness": 0.9}, "wry": {"neuroticism": 0.1},
	}
	var origin_list: Array = DialogueLibrary._load(DialogueLibrary.DIR + "newcomers/origins.json").keys()
	var worst := [1 << 30, ""]
	var combos := 0
	var tester := _person(rng, 8000)
	while tester.age() < 18:
		tester = _person(rng, 8000 + combos)
		combos += 1
	combos = 0
	for style in presets:
		var pers := {"openness": 0.5, "conscientiousness": 0.5, "extraversion": 0.5, "agreeableness": 0.5, "neuroticism": 0.5, "adventure": 0.5}
		pers.merge(presets[style], true)
		tester.personality = pers
		for trade in Professions.CATALOG:
			tester.profession = trade
			for where in origin_list:
				tester.origin = "born" if where == "born_here" else ("invited" if where == "joined_family" else "traveller")
				tester.parents = []
				tester.biography = "%s came %s. A trader by trade." % [tester.first_name, where] if not where in ["born_here", "joined_family"] else "Came at the invitation of family."
				var built := DialogueLibrary.build_newcomer(tester)
				var w := DialogueLibrary.word_count(DialogueLibrary.spoken_lines(built))
				combos += 1
				if built["style"] != style:
					worst = [-1, "style %s came out as %s" % [style, built["style"]]]
				if w < int(worst[0]):
					worst = [w, "%s %s %s" % [style, trade, where]]
	_check(int(worst[0]) >= NEWCOMER_TARGET, "all %d combinations of style, trade and origin have %d+ words (lowest %d: %s)" % [combos, NEWCOMER_TARGET, worst[0], worst[1]])

	# Same style, trade and origin: still two different people.
	var a := people[0] as Person
	var b := _person(rng, 9001)
	b.personality = a.personality.duplicate()
	b.profession = a.profession
	b.biography = a.biography
	b.origin = a.origin
	b.traits = a.traits
	b.ambition = a.ambition.duplicate()
	var la := DialogueLibrary.spoken_lines(DialogueLibrary.build_newcomer(a))
	var lb := DialogueLibrary.spoken_lines(DialogueLibrary.build_newcomer(b))
	var differ := la.filter(func(l): return not lb.has(l)).size()
	_check(differ >= 15, "two newcomers with the same style, trade and origin still differ in %d lines (home town, family, keepsake...)" % differ)

	# Every trade and origin has its own lines.
	var trades := DialogueLibrary._load(DialogueLibrary.DIR + "newcomers/professions.json")
	var missing_trades: Array = Professions.CATALOG.keys().filter(func(k): return not trades.has(k))
	_check(missing_trades.is_empty(), "every trade has its own lines %s" % str(missing_trades))
	var origins := DialogueLibrary._load(DialogueLibrary.DIR + "newcomers/origins.json")
	var missing_origins: Array = Array(PersonGenerator.ORIGINS).filter(func(o): return not origins.has(o))
	_check(missing_origins.is_empty(), "every place newcomers come from has its own lines %s" % str(missing_origins))

	# Children: their own voice, born here.
	var parent_a := people[1] as Person
	var parent_b := people[2] as Person
	var child := PersonGenerator.create_child(rng, "dlgchild", {}, [])
	child.origin = "born"
	child.parents = [parent_a.id, parent_b.id]
	var cp := DialogueLibrary.build_newcomer(child)
	var child_words := DialogueLibrary.word_count(DialogueLibrary.spoken_lines(cp))
	_check(cp["style"] == "child" and cp["origin_key"] == "born_here" and child_words >= CHILD_TARGET,
		"a child born here talks like a child (%s, %s): %d words" % [cp["style"], cp["origin_key"], child_words])
	print("   newcomer library words: lowest %d, child %d" % [min_words, child_words])


# --- Situations ----------------------------------------------------------------------

func _situations() -> void:
	print("-- time, weather, activity, mood, friendship")
	_check(DialogueLibrary.time_key(7.0) == "morning" and DialogueLibrary.time_key(14.0) == "afternoon"
		and DialogueLibrary.time_key(19.0) == "evening" and DialogueLibrary.time_key(23.0) == "night", "time of day is known")
	var mara = _v("mara")
	var me := GameManager.PLAYER_ID
	WorldClock.set_time(7.5)
	var hello := " ".join(TalkBrain.respond(mara, "Good morning!", null)["lines"])
	var morning: Array = DialogueLibrary.pool(mara, "greetings/morning") + TalkBrain.VOICES["mara"]["greeting"]
	_check(_in(hello, morning), "Mara's morning hello is a morning line or her own greeting: %s" % hello)
	WorldClock.set_time(10.0)
	var keys: Array = []
	mara.mind.relationships.erase(me)
	keys.append(DialogueLibrary.relationship_key(mara))
	mara.mind.adjust_opinion(me, 20.0, 10.0)
	keys.append(DialogueLibrary.relationship_key(mara))
	mara.mind.adjust_opinion(me, 30.0, 10.0)
	keys.append(DialogueLibrary.relationship_key(mara))
	mara.mind.adjust_opinion(me, -80.0, -20.0)
	keys.append(DialogueLibrary.relationship_key(mara))
	mara.mind.relationships.erase(me)
	_check(keys == ["stranger", "friend", "close", "wary"], "friendship changes how Mara talks to you: %s" % str(keys))
	var person: Person = mara.person
	var happy := person.happiness
	person.happiness = 85.0
	var mood_happy := DialogueLibrary.mood_key(mara)
	person.happiness = 20.0
	var mood_low := DialogueLibrary.mood_key(mara)
	WorldClock.set_time(23.0)
	person.happiness = 60.0
	var mood_late := DialogueLibrary.mood_key(mara)
	WorldClock.set_time(10.0)
	person.happiness = happy
	_check(mood_low == "worried" and mood_late == "tired" and mood_happy in ["happy", "busy"],
		"mood follows what's true (happy %s, unhappy %s, late %s)" % [mood_happy, mood_low, mood_late])
	var situ: Array = []
	for n in 6:
		situ.append(DialogueLibrary.situational(_v("elias")))
	var all_elias := DialogueLibrary.spoken_lines(DialogueLibrary.profile(_v("elias")))
	_check(situ.all(func(l): return l != "" and _in(l, all_elias)), "Elias says something about right now, from his own lines")
	var unique := {}
	for l in situ:
		unique[l] = true
	_check(unique.size() >= 5, "and doesn't repeat himself (%d different in 6)" % unique.size())


func _variety_and_topics() -> void:
	print("-- topics you can ask about, without repeats")
	var tomas = _v("tomas")
	var said := {}
	for n in 4:
		said[" ".join(TalkBrain.respond(tomas, "What was your childhood like?", null)["lines"])] = true
	_check(said.size() == 4, "asking Tomas about his childhood four times gives four different answers")
	var asks := {
		"Tell me about your childhood": "topics/childhood", "Where are you from?": "topics/background",
		"What are your dreams for the future?": "topics/hopes", "Tell me about your house": "topics/home",
		"Do you have any pets?": "topics/animals", "Do you like the forest?": "topics/nature",
		"What's your favourite season?": "topics/seasons", "Who are your friends?": "topics/friendship",
		"Do you ever argue with anyone?": "topics/disagreements", "What are you good at?": "topics/skills",
	}
	var wrong: Array = []
	var mara = _v("mara")
	for text in asks:
		var answer := " ".join(TalkBrain.respond(mara, text, null)["lines"])
		var paths: Array = TalkBrain.TOPIC_PATHS.get(String(TalkBrain.understand(text, mara)["intent"]), [asks[text]])
		var pool: Array = []
		for p in paths:
			pool.append_array(DialogueLibrary.pool(mara, String(p)))
		if not _in(answer, pool):
			wrong.append("%s -> %s" % [text, answer])
	_check(wrong.is_empty(), "Mara answers %d kinds of personal question from her own lines %s" % [asks.size(), str(wrong)])
	var sera = _v("sera")
	var first := TalkBrain.respond(sera, "Tell me a story", null)["lines"] as Array
	var second := TalkBrain.respond(sera, "Tell me another story", null)["lines"] as Array
	var stories := DialogueLibrary.pool(sera, "stories")
	_check(first.size() == 4 and _in(String(first[0]), stories[0]) and _in(String(second[0]), stories[1]),
		"Sera tells a whole story, then a different one next time")
	var elias = _v("elias")
	var before: float = elias.mind.get_affection("nia")
	var of_nia := " ".join(TalkBrain.respond(elias, "What do you think of Nia?", null)["lines"])
	_check(before <= -15.0 or (of_nia.contains("Nia") and _in(_strip(of_nia).trim_prefix("Nia? "), DialogueLibrary.pool(elias, "opinions/nia"))),
		"Elias talks about Nia, by name, in his own words: %s" % of_nia)
	var joke := " ".join(TalkBrain.respond(sera, "Tell me something funny", null)["lines"])
	_check(_in(joke, DialogueLibrary.pool(sera, "topics/funny") + TalkBrain.VOICES["sera"]["joke"]), "Sera's jokes come from her own funny stories too")


# --- Questions -----------------------------------------------------------------------

func _talked(v, times: int) -> void:
	for n in times:
		v.mind.memory.add("conversation", GameManager.PLAYER_ID, WorldClock.day - 1, 10.0)


func _questions() -> void:
	print("-- villagers ask you things and remember the answers")
	var nia = _v("nia")
	_check(not DialogueLibrary.wants_to_ask(nia), "no questions on a first meeting")
	_talked(nia, 2)
	_check(DialogueLibrary.wants_to_ask(nia), "after a couple of chats, Nia wants to ask you something")
	# With nothing planned to talk about, the conversation opens with it.
	for topic in ConversationLibrary.topics_for(&"nia"):
		nia.mind.memory.add("topic", GameManager.PLAYER_ID, 0, 10.0, String(topic["id"]))
	var c := DialogueService.build_conversation(nia, GameManager.PLAYER_ID)
	var q := DialogueLibrary.question(nia, c.pending_question.trim_prefix(DialogueLibrary.ANSWER_PREFIX))
	_check(not q.is_empty() and c.lines.has(String(q["ask"])), "Nia asks: %s" % (q.get("ask", "(nothing)")))
	var answers: Array = c.choices.filter(func(ch): return String(ch.get("action", "")) == "answer")
	_check(answers.size() >= 3 and answers.all(func(ch): return Conversation.kind_of(ch) == "say"), "the answers are things you say (%d buttons)" % answers.size())
	c.lines.clear()
	c.choose(0)
	var key := String(answers[0]["answer"])
	_check(DialogueLibrary.answer_of(nia, String(q["id"])) == key and not c.lines.is_empty(), "she reacts and remembers you said '%s': %s" % [key, " ".join(c.lines)])
	_check(not DialogueLibrary.wants_to_ask(nia), "only one question a day")
	_check(DialogueLibrary.recall(nia) == "", "she doesn't bring it up again the same day")
	WorldClock.day += 1
	var recalled := DialogueLibrary.recall(nia)
	_check(recalled != "" and not recalled.contains("{"), "the next day she remembers it: %s" % recalled)
	_check(DialogueLibrary.recall(nia) != recalled, "and doesn't keep repeating it")
	# Typed answers, including ones not on the list.
	var sera = _v("sera")
	var conv := Conversation.new(sera, GameManager.PLAYER_ID)
	conv.pending_question = DialogueLibrary.ANSWER_PREFIX + "sera_travel"
	conv.say_typed("I would love to see the moon")
	_check(DialogueLibrary.answer_of(sera, "sera_travel") == "the moon" and " ".join(conv.lines).contains("The moon?"),
		"a typed answer that isn't on the list is kept in your words (the heart of it): %s" % " ".join(conv.lines))
	_check(DialogueLibrary.answer_phrase("Probably a little red boat!") == "a little red boat" and DialogueLibrary.answer_phrase("I'd build a tower") == "a tower",
		"filler words are left out of remembered answers")
	conv.lines.clear()
	conv.pending_question = DialogueLibrary.ANSWER_PREFIX + "sera_bargain"
	conv.say_typed("Nope, I'm terrible")
	_check(DialogueLibrary.answer_of(sera, "sera_bargain") == "no", "a typed 'nope' counts as no")
	WorldClock.day += 1
	var r := ""
	for n in 3:
		var got := DialogueLibrary.recall(sera)
		if got != "":
			r += got + " "
	_check(r.contains("travel to the moon.") and r.contains("haggle"), "both come back later, in sensible words: %s" % r)
	var asked := " ".join(TalkBrain.respond(_v("tomas"), "Ask me a question", conv)["lines"])
	_check(conv.pending_question.begins_with(DialogueLibrary.ANSWER_PREFIX) and asked != "", "you can ask them to ask you something: %s" % asked)
	var skip := Conversation.new(_v("tomas"), GameManager.PLAYER_ID)
	skip.pending_question = conv.pending_question
	skip.choices = DialogueLibrary.ask(_v("tomas"), DialogueLibrary.question(_v("tomas"), conv.pending_question.trim_prefix(DialogueLibrary.ANSWER_PREFIX)))
	skip.choose(skip.choices.size() - 1)
	_check(" ".join(skip.lines).contains("alright"), "you can choose not to answer")


# --- Sharing -------------------------------------------------------------------------

func _sharing() -> void:
	print("-- villagers pass on what they really know about you")
	var mara = _v("mara")
	var elias = _v("elias")
	var tomas = _v("tomas")
	TalkBrain.respond(mara, "My name is Robin", null)
	TalkBrain.respond(mara, "I'm from the hills", null)
	_check(TalkBrain.known_name(elias) != "Robin", "(Elias hasn't been told)")
	mara.mind.adjust_opinion("elias", 20.0, 10.0)
	var shared := DialogueLibrary.share(mara, elias)
	_check(shared == "name", "Mara tells Elias your name")
	_check(DialogueLibrary.share(elias, tomas) == "", "Elias doesn't pass on what he only heard")
	var line := DialogueLibrary.heard_line(elias)
	_check(line.contains("Mara") and line.contains("Robin") and TalkBrain.known_name(elias) == "Robin",
		"Elias says who told him, and knows it from then on: %s" % line)
	_check(DialogueLibrary.heard_line(elias) == "", "he mentions it once")
	mara.mind.adjust_opinion("tomas", -60.0, -30.0)
	_check(DialogueLibrary.share(mara, tomas) == "", "villagers don't gossip with people they dislike")
	var nothing = _v("nia")
	_check(DialogueLibrary.share(nothing, tomas) == "" or TalkBrain.facts(nothing, "name").size() > 0, "nobody passes on facts they don't have")


# --- Life events and the player's deeds ----------------------------------------------

func _life_and_deeds() -> void:
	print("-- their life and what you've done")
	var nia = _v("nia")
	var person: Person = nia.person
	var old_partner := person.partner
	person.partner = "tomas"
	var said := DialogueLibrary.life_news(nia)
	_check(_in(said, DialogueLibrary.pool(nia, "life/partner")), "Nia talks about her new partner: %s" % said)
	_check(not _in(DialogueLibrary.life_news(nia), DialogueLibrary.pool(nia, "life/partner")), "once")
	person.partner = old_partner
	# A gift: the first one gets her own words too.
	GameState.add(&"food", 3)
	var lines := Deeds.perform(nia, "gift", "food")
	_check(lines.size() >= 2 and _in(String(lines[1]), DialogueLibrary.pool(nia, "player/gift")), "Nia thanks you for a first gift in her own words: %s" % " ".join(lines))
	var again := Deeds.perform(nia, "gift", "food")
	_check(again.size() == 1, "later gifts don't repeat it")
	if CreditRewards.instance:
		var credits := CreditRewards._credits()
		if credits:
			credits.paid["discover_windmill"] = true
			var news := DialogueLibrary.player_news(_v("tomas"))
			_check(news.contains("windmill"), "Tomas heard you found the windmill: %s" % news)
			_check(not DialogueLibrary.player_news(_v("tomas")).contains("windmill"), "and says so once")


# --- A real newcomer in the village --------------------------------------------------

func _real_newcomer() -> void:
	print("-- a newcomer living in the village")
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var person: Person
	for n in 50:
		person = PersonGenerator.create(rng, Population.new_id(), Population.taken_first_names(), Population.appearances())
		if person.age() >= 18:
			break
	Population.add(person)
	Population.make_resident(person)
	PopulationDirector.instance._spawn(person, false)
	var guard := 0
	while GameManager.get_villager(StringName(person.id)) == null and guard < 400:
		await _frames(2)
		guard += 1
	var v = GameManager.get_villager(StringName(person.id))
	_check(v != null, "%s (%s, %s) moved in" % [person.first_name, DialogueLibrary.style_for(person), person.profession])
	if v == null:
		return
	var all := DialogueLibrary.spoken_lines(DialogueLibrary.profile(v))
	var home_town := String(DialogueLibrary.sheet(person)["home_town"])
	var job := " ".join(TalkBrain.respond(v, "What do you do for work?", null)["lines"])
	_check(_in(job, all + TalkBrain.VOICES[TalkBrain.style_of(v)]["job"]), "they talk about their own work: %s" % job)
	var told: Array = []
	var off: Array = []
	for text in ["Tell me about your childhood", "Where are you from?", "Tell me a story", "Do you have any pets?", "What do you hope for?"]:
		var said: Array = TalkBrain.respond(v, text, null)["lines"]
		told.append(" ".join(said))
		if said.is_empty() or not _in(String(said[0]), all):
			off.append("%s -> %s" % [text, " ".join(said)])
	_check(off.is_empty(), "they answer personal questions from their own library %s" % str(off))
	var everything := " ".join(told)
	for n in 6:
		everything += " " + " ".join(TalkBrain.respond(v, "Tell me about your childhood", null)["lines"])
		everything += " " + " ".join(TalkBrain.respond(v, "Where are you from?", null)["lines"])
	print("   e.g. ", told[0])
	_check(everything.contains(home_town) or everything.contains(String(DialogueLibrary.sheet(person)["kin_name"])) or everything.contains(String(DialogueLibrary.sheet(person)["pet_name"])),
		"their answers include their own life (%s...)" % home_town)
	_check(DialogueLibrary.next_question(v).size() > 0, "they have questions of their own to ask you")


# --- Save and load ----------------------------------------------------------------------

func _saving() -> void:
	print("-- save and load")
	var nia = _v("nia")
	var elias = _v("elias")
	var nia_saved: Dictionary = JSON.parse_string(JSON.stringify(nia.get_save_data()))
	var elias_saved: Dictionary = JSON.parse_string(JSON.stringify(elias.get_save_data()))
	var answers := {}
	for q in DialogueLibrary.pool(nia, "questions"):
		answers[q["id"]] = DialogueLibrary.answer_of(nia, String(q["id"]))
	nia.mind.memory.entries.clear()
	elias.mind.memory.entries.clear()
	_check(DialogueLibrary.wants_to_ask(nia) == false and TalkBrain.known_name(elias) == "", "(forgotten for the test)")
	nia.apply_save_data(nia_saved)
	elias.apply_save_data(elias_saved)
	var same := true
	for id in answers:
		if DialogueLibrary.answer_of(nia, String(id)) != answers[id]:
			same = false
	_check(same, "answers to her questions survive save and load")
	_check(TalkBrain.known_name(elias) == "Robin" and DialogueLibrary.heard_line(elias) == "", "what Elias heard (and already said) survives too")


func _performance() -> void:
	print("-- many villagers")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var start := Time.get_ticks_usec()
	for n in 200:
		DialogueLibrary.build_newcomer(_person(rng, 5000 + n))
	var ms := float(Time.get_ticks_usec() - start) / 1000.0
	print("   200 newcomer libraries built in %.0f ms (%.2f ms each, cached after the first)" % [ms, ms / 200.0])
	_check(ms / 200.0 < 25.0, "building a newcomer's library is quick (%.2f ms on this machine)" % (ms / 200.0))
	var v = _v("mara")
	_check(DialogueLibrary.profile(v) == DialogueLibrary.profile(v), "profiles are cached")
