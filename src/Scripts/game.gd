extends Node2D

const Localization = preload("res://src/Scripts/components/localization.gd")
const PLAYER_SCENE: PackedScene = preload("res://src/Objects/player.tscn")
const DEFAULT_CURSOR_TEXTURE: Texture2D = null
const ANIMATED_CHAT_PROMPT_SCRIPT: Script = preload("res://src/Scripts/components/animated_chat_prompt.gd")
const KILL_FEED_RIFLE_TEXTURE: Texture2D = preload("res://Assets/Textures/Guns/AFRifle/image.png")
const KILL_FEED_SNIPER_TEXTURE: Texture2D = preload("res://Assets/Textures/Guns/Sniper/image.png")
const KILL_FEED_ROCKET_TEXTURE: Texture2D = preload("res://Assets/Textures/Guns/RocketLuncher/image.png")
const KILL_FEED_SHOTGUN_TEXTURE: Texture2D = preload("res://Assets/Textures/Guns/Shotgun/image.png")
const KILL_FEED_DEATH_ICON_SCRIPT: Script = preload("res://src/Scripts/components/kill_feed_death_icon.gd")
const CHAT_MESSAGE_SOUND: AudioStream = preload("res://Assets/Audio/chatMessage.mp3")
const MATCH_END_SOUND: AudioStream = preload("res://Assets/Audio/endGame.ogg")
const CHAT_FONT: FontFile = preload("res://Assets/Fonts/pf_ronda_seven.woff2")
const RESPAWN_LAYER_20_MASK: int = 1 << 19
const RESPAWN_TILE_SOURCE_ID: int = 10
const RESPAWN_TILE_ATLAS_COORDS := Vector2i(25, 2)
const LOBBY_URL: String = "https://pixelfight.live/"
const EXIT_DIALOG_MIN_SIZE := Vector2(360.0, 150.0)
const DEFAULT_CURSOR_TARGET_SIZE: float = 12.0
const CURSOR_RELOAD_RING_SCRIPT: Script = preload("res://src/Scripts/components/cursor_reload_ring.gd")
const KILL_FEED_ENTRY_LIFETIME: float = 4.0
const KILL_FEED_MAX_ENTRIES: int = 5
const KILL_FEED_KILLER_COLOR := Color(0.32, 0.66, 1.0, 1.0)
const KILL_FEED_KILLED_COLOR := Color(1.0, 0.28, 0.28, 1.0)
const MATCH_END_LEADERBOARD_SECONDS: float = 8.0
const CHAT_MAX_MESSAGE_WORDS: int = 50
const CHAT_MAX_MESSAGE_LENGTH: int = 300
const CHAT_REPEATED_CHAR_LIMIT: int = 8
const CHAT_MESSAGE_LIFETIME: float = 5.0
const CHAT_INPUT_FONT_SIZE: int = 13

# Cache scene nodes once so gameplay updates stay cheap
@onready var map: Node2D = $Map
@onready var player = $Player
@onready var player_body = $Player/CharacterBody2D
@onready var weapons: WeaponsManager = $Player/CharacterBody2D/Weapons
@onready var weapon_switcher_ui: Node = $WeaponSwitcher
@onready var respawn_ui: Node = $RespawnUi
@onready var timer_ui: Node = $Timer
@onready var leaderboard_ui: Node = $Leaderboard
@onready var cursor: Node2D = $Cursor
@onready var network_client: NetworkClient = get_tree().get_first_node_in_group("network_client") as NetworkClient

var observed_weapon: BaseWeapon
var remote_players: Dictionary = {}
var local_player_id: String = ""
var room_id: String = ""
var remaining_match_seconds: float = 0.0
var match_has_ended: bool = false
var respawn_positions: Array[Vector2] = []
var respawn_rng := RandomNumberGenerator.new()
var last_respawn_index: int = -1
var exit_dialog_layer: CanvasLayer
var exit_cancel_button: Button
var exit_dialog_open: bool = false
var player_controls_enabled_before_exit_dialog: bool = true
var mouse_mode_before_exit_dialog = Input.MOUSE_MODE_HIDDEN
var default_cursor: Sprite2D
var cursor_reload_ring: Node2D
var kill_feed_layer: CanvasLayer
var kill_feed_container: VBoxContainer
var chat_layer: CanvasLayer
var chat_container: VBoxContainer
var chat_messages_container: VBoxContainer
var chat_prompt_label: Control
var chat_input: LineEdit
var chat_message_audio_player: AudioStreamPlayer
var match_end_audio_player: AudioStreamPlayer
var chat_is_open: bool = false
var chat_controls_enabled_before_open: bool = true
var match_started_msec: int = 0
var final_match_summary: Dictionary = {}
var match_end_exit_scheduled: bool = false
var match_end_sound_played: bool = false
var processed_match_saved_ids: Dictionary = {}
var pending_match_ended_messages: Dictionary = {}
var pending_remote_player_states: Dictionary = {}

func _ready() -> void:
	match_started_msec = Time.get_ticks_msec()
	respawn_rng.randomize()
	_cache_respawn_positions()
	# Let the map own spawn points instead of hardcoding them in the player
	player_body.set_respawn_position_provider(Callable(self, "_get_random_respawn_position"))
	var initial_respawn_position := _get_random_respawn_position()
	player_body.set_spawn_position(initial_respawn_position)
	player_body.global_position = initial_respawn_position

	# Keep the HUD attached to the currently equipped weapon
	_hide_legacy_cursor_children()
	_create_default_cursor()
	_create_cursor_reload_ring()
	weapons.active_weapon_changed.connect(_on_active_weapon_changed)
	weapon_switcher_ui.call("set_weapons", weapons.get_weapons_in_order())
	_on_active_weapon_changed(weapons.get_active_weapon())
	_connect_network_signals()
	apply_network_snapshot()
	respawn_ui.call("update_for_player", player_body)
	timer_ui.call("set_remaining_seconds", remaining_match_seconds)
	_set_mouse_visible(false)
	_create_kill_feed()
	_create_chat()
	_create_chat_audio_player()
	_create_match_end_audio_player()
	_create_exit_dialog()
	Localization.apply_active_language_font(self)
	if match_has_ended:
		remaining_match_seconds = 0.0
		timer_ui.call("set_remaining_seconds", remaining_match_seconds)
		_freeze_match_play()
		leaderboard_ui.set("tab_visibility_enabled", false)
		leaderboard_ui.call("set_leaderboard_visible", true)
		_play_match_end_sound()
		final_match_summary = _build_match_summary()
		_schedule_match_end_dashboard_return()

func _process(delta: float) -> void:
	# Tick the local timer between server sync messages
	if not match_has_ended and remaining_match_seconds > 0.0:
		remaining_match_seconds = maxf(remaining_match_seconds - delta, 0.0)

	_flush_pending_remote_player_states()
	respawn_ui.call("update_for_player", player_body)
	timer_ui.call("set_remaining_seconds", remaining_match_seconds)
	_update_cursor_reload_ring()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and _is_enter_key(event):
		if chat_is_open:
			_submit_or_close_chat()
		else:
			_open_chat()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if chat_is_open:
			_close_chat()
			get_viewport().set_input_as_handled()
			return

		if match_has_ended:
			get_viewport().set_input_as_handled()
			return

		if exit_dialog_open:
			_cancel_exit_dialog()
		else:
			_show_exit_dialog()

		get_viewport().set_input_as_handled()

