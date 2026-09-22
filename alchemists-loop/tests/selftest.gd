extends RefCounted
class_name Selftest
# Раннер селфтеста (оп B1): счётчики + голова/хвост + порядок сюит — как было в main.

static var _total := 0
static var _fails := 0

static func check(name: String, cond: bool) -> void:
	_total += 1
	if cond:
		print("[OK] ", name)
	else:
		_fails += 1
		print("[FAIL] ", name)
		push_error("SELFTEST FAIL: " + name)

static func run(g: Game) -> void:
	_total = 0
	_fails = 0

	g.SAVE_PATH = "user://alchemy_st_save.json"
	g.TEMP_PATH = "user://alchemy_st_save.tmp"
	g.BACKUP_PATH = "user://alchemy_st_save.bak"
	for p in [g.SAVE_PATH, g.TEMP_PATH, g.BACKUP_PATH]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))

	Selftest.check("colors parse", g._item_colors.size() == g.ITEMS.size())
	var glyph_ok := true
	for raw_id in g.ITEMS:
		if not ElementGlyphs.has(g._online._item_glyph(String(raw_id))):
			glyph_ok = false
	Selftest.check("glyphs for all items", glyph_ok)
	Selftest.check("parametric glyphs valid", ElementGlyphs.has("star6") and ElementGlyphs.has("crystal5")
		and ElementGlyphs.has("ring3") and ElementGlyphs.is_parametric("poly8")
		and not ElementGlyphs.is_parametric("bogus") and not ElementGlyphs.has("bogus"))
	Selftest.check("pair key symmetric", g._pair_key("fire", "water") == g._pair_key("water", "fire"))
	var valid := true
	var keys := {}
	for r in g.RECIPES:
		var a := String(r["a"]); var b := String(r["b"]); var o := String(r["out"])
		if not (g.ITEMS.has(a) and g.ITEMS.has(b) and g.ITEMS.has(o)):
			valid = false
		keys[g._pair_key(a, b)] = true
	Selftest.check("recipes valid", valid)
	Selftest.check("recipes unique 53", g.RECIPES.size() == 53 and keys.size() == 53)
	Selftest.check("find steam", String(g._online._find_recipe("water", "fire").get("out", "") ) == "steam")
	Selftest.check("find empty", g._online._find_recipe("fire", "fire").is_empty())

	await SuiteCoreBrew.run(g)
	await SuiteLabModes.run(g)
	await SuiteRetortReturn.run(g)
	await SuiteResonanceNet.run(g)
	await SuiteBenchGifts.run(g)
	await SuiteCompanionAtlas.run(g)
	await SuiteQuestsGuild.run(g)
	await SuiteJournalMisc.run(g)
	await SuiteHintsHouse.run(g)
	await SuiteRiddlesRetention.run(g)

	for p in [g.SAVE_PATH, g.TEMP_PATH, g.BACKUP_PATH]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	g.SAVE_PATH = "user://alchemy_save.json"
	g.TEMP_PATH = "user://alchemy_save.tmp"
	g.BACKUP_PATH = "user://alchemy_save.bak"
	print("SELFTEST ", "PASS" if _fails == 0 else "FAIL",
		" (", _total - _fails, "/", _total, ")")
	g.get_tree().quit(0 if _fails == 0 else 1)
