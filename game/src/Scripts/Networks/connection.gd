extends Node

# Lobby/connection controller. It owns the pre-match room preview, starts the
# gameplay scene without closing the socket, and posts exit/results messages to
# the Web dashboard when exported.

const Localization = preload("res://src/Scripts/components/localization.gd")
const GAME_SCENE: PackedScene = preload("res://src/Scenes/game.tscn")
const PLAYER_SCENE: PackedScene = preload("res://src/Objects/player.tscn")
const LOBBY_URL: String = "https://pixelfight.live/"
const LOBBY_LEADERBOARD_REFRESH_SECONDS: float = 3.0
const ROOM_RESERVATION_TIMEOUT_SECONDS: float = 6.0

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
var lobby_leaderboard_refresh_elapsed: float = 0.0
var player_play_time_accumulated_ms: int = 0
var player_play_time_started_msec: int = -1
var player_play_time_room_id: String = ""
var is_waiting_for_room_reservation: bool = false
var room_reservation_wait_elapsed: float = 0.0

func _ready() -> void:
	Localization.apply_url_language()
	network_client.language = Localization.get_language()
	_apply_localized_static_text()
	Localization.apply_active_language_font(self)
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

	_begin_connection_attempt(Localization.translate("connecting_server"))
	leaderboard_ui.call("refresh_localization")

func _process(delta: float) -> void:
	if is_waiting_for_room_reservation and not has_started_game and not is_returning_to_lobby and not is_room_ready:
		room_reservation_wait_elapsed += delta
		if room_reservation_wait_elapsed >= ROOM_RESERVATION_TIMEOUT_SECONDS:
			is_waiting_for_room_reservation = false
			_set_status_text(Localization.translate("player_already_joined"))
			if network_client != null:
				network_client.close_connection()
		return

	if has_started_game or is_returning_to_lobby or not is_room_ready:
		return

	lobby_leaderboard_refresh_elapsed += delta
	if lobby_leaderboard_refresh_elapsed < LOBBY_LEADERBOARD_REFRESH_SECONDS:
		return

	lobby_leaderboard_refresh_elapsed = 0.0
	network_client.request_leaderboard_update()

func _begin_connection_attempt(status_text: String) -> void:
	if is_returning_to_lobby:
		return

	# Reset lobby state before trying to join a room again
	is_room_ready = false
	is_waiting_for_room_reservation = false
	room_reservation_wait_elapsed = 0.0
	local_player_id = ""
	_clear_preview_remote_players()
	_set_background_visible(true)
	_set_status_text(status_text)
	$CanvasLayer.visible = true
	_show_lobby_cursor()
	_set_room_ready_ui_visible(false)
	var error := network_client.connect_to_server()
	if error != OK:
		_set_status_text(Localization.translate("connection_failed"))

func _on_connection_established() -> void:
	if has_started_game:
		return

	_set_status_text(Localization.translate("connected_reserving"))
	_set_room_ready_ui_visible(false)
	is_waiting_for_room_reservation = true
	room_reservation_wait_elapsed = 0.0

func _on_room_ready(message: Dictionary) -> void:
	if has_started_game or is_returning_to_lobby:
		return

	# Show the room preview until the player chooses to join the match
	is_room_ready = true
	is_waiting_for_room_reservation = false
	room_reservation_wait_elapsed = 0.0
	lobby_leaderboard_refresh_elapsed = 0.0
	var assigned_room_id := str(message.get("room_id", network_client.local_room_id)).strip_edges()
	if player_play_time_room_id != "" and assigned_room_id != "" and assigned_room_id != player_play_time_room_id:
		_reset_player_play_timer()
	if player_play_time_room_id == "":
		player_play_time_room_id = assigned_room_id
	if network_client.local_player_id != "":
		local_player_id = network_client.local_player_id
	else:
		local_player_id = str(message.get("player_id", ""))

	_set_status_text(Localization.translate("room_reserved"))
	_apply_leaderboard_snapshot(message)
	network_client.request_leaderboard_update()
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
	is_waiting_for_room_reservation = false
	room_reservation_wait_elapsed = 0.0
	_set_status_text(Localization.translate("connection_failed"))
	$CanvasLayer.visible = true
	_show_lobby_cursor()
	_set_room_ready_ui_visible(false)

func _on_connection_lost(reason: String) -> void:
	if is_returning_to_lobby:
		return

	# Disconnected time is not active play time. Preserve the accumulated
	# value so rejoining the same room resumes the player's clock.
	_pause_player_play_timer()
	# Throw away the live match scene before reconnecting to the lobby
	if game_instance != null and is_instance_valid(game_instance):
		game_instance.queue_free()

	game_instance = null
	has_started_game = false
	is_room_ready = false
	is_waiting_for_room_reservation = false
	room_reservation_wait_elapsed = 0.0
	local_player_id = ""
	_clear_preview_remote_players()
	_begin_connection_attempt(Localization.translate("reconnecting") % reason)

