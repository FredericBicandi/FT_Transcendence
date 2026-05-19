class_name Player
extends CharacterBody2D

const POSITION_HEARTBEAT_INTERVAL: float = 5.0
const DAMAGE_NUMBER_LIFETIME: float = 0.45
const REMOTE_SNAPSHOT_REACHED_DISTANCE: float = 0.5
const REMOTE_AIM_DISTANCE: float = 32.0
const MAX_REMOTE_SNAPSHOTS: int = 60
const REMOTE_WALK_ANIMATION_HOLD_TIME: float = 0.12
const DEFAULT_PLAYER_DISPLAY_NAME := "Player"
const DAMAGEABLE_PLAYER_GROUP := "damageable_player"
const HITBOX_POINT_EPSILON := 0.5

# Values designers can tune from the inspector
@export var move_speed: float = 120.0
@export var max_health: int = 100
@export var leg_animation_speed: float = 12.0
@export var accepts_input: bool = true
@export var register_as_player_target: bool = true
@export var enable_player_camera: bool = true
@export var respawn_delay: float = 5.0
@export var auto_attack_players: bool = false
@export var attack_range: float = 120.0
@export var default_weapon_id: String = ""
@export var shoot_sound_attenuation: float = 1.5
@export var shoot_sound_volume_db: float = -6.0
@export var shoot_sound_cooldown: float = 0.05
@export var shoot_sound_fade_margin: float = 96.0
@export var shoot_sound_silent_volume_db: float = -60.0
@export var shoot_sound_max_simultaneous_per_stream: int = 4
@export var shoot_sound_listener_cooldown: float = 0.06
@export var shoot_sound_pitch_randomness: float = 0.04
@export var shoot_sound_volume_jitter_db: float = 1.5
@export var damage_number_rise_distance: float = 22.0
@export var damage_number_spread: float = 10.0

# Runtime state for health, network sync, sounds, and remote smoothing
var health: int
var is_dead: bool = false
var leg_animation_time: float = 0.0
var hit_flash_time: float = 0.0
var respawn_timer: float = 0.0
var spawn_position: Vector2
var respawn_position_provider: Callable = Callable()
var attack_target: Node = null
var network_client: NetworkClient = null
var idle_position_heartbeat_time: float = 0.0
var shoot_sound_cooldown_remaining: float = 0.0
var listener_sound_time: float = 0.0
var active_shot_voices: Array[Dictionary] = []
var last_shot_time_by_stream: Dictionary = {}
var damage_number_settings: LabelSettings
var match_controls_enabled: bool = true
var is_remote_proxy: bool = false
var has_received_remote_snapshot: bool = false
var remote_snapshot_queue: Array[Dictionary] = []
var remote_facing_direction: Vector2 = Vector2.RIGHT
var last_sent_angle: float = 0.0
var last_sent_aim_frame: int = -1
var remote_latest_angle_degrees: float = NAN
var remote_last_move_direction: Vector2 = Vector2.ZERO
var remote_walk_animation_hold_remaining: float = 0.0
var has_sent_join_state: bool = false
var last_reported_weapon_type: String = ""
var network_player_id: String = ""
var network_player_display_name: String = ""
var next_shot_sequence: int = 0
var has_requested_server_respawn: bool = false
var observed_shot_weapon: BaseWeapon = null

@onready var head: AnimatedSprite2D = $Head
@onready var legs: AnimatedSprite2D = $Leg
@onready var weapon: WeaponsManager = $Weapons
@onready var overhead_panel: PanelContainer = $"../OverheadUiCanvasLayer/OverheadPanel"
@onready var health_bar: ProgressBar = $"../OverheadUiCanvasLayer/OverheadPanel/OverheadMargin/OverheadVBox/HealthBar"
@onready var player_name_label: Label = $"../OverheadUiCanvasLayer/OverheadPanel/OverheadMargin/OverheadVBox/PlayerNameLabel"
@onready var damage_numbers: Node2D = $DamageNumbers
@onready var player_camera: Camera2D = $Camera2D
@onready var collision_shape: CollisionShape2D = get_node_or_null("body_collision") as CollisionShape2D
@onready var damage_hitbox: Area2D = get_node_or_null("HitBox") as Area2D
@onready var damage_hitbox_shape: CollisionShape2D = get_node_or_null("HitBox/CollisionShape2D") as CollisionShape2D
@onready var shoot_sound: AudioStreamPlayer2D = $ShootSound

