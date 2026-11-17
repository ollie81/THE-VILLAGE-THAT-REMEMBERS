class_name FurnishMode
extends Node3D
## Placing and arranging furniture.
## - New piece: a see-through copy follows in front of you, green where it
##   fits and red where it doesn't (with the reason). Rotate in quarter turns,
##   then Place (it's paid for then).
## - Arranging: tap any of your pieces to pick it up. Small things (chairs,
##   stools, lamps, plants, crates, barrels) are carried in your hands, with a
##   marker on the floor where they'll go; bigger pieces slide along in front
##   of you. Put it down, turn it, or put it away to place again later.
##   Carrying, you can walk out through a door and put it down outside (if
##   it's an outdoor piece), or in another of your houses.

static var instance: FurnishMode

signal changed

## Snapping for tidy rows of furniture.
const GRID := 0.25
## How far (in quarter metres) the preview may slide to find a spot that fits.
const NEARBY_RINGS := 7

var active: bool = false
var arranging: bool = false
var type: StringName = &""
var moving: Dictionary = {}
var reason: String = ""
var _from: Dictionary = {}  # where a moved piece came from, to put it back on Cancel
var _turns: int = 0
var _yaw_base: float = 0.0
var _position := Vector3.ZERO
var _ghost: Node3D
var _held: Node3D
var _ok_material: StandardMaterial3D
var _bad_material: StandardMaterial3D


func _ready() -> void:
	name = "FurnishMode"
	instance = self
	_ok_material = _material(Color(0.4, 0.95, 0.45, 0.45))
	_bad_material = _material(Color(0.95, 0.35, 0.3, 0.45))


func _exit_tree() -> void:
	if instance == self:
		instance = null