func _on_match_ended(message: Dictionary) -> void:
	_pause_player_play_timer()
	if has_started_game and game_instance != null and is_instance_valid(game_instance):
		return

	_apply_leaderboard_snapshot(message)
	_exit_to_dashboard("match_ended", false)

func _on_match_left(_message: Dictionary) -> void:
	if is_returning_to_lobby:
		return

	_reset_after_match_exit()

func _on_join_button_pressed() -> void:
	if has_started_game or not is_room_ready:
		return

	_start_game()

func _on_dashboard_button_pressed() -> void:
	_return_to_lobby()

func _start_game() -> void:
	_start_player_play_timer()
	has_started_game = true
	_set_status_text(Localization.translate("joining_match"))
	_set_room_ready_ui_visible(false)
	_set_background_visible(false)
	_clear_preview_remote_players()

	# Keep NetworkClient alive across the scene swap; game.gd will reuse cached
	# room/player snapshots that arrived while the lobby preview was visible.
	game_instance = GAME_SCENE.instantiate()
	add_child(game_instance)
	$CanvasLayer.visible = false

func _set_room_ready_ui_visible(is_visible: bool) -> void:
	if is_visible:
		_show_lobby_cursor()

	connection_panel.visible = not is_visible
	ready_bar.visible = is_visible
	join_button.disabled = not is_visible
	dashboard_button.disabled = not is_visible
	leaderboard_ui.call("set_leaderboard_visible", is_visible)

func _show_lobby_cursor() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _set_status_text(status_text: String) -> void:
	status_label.text = status_text
	Localization.apply_readable_text_font(status_label, status_text)

func _apply_localized_static_text() -> void:
	var title_label := $CanvasLayer/Overlay/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/TitleLabel as Label
	if title_label != null:
		title_label.text = Localization.translate("connection_title")
		Localization.apply_readable_text_font(title_label, title_label.text)
	status_label.text = Localization.translate("connecting")
	Localization.apply_readable_text_font(status_label, status_label.text)
	join_button.text = Localization.translate("join")
	Localization.apply_readable_text_font(join_button, join_button.text)
	dashboard_button.text = Localization.translate("dashboard")
	Localization.apply_readable_text_font(dashboard_button, dashboard_button.text)

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
		player_id = str(message.get("player_id", ""))

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
	var players_variant: Variant = message.get("players", message.get("remote_players", []))
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
	var player_id := str(message.get("player_id", ""))
	if player_id == "" or player_id == local_player_id:
		return

	# Preview remote players use the same proxy smoothing as the match scene, but
	# do not create them until the server gives us a position.
	var remote_body := _get_preview_remote_player(player_id)
	var has_position := NetworkClient.has_finite_vector2(message, "x", "y")
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
	var weapon_type := NetworkClient.get_authoritative_remote_weapon_type(message)
	if weapon_type != "":
		remote_body.set_remote_weapon(weapon_type)

	var has_health := NetworkClient.has_authoritative_health(message)
	var new_health := remote_body.health
	var is_respawn_state := NetworkClient.is_respawn_state(message)
	var authoritative_is_dead := bool(message.get("is_dead", false if is_respawn_state else remote_body.is_dead))
	if has_health:
		new_health = NetworkClient.get_authoritative_health(message, remote_body.health)
	elif is_respawn_state:
		new_health = remote_body.max_health
	if has_health and not message.has("is_dead"):
		authoritative_is_dead = new_health <= 0
	if has_health or message.has("is_dead") or is_respawn_state:
		remote_body.apply_authoritative_health_state(
			new_health,
			authoritative_is_dead,
			NetworkClient.get_finite_int(message.get("damage", 0), 0),
			NetworkClient.get_health_heal_amount(message, remote_body.health, new_health),
			"medkit" if NetworkClient.is_medkit_heal(message) else NetworkClient.get_health_source(message)
		)

	var aim_angle_degrees := NAN
	if message.has("aim_frame") and NetworkClient.is_valid_aim_frame(message["aim_frame"]):
		aim_angle_degrees = float(int(message["aim_frame"])) * 45.0
	elif message.has("angle"):
		aim_angle_degrees = NetworkClient.get_finite_float(message["angle"], NAN)
	elif message.has("rotation"):
		aim_angle_degrees = rad_to_deg(NetworkClient.get_finite_float(message["rotation"], 0.0))
	elif message.has("aim_angle"):
		aim_angle_degrees = NetworkClient.get_finite_float(message["aim_angle"], NAN)

	if has_position:
		var remote_position := NetworkClient.get_finite_vector2(message, "x", "y")
		var is_respawn_snap := was_dead and not authoritative_is_dead and (has_health or is_respawn_state) and new_health > 0
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

	remote_wrapper.name = "PreviewRemotePlayer_%s" % player_id.validate_node_name()
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
	_exit_to_dashboard("manual", should_notify_server)

