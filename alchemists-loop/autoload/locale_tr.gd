extends Node

## Автозагрузка локализации (RU / EN).
## Регистрирует динамический переводчик в TranslationServer и синхронизирует выбранный язык с UserData.

signal locale_changed(new_locale: String)

const EnTranslationScript := preload("res://game/ui/en_translation.gd")

var lang: String = "ru"
var _cli_lang: String = ""
var _en_tr: Translation = null
var _ru_tr: Translation = null


func _ready() -> void:
	_setup_translations()
	var saved := "ru"
	if UserData != null and UserData.has_method("get_locale"):
		saved = UserData.get_locale()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--lang="):
			_cli_lang = normalize_locale(arg.substr(7))
			saved = _cli_lang
	apply_locale(saved, false)


func _setup_translations() -> void:
	if _ru_tr == null:
		_ru_tr = Translation.new()
		_ru_tr.locale = "ru"
		TranslationServer.add_translation(_ru_tr)
	if _en_tr == null:
		var tr_inst: Translation = EnTranslationScript.new()
		tr_inst.locale = "en"
		if tr_inst.has_method("ensure_loaded"):
			tr_inst.call("ensure_loaded")
		_en_tr = tr_inst
		TranslationServer.add_translation(_en_tr)


func _exit_tree() -> void:
	if _en_tr != null:
		TranslationServer.remove_translation(_en_tr)
		_en_tr = null
	if _ru_tr != null:
		TranslationServer.remove_translation(_ru_tr)
		_ru_tr = null


func normalize_locale(loc: String) -> String:
	var clean := loc.strip_edges().to_lower()
	if clean.begins_with("en"):
		return "en"
	return "ru"


func get_locale_code() -> String:
	return lang


func is_english() -> bool:
	return lang == "en"


func set_lang(loc: String) -> String:
	return apply_locale(loc, true)


func apply_locale(loc: String, persist: bool = true) -> String:
	_setup_translations()
	var norm := normalize_locale(loc)
	lang = norm
	if persist and UserData != null and UserData.has_method("set_locale"):
		UserData.set_locale(norm)
	TranslationServer.set_locale(norm)
	locale_changed.emit(norm)
	return norm


func toggle_locale() -> String:
	var next_loc := "en" if lang == "ru" else "ru"
	return apply_locale(next_loc, true)


func register_dynamic(ru_text: String, en_text: String) -> void:
	_setup_translations()
	if _en_tr != null and _en_tr.has_method("register_dynamic"):
		_en_tr.call("register_dynamic", ru_text, en_text)


func t(text: String) -> String:
	if text.is_empty() or not is_english():
		return text
	_setup_translations()
	if _en_tr != null and _en_tr.has_method("translate_string"):
		return String(_en_tr.call("translate_string", text, 0))
	return tr(text)