func _ready() -> void:
	# Start alive and remember the first spawn position
	health = max_health
	spawn_position = global_position
	network_client = get_tree().get_first_node_in_group("network_client") as NetworkClient

	if register_as_player_target:
		add_to_group("player")
	add_to_group(DAMAGEABLE_PLAYER_GROUP)

	# Match camera and weapon input to this player's control mode
	player_camera.enabled = enable_player_camera
	weapon.set_input_enabled(accepts_input)
	weapon.active_weapon_changed.connect(_on_active_weapon_changed)
	legs.frame = 0
	head.z_index = 1
	_configure_shoot_sound()
	_validate_collision_shapes()
	get_viewport().size_changed.connect(_on_viewport_size_changed)

	# Let scenes choose a starting weapon without duplicating weapon scenes
	if default_weapon_id != "":
		weapon.equip_weapon_by_id(default_weapon_id)

	# Sync UI and weapon visuals before the first frame
	_on_active_weapon_changed(weapon.get_active_weapon())
	update_health_bar()
	_update_player_name_label()
	_update_overhead_ui()
	_configure_damage_numbers()
	last_sent_angle = _get_current_aim_angle()
	last_sent_aim_frame = weapon.get_aim_frame()
	_schedule_join_state_sync()

func _physics_process(delta: float) -> void:
	# Dead players cannot move until respawn
	if is_dead:
		return

	if is_remote_proxy:
		_process_remote_movement(delta)
		return

	var previous_position := global_position

	# Only local players read keyboard movement here
	var direction := Input.get_vector("left", "right", "up", "down") if accepts_input and match_controls_enabled else Vector2.ZERO
	velocity = direction * move_speed
	move_and_slide()

	# Keep legs and weapon sway using the same movement direction
	update_legs(direction, delta)
	weapon.update_movement(direction)
	_report_position_sync(previous_position, delta)

func _process(delta: float) -> void:
	shoot_sound_cooldown_remaining = maxf(shoot_sound_cooldown_remaining - delta, 0.0)
	listener_sound_time += delta
	_report_angle_on_frame_change()
	if accepts_input:
		_update_active_shot_mix()

	# Dead players wait for respawn; AI dummies keep attacking while alive
	if is_dead:
		respawn_timer = maxf(respawn_timer - delta, 0.0)
		if respawn_timer == 0.0:
			if _uses_server_authoritative_health():
				_request_server_respawn()
			else:
				respawn()
	else:
		if auto_attack_players:
			update_auto_attack()

	update_hit_flash(delta)
	update_head_direction_from_weapon()
	_update_overhead_ui()

func update_legs(direction: Vector2, delta: float) -> void:
	# Pick the walk cycle that matches the movement direction
	var frame_range := Vector2i(15, 21)

	if direction.x < 0.0:
		frame_range = Vector2i(8, 14)
	elif direction.x > 0.0:
		frame_range = Vector2i(15, 21)
	elif direction.y != 0.0:
		frame_range = Vector2i(0, 7)
	else:
		legs.frame = 0
		leg_animation_time = 0.0
		return

	# Loop inside the selected walk cycle
	leg_animation_time += delta * leg_animation_speed
	var frame_count := frame_range.y - frame_range.x + 1
	legs.frame = frame_range.x + int(leg_animation_time) % frame_count

func update_head_direction_from_weapon() -> void:
	# Match the head direction to the weapon aim
	head.frame = weapon.get_aim_frame()

func set_health(value: int) -> void:
	# Clamp health so UI and gameplay stay in valid range
	health = clampi(value, 0, max_health)
	update_health_bar()

func apply_damage(amount: int, hit_position: Vector2 = Vector2.ZERO, _source_weapon: Node = null) -> void:
	# Ignore damage that should not count
	if is_dead or amount <= 0:
		return

	# Apply local damage for non-server controlled targets
	health = maxi(health - amount, 0)
	hit_flash_time = 0.12
	update_health_bar()
	_show_damage_number(amount, hit_position)

	if health == 0:
		die()

func update_hit_flash(delta: float) -> void:
	# Flash red for a moment after taking damage
	if hit_flash_time > 0.0:
		hit_flash_time = maxf(hit_flash_time - delta, 0.0)
		var flash_weight: float = hit_flash_time / 0.12
		var tint: Color = Color(1.0, 0.35 + 0.65 * (1.0 - flash_weight), 0.35 + 0.65 * (1.0 - flash_weight), 1.0)
		legs.modulate = tint
		head.modulate = tint
	else:
		legs.modulate = Color.WHITE
		head.modulate = Color.WHITE

func update_health_bar() -> void:
	# Keep the health bar in sync with real health
	health_bar.max_value = max_health
	health_bar.value = health

func _on_active_weapon_changed(active_weapon: BaseWeapon) -> void:
	# Reapply input rules when a new weapon is equipped
	if active_weapon == null:
		return

	active_weapon.set_input_enabled(accepts_input and match_controls_enabled)
	_bind_weapon_shot_signal(active_weapon)

	if is_remote_proxy:
		active_weapon.set_aim_target(global_position + remote_facing_direction * REMOTE_AIM_DISTANCE)
		return

	_report_weapon_switch(active_weapon)

func _configure_damage_numbers() -> void:
	damage_number_settings = LabelSettings.new()
	damage_number_settings.font_size = 14
	damage_number_settings.font_color = Color(1.0, 0.92, 0.35, 1.0)
	damage_number_settings.outline_size = 4
	damage_number_settings.outline_color = Color(0.18, 0.05, 0.05, 0.95)

