class_name Fishing
extends Node3D
## Fishing at the river. With a rod (made at the workshop), stand on the bank
## or the bridge and tap Fish: you cast, wait for a bite, and when "Bite!"
## shows you have a moment to tap Reel. A catch is 2 food (a trout, a perch,
## sometimes something bigger). Wander off and the line comes in.

enum Stage { IDLE, WAITING, BITE }

const BITE_WINDOW := 1.6
const CATCH_FOOD := 2
const FISH := ["a speckled trout", "a fat perch", "a silver dace", "a little bream"]

static var instance: Fishing

var stage: int = Stage.IDLE
var interactable: Interactable
var _water := Vector3.ZERO
var _timer: float = 0.0
var _check: float = 0.0
var _rng := RandomNumberGenerator.new()
var _cast_from := Vector3.ZERO


func _ready() -> void:
	name = "Fishing"
	instance = self
	_rng.randomize()
	interactable = Interactable.new()
	interactable.radius = 1.4
	interactable.handler = self
	interactable.enabled = false
	interactable.interacted.connect(func(actor): use(actor))
	add_child(interactable)


func _exit_tree() -> void:
	if instance == self:
		instance = null


static func has_rod() -> bool:
	return bool(GameState.get_flag(&"has_rod"))


## The nearest water in front of someone on the bank or the bridge (or INF).
static func water_near(at: Vector3) -> Vector3:
	var center := VillageLayout.river_center_x(at.z)
	var off := at.x - center
	var on_bridge := VillageLayout.is_on_bridge(at.x, at.z)
	if not on_bridge and (absf(off) < VillageLayout.RIVER_HALF_WIDTH - 0.2 or absf(off) > VillageLayout.RIVER_WALL_OFFSET + 1.8):
		return Vector3.INF
	var side := signf(off) if absf(off) > 0.1 else 1.0
	var x := center + side * VillageLayout.RIVER_HALF_WIDTH * 0.6
	if on_bridge:
		x = at.x
	return Vector3(x, at.y - 0.6, at.z + (1.6 if on_bridge else 0.0))


func can_interact(_actor) -> bool:
	return interactable.enabled


func get_interaction_verb() -> String:
	match stage:
		Stage.WAITING:
			return "Wait"
		Stage.BITE:
			return "Reel"
	return "Fish"


func get_interaction_prompt() -> String:
	if not has_rod():
		return "Fishing spot  (make a fishing rod at the workshop first)"
	match stage:
		Stage.WAITING:
			return "Waiting for a bite..."
		Stage.BITE:
			return "Bite! Tap Reel now!"
	return "Fish here  (+%d food a catch)" % CATCH_FOOD


func _physics_process(delta: float) -> void:
	var player = GameManager.player
	if player == null:
		return
	if stage != Stage.IDLE:
		_timer -= delta
		if player.global_position.distance_to(_cast_from) > 2.5:
			_end("You walk away and reel in your line.")
		elif stage == Stage.WAITING and _timer <= 0.0:
			stage = Stage.BITE
			_timer = BITE_WINDOW
			Sounds.play("splash", _water, -2.0)
			GameManager.notify("Bite! Tap Reel now!")
		elif stage == Stage.BITE and _timer <= 0.0:
			_end("It got away! Tap Fish to try again.")
		return
	_check -= delta
	if _check > 0.0:
		return
	_check = 0.25
	var inside: bool = Interiors.instance != null and Interiors.instance.is_inside()
	var water := Vector3.INF if inside else water_near(player.global_position)
	interactable.enabled = water != Vector3.INF
	if interactable.enabled:
		_water = water
		global_position = player.global_position + (water - player.global_position).normalized() * 0.8


func use(actor) -> void:
	if not has_rod():
		GameManager.notify("You need a fishing rod. Make one at the workshop bench (3 wood, 1 herbs).")
		return
	match stage:
		Stage.IDLE:
			stage = Stage.WAITING
			_timer = _rng.randf_range(2.5, 5.5)
			_cast_from = actor.global_position
			if actor.has_method("perform_action"):
				actor.perform_action(&"work", 0.7, _water, &"fishing_rod")
			if actor.get("tools") and actor.tools:
				actor.tools.hold(&"fishing_rod", 12.0)
			Sounds.play("swing", null, -10.0)
		Stage.WAITING:
			GameManager.notify("Patience... wait for the bite.")
		Stage.BITE:
			var fish: String = FISH[_rng.randi_range(0, FISH.size() - 1)]
			GameState.add(&"food", CATCH_FOOD)
			GameState.increment(&"fish_caught")
			Sounds.play("pickup", null, -2.0)
			FloatingText.spawn(get_parent(), actor.global_position + Vector3(0, 2.2, 0), "+%d Food" % CATCH_FOOD)
			_end("You caught %s!  (+%d food)" % [fish, CATCH_FOOD])


func _end(message: String) -> void:
	stage = Stage.IDLE
	var player = GameManager.player
	if player and player.get("tools") and player.tools:
		player.tools.hold(&"", 0.0)
	GameManager.notify(message)
