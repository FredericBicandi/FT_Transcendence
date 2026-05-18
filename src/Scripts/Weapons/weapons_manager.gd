class_name WeaponsManager
extends Node2D

# Let HUD and networking know when the active weapon changes
signal active_weapon_changed(weapon: BaseWeapon)

# This uses the scene node name, not the WeaponData id
@export var default_weapon_node: StringName = &"Sniper"
@export var input_enabled: bool = true

# Keep lookup fast for scene names, weapon ids, and scroll order
var active_weapon: BaseWeapon
var weapons_by_node_name: Dictionary = {}
var weapons_by_id: Dictionary = {}
var weapon_order: Array[StringName] = []

func _ready() -> void:
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

	# Keep only one weapon visible and controllable
	if active_weapon != null and is_instance_valid(active_weapon):
		active_weapon.set_active(false)

	active_weapon = next_weapon
	active_weapon.set_active(true)
	active_weapon_changed.emit(active_weapon)
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
