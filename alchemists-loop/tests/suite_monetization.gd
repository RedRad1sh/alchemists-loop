extends RefCounted
class_name SuiteMonetization

const GooglePlayBillingAdapterScript := preload("res://platform/google_play_billing.gd")
const RuStorePayAdapterScript := preload("res://platform/rustore_pay.gd")

# U20 (T25) — покрытие денежных путей, до этого не покрытых вообще ничем: матрица
# purchaseState обоих биллинг-адаптеров (дефект T21), контракт «адаптер -> фасад»
# по состояниям, кап и cooldown rewarded, начисление из каталога (_grant_product)
# и гейты purchase(). Журнал покупок, порядок grant->consume->mark,
# идемпотентность, вайп, экспорт и consent-гейты уже покрыты
# tests/suite_journal_misc.gd (кейсы t22*/i1*/m1*/m2* и T23-блок :696-1197) и здесь
# НЕ дублируются.
#
# Адаптеры создаются .new() напрямую (extends RefCounted, плагин не нужен), их
# _normalize_state — единственное место, где «нет поля» могло превратиться в
# «куплено». Сюита герметична: пишет только в ST-файлы (пути переводят сами
# autoload'ы в _ready, U23; страховка — в Selftest.run), а состояние autoload'ов
# снимает на входе и возвращает на выходе.
# Внутри сюиты нет ни одного await, поэтому очередь Net за неё не «дренируется» и
# её размер — корректное доказательство «ни одного запроса не ушло».


