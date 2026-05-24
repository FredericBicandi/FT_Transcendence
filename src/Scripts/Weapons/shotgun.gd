class_name Shotgun
extends WeaponSprite

const PELLET_COUNT := 6
const PELLET_SPREAD := 0.25
const TOTAL_DAMAGE := 72
var shell_reloading: bool = false
var shell_reload_generation: int = 0

func _ready() -> void:
	weapon_id = "Shotgun"
	super._ready()

func shoot() -> void:
	if fire_cooldown > 0.0:
		return
	var config := get_weapon_config()
	if current_ammo <= 0:
		reload()
		return
	if reload_cooldown > 0.0:
		_cancel_shell_reload()
	var raw_shot_target: Vector2 = aim_target_override if has_aim_target_override else get_global_mouse_position()
	update_aim(raw_shot_target)
	fire_cooldown = config.get("fire_rate", 0.2)
	current_ammo -= 1
	emit_ammo_changed()
	_play_fire_sound()
	var shot_start_position := get_shot_start_position(config)
	var desired_shot_target := get_current_frame_shot_target(shot_start_position, config) if should_use_current_frame_for_shot(raw_shot_target) else raw_shot_target
	var base_offset := desired_shot_target - shot_start_position
	var base_direction := base_offset.normalized() if base_offset != Vector2.ZERO else Vector2.RIGHT
	apply_recoil(base_direction, config)
	for i in range(PELLET_COUNT):
		var spread := randf_range(-PELLET_SPREAD, PELLET_SPREAD)
		_spawn_bullet(base_direction.rotated(spread), shot_start_position, true, _get_pellet_damage(i), null)
	shot_fired.emit(base_direction.angle(), get_weapon_name(), shot_start_position, desired_shot_target)
	if current_ammo <= 0:
		reload()

func _get_pellet_damage(pellet_index: int) -> int:
	var base_damage := TOTAL_DAMAGE / PELLET_COUNT
	var remainder := TOTAL_DAMAGE % PELLET_COUNT
	return base_damage + (1 if pellet_index < remainder else 0)

func reload() -> void:
	if reload_cooldown > 0.0 or current_ammo == get_magazine_size():
		return
	_load_next_shell()

func _load_next_shell() -> void:
	if current_ammo >= get_magazine_size():
		return
	shell_reloading = true
	shell_reload_generation += 1
	var reload_generation: int = shell_reload_generation
	var shell_reload_time: float = get_next_shell_reload_time()
	reload_duration = shell_reload_time
	reload_cooldown = reload_duration
	reload_pending = false
	var reload_sound = get_weapon_config().get("reload_sound")
	if reload_sound:
		reload_audio_player.stream = reload_sound
		reload_audio_player.play()
	get_tree().create_timer(shell_reload_time).timeout.connect(func():
		if not is_inside_tree() or not shell_reloading or reload_generation != shell_reload_generation:
			return
		current_ammo += 1
		emit_ammo_changed()
		if current_ammo < get_magazine_size():
			_load_next_shell()
		else:
			shell_reloading = false
	)

func get_next_shell_reload_time() -> float:
	if current_ammo > 0:
		return get_reload_time()

	return maxf(float(get_weapon_config().get("empty_reload_time", get_reload_time())), get_reload_time())

func _cancel_shell_reload() -> void:
	shell_reloading = false
	shell_reload_generation += 1
	reload_cooldown = 0.0
	reload_duration = 0.0
	if reload_audio_player != null and reload_audio_player.playing:
		reload_audio_player.stop()

func reset_state() -> void:
	shell_reloading = false
	shell_reload_generation += 1
	super.reset_state()

func set_active(is_active: bool) -> void:
	# Cancel the queued shell-load chain when the shotgun is holstered;
	# pending timers re-check shell_reloading and bail out.
	if not is_active and shell_reloading:
		_cancel_shell_reload()
	super.set_active(is_active)
