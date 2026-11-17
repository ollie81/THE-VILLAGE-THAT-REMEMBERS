class_name VillageDefence
extends Node3D
## Keeping the village safe.
## - Two guards: the bravest grown-ups (Mara, who said to come to her first,
##   is usually one). In a raid they take up a sword and shield you can see
##   and go to meet it.
## - An alarm bell by the meeting circle, rung when raiders come.
## - Now and then (rarely: every 4–6 days at most, never before day 3) a band
##   of monsters gathers on a road outside the village. You're warned an hour
##   and a half before; at dusk they march on the village edge. The bell rings,
##   the guards hold the edge, everyone else gathers at the meeting circle.
##   You can join in: armed, the raiders come for you too.
## - When the last raider falls (or they give up after a while) the guards put
##   their swords away and everyone goes back to their day. Helping earns
##   credits; the village remembers.
## A guard knocked down falls back to the meeting circle hurt, and is fine by
## morning. Nobody dies.
## Saved: when the next raid may come, and how many have been driven off.

signal raid_started(edge: String)
signal raid_ended(won: bool)

static var instance: VillageDefence

enum Phase { QUIET, WARNED, RAID }

const FIRST_RAID_DAY := 3
const DAYS_BETWEEN := Vector2i(4, 6)
const RAID_CHANCE := 0.5
const WARNING_HOURS := 1.5
## A raid that isn't beaten in this many game hours melts back into the woods.
const RAID_HOURS := 2.5
const GUARD_HEALTH := 60.0
const GUARD_DAMAGE := 1
const GUARD_SWING := 1.6
const GUARD_REACH := 2.4
const REWARD_HELPED := 15
const REWARD_PER_RAIDER := 5
const HELP_DISTANCE := 25.0
## Where raids come from: the road and the edge of the village they march on.
const EDGES := {
	"west road": [Vector3(-104.0, 0.0, -2.0), Vector3(-84.0, 0.0, -2.0)],
	"north road": [Vector3(-66.0, 0.0, -104.0), Vector3(-58.0, 0.0, -84.0)],
	"east woods": [Vector3(104.0, 0.0, 6.0), Vector3(84.0, 0.0, 6.0)],
}

var phase: int = Phase.QUIET
var next_raid_day: int = FIRST_RAID_DAY
var raids_repelled: int = 0
var raid_edge: String = ""
var raid_hour: float = -1.0  # absolute game hour of today's raid
var raid_started_at: float = -1.0
var raiders: Array = []
var _guards: Array = []  # villager ids
var _guard_health: Dictionary = {}  # id -> hp
var _down: Dictionary = {}  # id -> true once knocked back this raid
var _swing: Dictionary = {}  # id -> cooldown
var _gear: Dictionary = {}  # id -> [sword, shield]
var _player_kills: int = 0
var _player_helped: bool = false
var _bell: Node3D
var _bell_swing: float = 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	name = "VillageDefence"
	instance = self
	_rng.randomize()
	_build_bell()
	WorldClock.day_changed.connect(_on_new_day)


func _exit_tree() -> void:
	if instance == self:
		instance = null


static func now_hours() -> float:
	return WorldClock.day * 24.0 + WorldClock.time_of_day


func is_raid() -> bool:
	return phase == Phase.RAID


# --- Guards -------------------------------------------------------------------------------

## The village's guards (villager nodes): the two bravest grown-ups living here.
func guards() -> Array:
	if _guards.is_empty():
		var candidates: Array = []
		for v in GameManager.villagers:
			var p: Person = Population.get_person(String(v.data.id))
			if p and p.is_resident() and p.life_stage() == Person.STAGE_ADULT:
				candidates.append([p.trait_weight("courage") + p.trait_weight("conscientiousness") * 0.3, String(v.data.id)])
		candidates.sort_custom(func(a, b): return a[0] > b[0])
		for c in candidates.slice(0, 2):
			_guards.append(c[1])
	var out: Array = []
	for id in _guards:
		var v = _villager(String(id))
		if v:
			out.append(v)
	return out


func is_guard(villager) -> bool:
	return villager != null and String(villager.data.id) in _guards


## Guards still on their feet in this raid.
func fighting_guards() -> Array:
	if phase != Phase.RAID:
		return []
	return guards().filter(func(g): return not _down.has(String(g.data.id)))


func _villager(id: String) -> Node:
	for v in GameManager.villagers:
		if is_instance_valid(v) and String(v.data.id) == id:
			return v
	return null


