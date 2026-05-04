class_name WeaponsManager
extends Node2D

@export var default_weapon_node: StringName = &"Assult_rifle"

var active_weapon: BaseWeapon
var weapons_by_node_name: Dictionary = {}
var weapons_by_id: Dictionary = {}

func _ready() -> void:
	for child in get_children():
		if child is BaseWeapon:
			register_weapon(child)

	if not equip_weapon(default_weapon_node) and not weapons_by_node_name.is_empty():
		var first_weapon_name: StringName = weapons_by_node_name.keys()[0]
		equip_weapon(first_weapon_name)

func register_weapon(weapon: BaseWeapon) -> void:
	weapons_by_node_name[weapon.name] = weapon
	weapons_by_id[weapon.weapon_id] = weapon
	weapon.set_active(false)

func equip_weapon(weapon_key: StringName) -> bool:
	var next_weapon: BaseWeapon = weapons_by_node_name.get(weapon_key)

	if next_weapon == null:
		next_weapon = weapons_by_id.get(String(weapon_key))

	if next_weapon == null:
		return false

	if active_weapon != null and is_instance_valid(active_weapon):
		active_weapon.set_active(false)

	active_weapon = next_weapon
	active_weapon.set_active(true)
	return true

func equip_weapon_by_id(next_weapon_id: String) -> bool:
	var next_weapon: BaseWeapon = weapons_by_id.get(next_weapon_id)

	if next_weapon == null:
		return false

	return equip_weapon(StringName(next_weapon.name))

func update_movement(direction: Vector2) -> void:
	if active_weapon != null:
		active_weapon.update_movement(direction)

func get_aim_frame() -> int:
	if active_weapon != null:
		return active_weapon.get_aim_frame()

	return 0

func get_active_weapon() -> BaseWeapon:
	return active_weapon
