class_name NetworkClient
extends Node

const Localization = preload("res://src/Scripts/components/localization.gd")

signal connection_established
signal connection_failed
signal connection_lost(reason: String)
signal room_reserved(message: Dictionary)
signal room_joined(message: Dictionary)
signal time_synced(message: Dictionary)
signal player_move_received(message: Dictionary)
signal player_angle_received(message: Dictionary)
signal player_weapon_switch_received(message: Dictionary)
signal player_health_received(message: Dictionary)
signal bullet_spawn_received(message: Dictionary)
signal player_left_received(player_id: String)
signal leaderboard_updated(message: Dictionary)
signal match_left(message: Dictionary)
signal kill_feed_received(message: Dictionary)
signal chat_message_received(message: Dictionary)
signal match_ended(message: Dictionary)

const MAX_LOG_PACKET_CHARS := 240

# Keep the server endpoint editable from the inspector
@export var server_url: String = "wss://pixelfight.live/ws"
@export var bypass_tls_validation: bool = false
@export var connection_timeout_seconds: float = 30.0
@export var max_packets_per_frame: int = 128
@export var max_packet_bytes: int = 65536
@export var player_id: String = ""
@export var player_name: String = "Player"
@export var player_level: int = 1
@export var current_xp: int = 0
@export var language: String = "english"

var socket: WebSocketPeer = WebSocketPeer.new()
var was_open_last_frame: bool = false
var has_reported_closed_state: bool = false
var has_connected_once: bool = false
var has_reported_connection_loss: bool = false
var has_sent_room_reservation_request: bool = false
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
	# Let gameplay scenes find the websocket client without a hard path
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
		# Drop silent sockets so the lobby can reconnect
		_handle_connection_loss("Connection timed out.")
		return

	_read_packets()

func connect_to_server() -> Error:
	_prepare_player_profile()

	# Reset connection state before opening a new socket. Close the previous
	# peer first so a half-open socket from a prior attempt does not linger
	# in the engine's internal poll list.
	if socket != null and socket.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		socket.close()
	socket = WebSocketPeer.new()
	was_open_last_frame = false
	has_reported_closed_state = false
	has_connected_once = false
	has_reported_connection_loss = false
	has_sent_room_reservation_request = false
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
		# Allow local test servers with self-signed certs
		return TLSOptions.client_unsafe()

	return TLSOptions.client()

func send_move(x: float, y: float, angle: float) -> void:
	if socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	if not are_finite_numbers([x, y, angle]):
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
	if not are_finite_numbers([x, y, angle]):
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
	if not is_finite_number(angle):
		return

	_send_json(
		{
			"type": "angle",
			"angle": angle
		}
	)

func send_on_connect() -> void:
	if socket.get_ready_state() != WebSocketPeer.STATE_OPEN or has_sent_room_reservation_request:
		return

	_prepare_player_profile()
	_send_json(
		{
			"type": "on_connect",
			"playerId": player_id,
			"playerName": player_name,
			"level": player_level,
			"currentXp": current_xp,
			"language": language
		}
	)
	has_sent_room_reservation_request = true

func request_room_reservation() -> void:
	if socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return

	has_sent_room_reservation_request = false
	send_on_connect()

func send_on_join(x: float, y: float, angle: float, weapon_type: String) -> void:
	if socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	if not are_finite_numbers([x, y, angle]):
		return

	_send_json(
		{
			"type": "on_join",
			"x": x,
			"y": y,
			"angle": angle,
			"weaponType": weapon_type
		}
	)

func send_respawn(x: float, y: float, angle: float, weapon_type: String) -> void:
	if socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	if not are_finite_numbers([x, y, angle]):
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

