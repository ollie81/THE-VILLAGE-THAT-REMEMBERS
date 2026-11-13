class_name HumanoidAnimations
extends RefCounted
## Builds the skeletal animation library used by every humanoid.
## Each animation is described as a pose function of the cycle phase and
## baked into keyframed bone rotation tracks (plus a Hips position track),
## which AnimationPlayer then plays and cross-fades like imported clips.
##
## Posture differences (e.g. Tomas's stoop) are baked into a per-posture
## library, so the same motion reads differently per character.

const B := HumanoidRig.Bone
## Locomotion. Walk and run share one phase convention and the same clip
## length, so CharacterModel can blend them at any speed in between without
## the legs fighting each other. Playback rate comes from the stride.
const WALK_SPEED := 1.5
const RUN_SPEED := 5.6
## Distance covered by one full gait cycle (two steps), in metres.
const WALK_STRIDE := 1.45
const RUN_STRIDE := 3.7
const SAMPLES := 16

## name -> [length (s), pose method]
const CLIPS := {
	&"idle": [4.0, "_idle"],
	&"walk": [1.0, "_walk"],
	&"run": [1.0, "_run"],
	&"jump": [1.2, "_jump"],
	&"work": [1.1, "_work"],
	&"gather": [2.4, "_gather"],
	&"talk": [3.0, "_talk"],
	&"wave": [1.0, "_wave"],
	&"sit": [5.0, "_sit"],
	&"sit_ground": [5.0, "_sit_ground"],
	&"sleep": [4.5, "_sleep"],
	&"cheer": [0.8, "_cheer"],
	&"dance": [1.6, "_dance"],
	&"bow": [2.0, "_bow"],
	&"slash": [0.55, "_slash"],
	&"block": [1.2, "_block"],
	&"dodge": [0.45, "_dodge"],
	&"hurt": [0.4, "_hurt"],
}

static var _cache: Dictionary = {}

var _stoop: float = 0.0
var _hips_height: float = HumanoidRig.HIPS_HEIGHT
var _leg_scale: float = 1.0


## One library per posture and leg length (children's hips sit lower and
## their bobbing is smaller); libraries are shared between characters.
static func get_library(stoop: float, proportions: BodyProportions = null) -> AnimationLibrary:
	var legs := snappedf(proportions.leg, 0.01) if proportions else 1.0
	var key := "%.2f/%.2f" % [snappedf(stoop, 0.01), legs]
	if not _cache.has(key):
		var builder := HumanoidAnimations.new()
		builder._stoop = snappedf(stoop, 0.01)
		builder._leg_scale = legs
		builder._hips_height = proportions.map_height(HumanoidRig.HIPS_HEIGHT) if proportions else HumanoidRig.HIPS_HEIGHT
		_cache[key] = builder._build_library()
	return _cache[key]


func _build_library() -> AnimationLibrary:
	var library := AnimationLibrary.new()
	for clip_name in CLIPS:
		var clip: Array = CLIPS[clip_name]
		library.add_animation(clip_name, _bake(clip[0], Callable(self, clip[1])))
	return library


func _bake(length: float, pose: Callable) -> Animation:
	var animation := Animation.new()
	animation.length = length
	animation.loop_mode = Animation.LOOP_LINEAR
	var bone_count := HumanoidRig.BONE_NAMES.size()
	var tracks: Array[int] = []
	for bone in bone_count:
		var track := animation.add_track(Animation.TYPE_ROTATION_3D)
		animation.track_set_path(track, NodePath("Skeleton3D:%s" % HumanoidRig.BONE_NAMES[bone]))
		animation.track_set_interpolation_type(track, Animation.INTERPOLATION_CUBIC)
		tracks.append(track)
	var hips_track := animation.add_track(Animation.TYPE_POSITION_3D)
	animation.track_set_path(hips_track, NodePath("Skeleton3D:Hips"))
	animation.track_set_interpolation_type(hips_track, Animation.INTERPOLATION_CUBIC)

	for i in SAMPLES + 1:
		var phase := float(i) / SAMPLES
		var time := phase * length
		var p: Dictionary = pose.call(phase)
		_apply_posture(p)
		for bone in bone_count:
			var euler: Vector3 = p.get(bone, Vector3.ZERO)
			animation.rotation_track_insert_key(tracks[bone], time, Quaternion.from_euler(euler))
		var offset: Vector3 = p.get("hips", Vector3.ZERO)
		animation.position_track_insert_key(hips_track, time, Vector3(0, _hips_height, 0) + offset * _leg_scale)
	return animation


