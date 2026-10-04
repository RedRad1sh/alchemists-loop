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
# - снятие _hide_network_pending из prune красит «badge hides after prune timeout».

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

	# ---- restore ----
	g._online._teardown_online_ux()
	g._online._pending_requests = st_pending
	g._online._ux_layer = st_ux
	g._online._toast_stack = st_toast
	g._online._network_badge = st_badge
