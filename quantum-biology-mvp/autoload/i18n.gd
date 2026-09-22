extends Node
# Минимальная локализация: data/i18n.json, ключи {lang}. Определение языка по ОС.

var lang := "en"
var _data: Dictionary = {}

func _ready() -> void:
	var f := FileAccess.open("res://data/i18n.json", FileAccess.READ)
	if f:
		_data = JSON.parse_string(f.get_as_text())
	var loc: String = OS.get_locale().to_lower()
	if loc.begins_with("ru"):
		lang = "ru"
	else:
		lang = "en"

func t(key: String) -> String:
	var by_lang: Dictionary = _data.get(lang, {})
	if by_lang.has(key):
		return by_lang[key]
	var en: Dictionary = _data.get("en", {})
	return en.get(key, key)

func tf(key: String, args: Array) -> String:
	return t(key).format(args)

func gene_text(g: Dictionary) -> Dictionary:
	# Достаёт name/desc нужного языка из записи гена.
	var n: Dictionary = g.get("name", {})
	var d: Dictionary = g.get("desc", {})
	return {
		"name": n.get(lang, n.get("en", "?")),
		"desc": d.get(lang, d.get("en", "?"))
	}