func _create_exit_dialog() -> void:
	exit_dialog_layer = CanvasLayer.new()
	exit_dialog_layer.name = "ExitDialogLayer"
	exit_dialog_layer.layer = 100
	exit_dialog_layer.visible = false
	add_child(exit_dialog_layer)

	var overlay := ColorRect.new()
	overlay.name = "Overlay"
	overlay.color = Color(0.0, 0.0, 0.0, 0.65)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	exit_dialog_layer.add_child(overlay)

	var center := CenterContainer.new()
	center.name = "CenterContainer"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = EXIT_DIALOG_MIN_SIZE
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 14)
	margin.add_child(content)

	var title := Label.new()
	title.text = Localization.translate("leave_game_title")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Localization.apply_readable_text_font(title, title.text)
	title.add_theme_font_size_override("font_size", 22)
	content.add_child(title)

	var body := Label.new()
	body.text = Localization.translate("leave_game_body")
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	Localization.apply_readable_text_font(body, body.text)
	content.add_child(body)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	content.add_child(buttons)

	exit_cancel_button = Button.new()
	exit_cancel_button.text = Localization.translate("cancel")
	exit_cancel_button.custom_minimum_size = Vector2(110.0, 34.0)
	Localization.apply_readable_text_font(exit_cancel_button, exit_cancel_button.text)
	exit_cancel_button.pressed.connect(_cancel_exit_dialog)
	buttons.add_child(exit_cancel_button)

	var yes_button := Button.new()
	yes_button.text = Localization.translate("yes")
	yes_button.custom_minimum_size = Vector2(110.0, 34.0)
	Localization.apply_readable_text_font(yes_button, yes_button.text)
	yes_button.pressed.connect(_confirm_exit_dialog)
	buttons.add_child(yes_button)

func _show_exit_dialog() -> void:
	if exit_dialog_open or exit_dialog_layer == null:
		return

	exit_dialog_open = true
	player_controls_enabled_before_exit_dialog = bool(player_body.match_controls_enabled) if player_body != null else true
	mouse_mode_before_exit_dialog = Input.get_mouse_mode()
	if player_body != null:
		player_body.set_match_controls_enabled(false)

	exit_dialog_layer.visible = true
	_set_mouse_visible(true)
	if exit_cancel_button != null:
		exit_cancel_button.grab_focus()

func _cancel_exit_dialog() -> void:
	if not exit_dialog_open:
		return

	exit_dialog_open = false
	if exit_dialog_layer != null:
		exit_dialog_layer.visible = false

	if player_body != null:
		player_body.set_match_controls_enabled(player_controls_enabled_before_exit_dialog and not match_has_ended)
	_set_mouse_visible(mouse_mode_before_exit_dialog != Input.MOUSE_MODE_HIDDEN)

func _confirm_exit_dialog() -> void:
	if player_body != null:
		player_body.set_match_controls_enabled(false)
	_exit_to_dashboard("manual")

func _exit_to_dashboard(reason: String, summary: Dictionary = {}) -> void:
	if _is_in_room() and network_client != null:
		network_client.send_leave_match()

	_cleanup_match_state()
	_reset_parent_after_exit()
	_post_exit_game(reason, summary)

func _is_in_room() -> bool:
	if room_id.strip_edges() != "":
		return true

	return network_client != null and network_client.is_in_room()

func _cleanup_match_state() -> void:
	if exit_dialog_open:
		exit_dialog_open = false
		if exit_dialog_layer != null:
			exit_dialog_layer.visible = false

	match_has_ended = false
	match_end_exit_scheduled = false
	remaining_match_seconds = 0.0
	room_id = ""
	local_player_id = ""
	final_match_summary = {}
	processed_match_saved_ids.clear()
	pending_match_ended_messages.clear()
	pending_remote_player_states.clear()

	if player_body != null:
		player_body.set_match_controls_enabled(false)
	if weapons != null:
		weapons.set_input_enabled(false)
		weapons.clear_all_projectiles()

	for remote_wrapper_variant in remote_players.values():
		var remote_wrapper := remote_wrapper_variant as Node
		if remote_wrapper != null and is_instance_valid(remote_wrapper):
			remote_wrapper.queue_free()

	remote_players.clear()

func _post_exit_game(reason: String = "manual", summary: Dictionary = {}) -> void:
	if not OS.has_feature("web"):
		get_tree().quit()
		return

	var payload := {
		"type": "EXIT_GAME",
		"reason": reason
	}
	if not summary.is_empty():
		payload["match_summary"] = summary
		payload["room_id"] = str(summary.get("room_id", ""))
		payload["player_id"] = str(summary.get("player_id", ""))
		payload["kills"] = int(summary.get("kills", 0))
		payload["deaths"] = int(summary.get("deaths", 0))
		payload["death"] = int(summary.get("death", summary.get("deaths", 0)))
		payload["score"] = int(summary.get("score", 0))
		payload["play_time_ms"] = int(summary.get("play_time_ms", 0))
		payload["play_time_seconds"] = float(summary.get("play_time_seconds", 0.0))

	JavaScriptBridge.eval(
		"window.parent.postMessage(%s, window.location.origin); if (window.parent === window) { window.location.href = '%s'; }" % [JSON.stringify(payload), LOBBY_URL],
		false
	)

func _create_default_cursor() -> void:
	default_cursor = Sprite2D.new()
	default_cursor.name = "DefaultCursor"
	default_cursor.texture = DEFAULT_CURSOR_TEXTURE
	default_cursor.z_index = 10
	if DEFAULT_CURSOR_TEXTURE != null:
		default_cursor.scale = _get_cursor_scale_for_texture(DEFAULT_CURSOR_TEXTURE)
	cursor.add_child(default_cursor)

func _hide_legacy_cursor_children() -> void:
	if cursor == null:
		return

	for child in cursor.get_children():
		var cursor_item := child as CanvasItem
		if cursor_item != null:
			cursor_item.visible = false

func _get_cursor_scale_for_texture(texture: Texture2D) -> Vector2:
	if texture == null:
		return Vector2.ONE

	var texture_size := texture.get_size()
	var largest_side := maxf(texture_size.x, texture_size.y)
	if largest_side <= 0.0:
		return Vector2.ONE

	var scale_factor := DEFAULT_CURSOR_TARGET_SIZE / largest_side
	return Vector2(scale_factor, scale_factor)

func _create_cursor_reload_ring() -> void:
	cursor_reload_ring = Node2D.new()
	cursor_reload_ring.name = "ReloadRing"
	cursor_reload_ring.set_script(CURSOR_RELOAD_RING_SCRIPT)
	cursor.add_child(cursor_reload_ring)

func _set_mouse_visible(is_visible: bool) -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE if is_visible else Input.MOUSE_MODE_HIDDEN)
	if cursor != null and is_instance_valid(cursor):
		# Hide the in-world cursor whenever the OS cursor is showing so we
		# never paint two cursors at once (exit dialog, match end, etc.).
		cursor.visible = not is_visible

