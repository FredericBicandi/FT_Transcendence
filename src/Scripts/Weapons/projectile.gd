class_name Projectile
extends RefCounted

const RAYCAST_IGNORE_NONE := ""
const RAYCAST_IGNORE_EXCLUDE_RID := "exclude_rid"
const RAYCAST_IGNORE_ADVANCE := "advance"
const RAYCAST_SKIP_EPSILON := 0.5
const MAX_RAYCAST_IGNORE_STEPS := 32

static func uses_arc_physics(config: Dictionary) -> bool:
	return bool(config.get("uses_ballistic_arc", false))

static func uses_target_arc(config: Dictionary) -> bool:
	return bool(config.get("uses_target_arc", false))

static func uses_frame_mapping(config: Dictionary) -> bool:
	return int(config.get("projectile_frame_count", 0)) > 0

static func get_frame_for_direction(config: Dictionary, fallback_frame: int, direction: Vector2) -> int:
	var projectile_frame_count: int = int(config.get("projectile_frame_count", 0))
	if projectile_frame_count <= 0:
		return fallback_frame

	# Pick the closest sprite frame for the projectile direction
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

static func raycast(space_state: PhysicsDirectSpaceState2D, from: Vector2, to: Vector2, collision_mask: int, excluded_rids: Array[RID], pass_over_layers: Array[String], hit_from_inside: bool = false, collide_with_areas: bool = true) -> Dictionary:
	var local_excluded_rids: Array[RID] = []
	local_excluded_rids.append_array(excluded_rids)
	var ray_from := from
	var ray_delta := to - from
	var ray_distance := ray_delta.length()
	if ray_distance <= 0.001:
		return {}

	var ray_direction := ray_delta / ray_distance

	for _step in range(MAX_RAYCAST_IGNORE_STEPS):
		# Keep raycasting past layers that this projectile is allowed to fly over
		var query := PhysicsRayQueryParameters2D.create(ray_from, to, collision_mask, local_excluded_rids)
		query.collide_with_areas = collide_with_areas
		query.collide_with_bodies = true
		query.hit_from_inside = hit_from_inside
		var hit: Dictionary = space_state.intersect_ray(query)
		if hit.is_empty():
			return {}

		var ignore_action := _get_ignore_action(hit, pass_over_layers)
		if ignore_action == RAYCAST_IGNORE_NONE:
			return hit

		if ignore_action == RAYCAST_IGNORE_EXCLUDE_RID:
			var hit_rid_variant: Variant = hit.get("rid", RID())
			if hit_rid_variant is RID:
				local_excluded_rids.append(hit_rid_variant as RID)
				continue

			return {}

		if ignore_action == RAYCAST_IGNORE_ADVANCE:
			var hit_position: Vector2 = hit.get("position", ray_from)
			if hit_position.distance_to(to) <= RAYCAST_SKIP_EPSILON:
				return {}

			ray_from = hit_position + ray_direction * RAYCAST_SKIP_EPSILON
			if (ray_from - from).dot(ray_direction) >= ray_distance:
				return {}

			continue

		return {}

	return {}

