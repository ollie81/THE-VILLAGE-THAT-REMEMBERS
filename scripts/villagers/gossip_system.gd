class_name GossipSystem
extends Node
## Villagers who are chatting together pass on what the player has done.
## The listener remembers who told them, forms a (weaker) opinion of the
## player from it, and may bring it up the next time they talk to the player.

const CHECK_INTERVAL := 5.0
## Chance per check that a pair of chatting villagers swap a story.
const SHARE_CHANCE := 0.35
## How strongly second-hand stories move the listener's opinion.
const HEARSAY_WEIGHT := 0.4
const CHAT_DISTANCE := 7.0

var _timer: float = 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	name = "GossipSystem"
	_rng.randomize()


func _process(delta: float) -> void:
	_timer += delta
	if _timer < CHECK_INTERVAL:
		return
	_timer = 0.0
	var chatting: Array = []
	for villager in GameManager.villagers:
		if is_chatting(villager):
			chatting.append(villager)
	for i in chatting.size():
		for j in chatting.size():
			if i == j:
				continue
			var speaker = chatting[i]
			var listener = chatting[j]
			if speaker.global_position.distance_to(listener.global_position) > CHAT_DISTANCE:
				continue
			if _rng.randf() < SHARE_CHANCE:
				share(speaker, listener)


static func is_chatting(villager) -> bool:
	return villager.visible and villager.state == Villager.State.PERFORMING \
		and villager.current_activity != null and villager.current_activity.kind == &"socialize"


## Speaker tells listener about one thing the player did that the listener
## hasn't heard yet. Returns the story's text, or "" if there was nothing new.
static func share(speaker, listener) -> String:
	var subject := GameManager.PLAYER_ID
	var speaker_mind: VillagerMind = speaker.mind
	var listener_mind: VillagerMind = listener.mind
	var deeds := speaker_mind.memory.find("deed", subject)
	deeds.reverse()
	for entry in deeds:
		var deed := DialogueService.unpack_deed(String(entry["detail"]))
		var heard_detail := "%s|%s|%s" % [String(speaker.get_villager_id()), deed["text"], deed["affection"]]
		if listener_mind.memory.has_detail("heard", subject, heard_detail):
			continue
		if listener_mind.memory.has_detail("deed", subject, String(entry["detail"])):
			continue
		var affection: float = deed["affection"]
		listener_mind.memory.add("heard", subject, WorldClock.day, WorldClock.time_of_day, heard_detail)
		listener_mind.adjust_opinion(subject, affection * HEARSAY_WEIGHT, affection * HEARSAY_WEIGHT * 0.5)
		GameManager.gossip_shared.emit(speaker, listener, deed["text"])
		return deed["text"]
	return ""
