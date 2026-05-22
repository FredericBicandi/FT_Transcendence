extends Node2D

const PLAYER_SCENE: PackedScene = preload("res://src/Objects/player.tscn")
const DEFAULT_CURSOR_TEXTURE: Texture2D = preload("res://Assets/Textures/cursor.png")
const KILL_FEED_RIFLE_TEXTURE: Texture2D = preload("res://Assets/Textures/Guns/AFRifle/image.png")
const RESPAWN_LAYER_20_MASK: int = 1 << 19
const RESPAWN_TILE_SOURCE_ID: int = 10
const RESPAWN_TILE_ATLAS_COORDS := Vector2i(25, 2)
const LOBBY_URL: String = "https://pixelfight.live/"
const EXIT_DIALOG_MIN_SIZE := Vector2(360.0, 150.0)
const ROCKET_LAUNCHER_WEAPON_NAME := "Rocket Launcher"
const KILL_FEED_ENTRY_LIFETIME: float = 4.0
const KILL_FEED_MAX_ENTRIES: int = 5
const KILL_FEED_KILLER_COLOR := Color(0.32, 0.66, 1.0, 1.0)
const KILL_FEED_KILLED_COLOR := Color(1.0, 0.28, 0.28, 1.0)
const MATCH_END_LEADERBOARD_SECONDS: float = 8.0

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
@onready var rocket_cursor: AnimatedSprite2D = $Cursor/AnimatedSprite2D
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
var kill_feed_layer: CanvasLayer
var kill_feed_container: VBoxContainer
var match_started_msec: int = 0
var final_match_summary: Dictionary = {}
var match_end_exit_scheduled: bool = false

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
	_create_default_cursor()
	weapons.active_weapon_changed.connect(_on_active_weapon_changed)
	_on_active_weapon_changed(weapons.get_active_weapon())
	_connect_network_signals()
	apply_network_snapshot()
	respawn_ui.call("update_for_player", player_body)
	timer_ui.call("set_remaining_seconds", remaining_match_seconds)
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	_create_kill_feed()
	_create_exit_dialog()
	if match_has_ended:
		_freeze_match_play()
		leaderboard_ui.set("tab_visibility_enabled", false)
		leaderboard_ui.call("set_leaderboard_visible", true)
		final_match_summary = _build_match_summary()
		_schedule_match_end_dashboard_return()

func _process(delta: float) -> void:
	# Tick the local timer between server sync messages
	if not match_has_ended and remaining_match_seconds > 0.0:
		remaining_match_seconds = maxf(remaining_match_seconds - delta, 0.0)

	respawn_ui.call("update_for_player", player_body)
	timer_ui.call("set_remaining_seconds", remaining_match_seconds)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
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
	title.text = "Leave game?"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	content.add_child(title)

	var body := Label.new()
	body.text = "Are you sure you want to leave the game?"
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(body)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	content.add_child(buttons)

	exit_cancel_button = Button.new()
	exit_cancel_button.text = "Cancel"
	exit_cancel_button.custom_minimum_size = Vector2(110.0, 34.0)
	exit_cancel_button.pressed.connect(_cancel_exit_dialog)
	buttons.add_child(exit_cancel_button)

	var yes_button := Button.new()
	yes_button.text = "Yes"
	yes_button.custom_minimum_size = Vector2(110.0, 34.0)
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
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
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
	Input.set_mouse_mode(mouse_mode_before_exit_dialog)

func _confirm_exit_dialog() -> void:
	if player_body != null:
		player_body.set_match_controls_enabled(false)
	if network_client != null:
		network_client.send_leave_match()

	_post_exit_game("manual")

