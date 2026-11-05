class_name Deeds
extends RefCounted
## Good and bad things the player can do to a villager in conversation:
## give a gift, pay a compliment, tell a joke, play a prank, insult them or
## steal from them. Each changes how they feel, is remembered (and comes up
## again later), spreads as gossip, and is seen by anyone standing nearby.

const WITNESS_DISTANCE := 8.0
## What each trade likes as a gift (best first).
const FAVOURITE_GIFTS := {
	"farmer": [&"herbs", &"food"], "builder": [&"wood", &"stone"], "herbalist": [&"herbs", &"food"],
	"craftsman": [&"wood", &"stone"], "trader": [&"food", &"herbs"], "woodcutter": [&"food", &"wood"],
	"stonemason": [&"food", &"stone"], "fisher": [&"food", &"herbs"], "cook": [&"herbs", &"food"],
	"weaver": [&"herbs", &"food"],
}
const GIFT_NAMES := {&"wood": "some good wood", &"stone": "some stone", &"food": "something to eat", &"herbs": "a bundle of herbs"}


## Kind things to do (offered from "Be kind..." in conversation).
static func kind_menu(villager) -> Array:
	var items: Array = []
	var gift := best_gift(villager)
	if gift != &"":
		items.append({"text": "Give them %s." % GIFT_NAMES[gift], "action": "deed", "deed": "gift", "thing": String(gift)})
	items.append({"text": "Pay them a compliment.", "action": "deed", "deed": "compliment"})
	items.append({"text": "Tell a joke: \"%s\"" % JOKES[randi() % JOKES.size()], "action": "deed", "deed": "joke"})
	items.append({"text": "Never mind.", "action": "back"})
	return items


## Unkind things to do (offered from "Be unkind...").
static func unkind_menu(villager) -> Array:
	var items: Array = [
		{"text": "Play a prank on them.", "action": "deed", "deed": "prank"},
		{"text": "Insult them.", "action": "deed", "deed": "insult"},
	]
	if villager.person == null or villager.person.age() >= 13:
		items.append({"text": "Quietly take something from their pocket.", "action": "deed", "deed": "steal"})
	items.append({"text": "Never mind.", "action": "back"})
	return items


## The gift they'd like most from what the player has (or none).
static func best_gift(villager) -> StringName:
	var job: String = villager.person.profession if villager.person else ""
	var order: Array = (FAVOURITE_GIFTS.get(job, []) as Array) + [&"food", &"herbs", &"wood", &"stone"]
	for resource in order:
		if GameState.count(resource) >= 1:
			return resource
	return &""


