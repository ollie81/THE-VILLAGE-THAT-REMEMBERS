class_name Interactable
extends Area3D
## Marks something the player can interact with. The owner sets `handler`
## (any object with `can_interact(actor) -> bool`) and listens to `interacted`.
## Future interactables (doors, crops, items, notice boards) reuse this.

signal interacted(actor: Node)

const LAYER_INTERACTION := 8

var prompt_verb: String = "Talk to"
var display_name: String = ""
var enabled: bool = true
## Untyped on purpose: any object implementing can_interact(actor).
var handler = null


func _ready() -> void:
	collision_layer = LAYER_INTERACTION
	collision_mask = 0
	monitoring = false
	monitorable = true
	var sphere := SphereShape3D.new()
	sphere.radius = 0.9
	var shape := CollisionShape3D.new()
	shape.shape = sphere
	shape.position = Vector3(0, 1.0, 0)
	add_child(shape)


func is_available() -> bool:
	if not enabled:
		return false
	if handler != null and handler.has_method("can_interact"):
		return bool(handler.can_interact(GameManager.player))
	return true


func get_prompt() -> String:
	return "%s %s" % [prompt_verb, display_name]


func interact(actor: Node) -> bool:
	if not is_available():
		return false
	interacted.emit(actor)
	return true
