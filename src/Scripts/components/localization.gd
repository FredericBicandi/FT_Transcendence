class_name GameLocalization
extends RefCounted

const DEFAULT_LANGUAGE := "english"
const SUPPORTED_LANGUAGES := ["english", "french", "arabic"]

const TRANSLATIONS := {
	"english": {
		"connection_title": "Multiplayer Connection",
		"connecting": "Connecting...",
		"connecting_server": "Connecting to multiplayer server...",
		"connection_failed": "Connection failed. Check the server URL and try again.",
		"connected_reserving": "Connected. Reserving a room...",
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
		"leaderboard_empty": "No players in the leaderboard yet.",
		"respawning": "Respawning",
		"leave_game_title": "Leave game?",
		"leave_game_body": "Are you sure you want to leave the game?",
		"cancel": "Cancel",
		"yes": "Yes"
	},
	"french": {
		"connection_title": "Connexion multijoueur",
		"connecting": "Connexion...",
		"connecting_server": "Connexion au serveur multijoueur...",
		"connection_failed": "Connexion echouee. Verifiez l'URL du serveur et reessayez.",
		"connected_reserving": "Connecte. Reservation d'une salle...",
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
		"leaderboard_empty": "Aucun joueur dans le classement.",
		"respawning": "Reapparition",
		"leave_game_title": "Quitter la partie ?",
		"leave_game_body": "Voulez-vous vraiment quitter la partie ?",
		"cancel": "Annuler",
		"yes": "Oui"
	},
	"arabic": {
		"connection_title": "اتصال متعدد اللاعبين",
		"connecting": "جار الاتصال...",
		"connecting_server": "جار الاتصال بخادم اللعب الجماعي...",
		"connection_failed": "فشل الاتصال. تحقق من رابط الخادم وحاول مرة أخرى.",
		"connected_reserving": "تم الاتصال. جار حجز غرفة...",
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
		"leaderboard_empty": "لا يوجد لاعبون في لوحة الصدارة بعد.",
		"respawning": "جار الظهور",
		"leave_game_title": "مغادرة اللعبة؟",
		"leave_game_body": "هل تريد مغادرة اللعبة؟",
		"cancel": "إلغاء",
		"yes": "نعم"
	}
}

static var language: String = DEFAULT_LANGUAGE

static func set_language(next_language: String) -> void:
	language = normalize_language(next_language)

static func get_language() -> String:
	return language

static func translate(key: String) -> String:
	var normalized_language: String = normalize_language(language)
	var language_table: Dictionary = TRANSLATIONS.get(normalized_language, TRANSLATIONS[DEFAULT_LANGUAGE])
	return str(language_table.get(key, TRANSLATIONS[DEFAULT_LANGUAGE].get(key, key)))

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
