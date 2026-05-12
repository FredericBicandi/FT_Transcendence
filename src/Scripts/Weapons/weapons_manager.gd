class_name WeaponsManager
extends Node2D

# Other systems can react when the player equips a different weapon.
signal active_weapon_changed(weapon: BaseWeapon)

# default_weapon_node uses the scene node name, not the weapon_id from WeaponData.
@export var default_weapon_node: StringName = &"Sniper"
@export var input_enabled: bool = true

# These collections let the manager look weapons up by node name, by gameplay id, and by cycle order.
var active_weapon: BaseWeapon
var weapons_by_node_name: Dictionary = {}
var weapons_by_id: Dictionary = {}
var weapon_order: Array[StringName] = []

func _ready() -> void:
	# Auto-register every BaseWeapon child placed under this manager in the scene.
	for child in get_children():
		if child is BaseWeapon:
			register_weapon(child)

	# Try the requested default weapon first, then fall back to the first registered one.
	if not equip_weapon(default_weapon_node) and not weapons_by_node_name.is_empty():
		var first_weapon_name: StringName = weapons_by_node_name.keys()[0]
		equip_weapon(first_weapon_name)

func register_weapon(weapon: BaseWeapon) -> void:
	# Keep multiple lookup paths so other code can equip by scene name or by weapon id.
	weapons_by_node_name[weapon.name] = weapon
	weapons_by_id[weapon.weapon_id] = weapon
	weapon_order.append(StringName(weapon.name))
	weapon.set_active(false)

func equip_weapon(weapon_key: StringName) -> bool:
	# Accept either a node name or a weapon id and resolve it to the actual weapon node.
	var next_weapon: BaseWeapon = weapons_by_node_name.get(weapon_key)

	if next_weapon == null:
		next_weapon = weapons_by_id.get(String(weapon_key))

	if next_weapon == null:
		return false

	if active_weapon == next_weapon:
		return true

	# Only one weapon stays active at a time, so hide the previous one before switching.
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
	# Forward the owner's movement direction so the equipped weapon can sway correctly.
	if active_weapon != null:
		active_weapon.update_movement(direction)

func _unhandled_input(event: InputEvent) -> void:
	# Mouse wheel switches weapons unless another system disabled manager input.
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
	# Exposes the current 8-direction aim frame for animation syncing elsewhere.
	if active_weapon != null:
		return active_weapon.get_aim_frame()

	return 0

func get_active_weapon() -> BaseWeapon:
	return active_weapon

func set_input_enabled(is_enabled: bool) -> void:
	input_enabled = is_enabled

func clear_all_projectiles() -> void:
	# Reset every registered weapon, not just the equipped one, so no stray bullets remain.
	for weapon_variant in weapons_by_node_name.values():
		var weapon := weapon_variant as BaseWeapon
		if weapon != null:
			weapon.reset_state()

func cycle_weapon(step: int) -> void:
	# Move forward or backward through the registration order and wrap around the ends.
	if weapon_order.is_empty():
		return

	var current_index := weapon_order.find(StringName(active_weapon.name)) if active_weapon != null else -1
	if current_index == -1:
		current_index = 0

	var next_index := posmod(current_index + step, weapon_order.size())
	equip_weapon(weapon_order[next_index])