## Adds the character's resting posture to any pose.
func _apply_posture(p: Dictionary) -> void:
	if _stoop <= 0.0:
		return
	p[B.SPINE] = p.get(B.SPINE, Vector3.ZERO) + Vector3(_stoop * 0.55, 0, 0)
	p[B.CHEST] = p.get(B.CHEST, Vector3.ZERO) + Vector3(_stoop * 0.45, 0, 0)
	p[B.NECK] = p.get(B.NECK, Vector3.ZERO) + Vector3(-_stoop * 0.6, 0, 0)
	p[B.HEAD] = p.get(B.HEAD, Vector3.ZERO) + Vector3(-_stoop * 0.25, 0, 0)
	for leg in [B.LEFT_LOWER_LEG, B.RIGHT_LOWER_LEG]:
		p[leg] = p.get(leg, Vector3.ZERO) + Vector3(_stoop * 0.25, 0, 0)
	for leg in [B.LEFT_UPPER_LEG, B.RIGHT_UPPER_LEG]:
		p[leg] = p.get(leg, Vector3.ZERO) + Vector3(-_stoop * 0.12, 0, 0)
	p["hips"] = p.get("hips", Vector3.ZERO) + Vector3(0, -_stoop * 0.04, 0)


# --- Helpers --------------------------------------------------------------------------

static func _s(x: float) -> float:
	return sin(TAU * x)


static func _c(x: float) -> float:
	return cos(TAU * x)


## Smooth bump centred on `center` (cycle-wrapped) with half-width `width`.
static func _bump(x: float, center: float, width: float) -> float:
	var d := fposmod(x - center + 0.5, 1.0) - 0.5
	return exp(-(d / width) * (d / width))


## Relaxed standing arms and legs; poses override what they need.
func _base() -> Dictionary:
	return {
		B.LEFT_UPPER_ARM: Vector3(0.04, 0.12, 0.16),
		B.RIGHT_UPPER_ARM: Vector3(0.04, -0.12, -0.16),
		B.LEFT_LOWER_ARM: Vector3(-0.32, 0, 0),
		B.RIGHT_LOWER_ARM: Vector3(-0.32, 0, 0),
		B.LEFT_HAND: Vector3(0.05, 0.25, -0.1),
		B.RIGHT_HAND: Vector3(0.05, -0.25, 0.1),
		B.LEFT_UPPER_LEG: Vector3(0, 0, 0.02),
		B.RIGHT_UPPER_LEG: Vector3(0, 0, -0.02),
	}


func _leg(p: Dictionary, side: float, thigh: float, knee: float, foot: float) -> void:
	p[HumanoidRig.sided(B.LEFT_UPPER_LEG, side)] = Vector3(thigh, 0, side * 0.02)
	p[HumanoidRig.sided(B.LEFT_LOWER_LEG, side)] = Vector3(knee, 0, 0)
	p[HumanoidRig.sided(B.LEFT_FOOT, side)] = Vector3(foot, 0, 0)


func _arm(p: Dictionary, side: float, swing: float, out: float, elbow: float, twist: float = 0.0) -> void:
	p[HumanoidRig.sided(B.LEFT_UPPER_ARM, side)] = Vector3(swing, twist, side * out)
	p[HumanoidRig.sided(B.LEFT_LOWER_ARM, side)] = Vector3(elbow, 0, 0)


# --- Clips ----------------------------------------------------------------------------

