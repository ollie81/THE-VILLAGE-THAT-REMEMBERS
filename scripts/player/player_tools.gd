class_name PlayerTools
extends Node
## Puts the right tool in the player's hand for each job: an axe to chop, a
## pickaxe to mine, a hammer to build, a hoe to plant, a watering can at the
## well. The tool is held on the right-hand bone for as long as the action
## lasts (the sword is put away meanwhile), so you never chop with bare hands.

var player: PlayerController
var _attachment: BoneAttachment3D
var _meshes: Dictionary = {}  # kind -> Node3D
var current: StringName = &""
var _timer: float = 0.0


func _ready() -> void:
	name = "PlayerTools"
	player = get_parent() as PlayerController


func _hand() -> BoneAttachment3D:
	if _attachment == null and player and player.model and player.model.skeleton:
		_attachment = BoneAttachment3D.new()
		_attachment.name = "ToolHand"
		_attachment.bone_name = "RightHand"
		player.model.skeleton.add_child(_attachment)
	return _attachment


## Shows `kind` in the hand for `seconds` ("" hides it).
func hold(kind: StringName, seconds: float) -> void:
	var hand := _hand()
	if hand == null:
		return
	for k in _meshes:
		_meshes[k].visible = false
	current = kind
	_timer = seconds
	if kind == &"":
		_show_sword(true)
		return
	if not _meshes.has(kind):
		var mesh: Node3D = player.model._create_tool(String(kind))
		if mesh == null:
			current = &""
			return
		hand.add_child(mesh)
		_meshes[kind] = mesh
	_meshes[kind].visible = true
	_show_sword(false)


func _show_sword(visible_now: bool) -> void:
	var combat := player.combat if player else null
	if combat and combat._sword:
		combat._sword.visible = visible_now and PlayerCombat.is_armed()


func _process(delta: float) -> void:
	if current == &"":
		return
	_timer -= delta
	if _timer <= 0.0:
		hold(&"", 0.0)
