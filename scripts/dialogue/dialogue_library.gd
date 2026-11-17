class_name DialogueLibrary
extends RefCounted
## Each villager's own dialogue, loaded from data/dialogue.
##
## Founders have a hand-written file each (founders/<id>.json). Everyone else
## gets a library put together from who they are: a speaking style from their
## personality (warm, blunt, shy, lively, dreamy, anxious, proud, wry, or the
## child voice), lines about their trade, the place they came from, their
## ambition and their traits, and a personal sheet (home town, a relative, a
## keepsake, a favourite food, a fear, an old pet, a dream) seeded from their
## id, so no two newcomers tell the same life story.
##
## Every profile has the same shape: greetings by time of day, weather,
## activity, mood and relationship lines, topics (childhood, family, work...),
## opinions of others, reactions to what the player has done, life events,
## multi-line stories, and questions they ask the player (answers are
## remembered as facts). Files load once and profiles are cached, so a big
## village costs little.

const DIR := "res://data/dialogue/"
const FOUNDERS := ["mara", "elias", "nia", "tomas", "sera"]
const STYLES := ["warm", "blunt", "shy", "lively", "dreamy", "anxious", "proud", "wry", "child"]
## Keys that hold data rather than spoken words.
const NOT_SPOKEN := ["id", "options", "free", "style", "origin_key", "sheet"]
## Remembered answers are saved as facts "q:<question id>=<answer>".
const ANSWER_PREFIX := "q:"
## A villager asks at most one question per day, from their second chat on.
const ASK_FROM_CONVERSATION := 2
const MAX_FREE_ANSWER := 30

## What the player did, as the villager would say it ("I heard you {thing}").
const ACHIEVEMENT_TEXT := {
	"first_home": "built your first house", "builder": "finished five buildings",
	"master_builder": "finished fifteen buildings", "homemaker": "filled your home with furniture",
	"cosy": "made your home the cosiest in the valley", "animal_friend": "took in an animal",
	"farmyard": "are looking after five animals now", "explorer": "explored three places already",
	"cartographer": "found every place in the valley", "woodcutter": "gathered sixty wood",
	"stonemason": "gathered forty stone", "regular": "kept coming back, day after day",
	"go_getter": "finished six daily challenges",
}

static var _files: Dictionary = {}
static var _profiles: Dictionary = {}


static func _load(path: String) -> Dictionary:
	if _files.has(path):
		return _files[path]
	var parsed: Variant = null
	if FileAccess.file_exists(path):
		parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	var out: Dictionary = parsed if parsed is Dictionary else {}
	if out.is_empty():
		push_warning("Dialogue file missing or invalid: " + path)
	_files[path] = out
	return out


static func clear_cache() -> void:
	_profiles.clear()


## This villager's dialogue (empty for anyone without a person, e.g. tests
## with bare villagers).
static func profile(villager) -> Dictionary:
	if villager == null or villager.data == null:
		return {}
	var id := String(villager.data.id)
	var person: Person = villager.person
	var key := id + ("/child" if person and person.age() < 13 else "")
	if _profiles.has(key):
		return _profiles[key]
	var p: Dictionary = {}
	if id in FOUNDERS:
		p = _load(DIR + "founders/%s.json" % id)
	elif person:
		p = build_newcomer(person)
	_profiles[key] = p
	return p


# --- Newcomers --------------------------------------------------------------------

## Speaking style from personality (the strongest side of them shows first).
static func style_for(person: Person) -> String:
	if person == null:
		return "warm"
	if person.age() < 13:
		return "child"
	var p: Dictionary = person.personality
	if float(p.get("agreeableness", 0.5)) < 0.4:
		return "blunt"
	if float(p.get("neuroticism", 0.5)) > 0.7:
		return "anxious"
	if float(p.get("extraversion", 0.5)) > 0.65:
		return "lively"
	if float(p.get("extraversion", 0.5)) < 0.35:
		return "shy"
	if float(p.get("openness", 0.5)) > 0.65:
		return "dreamy"
	if float(p.get("conscientiousness", 0.5)) > 0.68:
		return "proud"
	if float(p.get("neuroticism", 0.5)) < 0.32:
		return "wry"
	return "warm"


