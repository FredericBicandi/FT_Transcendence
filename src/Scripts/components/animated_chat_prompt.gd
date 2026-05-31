class_name AnimatedChatPrompt
extends HBoxContainer

const Localization = preload("res://src/Scripts/components/localization.gd")

const BASE_FONT_SIZE := 13
const GLOW_SCALE := 1.28
const LETTER_STEP_SECONDS := 0.08
const LETTER_PULSE_SECONDS := 0.24
const CYCLE_PAUSE_SECONDS := 0.55
const LETTER_SPACING := 1
const BASE_COLOR := Color(1.0, 1.0, 1.0, 0.72)
const GLOW_COLOR := Color(0.72, 0.94, 1.0, 1.0)
const SHADOW_COLOR := Color(0.0, 0.0, 0.0, 0.78)
const GLOW_SHADOW_COLOR := Color(0.42, 0.86, 1.0, 0.9)
const SPACE_WIDTH := 5.0
const NARROW_LETTER_WIDTH := 6.0
const LETTER_WIDTH := 9.0
const WIDE_LETTER_WIDTH := 12.0
const LETTER_HEIGHT := 24.0

var prompt_text: String = ""
var preferred_font: Font
var animation_time: float = 0.0
var letter_labels: Array[Label] = []
var pulse_cycle_seconds: float = 1.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	alignment = BoxContainer.ALIGNMENT_END
	add_theme_constant_override("separation", LETTER_SPACING)
	set_process(true)

func _process(delta: float) -> void:
	if letter_labels.is_empty():
		return

	animation_time = fmod(animation_time + delta, pulse_cycle_seconds)
	for index in range(letter_labels.size()):
		_apply_letter_animation(letter_labels[index], index)

func set_prompt_text(next_text: String, next_preferred_font: Font = null) -> void:
	prompt_text = next_text
	preferred_font = next_preferred_font
	animation_time = 0.0

	for child in get_children():
		child.queue_free()

	letter_labels.clear()
	var characters: Array[String] = []
	if Localization.contains_arabic(prompt_text):
		characters.append(prompt_text)
	else:
		characters = _get_characters(prompt_text)
	pulse_cycle_seconds = maxf(float(characters.size()) * LETTER_STEP_SECONDS + CYCLE_PAUSE_SECONDS, 1.0)

	for character in characters:
		var label := Label.new()
		label.text = character
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_color_override("font_color", BASE_COLOR)
		label.add_theme_color_override("font_shadow_color", SHADOW_COLOR)
		label.add_theme_color_override("font_outline_color", Color(0.48, 0.85, 1.0, 0.0))
		label.add_theme_constant_override("shadow_offset_x", 1)
		label.add_theme_constant_override("shadow_offset_y", 1)
		label.add_theme_constant_override("outline_size", 2)
		label.add_theme_font_size_override("font_size", BASE_FONT_SIZE)
		Localization.apply_readable_text_font(label, label.text, preferred_font)
		label.custom_minimum_size = Vector2(_get_character_width(character), LETTER_HEIGHT)
		add_child(label)
		letter_labels.append(label)

func _apply_letter_animation(label: Label, index: int) -> void:
	var local_time := fmod(animation_time - float(index) * LETTER_STEP_SECONDS + pulse_cycle_seconds, pulse_cycle_seconds)
	var strength := 0.0
	if local_time <= LETTER_PULSE_SECONDS:
		var progress := clampf(local_time / LETTER_PULSE_SECONDS, 0.0, 1.0)
		strength = sin(progress * PI)

	label.pivot_offset = label.size * 0.5
	label.scale = Vector2.ONE * lerpf(1.0, GLOW_SCALE, strength)
	label.add_theme_color_override("font_color", BASE_COLOR.lerp(GLOW_COLOR, strength))
	label.add_theme_color_override("font_shadow_color", SHADOW_COLOR.lerp(GLOW_SHADOW_COLOR, strength))
	label.add_theme_color_override("font_outline_color", Color(0.48, 0.85, 1.0, strength * 0.8))

func _get_characters(text: String) -> Array[String]:
	var result: Array[String] = []
	for index in range(text.length()):
		result.append(text.substr(index, 1))

	return result

func _get_character_width(character: String) -> float:
	if character.length() > 1:
		return maxf(LETTER_WIDTH, float(character.length()) * LETTER_WIDTH)
	if character == " ":
		return SPACE_WIDTH
	if ["i", "l", "I", "!", ".", ",", "'", "`", "|"].has(character):
		return NARROW_LETTER_WIDTH
	if ["m", "w", "M", "W"].has(character):
		return WIDE_LETTER_WIDTH

	return LETTER_WIDTH
