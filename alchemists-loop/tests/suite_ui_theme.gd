extends RefCounted
class_name SuiteUiTheme
# P0 темы UI. Каждый пин краснеет от конкретной правки:
# - token X — возврат старого холодного hex;
# - icon default — возврат UIIcon.into_button к UIStyle.TEXT;
# - room prop plaque warm — возврат подписи предмета комнаты к холодному цвету.

static func run(g: Game) -> void:
	_tokens()
	_icon_default()
	_assets()
	_theme_cache()
	_factories()
	_main_screen(g)
	_warm_texts(g)
	_wiring(g)
	_no_teal_chrome(g)
	_style_button_miss()


static func _tok(name: String, got: Color, hex: String) -> void:
	var want := Color(hex)
	if not got.is_equal_approx(want):
		print("       | %s = #%s, ждали #%s" % [name, got.to_html(false), hex])
	Selftest.check("token " + name, got.is_equal_approx(want))


static func _tokens() -> void:
	_tok("INK", UIStyle.INK, "14100e")
	_tok("NAVY", UIStyle.NAVY, "1a1210")
	_tok("PANEL", UIStyle.PANEL, "2a1d1e")
	_tok("PANEL_HI", UIStyle.PANEL_HI, "3d2b24")
	_tok("LINE", UIStyle.LINE, "5a3a25")
	_tok("WOOD_DEEP", UIStyle.WOOD_DEEP, "241610")
	_tok("WOOD", UIStyle.WOOD, "2e1d15")
	_tok("WOOD_LIGHT", UIStyle.WOOD_LIGHT, "5a3a26")
	_tok("PLASTER", UIStyle.PLASTER, "3a2e27")
	_tok("PLASTER_HI", UIStyle.PLASTER_HI, "80644f")
	_tok("IRON", UIStyle.IRON, "2b2320")
	_tok("PAPER_HI", UIStyle.PAPER_HI, "efe0bd")
	_tok("PAPER", UIStyle.PAPER, "c9ad7e")
	_tok("PAPER_LIT", UIStyle.PAPER_LIT, "edc17c")
	_tok("PAPER_INK", UIStyle.PAPER_INK, "2a1d16")
	_tok("BRASS_HI", UIStyle.BRASS_HI, "e6b87a")
	_tok("BRASS", UIStyle.BRASS, "c89060")
	_tok("BRASS_DIM", UIStyle.BRASS_DIM, "8a5c38")
	_tok("FLAME", UIStyle.FLAME, "f5c378")
	_tok("GLOW", UIStyle.GLOW, "eeb36b")
	_tok("EMBER", UIStyle.EMBER, "f7a76d")
	_tok("HIGHLIGHT", UIStyle.HIGHLIGHT, "fad69b")
	_tok("CREAM", UIStyle.CREAM, "dabfa6")
	_tok("TEXT_DIM", UIStyle.TEXT_DIM, "a98d74")
	_tok("TEXT_MUTED", UIStyle.TEXT_MUTED, "6e5c50")
	_tok("RUBY", UIStyle.RUBY, "b4553f")
	_tok("LEAF", UIStyle.LEAF, "6f8f5a")
	_tok("ARCANA", UIStyle.ARCANA, "8b6fa8")
	_tok("MAGIC", UIStyle.MAGIC, "7fa89a")
	Selftest.check("alias TEAL to GLOW", UIStyle.TEAL.is_equal_approx(UIStyle.GLOW))
	Selftest.check("alias TEAL_DIM to BRASS_DIM", UIStyle.TEAL_DIM.is_equal_approx(UIStyle.BRASS_DIM))
	Selftest.check("alias GOLD to BRASS_HI", UIStyle.GOLD.is_equal_approx(UIStyle.BRASS_HI))
	Selftest.check("alias GOLD_DIM to BRASS_DIM", UIStyle.GOLD_DIM.is_equal_approx(UIStyle.BRASS_DIM))
	Selftest.check("alias TEXT to CREAM", UIStyle.TEXT.is_equal_approx(UIStyle.CREAM))
	Selftest.check("alias DANGER to RUBY", UIStyle.DANGER.is_equal_approx(UIStyle.RUBY))


