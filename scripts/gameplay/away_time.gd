class_name AwayTime
extends Node
## The village keeps living while the game is closed (or in the background).
## When you come back the clock moves on by the time you were gone, at most
## one village day, so leaving for a week never ruins anything, and the
## days, births, arrivals, friendships, crops and trees all catch up. Then a
## short "While you were away..." story shows what happened.

signal caught_up(summary: Dictionary)

## At most this many village hours pass while you're away.
const MAX_HOURS := 24.0
## Shorter absences pass quietly (no summary).
const MIN_HOURS_FOR_SUMMARY := 2.0

static var instance: AwayTime

## True while catching up (SocialLife uses a quicker simulation then).
static var catching_up: bool = false

var rng := RandomNumberGenerator.new()
var _paused_at_unix: float = -1.0
## Story templates already used in this catch-up (no repeats).
var _used: Dictionary = {}


func _ready() -> void:
	name = "AwayTime"
	instance = self
	rng.randomize()


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _notification(what: int) -> void:
	# Android: the app went to the background, then came back.
	if what == NOTIFICATION_APPLICATION_PAUSED:
		_paused_at_unix = Time.get_unix_time_from_system()
	elif what == NOTIFICATION_APPLICATION_RESUMED and _paused_at_unix > 0.0:
		var away := Time.get_unix_time_from_system() - _paused_at_unix
		_paused_at_unix = -1.0
		catch_up(seconds_to_hours(away))


## Village hours for a real absence, at normal speed, capped at a day.
static func seconds_to_hours(seconds: float) -> float:
	return clampf(seconds / WorldClock.real_seconds_per_day * 24.0, 0.0, MAX_HOURS)


## Moves the village on by `hours` and returns (and announces) what happened.
func catch_up(hours: float) -> Dictionary:
	if hours <= 0.01 or GameManager.is_in_conversation():
		return {}
	var start_events := Population.events.size()
	var start_day := WorldClock.day
	var ripe_before := _ripe_plots()
	var resources_before := {}
	for resource in GameState.RESOURCES:
		resources_before[resource] = GameState.count(resource)
	var moments: Array = []
	_used.clear()
	catching_up = true
	var remaining := hours
	while remaining > 0.0:
		var step := minf(remaining, 1.0)
		WorldClock.advance(step)
		remaining -= step
		var hour := WorldClock.get_hour()
		if hour >= 8 and hour <= 21:
			var moment := _village_moment(hour)
			if not moment.is_empty():
				moments.append(moment)
	catching_up = false
	# A long absence always has at least one small story.
	if moments.is_empty() and hours >= 6.0:
		for attempt in 10:
			var moment := _village_moment(15)
			if not moment.is_empty():
				moments.append(moment)
				break
	# Let crop growth and helpers' work catch up, then put everyone where
	# their day says they should be now.
	if StructureManager.instance:
		StructureManager.instance._process(0.0)
	if TaskSystem.instance:
		TaskSystem.instance._process(0.0)
	for villager in GameManager.villagers:
		if not villager.is_leaving() and villager.state != Villager.State.INTERACTING:
			villager._place_for_current_time()
	var summary := _summary(hours, start_day, start_events, ripe_before, resources_before, moments)
	if hours >= MIN_HOURS_FOR_SUMMARY and not summary["lines"].is_empty():
		caught_up.emit(summary)
	return summary


# --- Little stories ------------------------------------------------------------------

## Now and then two villagers do something together while you're away:
## they become closer (or fall out) and it becomes one line of the story.
func _village_moment(hour: int) -> Dictionary:
	var people: Array = GameManager.villagers.filter(func(v): return v.person and v.person.is_resident() and not v.is_leaving())
	if people.size() < 2 or rng.randf() > 0.45:
		return {}
	var a = people[rng.randi_range(0, people.size() - 1)]
	var b = people[rng.randi_range(0, people.size() - 1)]
	if a == b:
		return {}
	var fit := SocialLife.compatibility(a.person, b.person)
	var an := a.data.display_name as String
	var bn := b.data.display_name as String
	var text := ""
	var mood := 0.0
	if rng.randf() < fit * 0.9 + 0.1:
		mood = 4.0 + 6.0 * fit
		var good := [
			"%s and %s talked by the fire until the stars came out." % [an, bn],
			"%s helped %s carry water from the river." % [an, bn],
			"%s made %s laugh so hard they spilled their tea." % [an, bn],
			"%s and %s shared lunch under the old oak." % [an, bn],
			"%s taught %s a song from the old days." % [an, bn],
		]
		if hour >= 18:
			good.append("%s and %s danced at the fire. Everyone clapped." % [an, bn])
		text = _unused(good)
	else:
		mood = -6.0
		var bad := [
			"%s and %s argued at the well about whose turn it was." % [an, bn],
			"%s accused %s of taking their tools. Words were said." % [an, bn],
			"%s and %s haven't spoken since a quarrel at lunch." % [an, bn],
		]
		text = _unused(bad)
	if text == "":
		return {}
	a.mind.adjust_opinion(String(b.get_villager_id()), mood, mood * 0.5)
	b.mind.adjust_opinion(String(a.get_villager_id()), mood, mood * 0.5)
	a.mind.record_interaction(String(b.get_villager_id()), "time_together", WorldClock.day, WorldClock.time_of_day)
	Population.log_event("moment", text, [String(a.get_villager_id()), String(b.get_villager_id())])
	return {"text": text, "good": mood > 0.0}


