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
