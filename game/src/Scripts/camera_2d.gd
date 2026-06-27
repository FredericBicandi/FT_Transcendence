extends Camera2D

@export var follow_speed := 8.0
@export var focus_distance := 80.0

@onready var player: Player = get_parent()

func _process(delta: float) -> void:
	if player == null:
		return

	var target := player.global_position

	if player.is_sniper_scope_active():
		var mouse_pos := get_global_mouse_position()

		var focus_offset := mouse_pos - player.global_position
		focus_offset = focus_offset.limit_length(focus_distance)

		target += focus_offset

	global_position = global_position.lerp(
		target,
		clampf(delta * follow_speed, 0.0, 1.0)
	)
