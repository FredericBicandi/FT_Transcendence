extends Node

const Localization = preload("res://src/Scripts/components/localization.gd")
const SLOT_SIZE := Vector2(190.0, 76.0)
const ICON_SIZE := Vector2(92.0, 32.0)
const SLOT_SPACING := 4.0
const PANEL_RIGHT_MARGIN := 18.0
const PANEL_BOTTOM_MARGIN := 82.0
const INACTIVE_PANEL_COLOR := Color(0.08, 0.1, 0.11, 0.9)
const ACTIVE_PANEL_COLOR := Color(0.12, 0.14, 0.16, 0.95)
const INACTIVE_BORDER_COLOR := Color(0.35, 0.39, 0.42, 0.95)
const ACTIVE_BORDER_COLOR := Color(0.88, 0.91, 0.94, 1.0)
const TEXT_COLOR := Color(0.96, 0.98, 1.0, 1.0)

@onready var weapon_panel: Control = $CanvasLayer/WeaponHud

var slot_container: VBoxContainer
var weapons: Array[BaseWeapon] = []
var active_weapon: BaseWeapon
var row_by_weapon: Dictionary = {}

func _ready() -> void:
	_build_shell()

func set_weapons(next_weapons: Array[BaseWeapon]) -> void:
	weapons = next_weapons
	_resize_panel_to_weapon_count()
	_rebuild_slots()

func show_weapon(weapon: BaseWeapon) -> void:
	active_weapon = weapon
	weapon_panel.visible = weapon != null
	_refresh_rows()

func set_ammo(current_ammo: int, max_ammo: int) -> void:
	if active_weapon == null:
		return

	_update_weapon_ammo(active_weapon, current_ammo, max_ammo)

func _build_shell() -> void:
	weapon_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	weapon_panel.offset_left = -(PANEL_RIGHT_MARGIN + SLOT_SIZE.x)
	weapon_panel.offset_top = -242.0
	weapon_panel.offset_right = -PANEL_RIGHT_MARGIN
	weapon_panel.offset_bottom = -PANEL_BOTTOM_MARGIN
	weapon_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if weapon_panel is PanelContainer:
		var shell_style: StyleBoxFlat = StyleBoxFlat.new()
		shell_style.bg_color = Color.TRANSPARENT
		(weapon_panel as PanelContainer).add_theme_stylebox_override("panel", shell_style)

	for child in weapon_panel.get_children():
		child.queue_free()

	var margin: MarginContainer = MarginContainer.new()
	margin.name = "MarginContainer"
	margin.add_theme_constant_override("margin_left", 0)
	margin.add_theme_constant_override("margin_top", 0)
	margin.add_theme_constant_override("margin_right", 0)
	margin.add_theme_constant_override("margin_bottom", 0)
	weapon_panel.add_child(margin)

	slot_container = VBoxContainer.new()
	slot_container.name = "Slots"
	slot_container.add_theme_constant_override("separation", int(SLOT_SPACING))
	margin.add_child(slot_container)
	_resize_panel_to_weapon_count()

func _resize_panel_to_weapon_count() -> void:
	var slot_count: int = max(weapons.size(), 1)
	var panel_height: float = SLOT_SIZE.y * slot_count + SLOT_SPACING * max(slot_count - 1, 0)
	weapon_panel.offset_top = -(panel_height + PANEL_BOTTOM_MARGIN)
	weapon_panel.offset_bottom = -PANEL_BOTTOM_MARGIN

func _rebuild_slots() -> void:
	if slot_container == null:
		return

	for child in slot_container.get_children():
		child.queue_free()

	row_by_weapon.clear()
	for index in range(weapons.size()):
		var weapon: BaseWeapon = weapons[index]
		if weapon == null:
			continue

		var row: PanelContainer = _create_slot_row(weapon, index)
		slot_container.add_child(row)
		row_by_weapon[weapon] = row

	_refresh_rows()