## Which origin's lines fit: the place named in their story, family who
## invited them, or the village itself for children born here.
static func origin_key(person: Person) -> String:
	var origins := _load(DIR + "newcomers/origins.json")
	for key in origins:
		if key not in ["born_here", "joined_family"] and person.biography.contains(String(key)):
			return String(key)
	if person.origin == "born" or not person.parents.is_empty() and person.origin != "invited":
		return "born_here"
	if person.origin == "invited" or person.biography.contains("invitation"):
		return "joined_family"
	var keys: Array = origins.keys().filter(func(k): return not String(k) in ["born_here", "joined_family"])
	if keys.is_empty():
		return ""
	return String(keys[absi(hash(person.id)) % keys.size()])


## Their personal details, the same every time for the same person.
static func sheet(person: Person) -> Dictionary:
	var lists: Dictionary = _load(DIR + "newcomers/personal.json").get("sheet", {})
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(person.id + "|sheet")
	var out := {}
	for key in lists:
		var options: Array = lists[key]
		out[key] = String(options[rng.randi_range(0, options.size() - 1)]) if not options.is_empty() else ""
	out["home_town"] = String(out.get("town_start", "")) + String(out.get("town_end", ""))
	return out


static func build_newcomer(person: Person) -> Dictionary:
	var style := style_for(person)
	var styles := _load(DIR + "newcomers/styles.json")
	var professions := _load(DIR + "newcomers/professions.json")
	var origins := _load(DIR + "newcomers/origins.json")
	var personal := _load(DIR + "newcomers/personal.json")
	var p := {"id": person.id, "style": style, "greetings": {}, "weather": {}, "activity": {}, "mood": {},
		"relationship": {}, "topics": {}, "opinions": {}, "player": {}, "life": {}, "stories": [], "questions": []}
	_merge(p, styles.get(style, styles.get("warm", {})))
	if style != "child":
		_merge(p, professions.get(person.profession, {}))
	var where := origin_key(person)
	p["origin_key"] = where
	_merge(p, origins.get(where, {}))
	_merge(p["topics"], personal.get("lines", {}))
	var ambition := String(person.ambition.get("id", ""))
	var ambitions: Dictionary = personal.get("ambitions", {})
	if style != "child" and ambitions.has(ambition):
		_merge(p["topics"], {"ambitions": ambitions[ambition]})
	var traits: Dictionary = personal.get("traits", {})
	for t in person.traits:
		if traits.has(String(t)):
			_merge(p["topics"], {"personality": traits[String(t)]})
	var s := sheet(person)
	p["sheet"] = s
	return _fill_all(p, s)


static func _merge(into: Dictionary, from: Dictionary) -> void:
	for key in from:
		var value: Variant = from[key]
		if value is Dictionary:
			if not into.get(key) is Dictionary:
				into[key] = {}
			_merge(into[key], value)
		elif value is Array:
			if not into.get(key) is Array:
				into[key] = []
			(into[key] as Array).append_array((value as Array).duplicate(true))
		else:
			into[key] = value


static func _fill_all(value: Variant, s: Dictionary, key: String = "") -> Variant:
	if key in NOT_SPOKEN:
		return value
	if value is String:
		return _fill_sheet(value, s)
	if value is Array:
		var out: Array = []
		for item in value:
			out.append(_fill_all(item, s))
		return out
	if value is Dictionary:
		var out := {}
		for k in value:
			out[k] = _fill_all(value[k], s, String(k))
		return out
	return value


static func _fill_sheet(line: String, s: Dictionary) -> String:
	if not line.contains("{"):
		return line
	for key in s:
		line = line.replace("{%s}" % key, String(s[key]))
	return line


# --- Picking lines ----------------------------------------------------------------

## The lines at "a/b" in this villager's profile ([] if none).
static func pool(villager, path: String) -> Array:
	var node: Variant = profile(villager)
	for part in path.split("/"):
		if node is Dictionary and (node as Dictionary).has(part):
			node = node[part]
		else:
			return []
	return node if node is Array else []


