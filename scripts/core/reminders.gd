class_name Reminders
extends Node
## A gentle reminder on the phone when the daily gift is ready again.
##
## - Asked first: after the first day's last goal ("Make it home") a small
##   question offers it; nothing is sent unless the player says yes (and, on
##   Android 13+, allows notifications). It can be switched off in Settings.
## - At most one a day: when the game is put away, one reminder is scheduled
##   for the next day (never before the next daily gift is ready, and only
##   between 10:00 and 19:30 local time); coming back cancels it.
## - Varied and personal: a streak to keep, a villager's gift waiting, or
##   someone in the village wondering where you are.
## On Android this uses the game's own plugin (android_plugin/, singleton
## VillageNotify). Elsewhere nothing is sent; `last_plan` shows what would be.

signal changed

static var instance: Reminders
## Tests switch this off so they never touch the player's files.
static var persist: bool = true

const SAVE_PATH := "user://reminders.cfg"
const ID_DAILY := 1001
const TITLE := "The Village That Remembers"
## Not before this long after putting the game away.
const MIN_GAP_HOURS := 20.0
## Local hours a reminder may arrive.
const EARLIEST_HOUR := 10.0
const LATEST_HOUR := 19.5
## Existing players (past the first day) are asked after this much play.
const ASK_LATER_SECONDS := 90.0

var enabled: bool = false
var asked: bool = false
## The last reminder planned ({} if none): at (unix), delay, title, text.
var last_plan: Dictionary = {}
var _plugin: Object = null
var _prompt: CanvasLayer
var _play_time: float = 0.0


func _ready() -> void:
	name = "Reminders"
	instance = self
	_load()
	if Engine.has_singleton("VillageNotify"):
		_plugin = Engine.get_singleton("VillageNotify")
	cancel_all()
	GameState.objective_completed.connect(_on_objective_completed)


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED:
		schedule_next()
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		cancel_all()


func _process(delta: float) -> void:
	# Existing players are asked after a little play (not in tests, which
	# run without saving).
	if asked or _prompt != null or not SaveService.enabled:
		return
	_play_time += delta
	var home := GameState.OBJECTIVES.map(func(o): return o["id"]).find("home")
	if _play_time >= ASK_LATER_SECONDS and (GameState.objective_index > home or GameState.is_week_complete()):
		ask()


func _on_objective_completed(index: int, _title: String) -> void:
	if GameState.objective_id(index) == "home" and not asked:
		get_tree().create_timer(4.0).timeout.connect(ask)


# --- Asking --------------------------------------------------------------------------------

## The one-time question: would you like a reminder?
func ask() -> void:
	if asked or _prompt != null or not is_inside_tree():
		return
	_prompt = CanvasLayer.new()
	_prompt.layer = 40
	_prompt.name = "ReminderPrompt"
	add_child(_prompt)
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(620, 0)
	panel.add_theme_stylebox_override("panel", UiTheme._box(Color(0.15, 0.11, 0.08, 0.98), 14))
	_prompt.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	box.add_child(UiTheme.label("A little reminder?", 26, UiTheme.ACCENT))
	var text := UiTheme.label("Your village keeps living while you're away. Want a gentle reminder when tomorrow's gift is ready? At most once a day, and you can turn it off in Settings.", 19)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size = Vector2(590, 0)
	box.add_child(text)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	var yes := UiTheme.button("Yes, remind me", 290)
	yes.name = "Yes"
	yes.pressed.connect(func(): answer(true))
	row.add_child(yes)
	var no := UiTheme.button("No thanks", 290)
	no.name = "No"
	no.pressed.connect(func(): answer(false))
	row.add_child(no)


func answer(yes: bool) -> void:
	asked = true
	if _prompt:
		_prompt.queue_free()
		_prompt = null
	set_enabled(yes)
	if yes:
		GameManager.notify("Reminder on. See you tomorrow!")


func is_asking() -> bool:
	return _prompt != null


