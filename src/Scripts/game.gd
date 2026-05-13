extends Node2D

const PLAYER_SCENE: PackedScene = preload("res://src/Objects/player.tscn")

# Cache the player, weapons, and HUD nodes once so the scene can update UI cheaply.
@onready var player = $Player
@onready var player_body = $Player/CharacterBody2D
@onready var weapons: WeaponsManager = $Player/CharacterBody2D/Weapons
@onready var weapon_panel: Control = $WeaponSwitcher/CanvasLayer/WeaponHud
@onready var weapon_icon: TextureRect = $WeaponSwitcher/CanvasLayer/WeaponHud/MarginContainer/VBoxContainer/WeaponIcon
@onready var weapon_name: Label = $WeaponSwitcher/CanvasLayer/WeaponHud/MarginContainer/VBoxContainer/WeaponName
@onready var ammo_label: Label = $WeaponSwitcher/CanvasLayer/WeaponHud/MarginContainer/VBoxContainer/AmmoLabel
@onready var respawn_overlay: ColorRect = $RespawnUi/CanvasLayer/RespawnOverlay
@onready var respawn_message: Label = $RespawnUi/CanvasLayer/RespawnOverlay/CenterContainer/VBoxContainer/RespawnMessage
@onready var respawn_countdown: Label = $RespawnUi/CanvasLayer/RespawnOverlay/CenterContainer/VBoxContainer/RespawnCountdown
@onready var timer_label: Label = $MatchUi/CanvasLayer/TimerLabel
@onready var network_client: NetworkClient = get_tree().get_first_node_in_group("network_client") as NetworkClient

var observed_weapon: BaseWeapon
var remote_players: Dictionary = {}
var local_player_id: String = ""
var room_id: String = ""
var remaining_match_seconds: float = 0.0
var match_has_ended: bool = false

func _ready() -> void:
	# Listen for weapon swaps so the HUD can follow whichever weapon is currently equipped.
	weapons.active_weapon_changed.connect(_on_active_weapon_changed)
	_on_active_weapon_changed(weapons.get_active_weapon())
	_connect_network_signals()
	apply_network_snapshot()
	update_respawn_overlay()
	update_match_ui()
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)

func _process(delta: float) -> void:
	# The respawn overlay depends on runtime player state, so refresh it every frame.
	if not match_has_ended and remaining_match_seconds > 0.0:
		remaining_match_seconds = maxf(remaining_match_seconds - delta, 0.0)

	update_respawn_overlay()
	update_match_ui()

func _on_active_weapon_changed(weapon: BaseWeapon) -> void:
	# Stop listening to the old weapon before tracking the newly equipped one.
	if observed_weapon != null and observed_weapon.ammo_changed.is_connected(_on_ammo_changed):
		observed_weapon.ammo_changed.disconnect(_on_ammo_changed)

	observed_weapon = weapon

	# If no weapon is active, hide the HUD instead of showing stale data.
	if observed_weapon == null:
		weapon_panel.visible = false
		weapon_icon.texture = null
		return

	# Fill the HUD from the new weapon and subscribe to future ammo updates.
	weapon_panel.visible = true
	weapon_icon.texture = observed_weapon.get_weapon_icon()
	weapon_name.text = observed_weapon.get_weapon_name()
	observed_weapon.ammo_changed.connect(_on_ammo_changed)
	_on_ammo_changed(observed_weapon.get_current_ammo(), observed_weapon.get_magazine_size())

func _on_ammo_changed(current_ammo: int, max_ammo: int) -> void:
	# Show current magazine ammo in a compact weapon HUD format.
	ammo_label.text = "%d/%d" % [current_ammo, max_ammo]

func update_respawn_overlay() -> void:
	# Read death and respawn state directly from the player body script.
	var is_dead: bool = bool(player_body.get("is_dead"))
	respawn_overlay.visible = is_dead

	if not is_dead:
		return

	# While dead, show a simple countdown until the player becomes active again.
	var respawn_timer: float = float(player_body.get("respawn_timer"))
	respawn_message.text = "Respawning"
	respawn_countdown.text = "%.1f" % maxf(respawn_timer, 0.0)

