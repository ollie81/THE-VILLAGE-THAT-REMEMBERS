class_name StructureManager
extends Node3D
## Spawns the player's structures (saved ones on load, new ones as they are
## placed) and lets farm crops grow as game time passes.

static var instance: StructureManager

signal structure_completed(structure: PlacedStructure)

var _last_clock: float = -1.0


func _ready() -> void:
	name = "Structures"
	instance = self
	for record in GameState.structures:
		_spawn(record)
	GameState.structure_added.connect(_spawn)


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _spawn(record: Dictionary) -> PlacedStructure:
	var structure := PlacedStructure.create(record)
	structure.add_to_group("placed_structures")
	structure.completed.connect(func(s): GameManager.notify("%s finished!" % s.get_info()["name"]))
	structure.completed.connect(func(s): structure_completed.emit(s))
	add_child(structure)
	return structure


func structures() -> Array:
	return get_tree().get_nodes_in_group("placed_structures")


func nearest_unfinished(from: Vector3) -> PlacedStructure:
	var best: PlacedStructure = null
	for structure in structures():
		if structure.is_complete():
			continue
		if best == null or structure.global_position.distance_to(from) < best.global_position.distance_to(from):
			best = structure
	return best


func _process(_delta: float) -> void:
	var clock := WorldClock.day * 24.0 + WorldClock.time_of_day
	if _last_clock >= 0.0 and clock > _last_clock:
		var hours := minf(clock - _last_clock, 24.0)
		for structure in structures():
			structure.grow(hours)
	_last_clock = clock
