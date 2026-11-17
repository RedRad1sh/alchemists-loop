extends RefCounted

const TYPES := {"male": ["cinder", "glass", "salt"], "female": ["herbalist", "night", "copper"]}
const LIMITS := {"face": 3, "expression": 4, "nose": 3, "accessory": 4, "outfit": 3, "palette": 6, "skin": 6, "hairColor": 6, "detail": 3}
const SKIN_COLORS := {
	"#dca478": 0, "#c68e65": 0, "#d0a17f": 0, "#a16d4f": 0, "#e0ad86": 0, "#d1a078": 0,
	"#b57b56": 1, "#ce956b": 1, "#a56c49": 1, "#bb855d": 1, "#ba805f": 1, "#79503b": 1,
	"#95654a": 1, "#c18b68": 1, "#dba681": 1, "#b88260": 1, "#c18e68": 1,
	"#8d573e": 2, "#c28b62": 1, "#c88b60": 1, "#b67b55": 1, "#9d6648": 2, "#be8761": 1,
}
static var _data: Dictionary = preload("res://game/ui/avatar_parts.gd").DATA

static func spec_for(seed: String, gender: String = "male") -> Dictionary:
	if not TYPES.has(gender):
		gender = "male"
	var state := [2166136261]
	var input := gender + ":" + seed.replace("е\u0308", "ё").replace("Е\u0308", "Ё").replace("и\u0306", "й").replace("И\u0306", "Й")
	for i in input.length():
		state[0] = _mul32(int(state[0]) ^ input.unicode_at(i), 16777619)
	var archetype: String = TYPES[gender][_pick(state, 3)]
	var prefix: String = {"night": "hood", "salt": "cap"}.get(archetype, archetype)
	return {
		"gender": gender, "archetype": archetype, "face": _pick(state, 3),
		"hairStyle": prefix + "-" + str(_pick(state, 3)), "expression": _pick(state, 4),
		"nose": _pick(state, 3), "accessory": _pick(state, 4), "outfit": _pick(state, 3),
		"palette": _pick(state, 6), "skin": _pick(state, 6), "hairColor": _pick(state, 6), "detail": _pick(state, 3),
	}

static func _mul32(a: int, b: int) -> int:
	return ((a & 65535) * b + (((a >> 16) * b & 65535) << 16)) & 0xffffffff

static func _pick(state: Array, n: int) -> int:
	state[0] = (int(state[0]) + 0x6D2B79F5) & 0xffffffff
	var h := int(state[0])
	var t := _mul32(h ^ (h >> 15), h | 1)
	t ^= (t + _mul32(t ^ (t >> 7), t | 61)) & 0xffffffff
	return int(float((t ^ (t >> 14)) & 0xffffffff) * n / 4294967296.0)

static func normalized(raw: Dictionary) -> Dictionary:
	var gender := String(raw.get("gender", "male"))
	if not TYPES.has(gender):
		gender = "male"
	var type := String(raw.get("archetype", TYPES[gender][0]))
	if type not in TYPES[gender]:
		type = TYPES[gender][0]
	var out := {"gender": gender, "archetype": type}
	for key in LIMITS:
		out[key] = clampi(int(raw.get(key, 0)), 0, int(LIMITS[key]) - 1)
	var prefix: String = {"night": "hood", "salt": "cap"}.get(type, type)
	out.hairStyle = prefix + "-" + str(clampi(String(raw.get("hairStyle", "0")).right(1).to_int(), 0, 2))
	return out

static func _replace(svg: String, pattern: String, value: String, all: bool = false) -> String:
	var re := RegEx.new()
	re.compile(pattern)
	return re.sub(svg, value, all)

static func _attr(svg: String, key: String, value: String) -> String:
	return _replace(svg, "\\b" + key + "=\"[^\"]*\"", key + "=\"" + value + "\"")

static func _group(part: String, content: String, transform: String = "") -> String:
	return '<g data-part="%s"%s>%s</g>' % [part, (' transform="%s"' % transform) if transform != "" else "", content]

static func _patch(a: Array, changes: Dictionary) -> void:
	for i in changes:
		a[int(i)] = changes[i]