func _connect_network_signals() -> void:
	if network_client == null:
		return

	if not network_client.room_joined.is_connected(_on_room_joined):
		network_client.room_joined.connect(_on_room_joined)

	if not network_client.time_synced.is_connected(_on_time_synced):
		network_client.time_synced.connect(_on_time_synced)

	if not network_client.player_move_received.is_connected(_on_player_move_received):
		network_client.player_move_received.connect(_on_player_move_received)

	if not network_client.player_angle_received.is_connected(_on_player_angle_received):
		network_client.player_angle_received.connect(_on_player_angle_received)

	if not network_client.player_weapon_switch_received.is_connected(_on_player_weapon_switch_received):
		network_client.player_weapon_switch_received.connect(_on_player_weapon_switch_received)

	if not network_client.player_health_received.is_connected(_on_player_health_received):
		network_client.player_health_received.connect(_on_player_health_received)

	if not network_client.bullet_spawn_received.is_connected(_on_bullet_spawn_received):
		network_client.bullet_spawn_received.connect(_on_bullet_spawn_received)

	if not network_client.player_left_received.is_connected(_on_player_left_received):
		network_client.player_left_received.connect(_on_player_left_received)

	if not network_client.match_ended.is_connected(_on_match_ended):
		network_client.match_ended.connect(_on_match_ended)

func apply_network_snapshot() -> void:
	if network_client == null:
		return

	local_player_id = network_client.local_player_id
	room_id = network_client.local_room_id
	player_body.set_network_player_id(local_player_id)
	remaining_match_seconds = maxf(network_client.remaining_seconds, 0.0)
	match_has_ended = network_client.match_finished
	player_body.set_match_controls_enabled(not match_has_ended)
	_apply_local_player_state(network_client.last_room_joined_message)
	_apply_initial_remote_players(network_client.last_room_joined_message)
	_apply_cached_remote_players()

func update_match_ui() -> void:
	timer_label.text = _format_match_time(remaining_match_seconds)

func _format_match_time(total_seconds: float) -> String:
	var clamped_seconds := maxi(int(ceil(maxf(total_seconds, 0.0))), 0)
	var minutes := clamped_seconds / 60
	var seconds := clamped_seconds % 60
	return "%02d:%02d" % [minutes, seconds]

func _on_room_joined(message: Dictionary) -> void:
	local_player_id = str(message.get("playerId", ""))
	room_id = str(message.get("roomId", ""))
	player_body.set_network_player_id(local_player_id)
	remaining_match_seconds = maxf(float(message.get("remainingSeconds", 0.0)), 0.0)
	match_has_ended = false
	player_body.set_match_controls_enabled(true)
	_apply_local_player_state(message)
	_apply_initial_remote_players(message)
	update_match_ui()

func _on_time_synced(message: Dictionary) -> void:
	var synced_room_id := str(message.get("roomId", ""))
	if room_id != "" and synced_room_id != "" and synced_room_id != room_id:
		return

	remaining_match_seconds = maxf(float(message.get("remainingSeconds", remaining_match_seconds)), 0.0)
	update_match_ui()

func _on_player_move_received(message: Dictionary) -> void:
	var player_id := str(message.get("playerId", ""))
	if player_id == "" or player_id == local_player_id:
		return

	_apply_remote_player_state(message)

func _on_player_left_received(player_id: String) -> void:
	_remove_remote_player(player_id)

func _on_player_angle_received(message: Dictionary) -> void:
	var player_id := str(message.get("playerId", ""))
	if player_id == "" or player_id == local_player_id or not message.has("angle"):
		return

	_apply_remote_player_state(message)

func _on_player_weapon_switch_received(message: Dictionary) -> void:
	var player_id := str(message.get("playerId", ""))
	if player_id == "" or player_id == local_player_id:
		return

	_apply_remote_player_state(message)

func _on_player_health_received(message: Dictionary) -> void:
	var player_id := str(message.get("playerId", message.get("id", "")))
	if player_id == "":
		return

	if player_id == local_player_id:
		_apply_local_player_state(message)
		return

	_apply_remote_player_state(message)

func _on_match_ended(message: Dictionary) -> void:
	var ended_room_id := str(message.get("roomId", ""))
	if room_id != "" and ended_room_id != "" and ended_room_id != room_id:
		return

	match_has_ended = true
	remaining_match_seconds = 0.0
	player_body.set_match_controls_enabled(false)
	update_match_ui()

