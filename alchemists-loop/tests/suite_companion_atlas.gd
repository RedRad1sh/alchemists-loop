extends RefCounted
class_name SuiteCompanionAtlas
# компаньон/профиль/редкость (оп B1).

static func run(g: Game) -> void:
	# дух-компаньон
	Selftest.check("companion built", g._spirit._companion != null)
	Selftest.check("companion bank", g._spirit._companion_line("idle", "") != "" and g._spirit._companion_line("success_new", "Пар") != "")
	var saved_met := g._spirit._companion_met
	g._spirit._companion_set_name("Тестер")
	Selftest.check("companion naming", g._spirit._player_name == "Тестер" and g._spirit._spirit_name != "" and g._spirit._companion_met)
	g._spirit._companion_met = saved_met
	Selftest.check("companion sprites loaded", g._spirit._companion != null and g._spirit._companion.has_sprites())
	Selftest.check("ago text", g._online._ago_text(5) == "только что" and g._online._ago_text(120).contains("мин")
		and g._online._ago_text(7200).contains("ч"))
	Selftest.check("challenge reward const", Game.CHALLENGE_REWARD == 50)

	# профиль: ник + аватар
	Selftest.check("avatar deterministic", Avatar.spec_for("Варда") == Avatar.spec_for("Варда"))
	var varda := Avatar.spec_for("Варда")
	Selftest.check("avatar spec shape", varda.has("bg") and varda.has("accent")
		and varda.has("sym") and varda.has("ring") and varda["bg"] != varda["accent"])
	Selftest.check("avatar cross-server", int(varda["sym"]) == 3
		and (varda["bg"] as Color) == Color("#7fcc6c")
		and (varda["accent"] as Color) == Color("#cc6ca6")
		and (varda["ring"] as bool) == false)
	var gelios := Avatar.spec_for("Гелиос")
	Selftest.check("avatar varies by nick", gelios["sym"] != varda["sym"]
		or gelios["bg"] != varda["bg"])
	Selftest.check("nick cleaned", g._hub._clean_player_nick("  Вар   да  ") == "Вар да"
		and g._hub._clean_player_nick("Варда!!!") == "Варда"
		and g._hub._clean_player_nick("Х") == ""
		and g._hub._clean_player_nick("Алхимик") == "Алхимик")
	Selftest.check("me avatar node", g._me_avatar != null and g._hub._profile_avatar != null)
	# ============ I-1 (T28): честный цикл смены ника ============
	# Раньше отказ сервера (400 «Ник уже занят») был невидим: _save_profile
	# печатал успех до ответа. Прогон герметичен: Net.base_url пуст (F1-ветка
	# _send_next не делает HTTP-попыток, очередь сливается offline-результатом
	# в несвязанный в selftest me_result), _on_net_me_result вызывается напрямую
	# (Net.me_result коннектится только при _net_enabled, main.gd).
	var t28_nick0 := g._online._net_nick
	var t28_status0 := g._engine.status_text
	var t28_base0 := Net.base_url
	var t28_line0 := g._hub._profile_nick.text
	var t28_prev0 := g._hub._profile_prev_nick
	var t28_dim0 := g._hub._profile_dim.visible
	var t28_popup0 := g._hub._profile_popup.visible
	Net.base_url = ""
	g._online._net_nick = "Т28Старый"
	g._hub._profile_nick.text = "Т28Новый"
	g._hub._save_profile()
	# Мутация «вернуть печать успеха в _save_profile» (или не перенести её в
	# ok-ветку) — краснеет здесь же, до всякого ответа сервера.
	Selftest.check("t28 nick save prints no premature success",
		not g._engine.status_text.contains("Имя сохранено")
		and g._online._net_nick == "Т28Новый")
	g._hub._on_net_me_result({"ok": false, "error": "HTTP 400",
		"message": "HTTP 400", "detail": "Ник уже занят"})
	# Мутация «удалить ветку отказа (оставить только if ok)» — краснеет здесь:
	# успех при этом возвращается в _save_profile (первый конъюнкт ловит и это,
	# и «не перенесён» вариант), ник не откатывается (второй конъюнкт), отказа
	# в статусе нет (третий).
	Selftest.check("t28 rejected nick rolls back",
		not g._engine.status_text.contains("Имя сохранено")
		and g._online._net_nick == "Т28Старый"
		and g._engine.status_text.contains("Имя не принято: Ник уже занят"))
	# Успех объявляется именно в ok-ветке и именно своей заявке: второй цикл
	# save→ответ. Мутация «убрать печать успеха в ok-ветке» краснит этот кейс.
	g._hub._profile_nick.text = "Т28Новый2"
	g._hub._save_profile()
	g._hub._on_net_me_result({"ok": true, "nick": "Т28Новый2"})
	Selftest.check("t28 success announced in ok branch",
		g._online._net_nick == "Т28Новый2"
		and g._engine.status_text.contains("Имя сохранено: Т28Новый2"))
	# restore: ничего из профиля/статуса/сети не оставляем изменённым.
	g._online._net_nick = t28_nick0
	g._engine.status_text = t28_status0
	Net.base_url = t28_base0
	g._hub._profile_nick.text = t28_line0
	g._hub._profile_prev_nick = t28_prev0
	g._hub._profile_dim.visible = t28_dim0
	g._hub._profile_popup.visible = t28_popup0

	# редкость веществ и «Атлас алхимика»
	Selftest.check("rarity base", g._engine._rarity_of("fire")["name"] == "первостихия"
		and int(g._engine._rarity_of("fire")["bounty"]) == 0)
	Selftest.check("rarity steam common", g._engine._rarity_of("steam")["name"] == "обычное"
		and int(g._engine._rarity_of("steam")["bounty"]) == 6)
	g.ITEMS["__st_epic"] = {"name": "Эпик", "color": "#888888"}
	g._online._server_layers["__st_epic"] = 5
	g.ITEMS["__st_leg"] = {"name": "Лег", "color": "#999999"}
	g._online._server_layers["__st_leg"] = 6
	Selftest.check("rarity epic by layer", g._engine._rarity_of("__st_epic")["name"] == "эпическое"
		and int(g._engine._rarity_of("__st_epic")["bounty"]) == 25)
	Selftest.check("rarity legendary by layer", g._engine._rarity_of("__st_leg")["name"] == "легендарное"
		and int(g._engine._rarity_of("__st_leg")["bounty"]) == 45)
	g.ITEMS.erase("__st_epic")
	g.ITEMS.erase("__st_leg")
	g._online._server_layers.erase("__st_epic")
	g._online._server_layers.erase("__st_leg")
	Selftest.check("milestone rewards", g._engine._milestone_reward(5) == 20 and g._engine._milestone_reward(10) == 25
		and g._engine._milestone_reward(55) == 120 and g._engine._milestone_reward(57) == 160)
	Selftest.check("milestone boosts", g._engine._milestone_boost(20) == "regen1" and g._engine._milestone_boost(40) == "cap50"
		and g._engine._milestone_boost(57) == "regen2" and g._engine._milestone_boost(5) == "")
	Selftest.check("next milestone", g._engine._next_milestone(3) == 5 and g._engine._next_milestone(56) == 57
		and g._engine._next_milestone(57) == 0)
	g._engine._milestones_done[20] = true
	Selftest.check("collection regen bonus", is_equal_approx(g._engine._collection_regen_bonus(), 0.5))
	g._engine._milestones_done[57] = true
	g._engine._milestones_done[40] = true
	Selftest.check("collection full bonuses", is_equal_approx(g._engine._collection_regen_bonus(), 1.25)
		and g._engine._collection_cap_bonus() == 50)
	g._engine._milestones_done.clear()
