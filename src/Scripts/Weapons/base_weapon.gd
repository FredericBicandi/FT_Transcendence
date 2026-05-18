class_name BaseWeapon
extends Node2D

# Keep weapon stats and sprite offsets outside the scene
const WeaponData = preload("res://src/Scripts/Weapons/weapon_data.gd")
const Projectile = preload("res://src/Scripts/Weapons/projectile.gd")
const DAMAGEABLE_PLAYER_GROUP := "damageable_player"
const DEFAULT_MUZZLE_COLLISION_MASK := 1
const DEFAULT_MUZZLE_WALL_PADDING := 1.5
const DEFAULT_MUZZLE_WALL_VISUAL_PULLBACK := 4.0
const DEFAULT_MUZZLE_WALL_MIN_VISUAL_SCALE := 0.6

# Let UI and networking react without polling this node
signal ammo_changed(current_ammo: int, max_ammo: int)
signal shot_fired(angle_radians: float, weapon_type: String, start_position: Vector2, target_position: Vector2)

# This id chooses the row from WeaponData
@export var weapon_id: String = WeaponData.DEFAULT_WEAPON_ID
@export var muzzle_collision_mask: int = DEFAULT_MUZZLE_COLLISION_MASK
@export var muzzle_wall_padding: float = DEFAULT_MUZZLE_WALL_PADDING
@export var muzzle_wall_visual_pullback: float = DEFAULT_MUZZLE_WALL_VISUAL_PULLBACK
@export var muzzle_wall_min_visual_scale: float = DEFAULT_MUZZLE_WALL_MIN_VISUAL_SCALE

# Runtime state kept here so each equipped weapon behaves independently
var active_bullets: Array[Dictionary] = []
var current_frame_index: int = 0
var fire_cooldown: float = 0.0
var reload_cooldown: float = 0.0
var reload_duration: float = 0.0
var base_position: Vector2
var movement_offset: Vector2 = Vector2.ZERO
var recoil_offset: Vector2 = Vector2.ZERO
var bullet_frames: SpriteFrames
var bullet_scale: Vector2 = Vector2.ONE
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

@onready var gun: AnimatedSprite2D = $Gun
@onready var muzzle_marker: Marker2D = $Gun/Marker2D
@onready var bullet_template: AnimatedSprite2D = $Gun/Marker2D/Bullets
@onready var shoot_audio_source: AudioStreamPlayer2D = $AudioStreamPlayer2D

func _ready() -> void:
	# Keep the original local position for recoil and movement sway
	base_position = position
	var owner_body: CollisionObject2D = find_owner_body()

	# Do not let bullets hit the body holding this weapon
	if owner_body != null:
		bullet_exclude_rids.append(owner_body.get_rid())
		var owner_hitbox := owner_body.get_node_or_null("HitBox") as CollisionObject2D
		if owner_hitbox != null:
			bullet_exclude_rids.append(owner_hitbox.get_rid())

	# Stop early if the weapon scene is missing required nodes
	if gun == null or muzzle_marker == null or bullet_template == null:
		push_error("Weapon node %s is missing Gun/Marker2D/Bullets." % name)
		set_process(false)
		return

	base_gun_scale = gun.scale

	# Copy bullet visuals once, then remove the editor template
	bullet_frames = bullet_template.sprite_frames
	bullet_scale = bullet_template.scale
	bullet_template.queue_free()

	# Start loaded but hidden until this weapon is equipped
	current_ammo = get_magazine_size()
	apply_frame_data(0)
	set_active(false)
	emit_ammo_changed()

	reload_audio_player = AudioStreamPlayer2D.new()
	add_child(reload_audio_player)

func _process(delta: float) -> void:
	# Keep fire and reload timers moving even while hidden
	fire_cooldown = maxf(fire_cooldown - delta, 0.0)
	reload_cooldown = maxf(reload_cooldown - delta, 0.0)

	# Bring the weapon back after recoil without snapping
	var recoil_recover_speed: float = float(get_weapon_config().get("recoil_recover_speed", 18.0))
	recoil_offset = recoil_offset.lerp(Vector2.ZERO, clampf(delta * recoil_recover_speed, 0.0, 1.0))
	position = base_position + movement_offset + recoil_offset

	# Finish reloads even if the player switched weapons
	if reload_pending and reload_cooldown == 0.0:
		current_ammo = get_magazine_size()
		reload_pending = false
		emit_ammo_changed()

	# Keep old bullets alive after switching weapons
	update_bullets(delta)

	if not is_active_weapon:
		return

	# Remote and AI players can force aim without using the mouse
	if has_aim_target_override:
		update_aim(aim_target_override)
	else:
		update_aim(get_global_mouse_position())

	# Only the local player weapon reads keyboard and mouse input
	if accepts_player_input:
		if Input.is_key_pressed(KEY_R):
			reload()

		if Input.is_action_pressed("click"):
			shoot()

