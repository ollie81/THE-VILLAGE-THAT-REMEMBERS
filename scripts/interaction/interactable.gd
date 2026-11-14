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
## Size of the area the player must reach.
var radius: float = 0.9


func _ready() -> void:
	collision_layer = LAYER_INTERACTION
	collision_mask = 0
	monitoring = false
	monitorable = true
	var sphere := SphereShape3D.new()
	sphere.radius = radius
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


## Handlers can provide live prompts ("Build house (2/6)") through
## get_interaction_prompt() and get_interaction_verb().
func get_prompt() -> String:
	if handler != null and handler.has_method("get_interaction_prompt"):
		return String(handler.get_interaction_prompt())
	return "%s %s" % [prompt_verb, display_name]


## Short label for the on-screen action button ("Talk", "Chop", "Build").
func get_verb() -> String:
	if handler != null and handler.has_method("get_interaction_verb"):
		return String(handler.get_interaction_verb())
	return prompt_verb.get_slice(" ", 0)


func interact(actor: Node) -> bool:
	if not is_available():
		return false
	interacted.emit(actor)
	return true
