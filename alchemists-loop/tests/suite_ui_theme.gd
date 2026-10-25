extends RefCounted
class_name SuiteUiTheme
# P0 темы UI. Каждый пин краснеет от конкретной правки:
# - token X — возврат старого холодного hex;
# - icon default — возврат UIIcon.into_button к UIStyle.TEXT;
# - experiment field title warm — возврат подписи поля к холодному литералу.

static func run(g: Game) -> void:
	_tokens()
	_icon_default()
	_warm_texts(g)


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


static func _warm_texts(g: Game) -> void:
	var title := g.find_child("ExperimentFieldTitle", true, false) as Label
	Selftest.check("experiment field title warm",
		title != null and title.get_theme_color("font_color").is_equal_approx(UIStyle.BRASS))