func _exit_to_dashboard(reason: String, should_notify_server: bool = true) -> void:
	if is_returning_to_lobby:
		return

	is_returning_to_lobby = true
	var play_time_ms := get_player_play_time_ms()
	var player_stats := _get_local_player_stats()
	var exit_room_id := network_client.local_room_id
	var exit_player_id := local_player_id if local_player_id != "" else network_client.local_player_id
	if should_notify_server and _is_in_room():
		network_client.send_leave_match()
		network_client.clear_match_state()

	_reset_after_match_exit()

	if OS.has_feature("web"):
		# Same parent-message contract as game.gd, used when leaving from lobby
		# or before the gameplay scene has taken over.
		var payload := {
			"type": "EXIT_GAME",
			"reason": reason
		}
		if play_time_ms > 0:
			payload["room_id"] = exit_room_id
			payload["player_id"] = exit_player_id
			payload["kills"] = int(player_stats.get("kills", 0))
			payload["deaths"] = int(player_stats.get("deaths", 0))
			payload["death"] = int(player_stats.get("deaths", 0))
			payload["score"] = int(player_stats.get("score", 0))
			payload["play_time_ms"] = play_time_ms
			payload["play_time_seconds"] = float(play_time_ms) / 1000.0
			payload["match_summary"] = {
				"room_id": exit_room_id,
				"player_id": exit_player_id,
				"kills": int(player_stats.get("kills", 0)),
				"deaths": int(player_stats.get("deaths", 0)),
				"death": int(player_stats.get("deaths", 0)),
				"score": int(player_stats.get("score", 0)),
				"play_time_ms": play_time_ms,
				"play_time_seconds": float(play_time_ms) / 1000.0
			}
		JavaScriptBridge.eval(
			"window.parent.postMessage(%s, window.location.origin); if (window.parent === window) { window.location.href = '%s'; }" % [JSON.stringify(payload), LOBBY_URL],
			false
		)
		return

	OS.shell_open(LOBBY_URL)

func _is_in_room() -> bool:
	return network_client != null and network_client.is_in_room()

func _get_local_player_stats() -> Dictionary:
	if leaderboard_ui == null:
		return {"kills": 0, "deaths": 0, "score": 0}

	var target_player_id := local_player_id if local_player_id != "" else network_client.local_player_id
	var entry_variant: Variant = leaderboard_ui.call("get_entry_for_player", target_player_id)
	if typeof(entry_variant) != TYPE_DICTIONARY:
		return {"kills": 0, "deaths": 0, "score": 0}

	var entry := entry_variant as Dictionary
	return {
		"kills": int(entry.get("kills", 0)),
		"deaths": int(entry.get("deaths", 0)),
		"score": int(entry.get("score", 0))
	}

func _reset_after_match_exit() -> void:
	if game_instance != null and is_instance_valid(game_instance):
		game_instance.queue_free()

	game_instance = null
	has_started_game = false
	_reset_player_play_timer()
	is_room_ready = false
	is_waiting_for_room_reservation = false
	room_reservation_wait_elapsed = 0.0
	is_returning_to_lobby = false
	local_player_id = network_client.local_player_id
	_clear_preview_remote_players()
	_set_background_visible(true)
	_set_room_ready_ui_visible(false)
	_set_status_text(Localization.translate("connected"))
	$CanvasLayer.visible = true
	_show_lobby_cursor()

	if network_client != null:
		network_client.request_room_reservation()

func get_player_play_time_ms() -> int:
	var elapsed_ms := player_play_time_accumulated_ms
	if player_play_time_started_msec >= 0:
		elapsed_ms += maxi(Time.get_ticks_msec() - player_play_time_started_msec, 0)
	return maxi(elapsed_ms, 0)

func get_player_play_time_seconds() -> float:
	return float(get_player_play_time_ms()) / 1000.0

func _start_player_play_timer() -> void:
	if player_play_time_started_msec >= 0:
		return

	if player_play_time_room_id == "":
		player_play_time_room_id = network_client.local_room_id.strip_edges()
	player_play_time_started_msec = Time.get_ticks_msec()

func _pause_player_play_timer() -> void:
	if player_play_time_started_msec < 0:
		return

	player_play_time_accumulated_ms += maxi(Time.get_ticks_msec() - player_play_time_started_msec, 0)
	player_play_time_started_msec = -1

func _reset_player_play_timer() -> void:
	player_play_time_accumulated_ms = 0
	player_play_time_started_msec = -1
	player_play_time_room_id = ""
