extends CanvasLayer

const Localization = preload("res://src/Scripts/components/localization.gd")

const HINT_KEY := "sniper_rmb_hint"
const FALLBACK_HINT_TEXT := "Hold RMB to aim farther"
const HINT_OFFSET := Vector2(18.0, -56.0)
const ICON_SIZE := Vector2(28.0, 28.0)
const SCREEN_PADDING := 8.0
const FADE_SPEED := 12.0
const SHOW_DURATION_SECONDS := 2.5

@onready var source_icon: TextureRect = get_node_or_null("Rmb") as TextureRect

var local_player: Player
var hint_panel: PanelContainer
var hint_label: Label
var hint_alpha: float = 0.0
var previous_sniper_equipped: bool = false
var visible_time_remaining: float = 0.0

func _ready() -> void:
	layer = 20
	if source_icon != null:
		source_icon.visible = false
		source_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_build_hint()
	_set_hint_alpha(0.0)

func _process(delta: float) -> void:
	if source_icon != null:
		source_icon.visible = false

	if local_player == null or not is_instance_valid(local_player):
		local_player = _find_local_player()

	_update_hint_window(delta)
	var target_alpha := 1.0 if _should_show_hint() else 0.0
	hint_alpha = move_toward(hint_alpha, target_alpha, delta * FADE_SPEED)
	_set_hint_alpha(hint_alpha)

	if hint_panel != null and hint_panel.visible:
		_position_hint()

func _build_hint() -> void:
	hint_panel = PanelContainer.new()
	hint_panel.name = "SniperRmbHint"
	hint_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hint_panel)

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.04, 0.05, 0.06, 0.86)
	panel_style.border_color = Color(0.9, 0.92, 0.86, 0.9)
	panel_style.border_width_left = 2
	panel_style.border_width_top = 2
	panel_style.border_width_right = 2
	panel_style.border_width_bottom = 2
	panel_style.corner_radius_top_left = 4
	panel_style.corner_radius_top_right = 4
	panel_style.corner_radius_bottom_right = 4
	panel_style.corner_radius_bottom_left = 4
	hint_panel.add_theme_stylebox_override("panel", panel_style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 5)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 5)
	hint_panel.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(row)

	var icon := TextureRect.new()
	icon.texture = source_icon.texture if source_icon != null else null
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.custom_minimum_size = ICON_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)

	hint_label = Label.new()
	hint_label.text = _get_hint_text()
	hint_label.add_theme_color_override("font_color", Color(0.96, 0.98, 1.0, 1.0))
	hint_label.add_theme_font_size_override("font_size", 13)
	hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Localization.apply_readable_text_font(hint_label, hint_label.text)
	row.add_child(hint_label)

func _set_hint_alpha(alpha: float) -> void:
	if hint_panel == null:
		return

	hint_panel.visible = alpha > 0.01
	var color := hint_panel.modulate
	color.a = clampf(alpha, 0.0, 1.0)
	hint_panel.modulate = color

func _position_hint() -> void:
	var viewport := get_viewport()
	if viewport == null:
		return

	var viewport_size := viewport.get_visible_rect().size
	var mouse_position := viewport.get_mouse_position()
	var hint_size := hint_panel.size
	if hint_size.x <= 1.0 or hint_size.y <= 1.0:
		hint_size = hint_panel.get_combined_minimum_size()

	var next_position := mouse_position + HINT_OFFSET
	if next_position.x + hint_size.x > viewport_size.x - SCREEN_PADDING:
		next_position.x = mouse_position.x - hint_size.x - HINT_OFFSET.x
	if next_position.y < SCREEN_PADDING:
		next_position.y = mouse_position.y + absf(HINT_OFFSET.y) * 0.35

	next_position.x = clampf(
		next_position.x,
		SCREEN_PADDING,
		maxf(SCREEN_PADDING, viewport_size.x - hint_size.x - SCREEN_PADDING)
	)
	next_position.y = clampf(
		next_position.y,
		SCREEN_PADDING,
		maxf(SCREEN_PADDING, viewport_size.y - hint_size.y - SCREEN_PADDING)
	)
	hint_panel.position = next_position.round()

func _should_show_hint() -> bool:
	if local_player == null or not is_instance_valid(local_player):
		return false
	if not local_player.accepts_input or local_player.is_remote_proxy:
		return false
	if local_player.is_dead or not local_player.match_controls_enabled:
		return false
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		return false

	return previous_sniper_equipped and visible_time_remaining > 0.0

func _update_hint_window(delta: float) -> void:
	var sniper_equipped := _is_sniper_hint_available()
	if sniper_equipped and not previous_sniper_equipped:
		visible_time_remaining = SHOW_DURATION_SECONDS
	elif not sniper_equipped:
		visible_time_remaining = 0.0

	previous_sniper_equipped = sniper_equipped

	if visible_time_remaining > 0.0:
		visible_time_remaining = maxf(visible_time_remaining - delta, 0.0)

func _is_sniper_hint_available() -> bool:
	if local_player == null or not is_instance_valid(local_player):
		return false
	if not local_player.accepts_input or local_player.is_remote_proxy:
		return false
	if local_player.is_dead or not local_player.match_controls_enabled:
		return false

	return local_player.is_sniper_equipped()

func _find_local_player() -> Player:
	var parent := get_parent()
	if parent != null:
		var scene_player := parent.get_node_or_null("Player/CharacterBody2D") as Player
		if _is_local_player(scene_player):
			return scene_player

		scene_player = parent.get_node_or_null("Player") as Player
		if _is_local_player(scene_player):
			return scene_player

	for candidate in get_tree().get_nodes_in_group("player"):
		var body := candidate as Player
		if _is_local_player(body):
			return body

	return null

func _is_local_player(player: Player) -> bool:
	return player != null and player.accepts_input and not player.is_remote_proxy

func _get_hint_text() -> String:
	var translated := Localization.translate(HINT_KEY)
	return FALLBACK_HINT_TEXT if translated == HINT_KEY else translated
