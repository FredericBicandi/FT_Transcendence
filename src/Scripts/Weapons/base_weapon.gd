class_name BaseWeapon
extends Node2D

const WeaponData = preload("res://src/Scripts/Weapons/weapon_data.gd")
const Projectile = preload("res://src/Scripts/Weapons/projectile.gd")
const TargetArcIndicatorScript = preload("res://src/Scripts/Weapons/target_arc_indicator.gd")
const DAMAGEABLE_PLAYER_GROUP := "damageable_player"
const DEFAULT_MUZZLE_COLLISION_MASK := 1
const DEFAULT_MUZZLE_WALL_PADDING := 1.5
const DEFAULT_MUZZLE_WALL_VISUAL_PULLBACK := 4.0
const DEFAULT_MUZZLE_WALL_MIN_VISUAL_SCALE := 0.6
const DEFAULT_TARGET_ARC_SELF_AIM_DISTANCE := 96.0
const DEFAULT_TARGET_ARC_INDICATOR_FILL_COLOR := Color(1.0, 0.12, 0.35, 0.22)
const MAX_ACTIVE_BULLETS_PER_WEAPON := 128

signal ammo_changed(current_ammo: int, max_ammo: int)
signal shot_fired(angle_radians: float, weapon_type: String, start_position: Vector2, target_position: Vector2)

@export var weapon_id: String = WeaponData.DEFAULT_WEAPON_ID
@export var muzzle_collision_mask: int = DEFAULT_MUZZLE_COLLISION_MASK
@export var muzzle_wall_padding: float = DEFAULT_MUZZLE_WALL_PADDING
@export var muzzle_wall_visual_pullback: float = DEFAULT_MUZZLE_WALL_VISUAL_PULLBACK
@export var muzzle_wall_min_visual_scale: float = DEFAULT_MUZZLE_WALL_MIN_VISUAL_SCALE

var active_bullets: Array[Dictionary] = []
var current_frame_index: int = 0
var fire_cooldown: float = 0.0
var reload_cooldown: float = 0.0
var reload_duration: float = 0.0
var base_position: Vector2
var movement_offset: Vector2 = Vector2.ZERO
var recoil_offset: Vector2 = Vector2.ZERO
var bullet_exclude_rids: Array[RID] = []
var current_ammo: int = 0
var accepts_player_input: bool = true
var has_aim_target_override: bool = false
var aim_target_override: Vector2 = Vector2.ZERO
var collision_mask_override: int = -1
var reload_pending: bool = false
var reload_audio_player: AudioStreamPlayer2D
var is_active_weapon: bool = false
var has_safe_muzzle_position: bool = false
var safe_muzzle_position: Vector2 = Vector2.ZERO
var base_gun_scale: Vector2 = Vector2.ONE
var fire_locked_until_click_released: bool = false
var muzzle_raycast_cache_valid: bool = false
var muzzle_raycast_cache_origin: Vector2 = Vector2.INF
var muzzle_raycast_cache_frame: int = -1
var muzzle_raycast_cache_gun_position: Vector2 = Vector2.ZERO
var muzzle_raycast_cache_gun_scale: Vector2 = Vector2.ONE
var muzzle_raycast_cache_safe_position: Vector2 = Vector2.ZERO
var muzzle_raycast_cache_has_safe_position: bool = false
var target_arc_indicator: Node2D
const MUZZLE_RAYCAST_CACHE_EPSILON: float = 0.5

@onready var gun: AnimatedSprite2D = $Gun
@onready var muzzle_marker: Marker2D = $Gun/Marker2D
@onready var shoot_audio_source: AudioStreamPlayer2D = $AudioStreamPlayer2D

func _ready() -> void:
	base_position = position
	var owner_body: CollisionObject2D = find_owner_body()

	if owner_body != null:
		bullet_exclude_rids.append(owner_body.get_rid())
		var owner_hitbox := owner_body.get_node_or_null("HitBox") as CollisionObject2D
		if owner_hitbox != null:
			bullet_exclude_rids.append(owner_hitbox.get_rid())

	if gun == null or muzzle_marker == null:
		push_error("Weapon node %s is missing Gun/Marker2D." % name)
		set_process(false)
		return

	base_gun_scale = gun.scale
	_load_bullet_template()

	current_ammo = get_magazine_size()
	apply_frame_data(0)
	set_active(false)
	emit_ammo_changed()

	reload_audio_player = AudioStreamPlayer2D.new()
	add_child(reload_audio_player)

func _exit_tree() -> void:
	_free_target_arc_indicator()
	_clear_active_bullets()

