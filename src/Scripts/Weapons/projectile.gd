class_name Projectile
extends RefCounted

static func uses_arc_physics(config: Dictionary) -> bool:
	return bool(config.get("uses_ballistic_arc", false))

static func uses_frame_mapping(config: Dictionary) -> bool:
	return int(config.get("projectile_frame_count", 0)) > 0

static func get_frame_for_direction(config: Dictionary, fallback_frame: int, direction: Vector2) -> int:
	var projectile_frame_count: int = int(config.get("projectile_frame_count", 0))
	if projectile_frame_count <= 0:
		return fallback_frame

	var angle: float = direction.angle()
	if angle < 0.0:
		angle += TAU

	var step: float = TAU / float(projectile_frame_count)
	var frame_index: int = int(floor((angle + step * 0.5) / step)) % projectile_frame_count
	var projectile_frames: Array[int] = _to_int_array(config.get("projectile_frames", []))
	if frame_index < projectile_frames.size():
		return projectile_frames[frame_index]

	return frame_index

static func get_pass_over_tilemap_layers(config: Dictionary) -> Array[String]:
	return _to_string_array(config.get("passes_over_tilemap_layers", []))

static func get_visual_z_index(config: Dictionary, fallback_z_index: int) -> int:
	return int(config.get("bullet_z_index", fallback_z_index))

static func raycast(space_state: PhysicsDirectSpaceState2D, from: Vector2, to: Vector2, collision_mask: int, excluded_rids: Array[RID], pass_over_layers: Array[String]) -> Dictionary:
	var local_excluded_rids: Array[RID] = []
	local_excluded_rids.append_array(excluded_rids)

	while true:
		var query := PhysicsRayQueryParameters2D.create(from, to, collision_mask, local_excluded_rids)
		var hit: Dictionary = space_state.intersect_ray(query)
		if hit.is_empty():
			return {}

		if not _should_ignore_hit(hit, pass_over_layers):
			return hit

		var hit_rid_variant: Variant = hit.get("rid", RID())
		if hit_rid_variant is RID:
			local_excluded_rids.append(hit_rid_variant as RID)
			continue

		return {}

	return {}

static func build_runtime_data(config: Dictionary, bullet: AnimatedSprite2D, direction: Vector2, bullet_lifetime: float, should_collide: bool, damage_override: int, collision_mask_override: int, pass_over_layers: Array[String]) -> Dictionary:
	var speed: float = float(config.get("bullet_speed", 300.0))
	var velocity: Vector2 = direction * speed
	if uses_arc_physics(config):
		velocity = _build_launch_velocity(config, direction, speed)

	return {
		"instance_id": bullet.get_instance_id(),
		"position": bullet.global_position,
		"direction": direction,
		"velocity": velocity,
		"speed": speed,
		"lifetime": bullet_lifetime,
		"age": 0.0,
		"collision_mask": collision_mask_override if should_collide and collision_mask_override >= 0 else int(config.get("bullet_collision_mask", 1)) if should_collide else 0,
		"damage": damage_override if damage_override >= 0 else int(config.get("damage", 1)) if should_collide else 0,
		"collides": should_collide,
		"pass_over_layers": pass_over_layers,
		"gravity": float(config.get("gravity", 0.0))
	}

static func configure_visual(bullet: AnimatedSprite2D, sprite_frames: SpriteFrames, bullet_scale: Vector2, config: Dictionary, fallback_frame: int, fallback_z_index: int, direction: Vector2, start_position: Vector2) -> void:
	bullet.sprite_frames = sprite_frames
	bullet.animation = &"default"
	bullet.frame = get_frame_for_direction(config, fallback_frame, direction)
	bullet.global_position = start_position
	bullet.z_index = get_visual_z_index(config, fallback_z_index)
	bullet.scale = bullet_scale

static func tick(runtime_data: Dictionary, delta: float) -> Dictionary:
	var start_position: Vector2 = runtime_data.get("position", Vector2.ZERO)
	var velocity: Vector2 = runtime_data.get("velocity", Vector2.ZERO)
	var gravity: float = float(runtime_data.get("gravity", 0.0))

	if gravity != 0.0:
		velocity.y += gravity * delta

	var end_position: Vector2 = start_position + velocity * delta
	var age: float = float(runtime_data.get("age", 0.0)) + delta
	var lifetime: float = float(runtime_data.get("lifetime", 0.0))
	var direction: Vector2 = velocity.normalized() if velocity.length_squared() > 0.0 else runtime_data.get("direction", Vector2.RIGHT)

	runtime_data["position"] = end_position
	runtime_data["velocity"] = velocity
	runtime_data["direction"] = direction
	runtime_data["age"] = age
	runtime_data["lifetime"] = maxf(lifetime - delta, 0.0)

	return {
		"start_position": start_position,
		"position": end_position,
		"velocity": velocity,
		"alive": age < lifetime
	}

static func update_visual_for_velocity(bullet: AnimatedSprite2D, config: Dictionary, velocity: Vector2, fallback_frame: int) -> void:
	if not uses_frame_mapping(config) or velocity.length_squared() == 0.0:
		return

	bullet.frame = get_frame_for_direction(config, fallback_frame, velocity.normalized())

static func _should_ignore_hit(hit: Dictionary, pass_over_layers: Array[String]) -> bool:
	if pass_over_layers.is_empty():
		return false

	var collider_variant: Variant = hit.get("collider")
	if not (collider_variant is TileMapLayer):
		return false

	var tile_layer := collider_variant as TileMapLayer
	return pass_over_layers.has(tile_layer.name)

static func _to_string_array(values: Variant) -> Array[String]:
	var result: Array[String] = []
	if not (values is Array):
		return result

	for value in values:
		result.append(str(value))

	return result

static func _to_int_array(values: Variant) -> Array[int]:
	var result: Array[int] = []
	if not (values is Array):
		return result

	for value in values:
		result.append(int(value))

	return result

static func _build_launch_velocity(config: Dictionary, direction: Vector2, speed: float) -> Vector2:
	var launch_angle_deg: float = absf(float(config.get("launch_angle_deg", 60.0)))
	var launch_angle_rad: float = deg_to_rad(launch_angle_deg)
	var horizontal_sign: float = -1.0 if direction.x < 0.0 else 1.0
	var launch_direction := Vector2(horizontal_sign * cos(launch_angle_rad), -sin(launch_angle_rad))
	return launch_direction.normalized() * speed
