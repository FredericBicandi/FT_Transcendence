extends Node

@onready var weapon_panel: Control = $CanvasLayer/WeaponHud
@onready var weapon_icon: TextureRect = $CanvasLayer/WeaponHud/MarginContainer/VBoxContainer/WeaponIcon
@onready var weapon_name: Label = $CanvasLayer/WeaponHud/MarginContainer/VBoxContainer/WeaponName
@onready var ammo_label: Label = $CanvasLayer/WeaponHud/MarginContainer/VBoxContainer/AmmoLabel


func show_weapon(weapon: BaseWeapon) -> void:
	if weapon == null:
		# Clear stale HUD data when no weapon is equipped
		weapon_panel.visible = false
		weapon_icon.texture = null
		return

	weapon_panel.visible = true
	weapon_icon.texture = weapon.get_weapon_icon()
	weapon_name.text = weapon.get_weapon_name()
	set_ammo(weapon.get_current_ammo(), weapon.get_magazine_size())


func set_ammo(current_ammo: int, max_ammo: int) -> void:
	ammo_label.text = "%d/%d" % [current_ammo, max_ammo]
