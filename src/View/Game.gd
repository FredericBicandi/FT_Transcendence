extends Node2D

@onready var player = $Player
@onready var weapons: WeaponsManager = $Player/CharacterBody2D/Weapons
@onready var weapon_panel: Control = $CanvasLayer/WeaponHud
@onready var weapon_name: Label = $CanvasLayer/WeaponHud/MarginContainer/VBoxContainer/WeaponName
@onready var ammo_label: Label = $CanvasLayer/WeaponHud/MarginContainer/VBoxContainer/AmmoLabel

var observed_weapon: BaseWeapon

func _ready() -> void:
	weapons.active_weapon_changed.connect(_on_active_weapon_changed)
	_on_active_weapon_changed(weapons.get_active_weapon())

func _on_active_weapon_changed(weapon: BaseWeapon) -> void:
	if observed_weapon != null and observed_weapon.ammo_changed.is_connected(_on_ammo_changed):
		observed_weapon.ammo_changed.disconnect(_on_ammo_changed)

	observed_weapon = weapon

	if observed_weapon == null:
		weapon_panel.visible = false
		return

	weapon_panel.visible = true
	weapon_name.text = observed_weapon.get_weapon_name()
	observed_weapon.ammo_changed.connect(_on_ammo_changed)
	_on_ammo_changed(observed_weapon.get_current_ammo(), observed_weapon.get_magazine_size())

func _on_ammo_changed(current_ammo: int, max_ammo: int) -> void:
	ammo_label.text = "%d/%d" % [current_ammo, max_ammo]
