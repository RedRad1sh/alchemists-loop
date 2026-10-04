extends RefCounted
class_name Selftest
# Раннер селфтеста (оп B1): счётчики + голова/хвост + порядок сюит — как было в main.

static var _total := 0
static var _fails := 0

# U20 (T25) / U23 (T27): файлы приватного контейнера, очереди аналитики и их
# ST-двойники. С U23 перевод путей делают сами UserData/Analytics в своём _ready
# (см. REAL_*/ST_* константы autoload'ов); эти массивы — снимок настоящих файлов,
# сверка в конце прогона и вайп. Литералы обязаны совпадать с константами
# autoload'ов: проверяется кейсом u23 в начале run (рассинхрон красит его).
# Имена двойников те же, что использует tests/suite_journal_misc.gd.
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

	# U20 (T25): снимок «что лежало в настоящих файлах до прогона» и проверка в
	# конце по тексту каждого файла. С U23 (T27) автозагрузки переводят пути на
	# ST-двойники в своём _ready — раньше Main._ready, — поэтому настоящие файлы
	# в самопрогоне только читаются и снимок фиксирует ровно то, что было у
	# пользователя.
	var real_before := {}
	for rp in U20_REAL_FILES:
		real_before[String(rp)] = _u20_read_text(String(rp))
	# U23 (T27): слой перевода путей в автозагрузках. Кейсы идут ДО страховочного
	# перевода ниже — иначе страховка скрывала бы снятие ST-ветки из _ready.
	# Мутация первого кейса: убрать ветку `if not SelftestMode.enabled(): return`
	# и перевод в UserData._ready или Analytics._ready (путь к началу run останется
	# настоящим; страховочный блок ниже, через все четыре кейса, — уже после сверки).
	# Мутация второго: рассинхрон любого литерала U20_*_FILES с любой REAL_*/ST_*
	# константой autoload'а — молча меняются и снимок, и вайп.
	# Мутация третьего: перенести _load() в UserData._ready выше
	# _isolate_selftest_paths() (флаг ставится первой строкой _load(); снятие
	# ST-ветки красит и этот кейс).
	# Мутация четвёртого: убрать гейт `if not _selftest:` в main.gd —
	# session_start поднимет session_count в загруженном контейнере прогона.
	# Честная оговорка: сам факт «_ready отработал раньше первого обращения к
	# файлам» и boot-перезапись с идентичным нормализованным текстом (один только
	# mtime) изнутри сюиты ненаблюдаемы — guarded, untested, проверяются пунктом 1
	# приёмки (mtime/текст настоящих файлов) externally; всё перечисляемое выше
	# краснеет из сюиты.
	Selftest.check("u23 autoload paths already redirected before suite start",
		UserData.SAVE_PATH == UserData.ST_SAVE_PATH
		and UserData.TEMP_PATH == UserData.ST_TEMP_PATH
		and UserData.BACKUP_PATH == UserData.ST_BACKUP_PATH
		and UserData.PURCHASES_PATH == UserData.ST_PURCHASES_PATH
		and UserData.PURCHASES_TEMP_PATH == UserData.ST_PURCHASES_TEMP_PATH
		and Analytics.QUEUE_PATH == Analytics.ST_QUEUE_PATH)
	Selftest.check("u23 selftest path literals match the autoload constants",
		String(U20_REAL_FILES[0]) == UserData.REAL_SAVE_PATH
		and String(U20_REAL_FILES[1]) == UserData.REAL_TEMP_PATH
		and String(U20_REAL_FILES[2]) == UserData.REAL_BACKUP_PATH
		and String(U20_REAL_FILES[3]) == UserData.REAL_PURCHASES_PATH
		and String(U20_REAL_FILES[4]) == UserData.REAL_PURCHASES_TEMP_PATH
		and String(U20_REAL_FILES[5]) == Analytics.REAL_QUEUE_PATH
		and String(U20_ST_FILES[0]) == UserData.ST_SAVE_PATH
		and String(U20_ST_FILES[1]) == UserData.ST_TEMP_PATH
		and String(U20_ST_FILES[2]) == UserData.ST_BACKUP_PATH
		and String(U20_ST_FILES[3]) == UserData.ST_PURCHASES_PATH
		and String(U20_ST_FILES[4]) == UserData.ST_PURCHASES_TEMP_PATH
		and String(U20_ST_FILES[5]) == Analytics.ST_QUEUE_PATH)
	Selftest.check("u23 UserData boot load already read from the ST twin",
		UserData._boot_load_used_st_path)
	Selftest.check("u23 selftest boot started no analytics session before the suite",
		UserData.session_count() == 0)
	# U23 (T27): страховочный второй слой. В здоровом дереве — no-op (пути уже ST,
	# сверено кейсом выше) и нужен только на случай, кто-то позже снимает ветку из
	# _ready: метки сюиты по-прежнему не дойдут до настоящих файлов. Кейсы u20/
	# u22 ниже краснеют на снятии ОБЕИХ строк перевода (ветка в _ready + этот блок);
	# снятие одной красит кейсы u23 выше.
	UserData.SAVE_PATH = UserData.ST_SAVE_PATH
	UserData.TEMP_PATH = UserData.ST_TEMP_PATH
	UserData.BACKUP_PATH = UserData.ST_BACKUP_PATH
	UserData.PURCHASES_PATH = UserData.ST_PURCHASES_PATH
	UserData.PURCHASES_TEMP_PATH = UserData.ST_PURCHASES_TEMP_PATH
	Analytics.QUEUE_PATH = Analytics.ST_QUEUE_PATH
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
	# База кода — 105 рецептов; сейв игрока может добавить серверные (мир-крафты),
	# поэтому строгий ==105 краснел бы от прогресса. Инварианты: база не съедена
	# и все пары в списке уникальны (register/restore дедупят — дубликат красит).
	Selftest.check("recipes unique", g.RECIPES.size() >= 105 and keys.size() == g.RECIPES.size())
	Selftest.check("find steam", String(g._online._find_recipe("water", "fire").get("out", "") ) == "steam")
	Selftest.check("find empty", g._online._find_recipe("fire", "fire").is_empty())

	await SuiteCoreBrew.run(g)
	await SuiteLabModes.run(g)
	await SuiteRetortReturn.run(g)
	await SuiteResonanceNet.run(g)
	await SuiteOnlineUx.run(g)
	await SuiteBenchGifts.run(g)
	await SuiteCompanionAtlas.run(g)
	await SuiteQuestsGuild.run(g)
	await SuiteJournalMisc.run(g)
	await SuiteMonetization.run(g)
	await SuiteHintsHouse.run(g)
	await SuiteRiddlesRetention.run(g)
	await SuiteVeinCircle.run(g)
	await SuiteSigilCards.run(g)
	await SuiteSigilLore.run(g)

	_u20_wipe([g.SAVE_PATH, g.TEMP_PATH, g.BACKUP_PATH] + U20_ST_FILES)
	g.SAVE_PATH = "user://alchemy_save.json"
	g.TEMP_PATH = "user://alchemy_save.tmp"
	g.BACKUP_PATH = "user://alchemy_save.bak"
	# U23 (T27): пути UserData/Analytics обратно на настоящие имена НЕ
	# возвращаются (раньше это делалось здесь). Пока перевод жил только в run,
	# возврат был безвреден: дальше процесс умирал. Теперь ST-двойники стоят с
	# _ready автозагрузок весь прогон, и ранний возврат открыл бы окно (отложенные
	# changed/_save, задержка quit()), в котором живой процесс пишет настоящие
	# файлы — ровно тот дефект, который юнит чинит. Сверки ниже читают настоящие
	# файлы литералами U20_REAL_FILES, живые настоящие пути в конце прогона не
	# нужны ничему.
	# Каждый из трёх u20-чеков краснеет на снятии перевода путей ЦЕЛИКОМ: ST-ветки
	# из UserData._ready/Analytics._ready И страховочного блока в начале run (по
	# отдельности каждый слой ловят кейсы u23 выше). Тогда метки, которые пишет
	# tests/suite_monetization.gd («u20_sentinel_product» в сейв, «u20_hermetic_sku»
	# в журнал, «u20_probe_event» в очередь аналитики), ложатся в настоящие файлы,
	# и их текст перестаёт совпадать с real_before. Сравнение идёт по тексту каждого
	# файла, а не словарём через == (глубокое сравнение в Godot 4 пропустило бы
	# «просто совпало»). Остаточный blind spot честно отмечаем: boot-перезапись с
	# идентичным нормализованным текстом (один только mtime) из сюиты ненаблюдаема —
	# она закрыта пунктом 1 приёмки externally.
	Selftest.check("u20 selftest left the real user data file untouched",
		_u20_untouched(real_before, [String(U20_REAL_FILES[0]), String(U20_REAL_FILES[1]), String(U20_REAL_FILES[2])]))
	Selftest.check("u20 selftest left the real purchase journal untouched",
		_u20_untouched(real_before, [String(U20_REAL_FILES[3]), String(U20_REAL_FILES[4])]))
	Selftest.check("u20 selftest left the real analytics queue untouched",
		_u20_untouched(real_before, [String(U20_REAL_FILES[5])]))
	# U22 (T26): точка отсчёта — boot-снимки g, снятые в самом верху Main._ready
	# константными настоящими именами. С U23 (T27) окно «boot-снимок -> перевод
	# путей» схлопнулось: перевод уже случился в _ready автозагрузок, и записи
	# гейтимого блока main.gd падали бы в ST-двойники — снятие гейта
	# `if not _selftest:` этот кейс больше не красит, его ловит кейс u23
	# «...started no analytics session...» (session_count в памяти прогона).
	# Собственная красная пара этого кейса — снятие перевода путей ЦЕЛИКОМ
	# (ST-ветки из _ready автозагрузок + страховка в начале run): в настоящие
	# user.json/очередь ложатся метки сюиты, и их текст в конце прогона расходится
	# со снимком. Граница окна: до boot-снимка при intact-переводе настоящие файлы
	# не пишутся вообще, поэтому first-run fingerprint в снимке отсутствует, и
	# сверка честна для каждого из двух файлов.
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
