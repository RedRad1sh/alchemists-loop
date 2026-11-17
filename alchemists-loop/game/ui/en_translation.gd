class_name EnTranslation
extends Translation

## Динамический переводчик RU -> EN для TranslationServer Godot 4.
## При локали "ru" возвращает пустой StringName, сохраняя исходные русские строки без изменений.

var _exact: Dictionary = {}
var _cache: Dictionary = {}
var _nl_patterns: Array = []
var _high_patterns: Array = []
var _low_patterns: Array = []
var _cyr_rx: RegEx = null
var _loaded := false

const SEPS := ["   ·   ", " · ", "  +  ", " + ", " → ", " — ", ": ", ", "]


func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_cyr_rx = RegEx.create_from_string("[А-Яа-яЁё]")
	var f := FileAccess.open("res://data/i18n_en.json", FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	if not (parsed is Dictionary):
		return
	var d: Dictionary = parsed
	if d.get("exact") is Dictionary:
		_exact = d["exact"]
	_nl_patterns = _compile_list(d.get("nl_patterns", []))
	_high_patterns = _compile_list(d.get("high_patterns", []))
	_low_patterns = _compile_list(d.get("low_patterns", []))


func _compile_list(raw: Variant) -> Array:
	var out: Array = []
	if not (raw is Array):
		return out
	for item in raw:
		if not (item is Dictionary):
			continue
		var pat := String(item.get("rx", ""))
		if pat.is_empty():
			continue
		var rx := RegEx.create_from_string(pat)
		if rx == null or not rx.is_valid():
			continue
		out.append({
			"rx": rx,
			"en": String(item.get("en", "")),
			"n": int(item.get("n", 0)),
		})
	return out


func register_dynamic(ru_text: String, en_text: String) -> void:
	if ru_text.is_empty() or en_text.is_empty():
		return
	ensure_loaded()
	_exact[ru_text] = en_text
	_cache[ru_text] = StringName(en_text)


func _get_message(src_message: StringName, _context: StringName = &"") -> StringName:
	if not TranslationServer.get_locale().begins_with("en"):
		return &""
	var s := String(src_message)
	if s.is_empty():
		return &""
	ensure_loaded()
	if _cache.has(s):
		return _cache[s]
	var tr_str := translate_string(s, 0)
	if tr_str == s:
		_cache[s] = &""
		return &""
	var sn := StringName(tr_str)
	_cache[s] = sn
	return sn


func translate_string(s: String, depth: int = 0) -> String:
	if s.is_empty() or depth > 5:
		return s
	ensure_loaded()
	if _exact.has(s):
		return String(_exact[s])
	if _cyr_rx != null and _cyr_rx.search(s) == null:
		return s

	var lstrip := s.lstrip(" ")
	var rstrip := lstrip.rstrip(" ")
	if rstrip != s and _exact.has(rstrip):
		var lead := s.substr(0, s.length() - lstrip.length())
		var trail := lstrip.substr(rstrip.length())
		return lead + String(_exact[rstrip]) + trail

	if s.contains("\n"):
		var nl_hit := _match_patterns(s, _nl_patterns, depth)
		if not nl_hit.is_empty():
			return nl_hit
		var lines := s.split("\n")
		var changed := false
		var out_lines := PackedStringArray()
		for line in lines:
			var tl := translate_string(line, depth + 1)
			if tl != line:
				changed = true
			out_lines.append(tl)
		if changed:
			return "\n".join(out_lines)

	var high_hit := _match_patterns(s, _high_patterns, depth)
	if not high_hit.is_empty():
		return high_hit

	for sep in SEPS:
		if s.contains(sep):
			var parts := s.split(sep)
			var changed := false
			var out_parts := PackedStringArray()
			for p in parts:
				var tp := translate_string(p, depth + 1)
				if tp != p:
					changed = true
				out_parts.append(tp)
			if changed:
				return sep.join(out_parts)

	var low_hit := _match_patterns(s, _low_patterns, depth)
	if not low_hit.is_empty():
		return low_hit

	return s


func _match_patterns(s: String, plist: Array, depth: int) -> String:
	for item in plist:
		var rx: RegEx = item["rx"]
		var m := rx.search(s)
		if m == null:
			continue
		var res := String(item["en"])
		var n := int(item["n"])
		for idx in range(n):
			var grp := m.get_string(idx + 1)
			var tr_grp := grp if grp == s else translate_string(grp, depth + 1)
			res = res.replace("{" + str(idx) + "}", tr_grp)
		return res
	return ""
