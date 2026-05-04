class_name WeaponData
extends RefCounted

const DEFAULT_WEAPON_ID := "Assult rifle"

const WEAPON_DATA := {
	"Assult rifle": {
		"fire_rate": 0.18,
		"ammo_mag_size": 30,
		"reload_time": 1.5,
		"bullet_speed": 200.0,
		"bullet_lifetime": 0.55,
		"bullet_collision_mask": 1,
		"move_offset": 1.5,
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
	}
}