func _set_cursor_for_weapon(weapon: BaseWeapon) -> void:
	if default_cursor == null:
		return

	if weapon != null and weapon.hides_cursor_when_selected():
		default_cursor.visible = false
		if cursor_reload_ring != null:
			cursor_reload_ring.call("set_ring_visible", false)
		return

	var crosshair_texture := DEFAULT_CURSOR_TEXTURE
	if weapon != null:
		var weapon_crosshair := weapon.get_weapon_crosshair()
		if weapon_crosshair != null:
			crosshair_texture = weapon_crosshair

	default_cursor.texture = crosshair_texture
	if crosshair_texture != null:
		default_cursor.scale = _get_cursor_scale_for_texture(crosshair_texture)
	else:
		default_cursor.scale = Vector2.ONE
	default_cursor.visible = true

func _update_cursor_reload_ring() -> void:
	if cursor_reload_ring == null:
		return

	# Hide while the cursor itself is hidden (exit dialog, match end).
	var ring_active := (
		cursor != null
		and cursor.visible
		and observed_weapon != null
		and not observed_weapon.hides_cursor_when_selected()
		and observed_weapon.is_reloading()
	)
	cursor_reload_ring.call("set_ring_visible", ring_active)
	if ring_active:
		cursor_reload_ring.call("set_progress", observed_weapon.get_reload_progress())

func _create_kill_feed() -> void:
	kill_feed_layer = CanvasLayer.new()
	kill_feed_layer.name = "KillFeedLayer"
	kill_feed_layer.layer = 30
	add_child(kill_feed_layer)

	var anchor: Control = Control.new()
	anchor.name = "KillFeedAnchor"
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor.set_anchors_preset(Control.PRESET_FULL_RECT)
	kill_feed_layer.add_child(anchor)

	kill_feed_container = VBoxContainer.new()
	kill_feed_container.name = "KillFeedContainer"
	kill_feed_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	kill_feed_container.anchor_left = 1.0
	kill_feed_container.anchor_top = 0.0
	kill_feed_container.anchor_right = 1.0
	kill_feed_container.anchor_bottom = 0.0
	kill_feed_container.offset_left = -360.0
	kill_feed_container.offset_top = 16.0
	kill_feed_container.offset_right = -16.0
	kill_feed_container.offset_bottom = 220.0
	kill_feed_container.add_theme_constant_override("separation", 6)
	anchor.add_child(kill_feed_container)

func _create_chat() -> void:
	chat_layer = CanvasLayer.new()
	chat_layer.name = "ChatLayer"
	chat_layer.layer = 32
	add_child(chat_layer)

	var anchor := Control.new()
	anchor.name = "ChatAnchor"
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor.set_anchors_preset(Control.PRESET_FULL_RECT)
	chat_layer.add_child(anchor)

	chat_container = VBoxContainer.new()
	chat_container.name = "ChatContainer"
	chat_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chat_container.anchor_left = 1.0
	chat_container.anchor_top = 1.0
	chat_container.anchor_right = 1.0
	chat_container.anchor_bottom = 1.0
	chat_container.offset_left = -414.0
	chat_container.offset_top = -282.0
	chat_container.offset_right = -18.0
	chat_container.offset_bottom = -18.0
	chat_container.add_theme_constant_override("separation", 5)
	anchor.add_child(chat_container)

	chat_messages_container = VBoxContainer.new()
	chat_messages_container.name = "Messages"
	chat_messages_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chat_messages_container.alignment = BoxContainer.ALIGNMENT_END
	chat_messages_container.add_theme_constant_override("separation", 4)
	chat_container.add_child(chat_messages_container)

	chat_prompt_label = ANIMATED_CHAT_PROMPT_SCRIPT.new() as Control
	chat_prompt_label.name = "ChatPrompt"
	chat_prompt_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chat_prompt_label.call("set_prompt_text", Localization.translate("chat_prompt"), CHAT_FONT)
	chat_container.add_child(chat_prompt_label)

	chat_input = LineEdit.new()
	chat_input.name = "ChatInput"
	chat_input.visible = false
	chat_input.placeholder_text = Localization.translate("chat_placeholder")
	chat_input.max_length = 0
	chat_input.custom_minimum_size = Vector2(0.0, 40.0)
	chat_input.mouse_filter = Control.MOUSE_FILTER_STOP
	Localization.apply_readable_text_font(chat_input, chat_input.placeholder_text, CHAT_FONT)
	chat_input.add_theme_font_size_override("font_size", CHAT_INPUT_FONT_SIZE)
	chat_input.text_changed.connect(_on_chat_input_text_changed)
	chat_input.text_submitted.connect(_on_chat_text_submitted)
	chat_container.add_child(chat_input)

func _create_chat_audio_player() -> void:
	chat_message_audio_player = AudioStreamPlayer.new()
	chat_message_audio_player.name = "ChatMessageAudioPlayer"
	chat_message_audio_player.stream = CHAT_MESSAGE_SOUND
	add_child(chat_message_audio_player)

func _create_match_end_audio_player() -> void:
	match_end_audio_player = AudioStreamPlayer.new()
	match_end_audio_player.name = "MatchEndAudioPlayer"
	match_end_audio_player.stream = MATCH_END_SOUND
	add_child(match_end_audio_player)

func _open_chat() -> void:
	if chat_input == null or match_has_ended:
		return

	chat_is_open = true
	chat_controls_enabled_before_open = bool(player_body.match_controls_enabled) if player_body != null else true
	if player_body != null:
		player_body.set_match_controls_enabled(false)
	if weapons != null:
		weapons.set_input_enabled(false)

	chat_input.text = ""
	chat_input.visible = true
	if chat_prompt_label != null:
		chat_prompt_label.visible = false
	chat_input.grab_focus()
	_set_mouse_visible(true)

func _submit_or_close_chat() -> void:
	if chat_input == null:
		return

	var clean_message: String = _sanitize_chat_message(chat_input.text)
	if clean_message != "":
		_send_chat_message(clean_message)

	_close_chat()

func _close_chat() -> void:
	if chat_input == null:
		return

	chat_is_open = false
	chat_input.text = ""
	chat_input.visible = false
	if chat_prompt_label != null:
		chat_prompt_label.visible = not match_has_ended
	chat_input.release_focus()
	if player_body != null:
		player_body.set_match_controls_enabled(chat_controls_enabled_before_open and not match_has_ended)
	if weapons != null:
		weapons.set_input_enabled(chat_controls_enabled_before_open and not match_has_ended)
	_set_mouse_visible(false)

func _on_chat_text_submitted(_submitted_text: String) -> void:
	_submit_or_close_chat()

func _on_chat_input_text_changed(next_text: String) -> void:
	var font_sample := next_text if next_text != "" else chat_input.placeholder_text
	Localization.apply_readable_text_font(chat_input, font_sample, CHAT_FONT)
	chat_input.add_theme_font_size_override("font_size", CHAT_INPUT_FONT_SIZE)

func _send_chat_message(clean_message: String) -> void:
	var sender_id: String = local_player_id
	var sender_name: String = network_client.player_name if network_client != null else Localization.translate("default_player")
	if sender_name.strip_edges() == "":
		sender_name = Localization.translate("default_player")

	if network_client != null:
		network_client.send_chat_message(clean_message)

	_show_chat_message(sender_id, sender_name, clean_message)
	_play_chat_message_sound()

