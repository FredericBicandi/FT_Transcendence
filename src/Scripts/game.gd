extends Node2D

# Cache the player, weapons, and HUD nodes once so the scene can update UI cheaply.
@onready var player = $Player
@onready var player_body = $Player/CharacterBody2D
@onready var weapons: WeaponsManager = $Player/CharacterBody2D/Weapons
@onready var weapon_panel: Control = $WeaponSwitcher/CanvasLayer/WeaponHud
@onready var weapon_icon: TextureRect = $WeaponSwitcher/CanvasLayer/WeaponHud/MarginContainer/VBoxContainer/WeaponIcon
@onready var weapon_name: Label = $WeaponSwitcher/CanvasLayer/WeaponHud/MarginContainer/VBoxContainer/WeaponName
@onready var ammo_label: Label = $WeaponSwitcher/CanvasLayer/WeaponHud/MarginContainer/VBoxContainer/AmmoLabel
@onready var respawn_overlay: ColorRect = $RespawnUi/CanvasLayer/RespawnOverlay
@onready var respawn_message: Label = $RespawnUi/CanvasLayer/RespawnOverlay/CenterContainer/VBoxContainer/RespawnMessage
@onready var respawn_countdown: Label = $RespawnUi/CanvasLayer/RespawnOverlay/CenterContainer/VBoxContainer/RespawnCountdown

var observed_weapon: BaseWeapon

func _ready() -> void:
	# Listen for weapon swaps so the HUD can follow whichever weapon is currently equipped.
	weapons.active_weapon_changed.connect(_on_active_weapon_changed)
	_on_active_weapon_changed(weapons.get_active_weapon())
	update_respawn_overlay()

func _process(_delta: float) -> void:
	# The respawn overlay depends on runtime player state, so refresh it every frame.
	update_respawn_overlay()

func _on_active_weapon_changed(weapon: BaseWeapon) -> void:
	# Stop listening to the old weapon before tracking the newly equipped one.
	if observed_weapon != null and observed_weapon.ammo_changed.is_connected(_on_ammo_changed):
		observed_weapon.ammo_changed.disconnect(_on_ammo_changed)

	observed_weapon = weapon

	# If no weapon is active, hide the HUD instead of showing stale data.
	if observed_weapon == null:
		weapon_panel.visible = false
		weapon_icon.texture = null
		return

	# Fill the HUD from the new weapon and subscribe to future ammo updates.
	weapon_panel.visible = true
	weapon_icon.texture = observed_weapon.get_weapon_icon()
	weapon_name.text = observed_weapon.get_weapon_name()
	observed_weapon.ammo_changed.connect(_on_ammo_changed)
	_on_ammo_changed(observed_weapon.get_current_ammo(), observed_weapon.get_magazine_size())

func _on_ammo_changed(current_ammo: int, max_ammo: int) -> void:
	# Show current magazine ammo in a compact weapon HUD format.
	ammo_label.text = "%d/%d" % [current_ammo, max_ammo]

func update_respawn_overlay() -> void:
	# Read death and respawn state directly from the player body script.
	var is_dead: bool = bool(player_body.get("is_dead"))
	respawn_overlay.visible = is_dead

	if not is_dead:
		return

	# While dead, show a simple countdown until the player becomes active again.
	var respawn_timer: float = float(player_body.get("respawn_timer"))
	respawn_message.text = "Respawning"
	respawn_countdown.text = "%.1f" % maxf(respawn_timer, 0.0)
