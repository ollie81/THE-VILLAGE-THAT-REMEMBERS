class_name Conversation
extends RefCounted
## One conversation with a villager: lines to show, then (optionally) a set of
## choices. Choosing applies the consequences: the villager's opinion of the
## player changes, and memorable choices become memories that come back in
## later conversations and spread through the village as gossip.

## Lines still to show. Lines may start with an expression tag ("[happy]").
var lines: Array[String] = []
## Choices offered once `lines` run out: dictionaries from ConversationLibrary.
var choices: Array = []
var topic_id: String = ""

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
