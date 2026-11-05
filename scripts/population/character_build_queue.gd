class_name CharacterBuildQueue
extends Node
## Builds character meshes one at a time on a worker thread, so a newcomer's
## face (about half a second of work, longer on a phone) never freezes the
## game. Results come from the offline cache when the person was built before.

## Tests can switch this off to build on the spot.
var threaded: bool = true

var _queue: Array = []  # { look, done: Callable }
var _current: Dictionary = {}
var _task_id: int = -1
var _result: Dictionary = {}


func _ready() -> void:
	# Shared materials must exist before a worker thread asks for them.
	Materials.character_body()
	Materials.character_face()


## Calls `done(meshes)` (a {body, head} dictionary) once the meshes are ready.
func request(look: CharacterAppearance, done: Callable) -> void:
	if not threaded:
		done.call(CharacterModel.build_meshes(look))
		return
	_queue.append({"look": look, "done": done})


func is_busy() -> bool:
	return _task_id != -1 or not _queue.is_empty()


func pending() -> int:
	return _queue.size() + (1 if _task_id != -1 else 0)


func _process(_delta: float) -> void:
	if _task_id != -1:
		if not WorkerThreadPool.is_task_completed(_task_id):
			return
		WorkerThreadPool.wait_for_task_completion(_task_id)
		_task_id = -1
		var done: Callable = _current["done"]
		_current = {}
		CharacterModel.save_to_cache(_result)
		if done.is_valid():
			done.call(_result)
		_result = {}
	if _queue.is_empty():
		return
	_current = _queue.pop_front()
	var look: CharacterAppearance = _current["look"]
	_task_id = WorkerThreadPool.add_task(_build.bind(look), false, "Build character")


## Worker thread: builds without saving (see CharacterModel.build_meshes).
func _build(look: CharacterAppearance) -> void:
	_result = CharacterModel.build_meshes(look, null, false)


func _exit_tree() -> void:
	if _task_id != -1:
		WorkerThreadPool.wait_for_task_completion(_task_id)
		_task_id = -1