func send_health_update(health: int, is_dead: bool, x: float, y: float, angle: float, weapon_type: String, heal_amount: int = 0, source: String = "") -> void:
	if socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	if not are_finite_numbers([x, y, angle]):
		return

	var clamped_health := maxi(health, 0)
	var clamped_heal_amount := maxi(heal_amount, 0)
	var normalized_source := source.strip_edges()
	var health_state := {
		"health": clamped_health,
		"newHealth": clamped_health,
		"currentHealth": clamped_health,
		"playerHealth": clamped_health,
		"isDead": is_dead,
		"x": x,
		"y": y,
		"angle": angle,
		"weaponType": weapon_type
	}

	if clamped_heal_amount > 0:
		health_state["amount"] = clamped_heal_amount
		health_state["healAmount"] = clamped_heal_amount
	if normalized_source != "":
		health_state["source"] = normalized_source

	var payload := health_state.duplicate()
	payload["type"] = "heal"
	payload["request"] = "medkit_heal" if normalized_source == "medkit" else "health_update"
	_apply_local_packet_identity(payload)
	_send_json(payload)

	var compatibility_payload := health_state.duplicate()
	compatibility_payload["type"] = "player_health"
	compatibility_payload["request"] = "health_update"
	_apply_local_packet_identity(compatibility_payload)
	_send_json(compatibility_payload)

func _apply_local_packet_identity(payload: Dictionary) -> void:
	if local_player_id != "":
		payload["playerId"] = local_player_id
	elif player_id != "":
		payload["playerId"] = player_id

	if local_room_id != "":
		payload["roomId"] = local_room_id
		payload["room_id"] = local_room_id

func send_hit(target_player_id: String, weapon_type: String, damage: int, shot_id: String, x: float, y: float, angle: float, timestamp: int) -> void:
	if socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	if target_player_id.strip_edges() == "" or damage <= 0:
		return
	if not are_finite_numbers([x, y, angle]):
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

func send_shoot(angle: float, weapon_type: String, shooter_position: Vector2, start_position: Vector2, target_position: Vector2) -> void:
	if socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	if not are_finite_numbers([angle, shooter_position.x, shooter_position.y, start_position.x, start_position.y, target_position.x, target_position.y]):
		return

	var payload := {
		"type": "shoot",
		"angle": angle,
		"weaponType": weapon_type,
		"x": shooter_position.x,
		"y": shooter_position.y,
		"startX": start_position.x,
		"startY": start_position.y,
		"targetX": target_position.x,
		"targetY": target_position.y
	}

	_send_json(payload)

func send_leave_match() -> void:
	if socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return

	var payload := {
		"type": "leave_match"
	}

	if local_player_id != "":
		payload["playerId"] = local_player_id
	elif player_id != "":
		payload["playerId"] = player_id

	if local_room_id != "":
		payload["roomId"] = local_room_id
		payload["room_id"] = local_room_id

	_send_json(payload)

func request_leaderboard_update() -> void:
	if socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	if local_room_id.strip_edges() == "":
		return

	var payload := {
		"type": "leaderboard_request",
		"roomId": local_room_id,
		"room_id": local_room_id
	}

	if local_player_id != "":
		payload["playerId"] = local_player_id
	elif player_id != "":
		payload["playerId"] = player_id

	_send_json(payload)

func send_chat_message(content: String) -> void:
	if socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return

	var clean_content: String = content.strip_edges()
	if clean_content == "":
		return

	var payload := {
		"request": "message",
		"playerId": local_player_id if local_player_id != "" else player_id,
		"playerName": player_name,
		"content": clean_content,
		"timestamp": Time.get_ticks_msec()
	}

	if local_room_id != "":
		payload["roomId"] = local_room_id
		payload["room_id"] = local_room_id

	_send_json(payload)

func _handle_state_changes(state: int) -> void:
	if state == WebSocketPeer.STATE_OPEN and not was_open_last_frame:
		was_open_last_frame = true
		has_connected_once = true
		has_reported_closed_state = false
		has_reported_connection_loss = false
		seconds_since_last_server_activity = 0.0
		send_on_connect()
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
	var packets_processed := 0
	var packet_limit := maxi(max_packets_per_frame, 1)

	while socket.get_available_packet_count() > 0 and packets_processed < packet_limit:
		packets_processed += 1
		var packet := socket.get_packet()
		if max_packet_bytes > 0 and packet.size() > max_packet_bytes:
			seconds_since_last_server_activity = 0.0
			push_warning("NetworkClient: ignored oversized packet (%d bytes)." % packet.size())
			continue

		var text := packet.get_string_from_utf8()
		var parsed: Variant = JSON.parse_string(text)
		seconds_since_last_server_activity = 0.0

		# Ignore bad packets so one server message cannot break the client
		if typeof(parsed) != TYPE_DICTIONARY:
			push_warning("NetworkClient: ignored invalid JSON packet: %s" % _truncate_packet_for_log(text))
			continue

		_handle_message(parsed)