func _create_slot_row(weapon: BaseWeapon, index: int) -> PanelContainer:
	var row: PanelContainer = PanelContainer.new()
	row.name = "%sSlot" % weapon.get_weapon_name().replace(" ", "")
	row.custom_minimum_size = SLOT_SIZE
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 7)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_right", 7)
	margin.add_theme_constant_override("margin_bottom", 4)
	row.add_child(margin)

	var layout: VBoxContainer = VBoxContainer.new()
	layout.add_theme_constant_override("separation", 0)
	margin.add_child(layout)

	var top_row: HBoxContainer = HBoxContainer.new()
	top_row.custom_minimum_size = Vector2(0.0, 17.0)
	layout.add_child(top_row)

	var weapon_slot_label: Label = Label.new()
	weapon_slot_label.name = "WeaponSlotLabel"
	weapon_slot_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	weapon_slot_label.add_theme_color_override("font_color", TEXT_COLOR)
	weapon_slot_label.add_theme_font_size_override("font_size", 13)
	weapon_slot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if Localization.is_arabic_language() else HORIZONTAL_ALIGNMENT_LEFT
	weapon_slot_label.text = _format_weapon_slot_text(weapon, index)
	Localization.apply_readable_text_font(weapon_slot_label, weapon_slot_label.text)
	top_row.add_child(weapon_slot_label)

	var icon_row: HBoxContainer = HBoxContainer.new()
	icon_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(icon_row)

	var icon: TextureRect = TextureRect.new()
	icon.name = "WeaponIcon"
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.custom_minimum_size = ICON_SIZE
	icon.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = weapon.get_weapon_icon()
	icon_row.add_child(icon)

	var bottom_row: HBoxContainer = HBoxContainer.new()
	bottom_row.custom_minimum_size = Vector2(0.0, 17.0)
	bottom_row.add_theme_constant_override("separation", 4)
	layout.add_child(bottom_row)

	var bottom_spacer: Control = Control.new()
	bottom_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom_row.add_child(bottom_spacer)

	var ammo_label: Label = Label.new()
	ammo_label.name = "AmmoLabel"
	ammo_label.add_theme_color_override("font_color", TEXT_COLOR)
	ammo_label.add_theme_font_size_override("font_size", 14)
	ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ammo_label.text = _format_ammo(weapon.get_current_ammo(), weapon.get_magazine_size())
	Localization.apply_readable_text_font(ammo_label, ammo_label.text)
	bottom_row.add_child(ammo_label)

	return row

func _refresh_rows() -> void:
	for weapon_variant in row_by_weapon.keys():
		var weapon: BaseWeapon = weapon_variant as BaseWeapon
		var row: PanelContainer = row_by_weapon[weapon_variant] as PanelContainer
		if row == null:
			continue

		var is_active: bool = weapon == active_weapon
		row.add_theme_stylebox_override("panel", _create_slot_style(is_active))
		row.modulate = Color(1.0, 1.0, 1.0, 1.0) if is_active else Color(0.78, 0.84, 0.72, 0.88)
		_update_weapon_ammo(weapon, weapon.get_current_ammo(), weapon.get_magazine_size())

func _update_weapon_ammo(weapon: BaseWeapon, current_ammo: int, max_ammo: int) -> void:
	var row: PanelContainer = row_by_weapon.get(weapon) as PanelContainer
	if row == null:
		return

	var ammo_label: Label = row.find_child("AmmoLabel", true, false) as Label
	if ammo_label != null:
		ammo_label.text = _format_ammo(current_ammo, max_ammo)
		Localization.apply_readable_text_font(ammo_label, ammo_label.text)

func _create_slot_style(is_active: bool) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = ACTIVE_PANEL_COLOR if is_active else INACTIVE_PANEL_COLOR
	style.border_width_left = 3 if is_active else 2
	style.border_width_top = 3 if is_active else 2
	style.border_width_right = 3 if is_active else 2
	style.border_width_bottom = 3 if is_active else 2
	style.border_color = ACTIVE_BORDER_COLOR if is_active else INACTIVE_BORDER_COLOR
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_right = 4
	style.corner_radius_bottom_left = 4
	return style

func _format_ammo(current_ammo: int, max_ammo: int) -> String:
	if max_ammo <= 0:
		return Localization.translate("infinite_ammo") if current_ammo > 999 else "%d" % current_ammo

	return "%d/%d" % [current_ammo, max_ammo]

func _format_weapon_slot_text(weapon: BaseWeapon, index: int) -> String:
	var weapon_name := Localization.translate_weapon_name(weapon.get_weapon_name())
	var slot_key := _get_slot_key_text(index)
	if Localization.is_arabic_language():
		return "%s %s" % [weapon_name, slot_key]

	return "%s [%s]" % [weapon_name, slot_key]

func _get_slot_key_text(index: int) -> String:
	if index == 9:
		return "0"

	return str(index + 1)
