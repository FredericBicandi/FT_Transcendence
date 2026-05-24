extends Node

const Localization = preload("res://src/Scripts/components/localization.gd")

@onready var respawn_overlay: ColorRect = $CanvasLayer/RespawnOverlay
@onready var respawn_message: Label = $CanvasLayer/RespawnOverlay/CenterContainer/VBoxContainer/RespawnMessage
@onready var respawn_countdown: Label = $CanvasLayer/RespawnOverlay/CenterContainer/VBoxContainer/RespawnCountdown


func update_for_player(player_body: Node) -> void:
	if player_body == null or not is_instance_valid(player_body):
		# Hide the overlay if the player body is gone
		respawn_overlay.visible = false
		return

	var is_dead: bool = bool(player_body.get("is_dead"))
	respawn_overlay.visible = is_dead

	if not is_dead:
		return

	# Let the player own respawn timing; this scene only displays it
	var respawn_timer: float = float(player_body.get("respawn_timer"))
	respawn_message.text = Localization.translate("respawning")
	respawn_countdown.text = "%.1f" % maxf(respawn_timer, 0.0)
