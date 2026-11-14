class_name FloatingText
extends Label3D
## "+2 Wood" text that rises and fades above where something happened.

const LIFETIME := 1.6

var _age: float = 0.0


static func spawn(parent: Node, at: Vector3, text_value: String, color: Color = Color(1.0, 0.92, 0.6)) -> void:
	var label := FloatingText.new()
	label.text = text_value
	label.modulate = color
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 64
	label.outline_size = 16
	label.outline_modulate = Color(0.1, 0.07, 0.05, 0.9)
	label.pixel_size = 0.005
	parent.add_child(label)
	label.global_position = at


func _process(delta: float) -> void:
	_age += delta
	position.y += delta * 0.8
	modulate.a = clampf(1.6 - _age, 0.0, 1.0)
	if _age >= LIFETIME:
		queue_free()