func _idle(x: float) -> Dictionary:
	var p := _base()
	var breath := _s(x * 2.0)
	p[B.SPINE] = Vector3(0.01, 0, 0)
	p[B.CHEST] = Vector3(0.02 * breath, 0.03 * _s(x), 0)
	p[B.NECK] = Vector3(0, 0.08 * _s(x), 0)
	p[B.HEAD] = Vector3(0.03 * _s(x * 2.0 + 0.1), 0.12 * _s(x + 0.15), 0.02 * _s(x))
	# Relaxed arms: slightly away from the body, elbows soft.
	_arm(p, 1.0, 0.04 + 0.03 * breath, 0.16, -0.32, 0.12)
	_arm(p, -1.0, 0.04 + 0.03 * breath, 0.16, -0.32, -0.12)
	p[B.HIPS] = Vector3(0, 0, 0.015 * _s(x))
	p[B.LEFT_UPPER_LEG] = Vector3(0, 0, 0.02 - 0.015 * _s(x))
	p[B.RIGHT_UPPER_LEG] = Vector3(0.0, 0, -0.02 - 0.015 * _s(x))
	p[B.RIGHT_LOWER_LEG] = Vector3(0.05 + 0.03 * (0.5 + 0.5 * _s(x)), 0, 0)
	p["hips"] = Vector3(0.004 * _s(x), 0.003 * breath, 0)
	return p


func _gait(x: float, thigh_mid: float, thigh_amp: float, knee_base: float, knee_swing: float,
		arm_amp: float, elbow: float, lean: float, bob: float, twist: float) -> Dictionary:
	var p := _base()
	for side in [1.0, -1.0]:
		var q: float = x if side > 0.0 else x + 0.5
		var thigh := thigh_mid - thigh_amp * _c(q)
		var knee := knee_base + 0.15 * _bump(q, 0.1, 0.1) + knee_swing * _bump(q, 0.66, 0.15)
		var foot := -(thigh + knee) * 0.7 - 0.22 * _bump(q, 0.0, 0.08) + 0.38 * _bump(q, 0.52, 0.08)
		_leg(p, side, thigh, knee, foot)
		var swing := 0.04 + arm_amp * _c(q)
		_arm(p, side, swing, 0.08 + absf(lean) * 0.2, elbow - 0.25 * (0.5 - 0.5 * _c(q)) * absf(arm_amp) * 2.0)
	# Pelvis turns with the swinging leg and drops toward the unsupported side;
	# shoulders counter-rotate and the head stays level and forward.
	p[B.HIPS] = Vector3(0, -twist * _c(x), 0.045 * _s(x) + 0.02 * _s(x * 2.0 + 0.25))
	p[B.SPINE] = Vector3(lean * 0.6, twist * 0.6 * _c(x), -0.03 * _s(x))
	p[B.CHEST] = Vector3(lean * 0.4 + 0.02 * _c(x * 2.0), twist * 1.4 * _c(x), -0.02 * _s(x))
	p[B.NECK] = Vector3(0, -twist * 0.9 * _c(x), 0.025 * _s(x))
	p[B.HEAD] = Vector3(-lean * 0.6 - 0.02 * _c(x * 2.0), -twist * 0.9 * _c(x), 0.02 * _s(x))
	p["hips"] = Vector3(0.022 * _s(x), -bob * 0.5 - bob * 0.5 * _c(x * 2.0), 0)
	return p


func _walk(x: float) -> Dictionary:
	return _gait(x, -0.04, 0.4, 0.06, 0.95, 0.48, -0.3, 0.06, 0.03, 0.11)


func _run(x: float) -> Dictionary:
	var p := _gait(x, -0.18, 0.72, 0.25, 1.7, 0.7, -1.3, 0.2, 0.055, 0.16)
	return p


func _jump(x: float) -> Dictionary:
	var p := _base()
	var drift := 0.05 * _s(x)
	_leg(p, 1.0, -0.75 + drift, 1.05, 0.25)
	_leg(p, -1.0, -0.2 - drift, 0.55, 0.3)
	_arm(p, 1.0, -0.55, 0.55 + drift, -0.6)
	_arm(p, -1.0, -0.4, 0.5 - drift, -0.5)
	p[B.SPINE] = Vector3(0.12, 0, 0)
	p[B.HEAD] = Vector3(-0.1, 0, 0)
	return p