func _post_exit_game(reason: String = "manual", summary: Dictionary = {}) -> void:
	if not OS.has_feature("web"):
		get_tree().quit()
		return

	var payload := {
		"type": "EXIT_GAME",
		"reason": reason
	}
	if not summary.is_empty():
		payload["matchSummary"] = summary
		payload["roomId"] = str(summary.get("roomId", ""))
		payload["room_id"] = str(summary.get("room_id", summary.get("roomId", "")))
		payload["playerId"] = str(summary.get("playerId", ""))
		payload["player_id"] = str(summary.get("player_id", summary.get("playerId", "")))
		payload["kills"] = int(summary.get("kills", 0))
		payload["deaths"] = int(summary.get("deaths", 0))
		payload["death"] = int(summary.get("death", summary.get("deaths", 0)))
		payload["score"] = int(summary.get("score", 0))
		payload["playTimeMs"] = int(summary.get("playTimeMs", 0))
		payload["playTimeSeconds"] = float(summary.get("playTimeSeconds", 0.0))

	JavaScriptBridge.eval(
		"window.parent.postMessage(%s, '*'); if (window.parent === window) { window.location.href = '%s'; }" % [JSON.stringify(payload), LOBBY_URL],
		false
	)

func _create_default_cursor() -> void:
	default_cursor = Sprite2D.new()
	default_cursor.name = "DefaultCursor"
	default_cursor.texture = DEFAULT_CURSOR_TEXTURE
	default_cursor.z_index = 10
	cursor.add_child(default_cursor)

func _set_cursor_for_weapon(weapon: BaseWeapon) -> void:
	var use_rocket_cursor := weapon != null and weapon.get_weapon_name() == ROCKET_LAUNCHER_WEAPON_NAME

	if default_cursor != null:
		default_cursor.visible = not use_rocket_cursor
	if rocket_cursor != null:
		rocket_cursor.visible = use_rocket_cursor
		if use_rocket_cursor and not rocket_cursor.is_playing():
			rocket_cursor.play("default")

func _create_kill_feed() -> void:
	kill_feed_layer = CanvasLayer.new()
	kill_feed_layer.name = "KillFeedLayer"
	kill_feed_layer.layer = 30
	add_child(kill_feed_layer)

	var anchor := Control.new()
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

func _on_kill_feed_received(message: Dictionary) -> void:
	var killer_name := _pick_kill_feed_name(message, ["killer", "killerName", "killer_name", "attacker", "attackerName"], "Unknown")
	var killed_name := _pick_kill_feed_name(message, ["killed", "killedName", "killed_name", "victim", "victimName"], "Unknown")
	if killer_name == "" or killed_name == "":
		return

	_show_kill_feed_entry(killer_name, killed_name)

func _show_kill_feed_entry(killer_name: String, killed_name: String) -> void:
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

	var icon := TextureRect.new()
	icon.texture = KILL_FEED_RIFLE_TEXTURE
	icon.custom_minimum_size = Vector2(28.0, 18.0)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	columns.add_child(icon)

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

	if not network_client.match_ended.is_connected(_on_match_ended):
		network_client.match_ended.connect(_on_match_ended)

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
	player_body.set_match_controls_enabled(not match_has_ended)
	_apply_leaderboard_snapshot(network_client.last_room_joined_message)
	_apply_local_player_state(network_client.last_room_joined_message, false)
	_apply_initial_remote_players(network_client.last_room_joined_message)
	_apply_cached_remote_players()

func _on_room_joined(message: Dictionary) -> void:
	if network_client != null and network_client.local_player_id != "":
		local_player_id = network_client.local_player_id
	else:
		local_player_id = str(message.get("playerId", message.get("id", "")))

	room_id = str(message.get("roomId", message.get("room_id", "")))
	player_body.set_network_player_id(local_player_id)
	player_body.set_network_player_display_name(network_client.get_local_player_display_name(message))
	leaderboard_ui.call("set_local_player_id", local_player_id)
	remaining_match_seconds = maxf(NetworkClient.get_finite_float(message.get("remainingSeconds", 0.0), 0.0), 0.0)
	match_has_ended = false
	player_body.set_match_controls_enabled(true)
	_apply_leaderboard_snapshot(message)
	_apply_local_player_state(message, false)
	_apply_initial_remote_players(message)

