class_name DialogueService
extends RefCounted
## Builds what a villager says to the player:
##   1. a greeting shaped by how often they've met and how they feel,
##   2. at most one memory: something the player did on an earlier day, or
##      something another villager told them about the player,
##   3. the next topic in their list, with choices (see ConversationLibrary),
##      or an apology scene if they've come to dislike the player.


static func build_conversation(villager, actor_id: String) -> Conversation:
	var conversation := Conversation.new(villager, actor_id)
	var mind: VillagerMind = villager.mind
	conversation.lines = build_greeting(villager, actor_id)
	var recollection := _recollection(villager, actor_id)
	if recollection != "":
		conversation.lines.append(recollection)

	var topic: Dictionary = {}
	if mind.is_hostile(actor_id):
		topic = ConversationLibrary.APOLOGY
		# Only the hostile line; drop the friendly greeting.
		conversation.lines = []
		if recollection != "":
			conversation.lines.append(recollection)
	else:
		topic = next_topic(villager, actor_id)
	if not topic.is_empty():
		conversation.topic_id = String(topic["id"])
		for line in topic["lines"]:
			conversation.lines.append(String(line))
		conversation.choices = topic["choices"]
		if topic != ConversationLibrary.APOLOGY:
			conversation.followup = closing_menu()
	else:
		conversation.lines.append_array(_small_talk(villager))
		conversation.choices = closing_menu()
	return conversation


## The last thing offered in a conversation: ask for help, or leave.
static func closing_menu() -> Array:
	return [
		{"text": "Could you help me with something?", "action": "ask"},
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
		lines.append("[laughing]There you are! I was hoping you'd come by.")
	elif affection <= -15.0:
		lines.append("[worried]Oh. It's you.")
	elif days_since <= 0:
		lines.append("[surprised]Back again already? Not that I mind.")
	elif days_since == 1:
		lines.append("[happy]%s. Good to see you again, we spoke just yesterday." % time_greeting(WorldClock.time_of_day))
	else:
		lines.append("[happy]%s. It's been %d days since we last talked." % [time_greeting(WorldClock.time_of_day), days_since])
	if affection > -15.0 and not data.returning_lines.is_empty():
		lines.append(data.returning_lines[(times_met - 1) % data.returning_lines.size()])
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
	var data: VillagerData = villager.data
	var lines: Array[String] = []
	var activity: VillagerActivity = villager.current_activity
	if activity:
		var comment := String(data.activity_comments.get(String(activity.kind), ""))
		if comment != "":
			lines.append(comment)
	if lines.is_empty():
		lines.append("[happy]Good to see you.")
	return lines


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
