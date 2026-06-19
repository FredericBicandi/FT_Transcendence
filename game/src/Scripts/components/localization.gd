class_name GameLocalization
extends RefCounted

const DEFAULT_LANGUAGE := "english"
const SUPPORTED_LANGUAGES := ["english", "french", "arabic"]
const ARABIC_FONT_RESOURCE := preload("res://Assets/Fonts/PixelAE-Regular.ttf")
const ARABIC_FONT_NAMES := ["Segoe UI", "Tahoma", "Arial", "Adobe Arabic", "Arial Unicode MS"]
const WEAPON_TRANSLATION_KEYS := {
	"Assult rifle": "weapon_assault_rifle",
	"Sniper": "weapon_sniper",
	"Rocket Launcher": "weapon_rocket_launcher",
	"Shotgun": "weapon_shotgun"
}

const TRANSLATIONS := {
	"english": {
		"connection_title": "Multiplayer Connection",
		"connecting": "Connecting...",
		"connecting_server": "Connecting to multiplayer server...",
		"connection_failed": "Connection failed. Check the server URL and try again.",
		"connected_reserving": "Connected. Reserving a room...",
		"player_already_joined": "This player is already joined in another tab or window.",
		"room_reserved": "Room reserved.",
		"joining_match": "Joining match...",
		"disconnected": "Disconnected.",
		"connected": "Connected.",
		"reconnecting": "%s Reconnecting...",
		"join": "Join",
		"dashboard": "Dashboard",
		"leaderboard": "Leaderboard",
		"player_name": "Player Name",
		"kills": "Kills",
		"deaths": "Deaths",
		"score": "Score",
		"default_player": "Player",
		"unknown_player": "Unknown",
		"leaderboard_empty": "No players in the leaderboard yet.",
		"respawning": "Respawning",
		"leave_game_title": "Leave game?",
		"leave_game_body": "Are you sure you want to leave the game?",
		"chat_prompt": "Press Enter to chat",
		"chat_placeholder": "type chat",
		"sniper_rmb_hint": "Hold RMB to aim farther",
		"weapon_assault_rifle": "Assault Rifle",
		"weapon_sniper": "Sniper",
		"weapon_rocket_launcher": "Rocket Launcher",
		"weapon_shotgun": "Shotgun",
		"infinite_ammo": "INF",
		"cancel": "Cancel",
		"yes": "Yes"
	},
	"french": {
		"connection_title": "Connexion multijoueur",
		"connecting": "Connexion...",
		"connecting_server": "Connexion au serveur multijoueur...",
		"connection_failed": "Connexion echouee. Verifiez l'URL du serveur et reessayez.",
		"connected_reserving": "Connecte. Reservation d'une salle...",
		"player_already_joined": "Ce joueur a deja rejoint la partie dans un autre onglet ou une autre fenetre.",
		"room_reserved": "Salle reservee.",
		"joining_match": "Entree dans la partie...",
		"disconnected": "Deconnecte.",
		"connected": "Connecte.",
		"reconnecting": "%s Reconnexion...",
		"join": "Rejoindre",
		"dashboard": "Tableau de bord",
		"leaderboard": "Classement",
		"player_name": "Joueur",
		"kills": "Eliminations",
		"deaths": "Morts",
		"score": "Score",
		"default_player": "Joueur",
		"unknown_player": "Inconnu",
		"leaderboard_empty": "Aucun joueur dans le classement.",
		"respawning": "Reapparition",
		"leave_game_title": "Quitter la partie ?",
		"leave_game_body": "Voulez-vous vraiment quitter la partie ?",
		"chat_prompt": "Appuyez sur Entree pour discuter",
		"chat_placeholder": "ecrire un message",
		"sniper_rmb_hint": "Maintenez clic droit pour viser plus loin",
		"weapon_assault_rifle": "Fusil d'assaut",
		"weapon_sniper": "Fusil de precision",
		"weapon_rocket_launcher": "Lance-roquettes",
		"weapon_shotgun": "Fusil a pompe",
		"infinite_ammo": "INF",
		"cancel": "Annuler",
		"yes": "Oui"
	},
	"arabic": {
		"connection_title": "اتصال متعدد اللاعبين",
		"connecting": "جار الاتصال...",
		"connecting_server": "جار الاتصال بخادم اللعب الجماعي...",
		"connection_failed": "فشل الاتصال. تحقق من رابط الخادم وحاول مرة أخرى.",
		"connected_reserving": "تم الاتصال. جار حجز غرفة...",
		"player_already_joined": "هذا اللاعب منضم بالفعل في تبويب أو نافذة أخرى.",
		"room_reserved": "تم حجز الغرفة.",
		"joining_match": "جار دخول المباراة...",
		"disconnected": "تم قطع الاتصال.",
		"connected": "تم الاتصال.",
		"reconnecting": "%s جار إعادة الاتصال...",
		"join": "انضمام",
		"dashboard": "لوحة التحكم",
		"leaderboard": "لوحة الصدارة",
		"player_name": "اسم اللاعب",
		"kills": "القتل",
		"deaths": "الموت",
		"score": "النقاط",
		"default_player": "لاعب",
		"unknown_player": "غير معروف",
		"leaderboard_empty": "لا يوجد لاعبون في لوحة الصدارة بعد.",
		"respawning": "جار الظهور",
		"leave_game_title": "مغادرة اللعبة؟",
		"leave_game_body": "هل تريد مغادرة اللعبة؟",
		"chat_prompt": "اضغط Enter للدردشة",
		"chat_placeholder": "اكتب رسالة",
		"sniper_rmb_hint": "اضغط الزر الأيمن للتصويب أبعد",
		"weapon_assault_rifle": "بندقية هجومية",
		"weapon_sniper": "قناصة",
		"weapon_rocket_launcher": "قاذف صواريخ",
		"weapon_shotgun": "بندقية رش",
		"infinite_ammo": "لا نهائي",
		"cancel": "إلغاء",
		"yes": "نعم"
	}
}

