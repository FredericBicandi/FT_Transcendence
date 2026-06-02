class_name KillFeedDeathIcon
extends Control

const ICON_SIZE := Vector2(28.0, 22.0)
const ICON_COLOR := Color(0.92, 0.95, 1.0, 1.0)
const SHADOW_COLOR := Color(0.0, 0.0, 0.0, 0.75)
const HOLE_COLOR := Color(0.05, 0.06, 0.08, 1.0)

func _ready() -> void:
	custom_minimum_size = ICON_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	_draw_icon(Vector2(1.0, 1.0), SHADOW_COLOR, SHADOW_COLOR)
	_draw_icon(Vector2.ZERO, ICON_COLOR, HOLE_COLOR)

func _draw_icon(offset: Vector2, color: Color, hole_color: Color) -> void:
	var draw_size := size
	if draw_size == Vector2.ZERO:
		draw_size = ICON_SIZE

	var scale: float = minf(draw_size.x / ICON_SIZE.x, draw_size.y / ICON_SIZE.y)
	var center := draw_size * 0.5 + offset

	var left_bone_start := center + Vector2(-9.0, 6.0) * scale
	var left_bone_end := center + Vector2(9.0, 12.0) * scale
	var right_bone_start := center + Vector2(9.0, 6.0) * scale
	var right_bone_end := center + Vector2(-9.0, 12.0) * scale
	draw_line(left_bone_start, left_bone_end, color, 2.0 * scale)
	draw_line(right_bone_start, right_bone_end, color, 2.0 * scale)

	var skull_center := center + Vector2(0.0, -2.0) * scale
	draw_circle(skull_center, 6.0 * scale, color)
	draw_rect(Rect2(skull_center + Vector2(-4.0, 2.0) * scale, Vector2(8.0, 5.0) * scale), color)

	draw_circle(skull_center + Vector2(-2.3, -1.2) * scale, 1.35 * scale, hole_color)
	draw_circle(skull_center + Vector2(2.3, -1.2) * scale, 1.35 * scale, hole_color)
	draw_rect(Rect2(skull_center + Vector2(-1.0, 1.0) * scale, Vector2(2.0, 1.8) * scale), hole_color)
