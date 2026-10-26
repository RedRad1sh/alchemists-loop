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
	var room_node: TextureRect = a.get_node_or_null("Room") if a != null else null
	var vignette_node: TextureRect = a.get_node_or_null("Vignette") if a != null else null
	Selftest.check("backdrop textures",
		UITheme.tex("backdrop_room") != null and UITheme.tex("vignette") != null
		and room_node != null and room_node.texture != null
		and vignette_node != null and vignette_node.texture != null)
	host.free()
	# На пустом хосте бэкдроп и так попал бы в индекс 0 — dummy-ребёнок до attach
	# делает проверку move_child(bd, 0) способной покраснеть.
	var host2 := Control.new()
	g.add_child(host2)
	var dummy := Control.new()
	host2.add_child(dummy)
	var bd2 := UIBackdrop.attach(host2)
	Selftest.check("backdrop first child over existing sibling",
		bd2 != null and host2.get_child(0) == bd2)
	host2.free()
	# Пины по исходнику шейдера: headless Godot не рендерит fragment(), поэтому
	# проверяем текст AMBIENT_CODE — при откате фикса каждый покраснеет.
	Selftest.check("ambient shader source keeps rect alpha",
		UIFx.AMBIENT_CODE.contains("vec4(col, COLOR.a)")
		and not UIFx.AMBIENT_CODE.contains("vec4(col, 1.0)"))
	Selftest.check("ambient shader source has no cold glint",
		not UIFx.AMBIENT_CODE.contains("0.10, 0.42, 0.42")
		and not UIFx.AMBIENT_CODE.contains("0.60, 0.95, 0.95"))
	Selftest.check("ambient shader source bakes no vignette",
		not UIFx.AMBIENT_CODE.contains("dot(v, v)"))