## A raider's blow lands on a guard.
func guard_hit(guard, amount: float, from: Vector3) -> void:
	var id := String(guard.data.id)
	if _down.has(id):
		return
	_guard_health[id] = float(_guard_health.get(id, GUARD_HEALTH)) - amount
	Sounds.play("hurt", guard.global_position, -6.0)
	FloatingText.spawn(get_parent(), guard.global_position + Vector3(0, 2.1, 0), "-%d" % int(amount), Color(1.0, 0.5, 0.45))
	var away: Vector3 = guard.global_position - from
	away.y = 0.0
	if away.length() > 0.05:
		guard.global_position += away.normalized() * 0.6
	if float(_guard_health[id]) <= 0.0:
		_down[id] = true
		_show_gear(guard, false)
		_send(guard, VillageLayout.get_nav_nodes().get("plaza_0", Vector3.ZERO), "Hurt, falling back to the meeting circle", "idle", 3.0)
		GameManager.notify("%s is hurt and falls back! (They'll be fine by morning.)" % guard.data.display_name)


func _show_gear(guard, shown: bool) -> void:
	var id := String(guard.data.id)
	if shown and not _gear.has(id) and guard.model and guard.model.skeleton:
		var sword := _attach(guard, PlayerCombat._build_sword(), "RightHand", Vector3(0, 0.02, 0.0), Vector3.ZERO)
		var shield := _attach(guard, PlayerCombat._build_shield(), "LeftHand", Vector3(0.03, 0.0, 0.04), Vector3(0, PI * 0.5, 0))
		_gear[id] = [sword, shield]
	if _gear.has(id):
		for g in _gear[id]:
			if is_instance_valid(g):
				g.visible = shown


func _attach(guard, mesh: Node3D, bone: String, offset: Vector3, rotation: Vector3) -> Node3D:
	var attachment := BoneAttachment3D.new()
	attachment.name = "Guard" + bone
	attachment.bone_name = guard.model.bone_name(StringName(bone))
	guard.model.skeleton.add_child(attachment)
	mesh.position = offset
	mesh.rotation = rotation
	attachment.add_child(mesh)
	return mesh


## Has a villager walk to `point` and do `anim` there, ahead of their day.
func _send(villager, point: Vector3, label: String, anim: String, hours: float, look: Variant = null) -> void:
	var activity := VillagerActivity.from_entry({"activity": "work", "location": "", "label": label, "anim": anim, "hour": WorldClock.time_of_day})
	villager.assign_task({"point": VillageLayout.ground_point(point.x, point.z), "activity": activity, "until": TaskSystem.absolute_hours() + hours, "look": look})


func _release(villager) -> void:
	villager.task = {}
	var next: VillagerActivity = villager.brain.choose_activity(villager, WorldClock.time_of_day)
	if next:
		villager.start_activity(next)


# --- The bell -----------------------------------------------------------------------------

## A bell under a little roof by the meeting circle.
func _build_bell() -> void:
	_bell = Node3D.new()
	_bell.name = "AlarmBell"
	add_child(_bell)
	var frame := MeshBuilder.new(31)
	for side: float in [-1.0, 1.0]:
		frame.add_box_at(Vector3(side * 0.55, 1.25, 0), Vector3(0.14, 2.5, 0.14), BuildingFactory.WOOD_DARK)
	frame.add_box_at(Vector3(0, 2.45, 0), Vector3(1.4, 0.14, 0.18), BuildingFactory.WOOD)
	frame.add_prism(Transform3D(Basis.IDENTITY, Vector3(0, 2.55, 0)), 1.6, 0.7, 0.45, Color(0.5, 0.28, 0.2))
	var frame_mesh := MeshInstance3D.new()
	frame_mesh.mesh = frame.build(Materials.vertex_color())
	_bell.add_child(frame_mesh)
	var bell := MeshBuilder.new(32)
	bell.add_cylinder_at(Vector3(0, -0.55, 0), 0.3, 0.14, 0.5, 10, Color(0.78, 0.62, 0.3))
	bell.add_cylinder_at(Vector3(0, -0.6, 0), 0.32, 0.32, 0.05, 10, Color(0.68, 0.52, 0.24))
	bell.add_box_at(Vector3(0, -0.05, 0), Vector3(0.05, 0.1, 0.05), BuildingFactory.WOOD_DARK)
	var swing := Node3D.new()
	swing.name = "Swing"
	swing.position = Vector3(0, 2.38, 0)
	_bell.add_child(swing)
	var bell_mesh := MeshInstance3D.new()
	bell_mesh.mesh = bell.build(Materials.vertex_color())
	swing.add_child(bell_mesh)
	var at := bell_spot()
	_bell.position = VillageLayout.ground_point(at.x, at.z)
	_bell.rotation.y = atan2(-at.x, -at.z)  # facing the fire


