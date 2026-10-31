class_name VillageMeeting
extends Node
## Calling a meeting at the fire: everyone who's awake walks to the meeting
## circle, then each villager speaks in turn. What they say depends on how
## they feel about the player and what the player has done for the village.

const MAX_WAIT := 45.0

var running: bool = false
var _wait: float = 0.0
var _attendees: Array = []


static func is_meeting_time() -> bool:
	return WorldClock.time_of_day >= 17.0 and WorldClock.time_of_day <= 21.5


func call_meeting() -> void:
	_attendees.clear()
	for villager in GameManager.villagers:
		if not villager.visible:
			continue
		var target := TaskSystem.task_target(villager, &"meeting")
		var activity := VillagerActivity.new()
		activity.kind = &"task_meeting"
		activity.location_id = "task"
		activity.label = String(TaskSystem.LABELS[&"meeting"])
		activity.animation = &"idle"
		target["kind"] = "meeting"
		target["activity"] = activity
		target["until"] = TaskSystem.absolute_hours() + 3.0
		villager.assign_task(target)
		_attendees.append(villager)
	if _attendees.is_empty():
		GameManager.notify("Everyone is asleep. Try earlier in the evening.")
		return
	running = true
	_wait = 0.0
	GameManager.notify("You called a village meeting. Everyone is coming to the fire.")


func _process(delta: float) -> void:
	if not running:
		return
	_wait += delta
	var arrived := 0
	for villager in _attendees:
		if villager.is_working_on_task():
			arrived += 1
	if arrived == _attendees.size() or _wait > MAX_WAIT:
		running = false
		hold()


## Runs the meeting conversation (also callable directly by tests).
func hold() -> void:
	var speakers: Array = _attendees if not _attendees.is_empty() else GameManager.villagers
	var conversation := Conversation.new(speakers[0], GameManager.PLAYER_ID)
	conversation.lines = meeting_lines(speakers)
	GameManager.start_scene(speakers[0], conversation, true)
	GameManager.conversation_ended.connect(_on_meeting_over.bind(speakers), CONNECT_ONE_SHOT)


func _on_meeting_over(_villager, speakers: Array) -> void:
	for villager in speakers:
		villager.mind.adjust_opinion(GameManager.PLAYER_ID, 5.0, 3.0)
		villager.mind.memory.add("event", GameManager.PLAYER_ID, WorldClock.day, WorldClock.time_of_day, "village meeting")
		villager.task["until"] = 0.0
	GameState.increment(&"meetings")
	GameState.set_flag(&"meeting_held")
	GameManager.notify("The meeting is over. A new mark is carved on the story stone.")


static func meeting_lines(speakers: Array) -> Array[String]:
	var lines: Array[String] = []
	var first: String = speakers[0].data.id
	lines.append("@%s [happy]Well, everyone's here. The newcomer called us together." % first)
	for villager in speakers:
		lines.append("@%s %s" % [villager.data.id, _speech(villager)])
	var built := GameState.structures.size()
	var stock := GameState.count(&"wood") + GameState.count(&"stone") + GameState.count(&"food")
	lines.append("@%s [laughing]%s" % [first,
		"With %d new structures and full stores, I'd say this village is growing." % built if built > 0 or stock > 20
		else "We've a long way to go, but we'll get there together."])
	lines.append("@%s [happy]Let's carve tonight on the story stone. The village will remember it." % first)
	return lines


## One villager's few words, shaped by their opinion and the player's deeds.
static func _speech(villager) -> String:
	var mind: VillagerMind = villager.mind
	var player := GameManager.PLAYER_ID
	var affection := mind.get_affection(player)
	var deeds := mind.memory.find("deed", player)
	if affection >= 25.0 and not deeds.is_empty():
		var deed := DialogueService.unpack_deed(String(deeds[deeds.size() - 1]["detail"]))
		if float(deed["affection"]) > 0.0:
			return "[happy]I'll say it: you %s, and I won't forget it." % deed["text"]
	if affection >= 15.0:
		return "[happy]You've been good to this village. I'm glad you came."
	if affection <= -15.0:
		return "[worried]I'll be honest. I'm not sure about you yet."
	if villager.data.id == &"sera":
		return "[laughing]If this turns into a story, I'm telling it!"
	if villager.data.id == &"tomas":
		return "[happy]Villages are built one day at a time. Today was a good one."
	return "[happy]It's good to gather like this. We should do it more often."
