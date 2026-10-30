class_name CharacterAppearance
extends Resource
## Visual description of a person. HumanoidMeshBuilder turns this into a
## skinned low-poly body. Kept separate from personality/identity data so
## future systems (children inheriting looks, ageing) can generate new
## appearances.

@export_group("Colours")
@export var skin_color: Color = Color(0.85, 0.66, 0.5)
@export var hair_color: Color = Color(0.25, 0.16, 0.1)
@export var eye_color: Color = Color(0.22, 0.14, 0.08)
@export var shirt_color: Color = Color(0.4, 0.5, 0.6)
@export var pants_color: Color = Color(0.3, 0.27, 0.24)
@export var accent_color: Color = Color(0.7, 0.5, 0.3)
@export var shoe_color: Color = Color(0.3, 0.2, 0.12)
## Optional colours; leave fully transparent to reuse shirt / accent colour.
@export var skirt_color: Color = Color(0, 0, 0, 0)
@export var apron_color: Color = Color(0, 0, 0, 0)
@export var hat_color: Color = Color(0, 0, 0, 0)

@export_group("Body")
@export_range(0.85, 1.15) var height_scale: float = 1.0
## General bulk; multiplies shoulder and hip width.
@export_range(0.8, 1.3) var build_width: float = 1.0
@export_range(0.8, 1.25) var shoulder_width: float = 1.0
@export_range(0.8, 1.25) var hip_width: float = 1.0
## 0 = flat chest, 1 = fuller chest.
@export_range(0.0, 1.0) var chest_shape: float = 0.0
## Forward lean of the upper body (0 = upright). Used for elderly characters.
@export_range(0.0, 0.4) var stoop: float = 0.0

@export_group("Face")
@export_range(0.85, 1.15) var face_width: float = 1.0
@export_range(0.8, 1.25) var jaw_width: float = 1.0
## Chin length and prominence.
@export_range(0.7, 1.4) var chin: float = 1.0
@export_range(0.0, 1.0) var cheekbones: float = 0.5
@export_range(0.0, 1.0) var brow_ridge: float = 0.4
@export_range(0.5, 1.8) var brow_thickness: float = 1.0
## How high the brows arch in the middle.
@export_range(0.0, 1.0) var brow_arch: float = 0.4
@export var brow_color: Color = Color(0, 0, 0, 0)
@export_range(0.8, 1.3) var eye_size: float = 1.0
@export_range(0.9, 1.1) var eye_spacing: float = 1.0
## Positive values lift the outer corners (almond eyes).
@export_range(-0.3, 0.3) var eye_tilt: float = 0.0
## Thickness of the dark lash line.
@export_range(0.0, 1.0) var lash_weight: float = 0.4
@export_range(0.8, 1.25) var nose_length: float = 1.0
@export_range(0.8, 1.3) var nose_width: float = 1.0
@export_range(0.0, 1.0) var nose_upturn: float = 0.0
@export_range(0.7, 1.4) var lip_fullness: float = 1.0
@export_range(0.85, 1.2) var mouth_width: float = 1.0
## Age lines: forehead, crow's feet, smile lines.
@export_range(0.0, 1.0) var wrinkles: float = 0.0
@export_range(0.0, 1.0) var freckles: float = 0.0
## Facial controls held when no expression is playing (see FaceExpressions).
@export var resting_face: Dictionary = {}

@export_group("Hair and clothing")
## short, long, bun, ponytail, curly, locs, balding
@export var hair_style: String = "short"
## 0 = shirt tucked in at the waist, 0.3..0.5 = tunic, 1 = ankle-length dress.
@export_range(0.0, 1.0) var tunic_length: float = 0.0
## 0 = short sleeves, 1 = full-length sleeves.
@export_range(0.0, 1.0) var sleeve_length: float = 1.0
## straw_hat, wide_hat, headband, headwrap, flower, earrings, glasses, beard,
## long_beard, scarf, satchel, apron, suspenders, tool_belt, cloak, backpack
@export var accessories: PackedStringArray = PackedStringArray()
## Prop held while working: hammer, hoe, basket, ledger (or empty).
@export var work_tool: String = ""


func has_accessory(accessory: String) -> bool:
	return accessories.has(accessory)