func _handle_message(message: Dictionary) -> void:
	_sanitize_incoming_message(message)
	var message_type := str(message.get("type", ""))
	var request_type := str(message.get("request", ""))

	if request_type == "message" or message_type == "message" or message_type == "chat_message":
		chat_message_received.emit(message)
		return

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
			if message.has("leaderboard"):
				leaderboard_updated.emit(message)
		"leaderboard_update":
			leaderboard_updated.emit(message)
		"match_left":
			_apply_match_left(message)
			match_left.emit(message)
		"kill_feed":
			kill_feed_received.emit(message)
		"room_reserved":
			_apply_room_assignment(message)
			room_reserved.emit(message)
		"room_joined":
			_apply_room_assignment(message)
			room_joined.emit(message)
		"time_sync":
			var had_remaining_seconds := message.has("remainingSeconds")
			remaining_seconds = get_finite_float(message.get("remainingSeconds", remaining_seconds), remaining_seconds)
			time_synced.emit(message)
			if had_remaining_seconds and remaining_seconds <= 0.0:
				match_finished = true
				match_ended.emit(message)
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

static func get_finite_float(value: Variant, fallback: float = NAN) -> float:
	var result := fallback

	match typeof(value):
		TYPE_FLOAT, TYPE_INT:
			result = float(value)
		TYPE_STRING:
			var text := str(value).strip_edges()
			if not text.is_valid_float():
				return fallback
			result = text.to_float()
		_:
			return fallback

	if is_nan(result) or is_inf(result):
		return fallback

	return result

static func get_finite_int(value: Variant, fallback: int = 0) -> int:
	var result := get_finite_float(value, NAN)
	if is_nan(result):
		return fallback

	return int(result)

static func is_finite_number(value: Variant) -> bool:
	return not is_nan(get_finite_float(value, NAN))

static func are_finite_numbers(values: Array) -> bool:
	for value in values:
		if not is_finite_number(value):
			return false

	return true

static func has_finite_vector2(message: Dictionary, x_key: String, y_key: String) -> bool:
	return message.has(x_key) and message.has(y_key) and is_finite_number(message[x_key]) and is_finite_number(message[y_key])

static func get_finite_vector2(message: Dictionary, x_key: String, y_key: String, fallback: Vector2 = Vector2.ZERO) -> Vector2:
	if not has_finite_vector2(message, x_key, y_key):
		return fallback

	return Vector2(get_finite_float(message[x_key], fallback.x), get_finite_float(message[y_key], fallback.y))

static func get_first_finite_float(message: Dictionary, keys: Array[String], fallback: float = NAN) -> float:
	for key in keys:
		if not message.has(key):
			continue

		var value := get_finite_float(message[key], NAN)
		if not is_nan(value):
			return value

	return fallback

static func get_authoritative_remote_weapon_type(message: Dictionary) -> String:
	var message_type := str(message.get("type", ""))
	var weapon_keys: Array[String] = []

	match message_type:
		"player_health":
			# Health packets often describe the attacker weapon. Only accept
			# fields that explicitly name the damaged player's equipped weapon.
			weapon_keys = ["targetWeapon", "targetWeaponType", "target_weapon", "target_weapon_type", "targetCurrentWeapon"]
		"player_weapon_switch", "player_connected", "player_move", "player_heartbeat", "":
			weapon_keys = ["weaponType", "weapon", "weapon_type", "weaponId", "weapon_id", "weaponHolding", "currentWeapon", "equippedWeapon", "activeWeapon"]
		_:
			weapon_keys = ["targetWeapon", "targetWeaponType", "target_weapon", "target_weapon_type", "targetCurrentWeapon"]

	for key in weapon_keys:
		if not message.has(key):
			continue

		var weapon_type := str(message[key]).strip_edges()
		if weapon_type != "":
			return weapon_type

	return ""

