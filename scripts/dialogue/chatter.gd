class_name Chatter
extends RefCounted
## What villagers talk about once you know them: the village's news, other
## villagers, their own life, the moment, and you. Every topic is built from
## the live state of the village, phrased in their own tone, and each
## villager remembers what they've already told you so they move on.


## One or two things to say right now.
static func lines_for(villager, count: int = 1) -> Array[String]:
	var topics := _topics(villager)
	var said: Array = villager.mind.memory.find("told", GameManager.PLAYER_ID).map(func(e): return String(e["detail"]))
	var fresh: Array = topics.filter(func(t): return not said.has(String(t["key"])))
	var out: Array[String] = []
	# Village news they haven't told you yet comes first, newest first:
	# that's what people want to share ("Have you seen the new baby?").
	var news: Array = fresh.filter(func(t): return String(t["key"]).begins_with("event:"))
	news.sort_custom(func(a, b): return int(String(a["key"]).get_slice(":", 1)) > int(String(b["key"]).get_slice(":", 1)))
	var rest: Array = fresh.filter(func(t): return not String(t["key"]).begins_with("event:"))
	rest.sort_custom(func(a, b): return float(a["weight"]) > float(b["weight"]))
	# Then the most interesting few of the rest, in a different order each time.
	var shortlist: Array = rest.slice(0, 5)
	shortlist.shuffle()
	for topic: Dictionary in news + shortlist:
		if out.size() >= count:
			break
		out.append(String(topic["line"]))
		villager.mind.memory.add("told", GameManager.PLAYER_ID, WorldClock.day, WorldClock.time_of_day, String(topic["key"]))
	if out.is_empty():
		out.append(_idle_line(villager))
	return out


## True when they've told you everything they have to say for now.
static func has_news(villager) -> bool:
	var said: Array = villager.mind.memory.find("told", GameManager.PLAYER_ID).map(func(e): return String(e["detail"]))
	return _topics(villager).any(func(t): return not said.has(String(t["key"])))


static func _topic(key: String, line: String, weight: float) -> Dictionary:
	return {"key": key, "line": line, "weight": weight}