func _process(delta: float) -> void:
	fire_cooldown = maxf(fire_cooldown - delta, 0.0)
	reload_cooldown = maxf(reload_cooldown - delta, 0.0)

	var recoil_recover_speed: float = float(get_weapon_config().get("recoil_recover_speed", 18.0))
	recoil_offset = recoil_offset.lerp(Vector2.ZERO, clampf(delta * recoil_recover_speed, 0.0, 1.0))
	position = base_position + movement_offset + recoil_offset

	if reload_pending and reload_cooldown == 0.0:
		current_ammo = get_magazine_size()
		reload_pending = false
		emit_ammo_changed()

	update_bullets(delta)

	if not is_active_weapon:
		_hide_target_arc_indicator()
		return

	if has_aim_target_override:
		update_aim(aim_target_override)
	else:
		update_aim(get_global_mouse_position())

	_update_target_arc_indicator()

	if accepts_player_input:
		if Input.is_key_pressed(KEY_R):
			reload()
		if fire_locked_until_click_released:
			if not Input.is_action_pressed("click"):
				fire_locked_until_click_released = false
			return
		if Input.is_action_pressed("click"):
			shoot()

# -- Virtual methods subclasses override --

func _load_bullet_template() -> void:
	pass

func _configure_spawned_bullet(bullet: Node2D, direction: Vector2, start_position: Vector2) -> void:
	pass

func _build_bullet_runtime_data(bullet: Node2D, direction: Vector2, bullet_lifetime: float, should_collide: bool, damage_override: int, pass_over_layers: Array[String], target_position: Variant = null) -> Dictionary:
	return Projectile.build_runtime_data(get_weapon_config(), bullet, direction, bullet_lifetime, should_collide, damage_override, collision_mask_override, pass_over_layers, target_position)

func _create_bullet_node() -> Node2D:
	return Node2D.new()

func _update_bullet_visual(bullet: Node2D, result: Dictionary) -> void:
	pass

func _play_impact_effect(position: Vector2) -> void:
	_apply_impact_screen_shake(position)
	_play_impact_sound(position)

func _free_bullet_node(bullet_instance_id: int) -> void:
	var bullet := instance_from_id(bullet_instance_id) as Node2D
	if bullet != null and is_instance_valid(bullet):
		bullet.queue_free()

# -- End virtual methods --

func set_active(is_active: bool) -> void:
	is_active_weapon = is_active
	visible = is_active
	if not is_active:
		_hide_target_arc_indicator()

func update_movement(direction: Vector2) -> void:
	var config := get_weapon_config()
	var move_offset: float = config.get("move_offset", 0.0)
	if direction == Vector2.ZERO:
		movement_offset = Vector2.ZERO
		return
	movement_offset = direction.normalized() * move_offset

func update_aim(target_position: Vector2) -> void:
	var dir: Vector2 = (target_position - global_position).normalized()
	var angle: float = rad_to_deg(dir.angle())
	if angle < 0.0:
		angle += 360.0
	apply_frame_data(angle_to_frame(angle))

func get_aim_frame() -> int:
	return current_frame_index

func get_bullet_frame() -> int:
	var config := get_weapon_config()
	var bullet_frames_map: Array = config.get("bullet_frames", [])
	if current_frame_index < bullet_frames_map.size():
		return int(bullet_frames_map[current_frame_index])
	return current_frame_index

func get_projectile_frame_for_direction(direction: Vector2) -> int:
	return Projectile.get_frame_for_direction(get_weapon_config(), get_bullet_frame(), direction)

func uses_projectile_frame_mapping() -> bool:
	return Projectile.uses_frame_mapping(get_weapon_config())

func get_pass_over_tilemap_layers() -> Array[String]:
	return Projectile.get_pass_over_tilemap_layers(get_weapon_config())

func get_bullet_visual_z_index() -> int:
	return Projectile.get_visual_z_index(get_weapon_config(), gun.z_index)

func get_spawned_bullet_frame(direction: Vector2) -> int:
	if uses_projectile_frame_mapping():
		return get_projectile_frame_for_direction(direction)
	return get_bullet_frame()

func get_current_frame_direction() -> Vector2:
	return Vector2.RIGHT.rotated(deg_to_rad(float(current_frame_index) * 45.0)).normalized()

func should_use_current_frame_for_shot(target_position: Vector2) -> bool:
	if has_aim_target_override:
		return false

	var owner_body := find_owner_body()
	if owner_body == null or not owner_body.has_method("is_local_aim_target_on_self"):
		return false

	return bool(owner_body.call("is_local_aim_target_on_self", target_position))

