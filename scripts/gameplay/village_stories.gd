class_name VillageStories
extends Node
## Small stories that grow out of what has really happened between the
## villagers and the player (memories, deeds, friendships and rivalries):
##
## - Remembering the day you met: a week after your first talk, a villager
##   who has come to like you remembers that day.
## - Repaying a kindness: someone who likes you, and remembers a particular
##   kind thing you did, thanks you properly with a gift.
## - Making peace: a friend of yours asks you to carry a peace offer to the
##   villager they've fallen out with. How it goes depends on how that
##   villager feels about you. Either way it's remembered and talked about.
##
## Each story happens once per person (or pair), is checked against the
## present state when told (nobody who has left or died, no friends turned
## rivals), and is saved.

const ANNIVERSARY_DAYS := 7
const ANNIVERSARY_AFFECTION := 10.0
const REPAY_AFFECTION := 35.0
const RIVAL_AFFECTION := -10.0
const PEACE_ASKER_AFFECTION := 15.0
## A peace errand is dropped quietly after this many days.
const PEACE_DAYS := 3
const PEACE_MAKES := 35.0

## What a grateful villager gives, by profession.
const REPAY_GIFTS := {
	"farmer": {&"food": 5}, "cook": {&"food": 5}, "fisher": {&"food": 5},
	"builder": {&"wood": 6}, "woodcutter": {&"wood": 6}, "craftsman": {&"wood": 4, &"stone": 2},
	"stonemason": {&"stone": 6}, "herbalist": {&"herbs": 4}, "trader": {&"wood": 3, &"stone": 3}, "weaver": {&"food": 3, &"herbs": 2},
}
static var instance: VillageStories

## Done stories by key ("anniversary:<id>", "repay:<id>", "peace:<a>:<b>").
var done: Dictionary = {}
## The running peace errand ({} if none): {from, to, day, stage}
## stage: "asked" (talk to `to`), then "accepted"/"refused" (tell `from`).
var peace: Dictionary = {}


func _ready() -> void:
	name = "VillageStories"
	instance = self
	WorldClock.day_changed.connect(func(_d): daily())


func _exit_tree() -> void:
	if instance == self:
		instance = null


static func _villager(id: String):
	var villager = GameManager.get_villager(StringName(id))
	if villager == null or not is_instance_valid(villager) or villager.is_visitor() or villager.is_leaving():
		return null
	return villager


## Each morning: drop a stale errand, and maybe start a peace story.
func daily() -> void:
	if not peace.is_empty():
		var stale := WorldClock.day - int(peace["day"]) > PEACE_DAYS
		if stale or _villager(String(peace["from"])) == null or _villager(String(peace["to"])) == null:
			done["peace:%s:%s" % [peace["from"], peace["to"]]] = true
			peace = {}
	if peace.is_empty():
		_maybe_start_peace()


## A friend of the player who has fallen out with someone.
func _maybe_start_peace() -> void:
	var player := GameManager.PLAYER_ID
	for asker in GameManager.villagers:
		if _villager(String(asker.get_villager_id())) == null or asker.mind.get_affection(player) < PEACE_ASKER_AFFECTION:
			continue
		for other in GameManager.villagers:
			if other == asker or _villager(String(other.get_villager_id())) == null:
				continue
			var a := String(asker.get_villager_id())
			var b := String(other.get_villager_id())
			if done.has(_pair_key(a, b)):
				continue
			if asker.person and asker.person.partner == b:
				continue
			if asker.mind.get_affection(b) <= RIVAL_AFFECTION or other.mind.get_affection(a) <= RIVAL_AFFECTION:
				peace = {"from": a, "to": b, "day": WorldClock.day, "stage": "new"}
				return


static func _pair_key(a: String, b: String) -> String:
	return "peace:%s:%s" % ([a, b] if a < b else [b, a])


# --- Dialogue: lines told at the start of a conversation --------------------------

## A story beat for the start of a talk with `villager` ([] if none).
func story_lines(villager) -> Array[String]:
	var id := String(villager.get_villager_id())
	var lines: Array[String] = []
	if villager.mind.is_hostile(GameManager.PLAYER_ID):
		return lines
	# Peace errand: asking, or hearing how it went.
	if not peace.is_empty() and String(peace["from"]) == id:
		var rival = _villager(String(peace["to"]))
		if rival:
			match String(peace["stage"]):
				"new":
					peace["stage"] = "asked"
					lines.append("[sad]Can I ask you something? %s and I haven't spoken properly in days. Some of it's my fault." % rival.data.display_name)
					lines.append("[worried]Would you tell %s I'd like to make peace? They might listen to you." % rival.data.display_name)
					return lines
				"accepted":
					_finish_peace(true)
					lines.append("[happy]%s came and found me. We talked for an hour. Thank you, truly." % rival.data.display_name)
					lines.append("[happy]I won't forget that you did this for us.")
					return lines
				"refused":
					_finish_peace(false)
					lines.append("[sad]%s isn't ready, then. Thank you for trying. That means a lot." % rival.data.display_name)
					return lines
	var anniversary := _anniversary(villager)
	if anniversary != "":
		lines.append(anniversary)
		return lines
	lines.append_array(_repay(villager))
	return lines