## Just outside the meeting circle, on clear ground.
static func bell_spot() -> Vector3:
	for extra: float in [1.5, 2.5, 3.5, 4.5, 5.5]:
		for i in 24:
			var a := deg_to_rad(215.0 + i * 15.0)
			var at := Vector3(cos(a), 0, sin(a)) * (VillageLayout.PLAZA_RADIUS + extra)
			if VillageLayout.blocking_reason(at.x, at.z, 0.9, 0.0) == "" and VillageDecor.blocking_reason(at, 0.9) == "" \
					and TerrainGenerator.distance_to_paths(at.x, at.z) > 1.2:
				return at
	return Vector3(VillageLayout.PLAZA_RADIUS + 4.0, 0, 0)


func ring_bell() -> void:
	_bell_swing = 6.0
	for i in 5:
		get_tree().create_timer(i * 0.9).timeout.connect(func(): Sounds.play("bell", _bell.global_position, -2.0))


func bell_position() -> Vector3:
	return _bell.global_position


# --- Raids --------------------------------------------------------------------------------

func _on_new_day(day: int) -> void:
	if phase == Phase.RAID:
		_end_raid(false, true)
	_guard_health.clear()
	_down.clear()
	if day >= next_raid_day and _rng.randf() < RAID_CHANCE:
		var edges := EDGES.keys()
		schedule_raid(String(edges[_rng.randi_range(0, edges.size() - 1)]), _rng.randf_range(18.5, 20.5))


## Plans a raid for today at `hour` from `edge`.
func schedule_raid(edge: String, hour: float) -> void:
	raid_edge = edge
	raid_hour = WorldClock.day * 24.0 + hour
	phase = Phase.QUIET


func _process(delta: float) -> void:
	_animate_bell(delta)
	var t := now_hours()
	match phase:
		Phase.QUIET:
			if raid_hour > 0.0 and t >= raid_hour - WARNING_HOURS:
				warn()
		Phase.WARNED:
			if t >= raid_hour:
				start_raid()
		Phase.RAID:
			_run_raid(delta)


## The warning: someone has seen them gathering.
func warn() -> void:
	phase = Phase.WARNED
	var spotter := "A traveller"
	var g := guards()
	if not g.is_empty():
		spotter = g[0].data.display_name
	var at := raid_hour - WorldClock.day * 24.0
	GameManager.notify("%s spotted monsters gathering on the %s! They'll come at the village edge around %02d:%02d. The guards will meet them; come and help if you can." % [spotter, raid_edge, int(at), int(fmod(at, 1.0) * 60.0)])
	for guard in g:
		_show_gear(guard, true)
		_send(guard, edge_point() + _guard_offset(guard), "Waiting for the raid at the %s, sword ready" % raid_edge, "block", WARNING_HOURS + RAID_HOURS, _road_point())


func edge_point() -> Vector3:
	return EDGES.get(raid_edge, EDGES["west road"])[1]


func _road_point() -> Vector3:
	return EDGES.get(raid_edge, EDGES["west road"])[0]


func _guard_offset(guard) -> Vector3:
	var road := (_road_point() - edge_point()).normalized()
	var side := Vector3(-road.z, 0, road.x)
	return side * (1.8 if guards().find(guard) == 0 else -1.8)


## The raid begins: the bell, the raiders, the guards, everyone else to the
## meeting circle.
func start_raid(edge: String = "") -> void:
	if edge != "":
		raid_edge = edge
	if raid_edge == "":
		raid_edge = "west road"
	phase = Phase.RAID
	raid_started_at = now_hours()
	if raid_hour < 0.0:
		raid_hour = raid_started_at
	_player_kills = 0
	_player_helped = false
	_down.clear()
	_guard_health.clear()
	ring_bell()
	var count := 3 + (1 if WorldClock.day > 10 else 0) + (1 if raids_repelled >= 3 else 0)
	var night := WorldClock.time_of_day >= 20.0 or WorldClock.time_of_day < 5.5
	var road := _road_point()
	for i in count:
		var kind: StringName = &"skeleton" if night or i % 2 == 0 else &"wolf"
		var at := road + Vector3(_rng.randf_range(-4, 4), 0, _rng.randf_range(-4, 4))
		at.y = TerrainGenerator.get_height(at.x, at.z) + 0.3
		var m := Monster.create(kind, at)
		m.raider = true
		m.raid_point = edge_point()
		add_child(m)
		m.defeated.connect(_on_raider_defeated)
		raiders.append(m)
	for guard in guards():
		_show_gear(guard, true)
	GameManager.notify("The alarm bell! Raiders on the %s! The guards are holding the edge; everyone else to the meeting circle." % raid_edge)
	raid_started.emit(raid_edge)


