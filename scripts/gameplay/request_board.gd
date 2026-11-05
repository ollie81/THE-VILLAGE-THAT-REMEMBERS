class_name RequestBoard
extends Node
## Each morning two to four villagers ask the player for something that comes
## out of their own life: an herbalist short of herbs for someone's fever, a
## man who wants to apologise but can't face her, a mother worried about her
## son. Doing it is remembered and warmly thanked; forgetting is remembered too,
## gently. Requests last until the end of the day.
##
## Kinds:
##   fetch    bring the requester some wood, stone, food or herbs
##   message  pass a message from the requester to someone else
##   check    see how someone the requester is worried about is doing

signal changed

static var instance: RequestBoard

## Today's requests: { id, kind, from, to, resource, amount, reason, text,
##   line_to, reply, done, day }
var requests: Array = []
var day: int = -1
## All requests ever completed (shown on the requests card).
var completed_total: int = 0
var rng := RandomNumberGenerator.new()
var _next_id: int = 1


func _ready() -> void:
	name = "RequestBoard"
	instance = self
	rng.randomize()
	WorldClock.day_changed.connect(func(_d): new_day())


func _exit_tree() -> void:
	if instance == self:
		instance = null


## Called once the villagers exist (after loading).
func start() -> void:
	if day != WorldClock.day:
		new_day()


func open_requests() -> Array:
	return requests.filter(func(r): return not bool(r["done"]))


## Ends yesterday's requests (remembering any left undone) and asks new ones.
func new_day() -> void:
	for request: Dictionary in requests:
		if bool(request["done"]) or int(request["day"]) == WorldClock.day:
			continue
		var asker = GameManager.get_villager(StringName(String(request["from"])))
		if asker:
			asker.mind.adjust_opinion(GameManager.PLAYER_ID, -2.0, -2.0)
			asker.mind.memory.add("forgot", GameManager.PLAYER_ID, WorldClock.day, WorldClock.time_of_day, String(request["reason"]))
	requests.clear()
	day = WorldClock.day
	var candidates: Array = GameManager.villagers.filter(func(v):
		return v.visible or v.state == Villager.State.INSIDE) \
		.filter(func(v): return not v.is_visitor() and not v.is_leaving() and (v.person == null or v.person.age() >= 6))
	candidates.shuffle()
	var wanted := clampi(2 + GameManager.villagers.size() / 10, 2, 4)
	var used := {}
	for asker in candidates:
		if requests.size() >= wanted:
			break
		if used.has(asker):
			continue
		if asker.mind.is_hostile(GameManager.PLAYER_ID):
			continue
		var request := _make_request(asker, candidates, used)
		if not request.is_empty():
			requests.append(request)
			used[asker] = true
	changed.emit()


func _make_request(asker, everyone: Array, used: Dictionary) -> Dictionary:
	var kinds := ["fetch", "fetch", "message", "check"]
	kinds.shuffle()
	for kind in kinds:
		var request := {}
		match kind:
			"fetch":
				request = _fetch(asker)
			"message":
				request = _message(asker, everyone, used)
			"check":
				request = _check(asker, everyone, used)
		if not request.is_empty():
			request["id"] = _next_id
			_next_id += 1
			request["kind"] = kind
			request["from"] = String(asker.get_villager_id())
			request["done"] = false
			request["day"] = WorldClock.day
			return request
	return {}


# --- Request kinds -----------------------------------------------------------------

const FETCH := {
	"herbalist": [[&"herbs", 3, "herbs for a fever tea", "Tomas has a fever again. Could you bring me 3 herbs? I'm all out."]],
	"farmer": [[&"wood", 4, "wood for a new fence", "The goats got through the fence again! Could you bring me 4 wood?"]],
	"builder": [[&"stone", 4, "stone for a doorstep", "I've a doorstep to set and no stone left. Could you bring me 4?"],
		[&"wood", 5, "wood for scaffolding", "I need 5 good planks for scaffolding. Would you fetch some?"]],
	"craftsman": [[&"wood", 3, "wood for a cradle", "I'm carving a cradle for the new baby. I need 3 more pieces of wood."]],
	"trader": [[&"food", 3, "food for the trade caravan", "A trader's coming through and I promised supper. Could you spare 3 food?"]],
	"cook": [[&"herbs", 2, "herbs for the stew", "The stew's bland as a boot. Bring me 2 herbs and I'll save you a bowl."]],
	"woodcutter": [[&"food", 3, "food for a long day", "I'll be in the woods till dark. Could you bring me 3 food?"]],
	"stonemason": [[&"food", 2, "lunch at the quarry", "I forgot my lunch again. 2 food would save my life."]],
	"fisher": [[&"wood", 3, "wood for a new rod", "My rod snapped on a monster trout. 3 wood and I'll make a new one."]],
	"weaver": [[&"herbs", 3, "herbs for dye", "I need 3 herbs to dye wool the colour of the hills."]],
}
const FETCH_ANY := [
	[&"food", 2, "a little food", "It's been a lean week. Could you spare 2 food?"],
	[&"herbs", 2, "herbs for a sore throat", "My throat's raw. Would you bring me 2 herbs for a tea?"],
	[&"wood", 3, "firewood", "The nights are getting cold. Could you bring me 3 wood for the fire?"],
]


