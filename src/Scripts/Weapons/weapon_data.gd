class_name WeaponData
extends RefCounted

# Use this when a weapon id is missing or typed wrong
const DEFAULT_WEAPON_ID := "Assult rifle"

# Keep weapon tuning in one place so scenes only choose an id
const WEAPON_DATA := {
	"Assult rifle": {
		# Fast rifle with a bigger magazine
		"image": preload("res://Assets/Textures/Guns/AFRifle/image.png"),
		"fire_sound" : preload("res://Assets/Audio/Weapons/rifleshot.ogg"),
		"reload_sound" : preload("res://Assets/Audio/Weapons/riflereload.ogg"),
		"damage": 20,
		"fire_rate": 0.15,
		"ammo_mag_size": 30,
		"reload_time": 1.5,
		"bullet_speed": 320.0,
		"bullet_lifetime": 1,
		"bullet_collision_mask": 3,
		"passes_over_tilemap_layers": ["Water"],
		"move_offset": 1.5,
		"recoil_distance": 2.5,
		"recoil_jitter": 0.35,
		"recoil_recover_speed": 18.0,
		# Match the bullet frame to the current aim frame
		"bullet_frames": [0, 1, 2, 3, 4, 5, 6, 7],

		# Keep hand position and muzzle position tuned per aim direction
		"frames": [
			# 0 = right
			{ "gun_position": Vector2(0, 1), "muzzle_offset": Vector2(12, 0) },
			# 1 = down-right
			{ "gun_position": Vector2(2, 1), "muzzle_offset": Vector2(10, 8) },
			# 2 = down
			{ "gun_position": Vector2(0, 2), "muzzle_offset": Vector2(5, 9) },
			# 3 = down-left
			{ "gun_position": Vector2(-2, 1), "muzzle_offset": Vector2(-10, 8) },
			# 4 = left
			{ "gun_position": Vector2(0, 1), "muzzle_offset": Vector2(-12, 0) },
			# 5 = up-left
			{ "gun_position": Vector2(-2, 0), "muzzle_offset": Vector2(-10, -9) },
			# 6 = up
			{ "gun_position": Vector2(0, -1), "muzzle_offset": Vector2(4, -7) },
			# 7 = up-right
			{ "gun_position": Vector2(2, 0), "muzzle_offset": Vector2(10, -8) }
		]
	},
	"Sniper": {
		# Slow weapon with high damage
		"image": preload("res://Assets/Textures/Guns/Sniper/image.png"),
		"fire_sound" : preload("res://Assets/Audio/Weapons/snipershot.ogg"),
		"reload_sound" : preload("res://Assets/Audio/Weapons/sniperreload.ogg"),
		"damage": 50,
		"fire_rate": 0.9,
		"ammo_mag_size": 5,
		"reload_time": 2.2,
		"bullet_speed": 450.0,
		"bullet_lifetime": 1.5,
		"bullet_collision_mask": 3,
		"passes_over_tilemap_layers": ["Water"],
		"move_offset": 1.0,
		"recoil_distance": 3.5,
		"recoil_jitter": 0.15,
		"recoil_recover_speed": 12.0,
		"bullet_frames": [0, 1, 2, 3, 4, 5, 6, 7],
		"frames": [
			{ "gun_position": Vector2(0, 1), "muzzle_offset": Vector2(12, 0) },
			{ "gun_position": Vector2(2, 1), "muzzle_offset": Vector2(10, 8) },
			{ "gun_position": Vector2(0, 2), "muzzle_offset": Vector2(5, 9) },
			{ "gun_position": Vector2(-2, 1), "muzzle_offset": Vector2(-10, 8) },
			{ "gun_position": Vector2(0, 1), "muzzle_offset": Vector2(-12, 0) },
			{ "gun_position": Vector2(-2, 0), "muzzle_offset": Vector2(-10, -9) },
			{ "gun_position": Vector2(0, -1), "muzzle_offset": Vector2(4, -7) },
			{ "gun_position": Vector2(2, 0), "muzzle_offset": Vector2(10, -8) }
		]
	},
	"Rocket Launcher": {
		# Heavy single-shot weapon with splash damage
		"image": preload("res://Assets/Textures/Guns/RocketLauncher/image.png"),
		"fire_sound" : preload("res://Assets/Audio/Weapons/rpgshot.ogg"),
		"reload_sound" : preload("res://Assets/Audio/Weapons/rpgreload.ogg"),
		"impact_sound": preload("res://Assets/Audio/Weapons/explo1.ogg"),
		"impact_sound_max_distance": 700.0,
		"impact_z_index": 8,
		"impact_shake_radius": 360.0,
		"impact_shake_strength": 8.0,
		"impact_shake_duration": 0.24,
		"damage": 80,
		"fire_rate": 1.1,
		"ammo_mag_size": 1,
		"reload_time": 1.6,
		"bullet_speed": 520.0,
		"bullet_lifetime": 0.95,
		"bullet_collision_mask": 3,
		"explosion_radius": 72.0,
		"explosion_damages_owner": true,
		"explosion_min_damage": 1,
		"explosion_falloff_power": 1.0,
		"target_arc_max_distance": 150.0,
		"move_offset": 0.8,
		"recoil_distance": 4.5,
		"recoil_jitter": 0.1,
		"recoil_recover_speed": 10.0,
		"bullet_frames": [0, 2, 4, 6, 8, 10, 12, 14],
		"projectile_frames": [0, 8, 1, 9, 2, 10, 3, 11, 4, 12, 5, 13, 6, 14, 7, 15],
		"projectile_frame_count": 16,
		"uses_target_arc": true,
		"arc_height": 42.0,
		"target_arc_self_aim_distance": 72.0,
		"show_target_arc_indicator": true,
		"hide_cursor_when_selected": true,
		"target_arc_indicator_radius": 24.0,
		"target_arc_indicator_center_dot_radius": 1.0,
		"target_arc_indicator_fill_color": Color(0.4745, 0.3373, 0.3176, 0.42),
		"passes_over_tilemap_layers": ["Water", "Obstacles", "ObsDecor"],
		"bullet_z_index": 6,
		"frames": [
			{ "gun_position": Vector2(0, 1), "muzzle_offset": Vector2(12, 0) },
			{ "gun_position": Vector2(2, 1), "muzzle_offset": Vector2(10, 8) },
			{ "gun_position": Vector2(0, 2), "muzzle_offset": Vector2(5, 9) },
			{ "gun_position": Vector2(-2, 1), "muzzle_offset": Vector2(-10, 8) },
			{ "gun_position": Vector2(0, 1), "muzzle_offset": Vector2(-12, 0) },
			{ "gun_position": Vector2(-2, 0), "muzzle_offset": Vector2(-10, -9) },
			{ "gun_position": Vector2(0, -1), "muzzle_offset": Vector2(4, -7) },
			{ "gun_position": Vector2(2, 0), "muzzle_offset": Vector2(10, -8) }
		]
	},
	"Shotgun": {
	"image": preload("res://Assets/Textures/Guns/Shotgun/image.png"),
	"fire_sound": preload("res://Assets/Audio/Weapons/shotgunshot.mp3"),
	"reload_sound": preload("res://Assets/Audio/Weapons/shotgunreload.mp3"),
	"damage": 8,
	"fire_rate": 0.75,
	"ammo_mag_size": 8,
	"reload_time": 0.6,
	"empty_reload_time": 0.6,
	"bullet_speed": 320.0,
	"bullet_lifetime": 0.8,
	"bullet_collision_mask": 3,
	"passes_over_tilemap_layers": ["Water"],
	"move_offset": 1.2,
	"recoil_distance": 4.0,
	"recoil_jitter": 0.6,
	"recoil_recover_speed": 14.0,
	"frames": [
		{ "gun_position": Vector2(0, 1), "muzzle_offset": Vector2(12, 0) },
		{ "gun_position": Vector2(2, 1), "muzzle_offset": Vector2(10, 8) },
		{ "gun_position": Vector2(0, 2), "muzzle_offset": Vector2(5, 9) },
		{ "gun_position": Vector2(-2, 1), "muzzle_offset": Vector2(-10, 8) },
		{ "gun_position": Vector2(0, 1), "muzzle_offset": Vector2(-12, 0) },
		{ "gun_position": Vector2(-2, 0), "muzzle_offset": Vector2(-10, -9) },
		{ "gun_position": Vector2(0, -1), "muzzle_offset": Vector2(4, -7) },
		{ "gun_position": Vector2(2, 0), "muzzle_offset": Vector2(10, -8) }
	]
}
}