func get_current_frame_shot_target(start_position: Vector2, config: Dictionary) -> Vector2:
	var bullet_speed := maxf(float(config.get("bullet_speed", 320.0)), 1.0)
	var bullet_lifetime := maxf(float(config.get("bullet_lifetime", 1.0)), 0.1)
	var shot_distance := bullet_speed * bullet_lifetime
	if Projectile.uses_target_arc(config):
		shot_distance = maxf(float(config.get("target_arc_self_aim_distance", DEFAULT_TARGET_ARC_SELF_AIM_DISTANCE)), 1.0)
	return start_position + get_current_frame_direction() * shot_distance

func clamp_target_arc_shot_target(range_origin: Vector2, target_position: Vector2, config: Dictionary) -> Vector2:
	if not Projectile.uses_target_arc(config):
		return target_position

	var max_distance := maxf(float(config.get("target_arc_max_distance", 0.0)), 0.0)
	if max_distance <= 0.0:
		return target_position

	var target_offset := target_position - range_origin
	if target_offset.length() <= max_distance:
		return target_position

	return range_origin + target_offset.limit_length(max_distance)

func get_target_arc_range_origin(fallback_position: Vector2) -> Vector2:
	var owner_body := find_owner_body()
	if owner_body != null:
		return owner_body.global_position
	return fallback_position

func shoot() -> void:
	if fire_cooldown > 0.0 or reload_cooldown > 0.0:
		return

	var config := get_weapon_config()

	if current_ammo <= 0:
		reload()
		return

	var raw_shot_target: Vector2 = aim_target_override if has_aim_target_override else get_global_mouse_position()
	update_aim(raw_shot_target)

	fire_cooldown = config.get("fire_rate", 0.2)
	current_ammo -= 1
	emit_ammo_changed()

	_play_fire_sound()

	var shot_start_position := get_shot_start_position(config)
	var frame_shot_target := get_current_frame_shot_target(shot_start_position, config)
	var uses_target_arc := Projectile.uses_target_arc(config)
	var should_use_frame_target := should_use_current_frame_for_shot(raw_shot_target) and not uses_target_arc
	var desired_shot_target := frame_shot_target if should_use_frame_target else raw_shot_target
	var range_origin := get_target_arc_range_origin(shot_start_position) if uses_target_arc else shot_start_position
	desired_shot_target = clamp_target_arc_shot_target(range_origin, desired_shot_target, config)
	var shot_target := _resolve_shot_target(shot_start_position, desired_shot_target, config)
	var bullet_offset := shot_target - shot_start_position
	var bullet_direction := bullet_offset.normalized() if bullet_offset != Vector2.ZERO else Vector2.RIGHT
	apply_recoil(bullet_direction, config)
	_spawn_bullet(bullet_direction, shot_start_position, true, -1, shot_target)
	shot_fired.emit(bullet_direction.angle(), get_weapon_name(), shot_start_position, shot_target)

	if current_ammo <= 0:
		reload()

func spawn_remote_bullet(angle_radians: float, target_position: Variant = null, start_position: Variant = null) -> void:
	var config := get_weapon_config()
	var shot_start_position := get_shot_start_position(config)
	if start_position is Vector2:
		shot_start_position = start_position as Vector2

	var has_target_position := target_position is Vector2
	var aim_target := shot_start_position + Vector2.RIGHT.rotated(angle_radians) * 32.0
	if has_target_position:
		aim_target = target_position as Vector2

	var bullet_offset := aim_target - shot_start_position
	var bullet_direction := bullet_offset.normalized() if has_target_position and bullet_offset != Vector2.ZERO else Vector2.RIGHT.rotated(angle_radians)
	update_aim(aim_target)
	if not (start_position is Vector2):
		shot_start_position = get_shot_start_position(config)

	apply_recoil(bullet_direction, config)
	_play_fire_sound()

	var replay_target: Variant = aim_target if has_target_position else null
	_spawn_bullet(bullet_direction, shot_start_position, true, 0, replay_target)

func _play_fire_sound() -> void:
	var fire_sound: AudioStream = null
	if shoot_audio_source != null:
		fire_sound = shoot_audio_source.stream
	if fire_sound == null:
		fire_sound = get_weapon_config().get("fire_sound")
	if fire_sound:
		var owner_body := find_owner_body()
		if owner_body != null and owner_body.has_method("play_shoot_sound"):
			owner_body.call("play_shoot_sound", fire_sound)

func _clear_active_bullets() -> void:
	for bullet_data_variant in active_bullets:
		var bullet_data: Dictionary = bullet_data_variant
		_free_bullet_node(int(bullet_data.get("instance_id", 0)))

	active_bullets.clear()

