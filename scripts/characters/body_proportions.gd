class_name BodyProportions
extends RefCounted
## Turns the adult body into a child's. Every character is built as an adult
## first; for children the skeleton joints and every mesh vertex then go
## through the same mapping, so skin, bones and animations stay consistent:
## legs and torso shrink most, the head least (children's heads are large
## for their bodies), and the body gets narrower.
##
## youth 0 = adult, 1 = about four years old (roughly 1 m tall).

## Boundary between legs and torso, and between torso and head (adult m).
const LEG_TOP := 0.96
const HEAD_BASE := HumanoidRig.NECK_HEIGHT

var youth: float = 0.0
var leg: float = 1.0
var torso: float = 1.0
var head: float = 1.0
var width: float = 1.0


static func for_youth(value: float) -> BodyProportions:
	var p := BodyProportions.new()
	p.youth = clampf(value, 0.0, 1.0)
	var t := p.youth
	p.leg = lerpf(1.0, 0.44, t)
	p.torso = lerpf(1.0, 0.57, t)
	p.head = lerpf(1.0, 0.92, t)
	p.width = lerpf(1.0, 0.66, t)
	return p


## How child-like someone of this age looks (0 from about 17).
static func youth_for_age(age: float) -> float:
	return clampf((17.0 - age) / 13.5, 0.0, 1.0)


func is_adult() -> bool:
	return youth <= 0.0005


func map_height(y: float) -> float:
	if y <= LEG_TOP:
		return y * leg
	if y <= HEAD_BASE:
		return LEG_TOP * leg + (y - LEG_TOP) * torso
	return LEG_TOP * leg + (HEAD_BASE - LEG_TOP) * torso + (y - HEAD_BASE) * head


## Horizontal scale at an adult height: the body's width below the neck,
## the head's scale above it, blended over the neck.
func width_at(y: float) -> float:
	var t := smoothstep(HEAD_BASE - 0.1, HEAD_BASE - 0.02, y)
	return lerpf(width, head, t)


func map_point(p: Vector3) -> Vector3:
	var s := width_at(p.y)
	return Vector3(p.x * s, map_height(p.y), p.z * s)


## Normals transform with the inverse of the local scale.
func map_normal(n: Vector3, y: float) -> Vector3:
	var s := width_at(y)
	var sy := leg if y <= LEG_TOP else (torso if y <= HEAD_BASE else head)
	var mapped := Vector3(n.x / s, n.y / sy, n.z / s)
	return mapped.normalized() if mapped.length_squared() > 0.0 else n


## Total height for an adult-scale height (e.g. the top of the head).
func height_of(adult_height: float) -> float:
	return map_height(adult_height)