func _show_damage_number(amount: int, hit_position: Vector2) -> void:
	if damage_numbers == null:
		return

	var label := Label.new()
	label.text = str(amount)
	label.label_settings = damage_number_settings
	label.z_index = 3
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var base_position := Vector2(-6.0, -18.0)
	if hit_position != Vector2.ZERO:
		base_position = to_local(hit_position) + Vector2(-6.0, -12.0)

	base_position.x += randf_range(-damage_number_spread, damage_number_spread)
	label.position = base_position
	damage_numbers.add_child(label)

	var end_position := label.position + Vector2(randf_range(-4.0, 4.0), -damage_number_rise_distance)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position", end_position, DAMAGE_NUMBER_LIFETIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, DAMAGE_NUMBER_LIFETIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.finished.connect(label.queue_free)

func play_shoot_sound(stream: AudioStream) -> void:
	if stream == null or shoot_sound_cooldown_remaining > 0.0:
		return

	shoot_sound_cooldown_remaining = shoot_sound_cooldown
	var listener := _get_listener_player()
	if listener == null:
		return

	listener._queue_shoot_sound(stream, global_position)

func _configure_shoot_sound() -> void:
	if shoot_sound == null:
		push_error("Player node %s is missing ShootSound." % name)
		return

	shoot_sound.max_distance = _get_camera_hearing_radius()
	shoot_sound.attenuation = shoot_sound_attenuation
	shoot_sound.volume_db = shoot_sound_volume_db

func _queue_shoot_sound(stream: AudioStream, shot_position: Vector2) -> void:
	if not accepts_input:
		return

	# Rate limit repeated gun sounds so busy fights stay readable
	var stream_key := _get_stream_key(stream)
	if _is_stream_rate_limited(stream_key):
		return

	var hearing_radius := _get_camera_hearing_radius()
	var distance := global_position.distance_to(shot_position)
	if distance > hearing_radius:
		return

	var same_stream_voices := _get_same_stream_voice_indices(stream_key)
	if same_stream_voices.size() >= shoot_sound_max_simultaneous_per_stream:
		# Keep closer shots when too many of the same sound are playing
		var farthest_voice_index := _find_farthest_voice_index(same_stream_voices)
		if farthest_voice_index == -1:
			return

		var farthest_distance: float = active_shot_voices[farthest_voice_index]["distance"]
		if distance >= farthest_distance:
			return

		_stop_shot_voice(farthest_voice_index)

	last_shot_time_by_stream[stream_key] = listener_sound_time
	_spawn_shot_voice(stream, stream_key, shot_position)

func _spawn_shot_voice(stream: AudioStream, stream_key: String, shot_position: Vector2) -> void:
	var voice := AudioStreamPlayer2D.new()
	voice.stream = stream
	voice.global_position = shot_position
	voice.attenuation = shoot_sound_attenuation
	voice.max_distance = _get_camera_hearing_radius()
	voice.pitch_scale = randf_range(1.0 - shoot_sound_pitch_randomness, 1.0 + shoot_sound_pitch_randomness)
	add_child(voice)

	active_shot_voices.append({
		"player": voice,
		"stream_key": stream_key,
		"position": shot_position,
		"distance": global_position.distance_to(shot_position),
		"volume_jitter_db": randf_range(-shoot_sound_volume_jitter_db, 0.0)
	})

	var voice_index := active_shot_voices.size() - 1
	_update_shot_voice_volume(voice_index)
	voice.play()

func _update_active_shot_mix() -> void:
	for i in range(active_shot_voices.size() - 1, -1, -1):
		var voice_variant: Variant = active_shot_voices[i].get("player")
		var voice := voice_variant as AudioStreamPlayer2D
		if voice == null or not is_instance_valid(voice):
			active_shot_voices.remove_at(i)
			continue

		if not voice.playing:
			voice.queue_free()
			active_shot_voices.remove_at(i)
			continue

		_update_shot_voice_volume(i)

func _update_shot_voice_volume(voice_index: int) -> void:
	var voice_data := active_shot_voices[voice_index]
	var voice := voice_data["player"] as AudioStreamPlayer2D
	if voice == null:
		return

	var shot_position: Vector2 = voice_data["position"]
	var distance := global_position.distance_to(shot_position)
	voice.global_position = shot_position
	voice.max_distance = _get_camera_hearing_radius()
	voice.volume_db = _get_shot_volume_for_distance(distance, float(voice_data["volume_jitter_db"]))
	voice_data["distance"] = distance
	active_shot_voices[voice_index] = voice_data