func _play_impact_sound(position: Vector2) -> void:
	var impact_sound: AudioStream = get_weapon_config().get("impact_sound")
	if impact_sound == null:
		return

	var current_scene := get_tree().current_scene
	if current_scene == null:
		return

	var impact_audio := AudioStreamPlayer2D.new()
	impact_audio.stream = impact_sound
	impact_audio.max_distance = float(get_weapon_config().get("impact_sound_max_distance", 700.0))
	impact_audio.attenuation = float(get_weapon_config().get("impact_sound_attenuation", 1.0))
	impact_audio.volume_db = float(get_weapon_config().get("impact_sound_volume_db", 0.0))
	current_scene.add_child(impact_audio)
	impact_audio.global_position = position
	impact_audio.finished.connect(impact_audio.queue_free)
	impact_audio.play()

func _apply_impact_screen_shake(position: Vector2) -> void:
	var config := get_weapon_config()
	var shake_radius := float(config.get("impact_shake_radius", 0.0))
	var shake_strength := float(config.get("impact_shake_strength", 0.0))
	var shake_duration := float(config.get("impact_shake_duration", 0.0))
	if shake_radius <= 0.0 or shake_strength <= 0.0 or shake_duration <= 0.0:
		return

	for candidate in get_tree().get_nodes_in_group("player"):
		if candidate != null and candidate.has_method("apply_screen_shake"):
			candidate.call("apply_screen_shake", position, shake_radius, shake_strength, shake_duration)

func apply_recoil(direction: Vector2, config: Dictionary) -> void:
	var recoil_distance: float = float(config.get("recoil_distance", 2.5))
	var recoil_jitter: float = float(config.get("recoil_jitter", 0.35))
	var sideways := direction.orthogonal() * randf_range(-recoil_jitter, recoil_jitter)
	recoil_offset = (-direction + sideways).normalized() * recoil_distance

func update_bullets(delta: float) -> void:
	var space_state := get_world_2d().direct_space_state

	for i in range(active_bullets.size() - 1, -1, -1):
		var bullet_data := active_bullets[i]
		var bullet_instance_id := int(bullet_data.get("instance_id", 0))
		var bullet := instance_from_id(bullet_instance_id) as Node2D

		if bullet == null or not is_instance_valid(bullet):
			active_bullets.remove_at(i)
			continue

		var result := Projectile.tick(bullet_data, delta)
		var start_position: Vector2 = result["start_position"]
		var end_position: Vector2 = result["position"]
		var collision_start_position: Vector2 = result.get("collision_start_position", start_position)
		var collision_end_position: Vector2 = result.get("collision_position", end_position)
		var collision_mask: int = bullet_data["collision_mask"]
		var damage: int = bullet_data["damage"]
		var should_collide: bool = bool(bullet_data.get("collides", true))
		var pass_over_layers: Array[String] = _to_string_array(bullet_data.get("pass_over_layers", []))
		var hit: Dictionary = {}
		if should_collide and collision_mask != 0:
			hit = raycast_bullet(space_state, collision_start_position, collision_end_position, collision_mask, pass_over_layers)

		if not hit.is_empty():
			_play_impact_effect(hit.get("position", bullet.global_position))
			apply_bullet_hit(hit, damage)
			bullet.global_position = hit["position"]
			bullet.queue_free()
			active_bullets.remove_at(i)
			continue

		if bool(result.get("landed", false)):
			_play_impact_effect(end_position)
			apply_bullet_hit({ "position": end_position }, damage)
			bullet.global_position = end_position
			bullet.queue_free()
			active_bullets.remove_at(i)
			continue

		bullet.global_position = end_position
		_update_bullet_visual(bullet, result)

		if not bool(result["alive"]):
			bullet.queue_free()
			active_bullets.remove_at(i)
			continue

		active_bullets[i] = bullet_data

func raycast_bullet(space_state: PhysicsDirectSpaceState2D, from: Vector2, to: Vector2, collision_mask: int, pass_over_layers: Array[String] = []) -> Dictionary:
	return Projectile.raycast(space_state, from, to, collision_mask, bullet_exclude_rids, pass_over_layers)

func _resolve_shot_target(start_position: Vector2, target_position: Vector2, config: Dictionary) -> Vector2:
	if not Projectile.uses_target_arc(config):
		return target_position

	var collision_mask := collision_mask_override if collision_mask_override >= 0 else int(config.get("bullet_collision_mask", 1))
	if collision_mask == 0:
		return target_position

	var hit := raycast_bullet(get_world_2d().direct_space_state, start_position, target_position, collision_mask, get_pass_over_tilemap_layers())
	if hit.is_empty():
		return target_position

	return hit.get("position", target_position)

