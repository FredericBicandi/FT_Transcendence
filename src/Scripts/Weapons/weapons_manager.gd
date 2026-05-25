class_name WeaponsManager
extends Node2D

const SWITCH_WEAPON_SOUND: AudioStream = preload("res://Assets/Audio/Weapons/switch_weapon.ogg")

# Let HUD and networking know when the active weapon changes
signal active_weapon_changed(weapon: BaseWeapon)

# This uses the scene node name, not the WeaponData id
@export var default_weapon_node: StringName = &"Sniper"
@export var input_enabled: bool = true
@export var switch_sound_volume_db: float = -4.0
@export var switch_sound_enabled: bool = true

# Keep lookup fast for scene names, weapon ids, and scroll order
var active_weapon: BaseWeapon
var weapons_by_node_name: Dictionary = {}
var weapons_by_id: Dictionary = {}
var weapon_order: Array[StringName] = []
var previous_weapon_name: StringName = &""
var switch_audio_player: AudioStreamPlayer2D

func _ready() -> void:
	switch_audio_player = AudioStreamPlayer2D.new()
	switch_audio_player.stream = SWITCH_WEAPON_SOUND
	switch_audio_player.volume_db = switch_sound_volume_db
	add_child(switch_audio_player)

	# Let the scene decide which weapons exist
	for child in get_children():
		if child is BaseWeapon:
			register_weapon(child)

	# Fall back to any weapon so the player is never empty-handed
	if not equip_weapon(default_weapon_node) and not weapons_by_node_name.is_empty():
		var first_weapon_name: StringName = weapons_by_node_name.keys()[0]
		equip_weapon(first_weapon_name)

func register_weapon(weapon: BaseWeapon) -> void:
	# Support both scene names and gameplay names when equipping
	weapons_by_node_name[weapon.name] = weapon
	weapons_by_id[weapon.weapon_id] = weapon
	weapon_order.append(StringName(weapon.name))
	weapon.set_active(false)

func equip_weapon(weapon_key: StringName) -> bool:
	# Accept either a scene node name or a weapon id
	var next_weapon: BaseWeapon = weapons_by_node_name.get(weapon_key)

	if next_weapon == null:
		next_weapon = weapons_by_id.get(String(weapon_key))

	if next_weapon == null:
		return false

	if active_weapon == next_weapon:
		return true

	var previous_weapon: BaseWeapon = active_weapon
	if previous_weapon != null:
		previous_weapon_name = StringName(previous_weapon.name)

	# Keep only one weapon visible and controllable
	if active_weapon != null and is_instance_valid(active_weapon):
		active_weapon.set_active(false)

	active_weapon = next_weapon
	active_weapon.set_active(true)
	active_weapon.set_input_enabled(input_enabled)
	if input_enabled and Input.is_action_pressed("click"):
		active_weapon.lock_fire_until_click_released()
	active_weapon_changed.emit(active_weapon)
	if previous_weapon != null:
		_play_switch_sound()
	return true

func equip_weapon_by_id(next_weapon_id: String) -> bool:
	var next_weapon: BaseWeapon = weapons_by_id.get(next_weapon_id)

	if next_weapon == null:
		return false

	return equip_weapon(StringName(next_weapon.name))

func update_movement(direction: Vector2) -> void:
	# Let the weapon sway with the player movement
	if active_weapon != null:
		active_weapon.update_movement(direction)

func _unhandled_input(event: InputEvent) -> void:
	# Let menus or match state disable weapon switching
	if not input_enabled:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if is_previous_weapon_key(event):
			equip_previous_weapon()
			get_viewport().set_input_as_handled()
			return

		var weapon_slot := get_weapon_slot_from_key(event)
		if weapon_slot != -1:
			equip_weapon_slot(weapon_slot)
			get_viewport().set_input_as_handled()

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			cycle_weapon(-1)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			cycle_weapon(1)
			get_viewport().set_input_as_handled()

func get_aim_frame() -> int:
	# Share the weapon aim frame with the head animation
	if active_weapon != null:
		return active_weapon.get_aim_frame()

	return 0

func get_active_weapon() -> BaseWeapon:
	return active_weapon

func set_input_enabled(is_enabled: bool) -> void:
	input_enabled = is_enabled
	if active_weapon != null:
		active_weapon.set_input_enabled(is_enabled)
		if is_enabled and Input.is_action_pressed("click"):
			active_weapon.lock_fire_until_click_released()

func set_switch_sound_enabled(is_enabled: bool) -> void:
	switch_sound_enabled = is_enabled

func clear_all_projectiles() -> void:
	# Clear every weapon so hidden bullets do not survive respawn
	for weapon_variant in weapons_by_node_name.values():
		var weapon := weapon_variant as BaseWeapon
		if weapon != null:
			weapon.reset_state()

func cycle_weapon(step: int) -> void:
	# Wrap scroll wheel switching around the weapon list
	if weapon_order.is_empty():
		return

	var current_index := weapon_order.find(StringName(active_weapon.name)) if active_weapon != null else -1
	if current_index == -1:
		current_index = 0

	var next_index := posmod(current_index + step, weapon_order.size())
	equip_weapon(weapon_order[next_index])

func equip_previous_weapon() -> void:
	if previous_weapon_name == &"":
		return

	if not weapons_by_node_name.has(previous_weapon_name):
		previous_weapon_name = &""
		return

	equip_weapon(previous_weapon_name)

func get_weapons_in_order() -> Array[BaseWeapon]:
	var ordered_weapons: Array[BaseWeapon] = []
	for weapon_name in weapon_order:
		var weapon := weapons_by_node_name.get(weapon_name) as BaseWeapon
		if weapon != null:
			ordered_weapons.append(weapon)

	return ordered_weapons

func equip_weapon_slot(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= weapon_order.size():
		return

	equip_weapon(weapon_order[slot_index])

func get_weapon_slot_from_key(event: InputEventKey) -> int:
	var keycode := event.physical_keycode
	if keycode == 0:
		keycode = event.keycode

	match keycode:
		KEY_1, KEY_KP_1:
			return 0
		KEY_2, KEY_KP_2:
			return 1
		KEY_3, KEY_KP_3:
			return 2
		KEY_4, KEY_KP_4:
			return 3
		KEY_5, KEY_KP_5:
			return 4
		KEY_6, KEY_KP_6:
			return 5
		KEY_7, KEY_KP_7:
			return 6
		KEY_8, KEY_KP_8:
			return 7
		KEY_9, KEY_KP_9:
			return 8
		KEY_0, KEY_KP_0:
			return 9

	return -1

func is_previous_weapon_key(event: InputEventKey) -> bool:
	var keycode := event.physical_keycode
	if keycode == 0:
		keycode = event.keycode

	return keycode == KEY_Q

func _play_switch_sound() -> void:
	if not switch_sound_enabled:
		return

	if switch_audio_player == null or SWITCH_WEAPON_SOUND == null:
		return

	switch_audio_player.stop()
	switch_audio_player.play()
