class_name SigilAssets
extends RefCounted

## Резолвер путей модуля. Позволяет жить в трёх местах:
##   1. отдельный проект        → res://shaders/..., res://data/...
##   2. res://sigil/            → модуль скопирован в игру как папка
##   3. res://game/sigil/       → принятая в игре раскладка
## Никаких правок кода при переносе не требуется.

const ROOTS := ["res://game/sigil/", "res://sigil/", "res://"]


static func find(rel_path: String) -> String:
	for root in ROOTS:
		var p: String = root.path_join(rel_path)
		if FileAccess.file_exists(p):
			return p
	# Для шейдеров file_exists не всегда срабатывает до импорта — проверяем ResourceLoader.
	for root in ROOTS:
		var p2: String = root.path_join(rel_path)
		if ResourceLoader.exists(p2):
			return p2
	return ""


static func shader_file(rel_path: String) -> Shader:
	var p := find(rel_path)
	if p == "":
		push_error("SigilAssets: не найден %s" % rel_path)
		return null
	var res := ResourceLoader.load(p)
	return res as Shader


static func json_file(rel_path: String) -> Variant:
	var p := find(rel_path)
	if p == "":
		return null
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return null
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed
