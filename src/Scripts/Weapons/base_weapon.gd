class_name BaseWeapon
extends Node2D

# Shared weapon stats and per-angle sprite setup live in WeaponData.
const WeaponData = preload("res://src/Scripts/Weapons/weapon_data.gd")
const Projectile = preload("res://src/Scripts/Weapons/projectile.gd")

# UI and game systems can listen to this to refresh ammo counters.
signal ammo_changed(current_ammo: int, max_ammo: int)
signal shot_fired(angle_radians: float, weapon_type: String)

# This weapon instance reads all of its gameplay values from WeaponData using this id.
@export var weapon_id: String = WeaponData.DEFAULT_WEAPON_ID

# Runtime state for spawned bullets, aiming, recoil, reloads, and optional AI control.
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

@onready var gun: AnimatedSprite2D = $Gun
@onready var muzzle_marker: Marker2D = $Gun/Marker2D
@onready var bullet_template: AnimatedSprite2D = $Gun/Marker2D/Bullets
@onready var shoot_audio_source: AudioStreamPlayer2D = $AudioStreamPlayer2D

func _ready() -> void:
	# Remember the original local position so recoil and movement sway can always return here.
	base_position = position
	var owner_body: CollisionObject2D = find_owner_body()

	# Prevent this weapon from immediately hitting the player or parent body that owns it.
	if owner_body != null:
		bullet_exclude_rids.append(owner_body.get_rid())

	# The scene must provide the gun sprite, muzzle marker, and a bullet sprite template.
	if gun == null or muzzle_marker == null or bullet_template == null:
		push_error("Weapon node %s is missing Gun/Marker2D/Bullets." % name)
		set_process(false)
		return

	# Copy bullet visuals from the template once, then remove the template scene node.
	bullet_frames = bullet_template.sprite_frames
	bullet_scale = bullet_template.scale
	bullet_template.queue_free()

	# Start with a full magazine, align the weapon to its first frame, and keep it hidden until equipped.
	current_ammo = get_magazine_size()
	apply_frame_data(0)
	set_active(false)
	emit_ammo_changed()

	reload_audio_player = AudioStreamPlayer2D.new()
	add_child(reload_audio_player)

func _process(delta: float) -> void:
	# Count active timers down every frame.
	fire_cooldown = maxf(fire_cooldown - delta, 0.0)
	reload_cooldown = maxf(reload_cooldown - delta, 0.0)

	# Smoothly remove recoil so the weapon settles back into place.
	var recoil_recover_speed: float = float(get_weapon_config().get("recoil_recover_speed", 18.0))
	recoil_offset = recoil_offset.lerp(Vector2.ZERO, clampf(delta * recoil_recover_speed, 0.0, 1.0))
	position = base_position + movement_offset + recoil_offset

	# Finish the reload the moment the timer reaches zero.
	if reload_pending and reload_cooldown == 0.0:
		current_ammo = get_magazine_size()
		reload_pending = false
		emit_ammo_changed()

	# Move every active bullet and resolve hits.
	update_bullets(delta)

	if not is_active_weapon:
		return

	# Aim either at a forced target or at the mouse cursor for player-controlled weapons.
	if has_aim_target_override:
		update_aim(aim_target_override)
	else:
		update_aim(get_global_mouse_position())

	# Only the local player path reads input directly from this weapon.
	if accepts_player_input:
		if Input.is_key_pressed(KEY_R):
			reload()

		if Input.is_action_pressed("click"):
			shoot()

func set_active(is_active: bool) -> void:
	# Hidden weapons stay simulated so reloads and in-flight bullets can finish naturally.
	is_active_weapon = is_active
	visible = is_active

func update_movement(direction: Vector2) -> void:
	# Add a small position offset so the weapon reacts to character movement.
	var config := get_weapon_config()
	var move_offset: float = config.get("move_offset", 0.0)

	if direction == Vector2.ZERO:
		movement_offset = Vector2.ZERO
		return

	movement_offset = direction.normalized() * move_offset

func update_aim(target_position: Vector2) -> void:
	# Convert world-space aim into one of the 8 weapon sprite directions.
	var dir: Vector2 = (target_position - global_position).normalized()
	var angle: float = rad_to_deg(dir.angle())

	if angle < 0.0:
		angle += 360.0

	apply_frame_data(angle_to_frame(angle))

func get_aim_frame() -> int:
	return current_frame_index

func get_bullet_frame() -> int:
	# Bullets can use a different sprite frame than the gun for the same aim direction.
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
	# Never fire while still cooling down or reloading.
	if fire_cooldown > 0.0 or reload_cooldown > 0.0:
		return

	var config := get_weapon_config()

	# An empty weapon immediately starts a reload instead of spawning a bullet.
	if current_ammo <= 0:
		reload()
		return

	# Consume ammo and start the fire-rate timer before spawning the projectile.
	fire_cooldown = config.get("fire_rate", 0.2)
	current_ammo -= 1
	emit_ammo_changed()
	var fire_sound: AudioStream = null

	if shoot_audio_source != null:
		fire_sound = shoot_audio_source.stream

	if fire_sound == null:
		fire_sound = get_weapon_config().get("fire_sound")

	if fire_sound:
		var owner_body := find_owner_body()
		if owner_body != null and owner_body.has_method("play_shoot_sound"):
			owner_body.call("play_shoot_sound", fire_sound)

	# Build the bullet travel direction from the muzzle toward the current target.
	var shot_target: Vector2 = aim_target_override if has_aim_target_override else get_global_mouse_position()
	var bullet_offset := shot_target - muzzle_marker.global_position
	var bullet_direction := bullet_offset.normalized() if bullet_offset != Vector2.ZERO else Vector2.RIGHT
	apply_recoil(bullet_direction, config)
	_spawn_bullet(bullet_direction, muzzle_marker.global_position, true, -1, shot_target)
	shot_fired.emit(bullet_direction.angle(), get_weapon_name())

	if current_ammo <= 0:
		reload()

func spawn_remote_bullet(angle_radians: float) -> void:
	var bullet_direction := Vector2.RIGHT.rotated(angle_radians)
	apply_recoil(bullet_direction, get_weapon_config())

	var fire_sound: AudioStream = null
	if shoot_audio_source != null:
		fire_sound = shoot_audio_source.stream

	if fire_sound == null:
		fire_sound = get_weapon_config().get("fire_sound")

	if fire_sound:
		var owner_body := find_owner_body()
		if owner_body != null and owner_body.has_method("play_shoot_sound"):
			owner_body.call("play_shoot_sound", fire_sound)

	_spawn_bullet(bullet_direction, muzzle_marker.global_position, true, 0)

func apply_recoil(direction: Vector2, config: Dictionary) -> void:
	# Kick the weapon backward, with a little sideways randomness to avoid a rigid feel.
	var recoil_distance: float = float(config.get("recoil_distance", 2.5))
	var recoil_jitter: float = float(config.get("recoil_jitter", 0.35))
	var sideways := direction.orthogonal() * randf_range(-recoil_jitter, recoil_jitter)
	recoil_offset = (-direction + sideways).normalized() * recoil_distance

func update_bullets(delta: float) -> void:
	# Use raycasts between frames so fast bullets cannot skip through targets.
	var space_state := get_world_2d().direct_space_state
	var config := get_weapon_config()

	for i in range(active_bullets.size() - 1, -1, -1):
		var bullet_data := active_bullets[i]
		var bullet_instance_id := int(bullet_data.get("instance_id", 0))
		var bullet := instance_from_id(bullet_instance_id) as AnimatedSprite2D

		# Drop stale entries if the visual node was already destroyed somewhere else.
		if bullet == null or not is_instance_valid(bullet):
			active_bullets.remove_at(i)
			continue

		# Simulate this bullet's next step and test the full segment for a hit.
		var result := Projectile.tick(bullet_data, delta)
		var start_position: Vector2 = result["start_position"]
		var end_position: Vector2 = result["position"]
		var collision_mask: int = bullet_data["collision_mask"]
		var damage: int = bullet_data["damage"]
		var should_collide: bool = bool(bullet_data.get("collides", true))
		var pass_over_layers: Array[String] = _to_string_array(bullet_data.get("pass_over_layers", []))
		var uses_target_arc := bool(config.get("uses_target_arc", false))
		var hit: Dictionary = {}
		if should_collide and collision_mask != 0 and not uses_target_arc:
			hit = raycast_bullet(space_state, start_position, end_position, collision_mask, pass_over_layers)

		# Stop the bullet on impact, apply damage, and remove it from the active list.
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

		# No impact happened, so keep moving the bullet until its lifetime expires.
		bullet.global_position = end_position
		Projectile.update_visual_for_arc_progress(bullet, config, float(result.get("arc_progress", 0.0)))
		Projectile.update_visual_for_velocity(bullet, config, result["velocity"], get_bullet_frame())

		if not bool(result["alive"]):
			bullet.queue_free()
			active_bullets.remove_at(i)
			continue

		active_bullets[i] = bullet_data

func raycast_bullet(space_state: PhysicsDirectSpaceState2D, from: Vector2, to: Vector2, collision_mask: int, pass_over_layers: Array[String] = []) -> Dictionary:
	return Projectile.raycast(space_state, from, to, collision_mask, bullet_exclude_rids, pass_over_layers)

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
	# Walk up the scene tree until we find the first physics body that owns this weapon.
	var current: Node = get_parent()
	while current != null:
		if current is CollisionObject2D:
			return current as CollisionObject2D
		current = current.get_parent()

	return null

func apply_bullet_hit(hit: Dictionary, damage: int) -> void:
	# Local player-owned bullets report proposed hits to the server; non-networked actors still use local damage.
	if damage <= 0:
		return

	var explosion_radius := float(get_weapon_config().get("explosion_radius", 0.0))
	if explosion_radius > 0.0:
		apply_explosion_damage(hit.get("position", Vector2.ZERO), explosion_radius, damage)
		return

	var collider_variant: Variant = hit.get("collider")
	if collider_variant == null or not (collider_variant is Node):
		return

	var collider := collider_variant as Node
	var owner_body := find_owner_body()
	if owner_body != null and owner_body.has_method("report_authoritative_hit"):
		if bool(owner_body.call("report_authoritative_hit", collider, damage, hit.get("position", Vector2.ZERO), self)):
			return

	if collider != null and collider.has_method("apply_damage"):
		collider.call("apply_damage", damage, hit.get("position", Vector2.ZERO), self)

