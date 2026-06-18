extends Node

@onready var timer_label: Label = $CanvasLayer/TimerPanel/MarginContainer/TimerLabel


func set_remaining_seconds(total_seconds: float) -> void:
	timer_label.text = _format_match_time(total_seconds)


func _format_match_time(total_seconds: float) -> String:
	# Round up so the timer does not show 00:00 too early
	var clamped_seconds := maxi(int(ceil(maxf(total_seconds, 0.0))), 0)
	var minutes := clamped_seconds / 60
	var seconds := clamped_seconds % 60
	return "%02d:%02d" % [minutes, seconds]
