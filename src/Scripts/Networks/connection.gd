extends Node

const GAME_SCENE: PackedScene = preload("res://src/Scenes/game.tscn")
const PLAYER_SCENE: PackedScene = preload("res://src/Objects/player.tscn")
const LOBBY_URL: String = "https://pixelfight.live/"

@onready var background_map: Node2D = $Map
@onready var background_camera: Camera2D = $BackgroundCamera
@onready var connection_panel: PanelContainer = $CanvasLayer/Overlay/CenterContainer/PanelContainer
@onready var status_label: Label = $CanvasLayer/Overlay/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/StatusLabel
@onready var ready_bar: Control = $CanvasLayer/Overlay/ReadyBar
@onready var join_button: Button = $CanvasLayer/Overlay/ReadyBar/ReadyMargin/ReadyRow/JoinButton
@onready var dashboard_button: Button = $CanvasLayer/Overlay/ReadyBar/ReadyMargin/ReadyRow/DashboardButton
@onready var network_client: NetworkClient = $NetworkClient
@onready var leaderboard_ui: Node = $RoomLeaderboard

var has_started_game: bool = false
var game_instance: Node = null
var is_returning_to_lobby: bool = false
var is_room_ready: bool = false
var local_player_id: String = ""
var preview_remote_players: Dictionary = {}

func _ready() -> void:
	network_client.connection_established.connect(_on_connection_established)
	network_client.connection_failed.connect(_on_connection_failed)
	network_client.connection_lost.connect(_on_connection_lost)
	network_client.room_reserved.connect(_on_room_ready)
	network_client.room_joined.connect(_on_room_ready)
	network_client.time_synced.connect(_on_time_synced)
	network_client.player_move_received.connect(_on_preview_player_move_received)
	network_client.player_angle_received.connect(_on_preview_player_angle_received)
	network_client.player_weapon_switch_received.connect(_on_preview_player_weapon_switch_received)
	network_client.player_health_received.connect(_on_preview_player_health_received)
	network_client.player_left_received.connect(_on_preview_player_left_received)
	network_client.leaderboard_updated.connect(_on_leaderboard_updated)
	network_client.match_left.connect(_on_match_left)
	network_client.match_ended.connect(_on_match_ended)
	join_button.pressed.connect(_on_join_button_pressed)
	dashboard_button.pressed.connect(_on_dashboard_button_pressed)

	_begin_connection_attempt("Connecting to multiplayer server...")

func _begin_connection_attempt(status_text: String) -> void:
	if is_returning_to_lobby:
		return

	# Reset lobby state before trying to join a room again
	is_room_ready = false
	local_player_id = ""
	_clear_preview_remote_players()
	_set_background_visible(true)
	_set_status_text(status_text)
	$CanvasLayer.visible = true
	_set_room_ready_ui_visible(false)
	var error := network_client.connect_to_server()
	if error != OK:
		_set_status_text("Connection failed. Check the server URL and try again.")

func _on_connection_established() -> void:
	if has_started_game:
		return

	_set_status_text("Connected. Reserving a room...")
	_set_room_ready_ui_visible(false)

func _on_room_ready(message: Dictionary) -> void:
	if has_started_game or is_returning_to_lobby:
		return

	# Show the room preview until the player chooses to join the match
	is_room_ready = true
	if network_client.local_player_id != "":
		local_player_id = network_client.local_player_id
	else:
		local_player_id = str(message.get("playerId", message.get("id", "")))

	_set_status_text("Room reserved.")
	_apply_leaderboard_snapshot(message)
	_apply_initial_preview_players(message)
	_apply_cached_preview_players()
	_set_room_ready_ui_visible(true)

func _on_time_synced(message: Dictionary) -> void:
	if has_started_game or is_returning_to_lobby:
		return

	_apply_leaderboard_snapshot(message)

func _on_leaderboard_updated(message: Dictionary) -> void:
	if has_started_game or is_returning_to_lobby:
		return

	_apply_leaderboard_snapshot(message)

func _on_connection_failed() -> void:
	has_started_game = false
	is_room_ready = false
	_set_status_text("Connection failed. Check the server URL and try again.")
	$CanvasLayer.visible = true
	_set_room_ready_ui_visible(false)

func _on_connection_lost(reason: String) -> void:
	if is_returning_to_lobby:
		return

	# Throw away the live match scene before reconnecting to the lobby
	if game_instance != null and is_instance_valid(game_instance):
		game_instance.queue_free()

	game_instance = null
	has_started_game = false
	is_room_ready = false
	local_player_id = ""
	_clear_preview_remote_players()
	_begin_connection_attempt("%s Reconnecting..." % reason)

