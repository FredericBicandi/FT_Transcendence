extends Node

const GAME_SCENE: PackedScene = preload("res://src/Scenes/game.tscn")
const LOBBY_URL: String = "http://localhost:5000"

@onready var status_label: Label = $CanvasLayer/Overlay/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/StatusLabel
@onready var network_client: NetworkClient = $NetworkClient

var has_started_game: bool = false
var game_instance: Node = null
var is_returning_to_lobby: bool = false

func _ready() -> void:
	network_client.connection_established.connect(_on_connection_established)
	network_client.connection_failed.connect(_on_connection_failed)
	network_client.connection_lost.connect(_on_connection_lost)
	network_client.match_ended.connect(_on_match_ended)

	_begin_connection_attempt("Connecting to multiplayer server...")

func _begin_connection_attempt(status_text: String) -> void:
	if is_returning_to_lobby:
		return

	status_label.text = status_text
	$CanvasLayer.visible = true
	var error := network_client.connect_to_server()
	if error != OK:
		status_label.text = "Connection failed. Check the server URL and try again."

func _on_connection_established() -> void:
	if has_started_game:
		return

	has_started_game = true
	status_label.text = "Connected. Starting game..."

	# Keep the network node alive in the root scene and add the gameplay scene beside it.
	game_instance = GAME_SCENE.instantiate()
	add_child(game_instance)
	$CanvasLayer.visible = false

func _on_connection_failed() -> void:
	has_started_game = false
	status_label.text = "Connection failed. Check the server URL and try again."
	$CanvasLayer.visible = true

func _on_connection_lost(reason: String) -> void:
	if is_returning_to_lobby:
		return

	if game_instance != null and is_instance_valid(game_instance):
		game_instance.queue_free()

	game_instance = null
	has_started_game = false
	_begin_connection_attempt("%s Reconnecting..." % reason)

func _on_match_ended(_message: Dictionary) -> void:
	_return_to_lobby()

func _return_to_lobby() -> void:
	if is_returning_to_lobby:
		return

	is_returning_to_lobby = true
	network_client.close_connection()

	if game_instance != null and is_instance_valid(game_instance):
		game_instance.queue_free()

	game_instance = null
	has_started_game = false
	$CanvasLayer.visible = false

	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.location.href = '%s';" % LOBBY_URL)
		return

	OS.shell_open(LOBBY_URL)
