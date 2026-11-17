extends Node
## Central registry and high-level game state: who is in the village, which
## camera mode is active and whether a conversation is running.
## Systems talk to each other through these signals instead of hard references.

signal camera_mode_changed(mode: int)
signal villager_registered(villager: Node)
signal villager_selected(villager: Node)
## `conversation` is a Conversation (lines, then choices).
signal conversation_started(villager: Node, conversation: RefCounted)
## A choice changed how a villager feels about the player.
signal opinion_changed(villager: Node, affection: float, trust: float)
## One villager told another about something the player did.
signal gossip_shared(speaker: Node, listener: Node, story: String)
signal conversation_ended(villager: Node)
signal interaction_focus_changed(target: Node)
## A short message for the player (shown by the HUD).
signal notice(message: String)

enum CameraMode { EXPLORATION, MANAGEMENT }

const PLAYER_ID := "player"

var camera_mode: int = CameraMode.EXPLORATION
# Untyped on purpose: these hold PlayerController / Villager instances and are
# called duck-typed so this autoload has no hard class dependencies.
var player = null
var villagers: Array = []
var selected_villager = null
var conversation_partner = null
## Who is talking right now (differs from the partner in group scenes).
var speaker = null
## True for scenes with several speakers (the village meeting): the camera
## frames whoever is speaking from across the circle instead of a close-up.
var group_scene: bool = false

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


func notify(message: String) -> void:
	notice.emit(message)


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
	speaker = villager
	group_scene = false
	villager.begin_interaction(player)
	player.model.set_expression(&"happy", 0.6)
	var conversation := DialogueService.build_conversation(villager, PLAYER_ID)
	villager.mind.record_interaction(PLAYER_ID, "conversation", WorldClock.day, WorldClock.time_of_day)
	GameState.check_objectives()
	conversation_started.emit(villager, conversation)
	return true


## Plays a prepared conversation (e.g. the village meeting) without the
## usual greeting and topics. Lines may switch speaker with "@id ".
func start_scene(villager, conversation, group: bool = false) -> bool:
	if is_in_conversation() or villager == null:
		return false
	conversation_partner = villager
	speaker = villager
	group_scene = group
	villager.begin_interaction(player)
	conversation_started.emit(villager, conversation)
	return true


func end_conversation() -> void:
	if conversation_partner == null:
		return
	var villager = conversation_partner
	conversation_partner = null
	speaker = null
	group_scene = false
	_conversation_ended_msec = Time.get_ticks_msec()
	villager.end_interaction()
	villager.model.set_talking(false)
	villager.model.set_expression(&"neutral")
	if player:
		player.model.set_expression(&"neutral")
	conversation_ended.emit(villager)