## A line or two about what people spent the day doing.
func _days_work(hours: float) -> Array[String]:
	var out: Array[String] = []
	if hours < 4.0:
		return out
	var people: Array = GameManager.villagers.filter(func(v): return v.person and v.person.is_resident())
	people.shuffle()
	for villager in people.slice(0, 2):
		var noon := villager.brain.choose_activity(villager, 10.0) as VillagerActivity
		if noon == null or noon.label == "":
			continue
		out.append("%s spent the morning %s." % [villager.data.display_name, noon.label.substr(0, 1).to_lower() + noon.label.substr(1)])
	return out


## A template not used yet in this story ("" if all are). Templates differ by
## index, since the names in them change.
func _unused(options: Array) -> String:
	var order := range(options.size())
	order.shuffle()
	for i in order:
		var key := "%d:%d" % [options.size(), i]
		if not _used.has(key):
			_used[key] = true
			return String(options[i])
	return ""


func _ripe_plots() -> int:
	if StructureManager.instance == null:
		return 0
	return StructureManager.instance.structures().filter(func(s): return s.get_type() == &"farm_plot" and s.is_ripe()).size()


## The story of the absence: the big news first, then a few small moments.
func _summary(hours: float, start_day: int, start_events: int, ripe_before: int, resources_before: Dictionary, moments: Array) -> Dictionary:
	var big: Array[String] = []
	var small: Array[String] = []
	for event: Dictionary in Population.events.slice(start_events):
		var text := String(event["text"])
		match String(event["type"]):
			"birth", "death", "marriage", "partnership", "arrival", "visitor", "coming_of_age", "expecting", "adoption", "departure", "ambition":
				big.append(text)
			"moment":
				pass
			_:
				small.append(text)
	for moment: Dictionary in moments:
		small.append(String(moment["text"]))
	small.append_array(_days_work(hours))
	var ripe := _ripe_plots()
	if ripe > ripe_before:
		big.append("Your crops are ready to harvest (%d field%s)." % [ripe, "" if ripe == 1 else "s"])
	var gained := PackedStringArray()
	for resource in GameState.RESOURCES:
		var diff := GameState.count(resource) - int(resources_before[resource])
		if diff > 0:
			gained.append("%d %s" % [diff, GameState.RESOURCE_NAMES[resource].to_lower()])
	if not gained.is_empty():
		small.append("The villagers you asked for help brought in %s." % ", ".join(gained))
	if not Population.visitors().is_empty():
		var visitor: Person = Population.visitors()[0]
		big.append("%s is waiting at the meeting circle, hoping to stay." % visitor.full_name())
	if RequestBoard.instance and not RequestBoard.instance.open_requests().is_empty():
		var asks := PackedStringArray()
		for request: Dictionary in RequestBoard.instance.open_requests():
			var who = GameManager.get_villager(StringName(String(request["from"])))
			if who:
				asks.append(who.data.display_name)
		if not asks.is_empty():
			big.append("%s %s something to ask you today." % [" and ".join(asks), "have" if asks.size() > 1 else "has"])
	small.shuffle()
	var lines: Array[String] = big + small.slice(0, maxi(0, 6 - big.size()))
	var days := WorldClock.day - start_day
	var title := "While you were away..."
	var subtitle := "%d hours passed in the village." % int(round(hours)) if days == 0 else ("A new day dawned. It's day %d." % WorldClock.day if days == 1 else "%d days passed." % days)
	return {"title": title, "subtitle": subtitle, "lines": lines, "hours": hours}