func _get_shot_volume_for_distance(distance: float, volume_jitter_db: float) -> float:
	var hearing_radius := _get_camera_hearing_radius()
	var fade_margin := clampf(shoot_sound_fade_margin, 0.0, hearing_radius)
	if fade_margin == 0.0:
		return shoot_sound_volume_db + volume_jitter_db

	var fade_start := hearing_radius - fade_margin
	if distance <= fade_start:
		return shoot_sound_volume_db + volume_jitter_db

	var fade_progress := inverse_lerp(fade_start, hearing_radius, minf(distance, hearing_radius))
	return lerpf(shoot_sound_volume_db + volume_jitter_db, shoot_sound_silent_volume_db, fade_progress)

func _is_stream_rate_limited(stream_key: String) -> bool:
	var last_time := float(last_shot_time_by_stream.get(stream_key, -INF))
	return listener_sound_time - last_time < shoot_sound_listener_cooldown

func _get_same_stream_voice_indices(stream_key: String) -> Array[int]:
	var indices: Array[int] = []

	for i in range(active_shot_voices.size()):
		if str(active_shot_voices[i].get("stream_key", "")) == stream_key:
			indices.append(i)

	return indices

func _find_farthest_voice_index(indices: Array[int]) -> int:
	var farthest_index := -1
	var farthest_distance := -1.0

	for index in indices:
		var distance := float(active_shot_voices[index].get("distance", 0.0))
		if distance > farthest_distance:
			farthest_distance = distance
			farthest_index = index

	return farthest_index

func _stop_shot_voice(voice_index: int) -> void:
	var voice_variant: Variant = active_shot_voices[voice_index].get("player")
	var voice := voice_variant as AudioStreamPlayer2D
	if voice != null and is_instance_valid(voice):
		voice.stop()
		voice.queue_free()

	active_shot_voices.remove_at(voice_index)

func _get_stream_key(stream: AudioStream) -> String:
	if stream.resource_path != "":
		return stream.resource_path

	return str(stream.get_instance_id())

func _get_listener_player() -> Player:
	if accepts_input:
		return self

	for candidate in get_tree().get_nodes_in_group("player"):
		var player_candidate := candidate as Player
		if player_candidate != null and player_candidate.accepts_input and not player_candidate.is_dead:
			return player_candidate

	return null

func _get_camera_hearing_radius() -> float:
	if player_camera == null:
		return 0.0

	var viewport_size := get_viewport_rect().size
	var world_size := viewport_size * player_camera.zoom
	return minf(world_size.x, world_size.y) * 0.5

func _on_viewport_size_changed() -> void:
	_configure_shoot_sound()

func die() -> void:
	# Hide and disable the player until respawn
	if is_dead:
		return

	is_dead = true
	respawn_timer = respawn_delay
	has_requested_server_respawn = false
	idle_position_heartbeat_time = 0.0
	velocity = Vector2.ZERO
	hit_flash_time = 0.0
	attack_target = null
	weapon.clear_all_projectiles()
	legs.modulate = Color.WHITE
	head.modulate = Color.WHITE
	_clear_active_shot_voices()
	legs.visible = false
	head.visible = false
	overhead_panel.visible = false
	_set_collision_shapes_disabled(true)

	var active_weapon := weapon.get_active_weapon()
	if active_weapon != null:
		active_weapon.set_active(false)

func respawn() -> void:
	# Restore the player so they can move and shoot again
	health = max_health
	global_position = _resolve_respawn_position()
	update_health_bar()
	_restore_after_respawn()

	if accepts_input and network_client != null:
		_send_respawn_state()

func update_auto_attack() -> void:
	# AI picks a live target and keeps aiming at it
	if not is_valid_attack_target(attack_target):
		attack_target = _find_nearest_attack_target()
		if not is_valid_attack_target(attack_target):
			return

	var target_body := attack_target as Node2D
	if target_body == null:
		return

	var active_weapon := weapon.get_active_weapon()
	if active_weapon == null:
		return

	# Aim first, shoot only when close enough
	active_weapon.set_aim_target(target_body.global_position)

	if global_position.distance_to(target_body.global_position) > attack_range:
		return

	active_weapon.shoot()

func _find_nearest_attack_target() -> Node:
	var nearest_target: Node = null
	var nearest_distance_squared := INF

	for candidate in get_tree().get_nodes_in_group("player"):
		if not is_valid_attack_target(candidate):
			continue

		var candidate_body := candidate as Node2D
		if candidate_body == null:
			continue

		var distance_squared := global_position.distance_squared_to(candidate_body.global_position)
		if distance_squared < nearest_distance_squared:
			nearest_distance_squared = distance_squared
			nearest_target = candidate_body

	return nearest_target

func _clear_active_shot_voices() -> void:
	for voice_data in active_shot_voices:
		var voice_variant: Variant = voice_data.get("player")
		var voice := voice_variant as AudioStreamPlayer2D
		if voice != null and is_instance_valid(voice):
			voice.stop()
			voice.queue_free()

	active_shot_voices.clear()
	last_shot_time_by_stream.clear()

func is_valid_attack_target(target: Node) -> bool:
	# Ignore targets that cannot be attacked anymore
	if target == null or not is_instance_valid(target):
		return false

	return not bool(target.get("is_dead"))