func _on_bullet_spawn_received(message: Dictionary) -> void:
	var player_id := str(message.get("playerId", ""))
	if player_id == "" or player_id == local_player_id:
		return

	var remote_body := _get_remote_player(player_id)
	if remote_body == null:
		remote_body = _get_or_create_remote_player(player_id)
	if remote_body == null:
		return

	var weapon_type := str(message.get("weaponType", message.get("weapon", "")))
	if weapon_type == "":
		weapon_type = remote_body.weapon.get_active_weapon().get_weapon_name() if remote_body.weapon != null and remote_body.weapon.get_active_weapon() != null else ""

	remote_body.spawn_remote_bullet_from_server(
		Vector2(float(message.get("x", remote_body.global_position.x)), float(message.get("y", remote_body.global_position.y))),
		float(message.get("angle", 0.0)),
		weapon_type
	)

func _get_or_create_remote_player(player_id: String) -> Player:
	var existing_remote := _get_remote_player(player_id)
	if existing_remote != null:
		return existing_remote

	var remote_wrapper := PLAYER_SCENE.instantiate() as Node2D
	if remote_wrapper == null:
		return null

	remote_wrapper.name = "RemotePlayer_%s" % player_id
	var remote_body := remote_wrapper.get_node("CharacterBody2D") as Player
	if remote_body == null:
		remote_wrapper.queue_free()
		return null

	remote_body.configure_as_remote_proxy()
	remote_body.set_network_player_id(player_id)
	add_child(remote_wrapper)
	remote_players[player_id] = remote_wrapper
	return remote_body

func _apply_local_player_state(message: Dictionary) -> void:
	if message.is_empty():
		return

	if message.has("x") and message.has("y"):
		player_body.global_position = Vector2(float(message["x"]), float(message["y"]))

	if message.has("health") or message.has("isDead"):
		player_body.apply_authoritative_health_state(
			int(message.get("health", player_body.health)),
			bool(message.get("isDead", player_body.is_dead)),
			int(message.get("damage", 0))
		)

func _get_remote_player(player_id: String) -> Player:
	var existing_wrapper := remote_players.get(player_id) as Node2D
	if existing_wrapper == null or not is_instance_valid(existing_wrapper):
		return null

	return existing_wrapper.get_node("CharacterBody2D") as Player

func _apply_initial_remote_players(message: Dictionary) -> void:
	if message.is_empty():
		return

	var players_variant: Variant = message.get("players", message.get("remotePlayers", []))
	if not (players_variant is Array):
		return

	for player_variant in players_variant:
		if typeof(player_variant) != TYPE_DICTIONARY:
			continue

		_apply_remote_player_state(player_variant)

func _apply_cached_remote_players() -> void:
	if network_client == null:
		return

	for snapshot_variant in network_client.remote_player_snapshots.values():
		if typeof(snapshot_variant) != TYPE_DICTIONARY:
			continue

		_apply_remote_player_state(snapshot_variant)

func _apply_remote_player_state(message: Dictionary) -> void:
	var player_id := str(message.get("playerId", message.get("id", "")))
	if player_id == "" or player_id == local_player_id:
		return

	var remote_body := _get_remote_player(player_id)
	var has_position := message.has("x") and message.has("y")
	if remote_body == null and not has_position:
		return

	if remote_body == null:
		remote_body = _get_or_create_remote_player(player_id)
	if remote_body == null:
		return

	var weapon_type := str(message.get("weaponType", message.get("weaponHolding", message.get("weapon", ""))))
	if weapon_type != "":
		remote_body.set_remote_weapon(weapon_type)

	if message.has("health"):
		remote_body.apply_authoritative_health_state(
			int(message["health"]),
			bool(message.get("isDead", remote_body.is_dead)),
			int(message.get("damage", 0))
		)

	var aim_angle_degrees := NAN
	if message.has("angle"):
		aim_angle_degrees = float(message["angle"])
	elif message.has("rotation"):
		aim_angle_degrees = rad_to_deg(float(message["rotation"]))
	elif message.has("aimAngle"):
		aim_angle_degrees = float(message["aimAngle"])

	if has_position:
		remote_body.enqueue_remote_snapshot(
			Vector2(
				float(message["x"]),
				float(message["y"])
			),
			aim_angle_degrees
		)
	elif not is_nan(aim_angle_degrees):
		remote_body.update_remote_angle(aim_angle_degrees)

func _remove_remote_player(player_id: String) -> void:
	var remote_wrapper := remote_players.get(player_id) as Node2D
	if remote_wrapper == null:
		return

	remote_players.erase(player_id)
	if is_instance_valid(remote_wrapper):
		remote_wrapper.queue_free()
