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

class CaptureNet extends NetBase:
	var last_url := ""
	var last_body := ""
	var last_method := 0
	func _try_send(url: String, _headers: PackedStringArray, method: int, body: String) -> int:
		last_url = url
		last_body = body
		last_method = method
		return ERR_CANT_CONNECT

class TargetAttemptSink extends RefCounted:
	var request_ids: Array[String] = []
	var pair_keys: Array[String] = []
	var results: Array[Dictionary] = []
	func catch(request_id: String, pair_key: String, result: Dictionary) -> void:
		request_ids.append(request_id)
		pair_keys.append(pair_key)
		results.append(result)

# подписчик на *_*_result: collects dispatched dicts
class OfflineSink extends RefCounted:
	var results: Array[Dictionary] = []
	var nonces: Array[String] = []
	func catch(res: Dictionary, sync_nonce: String = "") -> void:
		results.append(res)
		nonces.append(sync_nonce)

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
	# ============ Experiment: no-reagent start, success-only ether ============
	var exp_inv_before := g._engine.inventory.duplicate(true)
	var exp_known_before := g._engine.known_recipes.duplicate(true)
	var exp_rejected_before := g._engine._rejected_pairs.duplicate(true)
	var exp_pending_before := g._engine._experiment_pending_pair.duplicate()
	var exp_reserved_before := g._engine._experiment_reserved_ether
	var exp_ether_before := g._engine.ether
	var exp_overflow_before := g._engine.ether_overflow
	var exp_attempts_before := g._engine.attempts
	var exp_successes_before := g._engine.successes
	var exp_day_before := g._engine._experiment_day
	var exp_count_before := g._engine._experiment_count
	var exp_last_at_before := g._engine._experiment_last_at
	var exp_pair := g._pair_key("fire", "water")
	g._engine.inventory["fire"] = 0
	g._engine.inventory["water"] = 0
	g._engine.known_recipes.erase(exp_pair)
	g._engine._rejected_pairs.erase(exp_pair)
	g._engine._experiment_pending_pair.clear()
	g._engine._experiment_reserved_ether = 0
	g._engine._experiment_day = ""
	g._engine._experiment_count = 0
	g._engine._experiment_last_at = 0.0
	g._engine.ether = Game.EXPERIMENT_COST
	g._engine.ether_overflow = 0
	var exp_visible_before := g._engine.ether
	var exp_available_before := g._engine._available_ether()
	var exp_started := g._engine._begin_experiment("fire", "water")
	Selftest.check("experiment starts with zero reagent stock", exp_started)
	Selftest.check("experiment start keeps visible ether and reserves its cost",
		g._engine.ether == exp_visible_before
		and g._engine._available_ether() == exp_available_before - Game.EXPERIMENT_COST)
	Selftest.check("reserved experiment ether cannot fund a parallel spend",
		not g._engine._spend_ether(1) and g._engine.ether == exp_visible_before)
	g._engine.ether = exp_visible_before
	g._engine._cancel_experiment("earth", "air")
	Selftest.check("mismatched cancel keeps the experiment reserve",
		g._engine._available_ether() == exp_available_before - Game.EXPERIMENT_COST)
	g._engine._cancel_experiment("fire", "water")
	Selftest.check("cancel releases reserve without a debit",
		g._engine._available_ether() == exp_available_before and g._engine.ether == exp_visible_before)
	g._engine._experiment_pending_pair = ["fire", "water"]
	g._engine._experiment_reserved_ether = Game.EXPERIMENT_COST
	var exp_failed_visible_before := g._engine.ether
	var exp_failed_available_before := g._engine._available_ether()
	g._engine._experiment_failed("fire", "water")
	Selftest.check("experiment failure keeps reagents",
		g._engine.inventory.get("fire", 0) == 0
		and g._engine.inventory.get("water", 0) == 0
		and g._engine._experiment_pending_pair.is_empty())
	Selftest.check("experiment failure releases reserve without ether debit",
		g._engine.ether == exp_failed_visible_before
		and g._engine._available_ether() == exp_failed_available_before + Game.EXPERIMENT_COST)
	g._engine._rejected_pairs.erase(exp_pair)
	g._engine._experiment_last_at = 0.0
	g._engine._experiment_count = 0
	var exp_success_started := g._engine._begin_experiment("fire", "water")
	var exp_success_available_before := g._engine._available_ether()
	var exp_success_visible_before := g._engine.ether
	g._engine._experiment_succeeded("steam", "fire", "water")
	var exp_success_available_after := g._engine._available_ether()
	Selftest.check("experiment success settles its reserve and charges once",
		exp_success_started and exp_success_visible_before - g._engine.ether == Game.EXPERIMENT_COST
		and exp_success_available_before == exp_success_available_after)
	g._engine._experiment_succeeded("steam", "fire", "water")
	Selftest.check("experiment duplicate success does not charge twice", exp_success_available_after == g._engine._available_ether())
	g._engine.known_recipes.erase(exp_pair)
	g._engine._rejected_pairs.erase(exp_pair)
	g._engine._experiment_last_at = 0.0
	g._engine._experiment_count = 0
	g._engine.ether = Game.EXPERIMENT_COST
	g._engine.ether_overflow = 0
	var reused_started := g._engine._begin_experiment("fire", "water")
	var reused_available_before := g._engine._available_ether()
	var reused_visible_before := g._engine.ether
	g._engine._experiment_succeeded("steam", "fire", "water", "known")
	Selftest.check("experiment known owned output releases reserve without ether debit",
		reused_started and g._engine.ether == reused_visible_before
		and g._engine._available_ether() == reused_available_before + Game.EXPERIMENT_COST
		and int(g._engine.inventory.get("steam", 0)) == int(exp_inv_before.get("steam", 0)) + 2)
	g._engine.known_recipes[exp_pair] = true
	g._engine._experiment_last_at = 0.0
	g._engine._experiment_count = 0
	var target_started := g._engine._begin_experiment("fire", "water", true)
	Selftest.check("target experiment may resolve a locally known pair", target_started)
	g._engine._cancel_experiment("fire", "water")

	var reserve_spring_levels := g._engine.spring_levels.duplicate(true)
	var reserve_spring_inventory := g._engine.inventory.duplicate(true)
	g._engine.inventory["stone"] = 99
	g._engine.known_recipes.erase(exp_pair)
	g._engine._rejected_pairs.erase(exp_pair)
	g._engine._experiment_last_at = 0.0
	g._engine._experiment_count = 0
	g._engine.spring_levels["speed"] = 0
	g._engine.ether = Game.EXPERIMENT_COST + 29
	g._engine.ether_overflow = 0
	var reserve_spring_started := g._engine._begin_experiment("fire", "water")
	var reserve_spring_result: Dictionary = g._engine.spring_purchase("speed")
	Selftest.check("spring purchase cannot consume pending experiment ether",
		reserve_spring_started and not bool(reserve_spring_result.get("ok", false))
		and String(reserve_spring_result.get("error", "")).contains("ether")
		and g._engine.ether == Game.EXPERIMENT_COST + 29 and g._engine.spring_levels["speed"] == 0
		and int(g._engine.inventory.get("stone", 0)) == 99)
	g._engine._cancel_experiment("fire", "water")
	g._engine.spring_levels = reserve_spring_levels
	g._engine.inventory = reserve_spring_inventory
	g._engine.inventory = exp_inv_before
	g._engine.known_recipes = exp_known_before
	g._engine._rejected_pairs = exp_rejected_before
	g._engine._experiment_pending_pair.clear()
	for exp_raw in exp_pending_before:
		g._engine._experiment_pending_pair.append(String(exp_raw))
	g._engine._experiment_reserved_ether = exp_reserved_before
	g._engine.ether = exp_ether_before
	g._engine.ether_overflow = exp_overflow_before
	g._engine.attempts = exp_attempts_before
	g._engine.successes = exp_successes_before
	g._engine._experiment_day = exp_day_before
	g._engine._experiment_count = exp_count_before
	g._engine._experiment_last_at = exp_last_at_before
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
	# Доска v2 Task 4: _circle_on_discovery из мир-веток удалён — круг больше не
	# мутируется этими путями, снимки диска не нужны; возврат при prune (F1)
	# идёт через негейтимый _grant_ether (полный EXPERIMENT_COST в ether+
	# overflow) — его и восстанавливаем.
	var u11_ether := g._engine.ether
	var u11_ether_overflow := g._engine.ether_overflow
	# Замена снятого диска (доска v2 Task 4): очаг/вехи Contracts теперь мир-ветки
	# не трогают вообще — фиксируем это независимым снимком.
	var u11_cb4_pts := g._contracts._pts_total
	var u11_cb4_days := g._contracts._visit_days.size()
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
	# F1: TTL-prune живого эксперимента только снимает pending; поздний ответ
	# не применяется, а неизрасходованные реагенты и эфир остаются нетронутыми.
	g._engine._experiment_pending_pair = ["u14_exp_a", "u14_exp_b"]
	Selftest.check("u11 prune-exp register", g._online._register_pending_pair("u14_exp_a", "u14_exp_b", true))
	var u11_expkey := g._pair_key("u14_exp_a", "u14_exp_b")
	var u11_expiring: Dictionary = g._online._pending_requests[u11_expkey]
	u11_expiring["at"] = Time.get_ticks_msec() - g._online.PENDING_TTL_MSEC - 1000
	var u11_avail0 := g._engine.ether + g._engine.ether_overflow
	var u11_exp_a_before := int(g._engine.inventory.get("u14_exp_a", 0))
	var u11_exp_b_before := int(g._engine.inventory.get("u14_exp_b", 0))
	g._online._on_net_pair_result(u11_expkey, {"ok": true, "found": true, "status": "known",
		"out": {"slug": "u14_exp_late", "name": "U14-поздний", "color": "#112233", "glyph": "fire", "layer": 1}})
	Selftest.check("u11 prune-exp keeps reagents", g._engine._experiment_pending_pair.is_empty()
		and int(g._engine.inventory.get("u14_exp_a", 0)) == u11_exp_a_before
		and int(g._engine.inventory.get("u14_exp_b", 0)) == u11_exp_b_before)
	Selftest.check("u11 prune-exp keeps ether and drops late result", g._online._pending_requests.is_empty()
		and g._engine.ether + g._engine.ether_overflow == u11_avail0
		and not g.ITEMS.has("u14_exp_late") and not g._engine.inventory.has("u14_exp_late")
		and not g._engine.known_recipes.has(u11_expkey))
	# Недостаток эфира не должен частично зарегистрировать серверный элемент
	# или рецепт до отказа success commit.
	g._engine._experiment_pending_pair = ["fire", "water"]
	g._engine.ether = 0
	g._engine.ether_overflow = 0
	var u11_atomic_inv := g._engine.inventory.duplicate(true)
	var u11_atomic_known := g._engine.known_recipes.duplicate(true)
	var u11_atomic_recipes := g.RECIPES.duplicate(true)
	var u11_atomic_items := g.ITEMS.duplicate(true)
	g._online._experiment_outcome({"slug": "u11_no_ether", "name": "U11-без эфира",
		"color": "#112233", "glyph": "fire", "layer": 1}, "fire", "water")
	Selftest.check("experiment insufficient ether leaves graph unchanged",
		g._engine.ether + g._engine.ether_overflow == 0
		and not g.ITEMS.has("u11_no_ether") and not g._engine.inventory.has("u11_no_ether")
		and g._engine.inventory == u11_atomic_inv and g._engine.known_recipes == u11_atomic_known
		and g.RECIPES == u11_atomic_recipes and g.ITEMS == u11_atomic_items
		and g._engine._experiment_pending_pair.is_empty())
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
	# Возврат модалки. Мутация этих двух строк — «esc stack was clean on entry» в
	# suite_journal_misc: без них открытое «НОВЫЙ РЕЦЕПТ!» доживает до её canary.
	g._popup.visible = u11_popup
	g._popup_dim.visible = u11_popup_dim
	g._engine._experiment_pending_pair.clear()
	for u11_raw_e in u11_exp_pair:
		g._engine._experiment_pending_pair.append(String(u11_raw_e))
	# ассерт чувствителен к откату: посаженные slug'ы исчезли из ITEMS/inventory,
	# known_recipes по использованным парам вернулись к досюжетным значениям, а
	# ether/overflow/очаг восстановлены (сравнение объекта с самим собой ничего бы
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
		and g._contracts._pts_total == u11_cb4_pts
		and g._contracts._visit_days.size() == u11_cb4_days)

	# ============ personal target transport ============
	var pt_inv := g._engine.inventory.duplicate(true)
	var pt_known := g._engine.known_recipes.duplicate(true)
	var pt_rejected := g._engine._rejected_pairs.duplicate(true)
	var pt_recipes := g.RECIPES.duplicate(true)
	var pt_srv_recipes := g._online._server_recipes.duplicate(true)
	var pt_srv_authors := g._online._server_authors.duplicate(true)
	var pt_srv_els := g._online._server_elements.duplicate(true)
	var pt_srv_layers := g._online._server_layers.duplicate(true)
	var pt_items := g.ITEMS.duplicate(true)
	var pt_colors := g._item_colors.duplicate(true)
	var pt_layer_cache := g._engine._layer_cache.duplicate(true)
	var pt_pending := g._online._pending_requests.duplicate(true)
	var pt_exp_pair := g._engine._experiment_pending_pair.duplicate()
	var pt_reserved := g._engine._experiment_reserved_ether
	var pt_receipt: Dictionary = g._online._target_attempt_receipt.duplicate(true)
	var pt_sync_in_flight := g._online._target_sync_in_flight
	var pt_sync_nonce := g._online._target_sync_nonce
	var pt_view_state := g._online._target_view_state
	var pt_resume_wait := g._online._resume_experiment_wait
	var pt_ether := g._engine.ether
	var pt_overflow := g._engine.ether_overflow
	var pt_attempts := g._engine.attempts
	var pt_successes := g._engine.successes
	var pt_day := g._engine._experiment_day
	var pt_count := g._engine._experiment_count
	var pt_last_at := g._engine._experiment_last_at
	var pt_popup := g._popup.visible
	var pt_popup_dim := g._popup_dim.visible
	var pt_status := g._engine.status_text
	var pt_has_target_state := false
	for pt_property in g._online.get_script().get_script_property_list():
		if String(pt_property["name"]) == "_target_state":
			pt_has_target_state = true
	var pt_target_old: Dictionary = {}
	if pt_has_target_state:
		pt_target_old = g._online.get("_target_state").duplicate(true)
	var pt_target := {
		"id": "pt-target", "kind": "llm", "slug": "pt-hidden", "name": "Скрытая цель",
		"hint": "Соедини привычное с неожиданным.", "status": "active", "cycle_week": "2026-W48",
		"attempts": 0, "successful_steps": 0, "spent_ether": 0, "generation": 7,
		"next_eligible_week": ""}
	if pt_has_target_state:
		g._online.set("_target_state", pt_target.duplicate(true))

	var pt_capture := CaptureNet.new()
	pt_capture.base_url = "https://unit.test/api"
	if pt_capture.has_method("experiment_target_sync"):
		pt_capture.call("experiment_target_sync", "pt-device", "Pt", "pt-sync-nonce")
	var pt_sync_body: Dictionary = {}
	if pt_capture.last_body != "":
		pt_sync_body = JSON.parse_string(pt_capture.last_body) as Dictionary
	var pt_sync_body_ok := pt_sync_body.size() == 3 \
		and String(pt_sync_body.get("device_id", "")) == "pt-device" \
		and String(pt_sync_body.get("nick", "")) == "Pt" \
		and String(pt_sync_body.get("sync_nonce", "")) == "pt-sync-nonce"
	Selftest.check("net target sync route and body", pt_capture.has_method("experiment_target_sync")
		and String(pt_capture.last_url).ends_with("/api/experiment/target")
		and pt_capture.last_method == HTTPClient.METHOD_POST and pt_sync_body_ok)
	if pt_capture.has_method("experiment_target_attempt"):
		pt_capture.call("experiment_target_attempt", "fire", "water", "Pt", "pt-device", "pt-target", "pt-request")
	var pt_attempt_body: Dictionary = {}
	if pt_capture.last_body != "":
		pt_attempt_body = JSON.parse_string(pt_capture.last_body) as Dictionary
	var pt_attempt_keys := ["a", "b", "nick", "device_id", "target_id", "request_id"]
	var pt_attempt_body_ok := pt_attempt_body.size() == pt_attempt_keys.size()
	for pt_key in pt_attempt_keys:
		pt_attempt_body_ok = pt_attempt_body_ok and pt_attempt_body.has(String(pt_key))
	Selftest.check("net target attempt route hides target internals", pt_capture.has_method("experiment_target_attempt")
		and String(pt_capture.last_url).ends_with("/api/experiment/attempt")
		and pt_capture.last_method == HTTPClient.METHOD_POST and pt_attempt_body_ok
		and String(pt_attempt_body.get("a", "")) == "fire" and String(pt_attempt_body.get("b", "")) == "water"
		and String(pt_attempt_body.get("target_id", "")) == "pt-target"
		and String(pt_attempt_body.get("request_id", "")) == "pt-request")
	pt_capture.free()

	var pt_dispatch := NetBase.new()
	var pt_sync_sink := OfflineSink.new()
	var pt_attempt_sink := TargetAttemptSink.new()
	if pt_dispatch.has_signal("experiment_target_sync_result"):
		pt_dispatch.experiment_target_sync_result.connect(pt_sync_sink.catch)
	if pt_dispatch.has_signal("experiment_target_result"):
		pt_dispatch.experiment_target_result.connect(pt_attempt_sink.catch)
	var pt_pair := g._pair_key("fire", "water")
	pt_dispatch._dispatch({"kind": "experiment-target-sync",
		"body": {"sync_nonce": "pt-dispatch-nonce"}}, {"ok": true, "target": pt_target})
	pt_dispatch._dispatch({"kind": "experiment-target-attempt", "pair_key": pt_pair,
		"body": {"request_id": "pt-request"}}, {"ok": true, "status": "known"})
	Selftest.check("net target dispatch preserves request correlation",
		pt_dispatch.has_signal("experiment_target_sync_result") and pt_dispatch.has_signal("experiment_target_result")
		and pt_sync_sink.results.size() == 1 and pt_sync_sink.nonces == ["pt-dispatch-nonce"]
		and pt_attempt_sink.request_ids == ["pt-request"]
		and pt_attempt_sink.pair_keys == [pt_pair] and pt_attempt_sink.results.size() == 1)
	pt_dispatch.free()

	g._engine.inventory["steam"] = 0
	g._engine._experiment_pending_pair = ["fire", "water"]
	g._engine._experiment_reserved_ether = int(g._engine._bal().get_value("discovery.cost", Game.EXPERIMENT_COST))
	g._online._pending_requests[pt_pair] = {
		"a": "fire", "b": "water", "experiment": true, "target_mode": true,
		"target_id": "pt-target", "request_id": "pt-request", "generation": 7,
		"cycle_week": "2026-W48",
		"reserved_cost": g._engine._experiment_reserved_ether,
		"at": Time.get_ticks_msec()}
	var pt_mode_available := g._engine._available_ether()
	var pt_mode_inv := g._engine.inventory.duplicate(true)
	var pt_mode_known := g._engine.known_recipes.duplicate(true)
	g._online._on_net_pair_result(pt_pair, {"ok": true, "found": true, "status": "known",
		"out": {"slug": "steam", "name": "Steam", "color": "#88aabb", "glyph": "fire", "layer": 1}})
	Selftest.check("ordinary pair response cannot consume target pending",
		g._online._pending_requests.has(pt_pair) and g._engine._experiment_pending_pair == ["fire", "water"]
		and g._engine.inventory == pt_mode_inv and g._engine.known_recipes == pt_mode_known
		and g._engine._available_ether() == pt_mode_available)
	g._online._pending_requests.clear()
	g._engine._experiment_pending_pair.clear()
	g._engine._experiment_reserved_ether = 0
	g._engine.inventory = pt_inv
	g._engine.known_recipes = pt_known

	var pt_register_args := 0
	for pt_method in g._online.get_method_list():
		if String(pt_method["name"]) == "_register_pending_pair":
			pt_register_args = (pt_method["args"] as Array).size()
	var pt_registered := false
	if pt_register_args >= 9:
		pt_registered = g._online.callv("_register_pending_pair",
			["fire", "water", true, true, "pt-target", "pt-request", 7, "2026-W48",
				int(g._engine._bal().get_value("discovery.cost", Game.EXPERIMENT_COST))])
	var pt_registered_entry: Dictionary = g._online._pending_requests.get(pt_pair, {})
	Selftest.check("target pending stores correlation fields", pt_registered
		and bool(pt_registered_entry.get("target_mode", false))
		and String(pt_registered_entry.get("target_id", "")) == "pt-target"
		and String(pt_registered_entry.get("request_id", "")) == "pt-request"
		and int(pt_registered_entry.get("generation", -1)) == 7
		and String(pt_registered_entry.get("cycle_week", "")) == "2026-W48"
		and int(pt_registered_entry.get("reserved_cost", -1)) >= 0)
	g._online._pending_requests.clear()

	var pt_restore_graph := func() -> void:
		g._engine.inventory = pt_inv.duplicate(true)
		g._engine.known_recipes = pt_known.duplicate(true)
		g._engine._rejected_pairs = pt_rejected.duplicate(true)
		g.RECIPES = pt_recipes.duplicate(true)
		g._online._server_recipes = pt_srv_recipes.duplicate(true)
		g._online._server_authors = pt_srv_authors.duplicate(true)
		g._online._server_elements = pt_srv_els.duplicate(true)
		g._online._server_layers = pt_srv_layers.duplicate(true)
		g.ITEMS = pt_items.duplicate(true)
		g._item_colors = pt_colors.duplicate(true)
		g._engine._layer_cache = pt_layer_cache.duplicate(true)
		g._popup.visible = pt_popup
		g._popup_dim.visible = pt_popup_dim
		g._online._pending_requests.clear()
		g._engine._experiment_pending_pair.clear()
		g._engine._experiment_reserved_ether = 0
		g._engine.ether = pt_ether
		g._engine.ether_overflow = pt_overflow
	var pt_reset_target := func() -> void:
		if pt_has_target_state:
			g._online.set("_target_state", pt_target.duplicate(true))
	var pt_seed_target := func() -> void:
		g._engine._experiment_pending_pair = ["fire", "water"]
		g._engine._experiment_reserved_ether = int(g._engine._bal().get_value("discovery.cost", Game.EXPERIMENT_COST))
		g._online._pending_requests[pt_pair] = {
			"a": "fire", "b": "water", "experiment": true, "target_mode": true,
			"target_id": "pt-target", "request_id": "pt-request", "generation": 7,
			"cycle_week": "2026-W48",
			"reserved_cost": g._engine._experiment_reserved_ether,
			"at": Time.get_ticks_msec()}
	var pt_make_response := func(status: String, charge: int, snapshot_status: String) -> Dictionary:
		var snapshot: Dictionary = pt_target.duplicate(true)
		snapshot["status"] = snapshot_status
		if snapshot_status == "completed":
			snapshot["next_eligible_week"] = "2026-W49"
		var response := {
			"ok": status not in ["target_conflict", "target_stale", "target_not_found", "request_mismatch", "ingredient_not_granted"],
			"status": status, "target_id": "pt-target", "request_id": "pt-request", "pair_key": pt_pair,
			"target": snapshot, "ether_charged": charge, "acquired": charge > 0, "message": status}
		if status in ["created", "known", "reused"]:
			response["discovery"] = {"slug": "steam", "name": "Steam", "color": "#88aabb",
				"glyph": "fire", "layer": 1, "a": "fire", "b": "water", "author": "Pt", "reused": false}
		return response
	var pt_sync_handler_ready := pt_has_target_state \
		and g._online.has_method("_on_experiment_target_sync_result")
	if pt_sync_handler_ready:
		var pt_sync_raw: Dictionary = pt_target.duplicate(true)
		pt_sync_raw["target_name_norm"] = "скрытая цель"
		pt_sync_raw["source_pair"] = ["fire", "water"]
		pt_sync_raw["seed"] = 123
		pt_sync_raw["evaluator_reason"] = "hidden"
		g._online.call("_on_experiment_target_sync_result", {"ok": true, "target": pt_sync_raw})
		var pt_sync_state: Dictionary = g._online.get("_target_state")
		Selftest.check("target sync filters hidden fields and preserves generation",
			String(pt_sync_state.get("id", "")) == "pt-target"
			and int(pt_sync_state.get("generation", -1)) == 7
			and not pt_sync_state.has("target_name_norm") and not pt_sync_state.has("source_pair")
			and not pt_sync_state.has("seed") and not pt_sync_state.has("evaluator_reason"))
		var pt_next_raw: Dictionary = pt_sync_raw.duplicate(true)
		pt_next_raw["id"] = "pt-next"
		g._online.call("_on_experiment_target_sync_result", {"ok": true, "target": pt_next_raw})
		Selftest.check("target sync increments generation for a new target",
			String(g._online.get("_target_state").get("id", "")) == "pt-next"
			and int(g._online.get("_target_state").get("generation", -1)) == 8)
		pt_reset_target.call()
	else:
		Selftest.check("target sync handler exists", false)

	var pt_sync_lifecycle_ready := g._online.has_method("_sync_personal_target")
	if pt_sync_lifecycle_ready:
		var pt_life_net_base := Net.base_url
		var pt_life_net_available := Net._available
		var pt_life_net_enabled := g._online._net_enabled
		var pt_life_transport := g._online._discovery_transport
		var pt_life_has_inflight := false
		var pt_life_has_view := false
		var pt_life_has_nonce := false
		var pt_life_inflight_old: Variant = false
		var pt_life_view_old: Variant = ""
		var pt_life_nonce_old: Variant = ""
		for pt_life_property in g._online.get_property_list():
			var pt_life_name := String(pt_life_property["name"])
			if pt_life_name == "_target_sync_in_flight":
				pt_life_has_inflight = true
				pt_life_inflight_old = g._online.get(pt_life_name)
			elif pt_life_name == "_target_view_state":
				pt_life_has_view = true
				pt_life_view_old = g._online.get(pt_life_name)
			elif pt_life_name == "_target_sync_nonce":
				pt_life_has_nonce = true
				pt_life_nonce_old = g._online.get(pt_life_name)
		var pt_life_online_connected := Net.experiment_target_sync_result.is_connected(g._online._on_experiment_target_sync_result)
		if pt_life_online_connected:
			Net.experiment_target_sync_result.disconnect(g._online._on_experiment_target_sync_result)
		var pt_life_sync_sink := OfflineSink.new()
		var pt_life_attempt_sink := TargetAttemptSink.new()
		Net.experiment_target_sync_result.connect(pt_life_sync_sink.catch)
		Net.experiment_target_result.connect(pt_life_attempt_sink.catch)

		pt_reset_target.call()
		g._online._net_enabled = false
		var pt_life_offline_before: Dictionary = g._online.get("_target_state").duplicate(true)
		g._online.call("_sync_personal_target")
		Selftest.check("target offline sync preserves cached snapshot",
			g._online.get("_target_state") == pt_life_offline_before and pt_life_sync_sink.results.is_empty())

		g._online._net_enabled = true
		g._online.clear_discovery_transport()
		Net.base_url = "https://unit.test/api"
		Net._available = true
		g._online.call("_sync_personal_target")
		g._online.call("_sync_personal_target")
		var pt_life_inflight: Variant = g._online.get("_target_sync_in_flight") if pt_life_has_inflight else false
		var pt_life_sync_nonce := String(pt_life_sync_sink.nonces[0]) \
			if pt_life_sync_sink.nonces.size() == 1 else ""
		Selftest.check("target duplicate opens suppress in-flight sync",
			pt_life_sync_sink.results.size() == 1 and bool(pt_life_inflight)
			and pt_life_sync_nonce != "")

		g._online.call("_on_experiment_target_sync_result",
			{"ok": true, "target": pt_target}, pt_life_sync_nonce)
		pt_life_inflight = g._online.get("_target_sync_in_flight") if pt_life_has_inflight else true
		Selftest.check("target sync success clears in-flight guard", not bool(pt_life_inflight))

		if not pt_life_online_connected:
			Net.experiment_target_sync_result.connect(g._online._on_experiment_target_sync_result)
		pt_life_sync_sink.results.clear()
		var pt_life_cached_before_offline: Dictionary = g._online.get("_target_state").duplicate(true)
		g._online.call("_sync_personal_target")
		pt_life_inflight = g._online.get("_target_sync_in_flight") if pt_life_has_inflight else true
		Selftest.check("target offline result clears in-flight guard",
			pt_life_sync_sink.results.size() == 1 and not bool(pt_life_inflight)
			and g._online.get("_target_state") == pt_life_cached_before_offline)

		var pt_life_completed: Dictionary = pt_target.duplicate(true)
		pt_life_completed["status"] = "completed"
		pt_life_completed["next_eligible_week"] = "2099-W01"
		g._online.call("_on_experiment_target_sync_result", {"ok": true, "target": pt_life_completed})
		pt_life_sync_sink.results.clear()
		pt_life_attempt_sink.request_ids.clear()
		pt_life_attempt_sink.pair_keys.clear()
		g._online.call("_sync_personal_target")
		Selftest.check("target waiting slot asks server without creating another target",
			pt_life_sync_sink.results.size() == 1 and pt_life_attempt_sink.request_ids.is_empty()
			and String(g._online.get("_target_state").get("status", "")) == "completed")

		Net.experiment_target_sync_result.disconnect(pt_life_sync_sink.catch)
		Net.experiment_target_result.disconnect(pt_life_attempt_sink.catch)
		if not pt_life_online_connected:
			Net.experiment_target_sync_result.disconnect(g._online._on_experiment_target_sync_result)
		Net.base_url = pt_life_net_base
		Net._available = pt_life_net_available
		g._online._net_enabled = pt_life_net_enabled
		g._online._discovery_transport = pt_life_transport
		if pt_life_has_inflight:
			g._online.set("_target_sync_in_flight", pt_life_inflight_old)
		if pt_life_has_view:
			g._online.set("_target_view_state", pt_life_view_old)
		if pt_life_has_nonce:
			g._online.set("_target_sync_nonce", pt_life_nonce_old)
		pt_reset_target.call()
	else:
		Selftest.check("target sync lifecycle method exists", false)

	var pt_target_result_ready := pt_has_target_state \
		and g._online.has_method("_on_experiment_target_result")

	if pt_target_result_ready:
		pt_reset_target.call()
		pt_restore_graph.call()
		var pt_reserve_state: Dictionary = g._online.get("_target_state").duplicate(true)
		pt_reserve_state["kind"] = "world"
		pt_reserve_state["slug"] = "steam"
		g._online.set("_target_state", pt_reserve_state)
		g._engine._experiment_pending_pair.clear()
		g._engine._experiment_day = ""
		g._engine._experiment_count = 0
		g._engine._experiment_last_at = 0.0
		g._engine.ether = Game.EXPERIMENT_COST + 10
		g._engine.ether_overflow = 0
		var pt_reserve_started := g._engine._begin_experiment("fire", "water", true)
		var pt_reserve_registered := g._online._register_pending_pair("fire", "water", true,
			true, "pt-target", "pt-request", 7, "2026-W48",
			g._engine._experiment_reserved_ether)
		var pt_reserve_visible := g._engine.ether
		var pt_reserve_available := g._engine._available_ether()
		var pt_reserve_response: Dictionary = pt_make_response.call("known", 7, "completed")
		pt_reserve_response["target"]["kind"] = "world"
		pt_reserve_response["target"]["slug"] = "steam"
		g._online.call("_on_experiment_target_result", "pt-request", pt_pair, pt_reserve_response)
		Selftest.check("target success settles configured reserve at server charge",
			pt_reserve_started and pt_reserve_registered
			and pt_reserve_available == pt_reserve_visible - Game.EXPERIMENT_COST
			and pt_reserve_visible - g._engine.ether == 7
			and g._engine._available_ether() == g._engine.ether)
		pt_restore_graph.call()

		pt_reset_target.call()
		pt_seed_target.call()
		g._engine.inventory["steam"] = 1
		g._engine.ether = maxi(g._engine.ether, Game.EXPERIMENT_COST + 10)
		var pt_success_visible := g._engine.ether
		var pt_success_inventory := int(g._engine.inventory.get("steam", 0))
		var pt_success_state: Dictionary = g._online.get("_target_state").duplicate(true)
		pt_success_state["kind"] = "world"
		pt_success_state["slug"] = "steam"
		g._online.set("_target_state", pt_success_state)
		var pt_success_response: Dictionary = pt_make_response.call("known", 7, "completed")
		pt_success_response["target"]["kind"] = "world"
		pt_success_response["target"]["slug"] = "steam"
		g._online.call("_on_experiment_target_result", "pt-request", pt_pair, pt_success_response)
		var pt_success_available_after := g._engine._available_ether()
		Selftest.check("target response forwards server ether charge",
			pt_success_visible - g._engine.ether == 7
			and pt_success_available_after == g._engine.ether
			and int(g._engine.inventory.get("steam", 0)) == pt_success_inventory + 1
			and String(g._online.get("_target_state").get("status", "")) == "completed")
		g._online.call("_on_experiment_target_result", "pt-request", pt_pair, pt_success_response)
		Selftest.check("target duplicate response does not charge twice",
			g._engine._available_ether() == pt_success_available_after
			and int(g._engine.inventory.get("steam", 0)) == pt_success_inventory + 1)
		pt_restore_graph.call()

		pt_reset_target.call()
		pt_seed_target.call()
		var pt_zero_target: Dictionary = g._online.get("_target_state")
		pt_zero_target["slug"] = ""
		g._online.set("_target_state", pt_zero_target)
		g._engine.inventory["steam"] = 0
		g._engine.ether = maxi(g._engine.ether, Game.EXPERIMENT_COST + 1)
		var pt_zero_visible := g._engine.ether
		var pt_zero_response: Dictionary = pt_make_response.call("known", 0, "completed")
		pt_zero_response["target"]["slug"] = "pt-realized"
		pt_zero_response["target"]["successful_steps"] = 1
		g._online.call("_on_experiment_target_result", "pt-request", pt_pair, pt_zero_response)
		Selftest.check("target zero-acquisition completed snapshot cannot complete llm",
			g._online._pending_requests.is_empty() and g._engine._experiment_pending_pair.is_empty()
			and g._engine.ether == pt_zero_visible
			and g._engine._available_ether() == pt_zero_visible
			and int(g._engine.inventory.get("steam", 0)) == 0 and g.ITEMS == pt_items
			and String(g._online.get("_target_state").get("status", "")) == "active"
			and not bool(g._online.get("_target_state").get("completed", false))
			and String(g._online.get("_target_state").get("slug", "")) == ""
			and String(g._online.get("_target_state").get("next_eligible_week", "")) == "")
		pt_restore_graph.call()

		pt_reset_target.call()
		pt_seed_target.call()
		g._engine.inventory["steam"] = 0
		var pt_free_visible := g._engine.ether
		var pt_free_available := g._engine._available_ether()
		var pt_free_response: Dictionary = pt_make_response.call("created", 0, "active")
		pt_free_response["acquired"] = true
		g._online.call("_on_experiment_target_result", "pt-request", pt_pair, pt_free_response)
		Selftest.check("target acquired zero server charge grants once without debit",
			g._online._pending_requests.is_empty()
			and g._engine.ether == pt_free_visible
			and g._engine._available_ether() == pt_free_available + int(g._engine._bal().get_value("discovery.cost", Game.EXPERIMENT_COST))
			and int(g._engine.inventory.get("steam", 0)) == 1)
		pt_restore_graph.call()

		pt_reset_target.call()
		pt_seed_target.call()
		g._engine.inventory["steam"] = 0
		g._engine.ether = maxi(g._engine.ether, Game.EXPERIMENT_COST + 10)
		var pt_llm_known_visible := g._engine.ether
		var pt_llm_known_response: Dictionary = pt_make_response.call("known", 12, "completed")
		g._online.call("_on_experiment_target_result", "pt-request", pt_pair, pt_llm_known_response)
		Selftest.check("target llm known cannot complete",
			int(g._engine.inventory.get("steam", 0)) == 1
			and pt_llm_known_visible - g._engine.ether == 12
			and g._engine._available_ether() == g._engine.ether
			and String(g._online.get("_target_state").get("status", "")) == "active")
		pt_restore_graph.call()

		pt_reset_target.call()
		pt_seed_target.call()
		g._engine.inventory["steam"] = 0
		var pt_llm_created_visible := g._engine.ether
		var pt_llm_created_response: Dictionary = pt_make_response.call("created", 7, "completed")
		pt_llm_created_response["target"]["slug"] = "pt-realized"
		pt_llm_created_response["discovery"]["name"] = "  СКРЫТАЯ   ЦЕЛЬ  "
		var pt_llm_created_target: Dictionary = g._online.get("_target_state")
		pt_llm_created_target["slug"] = ""
		g._online.set("_target_state", pt_llm_created_target)
		g._online.call("_on_experiment_target_result", "pt-request", pt_pair, pt_llm_created_response)
		Selftest.check("target llm created completes with exact normalized name and realized slug",
			int(g._engine.inventory.get("steam", 0)) == 1
			and pt_llm_created_visible - g._engine.ether == 7
			and g._engine._available_ether() == g._engine.ether
			and String(g._online.get("_target_state").get("status", "")) == "completed"
			and String(g._online.get("_target_state").get("slug", "")) == "pt-realized")
		pt_restore_graph.call()

		pt_reset_target.call()
		pt_seed_target.call()
		g._engine.inventory["steam"] = 0
		var pt_llm_reused_visible := g._engine.ether
		var pt_llm_reused_response: Dictionary = pt_make_response.call("created", 7, "completed")
		pt_llm_reused_response["discovery"]["name"] = "Скрытая цель"
		pt_llm_reused_response["discovery"]["reused"] = true
		g._online.call("_on_experiment_target_result", "pt-request", pt_pair, pt_llm_reused_response)
		Selftest.check("target llm reused created result cannot complete",
			int(g._engine.inventory.get("steam", 0)) == 1
			and pt_llm_reused_visible - g._engine.ether == 7
			and String(g._online.get("_target_state").get("status", "")) == "active"
			and not bool(g._online.get("_target_state").get("completed", false)))
		pt_restore_graph.call()

		pt_reset_target.call()
		pt_seed_target.call()
		g._engine.inventory["steam"] = 0
		var pt_missing_charge_visible := g._engine.ether
		var pt_missing_charge_available := g._engine._available_ether()
		var pt_missing_charge_inventory := g._engine.inventory.duplicate(true)
		var pt_missing_charge_response: Dictionary = pt_make_response.call("created", 12, "completed")
		pt_missing_charge_response.erase("ether_charged")
		g._online.call("_on_experiment_target_result", "pt-request", pt_pair, pt_missing_charge_response)
		Selftest.check("target success without server charge is rejected",
			g._online._pending_requests.is_empty() and g._engine._experiment_pending_pair.is_empty()
			and g._engine.inventory == pt_missing_charge_inventory
			and g._engine.ether == pt_missing_charge_visible
			and g._engine._available_ether() == pt_missing_charge_available + int(g._engine._bal().get_value("discovery.cost", Game.EXPERIMENT_COST)))
		pt_restore_graph.call()

		pt_reset_target.call()
		pt_seed_target.call()
		var pt_mismatch_available := g._engine._available_ether()
		var pt_mismatch_inventory := g._engine.inventory.duplicate(true)
		var pt_wrong_response: Dictionary = pt_make_response.call("known", 12, "completed")
		g._online.call("_on_experiment_target_result", "wrong-request", pt_pair, pt_wrong_response)
		var pt_wrong_request_kept := g._online._pending_requests.has(pt_pair) \
			and g._engine.inventory == pt_mismatch_inventory \
			and g._engine._available_ether() == pt_mismatch_available
		pt_wrong_response["target_id"] = "other-target"
		g._online.call("_on_experiment_target_result", "pt-request", pt_pair, pt_wrong_response)
		Selftest.check("target mismatch response keeps pending slot", pt_wrong_request_kept
			and g._online._pending_requests.has(pt_pair) and g._engine.inventory == pt_mismatch_inventory
			and g._engine._available_ether() == pt_mismatch_available)
		pt_restore_graph.call()

		pt_reset_target.call()
		pt_seed_target.call()
		if pt_has_target_state:
			var pt_stale_state: Dictionary = g._online.get("_target_state").duplicate(true)
			pt_stale_state["generation"] = 8
			g._online.set("_target_state", pt_stale_state)
		var pt_stale_visible := g._engine.ether
		var pt_stale_available := g._engine._available_ether()
		var pt_stale_inventory := g._engine.inventory.duplicate(true)
		g._online.call("_on_experiment_target_result", "pt-request", pt_pair,
			pt_make_response.call("known", 12, "completed"))
		Selftest.check("target stale generation releases reserve without graph or visible ether mutation",
			g._online._pending_requests.is_empty()
			and g._engine.inventory == pt_stale_inventory and g.ITEMS == pt_items
			and g._engine.ether == pt_stale_visible
			and g._engine._available_ether() == pt_stale_available + int(g._engine._bal().get_value("discovery.cost", Game.EXPERIMENT_COST)))
		pt_restore_graph.call()

		pt_reset_target.call()
		pt_seed_target.call()
		var pt_false_complete_target: Dictionary = g._online.get("_target_state")
		pt_false_complete_target["slug"] = ""
		g._online.set("_target_state", pt_false_complete_target)
		var pt_false_complete_visible := g._engine.ether
		var pt_false_complete_inventory := g._engine.inventory.duplicate(true)
		var pt_false_complete_response: Dictionary = pt_make_response.call("not_combinable", 12, "completed")
		pt_false_complete_response["target"]["slug"] = "pt-realized"
		g._online.call("_on_experiment_target_result", "pt-request", pt_pair, pt_false_complete_response)
		Selftest.check("target failure completed snapshot cannot complete llm",
			g._online._pending_requests.is_empty() and g._engine._experiment_pending_pair.is_empty()
			and g._engine.inventory == pt_false_complete_inventory and g.ITEMS == pt_items
			and g._engine.ether == pt_false_complete_visible
			and g._engine._available_ether() == pt_false_complete_visible
			and String(g._online.get("_target_state").get("status", "")) == "active"
			and not bool(g._online.get("_target_state").get("completed", false))
			and String(g._online.get("_target_state").get("slug", "")) == ""
			and String(g._online.get("_target_state").get("next_eligible_week", "")) == "")
		pt_restore_graph.call()

		pt_reset_target.call()
		pt_seed_target.call()
		var pt_malformed_ok_target: Dictionary = g._online.get("_target_state")
		pt_malformed_ok_target["slug"] = ""
		g._online.set("_target_state", pt_malformed_ok_target)
		var pt_malformed_ok_visible := g._engine.ether
		var pt_malformed_ok_inventory := g._engine.inventory.duplicate(true)
		var pt_malformed_ok_response: Dictionary = pt_make_response.call("created", 12, "completed")
		pt_malformed_ok_response["ok"] = 1
		pt_malformed_ok_response["target"]["slug"] = "pt-realized"
		g._online.call("_on_experiment_target_result", "pt-request", pt_pair, pt_malformed_ok_response)
		Selftest.check("target malformed ok completed snapshot cannot complete llm",
			g._online._pending_requests.is_empty() and g._engine._experiment_pending_pair.is_empty()
			and g._engine.inventory == pt_malformed_ok_inventory and g.ITEMS == pt_items
			and g._engine.ether == pt_malformed_ok_visible
			and g._engine._available_ether() == pt_malformed_ok_visible
			and String(g._online.get("_target_state").get("status", "")) == "active"
			and not bool(g._online.get("_target_state").get("completed", false))
			and String(g._online.get("_target_state").get("slug", "")) == ""
			and String(g._online.get("_target_state").get("next_eligible_week", "")) == "")
		pt_restore_graph.call()

		for pt_failure_status in ["not_combinable", "unavailable", "target_conflict", "target_stale", "target_already_owned"]:
			pt_reset_target.call()
			pt_seed_target.call()
			var pt_failure_visible := g._engine.ether
			var pt_failure_available := g._engine._available_ether()
			var pt_failure_inventory := g._engine.inventory.duplicate(true)
			var pt_failure_response: Dictionary = pt_make_response.call(String(pt_failure_status), 12,
				"waiting_next_slot" if String(pt_failure_status) == "target_already_owned" else "active")
			if String(pt_failure_status) == "target_conflict":
				pt_failure_response["discovery"] = {"slug": "pt_forbidden", "name": "Forbidden",
					"color": "#112233", "glyph": "fire", "layer": 1, "a": "fire", "b": "water", "author": "Pt"}
			g._online.call("_on_experiment_target_result", "pt-request", pt_pair, pt_failure_response)
			Selftest.check("target failure %s keeps graph and ether" % pt_failure_status,
				g._online._pending_requests.is_empty() and g._engine._experiment_pending_pair.is_empty()
				and g._engine.inventory == pt_failure_inventory and not g.ITEMS.has("pt_forbidden")
				and g._engine.ether == pt_failure_visible
				and g._engine._available_ether() == pt_failure_available + int(g._engine._bal().get_value("discovery.cost", Game.EXPERIMENT_COST)))
			pt_restore_graph.call()
	else:
		Selftest.check("target response handler exists", false)

	var pt_net_base := Net.base_url
	var pt_net_available := Net._available
	var pt_net_enabled := g._online._net_enabled
	var pt_device := g._online._device_id
	var pt_nick := g._online._net_nick
	var pt_transport := g._online._discovery_transport
	var pt_connect_online := Net.has_signal("experiment_target_result") \
		and not Net.experiment_target_result.is_connected(g._online._on_experiment_target_result)
	if pt_connect_online:
		Net.experiment_target_result.connect(g._online._on_experiment_target_result)
	var pt_route_sink := TargetAttemptSink.new()
	if Net.has_signal("experiment_target_result"):
		Net.experiment_target_result.connect(pt_route_sink.catch)
	if pt_has_target_state:
		pt_reset_target.call()
		g._online.clear_discovery_transport()
		g._online._net_enabled = true
		g._online._device_id = "pt-device"
		g._online._net_nick = "Pt"
		Net.base_url = ""
		Net._available = true
		g._engine.inventory["steam"] = 1
		g._engine.known_recipes[pt_pair] = true
		g._engine._rejected_pairs.erase(pt_pair)
		g._engine._experiment_day = ""
		g._engine._experiment_count = 0
		g._engine._experiment_last_at = 0.0
		g._engine.ether = maxi(g._engine.ether, Game.EXPERIMENT_COST + 1)
		var pt_route_available := g._engine._available_ether()
		var pt_route_inventory := g._engine.inventory.duplicate(true)
		var pt_route_started := g._online._start_experiment("fire", "water")
		var pt_route_reserved_available := pt_route_available - int(g._engine._bal().get_value("discovery.cost", Game.EXPERIMENT_COST))
		Selftest.check("active target routes locally known pair through target attempt",
			pt_route_started and not g._online._find_recipe("fire", "water").is_empty()
			and pt_route_sink.request_ids.size() == 1 and String(pt_route_sink.request_ids[0]) != ""
			and pt_route_sink.pair_keys == [pt_pair] and g._engine.inventory == pt_route_inventory
			and g._engine._available_ether() == pt_route_reserved_available)
		Selftest.check("target offline response preserves replay pending without charge",
			g._online._pending_requests.has(pt_pair)
			and g._engine._experiment_pending_pair == ["fire", "water"]
			and not g._online._target_attempt_receipt.is_empty()
			and g._engine.inventory == pt_route_inventory
			and g._engine._available_ether() == pt_route_reserved_available)
	else:
		Selftest.check("active target state exists", false)
	if Net.has_signal("experiment_target_result"):
		Net.experiment_target_result.disconnect(pt_route_sink.catch)
	if pt_connect_online:
		Net.experiment_target_result.disconnect(g._online._on_experiment_target_result)
	Net.base_url = pt_net_base
	Net._available = pt_net_available
	g._online._net_enabled = pt_net_enabled
	g._online._device_id = pt_device
	g._online._net_nick = pt_nick
	g._online._discovery_transport = pt_transport
	pt_restore_graph.call()
	g._engine.ether = pt_ether
	g._engine.ether_overflow = pt_overflow
	g._engine.attempts = pt_attempts
	g._engine.successes = pt_successes
	g._engine._experiment_day = pt_day
	g._engine._experiment_count = pt_count
	g._engine._experiment_last_at = pt_last_at
	g._engine.status_text = pt_status
	g._online._pending_requests = pt_pending.duplicate(true)
	g._engine._experiment_pending_pair.clear()
	for pt_raw in pt_exp_pair:
		g._engine._experiment_pending_pair.append(String(pt_raw))
	g._engine._experiment_reserved_ether = pt_reserved
	g._online._target_attempt_receipt = pt_receipt.duplicate(true)
	g._online._target_sync_in_flight = pt_sync_in_flight
	g._online._target_sync_nonce = pt_sync_nonce
	g._online._target_view_state = pt_view_state
	g._online._resume_experiment_wait = pt_resume_wait
	if pt_has_target_state:
		g._online.set("_target_state", pt_target_old)
	Selftest.check("personal target transport state restored",
		g._engine.inventory == pt_inv and g.ITEMS == pt_items and not g.ITEMS.has("pt_forbidden")
		and g._engine.ether == pt_ether and g._engine.ether_overflow == pt_overflow
		and g._online._pending_requests == pt_pending
		and g._online._target_attempt_receipt == pt_receipt)

	# ============ /personal target transport ============

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