func _report_position_sync(previous_position: Vector2, delta: float) -> void:
	# Only the local player reports movement to the server
	if not accepts_input or not match_controls_enabled or network_client == null:
		return

	if not global_position.is_equal_approx(previous_position):
		idle_position_heartbeat_time = 0.0
		_send_move_position()
		return

	idle_position_heartbeat_time += delta
	if idle_position_heartbeat_time < POSITION_HEARTBEAT_INTERVAL:
		return

	# Send idle pings so the server still knows where we are
	idle_position_heartbeat_time = 0.0
	_send_ping_position()

func _send_move_position() -> void:
	last_sent_angle = _get_current_aim_angle()
	network_client.send_move(global_position.x, global_position.y, last_sent_angle)

func _send_ping_position() -> void:
	last_sent_angle = _get_current_aim_angle()
	network_client.send_idle(global_position.x, global_position.y, last_sent_angle)

func send_join_state() -> void:
	if has_sent_join_state or is_remote_proxy or not accepts_input or network_client == null:
		return

	global_position = _resolve_respawn_position()

	if not _send_full_player_state():
		return

	has_sent_join_state = true

func _report_weapon_switch(active_weapon: BaseWeapon) -> void:
	if active_weapon == null or not accepts_input or not match_controls_enabled or network_client == null:
		return

	var weapon_type := active_weapon.get_weapon_name()
	if weapon_type == last_reported_weapon_type:
		return

	network_client.send_weapon_switch(weapon_type)
	last_reported_weapon_type = weapon_type

func _bind_weapon_shot_signal(active_weapon: BaseWeapon) -> void:
	# Rebind shot reporting when the equipped weapon changes
	if observed_shot_weapon != null and observed_shot_weapon.shot_fired.is_connected(_on_weapon_shot_fired):
		observed_shot_weapon.shot_fired.disconnect(_on_weapon_shot_fired)

	observed_shot_weapon = active_weapon
	if observed_shot_weapon != null and not observed_shot_weapon.shot_fired.is_connected(_on_weapon_shot_fired):
		observed_shot_weapon.shot_fired.connect(_on_weapon_shot_fired)

func _on_weapon_shot_fired(angle_radians: float, weapon_type: String, start_position: Vector2, target_position: Vector2) -> void:
	if is_remote_proxy or not accepts_input or not match_controls_enabled or network_client == null:
		return

	network_client.send_shoot(angle_radians, weapon_type, global_position, start_position, target_position)

func _schedule_join_state_sync() -> void:
	if is_remote_proxy or not accepts_input or network_client == null:
		return

	# Try now, but also wait for the socket if it is still connecting
	call_deferred("_try_send_join_state")

	if has_sent_join_state:
		return

	if not network_client.connection_established.is_connected(_on_network_connection_established):
		network_client.connection_established.connect(_on_network_connection_established)

func _try_send_join_state() -> void:
	send_join_state()

	if has_sent_join_state and network_client != null and network_client.connection_established.is_connected(_on_network_connection_established):
		network_client.connection_established.disconnect(_on_network_connection_established)

func _on_network_connection_established() -> void:
	send_join_state()

	if has_sent_join_state and network_client != null and network_client.connection_established.is_connected(_on_network_connection_established):
		network_client.connection_established.disconnect(_on_network_connection_established)

func _send_respawn_state() -> void:
	var active_weapon := weapon.get_active_weapon() if weapon != null else null
	if active_weapon == null or network_client == null:
		return

	last_sent_angle = _get_current_aim_angle()
	network_client.send_respawn(
		global_position.x,
		global_position.y,
		last_sent_angle,
		active_weapon.get_weapon_name()
	)
	idle_position_heartbeat_time = 0.0

func _request_server_respawn() -> void:
	if has_requested_server_respawn or not accepts_input or network_client == null:
		return

	# Ask the server to accept this respawn once
	has_requested_server_respawn = true
	global_position = _resolve_respawn_position()
	_send_respawn_state()

func set_spawn_position(position: Vector2) -> void:
	spawn_position = position

func set_respawn_position_provider(provider: Callable) -> void:
	respawn_position_provider = provider

func _resolve_respawn_position() -> Vector2:
	if respawn_position_provider.is_valid():
		var next_position_variant: Variant = respawn_position_provider.call()
		if next_position_variant is Vector2:
			spawn_position = next_position_variant

	return spawn_position

func _send_full_player_state() -> bool:
	var active_weapon := weapon.get_active_weapon() if weapon != null else null
	if active_weapon == null or network_client == null:
		return false

	last_sent_angle = _get_current_aim_angle()
	network_client.send_on_join(
		global_position.x,
		global_position.y,
		last_sent_angle,
		active_weapon.get_weapon_name()
	)
	last_reported_weapon_type = active_weapon.get_weapon_name()
	last_sent_aim_frame = weapon.get_aim_frame()
	return true

func set_match_controls_enabled(is_enabled: bool) -> void:
	match_controls_enabled = is_enabled
	velocity = Vector2.ZERO
	idle_position_heartbeat_time = 0.0

	if weapon != null:
		weapon.set_input_enabled(accepts_input and match_controls_enabled)
		last_sent_aim_frame = weapon.get_aim_frame()

func configure_as_remote_proxy() -> void:
	is_remote_proxy = true
	accepts_input = false
	enable_player_camera = false
	register_as_player_target = false
	add_to_group(DAMAGEABLE_PLAYER_GROUP)
	# Let bullets hit remote proxies without making them block movement
	collision_layer = 2
	collision_mask = 0
	velocity = Vector2.ZERO
	remote_snapshot_queue.clear()
	has_received_remote_snapshot = false
	remote_facing_direction = Vector2.RIGHT
	remote_latest_angle_degrees = NAN
	remote_last_move_direction = Vector2.ZERO
	remote_walk_animation_hold_remaining = 0.0

	if collision_shape != null:
		collision_shape.disabled = false
	if damage_hitbox != null:
		damage_hitbox.monitorable = true
	if damage_hitbox_shape != null:
		damage_hitbox_shape.disabled = false

	if weapon != null:
		weapon.set_input_enabled(false)
		var active_weapon := weapon.get_active_weapon()
		if active_weapon != null:
			active_weapon.set_aim_target(global_position + remote_facing_direction * REMOTE_AIM_DISTANCE)

func set_network_player_id(player_id: String) -> void:
	network_player_id = player_id.strip_edges()
	_update_player_name_label()

func get_network_player_id() -> String:
	return network_player_id

func set_network_player_display_name(player_name: String) -> void:
	network_player_display_name = player_name.strip_edges()
	_update_player_name_label()

func get_network_player_display_name() -> String:
	return network_player_display_name

func is_projectile_damage_shape(shape_index: int, hit_position: Vector2 = Vector2.INF) -> bool:
	if damage_hitbox_shape == null or shape_index < 0:
		return false

	var owner_id := shape_find_owner(shape_index)
	if owner_id == -1:
		return false

	return hit_position != Vector2.INF and _is_global_point_inside_damage_hitbox(hit_position)

func _update_player_name_label() -> void:
	if player_name_label == null:
		return

	var display_name := network_player_display_name.strip_edges()
	player_name_label.text = display_name if display_name != "" else DEFAULT_PLAYER_DISPLAY_NAME

func _update_overhead_ui() -> void:
	if overhead_panel == null:
		return

	overhead_panel.visible = not is_dead
	if is_dead:
		return

	# Position the nameplate in screen space so it stays sharp
	var screen_position: Vector2 = get_viewport().get_canvas_transform() * global_position
	var panel_size: Vector2 = overhead_panel.size
	var panel_x: float = round(screen_position.x - panel_size.x * 0.5)
	var panel_y: float = round(screen_position.y - 30.0 - panel_size.y)
	overhead_panel.position = Vector2(panel_x, panel_y)

func create_authoritative_shot_id() -> String:
	next_shot_sequence += 1
	return "%s:%d" % [network_player_id if network_player_id != "" else "local", next_shot_sequence]

func report_authoritative_hit(target: Node, damage: int, hit_position: Vector2, source_weapon: Node, shot_id_override: String = "") -> bool:
	if network_client == null or is_remote_proxy or not accepts_input or damage <= 0:
		return false

	# Only report hits against players the server can identify
	if target == null or not is_instance_valid(target) or not target.has_method("get_network_player_id"):
		return false

	var target_player_id := str(target.call("get_network_player_id"))
	if target_player_id == "":
		return false

	var weapon_type := ""
	if source_weapon != null and source_weapon.has_method("get_weapon_name"):
		weapon_type = str(source_weapon.call("get_weapon_name"))

	var shot_id := shot_id_override
	if shot_id == "":
		shot_id = create_authoritative_shot_id()

	var shot_angle := rad_to_deg((hit_position - global_position).angle())
	if shot_angle < 0.0:
		shot_angle += 360.0
	network_client.send_hit(target_player_id, weapon_type, damage, shot_id, global_position.x, global_position.y, shot_angle, Time.get_ticks_msec())
	return true

func apply_authoritative_health_state(new_health: int, authoritative_is_dead: bool, reported_damage: int = 0) -> void:
	if is_dead and not authoritative_is_dead and respawn_timer > 0.0 and not is_remote_proxy:
		# Do not let late health packets cancel a local respawn countdown
		return

	var clamped_health := clampi(new_health, 0, max_health)
	var took_damage := clamped_health < health
	health = clamped_health
	update_health_bar()

	if took_damage:
		hit_flash_time = 0.12
		if reported_damage > 0:
			_show_damage_number(reported_damage, global_position)

	if authoritative_is_dead:
		die()
		health = 0
		update_health_bar()
		return

	if is_dead:
		_restore_after_respawn()

func _restore_after_respawn() -> void:
	is_dead = false
	respawn_timer = 0.0
	has_requested_server_respawn = false
	idle_position_heartbeat_time = 0.0
	legs.frame = 0
	leg_animation_time = 0.0
	legs.visible = true
	head.visible = true
	overhead_panel.visible = true
	_set_collision_shapes_disabled(false)

	weapon.clear_all_projectiles()
	var active_weapon := weapon.get_active_weapon()
	if active_weapon != null:
		active_weapon.set_input_enabled(accepts_input and match_controls_enabled)
		active_weapon.set_active(true)

func _uses_server_authoritative_health() -> bool:
	return network_client != null and (accepts_input or is_remote_proxy)

func _validate_collision_shapes() -> void:
	if collision_shape == null:
		push_error("Player node %s is missing body_collision." % name)
	if damage_hitbox == null:
		push_error("Player node %s is missing HitBox." % name)
	if damage_hitbox_shape == null:
		push_error("Player node %s is missing HitBox/CollisionShape2D." % name)

func _set_collision_shapes_disabled(is_disabled: bool) -> void:
	if collision_shape != null:
		collision_shape.set_deferred("disabled", is_disabled)
	if damage_hitbox != null:
		damage_hitbox.set_deferred("monitorable", not is_disabled)
	if damage_hitbox_shape != null:
		damage_hitbox_shape.set_deferred("disabled", is_disabled)

func _is_global_point_inside_damage_hitbox(global_point: Vector2) -> bool:
	if damage_hitbox_shape == null or damage_hitbox_shape.shape == null:
		return false

	var local_point := damage_hitbox_shape.to_local(global_point)
	var shape := damage_hitbox_shape.shape
	if shape is RectangleShape2D:
		var half_size := (shape as RectangleShape2D).size * 0.5 + Vector2.ONE * HITBOX_POINT_EPSILON
		return absf(local_point.x) <= half_size.x and absf(local_point.y) <= half_size.y

	if shape is CircleShape2D:
		return local_point.length() <= (shape as CircleShape2D).radius + HITBOX_POINT_EPSILON

	return false

func enqueue_remote_snapshot(position: Vector2, aim_angle_degrees: float = NAN) -> void:
	if not is_nan(aim_angle_degrees):
		remote_latest_angle_degrees = aim_angle_degrees

	if not has_received_remote_snapshot:
		# First remote packet should snap, not slide from origin
		snap_remote_snapshot(position, remote_latest_angle_degrees)
		return

	if remote_snapshot_queue.size() >= MAX_REMOTE_SNAPSHOTS:
		# Drop old snapshots if the client falls behind
		remote_snapshot_queue.remove_at(0)

	remote_snapshot_queue.append({
		"position": position,
		"aim_angle_degrees": remote_latest_angle_degrees
	})

func snap_remote_snapshot(position: Vector2, aim_angle_degrees: float = NAN) -> void:
	if not is_nan(aim_angle_degrees):
		remote_latest_angle_degrees = aim_angle_degrees

	has_received_remote_snapshot = true
	remote_snapshot_queue.clear()
	global_position = position
	velocity = Vector2.ZERO
	remote_last_move_direction = Vector2.ZERO
	remote_walk_animation_hold_remaining = 0.0
	update_legs(Vector2.ZERO, 0.0)
	weapon.update_movement(Vector2.ZERO)
	_apply_remote_aim(global_position + remote_facing_direction, remote_latest_angle_degrees)

func update_remote_angle(aim_angle_degrees: float) -> void:
	remote_latest_angle_degrees = aim_angle_degrees
	_apply_remote_aim(global_position + remote_facing_direction, remote_latest_angle_degrees)

func set_remote_weapon(weapon_type: String) -> void:
	if weapon == null or weapon_type == "":
		return

	# Normalize server weapon names before trying to equip them
	var normalized_weapon_type := _normalize_weapon_type(weapon_type)
	if not weapon.equip_weapon_by_id(normalized_weapon_type):
		weapon.equip_weapon(StringName(normalized_weapon_type))
	if weapon.get_active_weapon() == null or weapon.get_active_weapon().get_weapon_name() != normalized_weapon_type:
		weapon.equip_weapon(StringName(weapon_type))

	var active_weapon := weapon.get_active_weapon()
	if active_weapon != null:
		active_weapon.set_input_enabled(false)
		active_weapon.set_aim_target(global_position + remote_facing_direction * REMOTE_AIM_DISTANCE)

func _normalize_weapon_type(weapon_type: String) -> String:
	var key := weapon_type.strip_edges().to_lower().replace("_", " ").replace("-", " ")
	key = " ".join(key.split(" ", false))

	match key:
		"rocket launcher", "rocketlauncher", "rocket", "rpg":
			return "Rocket Launcher"
		"assult rifle", "assault rifle", "assultrifle", "assaultrifle", "rifle", "af rifle", "afrifle":
			return "Assult rifle"
		"sniper", "sniper rifle", "sniperrifle":
			return "Sniper"
		_:
			return weapon_type