## A line from "a/b", not one they've said lately ("" if they have none).
static func line(villager, path: String, thing: String = "") -> String:
	var lines := pool(villager, path)
	if lines.is_empty():
		return ""
	# Something specific to react to: lines that name it come first.
	if thing != "":
		var naming := lines.filter(func(l): return String(l).contains("{thing}"))
		if not naming.is_empty():
			lines = naming
	return _finish(villager, LineBank._fresh(villager, lines), thing)


## A line from any of `paths` (pooled together).
static func line_any(villager, paths: Array, thing: String = "") -> String:
	var lines: Array = []
	for p in paths:
		lines.append_array(pool(villager, String(p)))
	if lines.is_empty():
		return ""
	return _finish(villager, LineBank._fresh(villager, lines), thing)


static func _finish(villager, text: String, thing: String) -> String:
	return TalkBrain.fill(villager, text.replace("{thing}", thing))


static func time_key(hour: float) -> String:
	if hour >= 5.0 and hour < 12.0:
		return "morning"
	if hour >= 12.0 and hour < 17.0:
		return "afternoon"
	if hour >= 17.0 and hour < 22.0:
		return "evening"
	return "night"


static func weather_key() -> String:
	if Weather.instance and Weather.instance.has_method("is_storm") and Weather.instance.is_storm():
		return "storm"
	if Weather.instance and Weather.instance.is_raining():
		return "rain"
	return "clear"


static func activity_key(villager) -> String:
	var activity: VillagerActivity = villager.current_activity
	if activity == null:
		return "rest"
	if activity.is_sleep():
		return "sleep"
	var kind := String(activity.kind)
	if kind in ["work", "gather", "trade", "socialize", "explore"]:
		return kind
	if kind == "wander":
		return "explore"
	return "rest"


## How they're feeling, from what's true: a loss or a tent worries them,
## late hours tire them, a good life makes them happy, work keeps them busy.
static func mood_key(villager) -> String:
	var person: Person = villager.person
	if person and (Population.recently_lost(person) or person.leaving or person.home == Population.CAMP_ID):
		return "worried"
	if VillageDefence.instance and VillageDefence.instance.is_raid():
		return "worried"
	var h := WorldClock.time_of_day
	if h >= 22.0 or h < 5.0:
		return "tired"
	var happiness := person.happiness if person else 60.0
	if happiness < 40.0:
		return "worried"
	if activity_key(villager) in ["work", "trade"]:
		return "busy"
	if happiness >= 70.0:
		return "happy"
	return ""


## How well they know the player.
static func relationship_key(villager) -> String:
	var mind: VillagerMind = villager.mind
	var me := GameManager.PLAYER_ID
	var affection := mind.get_affection(me)
	if mind.is_hostile(me) or affection <= -15.0:
		return "wary"
	if affection >= 40.0:
		return "close"
	if affection >= 12.0 or mind.memory.count("conversation", me) >= 6:
		return "friend"
	return "stranger"


## One line about right now: how they feel, the weather, what they're
## doing, the time of day, or how they feel about you. Varied, and never
## the same one twice in a row.
static func situational(villager) -> String:
	var paths: Array = []
	var mood := mood_key(villager)
	if mood != "":
		paths.append("mood/" + mood)
	paths.append("weather/" + weather_key())
	paths.append("activity/" + activity_key(villager))
	paths.append("greetings/" + time_key(WorldClock.time_of_day))
	paths.append("relationship/" + relationship_key(villager))
	# A worried or grieving villager talks about that first.
	if mood == "worried" and not pool(villager, "mood/worried").is_empty():
		return line(villager, "mood/worried")
	return line_any(villager, paths)


# --- Things they bring up once -----------------------------------------------------

static func _mentioned(villager, key: String) -> bool:
	return villager.mind.memory.has_detail("mentioned", GameManager.PLAYER_ID, key)


static func _mark(villager, key: String) -> void:
	villager.mind.memory.add("mentioned", GameManager.PLAYER_ID, WorldClock.day, WorldClock.time_of_day, key)


