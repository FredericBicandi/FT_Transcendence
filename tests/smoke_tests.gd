extends SceneTree

const ProjectileScript = preload("res://src/Scripts/Weapons/projectile.gd")
const NetworkClientScript = preload("res://src/Scripts/Networks/network_client.gd")
const GameScript = preload("res://src/Scripts/game.gd")
const LeaderboardScript = preload("res://src/Scripts/components/leaderboard_ui.gd")
const PlayerScript = preload("res://src/Scripts/components/player.gd")

var failures: Array[String] = []


func _initialize() -> void:
	_test_projectile_lifetime()
	_test_network_vector_bounds()
	_test_chat_limits()
	_test_leaderboard_name_signature()
	_test_remote_medkit_eligibility()

	for failure in failures:
		push_error(failure)

	quit(1 if not failures.is_empty() else 0)


func _test_projectile_lifetime() -> void:
	var runtime_data := {
		"position": Vector2.ZERO,
		"velocity": Vector2(10.0, 0.0),
		"direction": Vector2.RIGHT,
		"age": 0.0,
		"lifetime": 1.0,
		"gravity": 0.0
	}

	for _step in range(4):
		var result: Dictionary = ProjectileScript.tick(runtime_data, 0.2)
		_check(bool(result.get("alive", false)), "Projectile expired before its configured lifetime.")

	_check(
		is_equal_approx(float(runtime_data.get("lifetime", 0.0)), 1.0),
		"Projectile lifetime was mutated while ticking."
	)
	var final_result: Dictionary = ProjectileScript.tick(runtime_data, 0.21)
	_check(not bool(final_result.get("alive", true)), "Projectile survived beyond its configured lifetime.")


func _test_network_vector_bounds() -> void:
	_check(
		NetworkClientScript.has_finite_vector2({"x": 999_999.0, "y": -999_999.0}, "x", "y"),
		"Valid bounded network coordinates were rejected."
	)
	_check(
		not NetworkClientScript.has_finite_vector2({"x": 1_000_001.0, "y": 0.0}, "x", "y"),
		"Out-of-range network coordinates were accepted."
	)
	_check(
		not NetworkClientScript.has_finite_vector2({"x": NAN, "y": 0.0}, "x", "y"),
		"Non-finite network coordinates were accepted."
	)


func _test_chat_limits() -> void:
	var game := GameScript.new()
	var sanitized: String = game.call("_sanitize_chat_message", "ab".repeat(5000))
	_check(sanitized.length() <= 320, "Chat sanitization exceeded the character limit.")
	var sanitized_name: String = game.call("_sanitize_player_name", "Player".repeat(100))
	_check(sanitized_name.length() <= 32, "Player-name sanitization exceeded the character limit.")
	game.free()


func _test_leaderboard_name_signature() -> void:
	var leaderboard := LeaderboardScript.new()
	var first_entries: Array[Dictionary] = [{
		"player_id": "player-1",
		"player_name": "Alpha",
		"kills": 1,
		"deaths": 0,
		"score": 10
	}]
	var renamed_entries: Array[Dictionary] = [{
		"player_id": "player-1",
		"player_name": "Bravo",
		"kills": 1,
		"deaths": 0,
		"score": 10
	}]
	var first_signature: int = leaderboard.call("_compute_entries_signature", first_entries)
	var renamed_signature: int = leaderboard.call("_compute_entries_signature", renamed_entries)
	_check(first_signature != renamed_signature, "Leaderboard name changes did not invalidate the row cache.")
	leaderboard.free()


func _test_remote_medkit_eligibility() -> void:
	var player := PlayerScript.new()
	player.health = 50
	player.accepts_input = true
	player.is_remote_proxy = false
	player.is_dead = false
	_check(player.can_collect_death_medkit(), "A damaged local player could not collect a medkit.")

	player.accepts_input = false
	player.is_remote_proxy = true
	_check(not player.can_collect_death_medkit(), "A remote proxy could consume a medkit locally.")
	player.free()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