static func _topics(villager) -> Array:
	var topics: Array = []
	var person: Person = villager.person
	var tone := LineBank.tone_of(villager)
	var child := tone == "child"
	var cool := tone == "cool"
	var grumpy := tone == "grumpy"
	var day := WorldClock.day

	# --- Village news (the last few days) ---
	for event: Dictionary in Population.events.slice(maxi(Population.events.size() - 30, 0)):
		if day - int(event["day"]) > 3:
			continue
		var ids: Array = event.get("ids", [])
		if person and ids.has(person.id):
			continue
		var subject := Population.get_person(String(ids[0])) if not ids.is_empty() else null
		if subject == null:
			continue
		var key := "event:%d:%s:%s" % [int(event["day"]), String(event["type"]), subject.id]
		var who := subject.first_name
		var line := ""
		match String(event["type"]):
			"birth":
				line = "[happy]Have you seen the new baby? Little %s. %s" % [who, "So tiny!" if not grumpy else "Loud, mind you."]
			"arrival":
				line = "[happy]%s the %s moved in. %s" % [who, Professions.label(subject.profession).to_lower(),
					"I think we'll be friends." if not grumpy and not cool else "We'll see how long that lasts."]
			"marriage":
				var other := Population.get_person(String(ids[1])) if ids.size() > 1 else null
				line = "[laughing]Did you hear? %s and %s got married! %s" % [who, other.first_name if other else "someone",
					"I cried, I'm not ashamed." if not grumpy else "Took them long enough."]
			"partnership":
				var other := Population.get_person(String(ids[1])) if ids.size() > 1 else null
				line = "[laughing]Between you and me, %s and %s are sweet on each other." % [who, other.first_name if other else "someone"]
			"death":
				line = "[sad]I keep thinking about %s. The village feels quieter." % who
			"departure":
				line = "[sad]%s left us. Packed up and went down the road." % who
			"coming_of_age":
				line = "[happy]Little %s is all grown up now. Where does the time go?" % who
			"apprentice":
				line = "[happy]%s has started learning a trade. Bright one, that." % who
			"expecting":
				line = "[laughing]%s is expecting! Don't tell anyone I told you." % who
			"adoption":
				line = "[happy]%s has a new family now. That's a happy ending." % who
			"reconciled":
				var other := Population.get_person(String(ids[1])) if ids.size() > 1 else null
				line = "[happy]%s and %s are talking again! I heard you had a hand in that." % [who, other.first_name if other else "someone"]
		if line != "":
			topics.append(_topic(key, line, 3.0))

	# --- Festivals: the one on now, or the one just gone ---
	if Festival.instance:
		var festival := Festival.instance.current()
		if not festival.is_empty():
			var pool: Array = festival["lines"]
			topics.append(_topic("festival_now:%d" % Festival.instance.week, String(pool[(day + hash(String(villager.get_villager_id()))) % pool.size()]), 2.5))
		var memory := Festival.instance.recent_memory()
		if not memory.is_empty():
			var line := String(memory["line"])
			if bool(memory["all_done"]):
				line += " And you made it special."
			topics.append(_topic("festival_past:%d" % int(memory["week"]), line, 2.0))

	# --- Something built recently ---
	for record: Dictionary in GameState.structures:
		if bool(record.get("complete", false)):
			var info := StructureCatalog.info(StringName(String(record["type"])))
			topics.append(_topic("built:%d" % int(record["uid"]),
				"[happy]That new %s is a fine thing. %s" % [String(info["name"]).to_lower(),
					"Your work, I hear?" if not cool else "Someone's busy."], 1.2))

	# --- Other villagers ---
	var fondest := ""
	var fondest_value := 20.0
	var least := ""
	var least_value := -10.0
	for other_id in villager.mind.relationships:
		if String(other_id) == GameManager.PLAYER_ID:
			continue
		var value: float = villager.mind.get_affection(String(other_id))
		if value > fondest_value:
			fondest_value = value
			fondest = String(other_id)
		if value < least_value:
			least_value = value
			least = String(other_id)
	if fondest != "":
		var friend = GameManager.get_villager(StringName(fondest))
		if friend:
			topics.append(_topic("fond:" + fondest, "[happy]%s is a good friend to me. %s" % [friend.data.display_name,
				["We talk for hours by the fire.", "Always there when I need a hand.", "Makes me laugh every single day."][hash(fondest) % 3]], 1.6))
	if least != "":
		var rival = GameManager.get_villager(StringName(least))
		if rival:
			topics.append(_topic("rival:" + least, "[angry]Don't get me started on %s." % rival.data.display_name, 1.4))
	# A word about a few of the neighbours, and what they're up to.
	var others: Array = GameManager.villagers.filter(func(v): return v != villager and v.visible)
	for k in mini(3, others.size()):
		var other = others[(day + k * 7 + hash(String(villager.get_villager_id()))) % others.size()]
		var activity: String = other.get_activity_description()
		activity = activity.substr(0, 1).to_lower() + activity.substr(1)
		if activity == "":
			continue
		var opinion: float = villager.mind.get_affection(String(other.get_villager_id()))
		var remark: String = ["Busy as ever.", "Wonder what they're up to.", "Good sort, that one.", "Rather them than me."][hash(String(other.get_villager_id()) + str(day)) % 4]
		if opinion >= SocialLife.FRIEND_AFFECTION:
			remark = "I should bring them some tea."
		topics.append(_topic("seen:%s:%d" % [other.get_villager_id(), day],
			"[happy]I saw %s earlier, %s. %s" % [other.data.display_name, activity, remark], 0.8))

	# --- Their own life ---
	if person:
		if not person.ambition.is_empty() and not bool(person.ambition.get("done", false)) and not child:
			var progress := float(person.ambition.get("progress", 0.0))
			topics.append(_topic("ambition:%d" % int(progress * 4.0),
				"[happy]I still want to %s. %s" % [String(person.ambition["text"]),
					"I'm getting there!" if progress > 0.5 else "One day."], 1.5))
		if person.home == Population.CAMP_ID:
			topics.append(_topic("camp:%d" % day, "[worried]The tent's cold at night. I'd give anything for a proper bed.", 2.0))
		if person.happiness < 35.0 and not person.founder:
			topics.append(_topic("unhappy:%d" % day, "[sad]I don't know. Some days I wonder if I belong here.", 2.2))
		elif person.happiness > 75.0:
			topics.append(_topic("happy:%d" % (day / 3), "[happy]I'm happy here. Truly. I didn't expect that.", 1.0))
		var partner := Population.get_person(person.partner)
		if partner:
			topics.append(_topic("partner:%d" % (day / 2), "[happy]%s and I are %s." % [partner.first_name,
				["thinking of planting a garden together", "arguing about whose turn it is to cook", "very happy, thank you for asking"][day % 3]], 1.2))
		for child_id in person.children:
			var kid := Population.get_person(String(child_id))
			if kid and kid.is_resident() and kid.age() < 18:
				topics.append(_topic("kid:%s:%d" % [kid.id, kid.age()], "[laughing]%s %s" % [kid.first_name,
					["asked me where the river goes today. I didn't know!", "is growing so fast.", "wants to be a %s when they grow up." % Professions.label(person.profession).to_lower()][hash(kid.id + str(day)) % 3]], 1.4))
	# --- Their trade ---
	var job: String = person.profession if person else _founder_trade(String(villager.get_villager_id()))
	var trade_lines: Array = TRADE_TALK.get(job, [])
	for i in trade_lines.size():
		topics.append(_topic("trade:%d:%d" % [i, day / 4], String(trade_lines[i]), 0.85))
	# --- Musings, by temperament ---
	var musings: Array = MUSINGS.get(tone, MUSINGS["plain"])
	for i in musings.size():
		topics.append(_topic("muse:%s:%d" % [tone, i], String(musings[i]), 0.6))
	# --- The village growing ---
	var population := Population.count()
	if population >= 8:
		topics.append(_topic("growth:%d" % (population / 5), "[happy]%d of us now! When I came there were five." % population
			if person == null or person.founder else "[happy]The village is growing. %d people! It feels alive." % population, 1.3))

	# --- How the village looks ---
	var beauty := GameState.beauty()
	if beauty >= 4.0:
		topics.append(_topic("beauty:%d" % int(beauty / 4.0), ["[happy]Have you noticed how lovely the village is getting? The flowers, the lanterns...",
			"[happy]I walked past the new things you built this morning. It feels like a real home now.",
			"[laughing]Visitors will think we're a proper town!"][int(beauty) % 3], 1.5))

	# --- The moment ---
	var hour := WorldClock.time_of_day
	if hour >= 20.0 or hour < 5.0:
		topics.append(_topic("night:%d" % day, "[worried]It's late. Shouldn't you be asleep?" if not child else "[laughing]I'm not tired! ...Maybe a bit.", 0.9))
	elif hour < 8.0:
		topics.append(_topic("dawn:%d" % day, "[happy]I love the village before everyone's up. So quiet.", 0.7))
	if villager.current_activity:
		var comment := String(villager.data.activity_comments.get(String(villager.current_activity.kind), ""))
		if comment != "":
			topics.append(_topic("activity:%s:%d" % [villager.current_activity.kind, day], comment, 1.0))

	# --- The player ---
	if GameState.get_flag(&"has_tools"):
		topics.append(_topic("tools", "[happy]Nice tools you made. Tomas says you've got the hands for it.", 0.6))
	var bad := int(GameState.get_flag(&"bad_deeds", 0))
	if bad >= 3:
		topics.append(_topic("reputation_bad:%d" % (bad / 3), "[worried]People are saying things about you. Unkind things. Are they true?", 2.5))
	var good := int(GameState.get_flag(&"good_deeds", 0))
	if good >= 3:
		topics.append(_topic("reputation_good:%d" % (good / 3), "[happy]Everyone says you've been generous lately. It's noticed.", 1.8))

	# Their own written lines, now and then.
	for i in villager.data.returning_lines.size():
		topics.append(_topic("own:%d" % i, String(villager.data.returning_lines[i]), 0.9))
	return topics