func spawn_remote_bullet_from_server(position: Vector2, angle_radians: float, weapon_type: String, target_position: Variant = null, start_position: Variant = null) -> void:
	# Snap the shooter to the server position before replaying the shot
	global_position = position
	remote_snapshot_queue.clear()
	set_remote_weapon(weapon_type)
	var has_target_position := target_position is Vector2
	var aim_target := global_position + Vector2.RIGHT.rotated(angle_radians)
	if has_target_position:
		aim_target = target_position as Vector2

	if has_target_position:
		var aim_direction := aim_target - global_position
		remote_latest_angle_degrees = rad_to_deg(aim_direction.angle()) if aim_direction != Vector2.ZERO else rad_to_deg(angle_radians)
		_apply_remote_aim(aim_target, NAN)
	else:
		remote_latest_angle_degrees = rad_to_deg(angle_radians)
		_apply_remote_aim(aim_target, remote_latest_angle_degrees)

	var active_weapon := weapon.get_active_weapon()
	if active_weapon != null:
		active_weapon.spawn_remote_bullet(angle_radians, target_position, start_position)

func _process_remote_movement(delta: float) -> void:
	while not remote_snapshot_queue.is_empty():
		var queued_snapshot := remote_snapshot_queue[0]
		var queued_position: Vector2 = queued_snapshot["position"]
		var queued_offset := queued_position - global_position
		var queued_distance := queued_offset.length()
		if queued_distance > REMOTE_SNAPSHOT_REACHED_DISTANCE:
			break

		if queued_distance > 0.001:
			remote_last_move_direction = queued_offset / queued_distance
			remote_walk_animation_hold_remaining = REMOTE_WALK_ANIMATION_HOLD_TIME

		global_position = queued_position
		_apply_remote_aim(queued_position, float(queued_snapshot.get("aim_angle_degrees", NAN)))
		remote_snapshot_queue.remove_at(0)

	if remote_snapshot_queue.is_empty():
		velocity = Vector2.ZERO
		if remote_walk_animation_hold_remaining > 0.0 and remote_last_move_direction != Vector2.ZERO:
			# Hold the walk frame briefly so remote movement does not flicker
			remote_walk_animation_hold_remaining = maxf(remote_walk_animation_hold_remaining - delta, 0.0)
			update_legs(remote_last_move_direction, delta)
			weapon.update_movement(remote_last_move_direction)
		else:
			update_legs(Vector2.ZERO, delta)
			weapon.update_movement(Vector2.ZERO)
		_apply_remote_aim(global_position + remote_facing_direction, NAN)
		return

	var next_snapshot := remote_snapshot_queue[0]
	var target_position: Vector2 = next_snapshot["position"]
	var offset := target_position - global_position
	var direction := offset.normalized()
	var step_distance := move_speed * delta
	if offset.length() <= step_distance:
		global_position = target_position
		remote_snapshot_queue.remove_at(0)
	else:
		# Remote players follow server snapshots without local collision solving
		global_position = global_position.move_toward(target_position, step_distance)

	remote_last_move_direction = direction
	remote_walk_animation_hold_remaining = REMOTE_WALK_ANIMATION_HOLD_TIME
	velocity = Vector2.ZERO
	update_legs(direction, delta)
	weapon.update_movement(direction)
	_apply_remote_aim(target_position, float(next_snapshot.get("aim_angle_degrees", NAN)))

func _apply_remote_aim(target_position: Vector2, aim_angle_degrees: float) -> void:
	# Prefer server aim angle, then fall back to movement direction
	var aim_direction := remote_facing_direction

	if not is_nan(aim_angle_degrees):
		aim_direction = Vector2.RIGHT.rotated(deg_to_rad(aim_angle_degrees))
	else:
		var movement_direction := target_position - global_position
		if movement_direction != Vector2.ZERO:
			aim_direction = movement_direction.normalized()

	if aim_direction == Vector2.ZERO:
		aim_direction = Vector2.RIGHT

	remote_facing_direction = aim_direction.normalized()
	var active_weapon := weapon.get_active_weapon()
	if active_weapon != null:
		active_weapon.set_aim_target(global_position + remote_facing_direction * REMOTE_AIM_DISTANCE)

func _get_current_aim_angle() -> float:
	var aim_direction := get_global_mouse_position() - global_position
	if aim_direction == Vector2.ZERO:
		return 0.0

	var angle := rad_to_deg(aim_direction.angle())
	if angle < 0.0:
		angle += 360.0

	return angle

func _report_angle_on_frame_change() -> void:
	if not accepts_input or not match_controls_enabled or network_client == null or weapon == null:
		return

	var current_aim_frame := weapon.get_aim_frame()
	if current_aim_frame == last_sent_aim_frame:
		return

	# Send only when the 8-direction frame changes to reduce traffic
	last_sent_aim_frame = current_aim_frame
	last_sent_angle = _get_current_aim_angle()
	network_client.send_angle(last_sent_angle)