func _work(x: float) -> Dictionary:
	var p := _base()
	# Wind up slowly, strike quickly, recover.
	var raise := smoothstep(0.0, 0.55, x) * (1.0 - smoothstep(0.55, 0.68, x))
	_arm(p, -1.0, -0.85 - 1.55 * raise, 0.12 + 0.1 * raise, -0.45 - 0.85 * raise)
	p[B.RIGHT_HAND] = Vector3(0.25 * raise - 0.2, 0, 0)
	_arm(p, 1.0, -0.75, 0.18, -0.95)
	p[B.LEFT_HAND] = Vector3(0, 0.3, 0)
	p[B.SPINE] = Vector3(0.14 + 0.08 * (1.0 - raise), 0, 0)
	p[B.CHEST] = Vector3(0.1, -0.15 * raise, 0)
	p[B.HEAD] = Vector3(0.28, 0.1 * raise, 0)
	_leg(p, 1.0, -0.18, 0.22, -0.04)
	_leg(p, -1.0, 0.1, 0.2, -0.3)
	p["hips"] = Vector3(0, -0.03, 0)
	return p


func _gather(x: float) -> Dictionary:
	var p := _base()
	# Crouch with feet planted, reach down with each hand in turn.
	for side in [1.0, -1.0]:
		_leg(p, side, -1.05, 1.82, -0.77)
		p[HumanoidRig.sided(B.LEFT_UPPER_LEG, side)] = Vector3(-1.05, 0, side * 0.16)
	var reach := _s(x)
	_arm(p, 1.0, -1.0 - 0.35 * reach, 0.18, -0.3)
	_arm(p, -1.0, -1.0 + 0.35 * reach, 0.18, -0.3)
	p[B.SPINE] = Vector3(0.4, 0.06 * reach, 0)
	p[B.CHEST] = Vector3(0.22, 0.08 * reach, 0)
	p[B.NECK] = Vector3(-0.15, 0, 0)
	p[B.HEAD] = Vector3(0.2, -0.1 * reach, 0)
	p["hips"] = Vector3(0, -0.3, 0.02)
	return p


func _talk(x: float) -> Dictionary:
	var p := _idle(x)
	_arm(p, -1.0, -0.42 - 0.18 * _s(x), 0.22 + 0.08 * _s(x * 2.0), -1.05 - 0.25 * _s(x + 0.2), 0.3)
	p[B.RIGHT_HAND] = Vector3(-0.2, 0.5 + 0.2 * _s(x * 2.0), 0.15)
	_arm(p, 1.0, -0.12 - 0.12 * _s(x * 2.0 + 0.3), 0.14, -0.55 - 0.15 * _s(x * 2.0))
	p[B.HEAD] = Vector3(0.05 * _s(x * 2.0), 0.1 * _s(x), 0.04 * _s(x + 0.3))
	p[B.CHEST] = Vector3(0.0, 0.06 * _s(x), 0)
	return p


func _wave(x: float) -> Dictionary:
	var p := _idle(x)
	_arm(p, -1.0, -0.25, 2.5, -0.4)
	p[B.RIGHT_LOWER_ARM] = Vector3(-0.35, 0, -0.45 * _s(x * 2.0))
	p[B.RIGHT_HAND] = Vector3(0, 0, 0)
	return p


## Sitting on a bench, log or chair about 0.45 m high: thighs level,
## shins down, hands resting on the knees.
func _sit(x: float) -> Dictionary:
	var p := _base()
	var breath := _s(x * 2.0)
	for side in [1.0, -1.0]:
		_leg(p, side, -1.5, 1.45, 0.05)
		p[HumanoidRig.sided(B.LEFT_UPPER_LEG, side)] = Vector3(-1.5, 0, side * 0.08)
		_arm(p, side, -0.55, 0.12, -0.75, side * 0.1)
	p[B.SPINE] = Vector3(0.05, 0, 0)
	p[B.CHEST] = Vector3(0.03 + 0.015 * breath, 0.03 * _s(x), 0)
	p[B.HEAD] = Vector3(0.04, 0.18 * _s(x * 0.5), 0.02 * _s(x))
	p["hips"] = Vector3(0, -0.47 + 0.003 * breath, -0.05)
	return p


