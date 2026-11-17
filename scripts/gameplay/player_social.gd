class_name PlayerSocial
extends Node
## The village notices the player: villagers wave back, bow back, laugh or
## join in when you dance, greet you as you pass (differently by time of day,
## mood and personality) and comment when you sit with them or slept outside.

const REACT_DISTANCE := 9.0
const GREET_DISTANCE := 3.6
## Seconds between any two greetings, and between greetings from one person.
const GREET_GAP := 7.0
const PERSONAL_GAP := 120.0

static var instance: PlayerSocial

var _check_timer: float = 0.0
var _last_greeting_msec: int = -100000
## villager id -> day they last got a goodwill bump from a wave or bow.
var _friendly_days: Dictionary = {}


func _ready() -> void:
	name = "PlayerSocial"
	instance = self
	if GameManager.player:
		GameManager.player.posed.connect(_on_player_posed)


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _nearby(distance: float) -> Array:
	var player = GameManager.player
	var out: Array = []
	for villager in GameManager.villagers:
		if not villager.visible or villager.is_leaving() or villager.state == Villager.State.INSIDE:
			continue
		if villager.state == Villager.State.INTERACTING or villager.is_reacting():
			continue
		if villager.global_position.distance_to(player.global_position) <= distance:
			out.append(villager)
	out.sort_custom(func(a, b): return a.global_position.distance_squared_to(player.global_position) < b.global_position.distance_squared_to(player.global_position))
	return out


# --- Reactions to the player's actions --------------------------------------------

func _on_player_posed(pose: StringName) -> void:
	var player = GameManager.player
	var people := _nearby(REACT_DISTANCE)
	var spoken := 0
	for villager in people:
		var tone := LineBank.tone_of(villager)
		var speak := spoken < 2
		var line := ""
		var animation: StringName = &"idle"
		var duration := 2.4
		match pose:
			&"wave":
				animation = &"wave" if tone != "cool" else &"idle"
				line = LineBank.pick(villager, "wave")
				_goodwill(villager, 0.6)
			&"bow":
				animation = &"bow" if tone in ["warm", "plain", "shy", "child"] else &"idle"
				line = LineBank.pick(villager, "bow")
				_goodwill(villager, 0.8)
			&"cheer":
				animation = &"cheer" if tone in ["warm", "cheerful", "child"] else &"idle"
				line = LineBank.pick(villager, "cheer")
			&"dance":
				var joins: bool = tone in ["cheerful", "child"] or (tone == "warm" and villager.data.personality.get("extraversion", 0.5) > 0.5)
				animation = &"dance" if joins else (&"talk" if tone != "grumpy" else &"idle")
				duration = 6.0 if joins else 2.5
				line = LineBank.pick(villager, "dance")
				_goodwill(villager, 0.4 if tone != "grumpy" else -0.3)
			&"sit", &"sit_ground":
				# Only someone sitting right next to you says anything.
				if villager.global_position.distance_to(player.global_position) > 2.6 or spoken > 0:
					continue
				villager.say(LineBank.pick(villager, "sit_near"))
				spoken += 1
				continue
			_:
				continue
		villager.react(animation, duration, player.global_position, line if speak else "")
		if speak:
			spoken += 1


## Small daily bump for friendly gestures (only once a day per person).
func _goodwill(villager, amount: float) -> void:
	var id := String(villager.get_villager_id())
	if int(_friendly_days.get(id, -1)) == WorldClock.day:
		return
	_friendly_days[id] = WorldClock.day
	villager.mind.adjust_opinion(GameManager.PLAYER_ID, amount, amount * 0.5)


# --- Greetings in passing -----------------------------------------------------------

func _process(delta: float) -> void:
	_check_timer -= delta
	if _check_timer > 0.0 or GameManager.player == null or GameManager.is_in_conversation():
		return
	_check_timer = 0.5
	if Time.get_ticks_msec() - _last_greeting_msec < int(GREET_GAP * 1000.0):
		return
	var player = GameManager.player
	for villager in _nearby(GREET_DISTANCE):
		if Time.get_ticks_msec() - int(villager.last_spoke_msec) < int(PERSONAL_GAP * 1000.0):
			continue
		if villager.mind.get_familiarity(GameManager.PLAYER_ID) == 0 and not villager.is_visitor():
			continue
		var situation := greeting_situation(villager)
		if GameState.get_flag(&"slept_outside") and WorldClock.time_of_day < 11.0:
			situation = "slept_outside"
			GameState.set_flag(&"slept_outside", false)
		villager.react(&"wave" if situation.begins_with("greet") and randf() < 0.5 else &"idle", 1.6,
			player.global_position, LineBank.pick(villager, situation))
		_last_greeting_msec = Time.get_ticks_msec()
		return


static func greeting_situation(villager) -> String:
	if villager.state == Villager.State.PERFORMING and villager.current_activity \
			and villager.current_activity.kind in [&"work", &"gather"]:
		return "busy_working"
	var hour := WorldClock.time_of_day
	if hour < 11.0:
		return "greet_morning"
	if hour < 17.5:
		return "greet_day"
	return "greet_evening"