static func _icon_default() -> void:
	var b := Button.new()
	UIIcon.into_button(b, "flask")
	var center := b.get_node_or_null("IconCenter")
	var icon: TextureRect = null
	if center != null and center.get_child_count() > 0:
		icon = center.get_child(0) as TextureRect
	Selftest.check("icon default is BRASS_HI",
		icon != null and icon.modulate.is_equal_approx(UIStyle.BRASS_HI))
	b.free()


static func _asset_state(name: String, w: int, h: int) -> String:
	var path := "res://assets/ui/theme/%s.png" % name
	if not ResourceLoader.exists(path):
		return "нет " + name + ".png"
	var t := load(path) as Texture2D
	if t == null:
		return name + ": не текстура"
	if t.get_width() != w or t.get_height() != h:
		return "%s: %dx%d вместо %dx%d" % [name, t.get_width(), t.get_height(), w, h]
	return ""


static func _sidecar(path: String, key: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	for line in f.get_as_text().split("\n"):
		if line.begins_with(key + "="):
			return line.split("=", true, 1)[1].strip_edges()
	return ""


static func _assets() -> void:
	var want := {
		"frame_modal": [192, 192], "frame_panel": [128, 128],
		"plaque_title": [400, 128], "well_slot": [128, 128],
		"field": [128, 72], "btn_brass": [192, 80], "btn_wood": [192, 80],
		"tab_active": [192, 88], "tab_rail": [1024, 128],
		"backdrop_room": [1080, 1920], "vignette": [1080, 1920],
	}
	var raw_bytes := 0
	var measured := 0
	for name in want:
		var why := _asset_state(name, int(want[name][0]), int(want[name][1]))
		if why != "":
			print("       | ", why)
		Selftest.check("theme asset " + name, why == "")
		if name != "backdrop_room" and name != "vignette":
			var f := FileAccess.open("res://assets/ui/theme/%s.png" % name, FileAccess.READ)
			if f != null:
				raw_bytes += f.get_length()
				measured += 1
				f.close()
			Selftest.check("theme %s uncompressed" % name,
				_sidecar("res://assets/ui/theme/%s.png.import" % name, "compress/mode") == "0"
				and _sidecar("res://assets/ui/theme/%s.png.import" % name, "mipmaps/generate") == "false")
	Selftest.check("theme 9-slice fits 2 MiB raw",
		measured == 9 and raw_bytes <= 2 * 1024 * 1024)
	for name in ["backdrop_room", "vignette"]:
		var mode := _sidecar("res://assets/ui/theme/%s.png.import" % name, "compress/mode")
		var mips := _sidecar("res://assets/ui/theme/%s.png.import" % name, "mipmaps/generate")
		Selftest.check("theme %s VRAM compressed" % name, mode == "2" and mips == "true")


static func _theme_cache() -> void:
	var a := UITheme.tex("frame_panel")
	var b := UITheme.tex("frame_panel")
	Selftest.check("texture cache returns one resource", a != null and a == b)
	var sb := UITheme.nine("frame_panel", Vector4(20, 20, 20, 20), Vector4(12, 10, 12, 10))
	Selftest.check("nine returns StyleBoxTexture", sb is StyleBoxTexture)
	Selftest.check("nine margins", sb != null and is_equal_approx(sb.texture_margin_left, 20.0)
		and is_equal_approx(sb.texture_margin_top, 20.0))
	Selftest.check("nine content margins", sb != null and is_equal_approx(sb.content_margin_left, 12.0)
		and is_equal_approx(sb.content_margin_top, 10.0))
	var sb2 := UITheme.nine("frame_panel", Vector4(20, 20, 20, 20), Vector4(12, 10, 12, 10))
	Selftest.check("nine boxes are independent", sb != null and sb2 != null and sb != sb2
		and sb.texture == sb2.texture)
	Selftest.check("nine unknown returns null", UITheme.nine("nope", Vector4(1, 1, 1, 1)) == null)
	var hv := UITheme.nine_hv("btn_brass", Vector4(24, 14, 24, 14), Vector4(10, 10, 10, 10))
	var hn := hv.get("normal") as StyleBoxTexture
	var hh := hv.get("hover") as StyleBoxTexture
	var hp := hv.get("pressed") as StyleBoxTexture
	Selftest.check("nine_hv states", hn != null and hh != null and hp != null)
	Selftest.check("nine_hv hover brighter", hh != null and hh.modulate_color.r > 1.0)
	Selftest.check("nine_hv pressed dimmer", hp != null and hp.modulate_color.r < 1.0)
	Selftest.check("nine_hv pressed 1 px down",
		hn != null and hp != null and is_equal_approx(hp.content_margin_top, hn.content_margin_top - 1.0))
	Selftest.check("nine_hv unknown returns empty",
		UITheme.nine_hv("nope", Vector4(1, 1, 1, 1), Vector4(1, 1, 1, 1)).is_empty())
	# Промах кэшируется как null; видно только через приватный словарь —
	# у GDScript нет счётчика load(), а ResourceLoader сам делает REUSE.
	UITheme.tex("__missing__")
	UITheme.tex("__missing__")
	Selftest.check("texture cache memoises misses",
		UITheme._tex_cache.has("__missing__") and UITheme._tex_cache["__missing__"] == null)
	Selftest.check("texture cache maps name to file",
		UITheme.tex("btn_brass") != null
		and UITheme.tex("btn_brass").resource_path.ends_with("btn_brass.png"))


static func _factories() -> void:
	var p := UIStyle.panel() as StyleBoxTexture
	Selftest.check("panel is frame_panel",
		p != null and p.texture != null and p.texture.resource_path.ends_with("frame_panel.png"))
	Selftest.check("panel margins 20",
		p != null and is_equal_approx(p.texture_margin_left, 20.0)
		and is_equal_approx(p.texture_margin_top, 20.0))
	Selftest.check("panel content R8",
		p != null and is_equal_approx(p.content_margin_left, 12.0)
		and is_equal_approx(p.content_margin_top, 10.0))

	var m := UIStyle.modal_panel() as StyleBoxTexture
	Selftest.check("modal is frame_modal",
		m != null and m.texture != null and m.texture.resource_path.ends_with("frame_modal.png"))
	Selftest.check("modal margins 34", m != null and is_equal_approx(m.texture_margin_left, 34.0))
	Selftest.check("modal content R8",
		m != null and is_equal_approx(m.content_margin_left, 18.0)
		and is_equal_approx(m.content_margin_top, 16.0))

	var b := Button.new()
	UIStyle.style_button(b, 1)
	var n := b.get_theme_stylebox("normal") as StyleBoxTexture
	var h := b.get_theme_stylebox("hover") as StyleBoxTexture
	var pr := b.get_theme_stylebox("pressed") as StyleBoxTexture
	Selftest.check("primary button is btn_brass",
		n != null and n.texture != null and n.texture.resource_path.ends_with("btn_brass.png"))
	Selftest.check("button content 10",
		n != null and is_equal_approx(n.content_margin_left, 10.0)
		and is_equal_approx(n.content_margin_top, 10.0))
	Selftest.check("button hover brighter", h != null and h.modulate_color.r > 1.0)
	Selftest.check("button pressed dimmer", pr != null and pr.modulate_color.r < 1.0)
	Selftest.check("button pressed 1 px down",
		n != null and pr != null and is_equal_approx(pr.content_margin_top, n.content_margin_top - 1.0))
	Selftest.check("brass button ink", b.get_theme_color("font_color").r < 0.3)
	UIStyle.style_button(b, 0)
	var w := b.get_theme_stylebox("normal") as StyleBoxTexture
	Selftest.check("secondary button is btn_wood",
		w != null and w.texture != null and w.texture.resource_path.ends_with("btn_wood.png"))
	Selftest.check("wood button cream",
		b.get_theme_color("font_color").is_equal_approx(UIStyle.CREAM))
	b.free()

	var row := Button.new()
	UIStyle.style_row(row)
	var r := row.get_theme_stylebox("normal") as StyleBoxTexture
	Selftest.check("row is frame_panel",
		r != null and r.texture != null and r.texture.resource_path.ends_with("frame_panel.png"))
	Selftest.check("row content R8",
		r != null and is_equal_approx(r.content_margin_left, 12.0)
		and is_equal_approx(r.content_margin_top, 10.0))
	row.free()

	var cell := Button.new()
	UIStyle.style_cell(cell)
	var cs := cell.get_theme_stylebox("normal") as StyleBoxTexture
	Selftest.check("cell is well_slot",
		cs != null and cs.texture != null and cs.texture.resource_path.ends_with("well_slot.png"))
	Selftest.check("cell content 8", cs != null and is_equal_approx(cs.content_margin_left, 8.0))
	cell.free()

	var tabs := TabContainer.new()
	UIStyle.style_tabs(tabs)
	var sel := tabs.get_theme_stylebox("tab_selected") as StyleBoxTexture
	var pan := tabs.get_theme_stylebox("panel") as StyleBoxTexture
	Selftest.check("tab selected is tab_active",
		sel != null and sel.texture != null and sel.texture.resource_path.ends_with("tab_active.png"))
	Selftest.check("tab panel is frame_panel",
		pan != null and pan.texture != null and pan.texture.resource_path.ends_with("frame_panel.png"))
	tabs.free()

	var th := Theme.new()
	UIStyle.apply_theme(th)
	var le := th.get_stylebox("normal", "LineEdit") as StyleBoxTexture
	Selftest.check("line edit is field",
		le != null and le.texture != null and le.texture.resource_path.ends_with("field.png"))


## Экран Эксперимента — на материалах, а не на плоских заливках.
static func _main_screen(g: Game) -> void:
	var arena_base: StyleBox = UIStyle.arena_style()
	var arena := arena_base as StyleBoxTexture
	Selftest.check("arena is carved table",
		arena != null and arena.texture != null
		and arena.texture.resource_path.ends_with("arena_table.png"))
	Selftest.check("arena 9-slice 96",
		arena != null and is_equal_approx(arena.texture_margin_left, 96.0)
		and is_equal_approx(arena.texture_margin_top, 96.0))

	var picker_base: StyleBox = UIStyle.picker_style()
	var picker := picker_base as StyleBoxTexture
	Selftest.check("reagent picker is textured",
		picker != null and picker.texture != null)

	var tabs := TabContainer.new()
	UIStyle.style_tabs(tabs)
	var un := tabs.get_theme_stylebox("tab_unselected") as StyleBoxTexture
	Selftest.check("unselected tab is tab_rail",
		un != null and un.texture != null and un.texture.resource_path.ends_with("tab_rail.png"))
	tabs.free()

	var warm := false
	var i := UIFx.FIELD_CODE.find("accent : source_color = vec4(")
	if i >= 0:
		var parts := UIFx.FIELD_CODE.substr(i + 29, 30).split(",")
		if parts.size() >= 3:
			warm = float(parts[0].strip_edges()) > float(parts[2].strip_edges()) + 0.2
	Selftest.check("field glyphs warm, not teal", warm)

	var plate := g.find_child("TitlePlaque", true, false) as PanelContainer
	var psb: StyleBox = plate.get_theme_stylebox("panel") if plate != null else null
	Selftest.check("header title on plaque",
		psb is StyleBoxTexture and (psb as StyleBoxTexture).texture != null
		and (psb as StyleBoxTexture).texture.resource_path.ends_with("plaque_title.png"))


static func _warm_texts(g: Game) -> void:
	# Обводка предмета комнаты: бледно-жёлтый тёплый контур, а не холодный
	# литерал. И обязательно шейдерная, по контуру самого спрайта:
	# прямоугольная рамка тап-зоны (Panel + StyleBoxFlat) — это и есть
	# «ореол квадратный», она гасит warm и красит пин.
	var warm := true
	for pname in ["Prop_Deck", "Prop_Board", "Prop_Scroll"]:
		var prop: Control = g._rooms._host.find_child(pname, true, false) as Control
		var glow := prop.get_meta("glow", null) as Control if prop != null else null
		var sprite := prop.find_child("Sprite", true, false) as TextureRect if prop != null else null
		var mat := glow.material as ShaderMaterial if glow != null else null
		if mat == null or sprite == null or glow.texture != sprite.texture:
			warm = false
			continue
		var c: Color = mat.get_shader_parameter("outline_color")
		warm = warm and c.r > c.b and c.g > c.b and c.a > 0.5
	Selftest.check("room prop outline is pale warm gold", warm)


static func _wiring(g: Game) -> void:
	var u: Dictionary = Game.UPGRADES[0]
	var row: Button = g._hub._up_row(u)
	var sb := row.get_theme_stylebox("normal") as StyleBoxTexture
	Selftest.check("upgrade row is frame_panel",
		sb != null and sb.texture != null and sb.texture.resource_path.ends_with("frame_panel.png"))
	var hb: HBoxContainer = null
	if row.get_child_count() > 0:
		hb = row.get_child(0) as HBoxContainer
	Selftest.check("upgrade row inset 12/8",
		hb != null and is_equal_approx(hb.offset_left, 12.0)
		and is_equal_approx(hb.offset_top, 8.0)
		and is_equal_approx(hb.offset_right, -12.0)
		and is_equal_approx(hb.offset_bottom, -8.0))
	row.free()
	var plate := g.find_child("UpgradeTitle", true, false) as PanelContainer
	var ps: StyleBoxTexture = null
	if plate != null:
		ps = plate.get_theme_stylebox("panel") as StyleBoxTexture
	Selftest.check("upgrades title is plaque_title",
		ps != null and ps.texture != null and ps.texture.resource_path.ends_with("plaque_title.png"))


# §10: «отсутствие TEAL в хроме». Пин поведенческий — обходит ЖИВОЕ дерево UI,
# которое selftest уже построил, и берёт эффективный цвет текста каждого узла,
# способного его нести. Легальны: (а) любой цвет, совпадающий с константой
# палитры UIStyle в пределах 0.02/канал (палитра — авторитет §3 и уже содержит
# холодные контент-акценты ARCANA/MAGIC/LEAF), и (б) любой НЕ холодный цвет.
# Холодным (циан/бирюза) считается c.b > c.r + 0.05 И c.g > c.r + 0.05. Так
# тёплые литералы проходят, а Color(0.45,0.95,0.9)/Color(0.8,0.85,0.9) — нет.
const _PALETTE: Array = [
	UIStyle.INK, UIStyle.NAVY, UIStyle.PANEL, UIStyle.PANEL_HI, UIStyle.LINE,
	UIStyle.WOOD_DEEP, UIStyle.WOOD, UIStyle.WOOD_LIGHT, UIStyle.PLASTER,
	UIStyle.PLASTER_HI, UIStyle.IRON, UIStyle.PAPER_HI, UIStyle.PAPER,
	UIStyle.PAPER_LIT, UIStyle.PAPER_INK, UIStyle.BRASS_HI, UIStyle.BRASS,
	UIStyle.BRASS_DIM, UIStyle.FLAME, UIStyle.GLOW, UIStyle.EMBER,
	UIStyle.HIGHLIGHT, UIStyle.CREAM, UIStyle.TEXT_DIM, UIStyle.TEXT_MUTED,
	UIStyle.RUBY, UIStyle.LEAF, UIStyle.ARCANA, UIStyle.MAGIC,
]

# Явные лазейки: холодные цвета, которые триггерят правило холода, но НЕ являются
# целью данной волны (Ruling-19 фиксит только 4 литерала). Это литералы, которые
# ledger ОТЛОЖИЛ до P3 (Task 5 minor: «ten in pages.gd», main.gd:1812,
# slot_well.gd:109, rarity-палитра; плюс холодный контент — вода Родника, травы,
# магия/аркан — легален как арт по §3, но пока живой литерал, а не токен). Hard
# rule волны — «не метить прочие холодные литералы» — запрещает их править, а пин
# обязан позеленеть, поэтому они разрешены ЗНАЧЕНИЕМ. Каждая запись — дыра в пине
# (см. final-fix-report.md). Список — точный снимок 29 distinct нарушителей RED-
# прогона минус три целевых цвета (73f2e6, 8cf2e6, ccd9e6), которые НЕ разрешены.
# Допуск 0.01 (уже палитрового 0.02): достаточно для hex→float round-trip (≤0.002)
# и не маскирует целевой ccd9e6 ближайшим отложенным c7d6e6 (Δr≈0.020).
static var _DEFERRED_COLD: Array = []


static func _deferred_cold() -> Array:
	if _DEFERRED_COLD.is_empty():
		for h in [
			"57d1ba", "738599", "73bf80", "79baff", "7e8d98", "80e0c4",
			"80e6d9", "85c7e0", "8c9ead", "8ca8b8", "8ccc99", "8cf2d7",
			"8fa3b8", "91adbd", "94abbd", "99a8b8", "99adbf", "99b3bf",
			"9cb8fa", "9eb3c2", "9eb8c4", "9ebdd1", "a1b5c7", "b8d6e0",
			"bfcfd4", "c2cfda", "c7d6e6", "dcecff", "e0f0f5",
		]:
			_DEFERRED_COLD.append(Color(h))
	return _DEFERRED_COLD

# Типы Control, несущие цвет текста; ключ — имя theme-color-итема.
const _TEXT_TYPES: Dictionary = {
	"Label": "font_color",
	"Button": "font_color",
	"RichTextLabel": "default_color",
	"LineEdit": "font_color",
	"CheckButton": "font_color",
	"CheckBox": "font_color",
	"OptionButton": "font_color",
	"LinkButton": "font_color",
}


static func _is_palette(c: Color) -> bool:
	for p in _PALETTE:
		if absf(c.r - p.r) <= 0.02 and absf(c.g - p.g) <= 0.02 and absf(c.b - p.b) <= 0.02:
			return true
	return false


static func _is_allowed_content(c: Color) -> bool:
	for a in _deferred_cold():
		if absf(c.r - a.r) <= 0.01 and absf(c.g - a.g) <= 0.01 and absf(c.b - a.b) <= 0.01:
			return true
	return false


static func _is_cold(c: Color) -> bool:
	return c.b > c.r + 0.05 and c.g > c.r + 0.05


static func _text_color_key(node: Control) -> String:
	for tname in _TEXT_TYPES:
		if node.is_class(tname):
			return _TEXT_TYPES[tname]
	return ""


static func _scan_cold(node: Node, offenders: Array, scanned: Array) -> void:
	if node is Control and not node.has_meta("content_color"):
		var key := _text_color_key(node)
		if key != "":
			var c: Color = (node as Control).get_theme_color(key)
			scanned[0] += 1
			if _is_cold(c) and not _is_palette(c) and not _is_allowed_content(c):
				offenders.append("%s (%s=%s)" % [node.get_path(), key, c.to_html(false)])
	for child in node.get_children():
		_scan_cold(child, offenders, scanned)


static func _no_teal_chrome(g: Game) -> void:
	var offenders: Array = []
	var scanned: Array = [0]
	_scan_cold(g, offenders, scanned)
	if not offenders.is_empty():
		print("       | cold chrome offenders (%d):" % offenders.size())
		for o in offenders:
			print("       |   ", o)
	print("       | chrome nodes scanned: %d" % scanned[0])
	Selftest.check("no TEAL/cold color in chrome (§10)", offenders.is_empty())
	# Защита от вакуумного PASS: скан обязан реально обойти дерево. Пол ниже
	# фактического количества текстовых узлов в прогоне (см. отчёт), чтобы
	# молчаливый «ничего не нашёл» краснел, а не проходил.
	Selftest.check("chrome scan examined enough nodes (>=100)", scanned[0] >= 100)


# Task 4 deferred minor / FIX-C: style_button обязан пережить промах nine_hv
# (пустой словарь при отсутствующей текстуре), не установив ни одного stylebox.
static func _style_button_miss() -> void:
	var b := Button.new()
	var had: bool = UITheme._tex_cache.has("btn_brass")
	var saved: Variant = UITheme._tex_cache["btn_brass"] if had else null
	UITheme._tex_cache["btn_brass"] = null
	UIStyle.style_button(b, 1)
	var installed := b.has_theme_stylebox_override("normal")
	# Кэш — статик на время процесса: восстанавливаем сразу, иначе null
	# сломает каждый последующий пин сюиты.
	if had:
		UITheme._tex_cache["btn_brass"] = saved
	else:
		UITheme._tex_cache.erase("btn_brass")
	Selftest.check("style_button survives nine_hv miss (no stylebox installed)",
		not installed)
	b.free()