static func render(raw: Dictionary) -> String:
	var s := normalized(raw)
	var type: String = s.archetype
	var l: Dictionary = _data.layouts[type]
	var p: Dictionary = _data.wardrobes[s.palette]
	var skin: Array = _data.skins[s.skin]
	var hair: Array = _data.greys[int(s.hairColor) % 4] if type in ["salt", "herbalist"] else _data.hairs[s.hairColor]
	var a: Array = _data.parts[type].duplicate()
	var color_re := RegEx.new()
	color_re.compile("#[0-9a-f]{6}")
	for i in a.size():
		var svg: String = a[i]
		var source := svg
		var matches := color_re.search_all(source)
		for j in range(matches.size() - 1, -1, -1):
			var m: RegExMatch = matches[j]
			var color := m.get_string()
			if SKIN_COLORS.has(color):
				svg = svg.substr(0, m.get_start()) + String(skin[SKIN_COLORS[color]]) + svg.substr(m.get_end())
		if i in l.hair and not (type == "night" and i != 5) and not (type == "salt" and i == 6):
			svg = _replace(svg, 'fill="#[0-9a-f]{6}"', 'fill="%s"' % hair[1 if 'fill="none"' in svg else 0])
			if 'fill="none"' in svg:
				svg = _replace(svg, 'stroke="#[0-9a-f]{6}"', 'stroke="%s"' % hair[1])
		if i in l.cloth:
			svg = _replace(svg, 'fill="#[0-9a-f]{6}"', 'fill="%s"' % (p.cloth if i == l.cloth[0] else p.lapel), true)
		if i in l.trim:
			svg = _replace(svg, 'fill="#[0-9a-f]{6}"', 'fill="%s"' % p.inner, true)
			svg = _replace(svg, 'stroke="#[0-9a-f]{6}"', 'stroke="%s"' % p.trim, true)
		a[i] = svg
	if type == "night":
		for i in [4, 5]:
			a[i] = _attr(a[i], "d", _data.night[str(i)])
		a[6] = _attr(a[6], "stroke-width", "2.6")
	var hair_index := String(s.hairStyle).right(1).to_int()
	for index in _data.hair[type][hair_index]:
		var original: String = _data.hair[type][hair_index][index]
		var re := RegEx.new()
		re.compile('d="([^"]*)"')
		a[int(index)] = _attr(a[int(index)], "d", re.search(original).get_string(1))
	_patch(a, _data.features[type]["%d:%d:%d" % [s.skin, s.nose, s.expression]])
	if type == "night":
		a[6] = _attr(a[6], "stroke-width", "2.6")
	var accessory: Dictionary = _data.accessories[type]["%d:%d:%d" % [s.skin, s.accessory, s.detail]]
	_patch(a, accessory.layers)
	var scale_x: float = [1.0, 0.95, 1.045][s.face]
	var transform := "translate(90 80) scale(%s 1) translate(-90 -80)" % str(scale_x)
	a[int(l.face)] = _group("face", a[int(l.face)])
	for i in l.hair:
		a[int(i)] = _group("hair", a[int(i)])
	for i in a.size():
		if (i >= l.neck and i <= l.end) or i in l.hair:
			a[i] = '<g transform="%s">%s</g>' % [transform, a[i]]
	a.insert(int(l.end) + 1, _group("accessory", accessory.extra, transform))
	var outfit := _group("outfit", _data.outfits["%d:%d" % [s.palette, s.outfit]])
	if type == "salt":
		a.insert(1, outfit)
	else:
		a.append(outfit)
	return '<svg xmlns="http://www.w3.org/2000/svg" width="180" height="180" viewBox="0 0 180 180" stroke="#382b25" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><defs><clipPath id="medallion"><circle cx="90" cy="88" r="78"/></clipPath></defs><circle cx="90" cy="88" r="82" fill="%s" stroke="#654c34" stroke-width="2"/><g clip-path="url(#medallion)">%s</g><circle cx="90" cy="88" r="79.5" fill="none" stroke="#c6a16a" stroke-width="2"/></svg>' % [p.bg, "".join(a)]
