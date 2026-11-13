class_name DialogueService
extends RefCounted
## Builds what a villager says to the player:
##   1. a greeting shaped by how often they've met and how they feel,
##   2. at most one memory: something the player did on an earlier day, or
##      something another villager told them about the player,
##   3. the next topic in their list, with choices (see ConversationLibrary),
##      or an apology scene if they've come to dislike the player.


static func build_conversation(villager, actor_id: String) -> Conversation:
	if villager.is_visitor():
		return visitor_conversation(villager, actor_id)
	var conversation := Conversation.new(villager, actor_id)
	var mind: VillagerMind = villager.mind
	conversation.lines = build_greeting(villager, actor_id)
	var recollection := _recollection(villager, actor_id)
	if recollection != "":
		conversation.lines.append(recollection)
	# Festival talk, then a story from what's happened between you.
	if Festival.instance and not mind.is_hostile(actor_id) and mind.memory.count("conversation", actor_id) > 0:
		var festive := Festival.instance.greeting_for(villager)
		if festive != "":
			conversation.lines.append(festive)
	if VillageStories.instance and actor_id == GameManager.PLAYER_ID and mind.memory.count("conversation", actor_id) > 0:
		conversation.lines.append_array(VillageStories.instance.story_lines(villager))

	var topic: Dictionary = {}
	if mind.is_hostile(actor_id):
		topic = ConversationLibrary.APOLOGY
		# Only the hostile line; drop the friendly greeting.
		conversation.lines = []
		if recollection != "":
			conversation.lines.append(recollection)
	else:
		topic = next_topic(villager, actor_id)
	if not topic.is_empty() and mind.memory.count("conversation", actor_id) > 1 and not mind.is_hostile(actor_id):
		conversation.lines.append_array(Chatter.lines_for(villager, 1))
	if not topic.is_empty():
		conversation.topic_id = String(topic["id"])
		for line in topic["lines"]:
			conversation.lines.append(String(line))
		conversation.choices = topic["choices"]
		if topic != ConversationLibrary.APOLOGY:
			conversation.followup = menu_for(villager)
	else:
		conversation.lines.append_array(_small_talk(villager))
		conversation.choices = menu_for(villager)
	_family_news(villager, conversation)
	if RequestBoard.instance and not mind.is_hostile(actor_id):
		var forgot := RequestBoard.instance.forgotten_line(villager)
		if forgot != "":
			conversation.lines.append(forgot)
		var ask := RequestBoard.instance.reminder_for(villager)
		if ask != "":
			conversation.lines.append(ask)
	# Someone who has decided to leave says so, and can be asked to stay.
	if villager.person and villager.person.leaving and not villager.is_leaving():
		conversation.lines.append("[sad]I've made up my mind. I'm leaving in the morning.")
		var menu: Array = [{"text": "Please stay. What would make you happier here?", "action": "ask_stay"}]
		menu.append_array(conversation.choices if conversation.choices.size() > 0 else closing_menu())
		conversation.choices = menu
	return conversation


## Grief comes first; otherwise a baby on the way or a little one at home.
static func _family_news(villager, conversation: Conversation) -> void:
	var person: Person = villager.person
	if person == null:
		return
	var lost := Population.recently_lost(person)
	if lost:
		conversation.lines.push_front("[sad]I'm not much company today. %s is gone, and I keep expecting to hear %s voice." % [
			lost.first_name, "her" if lost.sex == "female" else "his"])
		return
	if person.expecting_day >= 0:
		var days := person.expecting_day - WorldClock.day
		conversation.lines.append("[happy]The baby's coming any day now!" if days <= 1 else "[happy]We're having a baby! In about %d days." % days)
		return
	for child_id in person.children:
		var child := Population.get_person(String(child_id))
		if child and child.is_resident() and child.is_baby():
			conversation.lines.append("[laughing]Little %s kept us up all night again. Worth it, though." % child.first_name)
			return


