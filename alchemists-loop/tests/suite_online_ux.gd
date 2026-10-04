extends RefCounted
class_name SuiteOnlineUx
# UX-слой Online (док «refactor online.gd.md» §1–4): тосты + индикатор сети.
#
# Тестовая среда: selftest-раннер проекта, сюита получает живой g: Game.
# CanvasLayer/панели строятся в дереве g — после сюиты всё снимается, чтобы не
# течь в следующие сюиты (canary чистого стека модалок в suite_journal_misc).
#
# Мутационные красные зоны:
# - снятие капа тостов (4) красит «toast adds panel and caps at 4»;
# - снятие игнора пустого текста красит «toast empty text ignored»;
# - снятие вызова _show_network_pending в _register_pending_pair красит «badge shows»;
# - снятие _hide_network_pending при опустевшем pending красит «badge hides»;
# - снятие _hide_network_pending из prune красит «badge hides after prune timeout»;
# - снятие net-гейта в _start_experiment красит «start experiment blocked offline»;
# - снятие pending-гейта красит «start experiment blocks double tap»;
# - замена _choose_event_type_weighted на рандом без гейтов красит «choose event respects
#   availability» (пустой пул → comet);
# - снятие гейта modal_ui/qte_exclusion красит «can spawn blocked by modal group»;
# - телеграф: прямой _activate-спавн без token красит «spawn telegraphs before active»,
#   «activate after telegraph», «stale token ignored».