## Something the player did that this villager hasn't mentioned yet: a
## place found, an achievement, the player's first house. Only real records.
static func player_news(villager) -> String:
	var rewards := CreditRewards.instance
	if rewards:
		for a in CreditRewards.ACHIEVEMENTS:
			var id := String(a["id"])
			if rewards.is_achieved(id) and not _mentioned(villager, "player:a_" + id):
				_mark(villager, "player:a_" + id)
				var out := line(villager, "player/achievement", String(ACHIEVEMENT_TEXT.get(id, "did something special")))
				if out != "":
					return out
		for place in CreditRewards.PLACES:
			var pid := String(place["id"])
			if rewards.is_discovered(pid) and not _mentioned(villager, "player:d_" + pid):
				_mark(villager, "player:d_" + pid)
				var found := line(villager, "player/discovery", String(place["name"]))
				if found != "":
					return found
		if rewards.stat("houses") > 0 and not _mentioned(villager, "player:house"):
			_mark(villager, "player:house")
			return line(villager, "player/house")
	return ""


## Their own life: grief first, then a new partner, a baby, a home the
## player gave them, a new friend. Each said once (grief can return later).
static func life_news(villager) -> String:
	var person: Person = villager.person
	if person == null:
		return ""
	var lost := Population.recently_lost(person)
	if lost and not _mentioned(villager, "life:grief:" + lost.id):
		_mark(villager, "life:grief:" + lost.id)
		return line(villager, "life/grief")
	if person.partner != "" and not _mentioned(villager, "life:partner:" + person.partner):
		_mark(villager, "life:partner:" + person.partner)
		return line(villager, "life/partner")
	for child_id in person.children:
		if not _mentioned(villager, "life:child:" + String(child_id)):
			_mark(villager, "life:child:" + String(child_id))
			return line(villager, "life/child")
	if person.home != "" and person.home != Population.CAMP_ID and not _mentioned(villager, "life:home:" + person.home):
		_mark(villager, "life:home:" + person.home)
		return line(villager, "life/new_home")
	if SocialLife.instance:
		for friend_id in SocialLife.instance.friends_of(villager):
			if not _mentioned(villager, "life:friend:" + String(friend_id)):
				_mark(villager, "life:friend:" + String(friend_id))
				return line(villager, "life/friend")
	return ""


# --- Questions they ask the player ------------------------------------------------

static func question(villager, id: String) -> Dictionary:
	for q in pool(villager, "questions"):
		if String(q.get("id", "")) == id:
			return q
	return {}


static func answer_of(villager, id: String) -> String:
	return TalkBrain.fact(villager, ANSWER_PREFIX + id)


## The next question they haven't asked yet ({} when none are left).
static func next_question(villager) -> Dictionary:
	for q in pool(villager, "questions"):
		var id := String(q.get("id", ""))
		if answer_of(villager, id) == "" and not _mentioned(villager, "asked:" + id):
			return q
	return {}


## Should they ask something now? Not on a first meeting, not someone who's
## cross with you, and only once a day.
static func wants_to_ask(villager) -> bool:
	var mind: VillagerMind = villager.mind
	var me := GameManager.PLAYER_ID
	if mind.is_hostile(me) or mind.get_affection(me) < -5.0:
		return false
	if mind.memory.count("conversation", me) < ASK_FROM_CONVERSATION:
		return false
	for e in mind.memory.find("mentioned", me):
		if String(e["detail"]).begins_with("asked:") and int(e["day"]) == WorldClock.day:
			return false
	return not next_question(villager).is_empty()


## Marks the question asked and returns the answer buttons (spoken choices).
static func ask(villager, q: Dictionary) -> Array:
	_mark(villager, "asked:" + String(q["id"]))
	var choices: Array = []
	var options: Dictionary = q.get("options", {})
	for key in options:
		choices.append({"text": String(key).capitalize() + ".", "action": "answer", "question": String(q["id"]), "answer": String(key), "kind": "say"})
	choices.append({"text": "I'd rather not say.", "action": "answer", "question": String(q["id"]), "answer": "", "kind": "say"})
	return choices