func _on_chat_message_received(message: Dictionary) -> void:
	var content: String = _sanitize_chat_message(str(message.get("content", message.get("message", message.get("text", "")))))
	if content == "":
		return

	var sender_id: String = str(message.get("player_id", "")).strip_edges()
	if sender_id != "" and sender_id == local_player_id:
		return

	var sender_name: String = str(message.get("player_name", message.get("name", Localization.translate("default_player")))).strip_edges()
	if sender_name == "":
		sender_name = Localization.translate("default_player")

	_show_chat_message(sender_id, sender_name, content)
	_play_chat_message_sound()

func _show_chat_message(sender_id: String, sender_name: String, content: String) -> void:
	if chat_messages_container == null:
		return

	var row: PanelContainer = PanelContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.modulate.a = 0.0
	row.add_theme_stylebox_override("panel", _create_chat_message_style())

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 4)
	row.add_child(margin)

	var layout: HBoxContainer = HBoxContainer.new()
	layout.add_theme_constant_override("separation", 5)
	margin.add_child(layout)

	var name_color: Color = _get_chat_name_color(sender_id if sender_id != "" else sender_name)
	var name_label: Label = Label.new()
	name_label.text = "%s:" % sender_name
	name_label.add_theme_color_override("font_color", name_color)
	Localization.apply_readable_text_font(name_label, name_label.text, CHAT_FONT)
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(name_label)

	var content_label: Label = Label.new()
	content_label.text = content
	content_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content_label.add_theme_color_override("font_color", Color(0.96, 0.98, 1.0, 1.0))
	Localization.apply_readable_text_font(content_label, content, CHAT_FONT)
	content_label.add_theme_font_size_override("font_size", 10)
	content_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(content_label)

	chat_messages_container.add_child(row)

	var fade_in: Tween = create_tween()
	fade_in.tween_property(row, "modulate:a", 1.0, 0.08)
	get_tree().create_timer(CHAT_MESSAGE_LIFETIME).timeout.connect(_expire_chat_message.bind(row))

func _expire_chat_message(row: Control) -> void:
	if row == null or not is_instance_valid(row):
		return

	var fade_out: Tween = create_tween()
	fade_out.tween_property(row, "modulate:a", 0.0, 0.18)
	fade_out.finished.connect(row.queue_free)

func _play_chat_message_sound() -> void:
	if chat_message_audio_player == null:
		return

	chat_message_audio_player.stop()
	chat_message_audio_player.play()

func _play_match_end_sound() -> void:
	if match_end_sound_played or match_end_audio_player == null:
		return

	match_end_sound_played = true
	match_end_audio_player.stop()
	match_end_audio_player.play()

func _create_chat_message_style() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.13, 0.14, 0.72)
	style.border_color = Color(1.0, 1.0, 1.0, 0.08)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_right = 4
	style.corner_radius_bottom_left = 4
	return style

func _sanitize_chat_message(message: String) -> String:
	var collapsed: String = " ".join(message.strip_edges().split(" ", false))
	var result: String = ""
	var previous_code: int = -1
	var repeat_count: int = 0

	for index in collapsed.length():
		var code: int = collapsed.unicode_at(index)
		if not _is_allowed_chat_codepoint(code):
			continue

		if code == previous_code:
			repeat_count += 1
			if repeat_count > CHAT_REPEATED_CHAR_LIMIT:
				continue
		else:
			previous_code = code
			repeat_count = 1

		result += String.chr(code)

	var words: PackedStringArray = result.strip_edges().split(" ", false)
	var limited_words: PackedStringArray = PackedStringArray()
	for word_variant in words:
		limited_words.append(str(word_variant))
		if limited_words.size() >= CHAT_MAX_MESSAGE_WORDS:
			break

	return " ".join(limited_words).strip_edges().left(CHAT_MAX_MESSAGE_LENGTH)

func _is_allowed_chat_codepoint(code: int) -> bool:
	if code == 32:
		return true
	if code < 32 or code == 127:
		return false
	if code >= 0x0600 and code <= 0x06FF:
		return true
	if code >= 0x0750 and code <= 0x077F:
		return true
	if code >= 0x08A0 and code <= 0x08FF:
		return true
	if code >= 0xFB50 and code <= 0xFDFF:
		return true
	if code >= 0xFE70 and code <= 0xFEFF:
		return true
	if code >= 33 and code <= 126:
		return true

	return false

func _escape_chat_bbcode(text: String) -> String:
	return text.replace("[", "(").replace("]", ")")

func _get_chat_name_color(seed_text: String) -> Color:
	var hash_value: int = 0
	for index in seed_text.length():
		hash_value = int(posmod(hash_value * 31 + seed_text.unicode_at(index), 360))

	var hue := float(hash_value) / 360.0
	return Color.from_hsv(hue, 0.65, 0.95)

func _is_enter_key(event: InputEventKey) -> bool:
	return event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER

func _on_kill_feed_received(message: Dictionary) -> void:
	var killer_name: String = _pick_kill_feed_name(message, ["killer", "killer_name", "attacker", "attacker_name"], Localization.translate("unknown_player"))
	var killed_name: String = _pick_kill_feed_name(message, ["killed", "killed_name", "victim", "victim_name"], Localization.translate("unknown_player"))
	if killer_name == "" or killed_name == "":
		return

	var weapon_type: String = _pick_kill_feed_weapon_type(message)
	var is_self_kill: bool = _is_kill_feed_self_kill(message, killer_name, killed_name)
	_show_kill_feed_entry(killer_name, killed_name, weapon_type, is_self_kill)

func _show_kill_feed_entry(killer_name: String, killed_name: String, weapon_type: String, is_self_kill: bool) -> void:
	if kill_feed_container == null:
		return

	var row := PanelContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.modulate.a = 0.0
	row.size_flags_horizontal = Control.SIZE_SHRINK_END
	row.add_theme_stylebox_override("panel", _create_kill_feed_row_style())

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 6)
	row.add_child(margin)

	var columns := HBoxContainer.new()
	columns.alignment = BoxContainer.ALIGNMENT_END
	columns.add_theme_constant_override("separation", 8)
	margin.add_child(columns)

	var killer_label := _create_kill_feed_label(killer_name, KILL_FEED_KILLER_COLOR, HORIZONTAL_ALIGNMENT_RIGHT)
	columns.add_child(killer_label)

	if is_self_kill:
		var death_icon := KILL_FEED_DEATH_ICON_SCRIPT.new() as Control
		death_icon.custom_minimum_size = Vector2(28.0, 22.0)
		death_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		columns.add_child(death_icon)
	else:
		var icon := TextureRect.new()
		icon.texture = _get_kill_feed_weapon_texture(weapon_type)
		icon.custom_minimum_size = Vector2(38.0, 22.0)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		columns.add_child(icon)

	if not is_self_kill:
		var killed_label := _create_kill_feed_label(killed_name, KILL_FEED_KILLED_COLOR, HORIZONTAL_ALIGNMENT_LEFT)
		columns.add_child(killed_label)

	kill_feed_container.add_child(row)
	kill_feed_container.move_child(row, 0)
	_trim_kill_feed_entries()

	var fade_in := create_tween()
	fade_in.tween_property(row, "modulate:a", 1.0, 0.12)
	get_tree().create_timer(KILL_FEED_ENTRY_LIFETIME).timeout.connect(_expire_kill_feed_entry.bind(row))

func _create_kill_feed_label(text: String, color: Color, alignment: int) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = alignment
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.75))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.add_theme_font_size_override("font_size", 15)
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.custom_minimum_size = Vector2(112.0, 0.0)
	Localization.apply_readable_text_font(label, label.text)
	return label

