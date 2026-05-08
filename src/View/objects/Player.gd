class_name Player
extends CharacterBody2D

# Tuning values for movement, health, control mode, respawn, and optional AI behavior.
@export var move_speed: float = 120.0
@export var max_health: int = 200
@export var leg_animation_speed: float = 12.0
@export var accepts_input: bool = true
@export var register_as_player_target: bool = true
@export var enable_player_camera: bool = true
@export var respawn_delay: float = 5.0
@export var auto_attack_players: bool = false
@export var attack_range: float = 120.0
@export var default_weapon_id: String = ""

# Runtime state for health, death flow, leg animation, hit flash, respawn timing, and AI target tracking.
var health: int
var is_dead: bool = false
var leg_animation_time: float = 0.0
var hit_flash_time: float = 0.0
var respawn_timer: float = 0.0
var spawn_position: Vector2
var attack_target: Node = null
var network_client: NetworkClient = null

@onready var head: AnimatedSprite2D = $Head
@onready var legs: AnimatedSprite2D = $Leg
@onready var weapon: WeaponsManager = $Weapons
@onready var health_bar: ProgressBar = $HealthBar
@onready var reload_bar: ProgressBar = $ReloadBar
@onready var player_camera: Camera2D = $Camera2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

func _ready() -> void:
	# Initialize health, remember where this player should respawn, and register for AI targeting if needed.
	health = max_health
	spawn_position = global_position
	network_client = get_tree().get_first_node_in_group("network_client") as NetworkClient

	if register_as_player_target:
		add_to_group("player")

	# Configure child systems so they match whether this character is player-controlled or AI-controlled.
	player_camera.enabled = enable_player_camera
	weapon.set_input_enabled(accepts_input)
	weapon.active_weapon_changed.connect(_on_active_weapon_changed)
	legs.frame = 0
	head.z_index = 1

	# Let the scene force a starting weapon without changing the weapon scene itself.
	if default_weapon_id != "":
		weapon.equip_weapon_by_id(default_weapon_id)

	# Sync all UI and weapon-dependent visuals immediately.
	_on_active_weapon_changed(weapon.get_active_weapon())
	update_health_bar()
	update_reload_bar()

func _physics_process(delta: float) -> void:
	# Dead characters stop moving entirely until respawn.
	if is_dead:
		return

	var previous_position := global_position

	# Human-controlled players read movement input here; AI characters stay still and only aim/shoot.
	var direction := Input.get_vector("left", "right", "up", "down") if accepts_input else Vector2.ZERO
	velocity = direction * move_speed
	move_and_slide()

	# Keep movement animation and equipped weapon sway in sync with the body direction.
	update_legs(direction, delta)
	weapon.update_movement(direction)
	_report_position_change(previous_position)

func _process(delta: float) -> void:
	# Death state counts down to respawn; alive AI-controlled dummies can auto-attack player targets.
	if is_dead:
		respawn_timer = maxf(respawn_timer - delta, 0.0)
		if respawn_timer == 0.0:
			respawn()
	else:
		if auto_attack_players:
			update_auto_attack()

	update_hit_flash(delta)
	update_head_direction_from_weapon()
	update_reload_bar()

func update_legs(direction: Vector2, delta: float) -> void:
	# Choose a leg animation band based on movement direction and loop through its frames.
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

	# Advance through the selected directional walk cycle.
	leg_animation_time += delta * leg_animation_speed
	var frame_count := frame_range.y - frame_range.x + 1
	legs.frame = frame_range.x + int(leg_animation_time) % frame_count

func update_head_direction_from_weapon() -> void:
	# The head uses the same 8-direction aim frame as the active weapon.
	head.frame = weapon.get_aim_frame()

func set_health(value: int) -> void:
	# Clamp manual health changes so UI and gameplay never see values outside valid bounds.
	health = clampi(value, 0, max_health)
	update_health_bar()

func apply_damage(amount: int, _hit_position: Vector2 = Vector2.ZERO, _source_weapon: Node = null) -> void:
	# Ignore invalid damage and damage received while already dead.
	if is_dead or amount <= 0:
		return

	# Apply damage, trigger the hit flash, and die if health reaches zero.
	health = maxi(health - amount, 0)
	hit_flash_time = 0.12
	update_health_bar()

	if health == 0:
		die()

func update_hit_flash(delta: float) -> void:
	# Briefly tint the player red after taking damage, then restore the normal colors.
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
	# Keep the health bar range and fill aligned with the current max/current health.
	health_bar.max_value = max_health
	health_bar.value = health

func update_reload_bar() -> void:
	# The reload bar only appears while the active weapon is currently reloading.
	var active_weapon = weapon.get_active_weapon()

	if active_weapon == null or not active_weapon.is_reloading():
		reload_bar.visible = false
		reload_bar.value = 0.0
		return

	reload_bar.visible = true
	reload_bar.max_value = 1.0
	reload_bar.value = active_weapon.get_reload_progress()

func _on_active_weapon_changed(active_weapon: BaseWeapon) -> void:
	# Whenever the equipped weapon changes, reapply whether this character should control it directly.
	if active_weapon == null:
		return

	active_weapon.set_input_enabled(accepts_input)

func die() -> void:
	# Enter the dead state, stop interacting with the world, and hide body/UI visuals until respawn.
	is_dead = true
	respawn_timer = respawn_delay
	velocity = Vector2.ZERO
	hit_flash_time = 0.0
	attack_target = null
	weapon.clear_all_projectiles()
	legs.modulate = Color.WHITE
	head.modulate = Color.WHITE
	legs.visible = false
	head.visible = false
	health_bar.visible = false
	reload_bar.visible = false
	collision_shape.set_deferred("disabled", true)

	var active_weapon := weapon.get_active_weapon()
	if active_weapon != null:
		active_weapon.set_active(false)

func respawn() -> void:
	# Restore health, position, collision, visuals, and weapon state so the player can act again.
	is_dead = false
	respawn_timer = 0.0
	health = max_health
	global_position = spawn_position
	update_health_bar()
	legs.frame = 0
	leg_animation_time = 0.0
	legs.visible = true
	head.visible = true
	health_bar.visible = true
	reload_bar.visible = false
	collision_shape.set_deferred("disabled", false)

	weapon.clear_all_projectiles()
	var active_weapon := weapon.get_active_weapon()
	if active_weapon != null:
		active_weapon.set_input_enabled(accepts_input)
		active_weapon.set_active(true)

func update_auto_attack() -> void:
	# AI characters lock onto the first node in the player group and keep aiming at it.
	if not is_valid_attack_target(attack_target):
		attack_target = get_tree().get_first_node_in_group("player")
		if not is_valid_attack_target(attack_target):
			return

	var target_body := attack_target as Node2D
	if target_body == null:
		return

	var active_weapon := weapon.get_active_weapon()
	if active_weapon == null:
		return

	# Update aim every frame, but only fire once the target is inside attack range.
	active_weapon.set_aim_target(target_body.global_position)

	if global_position.distance_to(target_body.global_position) > attack_range:
		return

	active_weapon.shoot()

func is_valid_attack_target(target: Node) -> bool:
	# Ignore missing, freed, or dead targets so AI can reacquire a live player.
	if target == null or not is_instance_valid(target):
		return false

	return not bool(target.get("is_dead"))

func _report_position_change(previous_position: Vector2) -> void:
	# Only the locally controlled character reports movement to the websocket server.
	if not accepts_input or network_client == null:
		return

	if global_position.is_equal_approx(previous_position):
		return

	network_client.send_move(global_position.x, global_position.y)
