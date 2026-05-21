extends Node

const LEADERBOARD_GOLD := Color(1, 0.862745, 0.486275, 1)
const LEADERBOARD_WHITE := Color(1, 1, 1, 1)
const LEADERBOARD_COLUMNS := [
	{"key": "player_name", "title": "Player Name", "alignment": HORIZONTAL_ALIGNMENT_LEFT, "width": 340.0},
	{"key": "kills", "title": "Kills", "alignment": HORIZONTAL_ALIGNMENT_CENTER, "width": 120.0},
	{"key": "deaths", "title": "Deaths", "alignment": HORIZONTAL_ALIGNMENT_CENTER, "width": 120.0},
	{"key": "score", "title": "Score", "alignment": HORIZONTAL_ALIGNMENT_CENTER, "width": 120.0}
]

@export var tab_visibility_enabled: bool = true
@export var initially_visible: bool = false
@export var panel_minimum_size: Vector2 = Vector2(820, 560)

@onready var leaderboard_overlay: ColorRect = $CanvasLayer/LeaderboardOverlay
@onready var leaderboard_panel: PanelContainer = $CanvasLayer/LeaderboardOverlay/CenterContainer/LeaderboardPanel
@onready var leaderboard_rows_container: VBoxContainer = $CanvasLayer/LeaderboardOverlay/CenterContainer/LeaderboardPanel/MarginContainer/VBoxContainer/RowsPanel/RowsMargin/RowsContainer
@onready var leaderboard_header_labels: Array[Label] = [
	$CanvasLayer/LeaderboardOverlay/CenterContainer/LeaderboardPanel/MarginContainer/VBoxContainer/HeaderPanel/HeaderMargin/HeaderColumns/PlayerNameHeader,
	$CanvasLayer/LeaderboardOverlay/CenterContainer/LeaderboardPanel/MarginContainer/VBoxContainer/HeaderPanel/HeaderMargin/HeaderColumns/KillsHeader,
	$CanvasLayer/LeaderboardOverlay/CenterContainer/LeaderboardPanel/MarginContainer/VBoxContainer/HeaderPanel/HeaderMargin/HeaderColumns/DeathsHeader,
	$CanvasLayer/LeaderboardOverlay/CenterContainer/LeaderboardPanel/MarginContainer/VBoxContainer/HeaderPanel/HeaderMargin/HeaderColumns/ScoreHeader
]

var leaderboard_entries: Array[Dictionary] = []
var local_player_id: String = ""


func _ready() -> void:
	leaderboard_panel.custom_minimum_size = panel_minimum_size
	_configure_leaderboard_header()
	clear_leaderboard_entries()
	set_leaderboard_visible(initially_visible)


func _input(event: InputEvent) -> void:
	if not tab_visibility_enabled:
		return

	if event is InputEventKey and event.keycode == KEY_TAB and not event.echo:
		set_leaderboard_visible(event.pressed)
		get_viewport().set_input_as_handled()


func set_local_player_id(player_id: String) -> void:
	local_player_id = player_id
	_refresh_leaderboard_rows()


func set_leaderboard_visible(is_visible: bool) -> void:
	leaderboard_overlay.visible = is_visible


func set_leaderboard_entries(entries: Array) -> void:
	leaderboard_entries.clear()

	for entry_variant in entries:
		# Skip broken server entries instead of crashing the HUD
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue

		leaderboard_entries.append(_normalize_leaderboard_entry(entry_variant as Dictionary))

	leaderboard_entries.sort_custom(_sort_leaderboard_entries)
	_refresh_leaderboard_rows()


func apply_server_leaderboard_snapshot(entries: Array) -> void:
	set_leaderboard_entries(entries)

func get_entry_for_player(player_id: String) -> Dictionary:
	var normalized_player_id := player_id.strip_edges()
	if normalized_player_id == "":
		return {}

	for entry in leaderboard_entries:
		if str(entry.get("player_id", "")).strip_edges() == normalized_player_id:
			return entry.duplicate(true)

	return {}


func update_leaderboard_entry(entry: Dictionary) -> void:
	var normalized_entry := _normalize_leaderboard_entry(entry)
	var player_id := str(normalized_entry.get("player_id", ""))

	for index in leaderboard_entries.size():
		if str(leaderboard_entries[index].get("player_id", "")) == player_id:
			leaderboard_entries[index] = normalized_entry
			leaderboard_entries.sort_custom(_sort_leaderboard_entries)
			_refresh_leaderboard_rows()
			return

	leaderboard_entries.append(normalized_entry)
	leaderboard_entries.sort_custom(_sort_leaderboard_entries)
	_refresh_leaderboard_rows()


