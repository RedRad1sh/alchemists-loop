extends RefCounted
class_name SuiteUiTheme
# P0 темы UI. Каждый пин краснеет от конкретной правки:
# - token X — возврат старого холодного hex;
# - icon default — возврат UIIcon.into_button к UIStyle.TEXT;
# - experiment field title warm — возврат подписи поля к холодному литералу.

static func run(g: Game) -> void:
	_tokens()
	_icon_default()
	_assets()
	_theme_cache()
	_factories()
	_warm_texts(g)
	_wiring(g)


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


static func _warm_texts(g: Game) -> void:
	var title := g.find_child("ExperimentFieldTitle", true, false) as Label
	Selftest.check("experiment field title warm",
		title != null and title.get_theme_color("font_color").is_equal_approx(UIStyle.BRASS))


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
