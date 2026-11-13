class_name PlayerCombat
extends Node
## The player's side of a fight: health, the sword (attack), the shield
## (hold to block), a quick dodge, eating stew to heal, and being knocked
## out (you wake up at home with nothing lost). Lives on the player.
##
## Keys: F attack, Q block (hold), C dodge, H eat. On a phone the Attack,
## Block, Dodge and Eat buttons appear when you're armed and something hostile
## is near, so village life stays uncluttered.

signal health_changed(health: float, max_health: float)
signal knocked_out

const MAX_HEALTH := 100.0
const ATTACK_TIME := 0.5
## When in the swing the blade connects, and how far and wide it reaches.
const HIT_DELAY := 0.24
const HIT_RANGE := 2.2
const HIT_ARC := 0.45  # cos of the half-angle (about 63 degrees either side)
const BLOCK_REDUCTION := 0.8
const DODGE_TIME := 0.38
const DODGE_SPEED := 9.0
const DODGE_COOLDOWN := 0.7
const HURT_GRACE := 0.6  # can't be hit again straight away
const REGEN_DELAY := 6.0
const REGEN_PER_SECOND := 5.0
const STEW_HEAL := 45.0
## How close something hostile must be for the fight buttons to show.
const ALERT_RANGE := 16.0

var player: PlayerController
var health: float = MAX_HEALTH
var blocking: bool = false
var _attack_timer: float = 0.0
var _hit_pending: bool = false
var _dodge_timer: float = 0.0
var _dodge_cooldown: float = 0.0
var _dodge_direction := Vector3.ZERO
var _grace: float = 0.0
var _since_hurt: float = 100.0
var _knockback := Vector3.ZERO
var _sword: Node3D
var _shield: Node3D
var _flash: ColorRect


func _ready() -> void:
	name = "PlayerCombat"
	player = get_parent() as PlayerController
	_register_keys()
	_update_equipment.call_deferred()


static func _register_keys() -> void:
	for pair in [["attack", KEY_F], ["block", KEY_Q], ["dodge", KEY_C], ["eat", KEY_H]]:
		if not InputMap.has_action(pair[0]):
			InputMap.add_action(pair[0])
			var key := InputEventKey.new()
			key.physical_keycode = pair[1]
			InputMap.action_add_event(pair[0], key)


static func is_armed() -> bool:
	return bool(GameState.get_flag(&"has_sword"))


static func stews() -> int:
	return int(GameState.get_flag(&"stews", 0))


## Enemies within `range` of the player.
func enemies_near(range: float = ALERT_RANGE) -> Array:
	if player == null:
		return []
	return get_tree().get_nodes_in_group("enemies").filter(func(e): return e.is_alive() and e.global_position.distance_to(player.global_position) < range)


func in_fight() -> bool:
	return is_armed() and not enemies_near().is_empty()


func is_dodging() -> bool:
	return _dodge_timer > 0.0


func is_attacking() -> bool:
	return _attack_timer > 0.0


## Movement the controller should use instead of input (dodge, knock-back),
## or null.
func movement_override() -> Variant:
	if _dodge_timer > 0.0:
		return _dodge_direction * DODGE_SPEED
	if _knockback.length() > 0.3:
		return _knockback
	return null


## How fast the player may move (slower while blocking or swinging).
func speed_factor() -> float:
	if blocking:
		return 0.35
	if _attack_timer > 0.0:
		return 0.2
	return 1.0


func _physics_process(delta: float) -> void:
	if player == null:
		return
	_grace = maxf(_grace - delta, 0.0)
	_since_hurt += delta
	_dodge_cooldown = maxf(_dodge_cooldown - delta, 0.0)
	_knockback = _knockback.move_toward(Vector3.ZERO, 14.0 * delta)
	if _dodge_timer > 0.0:
		_dodge_timer -= delta
	if _attack_timer > 0.0:
		_attack_timer -= delta
		if _hit_pending and ATTACK_TIME - _attack_timer >= HIT_DELAY:
			_hit_pending = false
			_strike()
	if health < MAX_HEALTH and _since_hurt > REGEN_DELAY and enemies_near(10.0).is_empty():
		_set_health(health + REGEN_PER_SECOND * delta)
	var free: bool = player.can_control() or _attack_timer > 0.0 or blocking
	if not is_armed() or not free or player.pose != &"" or (Interiors.instance and Interiors.instance.is_inside()):
		blocking = false
	else:
		blocking = Input.is_action_pressed("block") and _dodge_timer <= 0.0
		if Input.is_action_just_pressed("attack"):
			attack()
		if Input.is_action_just_pressed("dodge"):
			dodge()
	if Input.is_action_just_pressed("eat"):
		eat()
	_update_flash(delta)