static func _material(colour: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.no_depth_test = false
	return m


## Where furniture goes right now: the house you're in, or outside.
static func current_place() -> String:
	if Interiors.instance and Interiors.instance.is_inside():
		return Interiors.instance.current
	return "outside"


static func origin_of(place: String) -> Vector3:
	return Interiors.ROOM_ORIGIN if place != "outside" else Vector3.ZERO


func set_arranging(on: bool) -> void:
	arranging = on
	changed.emit()


## Starts placing a new `type` (paid when placed), or a stored record.
func start_new(new_type: StringName, stored_record: Dictionary = {}) -> String:
	cancel()
	var info := FurnitureCatalog.info(new_type)
	if info.is_empty():
		return "Unknown furniture"
	if stored_record.is_empty() and not GameState.can_afford(info["cost"]):
		var missing := "%s for a %s" % [GameState.missing_text(info["cost"]), String(info["name"]).to_lower()]
		GameManager.notify(missing + ".")
		return missing
	type = new_type
	moving = stored_record
	_from = {}
	_begin()
	return ""


## Picks up one of your pieces to move it.
func pick_up(piece: FurniturePiece) -> void:
	cancel()
	type = piece.type
	moving = piece.record
	_from = {"place": String(moving["place"]), "pos": (moving["pos"] as Array).duplicate(), "yaw": float(moving.get("yaw", 0.0))}
	Furnishings.instance._despawn(moving)
	_begin()
	Sounds.play("pickup", null, -8.0)


func _begin() -> void:
	active = true
	_turns = 0
	var player = GameManager.player
	_yaw_base = snappedf(player.model.rotation.y + PI, PI * 0.5) if player else 0.0
	if not _from.is_empty():
		_yaw_base = float(_from["yaw"])
	var info := FurnitureCatalog.info(type)
	_ghost = _make_model(type, true)
	add_child(_ghost)
	if bool(info.get("carry", false)) and player:
		_held = _make_model(type, false)
		_held.name = "Carried"
		player.add_child(_held)
	_update()
	changed.emit()


func _make_model(t: StringName, ghost: bool) -> Node3D:
	var built := FurnitureCatalog.build(t)
	var mi := MeshInstance3D.new()
	mi.mesh = (built[0] as MeshBuilder).build(Materials.vertex_color())
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if ghost:
		mi.material_override = _ok_material
	var holder := Node3D.new()
	holder.add_child(mi)
	return holder


func is_carrying() -> bool:
	return active and _held != null


func turn() -> void:
	_turns = (_turns + 1) % 4
	_update()


func current_yaw() -> float:
	return _yaw_base + _turns * PI * 0.5


func _process(_delta: float) -> void:
	if active:
		_update()


## Moves the preview in front of you and checks whether it fits.
func _update() -> void:
	var player = GameManager.player
	if player == null or _ghost == null:
		return
	var place := current_place()
	var size := FurnitureCatalog.footprint(type, current_yaw())
	var facing: Vector3 = player.get_facing()
	var ahead := maxf(size.y, size.x) * 0.5 + 0.7
	var world: Vector3 = player.global_position + facing * ahead
	var local := world - origin_of(place)
	_position = Vector3(snappedf(local.x, GRID), 0.0, snappedf(local.z, GRID))
	reason = Furnishings.instance.can_place(type, place, _position, current_yaw(), moving) if Furnishings.instance else "No furniture here"
	if reason != "" and Furnishings.instance:
		# Facing a wall or another piece? Slide the preview to the nearest spot
		# close by where it fits, so it turns green instead of staying red.
		var near := Furnishings.instance.free_spot(type, place, _position, current_yaw(), moving, NEARBY_RINGS)
		if near != Vector3.INF:
			_position = near
			reason = ""
	if place != "outside" and not Furnishings.instance.is_players_place(place):
		reason = "This isn't your house"
	var at := origin_of(place) + _position
	if place == "outside":
		at = VillageLayout.ground_point(at.x, at.z)
	_ghost.global_position = at + Vector3(0, 0.02, 0)
	_ghost.rotation.y = current_yaw()
	(_ghost.get_child(0) as MeshInstance3D).material_override = _ok_material if reason == "" else _bad_material
	if _held:
		# Held in front, at the hands: the bottom of it about hip height.
		_held.position = Vector3(0, 0.62, 0) + Basis(Vector3.UP, player.model.rotation.y) * Vector3(0, 0, 0.45)
		_held.rotation.y = player.model.rotation.y + PI
		_held.scale = Vector3.ONE * 0.72


## Puts it down here. Returns "" or why not.
func confirm() -> String:
	if not active:
		return "Nothing to place"
	_update()
	if reason != "":
		GameManager.notify(reason + ".")
		return reason
	var place := current_place()
	var info := FurnitureCatalog.info(type)
	if moving.is_empty():
		GameState.spend(info["cost"])
		Furnishings.instance.add(type, place, _position, current_yaw())
		GameManager.notify("%s placed. Tap Arrange any time to move it." % info["name"])
	else:
		Furnishings.instance.move(moving, place, _position, current_yaw())
	if place != "outside" and Furnishings.instance.is_players_place(place):
		GameState.set_flag(&"furnished_home")  # the first day's "Make it home"
	Sounds.play("built", null, -10.0)
	_finish()
	return ""


## Puts the piece away (it can be placed again from Furnish > Put away).
func put_away() -> void:
	if not active or moving.is_empty():
		cancel()
		return
	Furnishings.instance.put_away(moving)
	GameManager.notify("%s put away. Place it again from the Furnish menu." % FurnitureCatalog.info(type).get("name", "It"))
	_finish()


func cancel() -> void:
	if not active:
		return
	if not moving.is_empty() and not _from.is_empty():
		var p: Array = _from["pos"]
		Furnishings.instance.move(moving, String(_from["place"]), Vector3(float(p[0]), float(p[1]), float(p[2])), float(_from["yaw"]))
	_finish()


func _finish() -> void:
	active = false
	moving = {}
	_from = {}
	type = &""
	if _ghost:
		_ghost.queue_free()
		_ghost = null
	if _held:
		_held.queue_free()
		_held = null
	changed.emit()


## Doors still work while you're carrying something, so you can take it out
## of the house or into another one.
static func allows_interaction(target) -> bool:
	if instance == null or not instance.active:
		return true
	if target == null or not instance.is_carrying():
		return false
	var handler = target.get("handler")
	if handler is UsableObject and String(handler.name).begins_with("ExitDoor"):
		return true
	return handler is PlacedStructure and HouseDesigns.is_house(handler.get_type())