func _on_match_ended(_message: Dictionary) -> void:
	if has_started_game and game_instance != null and is_instance_valid(game_instance):
		return

	_return_to_lobby(false)

func _on_match_left(_message: Dictionary) -> void:
	_reset_after_match_exit()

func _on_join_button_pressed() -> void:
	if has_started_game or not is_room_ready:
		return

	_start_game()

func _on_dashboard_button_pressed() -> void:
	_return_to_lobby()

func _start_game() -> void:
	has_started_game = true
	_set_status_text("Joining match...")
	_set_room_ready_ui_visible(false)
	_set_background_visible(false)
	_clear_preview_remote_players()

	# Keep the socket alive while swapping from lobby preview to gameplay
	game_instance = GAME_SCENE.instantiate()
	add_child(game_instance)
	$CanvasLayer.visible = false

func _set_room_ready_ui_visible(is_visible: bool) -> void:
	connection_panel.visible = not is_visible
	ready_bar.visible = is_visible
	join_button.disabled = not is_visible
	dashboard_button.disabled = not is_visible
	leaderboard_ui.call("set_leaderboard_visible", is_visible)

func _set_status_text(status_text: String) -> void:
	status_label.text = status_text

func _set_background_visible(is_visible: bool) -> void:
	background_map.visible = is_visible
	background_camera.enabled = is_visible

	for preview_wrapper in preview_remote_players.values():
		var preview_canvas_item := preview_wrapper as CanvasItem
		if preview_canvas_item != null and is_instance_valid(preview_canvas_item):
			preview_canvas_item.visible = is_visible

func _apply_leaderboard_snapshot(message: Dictionary) -> void:
	if message.is_empty():
		return

	var player_id := network_client.local_player_id
	if player_id == "":
		player_id = str(message.get("playerId", message.get("id", "")))

	if player_id != "":
		leaderboard_ui.call("set_local_player_id", player_id)

	var leaderboard_variant: Variant = message.get("leaderboard", [])
	if leaderboard_variant is Array:
		leaderboard_ui.call("apply_server_leaderboard_snapshot", leaderboard_variant)

	_apply_preview_display_names(message)

func _apply_preview_display_names(message: Dictionary) -> void:
	for player_id_variant in preview_remote_players.keys():
		var player_id := str(player_id_variant)
		var player_display_name := network_client.get_player_display_name(message, player_id)
		if player_display_name == "":
			continue

		var remote_body := _get_preview_remote_player(player_id)
		if remote_body != null:
			remote_body.set_network_player_display_name(player_display_name)

func _on_preview_player_move_received(message: Dictionary) -> void:
	if has_started_game or not is_room_ready:
		return

	_apply_preview_remote_player_state(message)

func _on_preview_player_angle_received(message: Dictionary) -> void:
	if has_started_game or not is_room_ready:
		return

	_apply_preview_remote_player_state(message)

func _on_preview_player_weapon_switch_received(message: Dictionary) -> void:
	if has_started_game or not is_room_ready:
		return

	_apply_preview_remote_player_state(message)

func _on_preview_player_health_received(message: Dictionary) -> void:
	if has_started_game or not is_room_ready:
		return

	_apply_preview_remote_player_state(message)

func _on_preview_player_left_received(player_id: String) -> void:
	_remove_preview_remote_player(player_id)

func _apply_initial_preview_players(message: Dictionary) -> void:
	if message.is_empty():
		return

	# Draw already-connected players in the lobby preview
	var players_variant: Variant = message.get("players", message.get("remotePlayers", []))
	if not (players_variant is Array):
		return

	for player_variant in players_variant:
		if typeof(player_variant) != TYPE_DICTIONARY:
			continue

		_apply_preview_remote_player_state(player_variant)

func _apply_cached_preview_players() -> void:
	if network_client == null:
		return

	# Use cached packets that arrived before the room UI was ready
	for snapshot_variant in network_client.remote_player_snapshots.values():
		if typeof(snapshot_variant) != TYPE_DICTIONARY:
			continue

		_apply_preview_remote_player_state(snapshot_variant)

