extends Node2D

const PLAYER_SCENE: PackedScene = preload("res://src/Objects/player.tscn")
const RESPAWN_LAYER_20_MASK: int = 1 << 19
const RESPAWN_TILE_SOURCE_ID: int = 10
const RESPAWN_TILE_ATLAS_COORDS := Vector2i(25, 2)

# Cache scene nodes once so gameplay updates stay cheap
@onready var map: Node2D = $Map
@onready var player = $Player
@onready var player_body = $Player/CharacterBody2D
@onready var weapons: WeaponsManager = $Player/CharacterBody2D/Weapons
@onready var weapon_switcher_ui: Node = $WeaponSwitcher
@onready var respawn_ui: Node = $RespawnUi
@onready var timer_ui: Node = $Timer
@onready var leaderboard_ui: Node = $Leaderboard
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

func _ready() -> void:
	respawn_rng.randomize()
	_cache_respawn_positions()
	# Let the map own spawn points instead of hardcoding them in the player
	player_body.set_respawn_position_provider(Callable(self, "_get_random_respawn_position"))
	var initial_respawn_position := _get_random_respawn_position()
	player_body.set_spawn_position(initial_respawn_position)
	player_body.global_position = initial_respawn_position

	# Keep the HUD attached to the currently equipped weapon
	weapons.active_weapon_changed.connect(_on_active_weapon_changed)
	_on_active_weapon_changed(weapons.get_active_weapon())
	_connect_network_signals()
	apply_network_snapshot()
	respawn_ui.call("update_for_player", player_body)
	timer_ui.call("set_remaining_seconds", remaining_match_seconds)
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)

func _process(delta: float) -> void:
	# Tick the local timer between server sync messages
	if not match_has_ended and remaining_match_seconds > 0.0:
		remaining_match_seconds = maxf(remaining_match_seconds - delta, 0.0)

	respawn_ui.call("update_for_player", player_body)
	timer_ui.call("set_remaining_seconds", remaining_match_seconds)

func _on_active_weapon_changed(weapon: BaseWeapon) -> void:
	# Stop listening to the old weapon before tracking the new one
	if observed_weapon != null and observed_weapon.ammo_changed.is_connected(_on_ammo_changed):
		observed_weapon.ammo_changed.disconnect(_on_ammo_changed)

	observed_weapon = weapon

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

	if not network_client.match_ended.is_connected(_on_match_ended):
		network_client.match_ended.connect(_on_match_ended)

func apply_network_snapshot() -> void:
	if network_client == null:
		return

	# Rebuild local state from data received before the game scene loaded
	local_player_id = network_client.local_player_id
	room_id = network_client.local_room_id
	player_body.set_network_player_id(local_player_id)
	leaderboard_ui.call("set_local_player_id", local_player_id)
	remaining_match_seconds = maxf(network_client.remaining_seconds, 0.0)
	match_has_ended = network_client.match_finished
	player_body.set_match_controls_enabled(not match_has_ended)
	_apply_leaderboard_snapshot(network_client.last_room_joined_message)
	_apply_local_player_state(network_client.last_room_joined_message, false)
	_apply_initial_remote_players(network_client.last_room_joined_message)
	_apply_cached_remote_players()

func _on_room_joined(message: Dictionary) -> void:
	local_player_id = str(message.get("playerId", ""))
	room_id = str(message.get("roomId", ""))
	player_body.set_network_player_id(local_player_id)
	leaderboard_ui.call("set_local_player_id", local_player_id)
	remaining_match_seconds = maxf(float(message.get("remainingSeconds", 0.0)), 0.0)
	match_has_ended = false
	player_body.set_match_controls_enabled(true)
	_apply_leaderboard_snapshot(message)
	_apply_local_player_state(message, false)
	_apply_initial_remote_players(message)

func _on_time_synced(message: Dictionary) -> void:
	var synced_room_id := str(message.get("roomId", ""))
	if room_id != "" and synced_room_id != "" and synced_room_id != room_id:
		# Ignore timer packets from an old room
		return

	remaining_match_seconds = maxf(float(message.get("remainingSeconds", remaining_match_seconds)), 0.0)
	_apply_leaderboard_snapshot(message)

func _on_player_move_received(message: Dictionary) -> void:
	var player_id := str(message.get("playerId", ""))
	if player_id == "" or player_id == local_player_id:
		return

	_apply_remote_player_state(message)

func _on_player_left_received(player_id: String) -> void:
	_remove_remote_player(player_id)

func _on_player_angle_received(message: Dictionary) -> void:
	var player_id := str(message.get("playerId", ""))
	if player_id == "" or player_id == local_player_id or not message.has("angle"):
		return

	_apply_remote_player_state(message)

func _on_player_weapon_switch_received(message: Dictionary) -> void:
	var player_id := str(message.get("playerId", ""))
	if player_id == "" or player_id == local_player_id:
		return

	_apply_remote_player_state(message)