func _create_kill_feed_row_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.54)
	style.border_color = Color(1.0, 1.0, 1.0, 0.08)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_right = 4
	style.corner_radius_bottom_left = 4
	return style

func _trim_kill_feed_entries() -> void:
	while kill_feed_container != null and kill_feed_container.get_child_count() > KILL_FEED_MAX_ENTRIES:
		var oldest := kill_feed_container.get_child(kill_feed_container.get_child_count() - 1)
		oldest.queue_free()

func _expire_kill_feed_entry(row: Control) -> void:
	if row == null or not is_instance_valid(row):
		return

	var fade_out := create_tween()
	fade_out.tween_property(row, "modulate:a", 0.0, 0.25)
	fade_out.finished.connect(row.queue_free)

func _pick_kill_feed_name(message: Dictionary, keys: Array[String], fallback: String) -> String:
	for key in keys:
		if not message.has(key):
			continue

		var value := str(message[key]).strip_edges()
		if value != "":
			return value

	return fallback

func _pick_kill_feed_weapon_type(message: Dictionary) -> String:
	for key in ["weapon", "weapon_type", "weapon_id", "weapon_holding", "source_weapon", "source_weapon_type", "killing_weapon", "cause"]:
		if not message.has(key):
			continue

		var value: String = str(message[key]).strip_edges()
		if value != "":
			return value

	return ""

func _is_kill_feed_self_kill(message: Dictionary, killer_name: String, killed_name: String) -> bool:
	if bool(message.get("self_kill", message.get("suicide", false))):
		return true

	var killer_id: String = _pick_kill_feed_name(message, ["killer_id", "attacker_id"], "")
	var killed_id: String = _pick_kill_feed_name(message, ["victim_id", "target_player_id"], "")
	if killer_id != "" and killed_id != "":
		return killer_id == killed_id

	return killer_name.strip_edges() != "" and killer_name == killed_name

func _get_kill_feed_weapon_texture(weapon_type: String) -> Texture2D:
	var normalized: String = weapon_type.strip_edges().to_lower().replace("_", " ").replace("-", " ")
	normalized = " ".join(normalized.split(" ", false))
	match normalized:
		"sniper", "sniper rifle":
			return KILL_FEED_SNIPER_TEXTURE
		"rocket launcher", "rocket", "rpg":
			return KILL_FEED_ROCKET_TEXTURE
		"shotgun":
			return KILL_FEED_SHOTGUN_TEXTURE
		"assult rifle", "assault rifle", "rifle", "ar":
			return KILL_FEED_RIFLE_TEXTURE

	return KILL_FEED_RIFLE_TEXTURE

func _on_active_weapon_changed(weapon: BaseWeapon) -> void:
	# Stop listening to the old weapon before tracking the new one
	if observed_weapon != null and observed_weapon.ammo_changed.is_connected(_on_ammo_changed):
		observed_weapon.ammo_changed.disconnect(_on_ammo_changed)

	observed_weapon = weapon
	_set_cursor_for_weapon(observed_weapon)

	# Let the weapon HUD own icon, name, and ammo display
	weapon_switcher_ui.call("show_weapon", observed_weapon)
	if observed_weapon == null:
		return

	observed_weapon.ammo_changed.connect(_on_ammo_changed)
	_on_ammo_changed(observed_weapon.get_current_ammo(), observed_weapon.get_magazine_size())

func _on_ammo_changed(current_ammo: int, max_ammo: int) -> void:
	weapon_switcher_ui.call("set_ammo", current_ammo, max_ammo)

func _connect_network_signals() -> void:
	if network_client == null:
		return

	# Guard connects because this scene can be recreated after a match
	if not network_client.room_joined.is_connected(_on_room_joined):
		network_client.room_joined.connect(_on_room_joined)

	if not network_client.time_synced.is_connected(_on_time_synced):
		network_client.time_synced.connect(_on_time_synced)

	if not network_client.player_move_received.is_connected(_on_player_move_received):
		network_client.player_move_received.connect(_on_player_move_received)

	if not network_client.player_angle_received.is_connected(_on_player_angle_received):
		network_client.player_angle_received.connect(_on_player_angle_received)

	if not network_client.player_weapon_switch_received.is_connected(_on_player_weapon_switch_received):
		network_client.player_weapon_switch_received.connect(_on_player_weapon_switch_received)

	if not network_client.player_health_received.is_connected(_on_player_health_received):
		network_client.player_health_received.connect(_on_player_health_received)

	if not network_client.bullet_spawn_received.is_connected(_on_bullet_spawn_received):
		network_client.bullet_spawn_received.connect(_on_bullet_spawn_received)

	if not network_client.player_left_received.is_connected(_on_player_left_received):
		network_client.player_left_received.connect(_on_player_left_received)

	if not network_client.leaderboard_updated.is_connected(_on_leaderboard_updated):
		network_client.leaderboard_updated.connect(_on_leaderboard_updated)

	if not network_client.kill_feed_received.is_connected(_on_kill_feed_received):
		network_client.kill_feed_received.connect(_on_kill_feed_received)

	if not network_client.chat_message_received.is_connected(_on_chat_message_received):
		network_client.chat_message_received.connect(_on_chat_message_received)

	if not network_client.match_ended.is_connected(_on_match_ended):
		network_client.match_ended.connect(_on_match_ended)

	if not network_client.match_saved.is_connected(_on_match_saved):
		network_client.match_saved.connect(_on_match_saved)

func apply_network_snapshot() -> void:
	if network_client == null:
		return

	# Rebuild local state from data received before the game scene loaded
	local_player_id = network_client.local_player_id
	room_id = network_client.local_room_id
	player_body.set_network_player_id(local_player_id)
	player_body.set_network_player_display_name(network_client.get_local_player_display_name(network_client.last_room_joined_message))
	leaderboard_ui.call("set_local_player_id", local_player_id)
	remaining_match_seconds = maxf(network_client.remaining_seconds, 0.0)
	match_has_ended = network_client.match_finished
	if match_has_ended:
		remaining_match_seconds = 0.0
	else:
		match_end_sound_played = false
	player_body.set_match_controls_enabled(not match_has_ended)
	_apply_leaderboard_snapshot(network_client.last_room_joined_message)
	_apply_local_player_state(network_client.last_room_joined_message, false)
	_apply_initial_remote_players(network_client.last_room_joined_message)
	_apply_cached_remote_players()

func _on_room_joined(message: Dictionary) -> void:
	if network_client != null and network_client.local_player_id != "":
		local_player_id = network_client.local_player_id
	else:
		local_player_id = str(message.get("player_id", ""))

	room_id = str(message.get("room_id", ""))
	player_body.set_network_player_id(local_player_id)
	player_body.set_network_player_display_name(network_client.get_local_player_display_name(message))
	leaderboard_ui.call("set_local_player_id", local_player_id)
	remaining_match_seconds = maxf(NetworkClient.get_finite_float(message.get("remaining_seconds", 0.0), 0.0), 0.0)
	match_has_ended = false
	match_end_sound_played = false
	player_body.set_match_controls_enabled(true)
	pending_remote_player_states.clear()
	_apply_leaderboard_snapshot(message)
	_apply_local_player_state(message, false)
	_apply_initial_remote_players(message)

