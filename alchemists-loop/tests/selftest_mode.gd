extends RefCounted
class_name SelftestMode
# U23 (T27): единый источник флага --selftest. Автозагрузкам он должен быть
# известен раньше Main._ready, который его разбирает: иначе UserData/App в своих _ready
# пишут настоящие файлы установки при неперведённых путях, а _ready автозагрузки
# отрабатывает до сцены. На App флаг повесить нельзя (UserData — первый
# автозагрузчик), на Game-сцену и на Selftest.run — тоже (они ещё позже).
# Поэтому это static-хелпер без зависимостей: он сам не знает ни про кого,
# а ссылаются на него отовсюду.

static func enabled() -> bool:
	# PackedStringArray читаем has() напрямую: to_array() у него нет.
	return OS.get_cmdline_user_args().has("--selftest")

# Герметичный прогон: самотест или сцена-харнесс из res://tests/ (съёмка кадров).
# Харнесс запускается без --selftest — тот выключил бы Juice, который он снимает, —
# но файлы установки, аналитика и сеть ему так же запрещены.
static func isolated() -> bool:
	return enabled() or is_harness_args(OS.get_cmdline_args())

static func is_harness_args(args: PackedStringArray) -> bool:
	for a in args:
		if a.begins_with("res://tests/") and a.ends_with(".tscn"):
			return true
	return false