func _update_target_arc_indicator() -> void:
	var config := get_weapon_config()
	if not _should_show_target_arc_indicator(config):
		_hide_target_arc_indicator()
		return

	var indicator := _ensure_target_arc_indicator(config)
	if indicator == null:
		return

	indicator.call(
		"configure",
		float(config.get("target_arc_indicator_radius", config.get("explosion_radius", 0.0))),
		_get_color_config(config, "target_arc_indicator_fill_color", DEFAULT_TARGET_ARC_INDICATOR_FILL_COLOR),
		float(config.get("target_arc_indicator_center_dot_radius", 1.5))
	)
	indicator.global_position = _get_target_arc_preview_position(get_global_mouse_position(), config)
	indicator.visible = true

func _get_target_arc_preview_position(raw_target: Vector2, config: Dictionary) -> Vector2:
	return clamp_target_arc_shot_target(get_target_arc_range_origin(global_position), raw_target, config)

func _should_show_target_arc_indicator(config: Dictionary) -> bool:
	return (
		is_active_weapon
		and accepts_player_input
		and not has_aim_target_override
		and Projectile.uses_target_arc(config)
		and bool(config.get("show_target_arc_indicator", false))
		and float(config.get("explosion_radius", 0.0)) > 0.0
	)

func _ensure_target_arc_indicator(config: Dictionary) -> Node2D:
	if target_arc_indicator != null and is_instance_valid(target_arc_indicator):
		return target_arc_indicator

	var parent := get_tree().current_scene
	if parent == null:
		return null

	target_arc_indicator = TargetArcIndicatorScript.new() as Node2D
	target_arc_indicator.name = "%sTargetArcIndicator" % get_weapon_name().replace(" ", "")
	target_arc_indicator.visible = false
	target_arc_indicator.z_index = int(config.get("target_arc_indicator_z_index", 1000))
	target_arc_indicator.z_as_relative = false
	parent.add_child(target_arc_indicator)
	return target_arc_indicator

func _hide_target_arc_indicator() -> void:
	if target_arc_indicator != null and is_instance_valid(target_arc_indicator):
		target_arc_indicator.visible = false

func _free_target_arc_indicator() -> void:
	if target_arc_indicator != null and is_instance_valid(target_arc_indicator):
		target_arc_indicator.queue_free()
	target_arc_indicator = null

func _get_color_config(config: Dictionary, key: String, fallback: Color) -> Color:
	var value: Variant = config.get(key, fallback)
	return value if value is Color else fallback

func _to_string_array(values: Variant) -> Array[String]:
	var result: Array[String] = []
	if not (values is Array):
		return result
	for value in values:
		result.append(str(value))
	return result

func _to_int_array(values: Variant) -> Array[int]:
	var result: Array[int] = []
	if not (values is Array):
		return result
	for value in values:
		result.append(int(value))
	return result

func find_owner_body() -> CollisionObject2D:
	var current: Node = get_parent()
	while current != null:
		if current is CollisionObject2D:
			return current as CollisionObject2D
		current = current.get_parent()
	return null

func apply_bullet_hit(hit: Dictionary, damage: int) -> void:
	if damage <= 0:
		return

	var collider := _resolve_damage_target(hit.get("collider"))
	var explosion_radius := float(get_weapon_config().get("explosion_radius", 0.0))
	if explosion_radius > 0.0:
		apply_explosion_damage(hit.get("position", Vector2.ZERO), explosion_radius, damage, collider)
		return

	if collider == null:
		return

	var owner_body := find_owner_body()
	if owner_body != null and owner_body.has_method("report_authoritative_hit"):
		if bool(owner_body.call("report_authoritative_hit", collider, damage, hit.get("position", Vector2.ZERO), self)):
			return

	if collider != null and collider.has_method("apply_damage"):
		collider.call("apply_damage", damage, hit.get("position", Vector2.ZERO), self)

func apply_explosion_damage(center: Vector2, radius: float, max_damage: int, direct_target: Node = null) -> void:
	if radius <= 0.0 or max_damage <= 0:
		return

	var owner_body: CollisionObject2D = find_owner_body()
	var damages_owner: bool = bool(get_weapon_config().get("explosion_damages_owner", false))
	var explosion_shot_id: String = _create_owner_shot_id(owner_body)
	for target in _collect_explosion_targets(center, radius, direct_target, damages_owner):
		if target == owner_body and not damages_owner:
			continue

		var damage := _get_explosion_damage_for_target(center, radius, max_damage, target, direct_target)
		if damage <= 0:
			continue

		if owner_body != null and owner_body.has_method("report_authoritative_hit"):
			if bool(owner_body.call("report_authoritative_hit", target, damage, center, self, explosion_shot_id)):
				continue

		target.call("apply_damage", damage, center, self)