func _on_time_synced(message: Dictionary) -> void:
	var synced_room_id := str(message.get("room_id", ""))
	if room_id != "" and synced_room_id != "" and synced_room_id != room_id:
		# Ignore timer packets from an old room
		return

	if match_has_ended:
		_apply_leaderboard_snapshot(message)
		final_match_summary = _build_match_summary()
		return

	remaining_match_seconds = maxf(NetworkClient.get_finite_float(message.get("remaining_seconds", remaining_match_seconds), remaining_match_seconds), 0.0)
	_apply_leaderboard_snapshot(message)

func _on_leaderboard_updated(message: Dictionary) -> void:
	_apply_leaderboard_snapshot(message)
	if match_has_ended:
		final_match_summary = _build_match_summary()

func _on_player_move_received(message: Dictionary) -> void:
	if match_has_ended:
		return

	var player_id := str(message.get("player_id", ""))
	if player_id == "" or player_id == local_player_id:
		return

	_queue_remote_player_state_message(player_id, message)

func _on_player_left_received(player_id: String) -> void:
	pending_remote_player_states.erase(player_id)
	_remove_remote_player(player_id)

func _on_player_angle_received(message: Dictionary) -> void:
	if match_has_ended:
		return

	var player_id := str(message.get("player_id", ""))
	var has_angle := (
		NetworkClient.is_finite_number(message.get("angle", NAN))
		or NetworkClient.is_finite_number(message.get("rotation", NAN))
		or NetworkClient.is_finite_number(message.get("aim_angle", NAN))
	)
	if player_id == "" or player_id == local_player_id or not has_angle:
		return

	_queue_remote_player_state_message(player_id, message)

func _on_player_weapon_switch_received(message: Dictionary) -> void:
	if match_has_ended:
		return

	var player_id := str(message.get("player_id", ""))
	if player_id == "" or player_id == local_player_id:
		return

	_queue_remote_player_state_message(player_id, message)

func _on_player_health_received(message: Dictionary) -> void:
	if match_has_ended:
		return

	var player_id := str(message.get("player_id", ""))
	if player_id == "":
		return

	if player_id == local_player_id:
		_apply_local_player_state(message, false)
		return

	_queue_remote_player_state_message(player_id, message)

func _queue_remote_player_state_message(player_id: String, message: Dictionary) -> void:
	if player_id == "":
		return

	var pending_variant: Variant = pending_remote_player_states.get(player_id, {})
	var merged_message: Dictionary = {}
	if typeof(pending_variant) == TYPE_DICTIONARY:
		merged_message = (pending_variant as Dictionary).duplicate(true)

	for key_variant in message.keys():
		merged_message[key_variant] = message[key_variant]

	pending_remote_player_states[player_id] = merged_message

func _flush_pending_remote_player_states() -> void:
	if pending_remote_player_states.is_empty() or match_has_ended:
		return

	for message_variant in pending_remote_player_states.values():
		if typeof(message_variant) != TYPE_DICTIONARY:
			continue

		_apply_remote_player_state(message_variant as Dictionary)

	pending_remote_player_states.clear()

func _on_match_ended(message: Dictionary) -> void:
	var ended_room_id := str(message.get("room_id", ""))
	if room_id != "" and ended_room_id != "" and ended_room_id != room_id:
		return

	var ended_match_id := str(message.get("match_id", ""))
	if ended_match_id != "":
		pending_match_ended_messages[ended_match_id] = message.duplicate(true)

	match_has_ended = true
	remaining_match_seconds = 0.0
	timer_ui.call("set_remaining_seconds", remaining_match_seconds)
	pending_remote_player_states.clear()
	_apply_leaderboard_snapshot(message)
	_freeze_match_play()
	leaderboard_ui.set("tab_visibility_enabled", false)
	leaderboard_ui.call("set_leaderboard_visible", true)
	_play_match_end_sound()
	final_match_summary = _build_match_summary()
	_schedule_match_end_dashboard_return()

func _on_match_saved(message: Dictionary) -> void:
	if message.is_empty():
		return

	var match_id := str(message.get("match_id", "")).strip_edges()
	var saved_room_id := str(message.get("room_id", "")).strip_edges()
	if match_id == "" or saved_room_id == "":
		return
	if bool(processed_match_saved_ids.get(match_id, false)):
		return

	var ended_message_variant: Variant = pending_match_ended_messages.get(match_id, {})
	if typeof(ended_message_variant) != TYPE_DICTIONARY:
		return

	var ended_message := ended_message_variant as Dictionary
	if str(ended_message.get("room_id", "")).strip_edges() != saved_room_id:
		return

	var payload := _build_match_saved_parent_payload(message, ended_message)
	if payload.is_empty():
		return

	_post_match_saved_to_parent(payload)
	processed_match_saved_ids[match_id] = true

func _freeze_match_play() -> void:
	if exit_dialog_open:
		exit_dialog_open = false
		if exit_dialog_layer != null:
			exit_dialog_layer.visible = false

	if player_body != null:
		player_body.set_match_controls_enabled(false)
	if weapons != null:
		weapons.set_input_enabled(false)
		weapons.clear_all_projectiles()

	for remote_wrapper_variant in remote_players.values():
		var remote_wrapper := remote_wrapper_variant as Node
		if remote_wrapper == null or not is_instance_valid(remote_wrapper):
			continue

		var remote_body := remote_wrapper.get_node_or_null("CharacterBody2D") as Player
		if remote_body != null:
			remote_body.set_match_controls_enabled(false)
			if remote_body.weapon != null:
				remote_body.weapon.clear_all_projectiles()

	_set_mouse_visible(true)

func _schedule_match_end_dashboard_return() -> void:
	if match_end_exit_scheduled:
		return

	match_end_exit_scheduled = true
	get_tree().create_timer(MATCH_END_LEADERBOARD_SECONDS).timeout.connect(_auto_return_to_dashboard_after_match_end)

func _auto_return_to_dashboard_after_match_end() -> void:
	if not match_has_ended:
		return

	if final_match_summary.is_empty():
		final_match_summary = _build_match_summary()

	_exit_to_dashboard("match_ended", final_match_summary)

func _reset_parent_after_exit() -> void:
	var parent_node := get_parent()
	if parent_node != null and parent_node.has_method("_reset_after_match_exit"):
		parent_node.call("_reset_after_match_exit")

func _build_match_summary() -> Dictionary:
	var stats := _get_local_leaderboard_stats()
	var elapsed_ms: int = maxi(Time.get_ticks_msec() - match_started_msec, 0)
	var resolved_room_id := room_id
	if resolved_room_id == "" and network_client != null:
		resolved_room_id = network_client.local_room_id

	return {
		"room_id": resolved_room_id,
		"player_id": local_player_id,
		"kills": int(stats.get("kills", 0)),
		"deaths": int(stats.get("deaths", 0)),
		"death": int(stats.get("deaths", 0)),
		"score": int(stats.get("score", 0)),
		"play_time_ms": elapsed_ms,
		"play_time_seconds": float(elapsed_ms) / 1000.0
	}

