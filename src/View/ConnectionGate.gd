extends Node

const GAME_SCENE: PackedScene = preload("res://src/View/Game.tscn")

@onready var status_label: Label = $CanvasLayer/Overlay/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/StatusLabel
@onready var network_client: NetworkClient = $NetworkClient

var has_started_game: bool = false

func _ready() -> void:
	status_label.text = "Connecting to multiplayer server..."
	network_client.connection_established.connect(_on_connection_established)
	network_client.connection_failed.connect(_on_connection_failed)

	var error := network_client.connect_to_server()
	if error != OK:
		status_label.text = "Connection failed. Check the server URL and try again."

func _on_connection_established() -> void:
	if has_started_game:
		return

	has_started_game = true
	status_label.text = "Connected. Starting game..."

	# Keep the network node alive in the root scene and add the gameplay scene beside it.
	var game := GAME_SCENE.instantiate()
	add_child(game)
	$CanvasLayer.visible = false

func _on_connection_failed() -> void:
	status_label.text = "Connection failed. Check the server URL and try again."