static func run(g: Game) -> void:
	# Снимок затрагиваемого состояния (restore в конце, по образцу u11-блока).
	var st_pending: Dictionary = g._online._pending_requests.duplicate(true)
	var st_ux: CanvasLayer = g._online._ux_layer
	var st_toast: VBoxContainer = g._online._toast_stack
	var st_badge: PanelContainer = g._online._network_badge
	g._online._pending_requests.clear()
	# Гарантированно чистый UX-слой для детерминированного прогона.
	g._online._teardown_online_ux()

	# ---- 1: сборка UX-слоя ----
	g._online._build_online_ux()
	Selftest.check("ux layer builds once",
		g._online._ux_layer != null and g._online._toast_stack != null
		and g._online._network_badge != null)
	var layer_first: CanvasLayer = g._online._ux_layer
	g._online._build_online_ux()
	Selftest.check("ux layer builds once", g._online._ux_layer == layer_first)

	# ---- 2: тосты ----
	g._online._toast("", 0)  # NoticeKind.INFO
	Selftest.check("toast empty text ignored", g._online._toast_stack.get_child_count() == 0)
	for i in range(6):
		g._online._toast("Тост %d" % i, 0)
	Selftest.check("toast adds panel and caps at 4",
		g._online._toast_stack.get_child_count() == 4)
	# mouse_filter стека не перехватывает клики игры.
	Selftest.check("toast stack ignores mouse",
		g._online._toast_stack.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	# Полный teardown+rebuild: стек уходит вместе со слоем, счётчик — с нуля.
	g._online._teardown_online_ux()
	g._online._build_online_ux()
	Selftest.check("toast stack rebuilt after teardown", g._online._toast_stack != null
		and g._online._toast_stack.get_child_count() == 0)

	# ---- 3: бейдж сетевого ожидания ----
	Selftest.check("badge hidden with empty pending", not g._online._network_badge.visible)
	g._online._ux_layer.visible = true  # CanvasLayer жив в дереве; badge — его ребёнок
	Selftest.check("register shows badge", g._online._register_pending_pair("fire", "air", false)
		and g._online._network_badge.visible)
	Selftest.check("register second pair refused while pending",
		not g._online._register_pending_pair("earth", "water", false))
	var uxe_key: String = g._pair_key("fire", "air")
	var entry: Dictionary = g._online._take_pending_pair(uxe_key)
	Selftest.check("take hides badge", not entry.is_empty()
		and not g._online._network_badge.visible)
	# Бейдж появляется и от experiment-записи.
	Selftest.check("register experiment shows badge",
		g._online._register_pending_pair("fire", "air", true)
		and g._online._network_badge.visible)
	# ---- 4: prune по таймауту гасит бейдж ----
	var stale: Dictionary = g._online._pending_requests[uxe_key]
	stale["at"] = Time.get_ticks_msec() - g._online.PENDING_TTL_MSEC - 1000
	# Prune отложит эксперимент-ресурсы только при совпадении с _experiment_pending_pair;
	# здесь пары нет — просто запись сотрётся.
	g._online._prune_pending_requests()
	Selftest.check("badge hides after prune timeout",
		g._online._pending_requests.is_empty() and not g._online._network_badge.visible)

	# ---- 5: запуск эксперимента (док §5) — только гейты, без реальной сети ----
	var st_inv: Dictionary = g._engine.inventory.duplicate(true)
	var st_ether: int = g._engine.ether
	var st_over: int = g._engine.ether_overflow
	var st_attempts: int = g._engine.attempts
	var st_pending_pair: Array = g._engine._experiment_pending_pair.duplicate()
	var st_net_on: bool = g._online._net_enabled
	var st_status: String = g._engine.status_text
	g._engine._experiment_pending_pair.clear()
	# оба реагента в запасе, эфир с запасом
	g._engine.inventory["water"] = int(g._engine.inventory.get("water", 0)) + 2
	g._engine.inventory["air"] = int(g._engine.inventory.get("air", 0)) + 2
	g._engine.ether = maxi(g._engine.ether, 40)
	var ether_expect: int = g._engine.ether + g._engine.ether_overflow
	# офлайн: гейт связи срабатывает первым — реагенты и эфир целы
	var st_avail: bool = Net.is_available()
	Net._available = false
	g._online._net_enabled = true
	Selftest.check("start experiment blocked offline", not g._online._start_experiment("water", "air")
		and int(g._engine.inventory.get("water", 0)) == st_inv.get("water", 0) + 2
		and g._engine.ether + g._engine.ether_overflow == ether_expect)
	# двойной тап: слот pending занят — второй запрос не уходит
	Net._available = true
	g._online._pending_requests[g._pair_key("fire", "water")] = {
		"a": "fire", "b": "water", "experiment": false, "at": Time.get_ticks_msec()}
	Selftest.check("start experiment blocks double tap", not g._online._start_experiment("water", "air")
		and g._engine._experiment_pending_pair.size() == 0
		and int(g._engine.inventory.get("air", 0)) == st_inv.get("air", 0) + 2)
	Net._available = st_avail
	g._online._pending_requests.clear()
	g._engine._experiment_pending_pair = st_pending_pair

	# ---- 6: телеграф QTE (док §8–12) ----
	var st_event_active: bool = g._online._event_active
	var st_event_type: String = g._online._event_type
	var st_event_left: float = g._online._event_left
	var st_event_clock: float = g._online._event_clock
	var st_token: int = g._online._event_spawn_token
	var st_tele: bool = g._online._event_telegraphing
	var st_qte_visible: bool = g._online._event_qte.visible
	# сборка QTE уже случилась в main; CanvasLayer-обёртка — по §6
	Selftest.check("event qte lives in canvas layer",
		g._online._event_canvas != null and g._online._event_canvas.layer == 15
		and g._online._event_qte.get_parent() == g._online._event_canvas)
	g._online._event_clock = Game.EVENT_INTERVAL - 0.01
	g._online._event_tick(0.02)  # clock переваливает интервал → spawn → телеграф
	Selftest.check("spawn telegraphs before active",
		g._online._event_telegraphing and not g._online._event_active
		and g._online._event_btn.disabled and g._online._event_qte.visible)
	g._online._activate_event(g._online._event_spawn_token)
	Selftest.check("activate after telegraph",
		g._online._event_active and not g._online._event_telegraphing)
	# завершение события вручную: тап по кнопке = награда; тип фиксирован, чтобы
	# тест не зависел от randi (insight открыл бы discovery popup поверх).
	g._online._event_type = "comet"
	g._online._on_event_tap()
	Selftest.check("event tap closes active", not g._online._event_active)
	# устаревший токен игнорируется: телеграф не стартует заново
	g._online._event_active = false
	g._online._event_telegraphing = true
	var stale_token: int = st_token  # заведомо старый
	g._online._activate_event(stale_token)
	Selftest.check("stale token ignored",
		g._online._event_active == false and g._online._event_telegraphing == true)
	g._online._event_telegraphing = st_tele
	g._online._event_qte.visible = st_qte_visible
	g._online._event_active = st_event_active
	g._online._event_type = st_event_type
	g._online._event_left = st_event_left
	g._online._event_clock = st_event_clock
	g._online._event_spawn_token = st_token

	# ---- 7: гейты спавна и выбор события (док §8–9) ----
	var st_popup_vis: bool = g._popup.visible
	g._popup.visible = true
	Selftest.check("can spawn blocked by modal group", not g._online._can_spawn_event())
	g._popup.visible = st_popup_vis
	# пустой пул: инвентарь только из базовых, все рецепты известны → только comet.
	# Инвентарь к этому моменту содержит чужие st_* элементы других сюит — дар был бы
	# доступен; сужаем до базовых и восстанавливаем полный снимок после кейса.
	var st_known: Dictionary = g._engine.known_recipes.duplicate(true)
	var st_rejected: Dictionary = g._engine._rejected_pairs.duplicate(true)
	var st_inv7: Dictionary = g._engine.inventory.duplicate(true)
	for k in g._engine.inventory.keys():
		if not Game.BASE_IDS.has(String(k)):
			g._engine.inventory.erase(String(k))
	for r in g.RECIPES:
		g._engine.known_recipes[g._pair_key(String(r["a"]), String(r["b"]))] = true
	Selftest.check("choose event respects availability",
		g._online._choose_event_type_weighted() == "comet")
	g._engine.known_recipes = st_known
	g._engine._rejected_pairs = st_rejected
	g._engine.inventory = st_inv7

	# ---- 8: позиционирование QTE (док §7) ----
	# Пузырь не пересекает BrewBar (группа qte_exclusion): серия попыток — все мимо.
	var bar_rect: Rect2 = (g._brew_bar as Control).get_global_rect()
	var hits := 0
	for i in 30:
		g._online._place_event_qte()
		var card_rect := Rect2(g._online._event_card.position,
			g._online._event_card.size)
		if card_rect.grow(10.0).intersects(bar_rect):
			hits += 1
	Selftest.check("qte placement avoids exclusions", hits == 0)

	# ---- 9: фолбэки наград (док §13) ----
	var st_ether13: int = g._engine.ether
	var st_over13: int = g._engine.ether_overflow
	var st_status13: String = g._engine.status_text
	var st_type13: String = g._online._event_type
	var st_active13: bool = g._online._event_active
	var st_inv13: Dictionary = g._engine.inventory.duplicate(true)
	# инвентарь без «даримого» (только базовые), пул рецептов пуст → gift даёт эфир
	var inv13_keys: Array = g._engine.inventory.keys()
	for k in inv13_keys:
		if not Game.BASE_IDS.has(String(k)):
			g._engine.inventory.erase(String(k))
	var st_known13: Dictionary = g._engine.known_recipes.duplicate(true)
	for r in g.RECIPES:
		g._engine.known_recipes[g._pair_key(String(r["a"]), String(r["b"]))] = true
	var ether_pool: int = g._engine.ether + g._engine.ether_overflow
	g._online._event_type = "gift"
	g._online._event_active = true
	g._online._event_left = 5.0
	g._online._on_event_tap()
	Selftest.check("gift without items grants ether fallback",
		not g._online._event_active
		and g._engine.ether + g._engine.ether_overflow == ether_pool + 15)
	g._online._event_type = "insight"
	g._online._event_active = true
	g._online._event_left = 5.0
	g._online._on_event_tap()
	Selftest.check("insight without recipes grants ether fallback",
		not g._online._event_active
		and g._engine.ether + g._engine.ether_overflow == ether_pool + 35)
	g._engine.inventory = st_inv13
	g._engine.known_recipes = st_known13
	g._engine.ether = st_ether13
	g._engine.ether_overflow = st_over13
	g._engine.status_text = st_status13
	g._online._event_type = st_type13
	g._online._event_active = st_active13

	# ---- 10: вибрация — вызовы безопасны на десктопе (док §14) ----
	g._online._haptic_light()
	g._online._haptic_medium()
	g._online._haptic_success()
	g._online._haptic_error()
	Selftest.check("haptics no-op on desktop", true)

	# ---- restore ----
	g._engine.inventory = st_inv
	g._engine.ether = st_ether
	g._engine.ether_overflow = st_over
	g._engine.attempts = st_attempts
	g._engine.status_text = st_status
	g._online._net_enabled = st_net_on
	g._online._teardown_online_ux()
	g._online._pending_requests = st_pending
	g._online._ux_layer = st_ux
	g._online._toast_stack = st_toast
	g._online._network_badge = st_badge
