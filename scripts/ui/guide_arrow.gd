class_name GuideArrow
extends Control
## An arrow at the edge of the screen pointing to the Guide's target when it's
## off-screen (or far away), with what it is and how far.

const MARGIN := 70.0
const COLOR := Color(1.0, 0.86, 0.35)

## Where the arrow is drawn, and which way it points (for tests).
var arrow_position := Vector2.ZERO
var arrow_direction := Vector2.ZERO
var showing: bool = false


func _ready() -> void:
	name = "GuideArrow"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	showing = _update()
	queue_redraw()


func _update() -> bool:
	var guide := Guide.instance
	var camera := get_viewport().get_camera_3d()
	var player = GameManager.player
	if guide == null or camera == null or player == null or not guide.enabled or guide.target == Vector3.INF:
		return false
	if GameManager.is_in_conversation() or GameManager.camera_mode != GameManager.CameraMode.EXPLORATION:
		return false
	var screen := get_viewport_rect().size
	var point := guide.target + Vector3(0, 1.5, 0)
	var behind := camera.is_position_behind(point)
	var projected := camera.unproject_position(point)
	var inside := Rect2(Vector2.ZERO, screen).grow(-MARGIN).has_point(projected)
	if inside and not behind:
		return false
	var center := screen * 0.5
	var direction := projected - center
	if behind:
		direction = -direction
	if direction.length() < 1.0:
		direction = Vector2(0, 1)
	direction = direction.normalized()
	# Push out to the screen edge (inside the margin).
	var half := center - Vector2(MARGIN, MARGIN)
	var scale := minf(half.x / maxf(absf(direction.x), 0.001), half.y / maxf(absf(direction.y), 0.001))
	arrow_position = center + direction * scale
	arrow_direction = direction
	return true


func _draw() -> void:
	if not showing:
		return
	var guide := Guide.instance
	var tip := arrow_position + arrow_direction * 26.0
	var side := Vector2(-arrow_direction.y, arrow_direction.x)
	var base := arrow_position - arrow_direction * 10.0
	var points := PackedVector2Array([tip, base + side * 20.0, base - side * 20.0])
	draw_circle(arrow_position, 34.0, Color(0.12, 0.08, 0.05, 0.75))
	draw_colored_polygon(points, COLOR)
	var font := get_theme_default_font()
	var distance := int(round(GameManager.player.global_position.distance_to(guide.target)))
	var text := "%s · %d m" % [guide.target_label, distance]
	var size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20)
	var at := arrow_position - arrow_direction * 58.0 - Vector2(size.x * 0.5, -6.0)
	at.x = clampf(at.x, 8.0, get_viewport_rect().size.x - size.x - 8.0)
	at.y = clampf(at.y, 24.0, get_viewport_rect().size.y - 8.0)
	draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, 6, Color(0.1, 0.07, 0.04, 0.9))
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, COLOR)