func raiders_left() -> Array:
	return raiders.filter(func(m): return is_instance_valid(m) and m.is_alive())


func _on_raider_defeated(m: Monster) -> void:
	if m.beaten_by_player:
		_player_kills += 1
		_player_helped = true
	if raiders_left().is_empty() and phase == Phase.RAID:
		_end_raid(true)


func _run_raid(delta: float) -> void:
	var player = GameManager.player
	if player and player.global_position.distance_to(edge_point()) < HELP_DISTANCE and PlayerCombat.is_armed():
		_player_helped = true
	if now_hours() - raid_started_at > RAID_HOURS:
		_end_raid(false)
		return
	var left := raiders_left()
	for guard in fighting_guards():
		var id := String(guard.data.id)
		_swing[id] = float(_swing.get(id, 0.0)) - delta
		var target: Monster = null
		var best := INF
		for m in left:
			var d: float = guard.global_position.distance_to(m.global_position)
			if d < best:
				best = d
				target = m
		if target == null:
			continue
		if best > GUARD_REACH:
			# Close in (refreshing the walk now and then as it moves).
			var goal: Vector3 = target.global_position + (guard.global_position - target.global_position).normalized() * 1.6
			var task: Dictionary = guard.task
			if task.is_empty() or (task.get("point", Vector3.ZERO) as Vector3).distance_to(goal) > 1.5:
				_send(guard, goal, "Fighting the raiders at the %s" % raid_edge, "slash", RAID_HOURS, target.global_position)
		elif float(_swing[id]) <= 0.0:
			_swing[id] = GUARD_SWING
			guard.model.set_animation(&"slash")
			Sounds.play("swing", guard.global_position, -8.0)
			target.take_hit(GUARD_DAMAGE, guard.global_position)


func _end_raid(won: bool, quiet: bool = false) -> void:
	phase = Phase.QUIET
	raid_hour = -1.0
	next_raid_day = WorldClock.day + _rng.randi_range(DAYS_BETWEEN.x, DAYS_BETWEEN.y)
	for m in raiders:
		if is_instance_valid(m) and m.is_alive():
			m.queue_free()
	raiders.clear()
	for guard in guards():
		_show_gear(guard, false)
		_release(guard)
	_down.clear()
	if won:
		raids_repelled += 1
		var reward := 0
		if _player_helped:
			reward = REWARD_HELPED + REWARD_PER_RAIDER * _player_kills
			if VillageCredits.instance:
				VillageCredits.instance.earn(reward, "raid_%d" % raids_repelled, "helping drive off the raid")
			for guard in guards():
				guard.mind.adjust_opinion(GameManager.PLAYER_ID, 6.0, 4.0)
		if not quiet:
			GameManager.notify("The raid is driven off! %s" % ("Thank you for standing with us. +%d credits." % reward if _player_helped else "The guards held the edge. Everyone's safe."))
		Sounds.play("built", null, -6.0)
	elif not quiet:
		GameManager.notify("The raiders melt back into the woods. Everyone's safe, for now.")
	raid_ended.emit(won)


func _animate_bell(delta: float) -> void:
	var swing: Node3D = _bell.get_node("Swing")
	if _bell_swing > 0.0:
		_bell_swing -= delta
		swing.rotation.z = sin(_bell_swing * 6.0) * 0.5 * clampf(_bell_swing / 2.0, 0.0, 1.0)
	else:
		swing.rotation.z = lerpf(swing.rotation.z, 0.0, clampf(delta * 4.0, 0.0, 1.0))


# --- Save ---------------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {"next_raid_day": next_raid_day, "raids_repelled": raids_repelled}


func from_dict(data: Dictionary) -> void:
	next_raid_day = int(data.get("next_raid_day", FIRST_RAID_DAY))
	raids_repelled = int(data.get("raids_repelled", 0))