func set_active(is_active: bool) -> void:
	# Hidden weapons still simulate reloads and bullets
	is_active_weapon = is_active
	visible = is_active

func update_movement(direction: Vector2) -> void:
	# Add a small offset so the weapon follows movement
	var config := get_weapon_config()
	var move_offset: float = config.get("move_offset", 0.0)

	if direction == Vector2.ZERO:
		movement_offset = Vector2.ZERO
		return

	movement_offset = direction.normalized() * move_offset

func update_aim(target_position: Vector2) -> void:
	# Turn world aim into one of the 8 sprite directions
	var dir: Vector2 = (target_position - global_position).normalized()
	var angle: float = rad_to_deg(dir.angle())

	if angle < 0.0:
		angle += 360.0

	apply_frame_data(angle_to_frame(angle))

func get_aim_frame() -> int:
	return current_frame_index

func get_bullet_frame() -> int:
	# Let bullets use a different frame than the gun
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

func shoot() -> void:
	# Block firing while cooldown or reload is active
	if fire_cooldown > 0.0 or reload_cooldown > 0.0:
		return

	var config := get_weapon_config()

	# Empty weapons reload instead of dry-firing
	if current_ammo <= 0:
		reload()
		return

	# Refresh aim so wall-clamped muzzle data is current
	var raw_shot_target: Vector2 = aim_target_override if has_aim_target_override else get_global_mouse_position()
	update_aim(raw_shot_target)

	# Consume ammo before spawning the projectile
	fire_cooldown = config.get("fire_rate", 0.2)
	current_ammo -= 1
	emit_ammo_changed()
	var fire_sound: AudioStream = null

	if shoot_audio_source != null:
		fire_sound = shoot_audio_source.stream

	if fire_sound == null:
		fire_sound = config.get("fire_sound")

	if fire_sound:
		var owner_body := find_owner_body()
		if owner_body != null and owner_body.has_method("play_shoot_sound"):
			owner_body.call("play_shoot_sound", fire_sound)

	# Use the safe muzzle point so bullets do not spawn inside walls
	var shot_start_position := get_shot_start_position(config)
	var shot_target := _resolve_shot_target(shot_start_position, raw_shot_target, config)
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

	var fire_sound: AudioStream = null
	if shoot_audio_source != null:
		fire_sound = shoot_audio_source.stream

	if fire_sound == null:
		fire_sound = config.get("fire_sound")

	if fire_sound:
		var owner_body := find_owner_body()
		if owner_body != null and owner_body.has_method("play_shoot_sound"):
			owner_body.call("play_shoot_sound", fire_sound)

	var replay_target: Variant = aim_target if has_target_position else null
	_spawn_bullet(bullet_direction, shot_start_position, true, 0, replay_target)

func apply_recoil(direction: Vector2, config: Dictionary) -> void:
	# Add a small random kick so shots do not feel stiff
	var recoil_distance: float = float(config.get("recoil_distance", 2.5))
	var recoil_jitter: float = float(config.get("recoil_jitter", 0.35))
	var sideways := direction.orthogonal() * randf_range(-recoil_jitter, recoil_jitter)
	recoil_offset = (-direction + sideways).normalized() * recoil_distance

