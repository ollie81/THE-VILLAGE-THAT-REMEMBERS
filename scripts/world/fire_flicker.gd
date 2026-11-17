extends MeshInstance3D
## Cheap fire animation: wobbles the flame mesh and the nearby fire light.

var _time := 0.0
var _light: OmniLight3D


func _ready() -> void:
	_light = get_parent().get_node_or_null("FireLight") as OmniLight3D


func _process(delta: float) -> void:
	_time += delta
	var flicker := 0.85 + sin(_time * 11.0) * 0.08 + sin(_time * 17.3 + 1.2) * 0.07
	scale = Vector3(0.9 + sin(_time * 7.0) * 0.08, flicker * 1.1, 0.9 + cos(_time * 6.3) * 0.08)
	rotation.y += delta * 0.6
	if _light and _light.has_meta("current_energy"):
		_light.light_energy = float(_light.get_meta("current_energy")) * flicker