func _sanitize_incoming_message(message: Dictionary) -> void:
	for pair_variant in [
		["x", "y"],
		["startX", "startY"],
		["muzzleX", "muzzleY"],
		["bulletX", "bulletY"],
		["targetX", "targetY"],
		["target_x", "target_y"]
	]:
		_sanitize_numeric_pair(message, str(pair_variant[0]), str(pair_variant[1]))

	for field in ["angle", "rotation", "aimAngle", "health", "damage", "remainingSeconds", "durationSeconds", "timestamp", "level"]:
		_sanitize_numeric_field(message, field)

	for vector_key in ["start", "muzzle", "target"]:
		_sanitize_vector_dictionary(message, vector_key)

func _sanitize_numeric_pair(message: Dictionary, x_key: String, y_key: String) -> void:
	var has_x := message.has(x_key)
	var has_y := message.has(y_key)
	if not has_x and not has_y:
		return

	if has_x and has_y and is_finite_number(message[x_key]) and is_finite_number(message[y_key]):
		return

	message.erase(x_key)
	message.erase(y_key)

func _sanitize_numeric_field(message: Dictionary, key: String) -> void:
	if message.has(key) and not is_finite_number(message[key]):
		message.erase(key)

func _sanitize_vector_dictionary(message: Dictionary, key: String) -> void:
	if not message.has(key):
		return

	var vector_variant: Variant = message[key]
	if typeof(vector_variant) != TYPE_DICTIONARY:
		message.erase(key)
		return

	var vector := vector_variant as Dictionary
	if not has_finite_vector2(vector, "x", "y"):
		message.erase(key)

func _truncate_packet_for_log(text: String) -> String:
	if text.length() <= MAX_LOG_PACKET_CHARS:
		return text

	return "%s..." % text.substr(0, MAX_LOG_PACKET_CHARS)

func _prepare_player_profile() -> void:
	_apply_web_player_profile_overrides()

	player_id = player_id.strip_edges()
	player_name = player_name.strip_edges()
	player_level = maxi(player_level, 1)
	current_xp = maxi(current_xp, 0)
	language = Localization.normalize_language(language)
	Localization.set_language(language)

	if player_id == "":
		player_id = _generate_fallback_player_id()
	if player_name == "":
		player_name = "Player"

func get_local_player_display_name(message: Dictionary) -> String:
	var display_name := get_player_display_name(
		message,
		local_player_id if local_player_id != "" else player_id,
		player_name
	)
	return display_name if display_name != "" else "Player"

func get_player_display_name(message: Dictionary, target_player_id: String, fallback: String = "") -> String:
	var normalized_player_id := target_player_id.strip_edges()
	var fallback_name := fallback.strip_edges()

	if not message.is_empty():
		var direct_player_id := _extract_player_id(message)
		var direct_name := _extract_player_display_name(message, direct_player_id != "")
		if direct_name != "" and (normalized_player_id == "" or direct_player_id == normalized_player_id):
			return direct_name

		for collection_key in ["players", "remotePlayers", "leaderboard"]:
			var collection_variant: Variant = message.get(collection_key, [])
			if not (collection_variant is Array):
				continue

			for entry_variant in collection_variant:
				if typeof(entry_variant) != TYPE_DICTIONARY:
					continue

				var entry := entry_variant as Dictionary
				if _extract_player_id(entry) != normalized_player_id:
					continue

				var entry_name := _extract_player_display_name(entry)
				if entry_name != "":
					return entry_name

	if normalized_player_id != "":
		var snapshot_variant: Variant = remote_player_snapshots.get(normalized_player_id, {})
		if typeof(snapshot_variant) == TYPE_DICTIONARY:
			var snapshot := snapshot_variant as Dictionary
			var snapshot_name := _extract_player_display_name(snapshot)
			if snapshot_name != "":
				return snapshot_name

	return fallback_name

func _extract_player_id(message: Dictionary) -> String:
	for key in ["playerId", "player_id", "userId", "user_id", "id"]:
		if not message.has(key):
			continue

		var value := str(message[key]).strip_edges()
		if value != "":
			return value

	return ""

