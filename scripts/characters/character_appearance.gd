class_name CharacterAppearance
extends Resource
## Visual description of a person. CharacterModel turns this into a
## low-poly body. Kept separate from personality/identity data so future
## systems (children inheriting looks, ageing) can generate new appearances.

@export var skin_color: Color = Color(0.85, 0.66, 0.5)
@export var hair_color: Color = Color(0.25, 0.16, 0.1)
@export var shirt_color: Color = Color(0.4, 0.5, 0.6)
@export var pants_color: Color = Color(0.3, 0.27, 0.24)
@export var accent_color: Color = Color(0.7, 0.5, 0.3)
@export var shoe_color: Color = Color(0.25, 0.17, 0.1)
## short, long, bun, ponytail, curly, balding
@export var hair_style: String = "short"
## straw_hat, tool_belt, flower, beard, long_beard, scarf, satchel, apron,
## headband, cloak, backpack, glasses
@export var accessories: PackedStringArray = PackedStringArray()
@export_range(0.8, 1.2) var height_scale: float = 1.0
@export_range(0.8, 1.3) var build_width: float = 1.0
## Forward lean of the upper body (0 = upright). Used for elderly characters.
@export_range(0.0, 0.4) var stoop: float = 0.0


func has_accessory(accessory: String) -> bool:
	return accessories.has(accessory)
