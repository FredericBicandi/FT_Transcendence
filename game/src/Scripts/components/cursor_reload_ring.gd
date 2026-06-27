extends Node2D

@export var ring_radius: int = 7
@export var segment_size := Vector2i(2, 2)
@export var segment_count: int = 16
@export var active_color := Color(1.0, 0.82, 0.22, 1.0)
@export var lead_color := Color(1.0, 0.97, 0.55, 1.0)
@export var inactive_color := Color(0.08, 0.08, 0.08, 0.72)
@export var shadow_color := Color(0.0, 0.0, 0.0, 0.65)

var progress: float = 0.0
var ring_visible: bool = false

func _ready() -> void:
	z_index = 11
	z_as_relative = false

func _process(_delta: float) -> void:
	if not ring_visible:
		return

	# Keep drawing crisp without detaching the ring from the cursor parent.
	position = Vector2.ZERO
	queue_redraw()

func set_progress(new_progress: float) -> void:
	var clamped_progress := clampf(new_progress, 0.0, 1.0)
	if absf(clamped_progress - progress) < 0.01 and ring_visible:
		return
	progress = clamped_progress
	queue_redraw()

func set_ring_visible(should_show: bool) -> void:
	if ring_visible == should_show:
		return
	ring_visible = should_show
	queue_redraw()

func _draw() -> void:
	if not ring_visible:
		return

	var safe_segment_count := maxi(segment_count, 1)
	var filled_segments := ceili(progress * float(safe_segment_count))
	var lead_index := clampi(filled_segments - 1, 0, safe_segment_count - 1)

	for index in range(safe_segment_count):
		var angle := -PI / 2.0 + TAU * float(index) / float(safe_segment_count)
		var segment_center := Vector2(cos(angle), sin(angle)) * float(ring_radius)
		var segment_position := (segment_center - Vector2(segment_size) * 0.5).round()
		var segment_rect := Rect2(segment_position, Vector2(segment_size))

		# Draw chunky square ticks instead of anti-aliased arcs for a pixel-art read.
		draw_rect(Rect2(segment_rect.position + Vector2.ONE, segment_rect.size), shadow_color)
		draw_rect(segment_rect, _get_segment_color(index, filled_segments, lead_index))

func _get_segment_color(index: int, filled_segments: int, lead_index: int) -> Color:
	if index >= filled_segments:
		return inactive_color

	if index == lead_index:
		return lead_color

	return active_color
