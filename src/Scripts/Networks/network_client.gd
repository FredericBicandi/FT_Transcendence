class_name NetworkClient
extends Node

signal connection_established
signal connection_failed
signal connection_lost(reason: String)
signal room_joined(message: Dictionary)
signal time_synced(message: Dictionary)
signal player_move_received(message: Dictionary)
signal player_angle_received(message: Dictionary)
signal player_weapon_switch_received(message: Dictionary)
signal player_health_received(message: Dictionary)
signal bullet_spawn_received(message: Dictionary)
signal player_left_received(player_id: String)
signal match_ended(message: Dictionary)

# Keep the server endpoint editable from the scene inspector.

@export var server_url: String = "wss://34.165.50.106:5000/ws"
@export var bypass_tls_validation: bool = true
@export var connection_timeout_seconds: float = 30.0

var socket: WebSocketPeer = WebSocketPeer.new()
var was_open_last_frame: bool = false
var has_reported_closed_state: bool = false
var has_connected_once: bool = false
var has_reported_connection_loss: bool = false
var local_player_id: String = ""
var local_room_id: String = ""
var match_duration_seconds: int = 0
var remaining_seconds: float = 0.0
var match_finished: bool = false
var last_room_joined_message: Dictionary = {}
var remote_player_snapshots: Dictionary = {}
var seconds_since_last_server_activity: float = 0.0
var is_connection_closed_manually: bool = false

func _ready() -> void:
	# Register in a group so gameplay code can find the client without relying on a fixed node path.
	add_to_group("network_client")

func _process(delta: float) -> void:
	var state := socket.get_ready_state()

	if state == WebSocketPeer.STATE_CONNECTING or state == WebSocketPeer.STATE_OPEN:
		socket.poll()
		state = socket.get_ready_state()

	_handle_state_changes(state)

	if state != WebSocketPeer.STATE_OPEN:
		return

	seconds_since_last_server_activity += delta
	if connection_timeout_seconds > 0.0 and seconds_since_last_server_activity >= connection_timeout_seconds:
		_handle_connection_loss("Connection timed out.")
		return

	_read_packets()

func connect_to_server() -> Error:
	# Reset transient connection state before opening a fresh socket connection.
	socket = WebSocketPeer.new()
	was_open_last_frame = false
	has_reported_closed_state = false
	has_connected_once = false
	has_reported_connection_loss = false
	local_player_id = ""
	local_room_id = ""
	match_duration_seconds = 0
	remaining_seconds = 0.0
	match_finished = false
	last_room_joined_message = {}
	remote_player_snapshots.clear()
	seconds_since_last_server_activity = 0.0
	is_connection_closed_manually = false

	var error := socket.connect_to_url(server_url, _create_tls_options())
	if error != OK:
		push_error("NetworkClient: failed to connect to %s (error %d)" % [server_url, error])
		connection_failed.emit()

	return error

func _create_tls_options() -> TLSOptions:
	if not server_url.begins_with("wss://"):
		return null

	if bypass_tls_validation:
		# Skip certificate and hostname verification for development servers using self-signed certs.
		return TLSOptions.client_unsafe()

	return TLSOptions.client()

func send_move(x: float, y: float, angle: float) -> void:
	if socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return

	_send_json(
		{
			"type": "move",
			"x": x,
			"y": y,
			"angle": angle
		}
	)

func send_idle(x: float, y: float, angle: float) -> void:
	if socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return

	_send_json(
		{
			"type": "idle",
			"x": x,
			"y": y,
			"angle": angle
		}
	)

func send_angle(angle: float) -> void:
	if socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return

	_send_json(
		{
			"type": "angle",
			"angle": angle
		}
	)

func send_on_connect(x: float, y: float, angle: float, weapon_type: String) -> void:
	if socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return

	_send_json(
		{
			"type": "on_connect",
			"x": x,
			"y": y,
			"angle": angle,
			"weaponType": weapon_type
		}
	)

func send_respawn(x: float, y: float, angle: float, weapon_type: String) -> void:
	if socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return

	_send_json(
		{
			"type": "respawn",
			"x": x,
			"y": y,
			"angle": angle,
			"weaponType": weapon_type
		}
	)

func send_hit(target_player_id: String, weapon_type: String, damage: int, shot_id: String, x: float, y: float, angle: float, timestamp: int) -> void:
	if socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return

	_send_json(
		{
			"type": "hit",
			"targetPlayerId": target_player_id,
			"weaponType": weapon_type,
			"damage": damage,
			"shotId": shot_id,
			"x": x,
			"y": y,
			"angle": angle,
			"timestamp": timestamp
		}
	)

