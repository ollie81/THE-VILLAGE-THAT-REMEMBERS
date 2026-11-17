class_name ScheduleBrain
extends VillagerBrain
## Follows the daily timetable authored in VillagerData.schedule.

var _activities: Array[VillagerActivity] = []


func _init(data: VillagerData) -> void:
	for entry in data.schedule:
		if entry is Dictionary:
			_activities.append(VillagerActivity.from_entry(entry))
	_activities.sort_custom(func(a, b): return a.start_hour < b.start_hour)
	if _activities.is_empty():
		_activities.append(VillagerActivity.from_entry({"activity": "wander", "hour": 0.0}))


func choose_activity(_villager: Node, hour: float) -> VillagerActivity:
	# The last entry of the day carries on past midnight until the first one.
	var chosen: VillagerActivity = _activities[_activities.size() - 1]
	for activity in _activities:
		if activity.start_hour <= hour:
			chosen = activity
	return chosen
