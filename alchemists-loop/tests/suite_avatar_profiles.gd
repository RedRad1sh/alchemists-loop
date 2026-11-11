extends RefCounted

static func run(g: Game) -> void:
	var hub = g._hub
	if hub.get("_profile_gender") == null:
		Selftest.check("profile requires explicit portrait gender", false)
		return
	Selftest.check("HUD portrait replaces rune at readable size", g._me_avatar.custom_minimum_size.x >= 36.0 * g.size.x / 360.0)
	var nick0: String = g._online._net_nick
	var gender0: String = g._online._avatar_gender
	var enabled0: bool = g._online._net_enabled
	var base0: String = Net.base_url
	var window_size0 := g.get_window().size
	var scale_size0 := g.get_window().content_scale_size
	g._online._net_enabled = false
	g._online._avatar_gender = ""
	hub._open_profile()
	Selftest.check("legacy profile has no inferred gender", hub._profile_gender == "" and hub._profile_gender_hint.visible)
	hub._profile_nick.text = "Портрет"
	hub._save_profile()
	Selftest.check("profile cannot confirm without gender", g._online._net_nick == nick0)
	hub._choose_profile_gender("female")
	Selftest.check("portrait preview does not commit draft", g._online._avatar_gender == "" and hub._profile_avatar._spec.gender == "female")
	hub._save_profile()
	Selftest.check("offline profile stores selected gender", g._online._avatar_gender == "female" and g._online._net_nick == "Портрет")
	g._saves._save_game()
	var saved: Dictionary = g._saves._read_save(g.SAVE_PATH)
	Selftest.check("save includes selected gender", saved.get("avatar_gender") == "female")
	g._online._avatar_gender = "male"
	g._saves._load_game()
	Selftest.check("save reload restores selected gender", g._online._avatar_gender == "female")
	hub._open_profile()
	hub._profile_nick.text = "Занято"
	hub._choose_profile_gender("male")
	g._online._net_enabled = true
	Net.base_url = ""
	hub._save_profile()
	hub._on_net_me_result({"ok": true, "nick": "Портрет", "avatar_gender": "female", "_profile_read": true})
	Selftest.check("startup profile read cannot complete pending update", hub._profile_pending and g._online._avatar_gender == "male")
	g._saves._save_game()
	var pending_save: Dictionary = g._saves._read_save(g.SAVE_PATH)
	Selftest.check("pending profile is not persisted before server approval", pending_save.get("net_nick") == "Портрет" and pending_save.get("avatar_gender") == "female")
	hub._on_net_me_result({"ok": false, "detail": "Ник уже занят"})
	Selftest.check("profile rejection restores name and gender", g._online._net_nick == "Портрет" and g._online._avatar_gender == "female")
	Selftest.check("profile rejection restores portrait", g._me_avatar._spec.gender == "female" and hub._profile_gender == "female")
	var met0: bool = g._spirit._companion_met
	g._spirit._companion_met = false
	g._spirit._companion_dlg_name.text = "Новичок"
	g._spirit._companion_on_name_ok()
	Selftest.check("onboarding name opens explicit gender preview before commitment", not g._spirit._companion_met and hub._profile_popup.visible and hub._profile_nick.text == "Новичок")
	g._online._net_enabled = false
	hub._choose_profile_gender("female")
	hub._save_profile()
	Selftest.check("onboarding finishes with selected female portrait", g._spirit._companion_met and g._online._avatar_gender == "female" and g._online._net_nick == "Новичок")
	g._spirit._companion_met = met0
	var spec := Avatar.spec_for("Гость", "female")
	g._online._remember_avatar("Гость", spec)
	var avatar := g._make_avatar("Гость", 40)
	Selftest.check("server portrait survives nickname-only UI helpers", avatar._spec == spec)
	Selftest.check("small portraits use minification filtering", avatar.texture_filter == CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS and avatar._texture.get_image().has_mipmaps())
	avatar.setup_spec({"kind": "spirit"}, 40)
	Selftest.check("spirit avatar does not use player generator", avatar._spec.get("kind") == "spirit" and not avatar._spec.has("archetype"))
	avatar.free()
	for viewport in [Vector2i(360, 800), Vector2i(540, 960)]:
		g.get_window().content_scale_size = viewport
		g.get_window().size = viewport
		hub._open_profile()
		await g.get_tree().process_frame
		await g.get_tree().process_frame
		var card: Control = hub._profile_nick.get_parent().get_parent()
		Selftest.check("portrait profile fits viewport " + str(viewport), g.get_viewport_rect().encloses(card.get_global_rect()))
	g._online._net_nick = nick0
	g._online._avatar_gender = gender0
	g._online._net_enabled = enabled0
	Net.base_url = base0
	g.get_window().content_scale_size = scale_size0
	g.get_window().size = window_size0
	hub._close_profile()