# --- Actions ----------------------------------------------------------------------

func attack() -> bool:
	if not is_armed() or _attack_timer > 0.0 or _dodge_timer > 0.0 or player.pose != &"":
		return false
	blocking = false
	_attack_timer = ATTACK_TIME
	_hit_pending = true
	# Turn towards the nearest enemy in front (a little help on a phone).
	var target = _nearest_enemy(HIT_RANGE + 1.5)
	if target:
		player.face_towards(target.global_position)
	player.play_combat_animation(&"slash", ATTACK_TIME)
	Sounds.play("swing", null, -6.0)
	return true


func _strike() -> int:
	var hits := 0
	var facing := player.get_facing()
	for enemy in enemies_near(HIT_RANGE + 1.0):
		var to: Vector3 = enemy.global_position - player.global_position
		to.y = 0.0
		var reach: float = HIT_RANGE + float(enemy.get("radius") if enemy.get("radius") != null else 0.4)
		if to.length() > reach:
			continue
		if to.length() > 0.3 and facing.dot(to.normalized()) < HIT_ARC:
			continue
		enemy.take_hit(damage(), player.global_position)
		hits += 1
	return hits


func damage() -> int:
	return 2 if GameState.get_flag(&"sword_upgraded") else 1


func dodge() -> bool:
	if _dodge_timer > 0.0 or _dodge_cooldown > 0.0 or player.pose != &"":
		return false
	var move := InputRouter.get_move_vector()
	var yaw := player.camera_rig.get_yaw() if player.camera_rig else 0.0
	var forward := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var direction := right * move.x - forward * move.y
	if direction.length() < 0.2:
		direction = -player.get_facing()  # no stick: hop back
	_dodge_direction = direction.normalized()
	_dodge_timer = DODGE_TIME
	_dodge_cooldown = DODGE_TIME + DODGE_COOLDOWN
	blocking = false
	_attack_timer = 0.0
	_hit_pending = false
	player.play_combat_animation(&"dodge", DODGE_TIME)
	Sounds.play("swing", null, -12.0)
	return true


func eat() -> bool:
	if stews() <= 0:
		GameManager.notify("You have no stew. Cook some at the hearth in your house (2 food, 1 herb).")
		return false
	if health >= MAX_HEALTH:
		GameManager.notify("You're not hurt.")
		return false
	GameState.increment(&"stews", -1)
	_set_health(health + STEW_HEAL)
	Sounds.play("pickup", null, -4.0)
	FloatingText.spawn(player.get_parent(), player.global_position + Vector3(0, 2.2, 0), "+%d" % int(STEW_HEAL), Color(0.6, 1.0, 0.6))
	return true


func heal_full() -> void:
	_set_health(MAX_HEALTH)


# --- Being hit --------------------------------------------------------------------

## Something hits the player. Returns the damage actually taken.
func take_hit(amount: float, from: Vector3) -> float:
	if health <= 0.0 or _grace > 0.0 or _dodge_timer > 0.0:
		return 0.0
	var away := player.global_position - from
	away.y = 0.0
	away = away.normalized() if away.length() > 0.05 else -player.get_facing()
	var taken := amount
	var facing_it := player.get_facing().dot(-away) > 0.2
	if blocking and facing_it:
		taken = amount * (1.0 - BLOCK_REDUCTION)
		_knockback = away * 2.5
		Sounds.play("block", null, -4.0)
	else:
		_knockback = away * 6.0
		Sounds.play("hurt", null, -3.0)
		player.play_combat_animation(&"hurt", 0.35)
		_flash_alpha = 0.45
	_grace = HURT_GRACE
	_since_hurt = 0.0
	_set_health(health - taken)
	FloatingText.spawn(player.get_parent(), player.global_position + Vector3(0, 2.1, 0), "-%d" % int(round(taken)), Color(1.0, 0.45, 0.4))
	if health <= 0.0:
		_knock_out()
	return taken


func _set_health(value: float) -> void:
	health = clampf(value, 0.0, MAX_HEALTH)
	health_changed.emit(health, MAX_HEALTH)


