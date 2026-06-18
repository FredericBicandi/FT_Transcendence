class_name WeaponSprite
extends BaseWeapon

# Static bullet visual adapter. The marker child is only a template; it is
# removed on ready and cloned as lightweight Sprite2D bullets when shots spawn.

var bullet_texture: Texture2D
var bullet_scale_stored: Vector2 = Vector2.ONE

@onready var bullet_template: Sprite2D = $Gun/Marker2D/Bullet

func _load_bullet_template() -> void:
	if bullet_template == null:
		push_error("Weapon node %s is missing Gun/Marker2D/Bullet." % name)
		return
	bullet_texture = bullet_template.texture
	bullet_scale_stored = bullet_template.scale
	bullet_template.queue_free()

func _create_bullet_node() -> Node2D:
	return Sprite2D.new()

func _configure_spawned_bullet(bullet: Node2D, direction: Vector2, start_position: Vector2) -> void:
	var s := bullet as Sprite2D
	s.texture = bullet_texture
	s.scale = bullet_scale_stored
	s.z_index = gun.z_index
	s.global_position = start_position
	s.rotation = direction.angle()

func _update_bullet_visual(bullet: Node2D, result: Dictionary) -> void:
	var velocity: Vector2 = result["velocity"]
	if velocity.length_squared() > 0.0:
		bullet.rotation = velocity.angle()

func _free_bullet_node(bullet_instance_id: int) -> void:
	var bullet := instance_from_id(bullet_instance_id) as Sprite2D
	if bullet != null and is_instance_valid(bullet):
		bullet.queue_free()