func clear_leaderboard_entries() -> void:
	leaderboard_entries.clear()
	_refresh_leaderboard_rows()


func _configure_leaderboard_header() -> void:
	for index in mini(leaderboard_header_labels.size(), LEADERBOARD_COLUMNS.size()):
		var label := leaderboard_header_labels[index]
		var column: Dictionary = LEADERBOARD_COLUMNS[index]
		label.custom_minimum_size = Vector2(float(column["width"]), 0.0)
		label.size_flags_horizontal = 0
		label.text = str(column["title"])
		label.horizontal_alignment = int(column["alignment"])


func _refresh_leaderboard_rows() -> void:
	for child in leaderboard_rows_container.get_children():
		child.queue_free()

	if leaderboard_entries.is_empty():
		var empty_state := Label.new()
		empty_state.text = "No players in the leaderboard yet."
		empty_state.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_state.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
		empty_state.add_theme_font_size_override("font_size", 18)
		leaderboard_rows_container.add_child(empty_state)
		return

	for entry in leaderboard_entries:
		var row := _create_leaderboard_row(entry)
		leaderboard_rows_container.add_child(row)


func _create_leaderboard_row(entry: Dictionary) -> Control:
	var row_margin := MarginContainer.new()
	row_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_margin.add_theme_constant_override("margin_left", 14)
	row_margin.add_theme_constant_override("margin_top", 10)
	row_margin.add_theme_constant_override("margin_right", 14)
	row_margin.add_theme_constant_override("margin_bottom", 10)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 12)
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_margin.add_child(columns)

	for column in LEADERBOARD_COLUMNS:
		var typed_column: Dictionary = column
		var label := Label.new()
		label.custom_minimum_size = Vector2(float(typed_column["width"]), 0.0)
		label.size_flags_horizontal = 0
		label.add_theme_color_override("font_color", _get_leaderboard_label_color(entry, str(typed_column["key"])))
		label.add_theme_font_size_override("font_size", 17)
		label.text = str(entry.get(str(typed_column["key"]), ""))
		label.horizontal_alignment = int(typed_column["alignment"])
		columns.add_child(label)

	return row_margin


func _normalize_leaderboard_entry(entry: Dictionary) -> Dictionary:
	# Accept both server naming styles so old payloads still work
	var normalized_player_name := _get_first_non_empty_entry_string(
		entry,
		["player_name", "playerName", "display_name", "displayName", "username", "name", "nickname"],
		"Unknown"
	)
	var normalized_player_id := _get_first_non_empty_entry_string(
		entry,
		["player_id", "playerId", "user_id", "userId", "id"],
		normalized_player_name
	)

	return {
		"player_id": normalized_player_id,
		"player_name": normalized_player_name,
		"kills": int(entry.get("kills", 0)),
		"deaths": int(entry.get("deaths", entry.get("death", 0))),
		"score": int(entry.get("score", 0))
	}


func _get_first_non_empty_entry_string(entry: Dictionary, keys: Array[String], fallback: String) -> String:
	for key in keys:
		if not entry.has(key):
			continue

		var value := str(entry[key]).strip_edges()
		if value != "":
			return value

	return fallback


func _get_leaderboard_label_color(entry: Dictionary, column_key: String) -> Color:
	if column_key == "player_name" and _is_local_leaderboard_entry(entry):
		return LEADERBOARD_GOLD

	return LEADERBOARD_WHITE


func _is_local_leaderboard_entry(entry: Dictionary) -> bool:
	var entry_player_id := str(entry.get("player_id", ""))
	return local_player_id != "" and entry_player_id == local_player_id


func _sort_leaderboard_entries(left: Dictionary, right: Dictionary) -> bool:
	# Score wins first, then kills, deaths, and name keep the order stable
	var left_score := int(left.get("score", 0))
	var right_score := int(right.get("score", 0))
	if left_score != right_score:
		return left_score > right_score

	var left_kills := int(left.get("kills", 0))
	var right_kills := int(right.get("kills", 0))
	if left_kills != right_kills:
		return left_kills > right_kills

	var left_deaths := int(left.get("deaths", 0))
	var right_deaths := int(right.get("deaths", 0))
	if left_deaths != right_deaths:
		return left_deaths < right_deaths

	return str(left.get("player_name", "")) < str(right.get("player_name", ""))