func update_bullets(delta: float) -> void:
	# Raycast between frames so fast bullets cannot skip targets
	var space_state := get_world_2d().direct_space_state
	var config := get_weapon_config()

	for i in range(active_bullets.size() - 1, -1, -1):
		var bullet_data := active_bullets[i]
		var bullet_instance_id := int(bullet_data.get("instance_id", 0))
		var bullet := instance_from_id(bullet_instance_id) as AnimatedSprite2D

		# Drop bullets that were already cleaned up
		if bullet == null or not is_instance_valid(bullet):
			active_bullets.remove_at(i)
			continue

		# Check the whole movement step, not only the final point
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

		# Resolve the hit once and remove the bullet
		if not hit.is_empty():
			apply_bullet_hit(hit, damage)
			bullet.global_position = hit["position"]
			bullet.queue_free()
			active_bullets.remove_at(i)
			continue

		if bool(result.get("landed", false)):
			apply_bullet_hit({ "position": end_position }, damage)
			bullet.global_position = end_position
			bullet.queue_free()
			active_bullets.remove_at(i)
			continue

		# Keep flying until lifetime runs out
		bullet.global_position = end_position
		Projectile.update_visual_for_velocity(bullet, config, result["velocity"], get_bullet_frame())

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

func _build_bullet_runtime_data(bullet: AnimatedSprite2D, direction: Vector2, bullet_lifetime: float, should_collide: bool, damage_override: int, pass_over_layers: Array[String], target_position: Variant = null) -> Dictionary:
	return Projectile.build_runtime_data(get_weapon_config(), bullet, direction, bullet_lifetime, should_collide, damage_override, collision_mask_override, pass_over_layers, target_position)

func _configure_spawned_bullet(bullet: AnimatedSprite2D, direction: Vector2, start_position: Vector2) -> void:
	Projectile.configure_visual(bullet, bullet_frames, bullet_scale, get_weapon_config(), get_spawned_bullet_frame(direction), gun.z_index, direction, start_position)

func find_owner_body() -> CollisionObject2D:
	# Find the body holding this weapon
	var current: Node = get_parent()
	while current != null:
		if current is CollisionObject2D:
			return current as CollisionObject2D
		current = current.get_parent()

	return null

func apply_bullet_hit(hit: Dictionary, damage: int) -> void:
	# Let the server approve local-player hits before applying damage
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

	var owner_body := find_owner_body()
	var explosion_shot_id := _create_owner_shot_id(owner_body)
	for target in _collect_explosion_targets(center, radius, direct_target):
		if target == owner_body:
			continue

		var damage := _get_explosion_damage_for_target(center, radius, max_damage, target, direct_target)
		if damage <= 0:
			continue

		if owner_body != null and owner_body.has_method("report_authoritative_hit"):
			if bool(owner_body.call("report_authoritative_hit", target, damage, center, self, explosion_shot_id)):
				continue

		target.call("apply_damage", damage, center, self)

func _collect_explosion_targets(center: Vector2, radius: float, direct_target: Node = null) -> Array[Node]:
	var targets: Array[Node] = []
	if direct_target != null and direct_target.has_method("apply_damage"):
		targets.append(direct_target)

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

	var current_scene := get_tree().current_scene
	if current_scene != null:
		_collect_scene_explosion_targets(current_scene, center, radius, targets)

	return targets

func _collect_scene_explosion_targets(node: Node, center: Vector2, radius: float, targets: Array[Node]) -> void:
	var target := _resolve_damage_target(node)
	if target != null and target == node and not targets.has(target):
		var target_body := target as Node2D
		if target_body != null and target_body.global_position.distance_to(center) <= radius:
			targets.append(target)

	for child in node.get_children():
		_collect_scene_explosion_targets(child, center, radius, targets)

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
	# Ignore reload when it is already running or not needed
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

func set_input_enabled(is_enabled: bool) -> void:
	# Let match state or remote control disable weapon input
	accepts_player_input = is_enabled

func set_aim_target(target_position: Vector2) -> void:
	# Remote players and AI aim without the local mouse
	has_aim_target_override = true
	aim_target_override = target_position

func clear_aim_target() -> void:
	has_aim_target_override = false

func set_collision_mask_override(mask: int) -> void:
	# Let special owners use different bullet collision rules
	collision_mask_override = mask

func reset_state() -> void:
	# Reset everything that should not survive respawn
	fire_cooldown = 0.0
	reload_cooldown = 0.0
	reload_duration = 0.0
	reload_pending = false
	has_safe_muzzle_position = false
	current_ammo = get_magazine_size()
	movement_offset = Vector2.ZERO
	recoil_offset = Vector2.ZERO
	position = base_position

	# Remove bullet nodes before clearing the tracking list
	for bullet_data_variant in active_bullets:
		var bullet_data: Dictionary = bullet_data_variant
		var bullet_instance_id := int(bullet_data.get("instance_id", 0))
		var bullet := instance_from_id(bullet_instance_id) as AnimatedSprite2D
		if bullet != null and is_instance_valid(bullet):
			bullet.queue_free()

	active_bullets.clear()
	emit_ammo_changed()

