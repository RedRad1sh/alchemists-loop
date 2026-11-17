extends RefCounted
class_name ProgressionProfileLoader


static func load_from_path(path: String) -> BalanceProfile:
	return BalanceConfig.load_profile_json(path)


static func apply_to_game(game: Game, path: String) -> bool:
	if path.is_empty():
		game.balance = BalanceConfig.baseline()
		return true
	var prof: BalanceProfile = BalanceConfig.load_profile_json(path)
	if prof == null:
		return false
	game.balance = prof
	return true