static func _founder_trade(id: String) -> String:
	return {"mara": "builder", "elias": "farmer", "nia": "herbalist", "tomas": "craftsman", "sera": "trader"}.get(id, "")


const TRADE_TALK := {
	"farmer": ["[happy]The barley's coming up nicely. Rain would help.", "[worried]Crows at the seed again. I need a better scarecrow.",
		"[happy]There's nothing like the smell of turned soil in the morning."],
	"builder": ["[laughing]Measure twice, cut once. Then measure again, because Tomas is watching.", "[happy]I've an idea for a bigger roof. Maybe a hall?",
		"[worried]That north wall wants patching before the winter."],
	"herbalist": ["[happy]Chamomile for sleep, mint for the stomach, and patience for everything else.", "[surprised]I found wild garlic by the river!",
		"[worried]The feverfew isn't doing well this year."],
	"craftsman": ["[happy]A good tool outlives the hand that made it.", "[worried]My chisels need sharpening. Everything needs sharpening.",
		"[laughing]The youngsters think I'm slow. I think they're sloppy."],
	"trader": ["[laughing]I traded a goat for a barrel of nails once. Best day of my life.", "[happy]If we had a road to the coast, think of the salt we could trade!",
		"[worried]Prices beyond the hills are going up, I hear."],
	"woodcutter": ["[happy]The oaks by the woodlot are old friends. I only take what they can spare.", "[laughing]My axe and I have an understanding."],
	"stonemason": ["[happy]Stone remembers everything. Every chisel mark.", "[worried]The quarry face is getting crumbly on the east side."],
	"fisher": ["[happy]The trout were jumping this morning!", "[laughing]The big one got away again. It's personal now."],
	"cook": ["[happy]A pinch of thyme makes anything taste like home.", "[laughing]I burned the bread. Don't tell anyone."],
	"weaver": ["[happy]I'm dyeing wool with walnut husks. It comes out the colour of autumn.", "[worried]My loom creaks. Tomas says it's character."],
}