func _collect_explosion_targets(center: Vector2, radius: float, direct_target: Node = null, include_owner: bool = false) -> Array[Node]:
	var targets: Array[Node] = []
	if direct_target != null and direct_target.has_method("apply_damage"):
		targets.append(direct_target)

	if include_owner:
		var owner_body: CollisionObject2D = find_owner_body()
		var owner_target: Node = _resolve_damage_target(owner_body)
		var owner_node: Node2D = owner_target as Node2D
		if (
			owner_target != null
			and not targets.has(owner_target)
			and owner_node != null
			and not bool(owner_target.get("is_dead"))
			and owner_node.global_position.distance_to(center) <= radius
		):
			targets.append(owner_target)

	for candidate in get_tree().get_nodes_in_group(DAMAGEABLE_PLAYER_GROUP):
		var target := _resolve_damage_target(candidate)
		if target == null or targets.has(target):
			continue
		var target_body := target as Node2D
		if target_body != null and not bool(target.get("is_dead")) and target_body.global_position.distance_to(center) <= radius:
			targets.append(target)

	var shape := CircleShape2D.new()
	shape.radius = radius
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, center)
	query.collision_mask = int(get_weapon_config().get("bullet_collision_mask", 1))
	query.exclude = bullet_exclude_rids

	for result in get_world_2d().direct_space_state.intersect_shape(query):
		var target := _resolve_damage_target(result.get("collider"))
		if target == null or targets.has(target):
			continue
		targets.append(target)

	return targets

func _resolve_damage_target(candidate: Variant) -> Node:
	if not (candidate is Node):
		return null
	var current := candidate as Node
	while current != null:
		if current.has_method("apply_damage"):
			return current
		current = current.get_parent()
	return null

func _create_owner_shot_id(owner_body: CollisionObject2D) -> String:
	if owner_body != null and owner_body.has_method("create_authoritative_shot_id"):
		return str(owner_body.call("create_authoritative_shot_id"))
	return "%s:%d:%d" % [get_weapon_name(), get_instance_id(), Time.get_ticks_usec()]

func _get_explosion_damage_for_target(center: Vector2, radius: float, max_damage: int, target: Node, direct_target: Node = null) -> int:
	if target == direct_target:
		return max_damage
	var target_body := target as Node2D
	if target_body == null:
		return 0
	var distance := target_body.global_position.distance_to(center)
	if distance > radius:
		return 0
	var falloff_power := maxf(float(get_weapon_config().get("explosion_falloff_power", 1.0)), 0.001)
	var falloff := pow(1.0 - clampf(distance / radius, 0.0, 1.0), falloff_power)
	var minimum_damage := clampi(int(get_weapon_config().get("explosion_min_damage", 1)), 1, max_damage)
	return clampi(ceili(float(max_damage) * falloff), minimum_damage, max_damage)

func reload() -> void:
	if reload_cooldown > 0.0 or current_ammo == get_magazine_size():
		return
	reload_duration = get_reload_time()
	reload_cooldown = reload_duration
	reload_pending = true
	var reload_sound = get_weapon_config().get("reload_sound")
	if reload_sound:
		reload_audio_player.stream = reload_sound
		reload_audio_player.play()

func get_magazine_size() -> int:
	return int(get_weapon_config().get("ammo_mag_size", 1))

func get_reload_time() -> float:
	return float(get_weapon_config().get("reload_time", 1.0))

func get_current_ammo() -> int:
	return current_ammo

func get_weapon_name() -> String:
	return weapon_id

func hides_cursor_when_selected() -> bool:
	return bool(get_weapon_config().get("hide_cursor_when_selected", false))

func set_input_enabled(is_enabled: bool) -> void:
	accepts_player_input = is_enabled
	if not is_enabled:
		fire_locked_until_click_released = false
		_hide_target_arc_indicator()

func lock_fire_until_click_released() -> void:
	fire_locked_until_click_released = Input.is_action_pressed("click")

func set_aim_target(target_position: Vector2) -> void:
	has_aim_target_override = true
	aim_target_override = target_position
	_hide_target_arc_indicator()

func clear_aim_target() -> void:
	has_aim_target_override = false

func set_collision_mask_override(mask: int) -> void:
	collision_mask_override = mask

func reset_state() -> void:
	fire_cooldown = 0.0
	reload_cooldown = 0.0
	reload_duration = 0.0
	reload_pending = false
	has_safe_muzzle_position = false
	muzzle_raycast_cache_valid = false
	current_ammo = get_magazine_size()
	movement_offset = Vector2.ZERO
	recoil_offset = Vector2.ZERO
	position = base_position

	_clear_active_bullets()
	emit_ammo_changed()

