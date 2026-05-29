extends Camera2D

@export var follow_speed := 8.0
@export var focus_distance := 80.0

@onready var player: Player = get_parent()

func _process(delta: float) -> void:
	if player == null:
		return

	var target := player.global_position

	# check if sniper is equipped
	var active_weapon := player.weapon.get_active_weapon()

	var is_sniper := false
	if active_weapon != null:
		is_sniper = active_weapon.get_weapon_name() == "Sniper"

	# only allow focus mode when sniper is equipped + RMB held
	if is_sniper and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		var mouse_pos := get_global_mouse_position()

		var offset := mouse_pos - player.global_position
		offset = offset.limit_length(focus_distance)

		target += offset

	global_position = global_position.lerp(
		target,
		clampf(delta * follow_speed, 0.0, 1.0)
	)
