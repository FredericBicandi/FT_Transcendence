class_name Shotgun
extends WeaponSprite

const PELLET_COUNT := 6
const PELLET_SPREAD := 0.25
var shell_reloading: bool = false

func _ready() -> void:
	weapon_id = "Shotgun"
	super._ready()

func shoot() -> void:
	if fire_cooldown > 0.0 or reload_cooldown > 0.0:
		return
	var config := get_weapon_config()
	if current_ammo <= 0:
		reload()
		return
	shell_reloading = false
	var raw_shot_target: Vector2 = aim_target_override if has_aim_target_override else get_global_mouse_position()
	update_aim(raw_shot_target)
	fire_cooldown = config.get("fire_rate", 0.2)
	current_ammo -= 1
	emit_ammo_changed()
	_play_fire_sound()
	var shot_start_position := get_shot_start_position(config)
	var base_offset := raw_shot_target - shot_start_position
	var base_direction := base_offset.normalized() if base_offset != Vector2.ZERO else Vector2.RIGHT
	apply_recoil(base_direction, config)
	for i in range(PELLET_COUNT):
		var spread := randf_range(-PELLET_SPREAD, PELLET_SPREAD)
		_spawn_bullet(base_direction.rotated(spread), shot_start_position, true, -1, null)
	shot_fired.emit(base_direction.angle(), get_weapon_name(), shot_start_position, raw_shot_target)
	if current_ammo <= 0:
		reload()

func reload() -> void:
	if reload_cooldown > 0.0 or current_ammo == get_magazine_size():
		return
	_load_next_shell()

func _load_next_shell() -> void:
	if current_ammo >= get_magazine_size():
		return
	shell_reloading = true
	reload_duration = get_reload_time()
	reload_cooldown = reload_duration
	reload_pending = false
	var reload_sound = get_weapon_config().get("reload_sound")
	if reload_sound:
		reload_audio_player.stream = reload_sound
		reload_audio_player.play()
	get_tree().create_timer(get_reload_time()).timeout.connect(func():
		if not shell_reloading:
			return
		current_ammo += 1
		emit_ammo_changed()
		if current_ammo < get_magazine_size():
			_load_next_shell()
		else:
			shell_reloading = false
	)