## Sitting on the grass: legs out in front, knees up a little, leaning back
## on the hands.
func _sit_ground(x: float) -> Dictionary:
	var p := _base()
	var breath := _s(x * 2.0)
	# One knee drawn up, the other leg stretched out, feet on the grass.
	_leg(p, 1.0, -2.05, 1.25, -0.2)
	_leg(p, -1.0, -1.62, 0.12, -0.15)
	for side in [1.0, -1.0]:
		_arm(p, side, 0.55, 0.28, -0.08, side * 0.2)
		p[HumanoidRig.sided(B.LEFT_HAND, side)] = Vector3(-0.6, 0, 0)
	p[B.SPINE] = Vector3(-0.15, 0, 0)
	p[B.CHEST] = Vector3(-0.05 + 0.015 * breath, 0, 0)
	p[B.NECK] = Vector3(0.1, 0, 0)
	p[B.HEAD] = Vector3(0.05, 0.25 * _s(x * 0.5), 0)
	p["hips"] = Vector3(0, -0.8 + 0.003 * breath, -0.08)
	return p


## Lying on the back asleep, breathing slowly.
func _sleep(x: float) -> Dictionary:
	var p := _base()
	var breath := _s(x)
	p[B.HIPS] = Vector3(-PI * 0.5, 0, 0)
	p[B.CHEST] = Vector3(0.02 * breath, 0, 0)
	p[B.HEAD] = Vector3(-0.15, 0.35, 0)
	_leg(p, 1.0, -0.05, 0.12, 0.6)
	_leg(p, -1.0, -0.25, 0.45, 0.5)
	# One arm at the side, one hand resting on the belly.
	_arm(p, 1.0, 0.05, 0.18, -0.15)
	_arm(p, -1.0, -0.35, 0.05, -1.55)
	p[B.RIGHT_HAND] = Vector3(0, 0, 0.3)
	p["hips"] = Vector3(0, -0.84, 0)
	return p


func _cheer(x: float) -> Dictionary:
	var p := _base()
	var hop := maxf(0.0, _s(x))
	for side in [1.0, -1.0]:
		_arm(p, side, -0.3, 2.6 + 0.25 * _s(x * 2.0), -0.25)
		p[HumanoidRig.sided(B.LEFT_HAND, side)] = Vector3(0, 0, side * 0.3 * _s(x * 2.0))
		_leg(p, side, -0.15 * hop, 0.3 * hop, 0.2 * hop)
	p[B.SPINE] = Vector3(-0.08, 0, 0)
	p[B.HEAD] = Vector3(-0.2, 0, 0)
	p["hips"] = Vector3(0, 0.08 * hop - 0.03, 0)
	return p


func _dance(x: float) -> Dictionary:
	var p := _base()
	var sway := _s(x)
	var beat := _s(x * 2.0)
	for side in [1.0, -1.0]:
		var q: float = x if side > 0.0 else x + 0.5
		_leg(p, side, -0.35 * maxf(0.0, _s(q)), 0.6 * maxf(0.0, _s(q)), 0.1)
		_arm(p, side, -0.4 - 0.9 * maxf(0.0, _s(q)), 0.5 + 0.6 * maxf(0.0, _s(q)), -0.9)
	p[B.HIPS] = Vector3(0, 0.2 * sway, 0.08 * sway)
	p[B.SPINE] = Vector3(0.05, -0.15 * sway, -0.06 * sway)
	p[B.CHEST] = Vector3(0.0, -0.1 * sway, -0.05 * sway)
	p[B.HEAD] = Vector3(0.08 * beat, 0.15 * sway, 0.1 * sway)
	p["hips"] = Vector3(0.05 * sway, -0.04 + 0.03 * absf(beat), 0)
	return p