static func run(g: Game) -> void:
	# ---------- 0. снимки всего, что блок трогает ----------
	var _u20_ad0: RefCounted = Monetization._adapter
	var _u20_ads0: RefCounted = Monetization._ads
	var _u20_game0: Node = Monetization._game
	var _u20_store0 := Monetization.store_id
	var _u20_billing0 := Monetization.billing_available
	var _u20_cfg0: Dictionary = Monetization.ads_config
	var _u20_cat_size0 := Monetization.catalog.size()
	var _u20_pproduct0 := Monetization._pending_product
	var _u20_pplace0 := Monetization._pending_placement
	var _u20_queue0: Array = Monetization._verify_requests.duplicate(true)
	var _u20_data0: Dictionary = UserData._data.duplicate(true)
	var _u20_proc0: Dictionary = UserData._processed.duplicate(true)
	var _u20_grant0: Dictionary = UserData._granted.duplicate(true)
	var _u20_ads_state0: Dictionary = UserData.get_ads_state()
	var _u20_consent0 := UserData.get_consent("ads_personalized")
	var _u20_own0 := UserData.is_product_owned("remove_ads")
	var _u20_eth0 := g._engine.ether
	var _u20_ovf0 := g._engine.ether_overflow
	var _u20_gold0 := g._engine.sage_gold
	var _u20_status0 := g._engine.status_text
	var _u20_theme0 := g._home._cosmetic_theme
	var _u20_thon0 := g._home._theme_custom_on
	var _u20_netq0 := Net._queue.size()
	# «Настоящие» имена файлов установки берутся из того же массива
	# Selftest.U20_REAL_FILES, чьи ST-пара и литералы сверяются с REAL_*/ST_*
	# константами autoload'ов кейсом u23 в начале Selftest.run (индексы 0/3/5 =
	# user.json / purchases.json / analytics.json): локальный литерал здесь
	# расходился бы молча, а сверка «путь отведён от настоящего имени» с общего
	# источника краснеет ровно на снятии перевода.
	var _u20_real_user := String(Selftest.U20_REAL_FILES[0])
	var _u20_real_journal := String(Selftest.U20_REAL_FILES[3])
	var _u20_real_analytics := String(Selftest.U20_REAL_FILES[5])
	var _u20_vocab := ["purchased", "pending", "rejected"]
	var _u20_ev := U20Events.new()
	Monetization.purchase_failed.connect(_u20_ev._on_purchase_failed)
	Monetization.purchase_started.connect(_u20_ev._on_purchase_started)
	Monetization.purchase_succeeded.connect(_u20_ev._on_purchase_succeeded)
	Monetization.rewarded_available.connect(_u20_ev._on_rewarded_available)
	Monetization.rewarded_started.connect(_u20_ev._on_rewarded_started)

	# ---------- 1. матрица Google Play purchaseState (T21) ----------
	var _u20_gp := GooglePlayBillingAdapterScript.new()
	# Убрать ветку `0:` или вернуть в ней не "purchased" — краснеет она.
	Selftest.check("u20 gp purchaseState 0 is the only confirmation",
		_u20_gp._normalize_state({"purchase_state": 0}) == "purchased")
	# Инверсия `1: return "purchased"` (или "rejected") — краснеет она.
	Selftest.check("u20 gp purchaseState 1 stays pending",
		_u20_gp._normalize_state({"purchase_state": 1}) == "pending")
	# Инверсия `2: return "purchased"` — краснеет она.
	Selftest.check("u20 gp purchaseState 2 refuses",
		_u20_gp._normalize_state({"purchase_state": 2}) == "rejected")
	# Удалить ветку `elif raw.has("purchaseState")` — краснеет только первый
	# конъюнкт: второй при удалении уходит в `else: return "rejected"` и даёт то же
	# значение, то есть остаётся зелёным. Второй закрепляет другое — camelCase-ветка
	# обязана сверять значение, а не подтверждать любой camelCase-ключ: жёсткий
	# `return "purchased"` в ней краснит ровно второй конъюнкт. Мутация
	# `_:` -> "purchased" сюда не доходит: 0 и 2 попадают в явные ветки.
	Selftest.check("u20 gp camelCase state key is read",
		_u20_gp._normalize_state({"purchaseState": 0}) == "purchased"
		and _u20_gp._normalize_state({"purchaseState": 2}) == "rejected")
	# Поменять местами проверку purchase_state / purchaseState — краснеет она.
	Selftest.check("u20 gp snake_case key wins when both are present",
		_u20_gp._normalize_state({"purchase_state": 0, "purchaseState": 2}) == "purchased"
		and _u20_gp._normalize_state({"purchase_state": 2, "purchaseState": 0}) == "rejected")
	# Дословный дефект T21: дефолт, превращающий «нет поля» в покупку. Заменить
	# `else: return "rejected"` на "purchased" (или вернуть `raw.get(..., 1)`) —
	# краснеет она.
	Selftest.check("u20 gp absent state is never a purchase",
		_u20_gp._normalize_state({}) == "rejected")
	# null не подтверждает покупку. Кейс pinned: мутация `_:` -> "purchased"
	# (null уходит именно в `_`) краснит его; туда же попадает приведение значения
	# перед match — int(null) это либо 0 -> "purchased", либо падение вызова и
	# тогда сравнение получает null, и в обоих прочтениях кейс краснеет.
	# Дефолт `raw.get("purchase_state", 0)` здесь НЕ при чём: ключ с null
	# присутствует, default не срабатывает, значение остаётся null и уходит в `_`.
	Selftest.check("u20 gp null state is never a purchase",
		_u20_gp._normalize_state({"purchase_state": null}) == "rejected")
	# Строка "0" — не целое: привести значение через int() — краснеет она.
	Selftest.check("u20 gp string state is never a purchase",
		_u20_gp._normalize_state({"purchase_state": "0"}) == "rejected")
	# Фолбэк `_:` -> "purchased" краснит оба конъюнкта.
	Selftest.check("u20 gp unknown numeric states refuse",
		_u20_gp._normalize_state({"purchase_state": 3}) == "rejected"
		and _u20_gp._normalize_state({"purchase_state": -1}) == "rejected")
	# Bool не подтверждает покупку — строго по обоим значениям. Этот кейс pinned:
	# он фиксирует текущую семантику движка (литеральный паттерн match сверяет тип
	# до значения, равенства BOOL↔INT нет), а не защиту от удалённой строки —
	# удалять здесь нечего. Краснеет как минимум на двух правках: привести значение
	# перед match (`int(value)` — true станет 1 -> "pending", красен первый
	# конъюнкт; false станет 0 -> "purchased", красен второй) либо подменить ветку
	# `_:` на подтверждающую строку (красны оба). Мутация
	# `raw.get("purchase_state", 0)` этот кейс НЕ касается:
	# ключ на месте, default не срабатывает.
	Selftest.check("u20 gp boolean state never confirms a purchase",
		_u20_gp._normalize_state({"purchase_state": true}) == "rejected"
		and _u20_gp._normalize_state({"purchase_state": false}) == "rejected")
	# Словарь состояний замкнут: фасад знает ровно эти три строки. Подменить любую
	# ветку на "unknown"/"" — краснеет она.
	var _u20_gp_vocab := true
	for _u20_raw in [{}, {"purchase_state": null}, {"purchase_state": 0}, {"purchase_state": 1},
			{"purchase_state": 2}, {"purchase_state": 7}, {"purchase_state": "0"},
			{"purchase_state": true}, {"purchaseState": 0}]:
		if not _u20_vocab.has(_u20_gp._normalize_state(_u20_raw as Dictionary)):
			_u20_gp_vocab = false
	Selftest.check("u20 gp state vocabulary is closed", _u20_gp_vocab)

	# ---------- 2. Google Play: нормализация всего чека ----------
	# Убрать `sku == "" or` в раннем возврате — краснеет она (словарь не пустой).
	Selftest.check("u20 gp receipt without sku is dropped",
		_u20_gp._normalize_purchase({"purchase_token": "u20_tok", "purchase_state": 0}).is_empty())
	# Убрать `or token == ""` — краснеет она.
	Selftest.check("u20 gp receipt without token is dropped",
		_u20_gp._normalize_purchase({"sku": "al_loop_ether_500", "purchase_state": 0}).is_empty())
	# Провайдер берётся из provider_id(), состояние — из матрицы выше: захардкодить
	# здесь "purchased" — краснеет последний конъюнкт, убрать provider_id() — второй.
	var _u20_gp_p: Dictionary = _u20_gp._normalize_purchase(
		{"sku": "al_loop_ether_500", "purchase_token": "u20_tok_full", "purchase_state": 1})
	Selftest.check("u20 gp receipt carries provider, sku, token and normalized state",
		not _u20_gp_p.is_empty()
		and String(_u20_gp_p.get("provider", "")) == "google_play"
		and String(_u20_gp_p.get("sku", "")) == "al_loop_ether_500"
		and String(_u20_gp_p.get("token", "")) == "u20_tok_full"
		and String(_u20_gp_p.get("state", "")) == "pending")
	# Убрать любой из алиасов (productId / purchaseToken) — краснеет соответствующий
	# конъюнкт; aliased-вход без состояния дал бы "rejected", поэтому третий конъюнкт
	# ловит именно сквозную передачу состояния.
	var _u20_gp_alias: Dictionary = _u20_gp._normalize_purchase(
		{"productId": "al_loop_ether_1500", "purchaseToken": "u20_tok_alias", "purchaseState": 0})
	Selftest.check("u20 gp receipt reads legacy plugin key aliases",
		String(_u20_gp_alias.get("sku", "")) == "al_loop_ether_1500"
		and String(_u20_gp_alias.get("token", "")) == "u20_tok_alias"
		and String(_u20_gp_alias.get("state", "")) == "purchased")
	# sku подставляется из _sku_pending, когда плагин его не прислал: убрать этот
	# алиас — краснеет она (чек стал бы пустым).
	_u20_gp._sku_pending = "al_loop_sage_gold_1"
	var _u20_gp_pend: Dictionary = _u20_gp._normalize_purchase({"purchase_token": "u20_tok_sku_fb", "purchase_state": 0})
	Selftest.check("u20 gp receipt falls back to the sku being bought",
		String(_u20_gp_pend.get("sku", "")) == "al_loop_sage_gold_1")
	_u20_gp._sku_pending = ""
	# acknowledged: дефолт false (без него non-consumable признали бы выданным до
	# acknowledge) — убрать чтение is_acknowledged — краснеет второй конъюнкт.
	var _u20_gp_ack: Dictionary = _u20_gp._normalize_purchase(
		{"sku": "al_loop_remove_ads", "purchase_token": "u20_tok_ack", "purchase_state": 0})
	var _u20_gp_ack2: Dictionary = _u20_gp._normalize_purchase(
		{"sku": "al_loop_remove_ads", "purchase_token": "u20_tok_ack2", "purchase_state": 0, "is_acknowledged": true})
	Selftest.check("u20 gp receipt acknowledges only when the store says so",
		bool(_u20_gp_ack.get("acknowledged", true)) == false
		and bool(_u20_gp_ack2.get("acknowledged", false)) == true)

	# ---------- 3. матрица RuStore Pay (тот же дефект T21, другая форма) ----------
	var _u20_rs := RuStorePayAdapterScript.new()
	# Выкинуть "PAID" из шаблона match — краснеет она.
	Selftest.check("u20 rs PAID grants", _u20_rs._normalize_state({"purchase_state": "PAID"}) == "purchased")
	# Выкинуть "BOUGHT" — краснеет она (синоним оплаченной покупки в RuStore Store
	# API, см. комментарий в самом методе).
	Selftest.check("u20 rs BOUGHT grants", _u20_rs._normalize_state({"purchaseState": "BOUGHT"}) == "purchased")
	# Выкинуть "PURCHASED" — краснеет она.
	Selftest.check("u20 rs PURCHASED grants", _u20_rs._normalize_state({"state": "PURCHASED"}) == "purchased")
	# Убрать to_upper() — "paid" уехал бы в `_` -> "rejected": краснеет первый
	# конъюнкт (второй ловит ту же мутацию на "Pending"). Регистр статуса не должен
	# решать судьбу покупки — это намеренное поведение, фиксируется здесь.
	Selftest.check("u20 rs status case is normalized",
		_u20_rs._normalize_state({"purchase_state": "paid"}) == "purchased"
		and _u20_rs._normalize_state({"purchase_state": "Pending"}) == "pending")
	# Инверсия "PENDING" -> purchased/rejected — краснеет она.
	Selftest.check("u20 rs PENDING stays pending",
		_u20_rs._normalize_state({"purchase_state": "PENDING"}) == "pending")
	# Отмена/возврат не должны попадать в «известные»: добавить любой из них в
	# шаблон "purchased" — краснеет соответствующий конъюнкт.
	Selftest.check("u20 rs canceled and refunded statuses refuse",
		_u20_rs._normalize_state({"purchase_state": "CANCELED"}) == "rejected"
		and _u20_rs._normalize_state({"purchase_state": "CANCELLED"}) == "rejected"
		and _u20_rs._normalize_state({"purchase_state": "refunded"}) == "rejected")
	# Дефект T21 в RuStore-форме: прежний дефолт был "PAID". Вернуть его
	# (`var value := "PAID"`) — краснеет она.
	Selftest.check("u20 rs absent status is never a purchase",
		_u20_rs._normalize_state({}) == "rejected")
	# Числовые состояния — язык Google Play; здесь они не подтверждают покупку.
	# Утверждение намеренно «не purchased», а не точная строка ответа: RuStore
	# приводит значение через String(raw[key]) (rustore_pay.gd:163), и сверять
	# "0"/"1" значило бы закрепить поведение каста, а не контракт. Мутация,
	# которая красит оба конъюнкта ровно этой проверки: начать матчить числовые
	# статусы в purchased-шаблон — добавить строковые литералы "0"/"1" рядом с
	# "PAID", "BOUGHT", "PURCHASED" (String(0) == "0" попадёт в шаблон и даст
	# "purchased"). Int-литералы 0/1 в шаблон добавлять бесполезно — value
	# после String() всегда строка, мутация не доживает до ответа.
	Selftest.check("u20 rs numeric status is never a purchase",
		_u20_rs._normalize_state({"purchase_state": 0}) != "purchased"
		and _u20_rs._normalize_state({"purchase_state": 1}) != "purchased")
	# Порядок ключей + break: решает первый найденный из перечисленных в цикле
	# (rustore_pay.gd:161-164), независимо от порядка вставки в словаре — оба
	# входа содержат purchase_state и state с разной вставкой. Мутации: убрать
	# break (побеждает последний найденный — "state", т.е. "PAID") краснит оба
	# конъюнкта; переставить ключи так, чтобы "state" стал первым, — тоже оба:
	# первый конъюнкт вернёт "purchased" вместо "rejected", второй — "purchased"
	# вместо "pending", который побеждает при текущем порядке.
	Selftest.check("u20 rs first known status key wins",
		_u20_rs._normalize_state({"purchase_state": "CANCELED", "state": "PAID"}) == "rejected"
		and _u20_rs._normalize_state({"state": "PAID", "purchase_state": "PENDING"}) == "pending")
	# Словарь состояний замкнут: на любом входе ответ — ровно одна из трёх строк
	# фасада. Краснеет на мутации, у которой _normalize_state начинает возвращать
	# строку вне вокабуляра ("" или, например, "unknown" — новый статус без
	# перевода на контракт фасада). ЭТА проверка не краснеет на удалении "PAID"
	# из шаблона (ответ "rejected" остаётся в вокабуляре) — тот дефект ловят
	# кейсы выше; здесь она страховка от расхождения алфавита адаптера и фасада.
	var _u20_rs_vocab := true
	for _u20_rraw in [{}, {"purchase_state": ""},
			{"purchase_state": "PAID"}, {"purchase_state": "paid"}, {"purchaseState": "PENDING"},
			{"state": "BOUGHT"}, {"state": "kaboodle"}]:
		if not _u20_vocab.has(_u20_rs._normalize_state(_u20_rraw as Dictionary)):
			_u20_rs_vocab = false
	Selftest.check("u20 rs state vocabulary is closed", _u20_rs_vocab)

	# ---------- 4. RuStore: нормализация всего чека ----------
	# Ранний возврат по пустому product_id — первый конъюнкт, по пустому
	# purchase_id — второй; убрать любой — краснеет он же.
	Selftest.check("u20 rs receipt without product or purchase id is dropped",
		_u20_rs._normalize_purchase({"purchase_id": "u20_rs_tok", "purchase_state": "PAID"}).is_empty()
		and _u20_rs._normalize_purchase({"product_id": "al_loop_ether_500", "purchase_state": "PAID"}).is_empty())
	# Провайдер и дублирование token -> purchase_id: переименовать ключ в
	# конструкторе — краснеет соответствующая строка.
	var _u20_rs_p: Dictionary = _u20_rs._normalize_purchase(
		{"product_id": "al_loop_ether_500", "purchase_id": "u20_rs_full", "purchase_state": "PENDING"})
	Selftest.check("u20 rs receipt carries provider, purchase_id and normalized state",
		not _u20_rs_p.is_empty()
		and String(_u20_rs_p.get("provider", "")) == "rustore"
		and String(_u20_rs_p.get("sku", "")) == "al_loop_ether_500"
		and String(_u20_rs_p.get("token", "")) == "u20_rs_full"
		and String(_u20_rs_p.get("purchase_id", "")) == "u20_rs_full"
		and String(_u20_rs_p.get("state", "")) == "pending")
	# Алиасы productId/invoiceId/product/subscriptionToken: убрать любой из
	# raw.get-алиасов — краснеет нужный конъюнкт.
	var _u20_rs_a1: Dictionary = _u20_rs._normalize_purchase(
		{"productId": "al_loop_ether_1500", "invoiceId": "u20_rs_inv", "state": "PAID"})
	var _u20_rs_a2: Dictionary = _u20_rs._normalize_purchase(
		{"product": "al_loop_sage_gold_1", "subscriptionToken": "u20_rs_sub", "purchaseState": "PURCHASED"})
	Selftest.check("u20 rs receipt reads plugin key aliases",
		String(_u20_rs_a1.get("sku", "")) == "al_loop_ether_1500"
		and String(_u20_rs_a1.get("token", "")) == "u20_rs_inv"
		and String(_u20_rs_a2.get("sku", "")) == "al_loop_sage_gold_1"
		and String(_u20_rs_a2.get("token", "")) == "u20_rs_sub"
		and String(_u20_rs_a2.get("state", "")) == "purchased")
	# Убрать `_sku_pending` из цепочки алиасов — чек стал бы пустым: краснеет она.
	_u20_rs._sku_pending = "al_loop_starter_2026"
	var _u20_rs_pend: Dictionary = _u20_rs._normalize_purchase({"purchase_id": "u20_rs_sku_fb", "purchase_state": "PAID"})
	Selftest.check("u20 rs receipt falls back to the sku being bought",
		String(_u20_rs_pend.get("sku", "")) == "al_loop_starter_2026")
	_u20_rs._sku_pending = ""

	# ---------- 5. контракт «адаптер -> фасад»: не-покупка не проходит дальше ----------
	# Этого не ловил ни один предыдущий прогон: состояние с выхода адаптера уходит в
	# реальный Monetization._on_purchase_received. Доказательства отказа: ровно один
	# нужный код purchase_failed, пустая очередь проверок чеков и пустая очередь Net
	# (начисление невозможно без запроса вердикта).
	Monetization.store_id = "google_play"
	Monetization._verify_requests.clear()
	var _u20_pending_receipt: Dictionary = _u20_gp._normalize_purchase(
		{"sku": "al_loop_ether_500", "purchase_token": "u20_facade_pending", "purchase_state": 1})
	var _u20_ev0 := _u20_ev.events.size()
	Monetization._on_purchase_received(_u20_pending_receipt)
	# Первый конъюнкт — сквозной контракт (адаптер обязан отдать "pending");
	# удаление `if state == "pending"` в фасаде (monetization.gd:297-299) краснит
	# второй конъюнкт (код станет purchase_rejected). К.3 («ok» нет), к.6 (эфир) —
	# страховка: не краснеют ни от какой мутации этих гейтов — успех и начисление
	# живут в асинхронном _finish_purchase, которого в рамках этого файла сюиты
	# нет (сам асинхронный путь напрямую прогоняется в suite_journal_misc: там
	# _finish_purchase вызывается и purchase_succeeded наблюдается); к.4-к.5
	# (верификация не ушла) краснеют только при удалении обоих state-гейтов сразу.
	Selftest.check("u20 facade refuses a pending google receipt",
		String(_u20_pending_receipt.get("state", "")) == "pending"
		and _u20_ev.count_since(_u20_ev0, "failed:purchase_pending:") == 1
		and _u20_ev.count_since(_u20_ev0, "ok:") == 0
		and Monetization._verify_requests.is_empty()
		and Net._queue.size() == _u20_netq0
		and g._engine.ether + g._engine.ether_overflow == _u20_eth0 + _u20_ovf0)
	# Убрать `if state != "purchased"` (monetization.gd:300-302) — краснеют второй,
	# четвёртый и пятый конъюнкты: declined ушёл бы на верификацию (заявка в
	# _verify_requests, запрос в очередь Net). К.3 («ok» нет) — страховка: он
	# краснеет только эмитом purchase_succeeded, а он асинхронный и в рамках этого
	# файла сюиты недостижим (сам асинхронный путь напрямую прогоняется в
	# suite_journal_misc).
	var _u20_rejected_receipt: Dictionary = _u20_gp._normalize_purchase(
		{"sku": "al_loop_ether_500", "purchase_token": "u20_facade_rejected", "purchase_state": 2})
	var _u20_ev1 := _u20_ev.events.size()
	Monetization._on_purchase_received(_u20_rejected_receipt)
	Selftest.check("u20 facade refuses a declined google receipt",
		String(_u20_rejected_receipt.get("state", "")) == "rejected"
		and _u20_ev.count_since(_u20_ev1, "failed:purchase_rejected:") == 1
		and _u20_ev.count_since(_u20_ev1, "ok:") == 0
		and Monetization._verify_requests.is_empty()
		and Net._queue.size() == _u20_netq0)
	# Тот же чек вообще без поля состояния — ровно форма дефекта T21: адаптер с
	# дефолтом вернул бы "purchased", запрос ушёл бы, товар начислился. Краснеет при
	# любой мутации, превращающей «нет поля» в purchased.
	var _u20_nostate_receipt: Dictionary = _u20_gp._normalize_purchase(
		{"sku": "al_loop_ether_500", "purchase_token": "u20_facade_nostate"})
	var _u20_ev2 := _u20_ev.events.size()
	Monetization._on_purchase_received(_u20_nostate_receipt)
	Selftest.check("u20 facade refuses a receipt with no state at all",
		String(_u20_nostate_receipt.get("state", "")) == "rejected"
		and _u20_ev.count_since(_u20_ev2, "failed:purchase_rejected:") == 1
		and _u20_ev.count_since(_u20_ev2, "failed:purchase_pending:") == 0
		and Monetization._verify_requests.is_empty()
		and Net._queue.size() == _u20_netq0)
	# Сырое вендорское состояние, пропущенное мимо адаптера («PAID» вместо
	# нормализованного «purchased»): фасад знает ровно три строки и обязан
	# отказать. Разрешить unknown-строку (ослабить гейт до `== "rejected"`) —
	# краснеют к.1, к.3, к.4; к.2 («ok» нет) — страховка: purchase_succeeded
	# эмитится только из асинхронного _finish_purchase, недостижимого в рамках
	# этого файла сюиты (асинхронный путь покрыт suite_journal_misc).
	var _u20_ev3 := _u20_ev.events.size()
	Monetization._on_purchase_received({"provider": "google_play", "sku": "al_loop_ether_500",
		"token": "u20_facade_raw", "state": "PAID"})
	Selftest.check("u20 facade refuses a vendor state it does not know",
		_u20_ev.count_since(_u20_ev3, "failed:purchase_rejected:") == 1
		and _u20_ev.count_since(_u20_ev3, "ok:") == 0
		and Monetization._verify_requests.is_empty()
		and Net._queue.size() == _u20_netq0)
	# Тот же отказ с другой стороны контракта (RuStore pending): удалить
	# `if state == "pending"` — краснеет к.2 (код станет purchase_rejected).
	# К.3 («ok» нет) — страховка: асинхронный успех в рамках этого файла сюиты
	# недостижим (он покрыт напрямую в suite_journal_misc); к.4
	# (верификация не ушла) краснеет только при удалении обоих state-гейтов.
	var _u20_rs_pending_receipt: Dictionary = _u20_rs._normalize_purchase(
		{"product_id": "al_loop_ether_500", "purchase_id": "u20_facade_rs_pending", "purchase_state": "PENDING"})
	var _u20_ev4 := _u20_ev.events.size()
	Monetization._on_purchase_received(_u20_rs_pending_receipt)
	Selftest.check("u20 facade refuses a pending rustore receipt",
		String(_u20_rs_pending_receipt.get("state", "")) == "pending"
		and _u20_ev.count_since(_u20_ev4, "failed:purchase_pending:") == 1
		and _u20_ev.count_since(_u20_ev4, "ok:") == 0
		and Monetization._verify_requests.is_empty())

	# ---------- 6. гейты purchase() ----------
	var _u20_bill := U20FakeBilling.new()
	Monetization._adapter = _u20_bill
	Monetization.billing_available = true
	Monetization.store_id = "google_play"
	# Товара нет в каталоге. Убрать `if product.is_empty()` — отказ пришёл бы с
	# кодом sku_not_configured, и точное совпадение кода (третий конъюнкт) краснеет.
	_u20_bill.calls.clear()
	var _u20_ev5 := _u20_ev.events.size()
	var _u20_unknown := Monetization.purchase("u20_no_such_product")
	Selftest.check("u20 purchase refuses a product missing from the catalog",
		not _u20_unknown and _u20_bill.calls.is_empty()
		and _u20_ev.count_since(_u20_ev5, "failed:unknown_sku:u20_no_such_product") == 1
		and Monetization._pending_product == _u20_pproduct0
		and UserData.get_pending_purchase("u20_no_such_product").is_empty())
	# already_owned стоит ДО обращения в стор: снять гейт — _u20_bill получил бы
	# sku (второй конъюнкт). Снять `type == "non_consumable"` — краснеет последний
	# конъюнкт: consumable «уже купленный» обязан пройти.
	UserData.set_owned_product("remove_ads", true)
	UserData.set_owned_product("ether_pack_small", true)
	var _u20_ev6 := _u20_ev.events.size()
	var _u20_owned_calls := _u20_bill.calls.size()
	var _u20_already := Monetization.purchase("remove_ads")
	var _u20_consumable_calls := _u20_bill.calls.size()
	var _u20_still_ok := Monetization.purchase("ether_pack_small")
	Selftest.check("u20 owned non-consumable is refused before the store is asked",
		not _u20_already and _u20_bill.calls.size() == _u20_owned_calls
		and _u20_ev.count_since(_u20_ev6, "failed:already_owned:remove_ads") == 1
		and UserData.get_pending_purchase("remove_ads").is_empty()
		and _u20_still_ok and _u20_bill.calls.size() == _u20_consumable_calls + 1)
	UserData.set_owned_product("remove_ads", _u20_own0)
	UserData.set_owned_product("ether_pack_small", false)
	UserData.clear_pending_purchase("ether_pack_small")
	Monetization._pending_product = _u20_pproduct0
	# Провайдер недоступен — двумя независимыми способами (адаптера нет / флаг
	# снят), код отказа обязан быть одним. Поменять `or` на `and` — краснеет второй
	# вызов (адаптер есть, флаг снят): он дошёл бы до sku-ветки.
	_u20_bill.calls.clear()
	var _u20_ev7 := _u20_ev.events.size()
	Monetization._adapter = null
	var _u20_no_adapter := Monetization.purchase("ether_pack_small")
	Monetization._adapter = _u20_bill
	Monetization.billing_available = false
	var _u20_no_flag := Monetization.purchase("ether_pack_small")
	Monetization.billing_available = true
	Selftest.check("u20 purchase without an available provider reports provider_unavailable",
		not _u20_no_adapter and not _u20_no_flag
		and _u20_ev.count_since(_u20_ev7, "failed:provider_unavailable:ether_pack_small") == 2
		and _u20_bill.calls.is_empty()
		and UserData.get_pending_purchase("ether_pack_small").is_empty())
	# SKU не настроен для текущего стора: отказ ДО открытия pending. Переставить
	# открытие pending выше sku-проверки — краснеют четвёртый и пятый конъюнкты
	# (запись pending и _pending_product); третий (стор не вызван) при этой
	# мутации остаётся зелёным — sku пустой, до адаптера дело не доходит.
	Monetization.store_id = "standalone"
	_u20_bill.calls.clear()
	var _u20_ev8 := _u20_ev.events.size()
	var _u20_no_sku := Monetization.purchase("ether_pack_small")
	Selftest.check("u20 purchase with no sku for this store neither opens pending nor calls the store",
		not _u20_no_sku and _u20_ev.count_since(_u20_ev8, "failed:sku_not_configured:ether_pack_small") == 1
		and _u20_bill.calls.is_empty()
		and UserData.get_pending_purchase("ether_pack_small").is_empty()
		and Monetization._pending_product == _u20_pproduct0)
	# Успешный старт: стор вызван ровно один раз и с тем sku, который резолвится по
	# активному провайдеру; pending открыт с provider/sku; сигнал purchase_started
	# был. Убрать set_pending_purchase — краснеет 4-й конъюнкт; убрать
	# purchase_started.emit — 6-й.
	Monetization.store_id = "google_play"
	_u20_bill.calls.clear()
	var _u20_ev9 := _u20_ev.events.size()
	var _u20_go := Monetization.purchase("ether_pack_small")
	var _u20_pend_rec := UserData.get_pending_purchase("ether_pack_small")
	Selftest.check("u20 purchase opens pending and asks the store for the mapped sku",
		_u20_go and _u20_bill.calls.size() == 1
		and String(_u20_bill.calls[0]) == "purchase:al_loop_ether_500"
		and String(_u20_pend_rec.get("provider", "")) == "google_play"
		and String(_u20_pend_rec.get("sku", "")) == "al_loop_ether_500"
		and Monetization._pending_product == "ether_pack_small"
		and _u20_ev.count_since(_u20_ev9, "started:ether_pack_small") == 1
		and _u20_ev.count_since(_u20_ev9, "failed:") == 0)
	UserData.clear_pending_purchase("ether_pack_small")
	Monetization._pending_product = _u20_pproduct0
	# Разные сторы — разные sku одного продукта (в каталоге значения совпадают,
	# поэтому фикстура заводит разъём). Заменить store_id в sku_map.get на
	# литеральный — краснеет второй вызов.
	Monetization.catalog["u20_gate_probe"] = {
		"id": "u20_gate_probe", "type": "consumable", "title": "U20 фикстура",
		"reward": {}, "store_sku": {"google_play": "u20_gp_sku", "rustore": "u20_rs_sku"},
	}
	_u20_bill.calls.clear()
	Monetization.store_id = "rustore"
	var _u20_rs_go := Monetization.purchase("u20_gate_probe")
	Monetization.store_id = "google_play"
	var _u20_gp_go := Monetization.purchase("u20_gate_probe")
	Selftest.check("u20 purchase maps the sku of the active store",
		_u20_rs_go and _u20_gp_go and _u20_bill.calls.size() == 2
		and String(_u20_bill.calls[0]) == "purchase:u20_rs_sku"
		and String(_u20_bill.calls[1]) == "purchase:u20_gp_sku")
	UserData.clear_pending_purchase("u20_gate_probe")
	Monetization.catalog.erase("u20_gate_probe")
	Monetization._pending_product = _u20_pproduct0
	# Честный возврат ответа стора: purchase() обязан вернуть ровно то, что
	# ответил адаптер (monetization.gd:172). Пары мутаций: заменить
	# `return bool(_adapter.purchase(sku))` на `return true` (оптимистичный успех
	# при отказе магазина) — краснеет первый конъюнкт; вернуть false до обращения
	# в стор — второй. Рычаг отказа — U20FakeBilling.ok = false.
	_u20_bill.ok = false
	_u20_bill.calls.clear()
	var _u20_store_off := Monetization.purchase("ether_pack_small")
	_u20_bill.ok = true
	Selftest.check("u20 purchase reports the store answer unchanged",
		not _u20_store_off and _u20_bill.calls.size() == 1)
	UserData.clear_pending_purchase("ether_pack_small")
	Monetization._pending_product = _u20_pproduct0

	# ---------- 7. кап и cooldown rewarded ----------
	var _u20_ads := U20FakeAds.new()
	Monetization._ads = _u20_ads
	UserData.set_consent("ads_personalized", "granted")
	var _u20_now := Time.get_unix_time_from_system()
	var _u20_today := Time.get_date_string_from_system()
	# Осмысленность фикстуры: guardrails и placement'ы читаются из
	# data/monetization.json. Поменять cap/cooldown в каталоге — краснеют первые две
	# строки, переименовать placement — третья/четвёртая.
	Selftest.check("u20 catalog guardrails and placements are readable",
		int(Monetization.ads_config.get("rewarded_daily_cap", -1)) == 5
		and float(Monetization.ads_config.get("rewarded_cooldown_sec", -1.0)) == 150.0
		and not Monetization._find_placement("extra_brew").is_empty()
		and not Monetization._find_placement("source_boost_60").is_empty()
		and Monetization._find_placement("u20_bogus_placement").is_empty())
	# Неизвестный placement: убрать `if placement.is_empty()` — фасад дошёл бы до
	# адаптера и вернул true: краснеют первый и второй конъюнкты.
	_u20_ads.calls.clear()
	var _u20_ev10 := _u20_ev.events.size()
	var _u20_bogus := Monetization.show_rewarded("u20_bogus_placement")
	Selftest.check("u20 unknown placement is refused with the availability event",
		not _u20_bogus and _u20_ads.calls.is_empty()
		and _u20_ev.count_since(_u20_ev10, "available:u20_bogus_placement:false") == 1
		and _u20_ev.count_since(_u20_ev10, "rstarted:") == 0
		and Monetization._pending_placement == _u20_pplace0)
	_u20_ads.calls.clear()
	var _u20_ev11 := _u20_ev.events.size()
	var _u20_empty := Monetization.show_rewarded("")
	# Пустой placement: тот же гейт на пустом аргументе; удалить проверку — краснеет
	# второй конъюнкт (emit ушёл бы с другим id).
	Selftest.check("u20 empty placement is refused too",
		not _u20_empty and _u20_ads.calls.is_empty()
		and _u20_ev.count_since(_u20_ev11, "available::false") == 1)
	# Дневной кап ровно на границе: 4 из 5 — показ идёт, 5 из 5 — отказ. Мутации:
	# `>=` → `>` (или cap+1) краснит к.5-к.8 проверки ниже; гейт с запасом в минус
	# (cap-1) краснит к.1-к.4.
	_u20_set_ads_state(_u20_today, 4, 0.0)
	_u20_ads.calls.clear()
	var _u20_ev12 := _u20_ev.events.size()
	var _u20_under_cap := Monetization.show_rewarded("extra_brew")
	var _u20_under_calls := _u20_ads.calls.size()
	var _u20_under_pending := Monetization._pending_placement
	Monetization._pending_placement = _u20_pplace0
	_u20_set_ads_state(_u20_today, 5, 0.0)
	_u20_ads.calls.clear()
	var _u20_ev13 := _u20_ev.events.size()
	var _u20_at_cap := Monetization.show_rewarded("extra_brew")
	# к.1-к.4 — контроль «4 из 5 ещё можно» (без них мутация капа с запасом
	# осталась бы зелёной); к.5-к.8 — ровно граница: отказ, чистый pending,
	# событие available:...:false и невзыванный адаптер.
	Selftest.check("u20 rewarded daily cap blocks exactly at the limit",
		_u20_under_cap and _u20_under_calls == 1 and _u20_under_pending == "extra_brew"
		and _u20_ev.count_since(_u20_ev12, "rstarted:extra_brew") == 1
		and not _u20_at_cap and Monetization._pending_placement == _u20_pplace0
		and _u20_ev.count_since(_u20_ev13, "available:extra_brew:false") == 1
		and _u20_ads.calls.is_empty())
	# Значение капа берётся из каталога: при cap=2 счётчик 2 — отказ (с хардкодом 5
	# показ прошёл бы). Заменить ads_config.get(...) на литерал 5 — краснеет она.
	var _u20_cap_cfg: Dictionary = Monetization.ads_config.duplicate(true)
	_u20_cap_cfg["rewarded_daily_cap"] = 2
	Monetization.ads_config = _u20_cap_cfg
	_u20_set_ads_state(_u20_today, 2, 0.0)
	_u20_ads.calls.clear()
	var _u20_ev14 := _u20_ev.events.size()
	var _u20_custom_cap := Monetization.show_rewarded("extra_brew")
	Monetization.ads_config = _u20_cfg0
	Selftest.check("u20 rewarded cap is read from the catalog, not hardcoded",
		not _u20_custom_cap and _u20_ads.calls.is_empty()
		and _u20_ev.count_since(_u20_ev14, "available:extra_brew:false") == 1)
	# Кулдаун: 200 с назад — показ идёт (окно 150 с), 60 с назад — отказ. Инверсия
	# `<` -> `>` краснит обе половины, обнуление дефолта — вторую.
	_u20_set_ads_state(_u20_today, 0, _u20_now - 200.0)
	_u20_ads.calls.clear()
	var _u20_ev15 := _u20_ev.events.size()
	var _u20_cool_ok := Monetization.show_rewarded("source_boost_60")
	var _u20_cool_calls := _u20_ads.calls.size()
	var _u20_cool_events := _u20_ev.count_since(_u20_ev15, "available:source_boost_60:false")
	Monetization._pending_placement = _u20_pplace0
	_u20_set_ads_state(_u20_today, 0, _u20_now - 60.0)
	_u20_ads.calls.clear()
	var _u20_ev16 := _u20_ev.events.size()
	var _u20_in_cool := Monetization.show_rewarded("source_boost_60")
	# Первая половина — «показ за пределами окна разрешён» (без неё отказ по `<`->`>`
	# был бы зелёным); вторая — «внутри окна запрещён».
	Selftest.check("u20 rewarded cooldown blocks only inside the window",
		_u20_cool_ok and _u20_cool_events == 0 and _u20_cool_calls == 1
		and not _u20_in_cool and _u20_ads.calls.is_empty()
		and _u20_ev.count_since(_u20_ev16, "available:source_boost_60:false") == 1)
	# То же для значения кулдауна: при 3000 с показ «200 с назад» запрещён.
	# Заменить `float(ads_config.get("rewarded_cooldown_sec", 150))` на литерал
	# 150.0 — фикстура прошла бы показ и краснеют все три конъюнкта.
	var _u20_cd_cfg: Dictionary = Monetization.ads_config.duplicate(true)
	_u20_cd_cfg["rewarded_cooldown_sec"] = 3000.0
	Monetization.ads_config = _u20_cd_cfg
	_u20_set_ads_state(_u20_today, 0, _u20_now - 200.0)
	_u20_ads.calls.clear()
	var _u20_ev17 := _u20_ev.events.size()
	var _u20_custom_cool := Monetization.show_rewarded("source_boost_60")
	Monetization.ads_config = _u20_cfg0
	Selftest.check("u20 rewarded cooldown is read from the catalog, not hardcoded",
		not _u20_custom_cool and _u20_ads.calls.is_empty()
		and _u20_ev.count_since(_u20_ev17, "available:source_boost_60:false") == 1)
	# Полный проход всех гейтов: адаптер вызван ровно раз и со своим placement,
	# rewarded_available не эмитится вообще. Мутации: вызов `_ads.show_rewarded("")`
	# вместо placement_id — краснеет второй конъюнкт; не выставить
	# `_pending_placement = placement_id` — третий; вернуть false до обращения к
	# адаптеру — первый и второй; эмит `rewarded_available(placement, true)` перед
	# показом — четвёртый.
	_u20_set_ads_state(_u20_today, 0, 0.0)
	_u20_ads.calls.clear()
	var _u20_ev18 := _u20_ev.events.size()
	var _u20_shown := Monetization.show_rewarded("extra_brew")
	var _u20_shown_pending := Monetization._pending_placement
	Monetization._pending_placement = _u20_pplace0
	Selftest.check("u20 rewarded show reaches the adapter with the placement id",
		_u20_shown and _u20_ads.calls.size() == 1 and String(_u20_ads.calls[0]) == "extra_brew"
		and _u20_shown_pending == "extra_brew"
		and _u20_ev.count_since(_u20_ev18, "available:") == 0)
	# Адаптер есть, но недоступен: убрать `not _ads.is_available()` — краснеет она
	# (показ ушёл бы в адаптер).
	_u20_ads.available = false
	_u20_ads.calls.clear()
	var _u20_ev19 := _u20_ev.events.size()
	var _u20_ads_down := Monetization.show_rewarded("extra_brew")
	_u20_ads.available = true
	Selftest.check("u20 unavailable ads adapter refuses a rewarded show",
		not _u20_ads_down and _u20_ads.calls.is_empty()
		and _u20_ev.count_since(_u20_ev19, "available:extra_brew:false") == 1)
	# Адаптера нет вообще: без `_ads == null` внутри условия падение происходит НА
	# проверке, то есть тело с emit rewarded_available(..., false) не выполняется —
	# краснеет второй конъюнкт (0 событий вместо 1), а не «вернулось null».
	Monetization._ads = null
	var _u20_ev20 := _u20_ev.events.size()
	var _u20_no_ads := Monetization.show_rewarded("extra_brew")
	Monetization._ads = _u20_ads
	Selftest.check("u20 missing ads adapter refuses a rewarded show",
		not _u20_no_ads and _u20_ev.count_since(_u20_ev20, "available:extra_brew:false") == 1
		and _u20_ev.count_since(_u20_ev20, "rstarted:") == 0
		and Monetization._pending_placement == _u20_pplace0)
	# Счётчик капа привязан ко дню: старый день с 9 просмотрами обязан давать 0
	# (иначе кап заперт навсегда), сегодняшний — 9. Убрать `return 0` в
	# rewarded_count_for_today — краснеет первый конъюнкт.
	_u20_set_ads_state("2000-01-01", 9, 0.0)
	var _u20_stale_day := UserData.rewarded_count_for_today()
	_u20_set_ads_state(_u20_today, 9, 0.0)
	var _u20_today_count := UserData.rewarded_count_for_today()
	Selftest.check("u20 rewarded counter is scoped to the current day",
		_u20_stale_day == 0 and _u20_today_count == 9)
	# Убрать сброс `state["rewarded_count"] = 0` в record_rewarded_view — стало бы
	# 10: краснеет второй конъюнкт.
	_u20_set_ads_state("2000-01-01", 9, _u20_now - 9000.0)
	UserData.record_rewarded_view()
	var _u20_rolled := UserData.get_ads_state()
	var _u20_rolled_count := UserData.rewarded_count_for_today()
	Selftest.check("u20 recording a rewarded view rolls the day over",
		String(_u20_rolled.get("day", "")) == _u20_today
		and _u20_rolled_count == 1
		and float(_u20_rolled.get("last_rewarded_at", 0.0)) >= _u20_now - 5.0)

	# ---------- 8. начисление из каталога (_grant_product) ----------
	var _u20_eth_base := g._engine.ether + g._engine.ether_overflow
	# Товара нет в каталоге -> false. Убрать `if product.is_empty(): return false` —
	# возврат стал бы true (reward {} ничего не начисляет): краснеет первый
	# конъюнкт. Второй (эфир не тронут) — страховка: та же мутация эфира не трогает
	# (у пустого reward нет ни ether-, ни gold-ветки), краснеет только если начать
	# начислять несуществующему товару.
	var _u20_grant_unknown := Monetization._grant_product("u20_no_such_product")
	Selftest.check("u20 granting an unknown product reports failure",
		not _u20_grant_unknown
		and g._engine.ether + g._engine.ether_overflow == _u20_eth_base)
	# Consumable: сумма ether + overflow растёт ровно на reward.ether (прямой эфир
	# ограничен капом, остаток уходит в видимый резерв — см. _grant_ether). Убрать
	# ветку `if reward.has("ether")` — краснеет второй конъюнкт, ветку sage_gold —
	# последний. Третий конъюнкт — не про перерисовку: status_text пишет сам
	# _grant_product (monetization.gd:511), и _refresh() там же (:512), тест
	# перерисовку не дёргает; краснеет он только от мутаций этих строк (снятие
	# записи статуса или смена источника текста).
	var _u20_grant_ether := Monetization._grant_product("ether_pack_small")
	var _u20_grant_sum := g._engine.ether + g._engine.ether_overflow
	Selftest.check("u20 consumable grant adds exactly the catalog ether",
		_u20_grant_ether and _u20_grant_sum == _u20_eth_base + 500
		and g._engine.status_text.contains(String(Monetization.get_product("ether_pack_small").get("title", "")))
		and g._engine.sage_gold == _u20_gold0)
	# Отдельная награда — отдельная ветка: без `if reward.has("sage_gold")`
	# краснеет второй конъюнкт, без `+= int(reward["sage_gold"])` — тоже.
	var _u20_grant_gold := Monetization._grant_product("sage_gold_pack")
	Selftest.check("u20 sage gold grant adds gold and no ether",
		_u20_grant_gold and g._engine.sage_gold == _u20_gold0 + 1
		and g._engine.ether + g._engine.ether_overflow == _u20_grant_sum)
	# Тема: ставится и cosmetic-тема, и сброс ручной палитры (фикстура выше ставит
	# _theme_custom_on = true): убрать `_theme_custom_on = false` — краснеет
	# третий конъюнкт, убрать ветку theme — второй.
	g._home._theme_custom_on = true
	var _u20_grant_bundle := Monetization._grant_product("starter_bundle")
	var _u20_bundle_sum := g._engine.ether + g._engine.ether_overflow
	Selftest.check("u20 bundle grant applies theme, ether and gold together",
		_u20_grant_bundle and g._home._cosmetic_theme == "ember"
		and g._home._theme_custom_on == false
		and _u20_bundle_sum == _u20_grant_sum + 500
		and g._engine.sage_gold == _u20_gold0 + 2)
	g._home._cosmetic_theme = _u20_theme0
	g._home._theme_custom_on = _u20_thon0
	g._home._apply_cosmetic()
	# remove_ads: владение — единственный наблюдаемый эффект награды, и оно обязано
	# глушить межэкранную рекламу. Без set_owned_product краснеет третий конъюнкт,
	# без гейта is_product_owned("remove_ads") в can_show_interstitial — четвёртый.
	# Фикстура guardrails та же, что в T23 (3 дня установки, 9 сессий): consent уже
	# «granted», кулдаун обнулён, remove_ads снят.
	UserData.set_owned_product("remove_ads", false)
	var _u20_app: Dictionary = (UserData._data.get("app", {}) as Dictionary).duplicate(true)
	_u20_app["install_at"] = _u20_now - 3.0 * 86400.0
	_u20_app["session_count"] = 9
	_u20_app["session_started_at"] = _u20_now - 700.0
	UserData._data["app"] = _u20_app
	_u20_set_ads_state(_u20_today, 0, 0.0, 0.0)
	var _u20_inter_before := Monetization.can_show_interstitial()
	var _u20_grant_ra := Monetization._grant_product("remove_ads")
	var _u20_inter_after := Monetization.can_show_interstitial()
	Selftest.check("u20 remove_ads grant records ownership and silences interstitials",
		_u20_inter_before and _u20_grant_ra and UserData.is_product_owned("remove_ads")
		and not _u20_inter_after)
	# Владение даёт только reward.remove_ads: ни тема, ни эфир его не покупают
	# (первый конъюнкт — контроль, что remove_ads действительно не куплен). Пометить
	# в _grant_product owned для ЛЮБОГО товара — краснеют второй и третий конъюнкт;
	# вариант «для любого non-consumable» их не касается: starter_bundle и
	# ether_pack_small в data/monetization.json имеют type "consumable", а
	# non-consumable в каталоге ровно remove_ads.
	UserData.set_owned_product("remove_ads", _u20_own0)
	Monetization._grant_product("starter_bundle")
	Monetization._grant_product("ether_pack_small")
	Selftest.check("u20 only the remove-ads reward grants ownership",
		UserData.is_product_owned("remove_ads") == _u20_own0
		and not UserData.is_product_owned("starter_bundle")
		and not UserData.is_product_owned("ether_pack_small"))
	# До bind_game restore приходит раньше Main._ready: начисление обязано быть
	# отложено целиком. Владение непосредственно перед блоком принудительно снято,
	# поэтому проверяется «владения нет», а не «владение не изменилось»: прежняя
	# форма с `_u20_own0` оставляла зелёный путь на сохранении хоста с купленным
	# remove_ads. Снятие на выходе — общий возврат к снимку в _u20_own0.
	# Мутация — удалить `if _game == null: return false` (monetization.gd:496-499):
	# ветка remove_ads успеет выполнить set_owned_product(..., true) в
	# monetization.gd:510 и упадёт на обращении к _game._engine в :511. Красным
	# делает кейс ровно второй конъюнкт — владение записано ДО падения. Первый
	# (`not _u20_defer`) мутацию не ловит: падение обрывает только сам вызов, он
	# отдаёт null, а `not null` истинно; хвост сюиты не теряется, то есть детект —
	# FAIL-строка, а не сокращение прогона. Третий конъюнкт (эфир) — страховка: у
	# remove_ads нет эфира, и эта ветка не трогает сумму ни до, ни после гейта.
	UserData.set_owned_product("remove_ads", false)
	Monetization._game = null
	var _u20_sum_before_null := g._engine.ether + g._engine.ether_overflow
	var _u20_defer := Monetization._grant_product("remove_ads")
	var _u20_defer_owned := UserData.is_product_owned("remove_ads")
	Monetization._game = _u20_game0
	UserData.set_owned_product("remove_ads", _u20_own0)
	Selftest.check("u20 grant without a bound game defers the whole reward",
		not _u20_defer and not _u20_defer_owned
		and g._engine.ether + g._engine.ether_overflow == _u20_sum_before_null)

	# ---------- 9. герметичность selftest ----------
	# Main-файл UserData: метка в pending уходит в изолированный файл. Убрать перевод
	# путей ЦЕЛИКОМ (ST-ветку из UserData._ready и страховку в Selftest.run) — метка
	# попадёт в реальный файл установки, и «u20 selftest left the real user data file
	# untouched» покраснеет; снятие только ST-ветки из _ready краснит кейсы u23 в
	# начале run.
	# Дополнительно каждый кейс сверяет имя полученного пути с назначением свойства
	# (подстрока + расширение). Это единственная защита от рассинхрона двух массивов:
	# Selftest.U20_REAL_FILES и U20_ST_FILES сопоставлены только парной индексацией
	# в Selftest.run, и перестановка внутри U20_ST_FILES не меняет ни одного
	# неравенства «ST != REAL». Ловится любая из 15 перестановок пары имён (сверено
	# попарно по всем четырём кейсам); ниже названы характерные случаи, а не весь
	# список: ST[0] с любым из ST[1..2] (теряется расширение .json), ST[0] с
	# ST[3]/ST[5] (теряется «st_user»), ST[3] с ST[4]
	# (оба содержат «purchases», спасает только .json), ST[5] с любым (теряется
	# «analytics»). Что не ловилось ничем до четвёртого кейса: ST[1] с ST[2] —
	# имена TEMP_PATH и BACKUP_PATH больше нигде не сравниваются.
	UserData.set_pending_purchase("u20_sentinel_product", {"provider": "u20", "sku": "u20_sentinel_sku", "started_at": 1.0})
	var _u20_user_st := _u20_read(UserData.SAVE_PATH)
	var _u20_user_real := _u20_read(_u20_real_user)
	Selftest.check("u20 user data writes land on the isolated path",
		UserData.SAVE_PATH != _u20_real_user
		and UserData.SAVE_PATH.contains("st_user") and UserData.SAVE_PATH.ends_with(".json")
		and _u20_user_st.contains("u20_sentinel_product")
		and not _u20_user_real.contains("u20_sentinel_product"))
	UserData.clear_pending_purchase("u20_sentinel_product")
	# Журнал покупок (отдельный файл, переживает wipe): та же схема с меткой.
	# Убрать перевод PURCHASES_PATH обоими слоями — метка ляжет в реальный журнал.
	var _u20_marked := UserData.mark_purchase_granted("u20", "u20_hermetic_token", "u20_hermetic_sku")
	var _u20_journal_st := _u20_read(UserData.PURCHASES_PATH)
	var _u20_journal_real := _u20_read(_u20_real_journal)
	Selftest.check("u20 purchase journal writes land on the isolated path",
		_u20_marked and UserData.PURCHASES_PATH != _u20_real_journal
		and UserData.PURCHASES_PATH.contains("purchases")
		and UserData.PURCHASES_PATH.ends_with(".json")
		and _u20_journal_st.contains("u20_hermetic_sku")
		and not _u20_journal_real.contains("u20_hermetic_sku"))
	UserData.clear_purchase_granted("u20", "u20_hermetic_token", "u20_hermetic_sku")
	# Очередь аналитики: при согласии «granted» каждый track пишется на диск. Убрать
	# перевод Analytics.QUEUE_PATH (ST-ветка в Analytics._ready + страховка в
	# Selftest.run) — событие-проба окажется в реальном файле:
	# краснеют первый и третий конъюнкты; второй ловит перестановку ST-имени.
	var _u20_an_consent0 := UserData.get_consent("analytics")
	var _u20_an_events0: Array = Analytics._events.duplicate(true)
	UserData.set_consent("analytics", "granted")
	Analytics.configure_consent()
	Analytics.track("u20_probe_event", {"store": "selftest"})
	var _u20_analytics_real := _u20_read(_u20_real_analytics)
	var _u20_analytics_st := _u20_read(Analytics.QUEUE_PATH)
	Selftest.check("u20 analytics queue is redirected away from the real file",
		Analytics.QUEUE_PATH != _u20_real_analytics
		and Analytics.QUEUE_PATH.contains("analytics")
		and not _u20_analytics_real.contains("u20_probe_event")
		and _u20_analytics_st.contains("u20_probe_event"))
	# Парность tmp/backup — четвёртый кейс закрывает ровно то, что три предыдущих
	# не видели: имена этих двух путей больше нигде не сверяются. Мутации:
	# перестановка ST[1] с ST[2] (TEMP_PATH станет .bak, BACKUP_PATH станет .tmp)
	# краснит первый конъюнкт; снятие перевода обоими слоями (пути вернутся к
	# «alchemists_loop_…») краснит второй, потому что в реальном имени нет «st_».
	Selftest.check("u20 temp and backup twins stay paired",
		UserData.TEMP_PATH.ends_with(".tmp") and UserData.BACKUP_PATH.ends_with(".bak")
		and UserData.TEMP_PATH.contains("st_user") and UserData.BACKUP_PATH.contains("st_user"))
	UserData.set_consent("analytics", _u20_an_consent0)
	Analytics._events = _u20_an_events0
	Analytics.configure_consent()

	# ---------- 10. восстановление ----------
	Monetization.purchase_failed.disconnect(_u20_ev._on_purchase_failed)
	Monetization.purchase_started.disconnect(_u20_ev._on_purchase_started)
	Monetization.purchase_succeeded.disconnect(_u20_ev._on_purchase_succeeded)
	Monetization.rewarded_available.disconnect(_u20_ev._on_rewarded_available)
	Monetization.rewarded_started.disconnect(_u20_ev._on_rewarded_started)
	Monetization._adapter = _u20_ad0
	Monetization._ads = _u20_ads0
	Monetization._game = _u20_game0
	Monetization.store_id = _u20_store0
	Monetization.billing_available = _u20_billing0
	Monetization.ads_config = _u20_cfg0
	Monetization._pending_product = _u20_pproduct0
	Monetization._pending_placement = _u20_pplace0
	Monetization._verify_requests = _u20_queue0
	UserData.set_consent("ads_personalized", _u20_consent0)
	_u20_restore_ads_state(_u20_ads_state0)
	UserData.set_owned_product("remove_ads", _u20_own0)
	UserData._data = _u20_data0
	UserData._processed = _u20_proc0
	UserData._granted = _u20_grant0
	g._engine.ether = _u20_eth0
	g._engine.ether_overflow = _u20_ovf0
	g._engine.sage_gold = _u20_gold0
	g._engine.status_text = _u20_status0
	g._home._cosmetic_theme = _u20_theme0
	g._home._theme_custom_on = _u20_thon0
	g._home._apply_cosmetic()
	g._saves._save_game()
	# Откат проверяется по конкретным признакам, а не сравнением словарей через ==
	# (в Godot 4 это глубокое сравнение, оно прошло бы и на «restore не выполнен,
	# просто совпало содержимое»). Убрать любую строку восстановления — краснеет
	# соответствующий конъюнкт: guardrails-значения (cap 2 / cooldown 3000 из
	# фикстур) вернутся, sentinel-метка останется в журнале, фикстура каталога —
	# в catalog, а экономка — в движке. Конъюнкт размера очереди Net — страховка:
	# на удаление строк этого блока он не краснеет вообще (очередь от restore
	# не зависит), его задача — поймать ушедший за прогон Net-запрос из любого
	# другого места сюиты.
	Selftest.check("u20 monetization fixtures and engine state restored",
		Monetization._adapter == _u20_ad0 and Monetization._ads == _u20_ads0
		and Monetization.store_id == _u20_store0 and Monetization.billing_available == _u20_billing0
		and int(Monetization.ads_config.get("rewarded_daily_cap", -1)) == 5
		and float(Monetization.ads_config.get("rewarded_cooldown_sec", -1.0)) == 150.0
		and Monetization.catalog.size() == _u20_cat_size0
		and not Monetization.catalog.has("u20_gate_probe")
		and Monetization._pending_product == _u20_pproduct0
		and Monetization._pending_placement == _u20_pplace0
		and Monetization._verify_requests.size() == _u20_queue0.size()
		and Net._queue.size() == _u20_netq0
		and UserData.get_consent("ads_personalized") == _u20_consent0
		and UserData.is_product_owned("remove_ads") == _u20_own0
		and not UserData._granted.has(UserData._token_key("u20", "u20_hermetic_token", "u20_hermetic_sku"))
		and not _u20_read(UserData.PURCHASES_PATH).contains("u20_hermetic_sku")
		and not _u20_read(UserData.SAVE_PATH).contains("u20_sentinel_product")
		and g._engine.ether + g._engine.ether_overflow == _u20_eth0 + _u20_ovf0
		and g._engine.sage_gold == _u20_gold0
		and g._home._cosmetic_theme == _u20_theme0)


