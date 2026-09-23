extends RefCounted
class_name SuiteResonanceNet
# резонанс/маршрутизация сети (оп B1).

const NetBase := preload("res://autoload/net.gd")

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
	# T13: если _try_send вернул err != OK, очередь НЕ дедлокавится — каждый
	# заqueued-запрос получает offline-результат, _inflight пуст, очередь жива
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
	var known_b2 := g._engine.known_recipes.size()
	Selftest.check("lens reveal", g._pages._lens_reveal() and g._engine.known_recipes.size() == known_b2 + 1
		and g._engine.ether == 300 - Game.LENS_COST)
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
	g._online._pending_requests.clear()
	# (1) «enqueue-перехват»: пока X ждёт ответа, Y слот не перезахватывает;
	# поздний ответ X применяет награду строго своей паре.
	var u11_kx := g._pair_key("fire", "air")
	var u11_ky := g._pair_key("earth", "air")
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
	g._engine._experiment_pending_pair.clear()
	for u11_raw_e in u11_exp_pair:
		g._engine._experiment_pending_pair.append(String(u11_raw_e))
	Selftest.check("u11 state restored", g._engine.inventory == u11_inv and g.ITEMS == u11_items
		and g._online._pending_requests.is_empty())
