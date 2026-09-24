extends RefCounted
class_name Selftest
# Раннер селфтеста (оп B1): счётчики + голова/хвост + порядок сюит — как было в main.

static var _total := 0
static var _fails := 0

# U20 (T25): файлы приватного контейнера, очереди аналитики и их ST-двойники.
# Порядок индексов совпадает с порядком перевода путей в run(): user.json /
# user.tmp / user.bak / purchases.json / purchases.tmp / analytics.json. Имена
# двойников те же, что уже использует tests/suite_journal_misc.gd, — иначе две
# слоя изоляции разошлись бы и чек «no trace» стал бы самообманом.
const U20_REAL_FILES: Array = [
	"user://alchemists_loop_user.json",
	"user://alchemists_loop_user.tmp",
	"user://alchemists_loop_user.bak",
	"user://alchemists_loop_purchases.json",
	"user://alchemists_loop_purchases.tmp",
	"user://alchemists_loop_analytics.json",
]
const U20_ST_FILES: Array = [
	"user://alchemy_st_user.json",
	"user://alchemy_st_user.tmp",
	"user://alchemy_st_user.bak",
	"user://alchemy_st_purchases.json",
	"user://alchemy_st_purchases.tmp",
	"user://alchemy_st_analytics.json",
]

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

	# U20 (T25): UserData и Analytics до этого перевода писали в настоящие файлы
	# установки (сейв с pending-метками, журнал покупок, очередь событий). Снимок
	# «что лежало в настоящих файлах до прогона» берётся ДО перевода путей, а
	# проверяется в конце по тексту каждого файла: без перевода путей эти чеки
	# краснеют (см. комментарии у них).
	var real_before := {}
	for rp in U20_REAL_FILES:
		real_before[String(rp)] = _u20_read_text(String(rp))
	UserData.SAVE_PATH = String(U20_ST_FILES[0])
	UserData.TEMP_PATH = String(U20_ST_FILES[1])
	UserData.BACKUP_PATH = String(U20_ST_FILES[2])
	UserData.PURCHASES_PATH = String(U20_ST_FILES[3])
	UserData.PURCHASES_TEMP_PATH = String(U20_ST_FILES[4])
	Analytics.QUEUE_PATH = String(U20_ST_FILES[5])
	_u20_wipe(U20_ST_FILES)

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
	await SuiteMonetization.run(g)
	await SuiteHintsHouse.run(g)
	await SuiteRiddlesRetention.run(g)

	_u20_wipe([g.SAVE_PATH, g.TEMP_PATH, g.BACKUP_PATH] + U20_ST_FILES)
	g.SAVE_PATH = "user://alchemy_save.json"
	g.TEMP_PATH = "user://alchemy_save.tmp"
	g.BACKUP_PATH = "user://alchemy_save.bak"
	UserData.SAVE_PATH = String(U20_REAL_FILES[0])
	UserData.TEMP_PATH = String(U20_REAL_FILES[1])
	UserData.BACKUP_PATH = String(U20_REAL_FILES[2])
	UserData.PURCHASES_PATH = String(U20_REAL_FILES[3])
	UserData.PURCHASES_TEMP_PATH = String(U20_REAL_FILES[4])
	Analytics.QUEUE_PATH = String(U20_REAL_FILES[5])
	# Каждый из трёх чеков краснеет ровно удалением своего перевода пути на входе:
	# tests/suite_monetization.gd пишет метки («u20_sentinel_product» в сейв,
	# «u20_hermetic_sku» в журнал, «u20_probe_event» в очередь аналитики) и тут же
	# сверяет изолированный файл с настоящим; этот чек — второй слой: он сравнивает
	# текст настоящего файла с снимком «до прогона». Убрать перевод
	# UserData.SAVE_PATH — в реальном user.json появится pending-метка; убрать
	# PURCHASES_PATH — в реальном журнале появится granted-запись; убрать
	# Analytics.QUEUE_PATH — в реальном файле аналитики появится событие-проба.
	# Сравнение идёт по тексту каждого файла, а не словарём через == (глубокое
	# сравнение в Godot 4 пропустило бы «просто совпало»).
	Selftest.check("u20 selftest left the real user data file untouched",
		_u20_untouched(real_before, [String(U20_REAL_FILES[0]), String(U20_REAL_FILES[1]), String(U20_REAL_FILES[2])]))
	Selftest.check("u20 selftest left the real purchase journal untouched",
		_u20_untouched(real_before, [String(U20_REAL_FILES[3]), String(U20_REAL_FILES[4])]))
	Selftest.check("u20 selftest left the real analytics queue untouched",
		_u20_untouched(real_before, [String(U20_REAL_FILES[5])]))
	# U22 (T26): снимок выше (real_before) берётся уже внутри run — post-фактум, и
	# записи онбординг-аналитики ДО изоляции путей не видит: к моменту real_before
	# main.gd уже успел их дописать. Здесь точка отсчёта — boot-снимки g, снятые в
	# самом верху Main._ready до первого обращения к Analytics. Мутация, краснящая
	# ровно этот кейс: убрать `if not _selftest:` вокруг Analytics.session_start /
	# Analytics.track в main.gd. Тогда session_start доходит до изоляции и
	# record_session_start безусловно поднимает session_count в НАСТОЯЩЕМ user.json
	# (согласие не нужен) — сравнение по user.json даёт детерминизм пары; при
	# выданном согласии ещё и два события лягут в реальную очередь аналитики, и
	# сравнение по ней их ловит, но сама по себе краснела бы лишь при granted.
	# Граница окна: реальный user.json перезаписывается и ДО снимка (UserData._ready
	# -> _load/_save при каждом старте, App._ready -> ensure_install_metadata при
	# первом запуске) — это не тестовые данные, и кейс их сознательно не сверяет.
	# Кейс рассчитан на канонический прогон (--selftest без демо-флагов); в гибриде
	# --selftest --demo --action=hint без --shot= демо-обход вызывает
	# Analytics.track вне гейта, и при выданном согласии он краснит эту пару.
	Selftest.check("u22 selftest wrote no onboarding analytics or session data before path isolation",
		_u20_read_text(String(U20_REAL_FILES[5])) == g._analytics_text_at_boot
		and _u20_read_text(String(U20_REAL_FILES[0])) == g._user_data_text_at_boot)
	print("SELFTEST ", "PASS" if _fails == 0 else "FAIL",
		" (", _total - _fails, "/", _total, ")")
	g.get_tree().quit(0 if _fails == 0 else 1)


static func _u20_read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text


static func _u20_wipe(paths: Array) -> void:
	for p in paths:
		if FileAccess.file_exists(String(p)):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(String(p)))


static func _u20_untouched(before: Dictionary, paths: Array) -> bool:
	# Ключи снимка всегда заполнены на входе, поэтому default здесь — только
	# страховка от «ключа нет вовсе»: он никогда не совпадёт с текстом файла.
	for p in paths:
		if _u20_read_text(String(p)) != String(before.get(String(p), "__u20_no_snapshot__")):
			return false
	return true
