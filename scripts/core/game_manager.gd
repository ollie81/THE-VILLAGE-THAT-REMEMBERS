extends Node
## Central registry and high-level game state: who is in the village, which
## camera mode is active and whether a conversation is running.
## Systems talk to each other through these signals instead of hard references.

signal camera_mode_changed(mode: int)
signal villager_registered(villager: Node)
signal villager_selected(villager: Node)
signal conversation_started(villager: Node, lines: Array[String])
signal conversation_ended(villager: Node)
signal interaction_focus_changed(target: Node)

enum CameraMode { EXPLORATION, MANAGEMENT }

const PLAYER_ID := "player"

var camera_mode: int = CameraMode.EXPLORATION
# Untyped on purpose: these hold PlayerController / Villager instances and are
# called duck-typed so this autoload has no hard class dependencies.
var player = null
var villagers: Array = []
var selected_villager = null
var conversation_partner = null

var _conversation_ended_msec: int = -100000


## Clears per-scene references before the world is rebuilt (e.g. after a reset).
func reset() -> void:
	player = null
	villagers.clear()
	selected_villager = null
	conversation_partner = null
	camera_mode = CameraMode.EXPLORATION


func register_player(node) -> void:
	player = node


func register_villager(villager) -> void:
	if villager in villagers:
		return
	villagers.append(villager)
	villager_registered.emit(villager)


func unregister_villager(villager) -> void:
	villagers.erase(villager)


func get_villager(id: StringName):
	for villager in villagers:
		if villager.get_villager_id() == id:
			return villager
	return null


func is_in_conversation() -> bool:
	return conversation_partner != null


## Prevents the key press that closes a conversation from immediately opening
## a new one.
func can_start_interaction() -> bool:
	return not is_in_conversation() and Time.get_ticks_msec() - _conversation_ended_msec > 400


# --- Camera -------------------------------------------------------------------

func toggle_camera_mode() -> void:
	if camera_mode == CameraMode.EXPLORATION:
		set_camera_mode(CameraMode.MANAGEMENT)
	else:
		set_camera_mode(CameraMode.EXPLORATION)


func set_camera_mode(mode: int) -> void:
	if mode == camera_mode or is_in_conversation():
		return
	camera_mode = mode
	if mode == CameraMode.EXPLORATION:
		select_villager(null)
	camera_mode_changed.emit(mode)


func select_villager(villager) -> void:
	selected_villager = villager
	villager_selected.emit(villager)


# --- Conversations ------------------------------------------------------------

func start_conversation(villager) -> bool:
	if is_in_conversation() or villager == null:
		return false
	if not villager.can_interact(player):
		return false
	conversation_partner = villager
	villager.begin_interaction(player)
	var lines: Array[String] = DialogueService.build_greeting(villager, PLAYER_ID)
	villager.mind.record_interaction(PLAYER_ID, "conversation", WorldClock.day, WorldClock.time_of_day)
	conversation_started.emit(villager, lines)
	return true


func end_conversation() -> void:
	if conversation_partner == null:
		return
	var villager = conversation_partner
	conversation_partner = null
	_conversation_ended_msec = Time.get_ticks_msec()
	villager.end_interaction()
	conversation_ended.emit(villager)