func _extract_player_display_name(message: Dictionary, include_generic_name_fields: bool = true) -> String:
	var keys: Array[String] = ["playerName", "player_name", "displayName", "display_name"]
	if include_generic_name_fields:
		keys.append_array(["username", "name", "nickname"])

	for key in keys:
		if not message.has(key):
			continue

		var value := str(message[key]).strip_edges()
		if value != "":
			return value

	return ""

func _apply_web_player_profile_overrides() -> void:
	if not OS.has_feature("web"):
		return

	player_id = get_url_param("playerId", player_id)
	player_name = get_url_param("playerName", player_name)
	player_level = int(get_url_param("level", str(player_level)))
	current_xp = int(get_url_param("currentXp", str(current_xp)))
	language = get_url_param("language", language)
	Localization.set_language(language)

func get_url_param(param_name: String, fallback: String = "") -> String:
	if not OS.has_feature("web"):
		return fallback

	var js_code: String = """
		new URLSearchParams(window.location.search).get("%s") || "%s"
	""" % [_escape_js_string(param_name), _escape_js_string(fallback)]

	var value: Variant = JavaScriptBridge.eval(js_code, true)
	return str(value) if value != null else fallback

func _escape_js_string(value: String) -> String:
	return value.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n").replace("\r", "\\r")

func _generate_fallback_player_id() -> String:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return "client-%d-%d" % [int(Time.get_unix_time_from_system()), rng.randi()]

func _apply_room_assignment(message: Dictionary) -> void:
	var assigned_player_id := _extract_player_id(message)
	local_player_id = assigned_player_id if assigned_player_id != "" else player_id
	local_room_id = str(message.get("roomId", message.get("room_id", local_room_id)))
	match_duration_seconds = get_finite_int(message.get("durationSeconds", match_duration_seconds), match_duration_seconds)
	remaining_seconds = get_finite_float(message.get("remainingSeconds", remaining_seconds if remaining_seconds > 0.0 else match_duration_seconds), remaining_seconds)
	match_finished = false
	last_room_joined_message = message.duplicate(true)

	if local_player_id != "":
		player_id = local_player_id

	player_name = get_local_player_display_name(message)

func _apply_match_left(message: Dictionary) -> void:
	var left_player_id := _extract_player_id(message)
	if left_player_id != "" and local_player_id != "" and left_player_id != local_player_id:
		return

	var left_room_id := str(message.get("roomId", message.get("room_id", "")))
	if left_room_id != "" and local_room_id != "" and left_room_id != local_room_id:
		return

	clear_match_state()

func is_in_room() -> bool:
	return local_room_id.strip_edges() != ""

func clear_match_state() -> void:
	local_room_id = ""
	match_duration_seconds = 0
	remaining_seconds = 0.0
	match_finished = false
	last_room_joined_message = {}
	remote_player_snapshots.clear()

func _store_remote_player_snapshot(message: Dictionary) -> void:
	var player_id := _extract_player_id(message)
	if player_id == "":
		return

	# Merge partial updates so new scenes can rebuild remote players later
	var existing_snapshot_variant: Variant = remote_player_snapshots.get(player_id, {})
	var existing_snapshot: Dictionary = {}
	if typeof(existing_snapshot_variant) == TYPE_DICTIONARY:
		existing_snapshot = existing_snapshot_variant as Dictionary

	var merged_snapshot: Dictionary = existing_snapshot.duplicate(true)
	for key_variant in message.keys():
		var key := str(key_variant)
		if key == "type":
			continue
		if str(message.get("type", "")) == "player_health" and _is_ambiguous_health_weapon_field(key):
			continue

		merged_snapshot[key_variant] = message[key_variant]

	remote_player_snapshots[player_id] = merged_snapshot

func _is_ambiguous_health_weapon_field(key: String) -> bool:
	return ["weaponType", "weapon", "weapon_type", "weaponId", "weapon_id", "weaponHolding", "currentWeapon", "equippedWeapon", "activeWeapon"].has(key)

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

func disconnect_multiplayer() -> void:
	close_connection()
	clear_match_state()
	seconds_since_last_server_activity = 0.0
	has_sent_room_reservation_request = false
	# Replace the peer so no stale close state leaks into the next connect cycle.
	socket = WebSocketPeer.new()