## A week after you first talked, if they've come to like you.
func _anniversary(villager) -> String:
	var id := String(villager.get_villager_id())
	var key := "anniversary:" + id
	if done.has(key):
		return ""
	var first: Array = villager.mind.memory.find("conversation", GameManager.PLAYER_ID)
	if first.is_empty():
		return ""
	var met_day := int(first[0]["day"])
	var days := WorldClock.day - met_day
	if days < ANNIVERSARY_DAYS or villager.mind.get_affection(GameManager.PLAYER_ID) < ANNIVERSARY_AFFECTION:
		return ""
	done[key] = true
	var times: int = villager.mind.memory.count("conversation", GameManager.PLAYER_ID)
	villager.mind.adjust_opinion(GameManager.PLAYER_ID, 3.0, 2.0)
	if LineBank.tone_of(villager) == "child":
		return "[laughing]Guess what! You've been my friend for %d whole days! I counted." % days
	return "[happy]Do you know, it's been %d days since you first came to talk to me? %d talks since. I'm glad you stayed." % [days, times]


## Thanks for a particular kindness they still remember, with a gift.
func _repay(villager) -> Array[String]:
	var lines: Array[String] = []
	var id := String(villager.get_villager_id())
	var key := "repay:" + id
	if done.has(key) or villager.mind.get_affection(GameManager.PLAYER_ID) < REPAY_AFFECTION:
		return lines
	var kindness := ""
	for entry in villager.mind.memory.find("deed", GameManager.PLAYER_ID):
		if int(entry["day"]) >= WorldClock.day:
			continue
		var deed := DialogueService.unpack_deed(String(entry["detail"]))
		if float(deed["affection"]) > 0.0:
			kindness = String(deed["text"])
	if kindness == "":
		return lines
	done[key] = true
	var job: String = villager.person.profession if villager.person else ""
	var gift: Dictionary = REPAY_GIFTS.get(job, {&"food": 3, &"wood": 3})
	for resource in gift:
		GameState.add(resource, int(gift[resource]))
	lines.append("[happy]I've been meaning to say: you %s, and I never thanked you properly." % kindness)
	lines.append("[happy]Here, I put this aside for you. (+%s)" % GameState.cost_text(gift))
	return lines


# --- Dialogue: the peace offer, carried to the rival ------------------------------

## Extra answers in a conversation with `villager`.
func choices_for(villager) -> Array:
	if peace.is_empty() or String(peace["stage"]) != "asked" or String(peace["to"]) != String(villager.get_villager_id()):
		return []
	var asker = _villager(String(peace["from"]))
	if asker == null:
		return []
	return [{"text": "%s would like to make peace with you." % asker.data.display_name, "action": "story_peace"}]


## The rival hears the offer. Returns what they say.
func carry_peace(villager) -> Array[String]:
	var lines: Array[String] = []
	var asker = _villager(String(peace.get("from", "")))
	if asker == null or String(peace.get("to", "")) != String(villager.get_villager_id()):
		return lines
	var a := String(asker.get_villager_id())
	var b := String(villager.get_villager_id())
	var trusts_you: bool = villager.mind.get_affection(GameManager.PLAYER_ID) >= 0.0
	if trusts_you:
		peace["stage"] = "accepted"
		villager.mind.adjust_opinion(a, PEACE_MAKES, 10.0)
		asker.mind.adjust_opinion(b, PEACE_MAKES, 10.0)
		villager.mind.adjust_opinion(GameManager.PLAYER_ID, 5.0, 5.0)
		villager.mind.memory.add("deed", GameManager.PLAYER_ID, WorldClock.day, WorldClock.time_of_day,
			DialogueService.pack_deed("helped me make peace with %s" % asker.data.display_name, 5.0))
		lines.append("[surprised]%s said that? ...I've missed talking to them, if I'm honest." % asker.data.display_name)
		lines.append("[happy]I'll go and find them. Thank you for carrying the message.")
	else:
		peace["stage"] = "refused"
		lines.append("[angry]Did %s send you? Tell them I'm not ready. And I'm not sure I trust the messenger either." % asker.data.display_name)
	return lines


func _finish_peace(made_up: bool) -> void:
	var a := String(peace["from"])
	var b := String(peace["to"])
	done[_pair_key(a, b)] = true
	var asker = _villager(a)
	if made_up:
		if asker:
			asker.mind.adjust_opinion(GameManager.PLAYER_ID, 8.0, 6.0)
			asker.mind.memory.add("deed", GameManager.PLAYER_ID, WorldClock.day, WorldClock.time_of_day,
				DialogueService.pack_deed("helped me make peace with %s" % GameManager.get_villager(StringName(b)).data.display_name, 8.0))
		# The whole village hears of it (and talks about it for a few days).
		if Population.get_person(a) and Population.get_person(b):
			Population.log_event("reconciled", "%s and %s made peace" % [a, b], [a, b])
	elif asker:
		asker.mind.adjust_opinion(GameManager.PLAYER_ID, 3.0, 3.0)
	peace = {}


# --- Save -------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {"done": done.duplicate(), "peace": peace.duplicate()}


func from_dict(data: Dictionary) -> void:
	if data.is_empty():
		return
	done = (data.get("done", {}) as Dictionary).duplicate()
	peace = (data.get("peace", {}) as Dictionary).duplicate()
