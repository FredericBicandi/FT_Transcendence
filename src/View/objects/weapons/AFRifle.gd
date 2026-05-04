class_name AFRifle
extends BaseWeapon

const WeaponDataRef = preload("res://src/View/objects/weapons/WeaponData.gd")

func _ready() -> void:
	weapon_id = WeaponDataRef.DEFAULT_WEAPON_ID
	super._ready()
