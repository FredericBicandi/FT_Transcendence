class_name TargetArcIndicator
extends Node2D

const CENTER_DOT_COLOR := Color(1.0, 0.0, 0.0, 1.0)
const CENTER_DOT_RADIUS := 1.5

var radius: float = 1.0
var center_dot_radius: float = CENTER_DOT_RADIUS
var fill_color: Color = Color(1.0, 0.12, 0.35, 0.22)

func configure(next_radius: float, next_fill_color: Color, next_center_dot_radius: float = CENTER_DOT_RADIUS) -> void:
	var clamped_radius := maxf(next_radius, 1.0)
	var clamped_center_dot_radius := maxf(next_center_dot_radius, 0.1)
	if (
		is_equal_approx(radius, clamped_radius)
		and is_equal_approx(center_dot_radius, clamped_center_dot_radius)
		and fill_color == next_fill_color
	):
		return

	radius = clamped_radius
	center_dot_radius = clamped_center_dot_radius
	fill_color = next_fill_color
	queue_redraw()

func _draw() -> void:
	draw_circle(Vector2.ZERO, radius, fill_color)
	draw_circle(Vector2.ZERO, center_dot_radius, CENTER_DOT_COLOR)
