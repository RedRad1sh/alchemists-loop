extends RefCounted
class_name SuiteResonanceNet
# резонанс/маршрутизация сети (оп B1).

const NetBase := preload("res://autoload/net.gd")
const AppBase := preload("res://autoload/app.gd")

# T13: seam Net._try_send всегда возвращает ошибку старта запроса (эмулирует
# штатный для Android случай, когда HTTPRequest.request() падает в фоне/при
# смене сети) без живого сервера и без реального HTTP.
class FailSendNet extends NetBase:
	var attempts := 0
	func _try_send(_url: String, _headers: PackedStringArray, _method: int, _body: String) -> int:
		attempts += 1
		return ERR_CANT_CONNECT

# подписчик на *_*_result: collects dispatched dicts
class OfflineSink extends RefCounted:
	var results: Array[Dictionary] = []
	func catch(res: Dictionary) -> void:
		results.append(res)

# подписчик на Net.error: считает эмиссии (F1: слив очереди при пустом base_url
# не имеет права эмитировать error — только offline-результаты через _dispatch).
class ErrorSink extends RefCounted:
	var count := 0
	func note(_message: String) -> void:
		count += 1

static func run(g: Game) -> void:
	# резонанс: вехи, бонусы, claim-математика
	g._resonance._res_done.clear()
	g._resonance._res_total = 0
	var newly0 := g._resonance._res_check_milestones()
	Selftest.check("res no miles at zero", newly0.is_empty() and g._resonance._res_done.is_empty())
	g._resonance._res_total = 55
	var newly55 := g._resonance._res_check_milestones()
	Selftest.check("res miles 10+50", newly55 == [10, 50] and g._resonance._res_done.has(10) and g._resonance._res_done.has(50))
	Selftest.check("res regen bonus", is_equal_approx(g._resonance._res_regen_bonus(), Game.RES_REGEN10))
	Selftest.check("res cap bonus", g._resonance._res_cap_bonus() == Game.RES_CAP50)
	var c0 := g._engine._max_ether()
	g._resonance._res_done.clear()
	var c1 := g._engine._max_ether()
	Selftest.check("res cap wires into max ether", c0 - c1 == Game.RES_CAP50)
	g._resonance._res_done = {10: true, 50: true}
	g._resonance._res_total = 120
	var newly100 := g._resonance._res_check_milestones()
	Selftest.check("res mile 100 gilds", newly100 == [100] and g._resonance._res_gilded())
	g._resonance._res_balance = 7
	g._resonance._res_echo_ether = 5
	Selftest.check("res claim ether", g._resonance._res_claim_ether() == 35)
	g._resonance._res_balance = 0
	# страница резонанса строится и обновляется
	g._pages._select_mode("resonance")
	Selftest.check("res page visible", (g._pages._mode_pages["resonance"] as Control).visible)
	g._resonance._res_desc = [{"name": "ДитяЭха", "slug": "x", "by": "РезБ", "at": ""}]
	g._resonance._res_desc_total = 1
	g._resonance._refresh_resonance_page()
	Selftest.check("res page shows descendants", (g._resonance._res_lines.get_child(0) as Label).text.contains("ДитяЭха"))
	Selftest.check("res claim disabled w/o balance", g._resonance._res_claim_btn.disabled)
	# сейв/лоад вех и счётчиков
	g._resonance._res_done = {10: true}
	g._resonance._res_total = 12
	g._resonance._res_balance = 3
	g._saves._save_game()
	g._resonance._res_done.clear()
	g._resonance._res_total = 0
	g._resonance._res_balance = 0
	g._saves._load_game()
	Selftest.check("res persist", g._resonance._res_done.has(10) and g._resonance._res_total == 12 and g._resonance._res_balance == 3)
	# маршрутизация сети: claim и выгрузка домика идут POST на явные пути
	var b_claim := Net._build_request({"kind": "echoes_claim", "path": "/echoes/claim", "body": {"device_id": "d"}})
	Selftest.check("net claim route", String(b_claim["url"]).ends_with("/api/echoes/claim") and int(b_claim["method"]) == HTTPClient.METHOD_POST)
	var b_house := Net._build_request({"kind": "house_save", "path": "/house", "body": {"device_id": "d"}})
	Selftest.check("net house save route", String(b_house["url"]).ends_with("/api/house") and int(b_house["method"]) == HTTPClient.METHOD_POST)
	var b_get := Net._build_request({"kind": "echoes", "path": "/echoes?device_id=d"})
	Selftest.check("net echoes get route", String(b_get["url"]).ends_with("/echoes?device_id=d") and int(b_get["method"]) == HTTPClient.METHOD_GET)
	var b_export := Net._build_request({"kind": "account_export", "path": "/account/export?device_id=d"})
	Selftest.check("net privacy export route", String(b_export["url"]).ends_with("/api/account/export?device_id=d") and int(b_export["method"]) == HTTPClient.METHOD_GET)
	var b_delete := Net._build_request({"kind": "account_delete", "path": "/account?device_id=d", "method": HTTPClient.METHOD_DELETE})
	Selftest.check("net privacy delete route", String(b_delete["url"]).ends_with("/api/account?device_id=d") and int(b_delete["method"]) == HTTPClient.METHOD_DELETE)
	# ============ U19 (T24): рантайм-конфиг env → ProjectSettings → дефолт ============
	# Чистые статические швы: resolve_base_url / App.pick / privacy_url_is_real читают
	# только аргументы, поэтому headless-проверяемы без живого сервера и без
	# OS-состояния (тонкий читатель resolve_config, который трогает OS/ProjectSettings,
	# headless не покрываем — там нечего проверять сверх pick).
	# Мутационный анализ (какой кейс краснеет при удалении конъюнкта) — в имени ниже.
	# env важнее настройки: удалить «if url=="": url=setting» или переставить
	# порядок → краснеет u19 resolve env>setting.
	Selftest.check("u19 resolve env>setting", NetBase.resolve_base_url("https://env.svc", "https://set.svc", true) == "https://env.svc")
	# пустая настройка = «не задано» → DEFAULT_BASE: убрать ветку «url=="" → DEFAULT_BASE»
	# → краснеет u19 resolve default when unset.
	Selftest.check("u19 resolve default when unset", NetBase.resolve_base_url("", "", true) == NetBase.DEFAULT_BASE)
	# настройка подхватывается, когда env пуст: удалить step «env → setting» → red.
	Selftest.check("u19 resolve setting used", NetBase.resolve_base_url("", "https://set.svc", true) == "https://set.svc")
	# strip_edges(): env из одних пробелов = «не задано»; убрать strip_edges →
	# «   » сочтётся значением → краснеет u19 resolve blank env ignored.
	Selftest.check("u19 resolve blank env ignored", NetBase.resolve_base_url("   ", "https://set.svc", true) == "https://set.svc")
	# is_debug + begins_with("http://"): в релизе http:// → пустая строка («сервера
	# нет»); удалить is_debug-гейт или begins_with("http://") → краснеет
	# u19 resolve http refused in release.
	Selftest.check("u19 resolve http refused in release", NetBase.resolve_base_url("http://staging.local", "", false) == "")
	# в debug http проходит (иначе разработчик не протестирует localhost); инвертировать
	# is_debug → краснеет u19 resolve http allowed in debug.
	Selftest.check("u19 resolve http allowed in debug", NetBase.resolve_base_url("http://127.0.0.1:8080/api", "", true) == "http://127.0.0.1:8080/api")
	# https в релизе всегда проходит; удалить ветку → "" для https → краснеет ниже.
	Selftest.check("u19 resolve https ok in release", NetBase.resolve_base_url("https://api.svc", "", false) == "https://api.svc")
	# F2: чистое ядро App.pick. Переставить ветки (сначала настройка) ИЛИ удалить
	# «if env != "": return env» → краснеет ровно u19 pick env wins.
	Selftest.check("u19 pick env wins", AppBase.pick("https://env.cfg", "https://set.cfg") == "https://env.cfg")
	# пустой env берёт настройку: заменить шаг на безусловный «return env» →
	# краснеет u19 pick setting when env empty.
	Selftest.check("u19 pick setting when env empty", AppBase.pick("", "https://set.cfg") == "https://set.cfg")
	# env из одних пробелов = «не задано»: убрать strip_edges() на env_value →
	# «   » вернётся значением → краснеет ровно u19 pick whitespace env unset.
	Selftest.check("u19 pick whitespace env unset", AppBase.pick("   ", "https://set.cfg") == "https://set.cfg")
	# пробелы снимаются и с настройки: убрать strip_edges() на setting_value →
	# вернётся «  https://set.cfg  » → краснеет ровно u19 pick setting trimmed.
	Selftest.check("u19 pick setting trimmed", AppBase.pick("", "  https://set.cfg  ") == "https://set.cfg")
	# обе пустые = «не задано»: дефолт подставляет вызывающий, не pick; заменить
	# финальный return на любой литерал → краснеет u19 pick both unset empty.
	Selftest.check("u19 pick both unset empty", AppBase.pick("", "") == "")
	# пустой base_url обязан означать «ни одной HTTP-попытки» (ранний возврат
	# _send_next): убрать guard → FailSendNet попытается отправить → attempts!=0.
	# Ожидание «очередь = 1 элемент» было следствием прежнего молчаливого return;
	# по F1 очередь сливается offline-результатами, поэтому она пуста.
	var empty_net = FailSendNet.new()
	empty_net.base_url = ""
	empty_net._enqueue({"kind": "world", "path": "/world?page=1"})
	Selftest.check("u19 empty base_url does not send", empty_net.attempts == 0 and empty_net._inflight.is_empty() and empty_net._queue.is_empty())
	empty_net.free()
	# F1: пустой base_url закрывает ВЕСЬ накопленный backlog offline-результатами
	# через _dispatch (иначе подписчики rating/world/удаления аккаунта остаются с
	# предзаполненным статусом навсегда). Удалить вызов _drain_offline в _send_next
	# (или вернуть молчаливый return) → краснеет u19 empty base_url drains queue:
	# очередь остаётся непустой, attempts при этом по-прежнему 0.
	var drain_net = FailSendNet.new()
	var drain_world = OfflineSink.new()
	var drain_rating = OfflineSink.new()
	var drain_err = ErrorSink.new()
	drain_net.world_result.connect(drain_world.catch)
	drain_net.rating_result.connect(drain_rating.catch)
	drain_net.error.connect(drain_err.note)
	drain_net.base_url = ""
	drain_net._enqueue({"kind": "world", "path": "/world?page=1"})
	drain_net._enqueue({"kind": "rating"})
	# тот же мутационный removal роняет и этот кейс (sinks остаются пустыми);
	# «delete _drain_offline → return» даёт ровно такую же картину
	Selftest.check("u19 empty base_url drains queue", drain_net._queue.is_empty()
		and drain_net._inflight.is_empty() and drain_net.attempts == 0
		and not drain_net.is_available())
	# подмена offline-результата на ok:true (или пропажа message из аргумента
	# _drain_offline("сервер не настроен")) → краснеет этот кейс
	Selftest.check("u19 drain dispatches offline results", drain_world.results.size() == 1
		and drain_rating.results.size() == 1
		and bool(drain_world.results[0].get("offline", false))
		and not bool(drain_world.results[0].get("ok", true))
		and bool(drain_rating.results[0].get("offline", false))
		and String(drain_rating.results[0].get("message", "")) == "сервер не настроен")
	# добавить error.emit в drain-ветку (_dispatch его не эмитит ни в одной
	# ветке) → краснеет u19 drain emits no error. Красность этого кейса держится
	# ещё и на подключении подписчика выше
	# (`drain_net.error.connect(drain_err.note)`): без него count остаётся 0 при
	# любом error.emit, поэтому мутация «удалить connect» называется здесь же.
	Selftest.check("u19 drain emits no error", drain_err.count == 0)
	drain_net.free()
	# privacy_url_is_real: https без placeholder'ов = true (удалить begins_with →
	# red на http-кейсе; удалить example.com-ветку → red на u19 privacy example.com).
	# Домен — alchemists-loop.dev, НЕ *.example.*: позитивный кейс не должен
	# проверять опечатку в списке placeholder'ов.
	Selftest.check("u19 privacy real https", AppBase.privacy_url_is_real("https://alchemists-loop.dev/privacy"))
	# strip_edges(): валидный https в обнимку с пробелами всё ещё реален; убрать
	# strip_edges → begins_with("https://") не совпадёт → краснеет этот кейс.
	Selftest.check("u19 privacy blank padded real", AppBase.privacy_url_is_real("  https://loop.dev/privacy  "))
	Selftest.check("u19 privacy http false", not AppBase.privacy_url_is_real("http://alchemists-loop.dev/privacy"))
	Selftest.check("u19 privacy empty false", not AppBase.privacy_url_is_real(""))
	# placeholder-дефолт из project.godot выглядит настроенным — он не настоящий.
	Selftest.check("u19 privacy example.com false", not AppBase.privacy_url_is_real("https://example.com/alchemists-loop/privacy"))
	Selftest.check("u19 privacy localhost false", not AppBase.privacy_url_is_real("https://localhost:8080/privacy"))
	# ============ /U19 ============

	# T13: если _try_send вернул err != OK, очередь НЕ дедлокавится — каждый
	# каждый поставленный в очередь запрос получает offline-результат, _inflight
	# пуст, очередь жива
	var dead_net = FailSendNet.new()
	var sink_world = OfflineSink.new()
	var sink_rating = OfflineSink.new()
	dead_net.world_result.connect(sink_world.catch)
	dead_net.rating_result.connect(sink_rating.catch)
	dead_net._enqueue({"kind": "world", "path": "/world?page=1"})
	dead_net._enqueue({"kind": "rating"})
	dead_net._enqueue({"kind": "world", "path": "/world?page=2"})
	Selftest.check("net err no deadlock", dead_net._inflight.is_empty() and dead_net._queue.is_empty() and dead_net.attempts == 3)
	Selftest.check("net err offline dispatched", sink_world.results.size() == 2 and sink_rating.results.size() == 1
		and bool(sink_world.results[0].get("offline", false)) and not bool(sink_world.results[0].get("ok", true))
		and bool(sink_rating.results[0].get("offline", false)))
	# ping-частный случай: err по-прежнему снимает flag доступности
	dead_net._available = true
	dead_net._ping()
	Selftest.check("net err ping clears available", not bool(dead_net._available) and dead_net.attempts == 4)
	# последующий enqueue снова реально пытается отправить (очередь разблокирована)
	var attempts_before := int(dead_net.attempts)
	dead_net.world(3)
	Selftest.check("net err queue live after fail", int(dead_net.attempts) == attempts_before + 1 and dead_net._inflight.is_empty())
	# I1: ре-ентрантный _send_next при живом _inflight не должен снимать очередь
	# с дрейна и перетирать «висящий» запрос (продолжение — из _on_completed).
	# Форма с sentinel: у FailSendNet вся вложенная отправка падает синхронно и
	# сама же гасит _inflight, поэтому «живой _inflight на внешнем хвосте» в том
	# harness недостижим детерминированно — поле ставится напрямую.
	var guard_net = FailSendNet.new()
	var sink_guard = OfflineSink.new()
	guard_net.world_result.connect(sink_guard.catch)
	guard_net._inflight = {"kind": "sentinel"}
	guard_net._enqueue({"kind": "world", "path": "/world?page=9"})
	Selftest.check("net inflight guard holds", guard_net._queue.size() == 1 and guard_net.attempts == 0)
	guard_net._send_next()
	Selftest.check("net inflight guard blocks send", guard_net._queue.size() == 1 and guard_net.attempts == 0
		and sink_guard.results.is_empty() and String(guard_net._inflight.get("kind", "")) == "sentinel")
	guard_net._inflight = {}
	guard_net._send_next()
	Selftest.check("net inflight guard releases", guard_net._queue.is_empty() and guard_net.attempts == 1
		and sink_guard.results.size() == 1 and guard_net._inflight.is_empty())
	guard_net.free()
	dead_net.free()
	g._engine.ether = 300
	var a_before := int(g._engine.inventory.get("water", 0))
	g._engine.spring_source = "water"
	g._engine.spring_on = true
	g._pages._spring_clock = 0.0
	g._engine._spring_tick(Game.SPRING_INTERVAL + 0.01)
	Selftest.check("spring drop", int(g._engine.inventory.get("water", 0)) == a_before + 1)
	g._engine.spring_on = false
	# ============ U11 (T14/T15): корреляция запрос↔ответ и grant world-opened ============
	# Обработчики дёргаются напрямую синтезированными сигналами по pair_key;
	# pending заполняется вызовами _register_pending_pair — Net не трогаем
	# (герметично, без сети). Снимок затрагиваемого состояния — в конце restore.
	var u11_inv := g._engine.inventory.duplicate(true)
	var u11_known := g._engine.known_recipes.duplicate(true)
	var u11_rejected := g._engine._rejected_pairs.duplicate(true)
	var u11_recipes := g.RECIPES.duplicate(true)
	var u11_srv_recipes := g._online._server_recipes.duplicate(true)
	var u11_srv_authors := g._online._server_authors.duplicate(true)
	var u11_srv_els := g._online._server_elements.duplicate(true)
	var u11_srv_layers := g._online._server_layers.duplicate(true)
	var u11_items := g.ITEMS.duplicate(true)
	var u11_colors := g._item_colors.duplicate(true)
	var u11_layer_cache := g._engine._layer_cache.duplicate(true)
	var u11_pending := g._online._pending_requests.duplicate(true)
	var u11_exp_pair := g._engine._experiment_pending_pair.duplicate()
	var u11_first_opens := g._engine._first_open_calls
	# F3 добавляет _circle_on_discovery в мир-ветки (он НЕ гейтится selftest → мутирует
	# _circle_disc/_circle_disc_day); возврат при prune (F1) идёт через негейтимый
	# _grant_ether (полный EXPERIMENT_COST в ether+overflow) — оба восстанавливаем.
	var u11_ether := g._engine.ether
	var u11_ether_overflow := g._engine.ether_overflow
	var u11_circle_disc := g._retention._circle_disc
	var u11_circle_disc_day := g._retention._circle_disc_day
	# Попап первооткрытия — тоже затрагиваемое состояние: мир-ветки зовут
	# main.gd::_show_discovery_popup, и без возврата он висел бы на следующей
	# сюите (её canary чистого стека модалок ловил именно его).
	var u11_popup := g._popup.visible
	var u11_popup_dim := g._popup_dim.visible
	g._online._pending_requests.clear()
	# (1) «enqueue-перехват»: пока X ждёт ответа, Y слот не перезахватывает;
	# поздний ответ X применяет награду строго своей паре.
	var u11_kx := g._pair_key("fire", "air")
	var u11_ky := g._pair_key("earth", "air")
	var u11_kx_before := g._engine.known_recipes.has(u11_kx)
	var u11_ky_before := g._engine.known_recipes.has(u11_ky)
	Selftest.check("t14 register first pair", g._online._register_pending_pair("fire", "air", false)
		and g._online._pending_requests.size() == 1)
	Selftest.check("t14 pending not rehooked", not g._online._register_pending_pair("earth", "air", false)
		and g._online._pending_requests.size() == 1 and g._online._pending_requests.has(u11_kx))
	g._online._on_net_pair_result(u11_kx, {"ok": true, "found": true, "status": "known",
		"out": {"slug": "u11_x_out", "name": "U11-X", "color": "#44aa55", "glyph": "fire", "layer": 1}})
	Selftest.check("t14 late response grants only its pair", int(g._engine.inventory.get("u11_x_out", 0)) == 1
		and g._engine.known_recipes.has(u11_kx)
		and g._engine.known_recipes.has(u11_ky) == u11_ky_before
		and g._online._pending_requests.is_empty())
	# (2) «поздний дубликат»: ответ с неизвестным pair_key (и без записи pending)
	# дропается без начислений — и в pair-, и в discover-фазе.
	g._online._on_net_pair_result(u11_kx, {"ok": true, "found": true, "status": "known",
		"out": {"slug": "u11_dup", "name": "U11-дубль", "color": "#aa4455", "glyph": "fire", "layer": 1}})
	g._online._on_net_discover_result(g._pair_key("bogus1", "bogus2"), {"status": "known",
		"discovery": {"slug": "u11_dup2", "name": "U11-дубль2", "color": "#5544aa", "glyph": "fire",
			"layer": 1, "a": "bogus1", "b": "bogus2", "author": "N"}})
	Selftest.check("t14 late duplicate dropped", not g._engine.inventory.has("u11_dup")
		and not g._engine.inventory.has("u11_dup2") and not g.ITEMS.has("u11_dup")
		and not g._engine.known_recipes.has(g._pair_key("bogus1", "bogus2")))
	# (3) discover с пустыми/чужими a/b дропается (раньше пустые a/b дарили
	# вещество «ни за что»); согласованные a/b — гран своей паре.
	Selftest.check("t14 register for discover", g._online._register_pending_pair("fire", "air", false))
	g._online._on_net_discover_result(u11_kx, {"status": "created",
		"discovery": {"slug": "u11_bad1", "name": "U11-пусто", "color": "#112233", "glyph": "fire",
			"layer": 1, "a": "", "b": "", "author": "N"}})
	Selftest.check("t14 discover empty a/b dropped", not g._engine.inventory.has("u11_bad1")
		and not g.ITEMS.has("u11_bad1"))
	Selftest.check("t14 re-register after drop", g._online._register_pending_pair("fire", "air", false))
	g._online._on_net_discover_result(u11_kx, {"status": "created",
		"discovery": {"slug": "u11_bad2", "name": "U11-чужая", "color": "#112233", "glyph": "fire",
			"layer": 1, "a": "water", "b": "steam", "author": "N"}})
	Selftest.check("t14 discover mismatched a/b dropped", not g._engine.inventory.has("u11_bad2")
		and not g.ITEMS.has("u11_bad2"))
	Selftest.check("t14 re-register third", g._online._register_pending_pair("fire", "air", false))
	g._online._on_net_discover_result(u11_kx, {"status": "known",
		"discovery": {"slug": "u11_ok", "name": "U11-ок", "color": "#22aa88", "glyph": "fire",
			"layer": 1, "a": "air", "b": "fire", "author": "N"}})
	Selftest.check("t14 discover grants its pair", int(g._engine.inventory.get("u11_ok", 0)) == 1
		and g._engine.known_recipes.has(u11_kx))
	# (4) T15-контракт: found=true (пара уже открыта в мире) при ПЕРВОМ
	# локальном получении проходит _grant_first_open ровно один раз; вторая
	# доставка той же пары — только +1 в стек, без повторного гранта.
	var u11_fo0 := g._engine._first_open_calls
	var u11_kz := g._pair_key("water", "earth")
	var u11_kz_before := g._engine.known_recipes.has(u11_kz)
	Selftest.check("t15 register world-opened pair", g._online._register_pending_pair("water", "earth", false))
	g._online._on_net_pair_result(u11_kz, {"ok": true, "found": true, "status": "known",
		"out": {"slug": "u15_world", "name": "U15-мир", "color": "#3388aa", "glyph": "fire", "layer": 1}})
	Selftest.check("t15 first acquisition grants first-open", int(g._engine.inventory.get("u15_world", 0)) == 1
		and g._engine._first_open_calls == u11_fo0 + 1)
	Selftest.check("t15 re-register same pair", g._online._register_pending_pair("water", "earth", false))
	g._online._on_net_pair_result(u11_kz, {"ok": true, "found": true, "status": "known",
		"out": {"slug": "u15_world", "name": "U15-мир", "color": "#3388aa", "glyph": "fire", "layer": 1}})
	Selftest.check("t15 second acquisition no re-grant", int(g._engine.inventory.get("u15_world", 0)) == 2
		and g._engine._first_open_calls == u11_fo0 + 1)
	# (5) U9-прикрытый зазор: поздний ответ СТАРОЙ экспериментальной пары, пока
	# висит новый эксперимент, дропается в обеих фазах (рецепт/вещество/
	# pending эксперимента не тронуты).
	g._engine._experiment_pending_pair = ["fire", "water"]
	var u11_kold := g._pair_key("u14_old_a", "u14_old_b")
	Selftest.check("t14 register orphan experiment", g._online._register_pending_pair("u14_old_a", "u14_old_b", true))
	g._online._on_net_pair_result(u11_kold, {"ok": true, "found": true, "status": "known",
		"out": {"slug": "u14_ghost", "name": "U14-призрак", "color": "#112233", "glyph": "fire", "layer": 1}})
	Selftest.check("t14 old-pair experiment response dropped", not g.ITEMS.has("u14_ghost")
		and not g._engine.inventory.has("u14_ghost") and not g._engine.known_recipes.has(u11_kold)
		and g._engine._experiment_pending_pair == ["fire", "water"]
		and g._online._pending_requests.is_empty())
	Selftest.check("t14 re-register orphan experiment", g._online._register_pending_pair("u14_old_a", "u14_old_b", true))
	g._online._on_net_discover_result(u11_kold, {"status": "created",
		"discovery": {"slug": "u14_ghost2", "name": "U14-призрак2", "color": "#112233", "glyph": "fire",
			"layer": 1, "a": "u14_old_a", "b": "u14_old_b", "author": "N"}})
	Selftest.check("t14 old-pair discover response dropped", not g.ITEMS.has("u14_ghost2")
		and not g._engine.inventory.has("u14_ghost2")
		and g._engine._experiment_pending_pair == ["fire", "water"])
	# TTL- pruning: запись старше PENDING_TTL_MSEC не переживает следующее
	# обращение (форсим «возраст» прямой записью at).
	g._online._register_pending_pair("fire", "air", false)
	var u11_tkey := g._pair_key("fire", "air")
	var u11_stale: Dictionary = g._online._pending_requests[u11_tkey]
	u11_stale["at"] = Time.get_ticks_msec() - g._online.PENDING_TTL_MSEC - 1000
	g._online._on_net_pair_result(u11_tkey, {"ok": true, "found": true, "status": "known",
		"out": {"slug": "u14_ttl", "name": "U14-TTL", "color": "#112233", "glyph": "fire", "layer": 1}})
	Selftest.check("t14 stale pending pruned", not g._engine.inventory.has("u14_ttl")
		and g._online._pending_requests.is_empty())
	# F1: TTL-prune ЖИВОГО эксперимента не осирочивает его — возвращает реагенты
	# и полный эфир (иначе _experiment_pending_pair size 2 блокировал бы варку,
	# «Начать заново» и престиж до перезапуска). Прунинг — обычным входом: поздний
	# ответ той же пары (запись изымается уже после prune → ответ дропается).
	g._engine._experiment_pending_pair = ["u14_exp_a", "u14_exp_b"]
	Selftest.check("u11 prune-exp register", g._online._register_pending_pair("u14_exp_a", "u14_exp_b", true))
	var u11_expkey := g._pair_key("u14_exp_a", "u14_exp_b")
	var u11_expiring: Dictionary = g._online._pending_requests[u11_expkey]
	u11_expiring["at"] = Time.get_ticks_msec() - g._online.PENDING_TTL_MSEC - 1000
	var u11_avail0 := g._engine.ether + g._engine.ether_overflow
	g._online._on_net_pair_result(u11_expkey, {"ok": true, "found": true, "status": "known"})
	Selftest.check("u11 prune-exp refunds reagents", g._engine._experiment_pending_pair.is_empty()
		and int(g._engine.inventory.get("u14_exp_a", 0)) == 1
		and int(g._engine.inventory.get("u14_exp_b", 0)) == 1)
	Selftest.check("u11 prune-exp refunds ether", g._online._pending_requests.is_empty()
		and g._engine.ether + g._engine.ether_overflow == u11_avail0 + Game.EXPERIMENT_COST)
	# restore: мир после блока U11 — точно таким же, как до него.
	g._engine.inventory = u11_inv
	g._engine.known_recipes = u11_known
	g._engine._rejected_pairs = u11_rejected
	g.RECIPES = u11_recipes
	g._online._server_recipes = u11_srv_recipes
	g._online._server_authors = u11_srv_authors
	g._online._server_elements = u11_srv_els
	g._online._server_layers = u11_srv_layers
	g.ITEMS = u11_items
	g._item_colors = u11_colors
	g._engine._layer_cache = u11_layer_cache
	g._online._pending_requests = u11_pending
	g._engine._first_open_calls = u11_first_opens
	g._engine.ether = u11_ether
	g._engine.ether_overflow = u11_ether_overflow
	g._retention._circle_disc = u11_circle_disc
	g._retention._circle_disc_day = u11_circle_disc_day
	# Возврат модалки. Мутация этих двух строк — «esc stack was clean on entry» в
	# suite_journal_misc: без них открытое «НОВЫЙ РЕЦЕПТ!» доживает до её canary.
	g._popup.visible = u11_popup
	g._popup_dim.visible = u11_popup_dim
	g._engine._experiment_pending_pair.clear()
	for u11_raw_e in u11_exp_pair:
		g._engine._experiment_pending_pair.append(String(u11_raw_e))
	# ассерт чувствителен к откату: посаженные slug'ы исчезли из ITEMS/inventory,
	# known_recipes по использованным парам вернулись к досюжетным значениям, а
	# ether/overflow/круг восстановлены (сравнение объекта с самим собой ничего бы
	# не проверяло — сравниваем независимые снимки).
	var u11_clean := true
	for u11_p in ["u11_x_out", "u11_ok", "u15_world", "u14_ghost", "u14_ghost2",
		"u11_dup", "u11_dup2", "u11_bad1", "u11_bad2", "u14_ttl", "u14_exp_a", "u14_exp_b"]:
		if g.ITEMS.has(String(u11_p)) or g._engine.inventory.has(String(u11_p)):
			u11_clean = false
	Selftest.check("u11 state restored", u11_clean
		and g._engine.known_recipes.has(u11_kx) == u11_kx_before
		and g._engine.known_recipes.has(u11_ky) == u11_ky_before
		and g._engine.known_recipes.has(u11_kz) == u11_kz_before
		and g._online._pending_requests.is_empty()
		and g._engine.ether == u11_ether and g._engine.ether_overflow == u11_ether_overflow
		and g._retention._circle_disc == u11_circle_disc
		and g._retention._circle_disc_day == u11_circle_disc_day)

	# ============ U13 (T17): окно «claim отголосков в пути» ============
	# Трата асинхронная, поэтому окно — не кадр, а round-trip до ответа мира.
	# Гейт чистый (часы параметром). Net не задеваем: _claim_echoes вызывается
	# только при заведомо выключенном мире, где отправка невозможна в принципе.
	var u13_claim_at := g._resonance._res_claim_at
	var u13_balance := g._resonance._res_balance
	var u13_total := g._resonance._res_total
	var u13_echo := g._resonance._res_echo_ether
	var u13_cap := g._resonance._res_cap
	var u13_desc := g._resonance._res_desc.duplicate(true)
	var u13_desc_total := g._resonance._res_desc_total
	var u13_top := g._resonance._res_top.duplicate(true)
	var u13_apprentice := g._resonance._res_apprentice.duplicate(true)
	var u13_ether := g._engine.ether
	var u13_overflow := g._engine.ether_overflow
	var u13_status := g._engine.status_text
	var u13_net_on := g._online._net_enabled
	var u13_device := g._online._device_id
	g._resonance._res_claim_at = 0
	Selftest.check("u13 claim gate arms", g._resonance._claim_gate(1000))
	Selftest.check("u13 claim gate refuses while in flight", not g._resonance._claim_gate(1100)
		and not g._resonance._claim_gate(1000 + Game.RESONANCE_CLAIM_GATE_MSEC - 1))
	# self-heal: потерянный ответ не должен запирать claim до конца сессии
	Selftest.check("u13 claim gate opens after round-trip window",
		g._resonance._claim_gate(1000 + Game.RESONANCE_CLAIM_GATE_MSEC))
	# ответ мира освобождает окно на обеих ветках
	g._resonance._res_claim_at = 1234
	g._resonance._on_net_echoes_claim_result({"ok": false})
	Selftest.check("u13 claim window releases on failed reply", g._resonance._res_claim_at == 0)
	g._resonance._res_claim_at = 1234
	g._resonance._res_balance = 0
	g._resonance._on_net_echoes_claim_result({"ok": true, "claimed": 0, "ether": 0})
	Selftest.check("u13 claim window releases on ok reply", g._resonance._res_claim_at == 0
		and g._engine.ether + g._engine.ether_overflow == u13_ether + u13_overflow)
	# тап «Забрать» без мира: окно не взведено (гейт стоит после check'ов связи),
	# запрос не порождается. Размер очереди Net тут ничего не доказывает: в
	# селфтесте base_url пуст (герметичный прогон), и enqueue-нутый запрос слился
	# бы синхронно — очередь осталась бы пуста. Считаем фактические dispatch'и:
	# echoes_claim_result эмитится только если трата действительно ушла в Net.
	g._resonance._res_claim_at = 0
	g._resonance._res_balance = 5
	g._online._net_enabled = false
	var u13_claims := [0]
	var u13_probe := func(_res: Dictionary) -> void: u13_claims[0] += 1
	Net.echoes_claim_result.connect(u13_probe)
	g._resonance._claim_echoes()
	Net.echoes_claim_result.disconnect(u13_probe)
	Selftest.check("u13 offline claim neither arms nor sends", g._resonance._res_claim_at == 0
		and u13_claims[0] == 0
		and String(Net._inflight.get("kind", "")) != "echoes_claim"
		and g._resonance._res_balance == 5)
	# restore: состояние резонанса и эфира — как до блока
	g._resonance._res_claim_at = u13_claim_at
	g._resonance._res_balance = u13_balance
	g._resonance._res_total = u13_total
	g._resonance._res_echo_ether = u13_echo
	g._resonance._res_cap = u13_cap
	g._resonance._res_desc = u13_desc
	g._resonance._res_desc_total = u13_desc_total
	g._resonance._res_top = u13_top
	g._resonance._res_apprentice = u13_apprentice
	g._engine.ether = u13_ether
	g._engine.ether_overflow = u13_overflow
	g._engine.status_text = u13_status
	g._online._net_enabled = u13_net_on
	g._online._device_id = u13_device
	Selftest.check("u13 resonance state restored", g._resonance._res_balance == u13_balance
		and g._resonance._res_total == u13_total
		and g._resonance._res_claim_at == u13_claim_at
		and g._engine.ether == u13_ether and g._engine.ether_overflow == u13_overflow
		and g._online._net_enabled == u13_net_on and g._online._device_id == u13_device)

	# ============ I-1 (T28): detail non-2xx-тела в Net._on_completed ============
	# Синтетический non-2xx прогоняется через единственную точку выхода HTTP:
	# _on_completed вызывается напрямую (result=RESULT_SUCCESS — «запрос дошёл»,
	# ответ — серверный код), живой сети нет; _inflight подставляется вручную,
	# ведь разбор идёт по уже снятому запросу. Мутация «удалить извлечение
	# detail из non-2xx-ветки» красит первый кейс; мутация «писать detail без
	# проверки тела/типа» (или снять typeof-гейт) красит второй: dict-detail
	# (/api/receipt/verify) и не-JSON-тело не должны уходить вверх — иначе hub
	# показал бы «Имя не принято: {…}», а монетизация прочитала мусор.
	var t28_net := NetBase.new()
	var t28_me := OfflineSink.new()
	t28_net.me_result.connect(t28_me.catch)
	t28_net._inflight = {"kind": "me"}
	t28_net._on_completed(HTTPRequest.RESULT_SUCCESS, 400, PackedStringArray(),
		JSON.stringify({"detail": "Ник уже занят"}).to_utf8_buffer())
	Selftest.check("t28 net extracts string detail", t28_me.results.size() == 1
		and String(t28_me.results[0].get("detail", "")) == "Ник уже занят"
		and String(t28_me.results[0].get("error", "")) == "HTTP 400"
		and String(t28_me.results[0].get("message", "")) == "HTTP 400"
		and not bool(t28_me.results[0].get("ok", true)))
	t28_net._inflight = {"kind": "me"}
	t28_net._on_completed(HTTPRequest.RESULT_SUCCESS, 400, PackedStringArray(),
		JSON.stringify({"ok": false, "detail": {"reason": "unknown_sku"}}).to_utf8_buffer())
	t28_net._inflight = {"kind": "me"}
	t28_net._on_completed(HTTPRequest.RESULT_SUCCESS, 502, PackedStringArray(),
		"не json".to_utf8_buffer())
	Selftest.check("t28 net ignores non string detail", t28_me.results.size() == 3
		and not t28_me.results[1].has("detail")
		and String(t28_me.results[1].get("error", "")) == "HTTP 400"
		and not t28_me.results[2].has("detail")
		and String(t28_me.results[2].get("error", "")) == "HTTP 502")
	t28_net.free()

	# ============ I-2: 2xx с не-JSON телом = отказ, а не «сервер жив» ============
	# Заглушка/антибот хостинга отвечает 200 на любой путь и отдаёт HTML. До фикса
	# такая ветка ставила _available = true и сливала подписчикам пустой словарь:
	# игра считала сервер здоровым, никогда не уходила в офлайн и оставалась с
	# предзаполненными статусами (мир/атлас/неделя не доходят). Мутация «оставить
	# _available = true без проверки тела» красит первый кейс, мутация «слать
	# parsed как есть (без ok:false/offline)» красит второй, мутация «выбросить
	# else-ветку» (ok/available для нормального JSON) красит третий.
	var i2_net := NetBase.new()
	var i2_world := OfflineSink.new()
	i2_net.world_result.connect(i2_world.catch)
	i2_net._inflight = {"kind": "world"}
	i2_net._on_completed(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(),
		"<html><body>access denied</body></html>".to_utf8_buffer())
	Selftest.check("i2 net non-json 2xx keeps server unavailable", not i2_net.is_available())
	Selftest.check("i2 net non-json 2xx dispatches offline", i2_world.results.size() == 1
		and not bool(i2_world.results[0].get("ok", true))
		and bool(i2_world.results[0].get("offline", false)))
	i2_net._inflight = {"kind": "world"}
	i2_net._on_completed(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(),
		JSON.stringify({"page": 1, "items": []}).to_utf8_buffer())
	Selftest.check("i2 net json 2xx marks available", i2_net.is_available()
		and i2_world.results.size() == 2
		and bool(i2_world.results[1].get("ok", false))
		and int(i2_world.results[1].get("page", 0)) == 1
		and not bool(i2_world.results[1].get("offline", false)))
	i2_net.free()