## Down, but never out: you wake up at home a couple of hours later.
func _knock_out() -> void:
	knocked_out.emit()
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.reset_to_home()
	GameManager.notify("You were knocked out... Nia found you and helped you home. Rest, and try again.")
	var home := VillageLayout.ground_point(-4.0, 9.5)
	for s in get_tree().get_nodes_in_group("placed_structures"):
		if s.get_type() == &"house" and s.is_complete():
			home = s.global_position + s.global_transform.basis * Vector3(0, 0, float(s.get_info()["footprint"].y) * 0.5 + 1.2)
	player.global_position = home + Vector3(0, 0.5, 0)
	player.velocity = Vector3.ZERO
	_knockback = Vector3.ZERO
	WorldClock.advance(2.0)
	heal_full()


func _nearest_enemy(range: float):
	var best = null
	for enemy in enemies_near(range):
		if best == null or enemy.global_position.distance_to(player.global_position) < best.global_position.distance_to(player.global_position):
			best = enemy
	return best


# --- Equipment and feedback --------------------------------------------------------

var _flash_alpha: float = 0.0


func _update_flash(delta: float) -> void:
	if _flash == null:
		if _flash_alpha <= 0.0:
			return
		var layer := CanvasLayer.new()
		layer.layer = 40
		add_child(layer)
		_flash = ColorRect.new()
		_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		layer.add_child(_flash)
	_flash_alpha = maxf(_flash_alpha - delta * 1.6, 0.0)
	_flash.color = Color(0.85, 0.1, 0.05, _flash_alpha)
	_flash.visible = _flash_alpha > 0.01


## Shows the sword on the right hand and the shield on the left arm once forged.
func _update_equipment() -> void:
	if player == null or player.model == null or player.model.skeleton == null:
		return
	var armed := is_armed()
	if armed and _sword == null:
		_sword = _attach(_build_sword(), "RightHand", Vector3(0, 0.02, 0.0), Vector3(0, 0, 0))
		_shield = _attach(_build_shield(), "LeftHand", Vector3(0.03, 0.0, 0.04), Vector3(0, PI * 0.5, 0))
	if _sword:
		_sword.visible = armed
		_shield.visible = armed


func refresh_equipment() -> void:
	_update_equipment()


func _attach(mesh: Node3D, bone: String, offset: Vector3, rotation: Vector3) -> Node3D:
	var attachment := BoneAttachment3D.new()
	attachment.name = "Combat" + bone
	attachment.bone_name = bone
	player.model.skeleton.add_child(attachment)
	mesh.position = offset
	mesh.rotation = rotation
	attachment.add_child(mesh)
	return mesh


static func _build_sword() -> Node3D:
	var b := MeshBuilder.new(11)
	b.color_jitter = 0.0
	b.add_box_at(Vector3(0, -0.05, 0), Vector3(0.035, 0.12, 0.035), Color(0.42, 0.27, 0.15))   # grip
	b.add_box_at(Vector3(0, 0.02, 0), Vector3(0.16, 0.03, 0.04), Color(0.75, 0.62, 0.3))      # guard
	b.add_box_at(Vector3(0, 0.36, 0), Vector3(0.05, 0.62, 0.012), Color(0.82, 0.85, 0.9))     # blade
	b.add_prism(Transform3D(Basis.IDENTITY, Vector3(0, 0.67, 0)), 0.05, 0.012, 0.07, Color(0.82, 0.85, 0.9))
	var mesh := MeshInstance3D.new()
	mesh.name = "Sword"
	mesh.mesh = b.build(Materials.vertex_color())
	var holder := Node3D.new()
	holder.add_child(mesh)
	# The blade points forward out of the fist.
	mesh.rotation = Vector3(PI * 0.5, 0, 0)
	return holder


static func _build_shield() -> Node3D:
	var b := MeshBuilder.new(12)
	b.color_jitter = 0.0
	b.add_cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO), 0.22, 0.22, 0.04, 12, Color(0.55, 0.36, 0.2))
	b.add_cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, 0.022)), 0.2, 0.2, 0.01, 12, Color(0.3, 0.45, 0.65))
	b.add_cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, 0.03)), 0.06, 0.05, 0.03, 8, Color(0.78, 0.68, 0.35))
	var mesh := MeshInstance3D.new()
	mesh.name = "Shield"
	mesh.mesh = b.build(Materials.vertex_color())
	var holder := Node3D.new()
	holder.add_child(mesh)
	return holder
