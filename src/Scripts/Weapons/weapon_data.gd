class_name WeaponData
extends RefCounted

# If a weapon asks for an unknown id, the game falls back to this entry instead of crashing.
const DEFAULT_WEAPON_ID := "Assult rifle"

# Central weapon database.
# Each entry defines the weapon icon, combat values, recoil feel, and the 8-direction sprite offsets.
const WEAPON_DATA := {
	"Assult rifle": {
		# Gameplay tuning for the assault rifle: fast, medium damage, larger magazine.
		"image": preload("res://Assets/Textures/Guns/AFRifle/image.png"),
		"fire_sound" : preload("res://Assets/Audio/Weapons/rifleshot.mp3"),
		"reload_sound" : preload("res://Assets/Audio/Weapons/riflereload.mp3"),
		"damage": 12,
		"fire_rate": 0.18,
		"ammo_mag_size": 30,
		"reload_time": 1.5,
		"bullet_speed": 200.0,
		"bullet_lifetime": 0.55,
		"bullet_collision_mask": 3,
		"move_offset": 1.5,
		"recoil_distance": 2.5,
		"recoil_jitter": 0.35,
		"recoil_recover_speed": 18.0,
		# bullet_frames maps weapon aim frame -> bullet sprite frame.
		# Example: if weapon frame 1 should use bullet frame 9, set index 1 to 9.
		"bullet_frames": [0, 1, 2, 3, 4, 5, 6, 7],

		# muzzle_offset is added to gun_position.
		# Change X to move the muzzle left/right.
		# Change Y to move the muzzle up/down.
		"frames": [
			# 0 = right
			{ "gun_position": Vector2(4, 1), "muzzle_offset": Vector2(12, 0) },
			# 1 = down-right
			{ "gun_position": Vector2(3, 2), "muzzle_offset": Vector2(10, 8) },
			# 2 = down
			{ "gun_position": Vector2(0, 3), "muzzle_offset": Vector2(5, 9) },
			# 3 = down-left
			{ "gun_position": Vector2(-3, 2), "muzzle_offset": Vector2(-10, 8) },
			# 4 = left
			{ "gun_position": Vector2(-4, 1), "muzzle_offset": Vector2(-12, 0) },
			# 5 = up-left
			{ "gun_position": Vector2(-3, -1), "muzzle_offset": Vector2(-10, -9) },
			# 6 = up
			{ "gun_position": Vector2(0, -2), "muzzle_offset": Vector2(4, -7) },
			# 7 = up-right
			{ "gun_position": Vector2(3, -1), "muzzle_offset": Vector2(10, -8) }
		]
	},
	"Sniper": {
		# Gameplay tuning for the sniper: slow fire rate, heavy damage, small magazine.
		"image": preload("res://Assets/Textures/Guns/Sniper/image.png"),
		"fire_sound" : preload("res://Assets/Audio/Weapons/snipershot.mp3"),
		"reload_sound" : preload("res://Assets/Audio/Weapons/sniperreload.mp3"),
		"damage": 50,
		"fire_rate": 0.9,
		"ammo_mag_size": 5,
		"reload_time": 2.2,
		"bullet_speed": 320.0,
		"bullet_lifetime": 0.85,
		"bullet_collision_mask": 3,
		"move_offset": 1.0,
		"recoil_distance": 3.5,
		"recoil_jitter": 0.15,
		"recoil_recover_speed": 12.0,
		"bullet_frames": [0, 1, 2, 3, 4, 5, 6, 7],
		"frames": [
			{ "gun_position": Vector2(4, 1), "muzzle_offset": Vector2(12, 0) },
			{ "gun_position": Vector2(3, 2), "muzzle_offset": Vector2(10, 8) },
			{ "gun_position": Vector2(0, 3), "muzzle_offset": Vector2(5, 9) },
			{ "gun_position": Vector2(-3, 2), "muzzle_offset": Vector2(-10, 8) },
			{ "gun_position": Vector2(-4, 1), "muzzle_offset": Vector2(-12, 0) },
			{ "gun_position": Vector2(-3, -1), "muzzle_offset": Vector2(-10, -9) },
			{ "gun_position": Vector2(0, -2), "muzzle_offset": Vector2(4, -7) },
			{ "gun_position": Vector2(3, -1), "muzzle_offset": Vector2(10, -8) }
		]
	},
	"Rocket Launcher": {
		# Gameplay tuning for the rocket launcher: strongest hit, single shot, heaviest recoil.
		"image": preload("res://Assets/Textures/Guns/RocketLuncher/image.png"),
		"fire_sound" : preload("res://Assets/Audio/Weapons/rpgshot.mp3"),
		"reload_sound" : preload("res://Assets/Audio/Weapons/rpgreload.mp3"),
		"damage": 80,
		"fire_rate": 1.1,
		"ammo_mag_size": 1,
		"reload_time": 2.6,
		"bullet_speed": 150.0,
		"bullet_lifetime": 1.0,
		"bullet_collision_mask": 3,
		"move_offset": 0.8,
		"recoil_distance": 4.5,
		"recoil_jitter": 0.1,
		"recoil_recover_speed": 10.0,
		"bullet_frames": [0, 1, 2, 3, 4, 5, 6, 7],
		"frames": [
			{ "gun_position": Vector2(4, 1), "muzzle_offset": Vector2(12, 0) },
			{ "gun_position": Vector2(3, 2), "muzzle_offset": Vector2(10, 8) },
			{ "gun_position": Vector2(0, 3), "muzzle_offset": Vector2(5, 9) },
			{ "gun_position": Vector2(-3, 2), "muzzle_offset": Vector2(-10, 8) },
			{ "gun_position": Vector2(-4, 1), "muzzle_offset": Vector2(-12, 0) },
			{ "gun_position": Vector2(-3, -1), "muzzle_offset": Vector2(-10, -9) },
			{ "gun_position": Vector2(0, -2), "muzzle_offset": Vector2(4, -7) },
			{ "gun_position": Vector2(3, -1), "muzzle_offset": Vector2(10, -8) }
		]
	}
}
