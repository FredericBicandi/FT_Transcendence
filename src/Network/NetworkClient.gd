class_name NetworkClient
extends Node

signal connection_established
signal connection_failed

# Keep the server endpoint editable from the scene inspector.
@export var server_url: String = "ws://34.165.214.228:5000/ws"

var socket: WebSocketPeer = WebSocketPeer.new()
var has_sent_initial_ping: bool = false
var was_open_last_frame: bool = false
var has_reported_closed_state: bool = false
var has_connected_once: bool = false

func _ready() -> void:
	# Register in a group so gameplay code can find the client without relying on a fixed node path.
	add_to_group("network_client")

func _process(_delta: float) -> void:
	var state := socket.get_ready_state()

	if state == WebSocketPeer.STATE_CONNECTING or state == WebSocketPeer.STATE_OPEN:
		socket.poll()
		state = socket.get_ready_state()

	_handle_state_changes(state)

	if state != WebSocketPeer.STATE_OPEN:
		return

	_read_packets()

func connect_to_server() -> Error:
	# Reset transient connection state before opening a fresh socket connection.
	socket = WebSocketPeer.new()
	has_sent_initial_ping = false
	was_open_last_frame = false
	has_reported_closed_state = false
	has_connected_once = false

	var error := socket.connect_to_url(server_url)
	if error != OK:
		push_error("NetworkClient: failed to connect to %s (error %d)" % [server_url, error])
		connection_failed.emit()

	return error

func send_move(x: float, y: float) -> void:
	if socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return

	_send_json({
		"type": "move",
		"x": x,
		"y": y
	})

func _handle_state_changes(state: int) -> void:
	if state == WebSocketPeer.STATE_OPEN and not was_open_last_frame:
		was_open_last_frame = true
		has_connected_once = true
		has_reported_closed_state = false
		print("NetworkClient: connected to %s" % server_url)
		connection_established.emit()
		_send_initial_ping()
		return

	if state != WebSocketPeer.STATE_OPEN:
		was_open_last_frame = false

		if state == WebSocketPeer.STATE_CLOSED and not has_reported_closed_state:
			has_reported_closed_state = true
			var close_code := socket.get_close_code()
			var close_reason := socket.get_close_reason()
			print("NetworkClient: socket closed (%d) %s" % [close_code, close_reason])

			if not has_connected_once:
				connection_failed.emit()

func _send_initial_ping() -> void:
	if has_sent_initial_ping:
		return

	has_sent_initial_ping = true
	_send_json({
		"type": "ping"
	})

func _read_packets() -> void:
	while socket.get_available_packet_count() > 0:
		var packet := socket.get_packet()
		var text := packet.get_string_from_utf8()
		var parsed: Variant = JSON.parse_string(text)

		# Ignore invalid or unexpected payloads so a bad packet never breaks the client loop.
		if typeof(parsed) != TYPE_DICTIONARY:
			push_warning("NetworkClient: ignored invalid JSON packet: %s" % text)
			continue

		_handle_message(parsed)

func _handle_message(message: Dictionary) -> void:
	var message_type := str(message.get("type", ""))

	match message_type:
		"pong":
			print("NetworkClient: received pong")
		"player_move":
			print(
				"NetworkClient: player_move playerId=%s x=%s y=%s"
				% [
					str(message.get("playerId", "")),
					str(message.get("x", 0.0)),
					str(message.get("y", 0.0))
				]
			)
		"player_left":
			print("NetworkClient: player_left playerId=%s" % str(message.get("playerId", "")))
		_:
			print("NetworkClient: unhandled message type=%s" % message_type)

func _send_json(payload: Dictionary) -> void:
	var data := JSON.stringify(payload)
	socket.send_text(data)