static var language: String = DEFAULT_LANGUAGE
static var arabic_font: Font

static func set_language(next_language: String) -> void:
	language = normalize_language(next_language)

static func get_language() -> String:
	return language

static func translate(key: String) -> String:
	var normalized_language: String = normalize_language(language)
	var language_table: Dictionary = TRANSLATIONS.get(normalized_language, TRANSLATIONS[DEFAULT_LANGUAGE])
	return str(language_table.get(key, TRANSLATIONS[DEFAULT_LANGUAGE].get(key, key)))

static func translate_weapon_name(weapon_name: String) -> String:
	var translation_key: String = str(WEAPON_TRANSLATION_KEYS.get(weapon_name, ""))
	if translation_key == "":
		return weapon_name

	return translate(translation_key)

static func is_arabic_language() -> bool:
	return normalize_language(language) == "arabic"

static func contains_arabic(text: String) -> bool:
	for index in range(text.length()):
		var codepoint := text.unicode_at(index)
		if (
			(codepoint >= 0x0600 and codepoint <= 0x06FF)
			or (codepoint >= 0x0750 and codepoint <= 0x077F)
			or (codepoint >= 0x08A0 and codepoint <= 0x08FF)
			or (codepoint >= 0xFB50 and codepoint <= 0xFDFF)
			or (codepoint >= 0xFE70 and codepoint <= 0xFEFF)
		):
			return true

	return false

static func get_arabic_font() -> Font:
	if arabic_font == null:
		arabic_font = ARABIC_FONT_RESOURCE
		if arabic_font == null:
			var system_font := SystemFont.new()
			system_font.font_names = PackedStringArray(ARABIC_FONT_NAMES)
			arabic_font = system_font

	return arabic_font

static func get_readable_font_for_text(text: String, preferred_font: Font = null) -> Font:
	if is_arabic_language() or contains_arabic(text):
		return get_arabic_font()

	return preferred_font

static func apply_readable_text_font(control: Control, text: String, preferred_font: Font = null) -> void:
	if control == null:
		return

	var readable_font := get_readable_font_for_text(text, preferred_font)
	if readable_font != null:
		control.add_theme_font_override("font", readable_font)

	if is_arabic_language() or contains_arabic(text):
		control.layout_direction = Control.LAYOUT_DIRECTION_LTR if _should_preserve_ltr_layout(control) else Control.LAYOUT_DIRECTION_RTL

static func apply_active_language_font(root: Node) -> void:
	if root == null or not is_arabic_language():
		return

	_apply_arabic_font_recursive(root)

static func normalize_language(value: String) -> String:
	var normalized: String = value.strip_edges().to_lower()
	if SUPPORTED_LANGUAGES.has(normalized):
		return normalized

	return DEFAULT_LANGUAGE

static func get_url_param(param_name: String, fallback: String = "") -> String:
	if not OS.has_feature("web"):
		return fallback

	var js_code: String = """
		new URLSearchParams(window.location.search).get("%s") || "%s"
	""" % [_escape_js_string(param_name), _escape_js_string(fallback)]

	var value: Variant = JavaScriptBridge.eval(js_code, true)
	return str(value) if value != null else fallback

static func apply_url_language() -> String:
	var next_language: String = get_url_param("language", language)
	set_language(next_language)
	return language

static func _escape_js_string(value: String) -> String:
	return value.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n").replace("\r", "\\r")

static func _apply_arabic_font_recursive(node: Node) -> void:
	var control := node as Control
	if control != null:
		control.add_theme_font_override("font", get_arabic_font())
		control.layout_direction = Control.LAYOUT_DIRECTION_LTR if _should_preserve_ltr_layout(control) else Control.LAYOUT_DIRECTION_RTL

	for child in node.get_children():
		_apply_arabic_font_recursive(child)

static func _should_preserve_ltr_layout(control: Control) -> bool:
	return control is ProgressBar
