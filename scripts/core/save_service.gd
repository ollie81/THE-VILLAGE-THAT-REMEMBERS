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
		"saved_unix": Time.get_unix_time_from_system(),
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("Could not write save file: %s" % FileAccess.get_open_error())
		return
	file.store_string(JSON.stringify(_data, "\t"))


func delete_save() -> void:
	_data = {}
	GameState.reset()
	Population.reset()
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


func _read_from_disk() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary and int(parsed.get("version", 0)) == SAVE_VERSION:
		_data = parsed
	else:
		push_warning("Ignoring incompatible or corrupt save file.")