## A traveller asking to stay: welcome them, hear more, or turn them away.
static func visitor_conversation(villager, actor_id: String) -> Conversation:
	var conversation := Conversation.new(villager, actor_id)
	conversation.lines = PersonGenerator.visitor_intro(villager.person)
	conversation.choices = visitor_menu(true)
	return conversation


static func visitor_menu(can_ask_more: bool) -> Array:
	var menu: Array = [{"text": "Welcome to the village! There's a place for you here.", "action": "welcome"}]
	if can_ask_more:
		menu.append({"text": "Tell me more about yourself first.", "action": "visitor_more"})
	menu.append({"text": "I'm sorry, we can't take anyone else in.", "action": "turn_away"})
	return menu


## The last thing offered in a conversation: ask for help, or leave.
## The closing menu for this villager ("What's new?" only if they have news).
static func menu_for(villager) -> Array:
	var menu := closing_menu()
	if RequestBoard.instance and villager:
		menu = RequestBoard.instance.choices_for(villager) + menu
	if VillageStories.instance and villager:
		menu = VillageStories.instance.choices_for(villager) + menu
	if villager and not Chatter.has_news(villager):
		menu = menu.filter(func(c): return String(c.get("action", "")) != "news")
	return fit_menu(menu)


## Keeps a menu within what fits on screen: when there are too many answers,
## asking for help and being kind or unkind fold into "Something else...",
## so requests, stories, news and Goodbye always stay visible.
static func fit_menu(menu: Array) -> Array:
	if menu.size() <= DialoguePanel.MAX_CHOICES:
		return menu
	var folded := ["ask", "kind", "unkind"]
	var errands: Array = []
	var news: Array = []
	var bye: Array = []
	var has_more := false
	for choice: Dictionary in menu:
		var action := String(choice.get("action", ""))
		if action in folded or action == "more":
			has_more = true
		elif action == "news":
			news.append(choice)
		elif action == "bye":
			bye.append(choice)
		else:
			errands.append(choice)
	var tail: Array = news + ([{"text": "Something else...", "action": "more"}] if has_more else []) + bye
	# A lot of errands at once: the first ones show (the rest next time).
	errands = errands.slice(0, DialoguePanel.MAX_CHOICES - tail.size())
	return errands + tail


## What "Something else..." opens.
static func more_menu() -> Array:
	return closing_menu().filter(func(c): return String(c["action"]) in ["ask", "kind", "unkind"]) + [{"text": "Never mind.", "action": "back"}]


static func closing_menu() -> Array:
	return [
		{"text": "What's new?", "action": "news"},
		{"text": "Could you help me with something?", "action": "ask"},
		{"text": "Be kind...", "action": "kind"},
		{"text": "Be unkind...", "action": "unkind"},
		{"text": "Goodbye.", "action": "bye"},
	]


## Jobs the player can ask for; building only when something needs building.
static func task_menu(_villager) -> Array:
	var menu: Array = []
	for kind in TaskSystem.KINDS:
		if kind == &"build" and (StructureManager.instance == null or StructureManager.instance.nearest_unfinished(Vector3.ZERO) == null):
			continue
		menu.append({"text": TaskSystem.ASK_TEXT[kind], "action": "task", "task": String(kind)})
	menu.append({"text": "Never mind.", "action": "bye"})
	return menu


## The first topic this villager hasn't discussed with the actor yet.
static func next_topic(villager, actor_id: String) -> Dictionary:
	var mind: VillagerMind = villager.mind
	for topic in ConversationLibrary.topics_for(villager.data.id):
		if not mind.memory.has_detail("topic", actor_id, String(topic["id"])):
			return topic
	return {}


