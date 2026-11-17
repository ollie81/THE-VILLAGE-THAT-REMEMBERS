class_name FaceExpressions
extends RefCounted
## Facial expression definitions shared by every character.
##
## A face is described by a handful of controls (0..1). Each expression is a
## set of control values; HumanoidMeshBuilder sculpts the head once per
## expression and stores the difference as a blend shape, so expressions are
## reusable for every character and cost nothing until they are used.
##
## Controls:
##   smile, frown       mouth corners up / down
##   smirk              one-sided smile (left corner)
##   open               jaw and lips open
##   round              lips pushed into an "o"
##   brow_up            both brows raised
##   brow_down          inner brows pulled down and together (anger, focus)
##   brow_sad           inner brows raised (sadness, worry)
##   squint             lids narrowed, cheeks raised
##   wide               lids wide open
##   blink              lids closed

const EXPRESSIONS := {
	&"neutral": {},
	&"happy": {"smile": 0.85, "squint": 0.3, "brow_up": 0.15},
	&"laughing": {"smile": 1.0, "open": 0.75, "squint": 0.85, "brow_up": 0.35},
	&"sad": {"frown": 0.85, "brow_sad": 1.0, "squint": 0.3},
	&"angry": {"brow_down": 1.0, "frown": 0.45, "squint": 0.45},
	&"surprised": {"brow_up": 1.0, "wide": 1.0, "open": 0.65, "round": 0.8},
	&"worried": {"brow_sad": 0.8, "brow_up": 0.3, "frown": 0.4, "wide": 0.35, "open": 0.06},
}

## Blend shapes baked into every head, in this order. "blink" and "talk" are
## layered on top of the current expression by CharacterModel.
const SHAPES: Array[StringName] = [&"happy", &"laughing", &"sad", &"angry", &"surprised", &"worried", &"blink", &"talk"]

const EXPRESSION_NAMES: Array[StringName] = [&"neutral", &"happy", &"laughing", &"sad", &"angry", &"surprised", &"worried"]


## The face a character makes when nothing in particular is happening.
static func resting(look: CharacterAppearance) -> Dictionary:
	return look.resting_face.duplicate()


## Control values for a blend shape. Expressions replace the resting face;
## blink and talk add to it (so they layer over any expression).
static func controls_for(shape: StringName, look: CharacterAppearance) -> Dictionary:
	match shape:
		&"blink":
			var blink := resting(look)
			blink["blink"] = 1.0
			return blink
		&"talk":
			var talk := resting(look)
			talk["open"] = float(talk.get("open", 0.0)) + 0.45
			return talk
	return Dictionary(EXPRESSIONS.get(shape, {})).duplicate()
