class_name BaseWeapon
extends Node2D

const WeaponData = preload("res://src/View/objects/weapons/WeaponData.gd")

@export var weapon_id: String = WeaponData.DEFAULT_WEAPON_ID

var active_bullets: Array[Dictionary] = []
var current_frame_index: int = 0
var fire_cooldown: float = 0.0
var reload_cooldown: float = 0.0
var reload_duration: float = 0.0
var base_position: Vector2
var bullet_frames: SpriteFrames
var bullet_exclude_rids: Array[RID] = []
var current_ammo: int = 0

@onready var gun: AnimatedSprite2D = $Gun
@onready var muzzle_marker: Marker2D = $Gun/Marker2D
@onready var bullet_template: AnimatedSprite2D = $Gun/Marker2D/Bullets

func _ready() -> void:
	base_position = position
	var owner_body := get_parent() as CollisionObject2D

	if owner_body != null:
		bullet_exclude_rids.append(owner_body.get_rid())

	if gun == null or muzzle_marker == null or bullet_template == null:
		push_error("Weapon node %s is missing Gun/Marker2D/Bullets." % name)
		set_process(false)
		return

	bullet_frames = bullet_template.sprite_frames
	bullet_template.queue_free()
	current_ammo = get_magazine_size()
	apply_frame_data(0)
	set_active(false)

func _process(delta: float) -> void:
	fire_cooldown = maxf(fire_cooldown - delta, 0.0)
	reload_cooldown = maxf(reload_cooldown - delta, 0.0)

	if reload_cooldown == 0.0 and current_ammo <= 0:
		current_ammo = get_magazine_size()

	update_aim(get_global_mouse_position())
	update_bullets(delta)

	if Input.is_key_pressed(KEY_R):
		reload()

	if Input.is_action_pressed("click"):
		shoot()

func set_active(is_active: bool) -> void:
	visible = is_active
	set_process(is_active)

func update_movement(direction: Vector2) -> void:
	var config := get_weapon_config()
	var move_offset: float = config.get("move_offset", 0.0)

	if direction == Vector2.ZERO:
		position = base_position
		return

	position = base_position + direction.normalized() * move_offset

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

func shoot() -> void:
	if fire_cooldown > 0.0 or reload_cooldown > 0.0:
		return

	var config := get_weapon_config()

	if current_ammo <= 0:
		reload()
		return

	fire_cooldown = config.get("fire_rate", 0.2)
	current_ammo -= 1
	var mouse_position := get_global_mouse_position()
	var bullet_offset := mouse_position - muzzle_marker.global_position
	var bullet_direction := bullet_offset.normalized() if bullet_offset != Vector2.ZERO else Vector2.RIGHT

	var bullet := AnimatedSprite2D.new()
	bullet.sprite_frames = bullet_frames
	bullet.animation = &"default"
	bullet.frame = get_bullet_frame()
	bullet.global_position = muzzle_marker.global_position
	bullet.z_index = gun.z_index
	bullet.scale = gun.scale

	get_tree().current_scene.add_child(bullet)

	active_bullets.append({
		"node": bullet,
		"position": bullet.global_position,
		"direction": bullet_direction,
		"speed": config.get("bullet_speed", 300.0),
		"lifetime": config.get("bullet_lifetime", 1.0),
		"collision_mask": int(config.get("bullet_collision_mask", 1))
	})

	if current_ammo <= 0:
		reload()

func update_bullets(delta: float) -> void:
	var space_state := get_world_2d().direct_space_state

	for i in range(active_bullets.size() - 1, -1, -1):
		var bullet_data := active_bullets[i]
		var bullet: AnimatedSprite2D = bullet_data["node"]

		if not is_instance_valid(bullet):
			active_bullets.remove_at(i)
			continue

		var start_position: Vector2 = bullet_data["position"]
		var bullet_direction: Vector2 = bullet_data["direction"]
		var bullet_speed: float = bullet_data["speed"]
		var end_position: Vector2 = start_position + bullet_direction * bullet_speed * delta
		var collision_mask: int = bullet_data["collision_mask"]
		var hit := raycast_bullet(space_state, start_position, end_position, collision_mask)

		if not hit.is_empty():
			bullet.global_position = hit["position"]
			bullet.queue_free()
			active_bullets.remove_at(i)
			continue

		bullet.global_position = end_position
		bullet_data["position"] = end_position
		bullet_data["lifetime"] -= delta

		if bullet_data["lifetime"] <= 0.0:
			bullet.queue_free()
			active_bullets.remove_at(i)
			continue

		active_bullets[i] = bullet_data

func raycast_bullet(space_state: PhysicsDirectSpaceState2D, from: Vector2, to: Vector2, collision_mask: int) -> Dictionary:
	var query := PhysicsRayQueryParameters2D.create(from, to, collision_mask, bullet_exclude_rids)
	return space_state.intersect_ray(query)

func reload() -> void:
	if reload_cooldown > 0.0 or current_ammo == get_magazine_size():
		return

	reload_duration = get_reload_time()
	reload_cooldown = reload_duration

func get_magazine_size() -> int:
	return int(get_weapon_config().get("ammo_mag_size", 1))

func get_reload_time() -> float:
	return float(get_weapon_config().get("reload_time", 1.0))

func get_current_ammo() -> int:
	return current_ammo

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
	gun.frame = frame_index

	var config := get_weapon_config()
	var frame_data: Dictionary = config["frames"][frame_index]
	gun.position = frame_data["gun_position"]
	muzzle_marker.position = frame_data["muzzle_offset"]