## Which option `text` means ("" if none).
static func match_answer(q: Dictionary, text: String) -> String:
	var n := TalkBrain.normalize(text)
	var options: Dictionary = q.get("options", {})
	for key in options:
		for word in options[key]:
			if RegEx.create_from_string("\\b" + TalkBrain.normalize(String(word)) + "\\b").search(n):
				return String(key)
	return ""


## The player answered (a button's key, or typed words). Remembers it and
## returns the villager's reaction. An empty answer means "rather not say".
static func answer(villager, q: Dictionary, key: String, typed: String = "") -> String:
	var id := String(q["id"])
	if key == "" and typed == "":
		_mark(villager, "skipped:" + id)
		return "[happy]That's alright. Another time, maybe."
	if key == "" and typed != "":
		key = match_answer(q, typed)
	var react: Dictionary = q.get("react", {})
	var value := key
	if key == "" or not react.has(key):
		if not bool(q.get("free", false)) and key == "":
			# A yes/no question answered with something else: keep it, unsure.
			value = "other"
		else:
			value = answer_phrase(typed)
			key = "other"
	TalkBrain.remember_fact(villager, ANSWER_PREFIX + id, value)
	villager.mind.adjust_opinion(GameManager.PLAYER_ID, 1.5, 1.0)
	var reaction := String(react.get(key, react.get("other", "[happy]I'll remember that.")))
	return LineBank.capitalize_first(TalkBrain.fill(villager, reaction.replace("{answer}", value)))


## The heart of a typed answer: "I would love to see the moon!" -> "the moon".
static func answer_phrase(typed: String) -> String:
	var text := TalkBrain.clean(typed).strip_edges()
	while text.length() > 0 and text[text.length() - 1] in ".!?,":
		text = text.substr(0, text.length() - 1)
	var filler := RegEx.create_from_string("(?i)^(well|hmm+|um+|oh|probably|maybe|definitely|i think|i guess|honestly|to be honest|my answer is|i d say|i'd say|i would say|it s|it's|it is|my favou?rite( one)? is|my favou?rite would be)[ ,]+")
	var wish := RegEx.create_from_string("(?i)^(i would|i'd|i d|i)( really| probably| definitely)? (love|like|want|choose|pick|go|travel|build|grow|be|make|say)( to)?( go| see| visit| travel| build| grow| be| make)?( to)?\\s+")
	for n in 3:
		var before := text
		text = filler.sub(text, "")
		text = wish.sub(text, "")
		if text == before:
			break
	if text == "":
		text = TalkBrain.clean(typed)
	return text.substr(0, MAX_FREE_ANSWER).strip_edges()


## Bringing up an answer you gave on an earlier day (once per answer).
static func recall(villager) -> String:
	var mind: VillagerMind = villager.mind
	for q in pool(villager, "questions"):
		var id := String(q["id"])
		var value := answer_of(villager, id)
		if value == "" or _mentioned(villager, "recalled:" + id):
			continue
		var told_today := false
		for e in mind.memory.find("fact", GameManager.PLAYER_ID):
			if String(e["detail"]).begins_with(ANSWER_PREFIX + id + "=") and int(e["day"]) >= WorldClock.day:
				told_today = true
		if told_today:
			continue
		_mark(villager, "recalled:" + id)
		var r: Variant = q.get("recall", "")
		var text := ""
		if r is Dictionary:
			text = String(r.get(value, r.get("other", "")))
		else:
			text = String(r).replace("{answer}", value)
		if text != "":
			return LineBank.capitalize_first(TalkBrain.fill(villager, text))
	return ""


# --- What villagers tell each other about the player ---------------------------------

## Facts that are fine to pass on (not private answers to questions).
const SHAREABLE := ["name", "from", "likes"]
## How much `a` must like `b` to chat about the player.
const SHARE_AFFECTION := 5.0
const HEARD := "fact_heard"


