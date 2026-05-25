class_name WeaponAnimated
extends BaseWeapon

var bullet_frames: SpriteFrames
var bullet_scale_stored: Vector2 = Vector2.ONE
var impact_frames: SpriteFrames
var impact_scale_stored: Vector2 = Vector2.ONE
var impact_speed_scale_stored: float = 1.0
var impact_smoke_frames: SpriteFrames
var impact_smoke_scale_stored: Vector2 = Vector2.ONE
var impact_smoke_speed_scale_stored: float = 1.0

@onready var bullet_template: AnimatedSprite2D = $Gun/Marker2D/Bullets
@onready var impact_template: AnimatedSprite2D = get_node_or_null("Gun/Marker2D/impact") as AnimatedSprite2D
@onready var impact_smoke_template: AnimatedSprite2D = get_node_or_null("Gun/Marker2D/smoke") as AnimatedSprite2D

func _load_bullet_template() -> void:
	if bullet_template == null:
		push_error("Weapon node %s is missing Gun/Marker2D/Bullets." % name)
		return
	bullet_frames = bullet_template.sprite_frames
	bullet_scale_stored = bullet_template.scale
	bullet_template.queue_free()
	if impact_template != null:
		# Duplicate once so we can force one-shot playback without reallocating every hit.
		impact_frames = impact_template.sprite_frames.duplicate(true) as SpriteFrames
		if impact_frames != null and impact_frames.has_animation(&"default"):
			impact_frames.set_animation_loop(&"default", false)
		impact_scale_stored = impact_template.scale
		impact_speed_scale_stored = impact_template.speed_scale
		impact_template.queue_free()
	if impact_smoke_template != null:
		impact_smoke_frames = impact_smoke_template.sprite_frames.duplicate(true) as SpriteFrames
		if impact_smoke_frames != null and impact_smoke_frames.has_animation(&"default"):
			impact_smoke_frames.set_animation_loop(&"default", false)
		impact_smoke_scale_stored = impact_smoke_template.scale
		impact_smoke_speed_scale_stored = impact_smoke_template.speed_scale
		impact_smoke_template.queue_free()

func _create_bullet_node() -> Node2D:
	return AnimatedSprite2D.new()

func _configure_spawned_bullet(bullet: Node2D, direction: Vector2, start_position: Vector2) -> void:
	var a := bullet as AnimatedSprite2D
	Projectile.configure_visual(a, bullet_frames, bullet_scale_stored, get_weapon_config(), get_spawned_bullet_frame(direction), gun.z_index, direction, start_position)

func _update_bullet_visual(bullet: Node2D, result: Dictionary) -> void:
	var a := bullet as AnimatedSprite2D
	Projectile.update_visual_for_velocity(a, get_weapon_config(), result["velocity"], get_bullet_frame())

func _play_impact_effect(position: Vector2) -> void:
	super._play_impact_effect(position)
	var current_scene := get_tree().current_scene
	if current_scene == null:
		return

	if impact_frames != null:
		_spawn_impact_animation(
			current_scene,
			impact_frames,
			impact_scale_stored,
			impact_speed_scale_stored,
			int(get_weapon_config().get("impact_z_index", get_bullet_visual_z_index() + 1)),
			position
		)
	if impact_smoke_frames != null:
		_spawn_impact_animation(
			current_scene,
			impact_smoke_frames,
			impact_smoke_scale_stored,
			impact_smoke_speed_scale_stored,
			int(get_weapon_config().get("impact_smoke_z_index", get_weapon_config().get("impact_z_index", get_bullet_visual_z_index() + 1))),
			position
		)

func _spawn_impact_animation(parent: Node, frames: SpriteFrames, animation_scale: Vector2, speed_scale: float, visual_z_index: int, position: Vector2) -> void:
	var impact := AnimatedSprite2D.new()
	impact.sprite_frames = frames
	impact.animation = &"default"
	impact.frame = 0
	impact.scale = animation_scale
	impact.speed_scale = speed_scale
	impact.z_index = visual_z_index
	parent.add_child(impact)
	impact.global_position = position
	impact.animation_finished.connect(impact.queue_free)
	impact.play(&"default")

func _free_bullet_node(bullet_instance_id: int) -> void:
	var bullet := instance_from_id(bullet_instance_id) as AnimatedSprite2D
	if bullet != null and is_instance_valid(bullet):
		bullet.queue_free()