func apply_explosion_damage(center: Vector2, radius: float, damage: int) -> void:
	if radius <= 0.0 or damage <= 0:
		return

	var shape := CircleShape2D.new()
	shape.radius = radius

	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, center)
	query.collision_mask = int(get_weapon_config().get("bullet_collision_mask", 1))
	query.exclude = bullet_exclude_rids

	var damaged_bodies: Array[Node] = []
	var owner_body := find_owner_body()
	for result in get_world_2d().direct_space_state.intersect_shape(query):
		var collider_variant: Variant = result.get("collider")
		if not (collider_variant is Node):
			continue

		var collider := collider_variant as Node
		if damaged_bodies.has(collider) or not collider.has_method("apply_damage"):
			continue

		damaged_bodies.append(collider)
		if owner_body != null and owner_body.has_method("report_authoritative_hit"):
			if bool(owner_body.call("report_authoritative_hit", collider, damage, center, self)):
				continue

		collider.call("apply_damage", damage, center, self)

func reload() -> void:
	# Ignore reload requests if a reload is already running or the magazine is already full.
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
	# Lets another system temporarily take over aiming and shooting.
	accepts_player_input = is_enabled

func set_aim_target(target_position: Vector2) -> void:
	# External controllers can force the weapon to aim somewhere other than the mouse.
	has_aim_target_override = true
	aim_target_override = target_position

func clear_aim_target() -> void:
	has_aim_target_override = false

func set_collision_mask_override(mask: int) -> void:
	# Useful when one owner needs different bullet collision rules than the default weapon data.
	collision_mask_override = mask

func reset_state() -> void:
	# Return the weapon to a clean state when changing scenes, respawning, or clearing projectiles.
	fire_cooldown = 0.0
	reload_cooldown = 0.0
	reload_duration = 0.0
	reload_pending = false
	current_ammo = get_magazine_size()
	movement_offset = Vector2.ZERO
	recoil_offset = Vector2.ZERO
	position = base_position

	# Destroy all still-active bullet nodes before forgetting them.
	for bullet_data_variant in active_bullets:
		var bullet_data: Dictionary = bullet_data_variant
		var bullet_instance_id := int(bullet_data.get("instance_id", 0))
		var bullet := instance_from_id(bullet_instance_id) as AnimatedSprite2D
		if bullet != null and is_instance_valid(bullet):
			bullet.queue_free()

	active_bullets.clear()
	emit_ammo_changed()

func get_weapon_icon() -> Texture2D:
	# Prefer the custom icon from data, but fall back to the first gun sprite frame if needed.
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
	# Always return valid data by falling back to the default weapon definition.
	if WeaponData.WEAPON_DATA.has(weapon_id):
		return WeaponData.WEAPON_DATA[weapon_id]

	return WeaponData.WEAPON_DATA[WeaponData.DEFAULT_WEAPON_ID]

func angle_to_frame(angle: float) -> int:
	# Map the full 360 degrees into 8 sprite directions.
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
	# Each aim frame changes both the gun sprite frame and the muzzle position used for bullets.
	current_frame_index = frame_index
	gun.frame = frame_index

	var config := get_weapon_config()
	var frame_data: Dictionary = config["frames"][frame_index]
	gun.position = frame_data["gun_position"]
	muzzle_marker.position = frame_data["muzzle_offset"]

func emit_ammo_changed() -> void:
	# Centralized helper so every ammo update notifies listeners the same way.
	ammo_changed.emit(current_ammo, get_magazine_size())

func _spawn_bullet(direction: Vector2, start_position: Vector2, should_collide: bool, damage_override: int = -1, target_position: Variant = null) -> void:
	var config := get_weapon_config()
	var bullet_lifetime: float = float(config.get("bullet_lifetime", 1.0))
	var pass_over_layers: Array[String] = get_pass_over_tilemap_layers()

	var bullet := AnimatedSprite2D.new()
	_configure_spawned_bullet(bullet, direction, start_position)

	get_tree().current_scene.add_child(bullet)
	# Failsafe cleanup: even if projectile state desyncs, the visual bullet cannot remain stuck forever.
	var bullet_instance_id := bullet.get_instance_id()
	get_tree().create_timer(bullet_lifetime).timeout.connect(_on_bullet_lifetime_timeout.bind(bullet_instance_id))

	active_bullets.append(_build_bullet_runtime_data(bullet, direction, bullet_lifetime, should_collide, damage_override, pass_over_layers, target_position))

func _on_bullet_lifetime_timeout(bullet_instance_id: int) -> void:
	var bullet := instance_from_id(bullet_instance_id) as AnimatedSprite2D
	if bullet != null and is_instance_valid(bullet):
		bullet.queue_free()
