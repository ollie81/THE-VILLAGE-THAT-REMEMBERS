class_name InteractionDetector
extends Area3D
## Lives on the player. Tracks nearby Interactables and picks the best one
## (closest, preferring what the player is facing).

signal focus_changed(target: Interactable)

const RADIUS := 2.6
const MASK_INTERACTION := 8

var focused: Interactable = null


func _ready() -> void:
	name = "InteractionDetector"
	collision_layer = 0
	collision_mask = MASK_INTERACTION
	monitoring = true
	monitorable = false
	var sphere := SphereShape3D.new()
	sphere.radius = RADIUS
	var shape := CollisionShape3D.new()
	shape.shape = sphere
	shape.position = Vector3(0, 1.0, 0)
	add_child(shape)


func _physics_process(_delta: float) -> void:
	var best: Interactable = null
	var best_score := INF
	var facing := Vector3.FORWARD
	var player := get_parent() as PlayerController
	if player:
		facing = player.get_facing()
	for area in get_overlapping_areas():
		var candidate := area as Interactable
		if candidate == null or not candidate.is_available():
			continue
		var to := candidate.global_position - global_position
		to.y = 0.0
		var distance := to.length()
		var alignment := facing.dot(to / distance) if distance > 0.01 else 1.0
		var score := distance - alignment * 0.8
		if score < best_score:
			best_score = score
			best = candidate
	if best != focused:
		focused = best
		focus_changed.emit(best)
		GameManager.interaction_focus_changed.emit(best)


func try_interact(actor: Node) -> bool:
	if focused and is_instance_valid(focused) and focused.is_available():
		return focused.interact(actor)
	return false