## `teller` passes on one thing the player told them that `listener` doesn't
## know yet. Only facts the teller knows for themselves: told by the player,
## or heard and then said to the player's face (never untested gossip, so
## nothing grows in the retelling). Returns the key shared ("" if nothing).
static func share(teller, listener) -> String:
	if teller == null or listener == null or teller == listener:
		return ""
	if teller.mind.get_affection(String(listener.data.id)) < SHARE_AFFECTION:
		return ""
	for key in SHAREABLE:
		for value in TalkBrain.facts(teller, key):
			if TalkBrain.facts(listener, key).has(value) or _heard(listener, key, String(value)):
				continue
			listener.mind.memory.add(HEARD, GameManager.PLAYER_ID, WorldClock.day, WorldClock.time_of_day,
				"%s=%s|%s" % [key, value, String(teller.data.id)])
			return key
	return ""


static func _heard(villager, key: String, value: String) -> bool:
	for e in villager.mind.memory.find(HEARD, GameManager.PLAYER_ID):
		if String(e["detail"]).begins_with("%s=%s|" % [key, value]):
			return true
	return false


## The first thing they heard about you and haven't mentioned, said with who
## told them; from then on they know it.
static func heard_line(villager) -> String:
	for e in villager.mind.memory.find(HEARD, GameManager.PLAYER_ID):
		var detail := String(e["detail"])
		if _mentioned(villager, "heard_fact:" + detail):
			continue
		var bar := detail.rfind("|")
		var eq := detail.find("=")
		if bar < 0 or eq < 0:
			continue
		var key := detail.substr(0, eq)
		var value := detail.substr(eq + 1, bar - eq - 1)
		var source = GameManager.get_villager(StringName(detail.substr(bar + 1)))
		var who: String = source.data.display_name if source else "Someone"
		_mark(villager, "heard_fact:" + detail)
		if TalkBrain.facts(villager, key).has(value):
			continue
		TalkBrain.remember_fact(villager, key, value)
		match key:
			"name":
				return "[happy]%s told me your name's %s. Nice to meet you properly, %s." % [who, value, value]
			"from":
				return "%s says you're from %s. Is that right? I'd love to hear about it." % [who, value]
			"likes":
				return "[happy]%s mentioned you like %s. I'll keep that in mind." % [who, value]
	return ""


# --- Stories ------------------------------------------------------------------------

## Their next untold story (all lines), or a retelling once all are told.
static func story(villager) -> Array:
	var stories := pool(villager, "stories")
	if stories.is_empty():
		return []
	for i in stories.size():
		if not _mentioned(villager, "story:%d" % i):
			_mark(villager, "story:%d" % i)
			return _story_lines(villager, stories[i])
	var again: Array = ["[laughing]You've heard all my stories! Alright, an old favourite."]
	again.append_array(_story_lines(villager, stories[randi() % stories.size()]))
	return again


static func _story_lines(villager, story_: Array) -> Array:
	var out: Array = []
	for l in story_:
		out.append(TalkBrain.fill(villager, String(l)))
	return out


## What this villager thinks of another (their own words if they have
## them, e.g. founders about each other).
static func opinion(villager, other_id: String) -> String:
	return line(villager, "opinions/" + other_id)


# --- Counting (tests and reports) ---------------------------------------------------

## Every spoken line in a profile (placeholders kept).
static func spoken_lines(value: Variant, key: String = "") -> Array:
	var out: Array = []
	if key in NOT_SPOKEN:
		return out
	if value is String:
		out.append(value)
	elif value is Array:
		for item in value:
			out.append_array(spoken_lines(item))
	elif value is Dictionary:
		for k in value:
			out.append_array(spoken_lines(value[k], String(k)))
	return out


## Words in `lines`, without expression tags or {placeholders}; duplicates
## counted once.
static func word_count(lines: Array) -> int:
	var seen := {}
	var n := 0
	var tags := RegEx.create_from_string("\\[[a-z]+\\]|\\{[a-z_]+\\}")
	for l in lines:
		if seen.has(l):
			continue
		seen[l] = true
		var text := tags.sub(String(l), " ", true)
		n += text.split(" ", false).size()
	return n