func send_weapon_switch(weapon_type: String) -> void:
	if socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return

	_send_json(
		{
			"type": "weapon_switch",
			"weaponType": weapon_type
		}
	)

func send_shoot(angle: float) -> void:
	if socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return

	_send_json(
		{
			"type": "shoot",
			"angle": angle
		}
	)

func _handle_state_changes(state: int) -> void:
	if state == WebSocketPeer.STATE_OPEN and not was_open_last_frame:
		was_open_last_frame = true
		has_connected_once = true
		has_reported_closed_state = false
		has_reported_connection_loss = false
		seconds_since_last_server_activity = 0.0
		connection_established.emit()
		return

	if state != WebSocketPeer.STATE_OPEN:
		was_open_last_frame = false

		if state == WebSocketPeer.STATE_CLOSED and not has_reported_closed_state:
			has_reported_closed_state = true

			if is_connection_closed_manually:
				return

			if not has_connected_once:
				connection_failed.emit()
			else:
				_handle_connection_loss("Connection closed.")

func _read_packets() -> void:
	while socket.get_available_packet_count() > 0:
		var packet := socket.get_packet()
		var text := packet.get_string_from_utf8()
		var parsed: Variant = JSON.parse_string(text)
		seconds_since_last_server_activity = 0.0

		# Ignore invalid or unexpected payloads so a bad packet never breaks the client loop.
		if typeof(parsed) != TYPE_DICTIONARY:
			push_warning("NetworkClient: ignored invalid JSON packet: %s" % text)
			continue

		_handle_message(parsed)

func _handle_message(message: Dictionary) -> void:
	var message_type := str(message.get("type", ""))

	match message_type:
		"pong":
			pass
		"player_connected":
			_store_remote_player_snapshot(message)
			player_move_received.emit(message)
		"player_move":
			_store_remote_player_snapshot(message)
			player_move_received.emit(message)
		"player_angle":
			_store_remote_player_snapshot(message)
			player_angle_received.emit(message)
		"player_weapon_switch":
			_store_remote_player_snapshot(message)
			player_weapon_switch_received.emit(message)
		"player_health":
			_store_remote_player_snapshot(message)
			player_health_received.emit(message)
		"player_heartbeat":
			_store_remote_player_snapshot(message)
			player_health_received.emit(message)
		"bullet_spawn":
			bullet_spawn_received.emit(message)
		"player_left":
			var left_player_id := str(message.get("playerId", message.get("id", "")))
			remote_player_snapshots.erase(left_player_id)
			player_left_received.emit(left_player_id)
		"room_joined":
			local_player_id = str(message.get("playerId", ""))
			local_room_id = str(message.get("roomId", ""))
			match_duration_seconds = int(message.get("durationSeconds", 0))
			remaining_seconds = float(message.get("remainingSeconds", match_duration_seconds))
			match_finished = false
			last_room_joined_message = message.duplicate(true)
			room_joined.emit(message)
		"time_sync":
			remaining_seconds = float(message.get("remainingSeconds", remaining_seconds))
			time_synced.emit(message)
		"match_ended":
			match_finished = true
			remaining_seconds = 0.0
			match_ended.emit(message)
		_:
			pass

func _send_json(payload: Dictionary) -> void:
	var data := JSON.stringify(payload)
	var error := socket.send_text(data)
	if error != OK:
		push_warning("NetworkClient: failed to send packet (error %d)" % error)

func _store_remote_player_snapshot(message: Dictionary) -> void:
	var player_id := str(message.get("playerId", message.get("id", "")))
	if player_id == "":
		return

	var existing_snapshot_variant: Variant = remote_player_snapshots.get(player_id, {})
	var existing_snapshot: Dictionary = {}
	if typeof(existing_snapshot_variant) == TYPE_DICTIONARY:
		existing_snapshot = existing_snapshot_variant as Dictionary

	var merged_snapshot: Dictionary = existing_snapshot.duplicate(true)
	for key_variant in message.keys():
		merged_snapshot[key_variant] = message[key_variant]

	remote_player_snapshots[player_id] = merged_snapshot

func _handle_connection_loss(reason: String) -> void:
	if has_reported_connection_loss:
		return

	has_reported_connection_loss = true
	has_reported_closed_state = true
	was_open_last_frame = false
	socket.close()
	connection_lost.emit(reason)

func close_connection() -> void:
	is_connection_closed_manually = true
	has_reported_connection_loss = true
	has_reported_closed_state = true
	was_open_last_frame = false
	has_connected_once = false
	if socket.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		socket.close()