func get_weapon_icon() -> Texture2D:
	# Prefer the data icon, then fall back to the gun sprite
	var weapon_image: Variant = get_weapon_config().get("image")
	if weapon_image is Texture2D:
		return weapon_image as Texture2D

	if gun == null or gun.sprite_frames == null:
		return null

	return gun.sprite_frames.get_frame_texture(&"default", 0)

func is_reloading() -> bool:
	return reload_cooldown > 0.0

func get_reload_progress() -> float:
	if not is_reloading() or reload_duration <= 0.0:
		return 0.0

	return clampf(1.0 - (reload_cooldown / reload_duration), 0.0, 1.0)

func get_weapon_config() -> Dictionary:
	# Fall back so a bad weapon id does not crash the match
	if WeaponData.WEAPON_DATA.has(weapon_id):
		return WeaponData.WEAPON_DATA[weapon_id]

	return WeaponData.WEAPON_DATA[WeaponData.DEFAULT_WEAPON_ID]

func angle_to_frame(angle: float) -> int:
	# Split the full circle into 8 aim frames
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
	# Each aim frame has its own hand and muzzle offset
	current_frame_index = frame_index
	gun.frame = frame_index
	gun.scale = base_gun_scale
	has_safe_muzzle_position = false

	var config := get_weapon_config()
	var frame_data: Dictionary = config["frames"][frame_index]
	gun.position = frame_data["gun_position"]
	muzzle_marker.position = frame_data["muzzle_offset"]
	keep_muzzle_out_of_walls(config)

func get_shot_start_position(config: Dictionary) -> Vector2:
	# Shoot from the wall-safe point when the visual muzzle is clamped
	if has_safe_muzzle_position:
		return safe_muzzle_position

	return get_safe_muzzle_position(config, muzzle_marker.global_position)

func keep_muzzle_out_of_walls(config: Dictionary) -> void:
	if not is_inside_tree() or gun == null or muzzle_marker == null:
		return

	# Pull the weapon only as much as needed to keep the muzzle valid
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
	# Shrink a little near walls instead of snapping the whole weapon back
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
	# Find the closest point before the wall where a bullet can start
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
	# Keep every ammo update using the same signal
	ammo_changed.emit(current_ammo, get_magazine_size())

func _spawn_bullet(direction: Vector2, start_position: Vector2, should_collide: bool, damage_override: int = -1, target_position: Variant = null) -> void:
	var config := get_weapon_config()
	var bullet_lifetime: float = float(config.get("bullet_lifetime", 1.0))
	var pass_over_layers: Array[String] = get_pass_over_tilemap_layers()

	var bullet := AnimatedSprite2D.new()
	_configure_spawned_bullet(bullet, direction, start_position)

	get_tree().current_scene.add_child(bullet)
	# Cleanup timer keeps bullet visuals from getting stuck forever
	var bullet_instance_id := bullet.get_instance_id()
	get_tree().create_timer(bullet_lifetime).timeout.connect(_on_bullet_lifetime_timeout.bind(bullet_instance_id))

	active_bullets.append(_build_bullet_runtime_data(bullet, direction, bullet_lifetime, should_collide, damage_override, pass_over_layers, target_position))

func _on_bullet_lifetime_timeout(bullet_instance_id: int) -> void:
	for i in range(active_bullets.size() - 1, -1, -1):
		var bullet_data := active_bullets[i]
		if int(bullet_data.get("instance_id", 0)) != bullet_instance_id:
			continue

		if bullet_data.has("target_position") and int(bullet_data.get("damage", 0)) > 0:
			var impact_position: Vector2 = bullet_data.get("ground_position", bullet_data.get("target_position", bullet_data.get("position", Vector2.ZERO)))
			apply_bullet_hit({ "position": impact_position }, int(bullet_data.get("damage", 0)))

		active_bullets.remove_at(i)
		break

	var bullet := instance_from_id(bullet_instance_id) as AnimatedSprite2D
	if bullet != null and is_instance_valid(bullet):
		bullet.queue_free()