static func build_greeting(villager, actor_id: String) -> Array[String]:
	var data: VillagerData = villager.data
	var mind: VillagerMind = villager.mind
	var lines: Array[String] = []
	var times_met := mind.memory.count("conversation", actor_id)
	var affection := mind.get_affection(actor_id)

	if times_met == 0:
		lines.append("[happy]%s! I don't think we've met. I'm %s." % [time_greeting(WorldClock.time_of_day), data.display_name])
		for line in data.first_meeting_lines:
			lines.append(line)
		return lines

	var last := mind.memory.last("conversation", actor_id)
	var days_since := WorldClock.day - int(last.get("day", WorldClock.day))
	if affection >= 40.0:
		lines.append(LineBank._fresh(villager, ["[laughing]There you are! I was hoping you'd come by.",
			"[happy]My favourite person! Come, sit.", "[laughing]I was just thinking about you!"]))
	elif affection <= -15.0:
		lines.append(LineBank._fresh(villager, ["[worried]Oh. It's you.", "[worried]What is it now?",
			"[angry]I'm busy.", "[worried]...Yes?"]))
	elif days_since <= 0:
		lines.append(LineBank._fresh(villager, ["[surprised]Back again already? Not that I mind.",
			"[happy]Hello again!", "[laughing]You again! Did you miss me?", "[happy]Oh, hello. Something on your mind?"]))
	elif days_since == 1:
		lines.append("[happy]%s. Good to see you again, we spoke just yesterday." % time_greeting(WorldClock.time_of_day))
	else:
		lines.append("[happy]%s. It's been %d days since we last talked." % [time_greeting(WorldClock.time_of_day), days_since])
	return lines


## Gossip they heard first, then the player's own past deeds (from an
## earlier day). Each is brought up once.
static func _recollection(villager, actor_id: String) -> String:
	var mind: VillagerMind = villager.mind
	var heard := mind.memory.find("heard", actor_id)
	heard.reverse()
	for entry in heard:
		var detail := String(entry["detail"])
		if mind.memory.has_detail("mentioned", actor_id, "heard:" + detail):
			continue
		var parts := detail.split("|")
		if parts.size() < 3:
			continue
		var source = GameManager.get_villager(StringName(parts[0]))
		var source_name: String = source.data.display_name if source else parts[0].capitalize()
		mind.memory.add("mentioned", actor_id, WorldClock.day, WorldClock.time_of_day, "heard:" + detail)
		var affection := float(parts[2])
		if affection > 0.0:
			return "[happy]%s told me you %s. That was good of you." % [source_name, parts[1]]
		return "[angry]%s told me you %s. Is that true?" % [source_name, parts[1]]

	var deeds := mind.memory.find("deed", actor_id)
	deeds.reverse()
	for entry in deeds:
		if int(entry["day"]) >= WorldClock.day:
			continue
		var detail := String(entry["detail"])
		if mind.memory.has_detail("mentioned", actor_id, "deed:" + detail):
			continue
		var deed := unpack_deed(detail)
		mind.memory.add("mentioned", actor_id, WorldClock.day, WorldClock.time_of_day, "deed:" + detail)
		if float(deed["affection"]) > 0.0:
			return "[happy]I haven't forgotten that you %s." % deed["text"]
		return "[sad]I still remember that you %s." % deed["text"]
	return ""


static func _small_talk(villager) -> Array[String]:
	return Chatter.lines_for(villager, 2)


static func pack_deed(text: String, affection: float) -> String:
	return "%s|%s" % [text, affection]


static func unpack_deed(detail: String) -> Dictionary:
	var split := detail.rfind("|")
	if split < 0:
		return {"text": detail, "affection": 0.0}
	return {"text": detail.substr(0, split), "affection": float(detail.substr(split + 1))}


static func time_greeting(hour: float) -> String:
	if hour >= 5.0 and hour < 12.0:
		return "Good morning"
	if hour >= 12.0 and hour < 17.0:
		return "Good afternoon"
	if hour >= 17.0 and hour < 21.0:
		return "Good evening"
	return "Hello there, you're up late"
