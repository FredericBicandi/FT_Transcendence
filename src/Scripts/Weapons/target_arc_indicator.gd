class_name TargetArcIndicator
extends Node2D

const CENTER_DOT_COLOR := Color(1.0, 0.0, 0.0, 1.0)
const CENTER_DOT_RADIUS := 1.5

var radius: float = 1.0
var fill_color: Color = Color(1.0, 0.12, 0.35, 0.22)

func configure(next_radius: float, next_fill_color: Color) -> void:
	var clamped_radius := maxf(next_radius, 1.0)
	if (
		is_equal_approx(radius, clamped_radius)
		and fill_color == next_fill_color
	):
		return

	radius = clamped_radius
	fill_color = next_fill_color
	queue_redraw()

func _draw() -> void:
	draw_circle(Vector2.ZERO, radius, fill_color)
	draw_circle(Vector2.ZERO, CENTER_DOT_RADIUS, CENTER_DOT_COLOR)
