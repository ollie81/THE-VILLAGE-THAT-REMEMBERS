class_name Conversation
extends RefCounted
## One conversation with a villager: lines to show, then (optionally) a set of
## choices. Choosing applies the consequences: the villager's opinion of the
## player changes, and memorable choices become memories that come back in
## later conversations and spread through the village as gossip.

## Lines still to show. Lines may start with an expression tag ("[happy]").
var lines: Array[String] = []
## Choices offered once `lines` run out: dictionaries from ConversationLibrary,
## or action choices ({ text, action }) such as asking for help.
var choices: Array = []
var topic_id: String = ""
## Shown after a topic's reply (e.g. "Could you help me with something?").
var followup: Array = []

var _villager
var _actor_id: String


func _init(villager = null, actor_id: String = "") -> void:
	_villager = villager
	_actor_id = actor_id


func has_lines() -> bool:
	return not lines.is_empty()


func next_line() -> String:
	return lines.pop_front() if not lines.is_empty() else ""


func has_choices() -> bool:
	return lines.is_empty() and not choices.is_empty()


func choice_texts() -> PackedStringArray:
	var texts := PackedStringArray()
	for choice in choices:
		texts.append(String(choice.get("text", "")))
	return texts


## Applies a choice and queues the villager's reply.
func choose(index: int) -> void:
	if index < 0 or index >= choices.size():
		return
	var choice: Dictionary = choices[index]
	choices = []
	if choice.has("action"):
		_do_action(choice)
		return
	var affection := float(choice.get("affection", 0))
	var trust := float(choice.get("trust", 0))
	var remembered := String(choice.get("remember", ""))
	if _villager:
		var mind: VillagerMind = _villager.mind
		mind.adjust_opinion(_actor_id, affection, trust)
		mind.memory.add("topic", _actor_id, WorldClock.day, WorldClock.time_of_day, topic_id)
		if remembered != "":
			mind.memory.add("deed", _actor_id, WorldClock.day, WorldClock.time_of_day,
				DialogueService.pack_deed(remembered, affection))
		if topic_id == "apology" and remembered != "":
			# An accepted apology lets the old grudges be talked about afresh.
			mind.memory.add("mentioned", _actor_id, WorldClock.day, WorldClock.time_of_day, "apology")
		GameManager.opinion_changed.emit(_villager, affection, trust)
	for reply in choice.get("reply", []):
		lines.append(String(reply))
	choices = followup
	followup = []


func _do_action(choice: Dictionary) -> void:
	match String(choice["action"]):
		"ask":
			choices = DialogueService.task_menu(_villager)
		"task":
			var result := TaskSystem.request(_villager, StringName(String(choice["task"])))
			for line in result["lines"]:
				lines.append(String(line))
		"ask_stay":
			var person: Person = _villager.person
			var warmth: float = _villager.mind.get_affection(_actor_id)
			if warmth >= -10.0:
				person.leaving = false
				person.unhappy_days = 0
				person.happiness = minf(person.happiness + 15.0, 100.0)
				_villager.mind.adjust_opinion(_actor_id, 8.0, 5.0)
				Population.log_event("stayed", "%s was talked into staying." % person.first_name, [person.id])
				var wish := "a proper home instead of a tent" if person.home == Population.CAMP_ID \
					else "a few more friends" if person.partner == "" else "a little more time"
				lines.append("[sad]...You really want me here?")
				lines.append("[happy]Alright. I'll give it another try. I suppose I just need %s." % wish)
			else:
				lines.append("[angry]After how you've treated me? No. I'm going.")
			choices = DialogueService.closing_menu()
		"visitor_more":
			lines.append_array(PersonGenerator.visitor_details(_villager.person))
			choices = DialogueService.visitor_menu(false)
		"welcome":
			if PopulationDirector.instance:
				lines.append_array(PopulationDirector.instance.welcome(_villager))
		"turn_away":
			if PopulationDirector.instance:
				lines.append_array(PopulationDirector.instance.turn_away(_villager))
		_:
			pass