func _bow(x: float) -> Dictionary:
	var p := _idle(0.0)
	var bend := smoothstep(0.0, 0.3, x) * (1.0 - smoothstep(0.65, 0.95, x))
	p[B.SPINE] = Vector3(0.55 * bend, 0, 0)
	p[B.CHEST] = Vector3(0.35 * bend, 0, 0)
	p[B.HEAD] = Vector3(0.2 * bend, 0, 0)
	_arm(p, 1.0, 0.1 * bend, 0.1, -0.2)
	_arm(p, -1.0, -0.6 * bend, 0.1, -1.3 * bend)
	p["hips"] = Vector3(0, 0, -0.06 * bend)
	return p


# --- Combat ---------------------------------------------------------------------------

## A diagonal sword stroke with the right hand: wind up over the shoulder,
## sweep across and down, recover. The shield arm stays up.
func _slash(x: float) -> Dictionary:
	var p := _base()
	var wind := smoothstep(0.0, 0.3, x) * (1.0 - smoothstep(0.3, 0.45, x))
	var strike := smoothstep(0.3, 0.48, x) * (1.0 - smoothstep(0.6, 1.0, x))
	_arm(p, -1.0, -0.5 - 1.3 * wind - 0.9 * strike, 0.2 + 1.1 * wind - 0.25 * strike, -0.4 - 0.9 * wind + 0.1 * strike)
	p[B.RIGHT_HAND] = Vector3(0.1 - 0.4 * strike, 0, 0)
	_arm(p, 1.0, -0.9, 0.2, -1.3, 0.2)
	p[B.SPINE] = Vector3(0.08 + 0.12 * strike, 0, 0)
	p[B.CHEST] = Vector3(0.05, 0.45 * wind - 0.6 * strike, 0)
	p[B.HEAD] = Vector3(0.05, -0.25 * wind + 0.3 * strike, 0)
	_leg(p, -1.0, -0.4 * strike - 0.1, 0.35 * strike + 0.1, 0.05)
	_leg(p, 1.0, 0.25, 0.15, -0.15)
	p["hips"] = Vector3(0, -0.05 - 0.04 * strike, 0.04 * strike)
	return p


## Shield raised in front, knees bent, sword held low and back.
func _block(x: float) -> Dictionary:
	var p := _base()
	var breath := _s(x)
	_arm(p, 1.0, -1.3, 0.12, -1.45, 0.35)
	p[B.LEFT_HAND] = Vector3(0, 0.4, 0)
	_arm(p, -1.0, -0.45, 0.3, -0.9)
	for side in [1.0, -1.0]:
		_leg(p, side, -0.5, 0.85, -0.32)
	p[B.SPINE] = Vector3(0.16 + 0.01 * breath, 0, 0)
	p[B.CHEST] = Vector3(0.06, -0.2, 0)
	p[B.HEAD] = Vector3(-0.08, 0.15, 0)
	p["hips"] = Vector3(0, -0.13, 0)
	return p


## A low, quick sidestep dash: duck, arms tucked, legs coiled.
func _dodge(x: float) -> Dictionary:
	var p := _base()
	var duck := sin(PI * clampf(x, 0.0, 1.0))
	for side in [1.0, -1.0]:
		_arm(p, side, -0.9 * duck, 0.25, -1.6 * duck)
		_leg(p, side, -1.1 * duck, 1.6 * duck, -0.5 * duck)
	p[B.SPINE] = Vector3(0.7 * duck, 0, 0)
	p[B.CHEST] = Vector3(0.3 * duck, 0, 0)
	p[B.HEAD] = Vector3(-0.3 * duck, 0, 0)
	p["hips"] = Vector3(0, -0.42 * duck, 0.05 * duck)
	return p


## Knocked back by a blow.
func _hurt(x: float) -> Dictionary:
	var p := _base()
	var jolt := sin(PI * clampf(x, 0.0, 1.0))
	for side in [1.0, -1.0]:
		_arm(p, side, -0.4 * jolt, 0.2 + 0.5 * jolt, -0.6 * jolt)
		_leg(p, side, 0.15 * jolt * side, 0.25 * jolt, 0.0)
	p[B.SPINE] = Vector3(-0.25 * jolt, 0, 0)
	p[B.HEAD] = Vector3(-0.3 * jolt, 0.1 * jolt, 0)
	p["hips"] = Vector3(0, -0.04 * jolt, -0.05 * jolt)
	return p