func set_enabled(on: bool) -> void:
	enabled = on
	asked = true
	if on and _plugin and not _plugin.call("can_notify"):
		_plugin.call("request_permission")
	if not on:
		cancel_all()
	_save()
	changed.emit()


# --- Scheduling -----------------------------------------------------------------------------

## Plans (and on Android, schedules) tomorrow's reminder. Returns the plan.
func schedule_next(now: float = -1.0) -> Dictionary:
	last_plan = {}
	if not enabled:
		return {}
	var plan := next_reminder(now if now >= 0.0 else Time.get_unix_time_from_system())
	last_plan = plan
	if _plugin:
		_plugin.call("schedule", ID_DAILY, String(plan["title"]), String(plan["text"]), int(plan["delay"]))
	return plan


func cancel_all() -> void:
	if _plugin:
		_plugin.call("cancel", ID_DAILY)


## When and what tomorrow's reminder would be, put away at `now` (unix).
func next_reminder(now: float) -> Dictionary:
	var day := 86400.0
	# Not before the next daily gift (days are UTC days) nor too soon.
	var next_gift: float = (floor(now / day) + 1.0) * day + 600.0
	var at := maxf(now + MIN_GAP_HOURS * 3600.0, next_gift)
	# Only at a friendly local hour.
	var hour := local_hour(at)
	if hour < EARLIEST_HOUR:
		at += (EARLIEST_HOUR - hour) * 3600.0
	elif hour >= LATEST_HOUR:
		at += (24.0 - hour + EARLIEST_HOUR) * 3600.0
	var text := message(int(floor(at / day)))
	return {"at": at, "delay": int(at - now), "title": TITLE, "text": text}


## The local hour (0-24) at unix time `t`.
static func local_hour(t: float) -> float:
	var local := float(Time.get_unix_time_from_datetime_dict(Time.get_datetime_dict_from_system(false)))
	var utc := float(Time.get_unix_time_from_datetime_dict(Time.get_datetime_dict_from_system(true)))
	return fposmod((t + (local - utc)) / 3600.0, 24.0)


## The reminder's words for day `day`: a streak to keep first, then a
## villager's gift waiting, otherwise a friendly line that changes daily.
func message(day: int) -> String:
	var gift := DailyGift.instance
	if gift and gift.streak >= 2:
		return "Keep your %d-day streak going: your daily gift is ready." % (gift.streak + 1)
	var giver := _house_gift_giver()
	if giver != "":
		return "%s has something for you from their work. Come and see!" % giver
	var name_ := _villager_name(day)
	var lines := [
		"%s is wondering where you are. Your daily gift is waiting." % name_,
		"The village kept living while you were away. Come and see what's new!",
		"Your daily gift is ready, and %s saved you a seat by the fire." % name_,
	]
	return String(lines[posmod(day, lines.size())])


func _house_gift_giver() -> String:
	for record: Dictionary in GameState.structures:
		if Population.is_given_house(record) and WorldClock.day + 1 - int(record.get("gift_day", WorldClock.day)) >= HomeLife.GIFT_EVERY_DAYS:
			var owner := Population.get_person(String(Population.home_owners.get(Population.cottage_home_id(record), "")))
			if owner and owner.is_resident():
				return owner.first_name
	return ""


func _villager_name(day: int) -> String:
	var names: Array = []
	for v in GameManager.villagers:
		if is_instance_valid(v) and v.person and v.person.is_resident() and v.person.founder:
			names.append(v.data.display_name)
	return String(names[posmod(day, names.size())]) if not names.is_empty() else "Everyone"


# --- Save --------------------------------------------------------------------------------------

func _load() -> void:
	if not persist:
		return
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) == OK:
		enabled = bool(config.get_value("reminders", "enabled", false))
		asked = bool(config.get_value("reminders", "asked", false))


func _save() -> void:
	if not persist:
		return
	var config := ConfigFile.new()
	config.set_value("reminders", "enabled", enabled)
	config.set_value("reminders", "asked", asked)
	config.save(SAVE_PATH)