func get_weapon_icon() -> Texture2D:
	var weapon_image: Variant = get_weapon_config().get("image")
	if weapon_image is Texture2D:
		return weapon_image as Texture2D
	if gun == null or gun.sprite_frames == null:
		return null
	return gun.sprite_frames.get_frame_texture(&"default", 0)

func get_weapon_crosshair() -> Texture2D:
	var weapon_image: Variant = get_weapon_config().get("image")
	if not (weapon_image is Texture2D):
		return null

	var image_path := (weapon_image as Texture2D).resource_path
	if image_path == "":
		return null

	var crosshair_path := image_path.get_base_dir().path_join("crosshair.png")
	if not ResourceLoader.exists(crosshair_path, "Texture2D"):
		return null

	return load(crosshair_path) as Texture2D

func is_reloading() -> bool:
	return reload_cooldown > 0.0

func get_reload_progress() -> float:
	if not is_reloading() or reload_duration <= 0.0:
		return 0.0
	return clampf(1.0 - (reload_cooldown / reload_duration), 0.0, 1.0)

func get_weapon_config() -> Dictionary:
	if WeaponData.WEAPON_DATA.has(weapon_id):
		return WeaponData.WEAPON_DATA[weapon_id]
	return WeaponData.WEAPON_DATA[WeaponData.DEFAULT_WEAPON_ID]

func angle_to_frame(angle: float) -> int:
	if angle >= 337.5 or angle < 22.5:
		return 0
	if angle < 67.5:
		return 1
	if angle < 112.5:
		return 2
	if angle < 157.5:
		return 3
	if angle < 202.5:
		return 4
	if angle < 247.5:
		return 5
	if angle < 292.5:
		return 6
	return 7

func apply_frame_data(frame_index: int) -> void:
	current_frame_index = frame_index
	if gun.frame != frame_index:
		gun.frame = frame_index
	gun.scale = base_gun_scale
	has_safe_muzzle_position = false
	var config := get_weapon_config()
	var frame_data: Dictionary = config["frames"][frame_index]
	gun.position = frame_data["gun_position"]
	muzzle_marker.position = frame_data["muzzle_offset"]
	_keep_muzzle_out_of_walls_cached(config, frame_index)

func _keep_muzzle_out_of_walls_cached(config: Dictionary, frame_index: int) -> void:
	# The raycast result depends on the weapon owner's global position and
	# the current 8-direction frame. Skip the physics query while neither
	# changes meaningfully — this is the hot path for every active weapon
	# in the scene, every frame.
	var owner_origin := global_position
	if (
		muzzle_raycast_cache_valid
		and muzzle_raycast_cache_frame == frame_index
		and muzzle_raycast_cache_origin.distance_squared_to(owner_origin) <= MUZZLE_RAYCAST_CACHE_EPSILON * MUZZLE_RAYCAST_CACHE_EPSILON
	):
		if muzzle_raycast_cache_has_safe_position:
			gun.position = muzzle_raycast_cache_gun_position
			gun.scale = muzzle_raycast_cache_gun_scale
			has_safe_muzzle_position = true
			safe_muzzle_position = muzzle_raycast_cache_safe_position
		return

	keep_muzzle_out_of_walls(config)
	muzzle_raycast_cache_valid = true
	muzzle_raycast_cache_frame = frame_index
	muzzle_raycast_cache_origin = owner_origin
	muzzle_raycast_cache_has_safe_position = has_safe_muzzle_position
	muzzle_raycast_cache_gun_position = gun.position
	muzzle_raycast_cache_gun_scale = gun.scale
	muzzle_raycast_cache_safe_position = safe_muzzle_position

func get_shot_start_position(config: Dictionary) -> Vector2:
	if has_safe_muzzle_position:
		return safe_muzzle_position
	return get_safe_muzzle_position(config, muzzle_marker.global_position)

func keep_muzzle_out_of_walls(config: Dictionary) -> void:
	if not is_inside_tree() or gun == null or muzzle_marker == null:
		return
	var desired_muzzle := muzzle_marker.global_position
	var safe_muzzle := get_safe_muzzle_position(config, desired_muzzle)
	if safe_muzzle == desired_muzzle:
		return
	has_safe_muzzle_position = true
	safe_muzzle_position = safe_muzzle
	var full_delta := to_local(safe_muzzle) - to_local(desired_muzzle)
	var visual_pullback_limit := maxf(float(config.get("muzzle_wall_visual_pullback", muzzle_wall_visual_pullback)), 0.0)
	var visual_delta := full_delta.limit_length(visual_pullback_limit)
	gun.position += visual_delta
	scale_wall_blocked_weapon(config, safe_muzzle, desired_muzzle)