func _on_player_health_received(message: Dictionary) -> void:
	var player_id := str(message.get("playerId", message.get("id", "")))
	if player_id == "":
		return

	if player_id == local_player_id:
		_apply_local_player_state(message, false)
		return

	_apply_remote_player_state(message)

func _on_match_ended(message: Dictionary) -> void:
	var ended_room_id := str(message.get("roomId", ""))
	if room_id != "" and ended_room_id != "" and ended_room_id != room_id:
		return

	match_has_ended = true
	remaining_match_seconds = 0.0
	player_body.set_match_controls_enabled(false)
	_apply_leaderboard_snapshot(message)

func _on_bullet_spawn_received(message: Dictionary) -> void:
	var player_id := str(message.get("playerId", ""))
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
		Vector2(float(message.get("x", remote_body.global_position.x)), float(message.get("y", remote_body.global_position.y))),
		float(message.get("angle", 0.0)),
		weapon_type,
		_get_bullet_target_position(message),
		_get_bullet_start_position(message)
	)

func _get_bullet_weapon_type(message: Dictionary, remote_body: Player) -> String:
	for key in ["weaponType", "weapon", "weapon_type", "weaponId", "weapon_id", "weaponHolding"]:
		if not message.has(key):
			continue

		var weapon_type := str(message[key])
		if weapon_type != "":
			return weapon_type

	return remote_body.weapon.get_active_weapon().get_weapon_name() if remote_body.weapon != null and remote_body.weapon.get_active_weapon() != null else ""

func _get_bullet_start_position(message: Dictionary) -> Variant:
	# Support old and new server field names
	if message.has("startX") and message.has("startY"):
		return Vector2(float(message["startX"]), float(message["startY"]))

	if message.has("muzzleX") and message.has("muzzleY"):
		return Vector2(float(message["muzzleX"]), float(message["muzzleY"]))

	if message.has("bulletX") and message.has("bulletY"):
		return Vector2(float(message["bulletX"]), float(message["bulletY"]))

	var start_variant: Variant = message.get("start", message.get("muzzle", null))
	if typeof(start_variant) == TYPE_DICTIONARY:
		var start := start_variant as Dictionary
		if start.has("x") and start.has("y"):
			return Vector2(float(start["x"]), float(start["y"]))

	return null

func _get_bullet_target_position(message: Dictionary) -> Variant:
	if message.has("targetX") and message.has("targetY"):
		return Vector2(float(message["targetX"]), float(message["targetY"]))

	if message.has("target_x") and message.has("target_y"):
		return Vector2(float(message["target_x"]), float(message["target_y"]))

	var target_variant: Variant = message.get("target", null)
	if typeof(target_variant) == TYPE_DICTIONARY:
		var target := target_variant as Dictionary
		if target.has("x") and target.has("y"):
			return Vector2(float(target["x"]), float(target["y"]))

	return null

func _get_or_create_remote_player(player_id: String) -> Player:
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
	add_child(remote_wrapper)
	remote_players[player_id] = remote_wrapper
	return remote_body

func _apply_local_player_state(message: Dictionary, should_apply_position: bool = true) -> void:
	if message.is_empty():
		return

	if should_apply_position and message.has("x") and message.has("y"):
		# Trust server position when it sends one for the local player
		var authoritative_position := Vector2(float(message["x"]), float(message["y"]))
		player_body.global_position = authoritative_position
		player_body.set_spawn_position(authoritative_position)

	if message.has("health") or message.has("isDead"):
		player_body.apply_authoritative_health_state(
			int(message.get("health", player_body.health)),
			bool(message.get("isDead", player_body.is_dead)),
			int(message.get("damage", 0))
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
	var has_position := message.has("x") and message.has("y")
	if remote_body == null and not has_position:
		return

	if remote_body == null:
		remote_body = _get_or_create_remote_player(player_id)
	if remote_body == null:
		return

	var was_dead := remote_body.is_dead
	var weapon_type := str(message.get("weaponType", message.get("weaponHolding", message.get("weapon", ""))))
	if weapon_type != "":
		remote_body.set_remote_weapon(weapon_type)

	var authoritative_is_dead := bool(message.get("isDead", remote_body.is_dead))
	if message.has("health") and not message.has("isDead"):
		authoritative_is_dead = int(message["health"]) <= 0
	if message.has("health"):
		remote_body.apply_authoritative_health_state(
			int(message["health"]),
			authoritative_is_dead,
			int(message.get("damage", 0))
		)

	var aim_angle_degrees := NAN
	if message.has("angle"):
		aim_angle_degrees = float(message["angle"])
	elif message.has("rotation"):
		aim_angle_degrees = rad_to_deg(float(message["rotation"]))
	elif message.has("aimAngle"):
		aim_angle_degrees = float(message["aimAngle"])

	if has_position:
		var remote_position := Vector2(float(message["x"]), float(message["y"]))
		var is_respawn_snap := was_dead and not authoritative_is_dead and message.has("health") and int(message["health"]) > 0
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