func _on_time_synced(message: Dictionary) -> void:
	var synced_room_id := str(message.get("roomId", message.get("room_id", "")))
	if room_id != "" and synced_room_id != "" and synced_room_id != room_id:
		# Ignore timer packets from an old room
		return

	if match_has_ended:
		_apply_leaderboard_snapshot(message)
		final_match_summary = _build_match_summary()
		return

	remaining_match_seconds = maxf(NetworkClient.get_finite_float(message.get("remainingSeconds", remaining_match_seconds), remaining_match_seconds), 0.0)
	_apply_leaderboard_snapshot(message)

func _on_leaderboard_updated(message: Dictionary) -> void:
	_apply_leaderboard_snapshot(message)
	if match_has_ended:
		final_match_summary = _build_match_summary()

func _on_player_move_received(message: Dictionary) -> void:
	if match_has_ended:
		return

	var player_id := str(message.get("playerId", message.get("id", "")))
	if player_id == "" or player_id == local_player_id:
		return

	_apply_remote_player_state(message)

func _on_player_left_received(player_id: String) -> void:
	_remove_remote_player(player_id)

func _on_player_angle_received(message: Dictionary) -> void:
	if match_has_ended:
		return

	var player_id := str(message.get("playerId", message.get("id", "")))
	var has_angle := (
		NetworkClient.is_finite_number(message.get("angle", NAN))
		or NetworkClient.is_finite_number(message.get("rotation", NAN))
		or NetworkClient.is_finite_number(message.get("aimAngle", NAN))
	)
	if player_id == "" or player_id == local_player_id or not has_angle:
		return

	_apply_remote_player_state(message)

func _on_player_weapon_switch_received(message: Dictionary) -> void:
	if match_has_ended:
		return

	var player_id := str(message.get("playerId", message.get("id", "")))
	if player_id == "" or player_id == local_player_id:
		return

	_apply_remote_player_state(message)

func _on_player_health_received(message: Dictionary) -> void:
	if match_has_ended:
		return

	var player_id := str(message.get("playerId", message.get("id", "")))
	if player_id == "":
		return

	if player_id == local_player_id:
		_apply_local_player_state(message, false)
		return

	_apply_remote_player_state(message)

func _on_match_ended(message: Dictionary) -> void:
	var ended_room_id := str(message.get("roomId", message.get("room_id", "")))
	if room_id != "" and ended_room_id != "" and ended_room_id != room_id:
		return

	match_has_ended = true
	remaining_match_seconds = 0.0
	_apply_leaderboard_snapshot(message)
	_freeze_match_play()
	leaderboard_ui.set("tab_visibility_enabled", false)
	leaderboard_ui.call("set_leaderboard_visible", true)
	final_match_summary = _build_match_summary()
	_schedule_match_end_dashboard_return()

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

	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

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

	if network_client != null:
		network_client.send_leave_match()

	_reset_parent_after_exit()
	_post_exit_game("match_ended", final_match_summary)

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
		"roomId": resolved_room_id,
		"room_id": resolved_room_id,
		"playerId": local_player_id,
		"player_id": local_player_id,
		"kills": int(stats.get("kills", 0)),
		"deaths": int(stats.get("deaths", 0)),
		"death": int(stats.get("deaths", 0)),
		"score": int(stats.get("score", 0)),
		"playTimeMs": elapsed_ms,
		"playTimeSeconds": float(elapsed_ms) / 1000.0
	}

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

	var player_id := str(message.get("playerId", message.get("id", "")))
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
	for key in ["weaponType", "weapon", "weapon_type", "weaponId", "weapon_id", "weaponHolding"]:
		if not message.has(key):
			continue

		var weapon_type := str(message[key]).strip_edges()
		if weapon_type != "":
			return weapon_type

	return remote_body.weapon.get_active_weapon().get_weapon_name() if remote_body.weapon != null and remote_body.weapon.get_active_weapon() != null else ""