func scale_wall_blocked_weapon(config: Dictionary, safe_muzzle: Vector2, desired_muzzle: Vector2) -> void:
	var muzzle_vector := desired_muzzle - global_position
	var muzzle_distance := muzzle_vector.length()
	if muzzle_distance <= 0.001:
		return
	var muzzle_direction := muzzle_vector / muzzle_distance
	var safe_distance := (safe_muzzle - global_position).dot(muzzle_direction)
	var current_distance := (muzzle_marker.global_position - global_position).dot(muzzle_direction)
	if current_distance <= safe_distance + 0.001:
		return
	var marker_projection := (muzzle_marker.global_position - gun.global_position).dot(muzzle_direction)
	if marker_projection <= 0.001:
		gun.position += to_local(safe_muzzle) - to_local(muzzle_marker.global_position)
		return
	var gun_origin_projection := (gun.global_position - global_position).dot(muzzle_direction)
	var required_marker_projection := maxf(safe_distance - gun_origin_projection, 0.0)
	var min_visual_scale := clampf(float(config.get("muzzle_wall_min_visual_scale", muzzle_wall_min_visual_scale)), 0.1, 1.0)
	var scale_factor := clampf(required_marker_projection / marker_projection, min_visual_scale, 1.0)
	gun.scale = base_gun_scale * scale_factor
	var remaining_delta := to_local(safe_muzzle) - to_local(muzzle_marker.global_position)
	if remaining_delta.length() > 0.001:
		gun.position += remaining_delta

func get_safe_muzzle_position(config: Dictionary, desired_muzzle: Vector2) -> Vector2:
	var collision_mask := int(config.get("muzzle_collision_mask", muzzle_collision_mask))
	if collision_mask == 0:
		return desired_muzzle
	var ray_start := global_position
	var muzzle_vector := desired_muzzle - ray_start
	var muzzle_distance := muzzle_vector.length()
	if muzzle_distance <= 0.001:
		return desired_muzzle
	var hit := Projectile.raycast(
		get_world_2d().direct_space_state,
		ray_start,
		desired_muzzle,
		collision_mask,
		bullet_exclude_rids,
		Projectile.get_pass_over_tilemap_layers(config),
		true,
		false
	)
	if hit.is_empty():
		return desired_muzzle
	var hit_position: Vector2 = hit.get("position", desired_muzzle)
	var muzzle_direction := muzzle_vector / muzzle_distance
	var padding := maxf(float(config.get("muzzle_wall_padding", muzzle_wall_padding)), 0.0)
	var safe_distance := clampf((hit_position - ray_start).dot(muzzle_direction) - padding, 0.0, muzzle_distance)
	return ray_start + muzzle_direction * safe_distance

func emit_ammo_changed() -> void:
	ammo_changed.emit(current_ammo, get_magazine_size())

func _spawn_bullet(direction: Vector2, start_position: Vector2, should_collide: bool, damage_override: int = -1, target_position: Variant = null) -> void:
	var config := get_weapon_config()
	var bullet_lifetime: float = float(config.get("bullet_lifetime", 1.0))
	var pass_over_layers: Array[String] = get_pass_over_tilemap_layers()

	var bullet := _create_bullet_node()
	_configure_spawned_bullet(bullet, direction, start_position)

	var current_scene := get_tree().current_scene
	if current_scene == null:
		bullet.queue_free()
		return

	while active_bullets.size() >= MAX_ACTIVE_BULLETS_PER_WEAPON:
		var oldest_bullet_data := active_bullets[0]
		active_bullets.remove_at(0)
		_free_bullet_node(int(oldest_bullet_data.get("instance_id", 0)))

	current_scene.add_child(bullet)
	var bullet_instance_id := bullet.get_instance_id()
	get_tree().create_timer(bullet_lifetime).timeout.connect(_on_bullet_lifetime_timeout.bind(bullet_instance_id))
	active_bullets.append(_build_bullet_runtime_data(bullet, direction, bullet_lifetime, should_collide, damage_override, pass_over_layers, target_position))

func _on_bullet_lifetime_timeout(bullet_instance_id: int) -> void:
	for i in range(active_bullets.size() - 1, -1, -1):
		var bullet_data := active_bullets[i]
		if int(bullet_data.get("instance_id", 0)) != bullet_instance_id:
			continue
		if bullet_data.has("target_position"):
			var impact_position: Vector2 = bullet_data.get("ground_position", bullet_data.get("target_position", bullet_data.get("position", Vector2.ZERO)))
			_play_impact_effect(impact_position)
			if int(bullet_data.get("damage", 0)) > 0:
				apply_bullet_hit({ "position": impact_position }, int(bullet_data.get("damage", 0)))
		active_bullets.remove_at(i)
		break
	_free_bullet_node(bullet_instance_id)