static func _u20_set_ads_state(day: String, count: int, last_rewarded: float, last_interstitial: float = 0.0) -> void:
	# Одна точка для фикстуры дневных лимитов: day="" дал бы 0 независимо от
	# счётчика, поэтому кап/кулдаун выставляются только парой «день + число».
	UserData.set_ads_state({
		"day": day,
		"rewarded_count": count,
		"last_rewarded_at": last_rewarded,
		"last_interstitial_at": last_interstitial,
	})


static func _u20_restore_ads_state(state: Dictionary) -> void:
	UserData.set_ads_state(state)


static func _u20_read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text


class U20FakeBilling extends RefCounted:
	# Копия наблюдаемой части контракта адаптеров для purchase(): фасад зовёт
	# только purchase(sku) и верит bool. Сигналов нет — начисление покрывается
	# отдельно (секция 8), а не через callback стора. ok=false выставляется ровно
	# в одном кейсе («reports the store answer unchanged») — мутация возврата
	# purchase() на оптимистичный true краснит его.
	var calls: Array = []
	var ok := true
	func purchase(store_sku: String) -> bool:
		calls.append("purchase:" + store_sku)
		return ok


class U20FakeAds extends RefCounted:
	# AdsAdapter-контракт для фасада ровно в том объёме, который дергается из
	# show_rewarded: is_available() и show_rewarded(placement). available — рычаг
	# гейта недоступности; вызовы пишутся, чтобы «отказ до адаптера» был наблюдаем,
	# а не выдуман. show_interstitial здесь не нужен: Monetization.show_interstitial
	# в этой сюите не вызывается (для него есть своя фикстура в
	# tests/suite_journal_misc.gd), а can_show_interstitial покрывается гейтом
	# remove_ads без обращения к адаптеру.
	var calls: Array = []
	var available := true
	func is_available() -> bool:
		return available
	func show_rewarded(placement_id: String) -> bool:
		calls.append(placement_id)
		return true


class U20Events extends RefCounted:
	# Коллектор платёжных и рекламных сигналов фасада в один поток: отсутствие
	# эмиссии наблюдаемо так же хорошо, как наличие. Метки считаются по префиксу с
	# индекса, поэтому лишнее событие красит кейс, а не сдвигает окна молча.
	var events: Array = []
	func _on_purchase_started(product_id: String) -> void:
		events.append("started:" + product_id)
	func _on_purchase_succeeded(product_id: String, _provider: String) -> void:
		events.append("ok:" + product_id)
	func _on_purchase_failed(product_id: String, code: String, _message: String) -> void:
		events.append("failed:" + code + ":" + product_id)
	func _on_rewarded_available(placement_id: String, available: bool) -> void:
		events.append("available:%s:%s" % [placement_id, str(available)])
	func _on_rewarded_started(placement_id: String) -> void:
		events.append("rstarted:" + placement_id)
	func count_since(start_index: int, prefix: String) -> int:
		var hits := 0
		for i in range(start_index, events.size()):
			if String(events[i]).begins_with(prefix):
				hits += 1
		return hits