static func build_runtime_data(config: Dictionary, bullet: AnimatedSprite2D, direction: Vector2, bullet_lifetime: float, should_collide: bool, damage_override: int, collision_mask_override: int, pass_over_layers: Array[String], target_position: Variant = null) -> Dictionary:
	var speed: float = float(config.get("bullet_speed", 300.0))
	var velocity: Vector2 = direction * speed
	if uses_arc_physics(config):
		# Add lift for projectiles that use simple ballistic movement
		velocity = _build_launch_velocity(config, direction, speed)

	var runtime_data := {
		"instance_id": bullet.get_instance_id(),
		"position": bullet.global_position,
		"start_position": bullet.global_position,
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

	if uses_target_arc(config):
		# Target arcs move visually in the air while collision stays on the ground path
		var target := bullet.global_position + direction * speed * bullet_lifetime
		if target_position is Vector2:
			target = target_position as Vector2

		runtime_data["target_position"] = target
		runtime_data["ground_position"] = bullet.global_position
		runtime_data["arc_height"] = float(config.get("arc_height", 64.0))

	return runtime_data

static func configure_visual(bullet: AnimatedSprite2D, sprite_frames: SpriteFrames, bullet_scale: Vector2, config: Dictionary, fallback_frame: int, fallback_z_index: int, direction: Vector2, start_position: Vector2) -> void:
	bullet.sprite_frames = sprite_frames
	bullet.animation = &"default"
	bullet.frame = get_frame_for_direction(config, fallback_frame, direction)
	bullet.global_position = start_position
	bullet.z_index = get_visual_z_index(config, fallback_z_index)
	bullet.scale = bullet_scale

static func tick(runtime_data: Dictionary, delta: float) -> Dictionary:
	if runtime_data.has("target_position"):
		return _tick_target_arc(runtime_data, delta)

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

	if not bool(config.get("projectile_tracks_velocity", true)):
		return

	# Rotate frame choice as the projectile direction changes
	bullet.frame = get_frame_for_direction(config, fallback_frame, velocity.normalized())

static func _tick_target_arc(runtime_data: Dictionary, delta: float) -> Dictionary:
	# Move the sprite over an arc but report collision on the floor line
	var start_position: Vector2 = runtime_data.get("position", Vector2.ZERO)
	var launch_position: Vector2 = runtime_data.get("start_position", start_position)
	var target_position: Vector2 = runtime_data.get("target_position", start_position)
	var ground_start_position: Vector2 = runtime_data.get("ground_position", launch_position)
	var age: float = float(runtime_data.get("age", 0.0)) + delta
	var total_lifetime: float = maxf(float(runtime_data.get("lifetime", 0.0)), 0.001)
	var progress := clampf(age / total_lifetime, 0.0, 1.0)
	var arc_height: float = float(runtime_data.get("arc_height", 64.0))

	var ground_end_position := launch_position.lerp(target_position, progress)
	var end_position := ground_end_position - Vector2(0.0, sin(progress * PI) * arc_height)
	var velocity := (end_position - start_position) / maxf(delta, 0.0001)
	var direction: Vector2 = velocity.normalized() if velocity.length_squared() > 0.0 else runtime_data.get("direction", Vector2.RIGHT)

	runtime_data["position"] = end_position
	runtime_data["ground_position"] = ground_end_position
	runtime_data["velocity"] = velocity
	runtime_data["direction"] = direction
	runtime_data["age"] = age
	runtime_data["lifetime"] = total_lifetime

	return {
		"start_position": start_position,
		"position": end_position,
		"collision_start_position": ground_start_position,
		"collision_position": ground_end_position,
		"velocity": velocity,
		"alive": progress < 1.0,
		"landed": progress >= 1.0,
		"arc_progress": progress
	}

static func _get_ignore_action(hit: Dictionary, pass_over_layers: Array[String]) -> String:
	if _should_ignore_tilemap_hit(hit, pass_over_layers):
		return RAYCAST_IGNORE_EXCLUDE_RID

	if _should_ignore_projectile_damage_shape_hit(hit):
		return RAYCAST_IGNORE_ADVANCE

	return RAYCAST_IGNORE_NONE

static func _should_ignore_tilemap_hit(hit: Dictionary, pass_over_layers: Array[String]) -> bool:
	if pass_over_layers.is_empty():
		return false

	var collider_variant: Variant = hit.get("collider")
	if not (collider_variant is TileMapLayer):
		return false

	var tile_layer := collider_variant as TileMapLayer
	return pass_over_layers.has(tile_layer.name)

static func _should_ignore_projectile_damage_shape_hit(hit: Dictionary) -> bool:
	var collider_variant: Variant = hit.get("collider")
	if not (collider_variant is CollisionObject2D):
		return false

	var collider := collider_variant as CollisionObject2D
	if not collider.has_method("is_projectile_damage_shape"):
		return false

	var shape_index := int(hit.get("shape", -1))
	var hit_position: Vector2 = hit.get("position", Vector2.INF)
	return not bool(collider.call("is_projectile_damage_shape", shape_index, hit_position))

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
	var launch_direction := direction.normalized()
	if launch_direction == Vector2.ZERO:
		launch_direction = Vector2.RIGHT

	var velocity := launch_direction * speed
	velocity.y -= float(config.get("arc_lift", 0.0))
	return velocity