func _build_match_saved_parent_payload(match_saved_message: Dictionary, match_ended_message: Dictionary) -> Dictionary:
	var match_id := str(match_saved_message.get("match_id", "")).strip_edges()
	var room_id := str(match_saved_message.get("room_id", "")).strip_edges()
	if match_id == "" or room_id == "":
		return {}

	var leaderboard_variant: Variant = match_ended_message.get("leaderboard", [])
	if not (leaderboard_variant is Array):
		return {}

	var player_result := _get_local_match_result(leaderboard_variant as Array)
	if player_result.is_empty():
		return {}

	return {
		"type": "match_saved",
		"match_id": match_id,
		"score": int(player_result.get("score", 0)),
		"kills": int(player_result.get("kills", 0)),
		"deaths": int(player_result.get("deaths", 0)),
		"duration_seconds": int(NetworkClient.get_finite_int(match_ended_message.get("duration_seconds", 0), 0))
	}

func _get_local_match_result(leaderboard: Array) -> Dictionary:
	for entry_variant in leaderboard:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue

		var entry := entry_variant as Dictionary
		if str(entry.get("player_id", "")).strip_edges() != local_player_id.strip_edges():
			continue

		return {
			"player_id": local_player_id,
			"score": int(roundf(NetworkClient.get_finite_float(entry.get("score", 0), 0.0))),
			"kills": int(NetworkClient.get_finite_int(entry.get("kills", 0), 0)),
			"deaths": int(NetworkClient.get_finite_int(entry.get("deaths", 0), 0))
		}

	return {}

func _post_match_saved_to_parent(payload: Dictionary) -> void:
	if payload.is_empty() or not OS.has_feature("web"):
		return

	JavaScriptBridge.eval(
		"window.parent.postMessage(%s, window.location.origin);" % JSON.stringify(payload),
		false
	)

func _get_local_leaderboard_stats() -> Dictionary:
	if leaderboard_ui == null:
		return {
			"kills": 0,
			"deaths": 0,
			"score": 0
		}

	var entry_variant: Variant = leaderboard_ui.call("get_entry_for_player", local_player_id)
	if typeof(entry_variant) != TYPE_DICTIONARY:
		return {
			"kills": 0,
			"deaths": 0,
			"score": 0
		}

	var entry := entry_variant as Dictionary
	return {
		"kills": int(entry.get("kills", 0)),
		"deaths": int(entry.get("deaths", 0)),
		"score": int(entry.get("score", 0))
	}

func _on_bullet_spawn_received(message: Dictionary) -> void:
	if match_has_ended:
		return

	var player_id := str(message.get("player_id", ""))
	if player_id == "" or player_id == local_player_id:
		return

	var remote_body := _get_remote_player(player_id)
	if remote_body == null:
		remote_body = _get_or_create_remote_player(player_id)
	if remote_body == null:
		return

	var weapon_type := _get_bullet_weapon_type(message, remote_body)

	# Replay the server bullet using the shooter's weapon
	remote_body.spawn_remote_bullet_from_server(
		NetworkClient.get_finite_vector2(message, "x", "y", remote_body.global_position),
		NetworkClient.get_finite_float(message.get("angle", 0.0), 0.0),
		weapon_type,
		_get_bullet_target_position(message),
		_get_bullet_start_position(message)
	)

func _get_bullet_weapon_type(message: Dictionary, remote_body: Player) -> String:
	for key in ["weapon", "weapon_type", "weapon_id", "weapon_holding"]:
		if not message.has(key):
			continue

		var weapon_type := str(message[key]).strip_edges()
		if weapon_type != "":
			return weapon_type

	return remote_body.weapon.get_active_weapon().get_weapon_name() if remote_body.weapon != null and remote_body.weapon.get_active_weapon() != null else ""

func _get_bullet_start_position(message: Dictionary) -> Variant:
	# Support old and new server field names
	if NetworkClient.has_finite_vector2(message, "start_x", "start_y"):
		return NetworkClient.get_finite_vector2(message, "start_x", "start_y")

	if NetworkClient.has_finite_vector2(message, "muzzle_x", "muzzle_y"):
		return NetworkClient.get_finite_vector2(message, "muzzle_x", "muzzle_y")

	if NetworkClient.has_finite_vector2(message, "bullet_x", "bullet_y"):
		return NetworkClient.get_finite_vector2(message, "bullet_x", "bullet_y")

	var start_variant: Variant = message.get("start", message.get("muzzle", null))
	if typeof(start_variant) == TYPE_DICTIONARY:
		var start := start_variant as Dictionary
		if NetworkClient.has_finite_vector2(start, "x", "y"):
			return NetworkClient.get_finite_vector2(start, "x", "y")

	return null

func _get_bullet_target_position(message: Dictionary) -> Variant:
	if NetworkClient.has_finite_vector2(message, "target_x", "target_y"):
		return NetworkClient.get_finite_vector2(message, "target_x", "target_y")

	var target_variant: Variant = message.get("target", null)
	if typeof(target_variant) == TYPE_DICTIONARY:
		var target := target_variant as Dictionary
		if NetworkClient.has_finite_vector2(target, "x", "y"):
			return NetworkClient.get_finite_vector2(target, "x", "y")

	return null

func _get_or_create_remote_player(player_id: String, player_display_name: String = "") -> Player:
	var existing_remote := _get_remote_player(player_id)
	if existing_remote != null:
		return existing_remote

	# Spawn remote players from the same scene so visuals stay identical
	var remote_wrapper := PLAYER_SCENE.instantiate() as Node2D
	if remote_wrapper == null:
		return null

	remote_wrapper.name = "RemotePlayer_%s" % player_id
	var remote_body := remote_wrapper.get_node("CharacterBody2D") as Player
	if remote_body == null:
		remote_wrapper.queue_free()
		return null

	remote_body.configure_as_remote_proxy()
	remote_body.set_network_player_id(player_id)
	remote_body.set_network_player_display_name(player_display_name)
	add_child(remote_wrapper)
	remote_players[player_id] = remote_wrapper
	return remote_body

func _apply_local_player_state(message: Dictionary, should_apply_position: bool = true) -> void:
	if message.is_empty():
		return

	if should_apply_position and NetworkClient.has_finite_vector2(message, "x", "y"):
		# Trust server position when it sends one for the local player
		var authoritative_position := NetworkClient.get_finite_vector2(message, "x", "y")
		player_body.global_position = authoritative_position
		player_body.set_spawn_position(authoritative_position)

	var has_health := NetworkClient.has_authoritative_health(message)
	if has_health or message.has("is_dead"):
		var new_health := NetworkClient.get_authoritative_health(message, player_body.health)
		player_body.apply_authoritative_health_state(
			new_health,
			bool(message.get("is_dead", player_body.is_dead)),
			NetworkClient.get_finite_int(message.get("damage", 0), 0),
			NetworkClient.get_health_heal_amount(message, player_body.health, new_health),
			_get_health_feedback_source(message)
		)
		if NetworkClient.is_medkit_heal(message):
			_consume_collected_death_medkit(_get_health_packet_position(message, player_body))

func _get_remote_player(player_id: String) -> Player:
	var existing_wrapper := remote_players.get(player_id) as Node2D
	if existing_wrapper == null or not is_instance_valid(existing_wrapper):
		return null

	return existing_wrapper.get_node("CharacterBody2D") as Player

func _apply_initial_remote_players(message: Dictionary) -> void:
	if message.is_empty():
		return

	var players_variant: Variant = message.get("players", message.get("remote_players", []))
	if not (players_variant is Array):
		return

	for player_variant in players_variant:
		if typeof(player_variant) != TYPE_DICTIONARY:
			continue

		_apply_remote_player_state(player_variant)

