class_name DialogueService
extends RefCounted
## Builds what a villager says. Milestone 1: an introduction on first meeting,
## a remembered greeting on later visits, and a comment on what they are doing.
## Future: lines chosen by mood, relationship, recent village events and
## memories of specific things the player did.


static func build_greeting(villager, actor_id: String) -> Array[String]:
	var data: VillagerData = villager.data
	var mind: VillagerMind = villager.mind
	var lines: Array[String] = []
	var times_met := mind.memory.count("conversation", actor_id)

	if times_met == 0:
		lines.append("%s! I don't think we've met. I'm %s." % [time_greeting(WorldClock.time_of_day), data.display_name])
		for line in data.first_meeting_lines:
			lines.append(line)
	else:
		var last := mind.memory.last("conversation", actor_id)
		var days_since := WorldClock.day - int(last.get("day", WorldClock.day))
		if days_since <= 0:
			lines.append("Back again already? Not that I mind.")
		elif days_since == 1:
			lines.append("%s. Good to see you again, we spoke just yesterday." % time_greeting(WorldClock.time_of_day))
		else:
			lines.append("%s. It's been %d days since we last talked." % [time_greeting(WorldClock.time_of_day), days_since])
		if not data.returning_lines.is_empty():
			lines.append(data.returning_lines[(times_met - 1) % data.returning_lines.size()])

	var activity: VillagerActivity = villager.current_activity
	if activity:
		var comment := String(data.activity_comments.get(String(activity.kind), ""))
		if comment != "":
			lines.append(comment)
	return lines


static func time_greeting(hour: float) -> String:
	if hour >= 5.0 and hour < 12.0:
		return "Good morning"
	if hour >= 12.0 and hour < 17.0:
		return "Good afternoon"
	if hour >= 17.0 and hour < 21.0:
		return "Good evening"
	return "Hello there, you're up late"
