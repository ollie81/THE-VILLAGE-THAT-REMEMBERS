class_name DailyGift
extends Node
## A small welcome gift on the first visit of each real-world day.
##
## - Days are UTC calendar days (in Rwanda a new one starts at 02:00), so
##   changing the phone's time zone can't produce a second gift.
## - Setting the clock back is noticed (the latest time ever seen is kept)
##   and gives nothing until real time catches up. Setting it forward only
##   takes tomorrow's gift early.
## - Missing days never costs anything: gifts follow your number of visits,
##   not a streak, so they just carry on where they left off.
## - The record lives in the save and is signed, so editing it by hand
##   doesn't produce gifts either (an edited record just waits for tomorrow).

signal claimed(gift: Dictionary)

const DAY_SECONDS := 86400
## The clock may wobble a little (network time corrections) without counting
## as being set back.
const CLOCK_TOLERANCE := 600.0
const SALT := "village-remembers:daily-gift:v1"
## A signed copy of the record outside the save, so starting the village over
## ("Forget everything") doesn't hand out a second gift the same day.
const MIRROR_PATH := "user://welcome_gift.cfg"

## Seven gifts in turn, by visit number. Each comes from someone in the village.
const CALENDAR := [
	{"items": {&"food": 3}, "text": "%s left a loaf of warm bread at your door."},
	{"items": {&"wood": 5}, "text": "%s stacked some firewood by your path."},
	{"items": {&"herbs": 3}, "text": "%s picked you a bundle of fresh herbs."},
	{"items": {&"stone": 4}, "text": "%s found some good stones by the river for you."},
	{"items": {&"food": 2, &"herbs": 2}, "text": "%s brought you honey cakes and mint tea."},
	{"items": {&"wood": 4, &"stone": 3}, "text": "%s had spare planks and stone from a job."},
	{"items": {&"wood": 8, &"stone": 5, &"food": 4}, "text": "The whole village chipped in: a week of visits deserves a basket like this!"},
]

static var instance: DailyGift

## Disabled by tests that count resources exactly.
static var enabled: bool = true
## Tests switch this off so they never touch the player's files.
static var persist: bool = true

var claims: int = 0
var last_claim_day: int = -1
var last_claim_unix: float = 0.0
## The latest clock time ever seen (to notice the clock being set back).
var high_unix: float = 0.0
## Why the last check gave nothing ("" after a gift), for tests and debugging.
var last_reason: String = ""


func _ready() -> void:
	name = "DailyGift"
	instance = self
	_merge(_read_mirror())


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _notification(what: int) -> void:
	# Coming back to the app on a new day also counts as a first visit.
	if what == NOTIFICATION_APPLICATION_RESUMED and is_inside_tree():
		try_claim.call_deferred()


static func day_number(unix: float) -> int:
	return int(floor(unix / DAY_SECONDS))


## Gives today's gift if it hasn't been given yet. Returns the gift ({} if none).
func try_claim(now_unix: float = -1.0) -> Dictionary:
	if not enabled:
		last_reason = "disabled"
		return {}
	var now := now_unix if now_unix >= 0.0 else Time.get_unix_time_from_system()
	var gift := check(now)
	if gift.is_empty():
		return {}
	for resource in gift["items"]:
		GameState.add(resource, int(gift["items"][resource]))
	GameManager.notify("Welcome back! %s  (+%s)" % [gift["text"], GameState.cost_text(gift["items"])])
	Sounds.play("built", null, -6.0)
	SaveService.save_game()
	claimed.emit(gift)
	return gift


## The claim rules, without giving anything (tests call this with any time).
func check(now: float) -> Dictionary:
	now = floor(now)  # whole seconds survive the save exactly (the signature needs that)
	if now + CLOCK_TOLERANCE < high_unix:
		last_reason = "clock set back"
		return {}
	high_unix = maxf(high_unix, now)
	var today := day_number(now)
	if today <= last_claim_day:
		last_reason = "already claimed today"
		return {}
	claims += 1
	last_claim_day = today
	last_claim_unix = now
	last_reason = ""
	_write_mirror()
	var entry: Dictionary = CALENDAR[(claims - 1) % CALENDAR.size()]
	var text := String(entry["text"])
	if text.contains("%s"):
		text = text % _giver_name()
	return {"items": entry["items"], "text": text, "visit": claims}


## Whoever is around to leave the gift (a founder if possible).
func _giver_name() -> String:
	var names: Array = []
	for villager in GameManager.villagers:
		if is_instance_valid(villager) and not villager.is_visitor():
			names.append(villager.data.display_name)
	if names.is_empty():
		return "A neighbour"
	return String(names[(claims - 1) % names.size()])


# --- Save ---------------------------------------------------------------------------

func to_dict() -> Dictionary:
	var data := {"claims": claims, "last_day": last_claim_day, "last_unix": last_claim_unix, "high_unix": high_unix}
	data["sig"] = _signature(data)
	return data


func from_dict(data: Dictionary) -> void:
	if data.is_empty():
		return
	var mirror := {"last_day": last_claim_day, "last_unix": last_claim_unix, "high_unix": high_unix}
	var fields := {"claims": int(data.get("claims", 0)), "last_day": int(data.get("last_day", -1)),
		"last_unix": float(data.get("last_unix", 0.0)), "high_unix": float(data.get("high_unix", 0.0))}
	claims = fields["claims"]
	if String(data.get("sig", "")) != _signature(fields):
		# Edited by hand: keep the visit count but treat today as claimed.
		var now: float = floor(Time.get_unix_time_from_system())
		last_claim_day = day_number(now)
		last_claim_unix = now
		high_unix = maxf(now, float(fields["high_unix"]))
		last_reason = "save edited"
		return
	last_claim_day = fields["last_day"]
	last_claim_unix = fields["last_unix"]
	high_unix = fields["high_unix"]
	_merge(mirror)


static func _signature(fields: Dictionary) -> String:
	var text := "%s|%d|%d|%.3f|%.3f" % [SALT, int(fields["claims"]), int(fields["last_day"]),
		float(fields["last_unix"]), float(fields["high_unix"])]
	return text.sha256_text()


## Keeps the later of two records (the save and the mirror file).
func _merge(other: Dictionary) -> void:
	if other.is_empty():
		return
	last_claim_day = maxi(last_claim_day, int(other.get("last_day", -1)))
	last_claim_unix = maxf(last_claim_unix, float(other.get("last_unix", 0.0)))
	high_unix = maxf(high_unix, float(other.get("high_unix", 0.0)))


func _read_mirror() -> Dictionary:
	if not persist:
		return {}
	var config := ConfigFile.new()
	if config.load(MIRROR_PATH) != OK:
		return {}
	var fields := {"claims": 0, "last_day": int(config.get_value("gift", "last_day", -1)),
		"last_unix": float(config.get_value("gift", "last_unix", 0.0)), "high_unix": float(config.get_value("gift", "high_unix", 0.0))}
	if String(config.get_value("gift", "sig", "")) != _signature(fields):
		return {}
	return fields


func _write_mirror() -> void:
	if not persist:
		return
	var fields := {"claims": 0, "last_day": last_claim_day, "last_unix": last_claim_unix, "high_unix": high_unix}
	var config := ConfigFile.new()
	for key in ["last_day", "last_unix", "high_unix"]:
		config.set_value("gift", key, fields[key])
	config.set_value("gift", "sig", _signature(fields))
	config.save(MIRROR_PATH)