func _apply_cached_remote_players() -> void:
	if network_client == null:
		return

	# Catch up remote players that moved before this scene existed
	for snapshot_variant in network_client.remote_player_snapshots.values():
		if typeof(snapshot_variant) != TYPE_DICTIONARY:
			continue

		_apply_remote_player_state(snapshot_variant)

func _apply_remote_player_state(message: Dictionary) -> void:
	var player_id := str(message.get("player_id", ""))
	if player_id == "" or player_id == local_player_id:
		return

	var remote_body := _get_remote_player(player_id)
	var has_position := NetworkClient.has_finite_vector2(message, "x", "y")
	if remote_body == null and not has_position:
		return

	var remote_display_name: String = network_client.get_player_display_name(message, player_id) if network_client != null else ""
	if remote_body == null:
		remote_body = _get_or_create_remote_player(player_id, remote_display_name)
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
	var authoritative_is_dead := bool(message.get("is_dead", remote_body.is_dead))
	if has_health:
		new_health = NetworkClient.get_authoritative_health(message, remote_body.health)
	if has_health and not message.has("is_dead"):
		authoritative_is_dead = new_health <= 0
	if has_health or message.has("is_dead"):
		remote_body.apply_authoritative_health_state(
			new_health,
			authoritative_is_dead,
			NetworkClient.get_finite_int(message.get("damage", 0), 0),
			NetworkClient.get_health_heal_amount(message, remote_body.health, new_health),
			_get_health_feedback_source(message)
		)
		if NetworkClient.is_medkit_heal(message):
			_consume_collected_death_medkit(_get_health_packet_position(message, remote_body))

	var aim_angle_degrees := NAN
	if message.has("angle"):
		aim_angle_degrees = NetworkClient.get_finite_float(message["angle"], NAN)
	elif message.has("rotation"):
		aim_angle_degrees = rad_to_deg(NetworkClient.get_finite_float(message["rotation"], 0.0))
	elif message.has("aim_angle"):
		aim_angle_degrees = NetworkClient.get_finite_float(message["aim_angle"], NAN)

	if has_position:
		var remote_position := NetworkClient.get_finite_vector2(message, "x", "y")
		var is_respawn_snap := was_dead and not authoritative_is_dead and has_health and new_health > 0
		if is_respawn_snap:
			# Respawns should appear immediately at the new spawn point
			remote_body.snap_remote_snapshot(remote_position, aim_angle_degrees)
		else:
			remote_body.enqueue_remote_snapshot(remote_position, aim_angle_degrees)
	elif not is_nan(aim_angle_degrees):
		remote_body.update_remote_angle(aim_angle_degrees)

func _get_health_feedback_source(message: Dictionary) -> String:
	return "medkit" if NetworkClient.is_medkit_heal(message) else NetworkClient.get_health_source(message)

func _get_health_packet_position(message: Dictionary, fallback_player: Player) -> Vector2:
	if NetworkClient.has_finite_vector2(message, "x", "y"):
		return NetworkClient.get_finite_vector2(message, "x", "y")

	return fallback_player.global_position if fallback_player != null else Vector2.ZERO

func _consume_collected_death_medkit(collector_position: Vector2) -> void:
	var closest_owner: Player = null
	var closest_distance := INF

	for owner in _get_players_with_death_medkits():
		var distance := owner.get_death_medkit_distance_to(collector_position)
		if distance < closest_distance:
			closest_distance = distance
			closest_owner = owner

	if closest_owner == null:
		return

	closest_owner.consume_death_medkit_near(collector_position)

func _get_players_with_death_medkits() -> Array[Player]:
	var players: Array[Player] = []
	var local_body := player_body as Player
	if local_body != null:
		players.append(local_body)

	for remote_wrapper_variant in remote_players.values():
		var remote_wrapper := remote_wrapper_variant as Node
		if remote_wrapper == null or not is_instance_valid(remote_wrapper):
			continue

		var remote_body := remote_wrapper.get_node_or_null("CharacterBody2D") as Player
		if remote_body != null:
			players.append(remote_body)

	return players

func _remove_remote_player(player_id: String) -> void:
	var remote_wrapper := remote_players.get(player_id) as Node2D
	if remote_wrapper == null:
		return

	remote_players.erase(player_id)
	if is_instance_valid(remote_wrapper):
		remote_wrapper.queue_free()

func _apply_leaderboard_snapshot(message: Dictionary) -> void:
	if message.is_empty() or not message.has("leaderboard"):
		return

	var leaderboard_variant: Variant = message.get("leaderboard", [])
	if leaderboard_variant is Array:
		leaderboard_ui.call("apply_server_leaderboard_snapshot", leaderboard_variant)

	_apply_player_display_names(message)

func _apply_player_display_names(message: Dictionary) -> void:
	if network_client == null:
		return

	player_body.set_network_player_display_name(network_client.get_local_player_display_name(message))

	for player_id_variant in remote_players.keys():
		var player_id := str(player_id_variant)
		var player_display_name := network_client.get_player_display_name(message, player_id)
		if player_display_name == "":
			continue

		var remote_body := _get_remote_player(player_id)
		if remote_body != null:
			remote_body.set_network_player_display_name(player_display_name)

func _cache_respawn_positions() -> void:
	respawn_positions.clear()

	# Read spawn markers from the hidden RespawnPoints layer
	var respawn_layer := _find_respawn_points_layer()
	if respawn_layer == null:
		push_error("Game: RespawnPoints TileMapLayer with light mask 20 and visibility layer 20 was not found.")
		return

	for cell in respawn_layer.get_used_cells():
		if not _is_respawn_tile(respawn_layer, cell):
			continue

		respawn_positions.append(respawn_layer.to_global(respawn_layer.map_to_local(cell)))

	if respawn_positions.is_empty():
		push_error("Game: RespawnPoints exists, but no valid respawn marker tiles were found.")

func _find_respawn_points_layer() -> TileMapLayer:
	if map == null:
		return null

	# The map scene keeps tile layers under StaticBody2D
	var respawn_layer := map.find_child("RespawnPoints", true, false) as TileMapLayer
	if respawn_layer == null:
		return null

	if respawn_layer.light_mask != RESPAWN_LAYER_20_MASK or respawn_layer.visibility_layer != RESPAWN_LAYER_20_MASK:
		return null

	return respawn_layer

func _is_respawn_tile(respawn_layer: TileMapLayer, cell: Vector2i) -> bool:
	return (
		respawn_layer.get_cell_source_id(cell) == RESPAWN_TILE_SOURCE_ID
		and respawn_layer.get_cell_atlas_coords(cell) == RESPAWN_TILE_ATLAS_COORDS
	)

func _get_random_respawn_position() -> Vector2:
	if respawn_positions.is_empty():
		push_error("Game: Cannot choose a respawn position because no valid respawn marker tiles are cached.")
		return player_body.spawn_position

	if respawn_positions.size() == 1:
		last_respawn_index = 0
		return respawn_positions[0]

	var next_index := respawn_rng.randi_range(0, respawn_positions.size() - 1)
	while next_index == last_respawn_index:
		# Avoid spawning twice in the exact same spot when possible
		next_index = respawn_rng.randi_range(0, respawn_positions.size() - 1)

	last_respawn_index = next_index
	return respawn_positions[next_index]