func _apply_preview_remote_player_state(message: Dictionary) -> void:
	var player_id := str(message.get("playerId", message.get("id", "")))
	if player_id == "" or player_id == local_player_id:
		return

	# Do not create preview players until the server gives us a position
	var remote_body := _get_preview_remote_player(player_id)
	var has_position := message.has("x") and message.has("y")
	if remote_body == null and not has_position:
		return

	var remote_display_name := network_client.get_player_display_name(message, player_id)
	if remote_body == null:
		remote_body = _get_or_create_preview_remote_player(player_id, remote_display_name)
	if remote_body == null:
		return

	if remote_display_name != "":
		remote_body.set_network_player_display_name(remote_display_name)

	var was_dead := remote_body.is_dead
	var weapon_type := str(message.get("weaponType", message.get("weaponHolding", message.get("weapon", ""))))
	if weapon_type != "":
		remote_body.set_remote_weapon(weapon_type)

	var authoritative_is_dead := bool(message.get("isDead", remote_body.is_dead))
	if message.has("health") and not message.has("isDead"):
		authoritative_is_dead = int(message["health"]) <= 0
	if message.has("health"):
		remote_body.apply_authoritative_health_state(
			int(message["health"]),
			authoritative_is_dead,
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
		var remote_position := Vector2(float(message["x"]), float(message["y"]))
		var is_respawn_snap := was_dead and not authoritative_is_dead and message.has("health") and int(message["health"]) > 0
		if is_respawn_snap:
			# Respawns should snap so players do not slide from the death spot
			remote_body.snap_remote_snapshot(remote_position, aim_angle_degrees)
		else:
			remote_body.enqueue_remote_snapshot(remote_position, aim_angle_degrees)
	elif not is_nan(aim_angle_degrees):
		remote_body.update_remote_angle(aim_angle_degrees)

func _get_or_create_preview_remote_player(player_id: String, player_display_name: String = "") -> Player:
	var existing_remote := _get_preview_remote_player(player_id)
	if existing_remote != null:
		return existing_remote

	var remote_wrapper := PLAYER_SCENE.instantiate() as Node2D
	if remote_wrapper == null:
		return null

	remote_wrapper.name = "PreviewRemotePlayer_%s" % player_id
	var remote_body := remote_wrapper.get_node("CharacterBody2D") as Player
	if remote_body == null:
		remote_wrapper.queue_free()
		return null

	remote_body.configure_as_remote_proxy()
	remote_body.set_network_player_id(player_id)
	remote_body.set_network_player_display_name(player_display_name)
	add_child(remote_wrapper)
	preview_remote_players[player_id] = remote_wrapper
	return remote_body

func _get_preview_remote_player(player_id: String) -> Player:
	var existing_wrapper := preview_remote_players.get(player_id) as Node2D
	if existing_wrapper == null or not is_instance_valid(existing_wrapper):
		return null

	return existing_wrapper.get_node("CharacterBody2D") as Player

func _remove_preview_remote_player(player_id: String) -> void:
	var remote_wrapper := preview_remote_players.get(player_id) as Node2D
	if remote_wrapper == null:
		return

	preview_remote_players.erase(player_id)
	if is_instance_valid(remote_wrapper):
		remote_wrapper.queue_free()

func _clear_preview_remote_players() -> void:
	for remote_wrapper in preview_remote_players.values():
		var remote_node := remote_wrapper as Node
		if remote_node != null and is_instance_valid(remote_node):
			remote_node.queue_free()

	preview_remote_players.clear()

func _return_to_lobby(should_notify_server: bool = true) -> void:
	if is_returning_to_lobby:
		return

	if should_notify_server:
		network_client.send_leave_match()

	if OS.has_feature("web"):
		_reset_after_match_exit()
		JavaScriptBridge.eval(
			"window.parent.postMessage({ type: 'EXIT_GAME', reason: 'manual' }, '*'); if (window.parent === window) { window.location.href = '%s'; }" % LOBBY_URL,
			false
		)
		return

	# Native builds cannot ask a parent React page to hide the game.
	is_returning_to_lobby = true
	network_client.close_connection()
	is_room_ready = false
	local_player_id = ""
	_set_room_ready_ui_visible(false)
	_clear_preview_remote_players()

	if game_instance != null and is_instance_valid(game_instance):
		game_instance.queue_free()

	game_instance = null
	has_started_game = false
	$CanvasLayer.visible = false

	OS.shell_open(LOBBY_URL)

func _reset_after_match_exit() -> void:
	if game_instance != null and is_instance_valid(game_instance):
		game_instance.queue_free()

	game_instance = null
	has_started_game = false
	is_room_ready = false
	local_player_id = network_client.local_player_id
	_clear_preview_remote_players()
	_set_background_visible(true)
	_set_room_ready_ui_visible(false)
	_set_status_text("Connected.")
	$CanvasLayer.visible = true
