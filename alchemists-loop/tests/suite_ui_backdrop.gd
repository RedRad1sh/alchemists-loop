extends RefCounted
class_name SuiteUiBackdrop
# P0 фон: один слой на хост, порядок Room→Tint→Vignette, мышь сквозь,
# тинт темы меняет только цвет при постоянной альфе.

static func run(g: Game) -> void:
	var host := Control.new()
	g.add_child(host)
	var a := UIBackdrop.attach(host)
	var b := UIBackdrop.attach(host)
	Selftest.check("backdrop idempotent",
		a != null and a == b and host.get_child_count() == 1)
	Selftest.check("backdrop layer order",
		a != null and a.get_child_count() == 3
		and a.get_child(0).name == "Room"
		and a.get_child(1).name == "Tint"
		and a.get_child(2).name == "Vignette")
	var silent := a != null and a.mouse_filter == Control.MOUSE_FILTER_IGNORE
	if a != null:
		for c in a.get_children():
			silent = silent and (c as Control).mouse_filter == Control.MOUSE_FILTER_IGNORE
	Selftest.check("backdrop ignores mouse", silent)
	var tint := a.tint_rect() if a != null else null
	a.set_tint(Color("1a0e0e")) if a != null else null
	Selftest.check("backdrop tint keeps alpha",
		tint != null and is_equal_approx(tint.color.a, UIBackdrop.TINT_ALPHA)
		and is_equal_approx(tint.color.r, Color("1a0e0e").r))
	Selftest.check("backdrop textures",
		UITheme.tex("backdrop_room") != null and UITheme.tex("vignette") != null)
	host.free()
