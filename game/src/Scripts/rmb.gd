extends TextureRect

@export var cursor_offset := Vector2(20, -20)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

func _process(_delta: float) -> void:
	if not visible:
		return

	global_position = get_viewport().get_mouse_position() + cursor_offset
