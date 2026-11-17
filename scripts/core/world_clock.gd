extends Node
## The village's shared time. Every time-dependent system (sky, villager
## schedules, future seasons and ageing) reads from here.

signal hour_changed(hour: int)
signal day_changed(day: int)
signal time_scale_changed(scale: float)

const TIME_SCALES: Array[float] = [1.0, 5.0, 20.0]

## How long one in-game day lasts at normal speed.
var real_seconds_per_day: float = 960.0
var day: int = 1
var time_of_day: float = 7.5
var time_scale: float = 1.0
var paused: bool = false

var _last_hour: int = -1


func _process(delta: float) -> void:
	if paused:
		return
	advance(delta * time_scale * 24.0 / real_seconds_per_day)


func advance(hours: float) -> void:
	time_of_day += hours
	while time_of_day >= 24.0:
		time_of_day -= 24.0
		day += 1
		day_changed.emit(day)
	var hour := get_hour()
	if hour != _last_hour:
		_last_hour = hour
		hour_changed.emit(hour)


func set_time(hours: float) -> void:
	time_of_day = fposmod(hours, 24.0)
	_last_hour = -1
	advance(0.0)


func set_time_scale(value: float) -> void:
	time_scale = maxf(value, 0.0)
	time_scale_changed.emit(time_scale)


## Steps through the preset speeds (1x, 5x, 20x).
func cycle_time_scale() -> void:
	var index := TIME_SCALES.find(time_scale)
	set_time_scale(TIME_SCALES[(index + 1) % TIME_SCALES.size()])


func get_hour() -> int:
	return int(time_of_day)


func get_minute() -> int:
	return int((time_of_day - floorf(time_of_day)) * 60.0)


func get_time_string() -> String:
	return "%02d:%02d" % [get_hour(), get_minute()]


func get_period_name() -> String:
	var t := time_of_day
	if t < 5.0:
		return "Night"
	if t < 7.0:
		return "Dawn"
	if t < 12.0:
		return "Morning"
	if t < 17.0:
		return "Afternoon"
	if t < 20.5:
		return "Evening"
	return "Night"


func is_night() -> bool:
	return time_of_day < 5.5 or time_of_day >= 20.5


func to_dict() -> Dictionary:
	return {"day": day, "time_of_day": time_of_day}


func from_dict(data: Dictionary) -> void:
	day = int(data.get("day", 1))
	set_time(float(data.get("time_of_day", 7.5)))