## Does a deed. Returns the villager's reply lines.
static func perform(villager, deed: String, thing: String = "") -> Array[String]:
	var mind: VillagerMind = villager.mind
	var player := GameManager.PLAYER_ID
	var p: Dictionary = villager.data.personality
	var lines: Array[String] = []
	var affection := 0.0
	var trust := 0.0
	var remembered := ""
	var bad := false
	match deed:
		"gift":
			var resource := StringName(thing)
			GameState.add(resource, -1)
			var job: String = villager.person.profession if villager.person else ""
			var favourites: Array = FAVOURITE_GIFTS.get(job, [&"food"])
			var loved := favourites.has(resource)
			affection = 9.0 if loved else 4.0
			trust = 3.0
			remembered = "gave me %s" % GIFT_NAMES[resource]
			lines.append(LineBank.pick(villager, "gift_love" if loved else "gift_ok", {"thing": GIFT_NAMES[resource]}))
			GameState.increment(&"gifts")
		"compliment":
			var repeats := mind.memory.count("compliment", player)
			mind.memory.add("compliment", player, WorldClock.day, WorldClock.time_of_day)
			affection = maxf(4.0 - repeats * 1.5, 0.0)
			lines.append(LineBank.pick(villager, "compliment") if affection > 0.0 else "[worried]You keep saying that. Do you mean it?")
		"joke":
			var humour := float(p.get("openness", 0.5)) * 0.5 + float(p.get("extraversion", 0.5)) * 0.5
			var lands := randf() < 0.35 + humour * 0.5
			affection = 3.0 if lands else -1.0
			lines.append(LineBank.pick(villager, "joke_good" if lands else "joke_bad"))
		"prank":
			var playful := float(p.get("extraversion", 0.5)) * 0.6 + float(p.get("agreeableness", 0.5)) * 0.4
			affection = 2.0 if playful > 0.6 else -6.0
			trust = -2.0
			remembered = "played a prank on me"
			bad = affection < 0.0
			lines.append(LineBank.pick(villager, "prank"))
		"insult":
			affection = -15.0
			trust = -8.0
			remembered = "insulted me"
			bad = true
			lines.append(LineBank.pick(villager, "insult"))
		"steal":
			var caught := randf() < 0.45 + float(p.get("conscientiousness", 0.5)) * 0.3
			bad = true
			var loot := [&"food", &"wood", &"stone", &"herbs"][randi() % 4] as StringName
			if caught:
				affection = -25.0
				trust = -30.0
				remembered = "tried to steal from me"
				lines.append(LineBank.pick(villager, "caught_stealing"))
			else:
				GameState.add(loot, 2)
				GameManager.notify("You pocketed 2 %s. Nobody noticed... this time." % GameState.RESOURCE_NAMES[loot].to_lower())
				lines.append("[happy]Anyway, as I was saying...")
				# They'll find out later, and remember.
				mind.memory.add("deed", player, WorldClock.day + 1, WorldClock.time_of_day,
					DialogueService.pack_deed("stole from me", -20.0))
				mind.adjust_opinion(player, 0.0, -5.0)
				_witnesses(villager, true, "stole from %s" % villager.data.display_name)
				return lines
	mind.adjust_opinion(player, affection, trust)
	if remembered != "":
		mind.memory.add("deed", player, WorldClock.day, WorldClock.time_of_day, DialogueService.pack_deed(remembered, affection))
	GameManager.opinion_changed.emit(villager, affection, trust)
	if bad:
		GameState.increment(&"bad_deeds")
		villager.model.set_expression(&"angry" if affection < -10.0 else &"sad", 0.9)
		_witnesses(villager, true, "%s %s" % [{"insult": "insulted", "prank": "pranked", "steal": "tried to rob"}.get(deed, "upset"), villager.data.display_name])
	elif deed == "gift":
		GameState.increment(&"good_deeds")
		_witnesses(villager, false, "gave %s a gift" % villager.data.display_name)
	return lines


## Villagers standing nearby saw what happened: their opinion changes, they
## remember it, and the nearest says something.
static func _witnesses(target, bad: bool, what: String) -> void:
	var spoke := false
	for other in GameManager.villagers:
		if other == target or not other.visible or other.state == Villager.State.INSIDE:
			continue
		if other.global_position.distance_to(target.global_position) > WITNESS_DISTANCE:
			continue
		var shift := -8.0 if bad else 3.0
		# Close family and friends take it personally.
		if other.mind.get_affection(String(target.get_villager_id())) >= SocialLife.FRIEND_AFFECTION:
			shift *= 1.6
		other.mind.adjust_opinion(GameManager.PLAYER_ID, shift, shift * 0.6)
		other.mind.memory.add("deed", GameManager.PLAYER_ID, WorldClock.day, WorldClock.time_of_day,
			DialogueService.pack_deed(what, shift))
		if not spoke:
			spoke = true
			# Said after the conversation closes (the bubble hides while talking).
			other.set_meta("pending_line", LineBank.pick(other, "witness_bad" if bad else "witness_good"))


const JOKES: Array[String] = [
	"Why did the scarecrow win a prize? Because he was outstanding in his field.",
	"I'd tell you a joke about the bridge, but you'd never get over it.",
	"What do you call a sleeping cow? A bulldozer.",
	"The baker's retiring. He just doesn't knead the dough any more.",
	"Why don't trees play cards? Too many leaves in the deck.",
	"I asked the river for directions. It said, go with the flow.",
	"Tomas's hammer told me a joke. It really hit the nail on the head.",
]

