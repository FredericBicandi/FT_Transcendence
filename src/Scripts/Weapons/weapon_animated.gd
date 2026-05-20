class_name WeaponAnimated
extends BaseWeapon

var bullet_frames: SpriteFrames
var bullet_scale_stored: Vector2 = Vector2.ONE

@onready var bullet_template: AnimatedSprite2D = $Gun/Marker2D/Bullets

func _load_bullet_template() -> void:
	if bullet_template == null:
		push_error("Weapon node %s is missing Gun/Marker2D/Bullets." % name)
		return
	bullet_frames = bullet_template.sprite_frames
	bullet_scale_stored = bullet_template.scale
	bullet_template.queue_free()

func _create_bullet_node() -> Node2D:
	return AnimatedSprite2D.new()

func _configure_spawned_bullet(bullet: Node2D, direction: Vector2, start_position: Vector2) -> void:
	var a := bullet as AnimatedSprite2D
	Projectile.configure_visual(a, bullet_frames, bullet_scale_stored, get_weapon_config(), get_spawned_bullet_frame(direction), gun.z_index, direction, start_position)

func _update_bullet_visual(bullet: Node2D, result: Dictionary) -> void:
	var a := bullet as AnimatedSprite2D
	Projectile.update_visual_for_velocity(a, get_weapon_config(), result["velocity"], get_bullet_frame())

func _free_bullet_node(bullet_instance_id: int) -> void:
	var bullet := instance_from_id(bullet_instance_id) as AnimatedSprite2D
	if bullet != null and is_instance_valid(bullet):
		bullet.queue_free()