func _get_bullet_start_position(message: Dictionary) -> Variant:
	# Support old and new server field names
	if NetworkClient.has_finite_vector2(message, "startX", "startY"):
		return NetworkClient.get_finite_vector2(message, "startX", "startY")

	if NetworkClient.has_finite_vector2(message, "muzzleX", "muzzleY"):
		return NetworkClient.get_finite_vector2(message, "muzzleX", "muzzleY")

	if NetworkClient.has_finite_vector2(message, "bulletX", "bulletY"):
		return NetworkClient.get_finite_vector2(message, "bulletX", "bulletY")

	var start_variant: Variant = message.get("start", message.get("muzzle", null))
	if typeof(start_variant) == TYPE_DICTIONARY:
		var start := start_variant as Dictionary
		if NetworkClient.has_finite_vector2(start, "x", "y"):
			return NetworkClient.get_finite_vector2(start, "x", "y")

	return null

func _get_bullet_target_position(message: Dictionary) -> Variant:
	if NetworkClient.has_finite_vector2(message, "targetX", "targetY"):
		return NetworkClient.get_finite_vector2(message, "targetX", "targetY")

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

	if message.has("health") or message.has("isDead"):
		player_body.apply_authoritative_health_state(
			NetworkClient.get_finite_int(message.get("health", player_body.health), player_body.health),
			bool(message.get("isDead", player_body.is_dead)),
			NetworkClient.get_finite_int(message.get("damage", 0), 0)
		)

func _get_remote_player(player_id: String) -> Player:
	var existing_wrapper := remote_players.get(player_id) as Node2D
	if existing_wrapper == null or not is_instance_valid(existing_wrapper):
		return null

	return existing_wrapper.get_node("CharacterBody2D") as Player

func _apply_initial_remote_players(message: Dictionary) -> void:
	if message.is_empty():
		return

	var players_variant: Variant = message.get("players", message.get("remotePlayers", []))
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
	var player_id := str(message.get("playerId", message.get("id", "")))
	if player_id == "" or player_id == local_player_id:
		return

	var remote_body := _get_remote_player(player_id)
	var has_position := NetworkClient.has_finite_vector2(message, "x", "y")
	if remote_body == null and not has_position:
		return

	var remote_display_name := network_client.get_player_display_name(message, player_id) if network_client != null else ""
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

	var authoritative_is_dead := bool(message.get("isDead", remote_body.is_dead))
	if message.has("health") and not message.has("isDead"):
		authoritative_is_dead = NetworkClient.get_finite_int(message["health"], remote_body.health) <= 0
	if message.has("health"):
		remote_body.apply_authoritative_health_state(
			NetworkClient.get_finite_int(message["health"], remote_body.health),
			authoritative_is_dead,
			NetworkClient.get_finite_int(message.get("damage", 0), 0)
		)

	var aim_angle_degrees := NAN
	if message.has("angle"):
		aim_angle_degrees = NetworkClient.get_finite_float(message["angle"], NAN)
	elif message.has("rotation"):
		aim_angle_degrees = rad_to_deg(NetworkClient.get_finite_float(message["rotation"], 0.0))
	elif message.has("aimAngle"):
		aim_angle_degrees = NetworkClient.get_finite_float(message["aimAngle"], NAN)

	if has_position:
		var remote_position := NetworkClient.get_finite_vector2(message, "x", "y")
		var is_respawn_snap := was_dead and not authoritative_is_dead and message.has("health") and NetworkClient.get_finite_int(message["health"], 0) > 0
		if is_respawn_snap:
			# Respawns should appear immediately at the new spawn point
			remote_body.snap_remote_snapshot(remote_position, aim_angle_degrees)
		else:
			remote_body.enqueue_remote_snapshot(remote_position, aim_angle_degrees)
	elif not is_nan(aim_angle_degrees):
		remote_body.update_remote_angle(aim_angle_degrees)

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
