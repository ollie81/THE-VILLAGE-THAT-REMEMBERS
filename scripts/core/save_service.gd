extends Node
## Offline-first persistence. Stores the clock, the player's position and every
## villager's mind (memories, familiarity) in a local JSON file so that the
## village keeps remembering between sessions.

const SAVE_PATH := "user://savegame.json"
const SAVE_VERSION := 1
const AUTOSAVE_INTERVAL := 60.0

## Disabled by automated tests so they never touch the player's save.
var enabled: bool = true

var _data: Dictionary = {}
var _autosave_timer: float = 0.0


func _ready() -> void:
	_read_from_disk()


func _process(delta: float) -> void:
	if not enabled or GameManager.player == null:
		return
	_autosave_timer += delta
	if _autosave_timer >= AUTOSAVE_INTERVAL:
		_autosave_timer = 0.0
		save_game()


func _notification(what: int) -> void:
	# Android may kill a paused app without warning, so save when backgrounded.
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		save_game()


func has_save() -> bool:
	return not _data.is_empty()


## Restores inventory, structures and objectives. Called before the world is
## built so saved structures and depleted resources appear correctly.
func apply_saved_game_state() -> void:
	if not enabled or _data.is_empty():
		return
	var state: Dictionary = _data.get("game_state", {})
	if not state.is_empty():
		GameState.from_dict(state)


## Restores everyone's life records (who lives here, families, history).
## Called before villagers are spawned. A new game starts empty; Main then
## adds the five founders.
func apply_saved_population() -> void:
	Population.reset()
	if not enabled or _data.is_empty():
		return
	var saved: Dictionary = _data.get("population", {})
	if not saved.is_empty():
		Population.from_dict(saved)


## A saved section by name ({} if none or saving is off).
func section(key: String) -> Dictionary:
	if not enabled:
		return {}
	var value: Variant = _data.get(key, {})
	return value if value is Dictionary else {}


## Real seconds since the game was last saved (0 for a new game).
func seconds_since_save() -> float:
	if not enabled or not _data.has("saved_unix"):
		return 0.0
	return maxf(Time.get_unix_time_from_system() - float(_data["saved_unix"]), 0.0)


## Saved mind (memories, opinions) of one villager, for people whose bodies
## are spawned after loading.
func villager_state(id: String) -> Dictionary:
	if not enabled:
		return {}
	var states: Dictionary = _data.get("villagers", {})
	var state: Variant = states.get(id, {})
	return state if state is Dictionary else {}


## Restores the saved time of day. Called before villagers are placed so they
## appear where their schedule puts them at that time.
func apply_saved_clock() -> void:
	if not enabled or _data.is_empty():
		return
	var clock: Dictionary = _data.get("clock", {})
	if not clock.is_empty():
		WorldClock.from_dict(clock)


## Restores loaded state onto the freshly built world. Called once by Main.
func apply_loaded_state() -> void:
	if not enabled or _data.is_empty():
		return
	var player_state: Dictionary = _data.get("player", {})
	if GameManager.player and not player_state.is_empty():
		GameManager.player.apply_save_data(player_state)
	var villager_states: Dictionary = _data.get("villagers", {})
	for villager in GameManager.villagers:
		var key := String(villager.get_villager_id())
		if villager_states.has(key):
			villager.apply_save_data(villager_states[key])


func save_game() -> void:
	if not enabled or GameManager.player == null:
		return
	# Keep saved minds of people whose bodies haven't spawned yet.
	var villager_states: Dictionary = (_data.get("villagers", {}) as Dictionary).duplicate() if _data.get("villagers", {}) is Dictionary else {}
	for id in villager_states.keys():
		var person := Population.get_person(String(id))
		if person == null or not person.is_present():
			villager_states.erase(id)
	for villager in GameManager.villagers:
		villager_states[String(villager.get_villager_id())] = villager.get_save_data()
	_data = {
		"version": SAVE_VERSION,
		"clock": WorldClock.to_dict(),
		"player": GameManager.player.get_save_data(),
		"villagers": villager_states,
		"game_state": GameState.to_dict(),
		"population": Population.to_dict(),
		"requests": RequestBoard.instance.to_dict() if RequestBoard.instance else {},
		"daily_gift": DailyGift.instance.to_dict() if DailyGift.instance else (_data.get("daily_gift", {}) if _data.get("daily_gift", {}) is Dictionary else {}),
		"festival": Festival.instance.to_dict() if Festival.instance else {},
		"stories": VillageStories.instance.to_dict() if VillageStories.instance else {},
		"thornwood": Thornwood.instance.to_dict() if Thornwood.instance else {},
		"saved_unix": Time.get_unix_time_from_system(),
	}
	if not write_safely(SAVE_PATH, JSON.stringify(_data, "\t")):
		push_error("SaveService: could not write the save file %s." % SAVE_PATH)


func delete_save() -> void:
	_data = {}
	GameState.reset()
	Population.reset()
	for path in [SAVE_PATH, SAVE_PATH + ".bak", SAVE_PATH + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _read_from_disk() -> void:
	_data = read_safely(SAVE_PATH)


## Writes `text` so that a phone killing the app mid-write can't lose the
## save: it goes to a .tmp file first, is read back to check it, then the old
## save becomes the .bak and the new one takes its place.
static func write_safely(path: String, text: String) -> bool:
	var tmp := path + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		push_error("SaveService: can't open %s (error %d)." % [tmp, FileAccess.get_open_error()])
		return false
	file.store_string(text)
	file.close()
	if FileAccess.get_file_as_string(tmp).length() != text.length():
		push_error("SaveService: %s was not written completely." % tmp)
		return false
	var dir := DirAccess.open(path.get_base_dir())
	if dir == null:
		push_error("SaveService: can't open the save folder.")
		return false
	if FileAccess.file_exists(path):
		if FileAccess.file_exists(path + ".bak"):
			dir.remove(path.get_file() + ".bak")
		dir.rename(path.get_file(), path.get_file() + ".bak")
	var err := dir.rename(tmp.get_file(), path.get_file())
	if err != OK:
		push_error("SaveService: can't move the new save into place (error %d)." % err)
		return false
	return true


## The save at `path`, or its backup if the save is missing, cut short or from
## an older version ({} if neither is usable).
static func read_safely(path: String) -> Dictionary:
	for candidate in [path, path + ".bak"]:
		if not FileAccess.file_exists(candidate):
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(candidate))
		if parsed is Dictionary and int(parsed.get("version", 0)) == SAVE_VERSION:
			if candidate != path:
				push_warning("SaveService: the save was unreadable; restored the backup from the previous save.")
			return parsed
		push_warning("SaveService: ignoring an unreadable or incompatible save at %s." % candidate)
	return {}