func _fetch(asker) -> Dictionary:
	var job: String = asker.person.profession if asker.person else Chatter._founder_trade(String(asker.get_villager_id()))
	var options: Array = (FETCH.get(job, []) as Array) + FETCH_ANY
	if asker.person and asker.person.age() < 13:
		options = [[&"food", 1, "a snack", "I'm sooo hungry. Could you bring me 1 food? Please?"]]
	var pick: Array = options[rng.randi_range(0, options.size() - 1)]
	return {"resource": String(pick[0]), "amount": int(pick[1]), "reason": String(pick[2]), "ask": String(pick[3]),
		"text": "Bring %s %d %s (%s)." % [asker.data.display_name, int(pick[1]), GameState.RESOURCE_NAMES[pick[0]].to_lower(), pick[2]]}


func _message(asker, everyone: Array, used: Dictionary) -> Dictionary:
	var target = _pick_other(asker, everyone, used)
	if target == null:
		return {}
	var a := asker.data.display_name as String
	var b := target.data.display_name as String
	var opinion: float = asker.mind.get_affection(String(target.get_villager_id()))
	# [what, ask, what you tell them, their reply]. {a} asker, {b} target,
	# {them}/{they} the target.
	var templates: Array
	if opinion < 0.0:
		templates = [["an apology", "[sad]I said something cruel to {b} and I can't face {them}. Would you tell {them} I'm sorry?",
			"{a} asked me to tell you: they're sorry for what they said.", "[sad]...Did they really? Tell {a} I forgive them."]]
	elif opinion >= SocialLife.FRIEND_AFFECTION:
		templates = [["a thank-you", "[happy]{b} helped me more than {they} knows. Would you thank {them} for me?",
			"{a} wanted me to thank you. You helped them more than you know.", "[happy]Oh! Tell {a} it was nothing. ...It means a lot, though."],
			["an invitation", "[happy]Would you ask {b} to sit with me by the fire tonight? I'm too shy to ask {them} myself.",
			"{a} hopes you'll sit with them by the fire tonight.", "[laughing]Tell {a} I'll be there!"]]
	else:
		templates = [["a friendly word", "[happy]I'd like to get to know {b} better. Would you put in a good word for me?",
			"{a} speaks well of you. They'd like to get to know you.", "[happy]Really? I'll say hello to {a} then."]]
	var t: Array = templates[rng.randi_range(0, templates.size() - 1)]
	var female := _is_female(target)
	var names := {"a": asker.data.display_name, "b": target.data.display_name, "them": "her" if female else "him", "they": "she" if female else "he"}
	return {"to": String(target.get_villager_id()), "reason": "%s for %s" % [t[0], names["b"]], "ask": String(t[1]).format(names),
		"line_to": String(t[2]).format(names), "reply": String(t[3]).format(names),
		"text": "Take %s to %s from %s." % [t[0], names["b"], names["a"]]}


func _check(asker, everyone: Array, used: Dictionary) -> Dictionary:
	var target = null
	var reason := ""
	if asker.person:
		for child_id in asker.person.children:
			var kid = GameManager.get_villager(StringName(String(child_id)))
			if kid and not used.has(kid):
				target = kid
				reason = "is out late again"
		var partner = GameManager.get_villager(StringName(asker.person.partner)) if asker.person.partner != "" else null
		if target == null and partner and not used.has(partner):
			target = partner
			reason = "has been quiet lately"
	if target == null:
		target = _pick_other(asker, everyone, used)
		reason = "hasn't seemed themselves"
	if target == null:
		return {}
	var b := target.data.display_name as String
	return {"to": String(target.get_villager_id()), "reason": "checking on %s" % b,
		"ask": "[worried]I'm worried about %s. %s %s. Would you see how %s's doing?" % [b, b, reason, "she" if _is_female(target) else "he"],
		"line_to": "%s was worried about you. Are you alright?" % asker.data.display_name,
		"reply": "[happy]Oh, that's sweet of %s. I'm fine, really. Tell them not to fuss." % asker.data.display_name,
		"text": "See how %s is doing (for %s)." % [b, asker.data.display_name]}


func _pick_other(asker, everyone: Array, used: Dictionary):
	var others: Array = everyone.filter(func(v): return v != asker and not used.has(v))
	if others.is_empty():
		return null
	return others[rng.randi_range(0, others.size() - 1)]


static func _is_female(villager) -> bool:
	if villager.person:
		return villager.person.sex == "female"
	return not (String(villager.get_villager_id()) in ["elias", "tomas"])


# --- Talking about requests ----------------------------------------------------------

## The request this villager made today and hasn't been done yet, if any.
func asked_by(villager) -> Dictionary:
	for request: Dictionary in open_requests():
		if String(request["from"]) == String(villager.get_villager_id()):
			return request
	return {}