const MUSINGS := {
	"warm": ["[happy]You know, I'm glad you came here.", "[happy]Days go quicker with a friend about.", "[laughing]Remember when you first arrived? You looked so lost!"],
	"cheerful": ["[laughing]Have you ever tried to count the stars? I got to forty and fell asleep.", "[laughing]We should have a festival! With pies!",
		"[happy]I had the strangest dream about a talking goose."],
	"shy": ["[happy]I like the sound of the river at night.", "[happy]...Sometimes I just sit and watch the clouds."],
	"grumpy": ["Everyone's too loud today.", "Back in my day we didn't have benches. We sat on the ground and liked it.",
		"[angry]Someone keeps leaving the storehouse door open."],
	"cool": ["[worried]I'm keeping an eye on you.", "Hm. You're still here, then."],
	"child": ["[laughing]I found a frog! I named him Sir Hops.", "[surprised]Do you think there are dragons past the forest?",
		"[laughing]I can climb the big oak higher than anyone!"],
	"plain": ["[happy]The weather's been kind to us lately.", "[happy]It's the little things, isn't it? A warm meal, a good chat.",
		"[worried]I wonder what the winter will bring."],
}


static func _idle_line(villager) -> String:
	return LineBank._fresh(villager, ["[laughing]You've heard all my news today! Come back tomorrow.",
		"[happy]That's everything, really. It's been a quiet day.", "[happy]Nothing new since we last spoke, I'm afraid.",
		"[laughing]I'm all talked out! Ask me again tomorrow."])
