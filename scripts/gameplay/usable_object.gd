class_name UsableObject
extends Node3D
## A world object whose prompt and behaviour are callables (see WorldObjects).

var prompt: Callable
var verb: Callable
var use: Callable


func can_interact(_actor) -> bool:
	return true


func get_interaction_prompt() -> String:
	return String(prompt.call())


func get_interaction_verb() -> String:
	return String(verb.call())