## Things to say about requests when talking to `villager`.
func choices_for(villager) -> Array:
	var id := String(villager.get_villager_id())
	var out: Array = []
	for request: Dictionary in open_requests():
		match String(request["kind"]):
			"fetch":
				if String(request["from"]) == id:
					var resource := StringName(String(request["resource"]))
					if GameState.count(resource) >= int(request["amount"]):
						out.append({"text": "Here are the %d %s you asked for." % [int(request["amount"]),
							GameState.RESOURCE_NAMES[resource].to_lower()], "action": "request", "request": int(request["id"])})
			"message", "check":
				if String(request["to"]) == id:
					out.append({"text": String(request["line_to"]), "action": "request", "request": int(request["id"])})
	return out


## Does a request. Returns what's said.
func fulfil(request_id: int, villager) -> Array[String]:
	var lines: Array[String] = []
	for request: Dictionary in requests:
		if int(request["id"]) != request_id or bool(request["done"]):
			continue
		var asker = GameManager.get_villager(StringName(String(request["from"])))
		match String(request["kind"]):
			"fetch":
				var resource := StringName(String(request["resource"]))
				GameState.add(resource, -int(request["amount"]))
				lines.append(LineBank._fresh(villager, ["[laughing]You remembered! Thank you!", "[happy]Oh, bless you. Exactly what I needed.",
					"[happy]You're a lifesaver, truly."]))
				lines.append(_thank_you_gift(villager))
			"message", "check":
				lines.append(String(request["reply"]))
				if asker:
					var target_id := String(villager.get_villager_id())
					asker.mind.adjust_opinion(target_id, 10.0, 5.0)
					villager.mind.adjust_opinion(String(asker.get_villager_id()), 10.0, 5.0)
					if villager.person:
						villager.person.happiness = minf(villager.person.happiness + 8.0, 100.0)
					asker.set_meta("pending_line", "[happy]%s told me what they said. Thank you for that." % villager.data.display_name)
		request["done"] = true
		completed_total += 1
		if asker:
			asker.mind.adjust_opinion(GameManager.PLAYER_ID, 10.0, 7.0)
			asker.mind.memory.add("deed", GameManager.PLAYER_ID, WorldClock.day, WorldClock.time_of_day,
				DialogueService.pack_deed("helped me with %s" % request["reason"], 10.0))
		GameState.increment(&"good_deeds")
		GameState.increment(&"requests_done")
		if open_requests().is_empty():
			GameManager.notify("You helped everyone who asked today. The village won't forget it.")
			for v in GameManager.villagers:
				v.mind.adjust_opinion(GameManager.PLAYER_ID, 1.5, 1.0)
		changed.emit()
		break
	return lines


## Thanks in kind, sometimes.
func _thank_you_gift(villager) -> String:
	var gifts := [[&"food", 3, "Take these eggs, I insist."], [&"herbs", 2, "Here, some of my best herbs."],
		[&"wood", 3, "I had some spare wood. It's yours."], [&"stone", 2, "Take this stone, I won't need it."]]
	if rng.randf() < 0.5:
		return "[happy]Come back any time."
	var gift: Array = gifts[rng.randi_range(0, gifts.size() - 1)]
	GameState.add(gift[0], gift[1])
	FloatingText.spawn(villager.get_parent(), villager.global_position + Vector3(0, 2.2, 0), "+%d %s" % [gift[1], GameState.RESOURCE_NAMES[gift[0]]])
	return "[happy]%s" % gift[2]


## What the asker says about their request when you talk to them.
func reminder_for(villager) -> String:
	var request := asked_by(villager)
	if request.is_empty():
		return ""
	var said: Array = villager.get_meta("asked_today", [])
	if not said.has(int(request["id"])):
		said.append(int(request["id"]))
		villager.set_meta("asked_today", said)
		return String(request["ask"])
	if String(request["kind"]) == "fetch":
		return "[happy]Any luck finding the %s?" % GameState.RESOURCE_NAMES[StringName(String(request["resource"]))].to_lower()
	return "[happy]Did you get a chance to talk to %s?" % GameManager.get_villager(StringName(String(request["to"]))).data.display_name


## Anything left undone yesterday, brought up once.
func forgotten_line(villager) -> String:
	var forgot: Array = villager.mind.memory.find("forgot", GameManager.PLAYER_ID)
	for entry: Dictionary in forgot:
		if villager.mind.memory.has_detail("mentioned", GameManager.PLAYER_ID, "forgot:" + String(entry["detail"])):
			continue
		villager.mind.memory.add("mentioned", GameManager.PLAYER_ID, WorldClock.day, WorldClock.time_of_day, "forgot:" + String(entry["detail"]))
		return LineBank._fresh(villager, ["[sad]You never came by with %s yesterday. It's alright. I managed." % entry["detail"],
			"[worried]I waited for you yesterday, about %s. Never mind." % entry["detail"]])
	return ""


# --- Persistence ----------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {"requests": requests.duplicate(true), "day": day, "completed": completed_total, "next_id": _next_id}


func from_dict(data: Dictionary) -> void:
	var saved: Variant = data.get("requests", [])
	requests = (saved as Array).duplicate(true) if saved is Array else []
	day = int(data.get("day", -1))
	completed_total = int(data.get("completed", 0))
	_next_id = int(data.get("next_id", 1))
