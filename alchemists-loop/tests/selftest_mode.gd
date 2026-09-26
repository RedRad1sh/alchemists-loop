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
