extends RefCounted
class_name SuiteLabModes
# лаборатория/режимы/прокачка/поиск (оп B1).

const NetBase := preload("res://autoload/net.gd")

class TargetSyncSink extends RefCounted:
	var nonces: Array[String] = []
	func catch(_result: Dictionary, sync_nonce: String = "") -> void:
		nonces.append(sync_nonce)

static func _has_target_sync_nonce(g: Game) -> bool:
	for property in g._online.get_property_list():
		if String(property["name"]) == "_target_sync_nonce":
			return true
	return false

static func _deliver_target_sync(g: Game, result: Dictionary, sync_nonce: String) -> void:
	var arg_count := 0
	for method in g._online.get_method_list():
		if String(method["name"]) == "_on_experiment_target_sync_result":
			arg_count = (method["args"] as Array).size()
			break
	if arg_count >= 2:
		g._online.call("_on_experiment_target_sync_result", result, sync_nonce)
	else:
		g._online.call("_on_experiment_target_sync_result", result)

static func _personal_target_fixture() -> Dictionary:
	return {
		"id": "pt-ui-target", "kind": "llm", "slug": "pt-ui-hidden", "name": "Скрытая цель",
		"hint": "Соедини привычное с неожиданным.", "status": "active", "cycle_week": "2026-W48",
		"attempts": 3, "successful_steps": 2, "spent_ether": 34, "generation": 4,
		"next_eligible_week": ""}

static func _target_label(g: Game, node_name: String) -> Label:
	if g._pages._experiment_field == null:
		return null
	return g._pages._experiment_field.find_child(node_name, true, false) as Label

static func _render_personal_target(g: Game) -> void:
	if g._online.has_method("_render_personal_target_state"):
		g._online.call("_render_personal_target_state")

static func _set_target_view_state(g: Game, state: String) -> void:
	for property in g._online.get_property_list():
		if String(property["name"]) == "_target_view_state":
			g._online.set("_target_view_state", state)
			return

static func run(g: Game) -> void:
	# закреплённая панель «ВАРИТЬ»
	Selftest.check("brew bar overlaid", g._brew_bar != null and g._brew_bar.get_parent() == g)
	Selftest.check("brew bar bottom anchor", g._brew_bar.anchor_bottom == 1.0 and g._brew_bar.offset_bottom < 0.0)
	Selftest.check("brew btn inside bar", g._engine._brew_btn.get_parent() != g._tabs_ref and g._brew_bar.is_ancestor_of(g._engine._brew_btn))
	Selftest.check("primary experiment tab", g._tabs_ref.get_tab_title(0) == "Эксперимент")
	Selftest.check("experiment location built", g._pages._experiment_field != null and g._pages._experiment_cauldron != null and g._pages._experiment_drawer != null)
	# Комната — главный экран: выбор реагентов спрятан и открывается по тапу.
	if g._pages._experiment_drawer.visible:
		g._pages._toggle_experiment_drawer()
	Selftest.check("experiment drawer hidden until asked", not g._pages._experiment_drawer.visible
		and g._pages._experiment_cauldron_btn.visible
		and g._pages._experiment_cauldron_art.visible)
	g._pages._toggle_experiment_drawer()
	Selftest.check("experiment drawer opens on demand", g._pages._experiment_drawer.visible)
	g._pages._toggle_experiment_drawer()
	Selftest.check("experiment drawer closes back to the field", not g._pages._experiment_drawer.visible)

	var pt_catalog_inv: Dictionary = g._engine.inventory.duplicate(true)
	var pt_catalog_defs: Dictionary = g._engine.known_recipe_defs.duplicate(true)
	var pt_catalog_server: Dictionary = g._online._server_elements.duplicate(true)
	g._engine.inventory["fire"] = 0
	g._engine.inventory["u_unknown"] = 3
	g._engine.inventory.erase("steam")
	g._engine.inventory.erase("stone")
	g._engine.known_recipe_defs[g._pair_key("fire", "water")] = {"a": "fire", "b": "water", "out": "steam"}
	g._online._server_elements["stone"] = g.ITEMS["stone"]
	var pt_known_ids: Array = []
	if g._pages.has_method("_experiment_known_ids"):
		pt_known_ids = g._pages.call("_experiment_known_ids")
	var pt_catalog_ids: Array = g._pages._experiment_reagent_ids(false)
	Selftest.check("experiment picker includes known zero-stock item", pt_catalog_ids.has("fire"))
	Selftest.check("experiment picker hides unknown item", not pt_catalog_ids.has("u_unknown"))
	Selftest.check("experiment catalog includes zero-stock recipe output", pt_catalog_ids.has("steam") and pt_known_ids.has("steam"))
	Selftest.check("experiment catalog includes server element without inventory", pt_catalog_ids.has("stone") and pt_known_ids.has("stone"))
	g._engine.inventory = pt_catalog_inv
	g._engine.known_recipe_defs = pt_catalog_defs
	g._online._server_elements = pt_catalog_server

	var pt_zero_inv: Dictionary = g._engine.inventory.duplicate(true)
	g._engine.inventory["fire"] = 0
	var pt_zero_tokens_before := g._pages._experiment_tokens.size()
	g._pages._experiment_spawn_token("fire")
	var pt_zero_token: ElementOrb = null
	if g._pages._experiment_tokens.size() > pt_zero_tokens_before:
		pt_zero_token = g._pages._experiment_tokens.back()
	Selftest.check("experiment zero-stock known item creates virtual reagent",
		is_instance_valid(pt_zero_token) and pt_zero_token.element_id == "fire")
	if is_instance_valid(pt_zero_token):
		g._pages._experiment_add_token_to_cauldron(pt_zero_token)
		Selftest.check("experiment zero-stock reagent enters cauldron without inventory debit",
			g._pages._experiment_cauldron_items == ["fire"] and int(g._engine.inventory.get("fire", 0)) == 0)
	if is_instance_valid(pt_zero_token) and g._pages._experiment_tokens.has(pt_zero_token):
		g._pages._experiment_tokens.erase(pt_zero_token)
		pt_zero_token.queue_free()
	g._pages._experiment_clear_cauldron()
	g._engine.inventory = pt_zero_inv

	var pt_ui_target_old: Dictionary = g._online._target_state.duplicate(true)
	var pt_ui_raw := _personal_target_fixture()
	pt_ui_raw["source_pair"] = ["fire", "water"]
	pt_ui_raw["seed"] = 123
	pt_ui_raw["prompt"] = "SECRET_PROMPT"
	pt_ui_raw["evaluator_explanation"] = "SECRET_EXPLANATION"
	g._online._on_experiment_target_sync_result({"ok": true, "target": pt_ui_raw})
	_render_personal_target(g)
	var pt_ui_title := _target_label(g, "TargetName")
	var pt_ui_hint := _target_label(g, "TargetHint")
	var pt_ui_stats := _target_label(g, "TargetStats")
	var pt_ui_active := _target_label(g, "TargetState")
	Selftest.check("target card renders active state",
		pt_ui_active != null and pt_ui_active.text.to_lower().contains("актив"))
	Selftest.check("target card draws above room props",
		g._rooms != null and g._rooms._host != null and g._tabs_ref.z_index > g._rooms._host.z_index)
	Selftest.check("target snapshot does not expose source pair", not g._online._target_state.has("source_pair"))
	Selftest.check("target card renders name hint and progress",
		pt_ui_title != null and pt_ui_title.text == "Скрытая цель"
		and pt_ui_hint != null and pt_ui_hint.text == "Соедини привычное с неожиданным."
		and pt_ui_stats != null and pt_ui_stats.text.contains("2") and pt_ui_stats.text.contains("34")
		and not (pt_ui_title.text + pt_ui_hint.text + pt_ui_stats.text + pt_ui_active.text).contains("SECRET")
		and not (pt_ui_title.text + pt_ui_hint.text + pt_ui_stats.text + pt_ui_active.text).contains("pt-ui-hidden"))
	for pt_ui_status in ["completed", "waiting_next_slot"]:
		var pt_ui_snapshot := _personal_target_fixture()
		pt_ui_snapshot["status"] = pt_ui_status
		if pt_ui_status == "completed":
			pt_ui_snapshot["next_eligible_week"] = "2026-W49"
		g._online._on_experiment_target_sync_result({"ok": true, "target": pt_ui_snapshot})
		_render_personal_target(g)
		var pt_ui_state := _target_label(g, "TargetState")
		var pt_ui_state_text := pt_ui_state.text.to_lower() if pt_ui_state != null else ""
		var pt_ui_expected := "выполн" if pt_ui_status == "completed" else "следующ"
		Selftest.check("target card renders %s state" % pt_ui_status, pt_ui_state_text.contains(pt_ui_expected))
	for pt_ui_view in ["syncing", "offline", "target_unavailable"]:
		_set_target_view_state(g, pt_ui_view)
		_render_personal_target(g)
		var pt_ui_transient := _target_label(g, "TargetState")
		var pt_ui_transient_text := pt_ui_transient.text.to_lower() if pt_ui_transient != null else ""
		var pt_ui_expected_transient: String = {"syncing": "синхрон", "offline": "нет связи", "target_unavailable": "недоступ"}[pt_ui_view]
		Selftest.check("target card renders %s state" % pt_ui_view, pt_ui_transient_text.contains(String(pt_ui_expected_transient)))
	_set_target_view_state(g, "")
	g._online._target_state = pt_ui_target_old
	_render_personal_target(g)

	var pt_compact_screen_was_open := g._pages._on_cauldron_screen()
	g._screens.close()
	g._pages._fit_experiment_overlay()
	var pt_compact_ribbon := g._pages._experiment_field.find_child("PersonalTargetCard", true, false) as Control
	Selftest.check("personal target ribbon stays compact in room",
		pt_compact_ribbon != null and pt_compact_ribbon.size.y <= 48.0)
	g._pages._open_cauldron_screen()
	g._pages._fit_experiment_overlay()
	var pt_compact_details := g._pages._experiment_field.find_child("TargetDetails", true, false) as Control
	var pt_compact_toggle := g._pages._experiment_field.find_child("TargetDetailsButton", true, false) as Button
	Selftest.check("personal target ribbon keeps drag field clear on cauldron screen",
		pt_compact_ribbon != null and pt_compact_ribbon.size.y <= 48.0
		and pt_compact_details != null and not pt_compact_details.visible
		and pt_compact_toggle != null)
	if pt_compact_toggle != null and pt_compact_details != null:
		pt_compact_toggle.pressed.emit()
		var pt_compact_opened := pt_compact_details.visible and pt_compact_ribbon.size.y <= 48.0
		var pt_clear := g._pages._experiment_clear_button
		var pt_line := g._pages._experiment_recipe_line
		Selftest.check("opened target details never sit on top of live cauldron controls",
			pt_compact_opened and pt_clear != null and not pt_clear.visible
			and pt_line != null and not pt_line.visible)
		var pt_field_w := g._pages._experiment_field.size.x
		Selftest.check("personal target ribbon is centred with equal side margins",
			pt_compact_ribbon != null and is_equal_approx(pt_compact_ribbon.position.x,
			pt_field_w - pt_compact_ribbon.position.x - pt_compact_ribbon.size.x))
		var pt_paper := pt_compact_ribbon.find_child("TargetPaper", true, false) as NinePatchRect
		var pt_note := pt_compact_details.get_theme_stylebox("panel") as StyleBoxTexture
		Selftest.check("target paper textures are cropped to their opaque sheet",
			pt_paper != null and pt_paper.region_rect.has_area()
			and pt_note != null and pt_note.region_rect.has_area())
		g._pages._on_experiment_source_drag_started(null, Vector2.ZERO, "fire")
		Selftest.check("personal target details collapse when reagent drag starts",
			pt_compact_opened and not pt_compact_details.visible)
		Selftest.check("collapsed target details give cauldron controls back",
			pt_clear != null and pt_clear.visible)
	else:
		Selftest.check("personal target details collapse when reagent drag starts", false)
	var pt_state_label := g._pages._experiment_field.find_child("TargetState", true, false) as Label
	var pt_state_font := pt_state_label.get_theme_font("font") if pt_state_label != null else null
	var pt_state_need := pt_state_font.get_string_size(pt_state_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
		pt_state_label.get_theme_font_size("font_size")).x if pt_state_font != null else 0.0
	Selftest.check("personal target status text is fully visible in the ribbon",
		pt_state_label != null and pt_state_label.text != "" and pt_state_label.size.x + 0.5 >= pt_state_need)
	Selftest.check("personal target ribbon stays below screens and popups",
		pt_compact_ribbon != null and pt_compact_ribbon.z_as_relative
		and pt_compact_ribbon.z_index < ScreenRouter.SCREEN_Z)
	if pt_compact_details != null:
		g._pages._collapse_personal_target_details()
		var pt_touch := InputEventScreenTouch.new()
		pt_touch.pressed = true
		var pt_click := InputEventMouseButton.new()
		pt_click.pressed = true
		pt_click.button_index = MOUSE_BUTTON_LEFT
		g._pages._on_personal_target_input(pt_touch)
		g._pages._on_personal_target_input(pt_click)
		Selftest.check("one tap with mouse emulation opens target details once", pt_compact_details.visible)
		var pt_icon := pt_compact_ribbon.find_child("IconCenter", true, false) as Control
		Selftest.check("target details chevron rotates around its own centre",
			pt_icon != null and pt_icon.pivot_offset.is_equal_approx(pt_icon.size * 0.5))
		g._pages._collapse_personal_target_details()
	g._screens.close()
	if pt_compact_screen_was_open:
		g._pages._open_cauldron_screen()
	_render_personal_target(g)

	# Net must carry the caller's sync nonce from the queued request to its result.
	var pt_nonce_net := NetBase.new()
	var pt_nonce_sink := TargetSyncSink.new()
	pt_nonce_net.experiment_target_sync_result.connect(pt_nonce_sink.catch)
	pt_nonce_net._inflight = {"kind": "sentinel"}
	var pt_nonce_arg_count := 0
	for pt_nonce_method in pt_nonce_net.get_method_list():
		if String(pt_nonce_method["name"]) == "experiment_target_sync":
			pt_nonce_arg_count = (pt_nonce_method["args"] as Array).size()
			break
	if pt_nonce_arg_count >= 3:
		pt_nonce_net.call("experiment_target_sync", "pt-device", "Pt", "pt-current-nonce")
	else:
		pt_nonce_net.call("experiment_target_sync", "pt-device", "Pt")
	var pt_nonce_req: Dictionary = pt_nonce_net._queue.pop_front() if not pt_nonce_net._queue.is_empty() else {}
	var pt_nonce_body: Dictionary = pt_nonce_req.get("body", {}) as Dictionary
	Selftest.check("net target sync request carries caller nonce",
		pt_nonce_body.size() == 3 and String(pt_nonce_body.get("sync_nonce", "")) == "pt-current-nonce")
	pt_nonce_net._dispatch(pt_nonce_req, {"ok": true})
	Selftest.check("net target sync result carries request nonce",
		pt_nonce_sink.nonces == ["pt-current-nonce"])
	pt_nonce_net.free()

	# A late response must not replace a newer snapshot, end the live sync, or save.
	var pt_sync_target_old: Dictionary = g._online._target_state.duplicate(true)
	var pt_sync_view_old := g._online._target_view_state
	var pt_sync_inflight_old := g._online._target_sync_in_flight
	var pt_sync_receipt_old: Dictionary = g._online._target_attempt_receipt.duplicate(true)
	var pt_sync_frozen_old := g._saves._save_frozen
	var pt_sync_has_nonce := _has_target_sync_nonce(g)
	var pt_sync_nonce_old := String(g._online.get("_target_sync_nonce")) if pt_sync_has_nonce else ""
	g._saves._save_frozen = false
	g._online._target_attempt_receipt = {}
	g._online._target_sync_in_flight = false
	var pt_newer := _personal_target_fixture()
	pt_newer["id"] = "pt-newer"
	g._online._on_experiment_target_sync_result({"ok": true, "target": pt_newer})
	var pt_newer_state: Dictionary = g._online._target_state.duplicate(true)
	var pt_newer_save := FileAccess.get_file_as_string(g.SAVE_PATH)
	var pt_older := _personal_target_fixture()
	pt_older["id"] = "pt-older"
	g._online._target_sync_in_flight = true
	g._online._target_view_state = "syncing"
	if pt_sync_has_nonce:
		g._online.set("_target_sync_nonce", "pt-live-nonce")
	_deliver_target_sync(g, {"ok": true, "target": pt_older}, "pt-stale-nonce")
	Selftest.check("stale target sync cannot overwrite newer target or save",
		g._online._target_state == pt_newer_state and g._online._target_sync_in_flight
		and g._online._target_view_state == "syncing"
		and FileAccess.get_file_as_string(g.SAVE_PATH) == pt_newer_save)
	_deliver_target_sync(g, {"ok": true, "target": pt_older}, "")
	Selftest.check("target sync without nonce is rejected while in flight",
		g._online._target_state == pt_newer_state and g._online._target_sync_in_flight
		and g._online._target_view_state == "syncing"
		and FileAccess.get_file_as_string(g.SAVE_PATH) == pt_newer_save)

	var pt_latest := _personal_target_fixture()
	pt_latest["id"] = "pt-latest"
	_deliver_target_sync(g, {"ok": true, "target": pt_latest}, "pt-live-nonce")
	var pt_latest_state: Dictionary = g._online._target_state.duplicate(true)
	var pt_latest_save := FileAccess.get_file_as_string(g.SAVE_PATH)
	_deliver_target_sync(g, {"ok": true, "target": pt_older}, "pt-stale-nonce")
	Selftest.check("late stale target sync cannot overwrite completed sync or save",
		g._online._target_state == pt_latest_state and not g._online._target_sync_in_flight
		and FileAccess.get_file_as_string(g.SAVE_PATH) == pt_latest_save)
	_deliver_target_sync(g, {"ok": true, "target": pt_older}, "pt-live-nonce")
	Selftest.check("completed target sync duplicate cannot overwrite or save",
		g._online._target_state == pt_latest_state and not g._online._target_sync_in_flight
		and FileAccess.get_file_as_string(g.SAVE_PATH) == pt_latest_save)

	for pt_sync_failure in ["offline", "auth_required"]:
		g._online._target_state = pt_newer_state
		g._online._target_sync_in_flight = true
		g._online._target_view_state = "syncing"
		var pt_failure_nonce: String = "pt-" + String(pt_sync_failure)
		if pt_sync_has_nonce:
			g._online.set("_target_sync_nonce", pt_failure_nonce)
		var pt_failure_result := {
			"offline": pt_sync_failure == "offline",
			"auth_required": pt_sync_failure == "auth_required"}
		_deliver_target_sync(g, pt_failure_result, pt_failure_nonce)
		var pt_failure_nonce_cleared := not pt_sync_has_nonce or String(g._online.get("_target_sync_nonce")) == ""
		Selftest.check("target sync %s result clears correlation" % pt_sync_failure,
			not g._online._target_sync_in_flight and pt_failure_nonce_cleared
			and g._online._target_state == pt_newer_state and g._online._target_view_state == "offline")

	# Legacy direct calls remain valid when idle and clear any unused correlation.
	if pt_sync_has_nonce:
		g._online.set("_target_sync_nonce", "pt-unused-nonce")
	var pt_idle := _personal_target_fixture()
	g._online._on_experiment_target_sync_result({"ok": true, "target": pt_idle})
	var pt_idle_nonce_cleared := not pt_sync_has_nonce or String(g._online.get("_target_sync_nonce")) == ""
	Selftest.check("legacy target sync result remains valid when idle",
		String(g._online._target_state.get("id", "")) == "pt-ui-target"
		and not g._online._target_sync_in_flight and pt_idle_nonce_cleared)

	# The endpoint may report waiting at top level while its nested row is completed.
	var pt_waiting := _personal_target_fixture()
	pt_waiting["status"] = "completed"
	pt_waiting["completed"] = true
	pt_waiting["next_eligible_week"] = "2026-W49"
	g._online._on_experiment_target_sync_result({"ok": true, "status": "waiting_next_slot", "target": pt_waiting})
	var pt_waiting_save: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(g.SAVE_PATH)) as Dictionary
	var pt_waiting_saved: Dictionary = pt_waiting_save.get("personal_experiment_target", {}) as Dictionary
	Selftest.check("top-level waiting_next_slot overrides nested completed target",
		String(g._online._target_state.get("status", "")) == "waiting_next_slot"
		and not bool(g._online._target_state.get("completed", true))
		and String(g._online._target_state.get("next_eligible_week", "")) == "2026-W49"
		and String(pt_waiting_saved.get("status", "")) == "waiting_next_slot"
		and not bool(pt_waiting_saved.get("completed", true))
		and String(pt_waiting_saved.get("next_eligible_week", "")) == "2026-W49")
	_render_personal_target(g)
	var pt_waiting_label := _target_label(g, "TargetState")
	Selftest.check("target card renders authoritative waiting state",
		pt_waiting_label != null and pt_waiting_label.text.to_lower().contains("следующ"))
	var pt_completed := _personal_target_fixture()
	pt_completed["status"] = "waiting_next_slot"
	pt_completed["completed"] = false
	g._online._on_experiment_target_sync_result({"ok": true, "status": "completed", "target": pt_completed})
	Selftest.check("top-level completed overrides nested waiting target",
		String(g._online._target_state.get("status", "")) == "completed"
		and bool(g._online._target_state.get("completed", false)))

	g._online._target_state = pt_sync_target_old
	g._online._target_view_state = pt_sync_view_old
	g._online._target_sync_in_flight = pt_sync_inflight_old
	g._online._target_attempt_receipt = pt_sync_receipt_old
	if pt_sync_has_nonce:
		g._online.set("_target_sync_nonce", pt_sync_nonce_old)
	g._saves._save_frozen = pt_sync_frozen_old
	if not g._saves._save_frozen:
		g._saves._save_game()
	_render_personal_target(g)

	g._engine.inventory["fire"] = maxi(int(g._engine.inventory.get("fire", 0)), 1)
	var exp_tokens_before := g._pages._experiment_tokens.size()
	g._pages._experiment_spawn_token("fire")
	Selftest.check("experiment tap creates field reagent", g._pages._experiment_tokens.size() == exp_tokens_before + 1)
	var exp_token: ElementOrb = g._pages._experiment_tokens.back()
	g._pages._experiment_add_token_to_cauldron(exp_token)
	Selftest.check("field reagent enters cauldron", g._pages._experiment_cauldron_items.size() == 1 and g._pages._experiment_cauldron_items[0] == "fire")
	g._pages._experiment_clear_cauldron()
	Selftest.check("experiment cauldron can be cleared", g._pages._experiment_cauldron_items.is_empty())
	g._screens.close()
	g._tabs_ref.current_tab = Game.TAB_WORLD
	g._update_brew_bar_visibility()
	Selftest.check("bar hides on other tab", not g._brew_bar.visible)
	g._tabs_ref.current_tab = Game.TAB_LAB
	g._update_brew_bar_visibility()
	Selftest.check("bar visible on lab", g._brew_bar.visible)
	var pad_ok := false
	var lab_scroll := g._tabs_ref.get_child(Game.TAB_LAB) as ScrollContainer
	if lab_scroll != null:
		for ch in lab_scroll.get_children():
			var v: VBoxContainer = null
			if ch is VBoxContainer:
				v = ch
			elif ch is MarginContainer:
				for gc in ch.get_children():
					if gc is VBoxContainer:
						v = gc
			if v == null:
				continue
			for sub in v.get_children():
				if sub is Control and (sub as Control).custom_minimum_size.y >= 100.0 \
						and sub.get_child_count() == 0:
					pad_ok = true
	Selftest.check("lab pad for bar", pad_ok)

	# прокачка: улучшения появляются вместе с веществами
	var steam_keep := int(g._engine.inventory.get("steam", 0))
	g._engine.inventory.erase("steam")
	g._engine.inventory.erase("clay")
	g._engine.inventory.erase("glass")
	g._engine.inventory.erase("mushroom")
	Selftest.check("upgrades locked while items closed", not g._engine._up_unlocked("ether_regen")
		and not g._engine._up_unlocked("ether_cap") and not g._engine._up_unlocked("brew_speed")
		and not g._engine._up_unlocked("source_yield") and not g._engine._up_unlocked("auto_gift"))
	g._engine.ether = 10
	Selftest.check("locked upgrade rejected", not g._engine._buy_upgrade("ether_regen") and g._engine._up_lvl("ether_regen") == 0)
	g._engine.inventory["steam"] = maxi(steam_keep, 1)
	Selftest.check("upgrade unlocked by steam", g._engine._up_unlocked("ether_regen") and not g._engine._up_unlocked("brew_speed"))
	g._engine.ether = 1000
	Selftest.check("upgrade buy", g._engine._buy_upgrade("ether_regen") and g._engine._up_lvl("ether_regen") == 1 and g._engine.ether == 850)
	Selftest.check("regen faster", g._engine._ether_rate() >= Game.BASE_ETHER_REGEN + 0.35)
	g._engine.inventory["clay"] = maxi(int(g._engine.inventory.get("clay", 0)), 1)
	g._engine.inventory["glass"] = maxi(int(g._engine.inventory.get("glass", 0)), 1)
	g._engine.inventory["mushroom"] = maxi(int(g._engine.inventory.get("mushroom", 0)), 1)
	g._engine.inventory["fish"] = maxi(int(g._engine.inventory.get("fish", 0)), 1)
	Selftest.check("upgrades unlocked later", g._engine._up_unlocked("ether_cap") and g._engine._up_unlocked("brew_speed")
		and g._engine._up_unlocked("source_yield") and g._engine._up_unlocked("auto_gift"))
	var _cap_pre := g._engine._max_ether()
	Selftest.check("upgrade cap buy", g._engine._buy_upgrade("ether_cap") and g._engine._max_ether() == _cap_pre + 50)
	# дефект: цена не должна расти быстрее, чем кап эфира (иначе ступень недостижима)
	var _cap_max := Game.MAX_ETHER + 50 * 8 + 50
	var _affordable := true
	for u in Game.UPGRADES:
		for l in int(u["max"]):
			if int(float(u["base"]) * pow(float(u["growth"]), l)) > _cap_max:
				_affordable = false
	Selftest.check("upgrades affordable within cap", _affordable)
	var bs_saved := g.BREW_SECONDS
	g.BREW_SECONDS = 2.0
	Selftest.check("brew speed buy", g._engine._buy_upgrade("brew_speed") and g._engine._brew_time() < g.BREW_SECONDS)
	g.BREW_SECONDS = bs_saved
	g._engine.ether = 5000
	Selftest.check("upgrade mid level", g._engine._buy_upgrade("ether_cap") and g._engine._up_lvl("ether_cap") == 2)
	# Оптовая покупка ×1/×10/×100: до максимума и пока хватает эфира.
	if g._engine.has_method("_up_cost_at"):
		var eng := g._engine
		var cap_keep := eng._up_lvl("ether_cap")
		var eth_keep := eng.ether
		var over_keep := eng.ether_overflow
		var cap_max := 0
		for u in Game.UPGRADES:
			if String(u["id"]) == "ether_cap":
				cap_max = int(u["max"])
		eng.upgrades["ether_cap"] = 0
		eng.ether_overflow = 0
		eng.ether = 100000000
		var want := 0
		for k in cap_max:
			want += eng._up_cost_at("ether_cap", k)
		Selftest.check("bulk buy stops at max", eng._buy_upgrade("ether_cap", 100)
				and eng._up_lvl("ether_cap") == cap_max and eng.ether == 100000000 - want)
		Selftest.check("bulk buy at max refused", not eng._buy_upgrade("ether_cap", 10)
				and eng._up_lvl("ether_cap") == cap_max)
		eng.upgrades["ether_cap"] = 0
		eng.ether = eng._up_cost_at("ether_cap", 0) + eng._up_cost_at("ether_cap", 1) + 5
		eng.ether_overflow = 0
		Selftest.check("bulk buy limited by ether", eng._buy_upgrade("ether_cap", 10)
				and eng._up_lvl("ether_cap") == 2 and eng.ether == 5)
		Selftest.check("upgrade has no quantity selector", g.find_child("UpQtyRow", true, false) == null)
		eng.upgrades["ether_cap"] = cap_keep
		eng.ether = eth_keep
		eng.ether_overflow = over_keep
		eng._refresh()
	else:
		Selftest.check("bulk buy stops at max", false)
	for i in 3:
		g._engine._buy_upgrade("source_yield")
	Selftest.check("source yield maxed", g._engine._up_lvl("source_yield") == 3)
	var water_have := int(g._engine.inventory.get("water", 0))
	g._engine._source_taps = 0
	for i in 3:
		g._engine._collect("water")
	Selftest.check("source yield calm taps", int(g._engine.inventory.get("water", 0)) == water_have + 3)
	g._engine._collect("water")
	Selftest.check("source yield waits until fifth tap", int(g._engine.inventory.get("water", 0)) == water_have + 4)
	g._engine._collect("water")
	Selftest.check("source yield bonus", int(g._engine.inventory.get("water", 0)) == water_have + 6)

	# Подсказка Светика — единственный платный канал: направление без reveal результата.
	g._spirit._companion_unlocked = true
	g._engine.inventory["fire"] = maxi(int(g._engine.inventory.get("fire", 0)), 1)
	g._engine.inventory["water"] = maxi(int(g._engine.inventory.get("water", 0)), 1)
	g._engine.known_recipes.erase(g._pair_key("fire", "water"))
	var known_before := g._engine.known_recipes.size()
	g._engine.ether = 200
	var hint_paid := g._pages._hint()
	Selftest.check("paid hint points without reveal", hint_paid and g._engine.ether == 200 - Game.HINT_COST and g._engine.known_recipes.size() == known_before
		and g._engine.status_text.find("Светик") >= 0)

	# поиск по названию (лаборатория)
	Selftest.check("search matches all", g._online._matches_search("fire") and g._online._matches_search("house"))
	g._engine._search_box.text = "дом"
	Selftest.check("search finds house", g._online._matches_search("house") and not g._online._matches_search("fire"))
	Selftest.check("search finds house recipe", g._online._find_recipe("wall", "wood").get("out", "") == "house")
	g._engine._search_box.text = ""

	# судьбоносные режимы
	g._engine.inventory["plant"] = maxi(int(g._engine.inventory.get("plant", 0)), 1)
	Selftest.check("modes unlocked by items", g._engine._mode_unlocked("spring"))
	g._engine.inventory["person"] = maxi(int(g._engine.inventory.get("person", 0)), 1)
	g._engine._refresh()
	Selftest.check("mode bench unlocked", g._engine._mode_unlocked("bench"))
	# resonance = _ach_world_first >= 1; счётчик персистится в сейве, поэтому
	# изолируем его: сейв прошлого прогона мог принести >0 (иначе кейс краснел
	# бы от чужого прогресса, а не от мутации кода).
	var awf_snapshot: int = g._progress_ui._ach_world_first
	g._progress_ui._ach_world_first = 0
	Selftest.check("mode resonance locked w/o discovery", not g._engine._mode_unlocked("resonance"))
	g._progress_ui._ach_world_first = maxi(awf_snapshot, 1)
	g._progress_ui._ach_world_first = 1
	# Late systems are deliberately staged by collection depth; make the fixture
	# represent a late-mid-game laboratory before checking lazy page creation.
	var mode_ids: Array = g.ITEMS.keys()
	for mode_id in mode_ids:
		if g._engine.inventory.size() >= 30:
			break
		g._engine.inventory[String(mode_id)] = maxi(int(g._engine.inventory.get(String(mode_id), 0)), 1)
	g._engine._refresh()
	Selftest.check("mode resonance unlocked by discovery", g._engine._mode_unlocked("resonance"))
	# доска v2 Task 5: вкладки «Круг»/«Неделя» сняты — MODES сократился с 9 до 7
	Selftest.check("mode pages built", g._pages._mode_pages.size() == 7 and g._pages._mode_chips.size() == 7)
	Selftest.check("mode tabs compat", g._pages._mode_tabs.size() == 7)
	# Все механики — на экранах комнаты; фишек в «Ещё» не остаётся.
	var any_chip := false
	for k in g._pages._mode_chips:
		any_chip = any_chip or (g._pages._mode_chips[k] as Button).visible
	Selftest.check("more tab shows no mode chips", not any_chip)
	Selftest.check("compact tools omit experiment", not (g._pages._mode_chips["experiment"] as Button).visible
		and not (g._pages._mode_chips["spring"] as Button).visible
		and not (g._pages._mode_chips["resonance"] as Button).visible
		and not (g._pages._mode_chips["atlas"] as Button).visible)
	Selftest.check("experiment primary remains available", g._engine._mode_unlocked("experiment") and g._pages._experiment_field != null)
	g._engine._experiment_day = Time.get_date_string_from_system()
	g._engine._experiment_count = 0
	g._engine._experiment_last_at = 0.0
	g._engine.inventory["fire"] = maxi(int(g._engine.inventory.get("fire", 0)), 2)
	g._engine.ether = maxi(g._engine.ether, 200)
	g._engine._rejected_pairs.erase(g._pair_key("fire", "fire"))
	var experiment_status := g._engine._experiment_status("fire", "fire")
	Selftest.check("experiment frontier status", bool(experiment_status.get("ok", false)))

	var pt_launch_target: Dictionary = g._online._target_state.duplicate(true)
	var pt_launch_net := g._online._net_enabled
	var pt_launch_known: Dictionary = g._engine.known_recipes.duplicate(true)
	var pt_launch_defs: Dictionary = g._engine.known_recipe_defs.duplicate(true)
	var pt_launch_cauldron: Array[String] = g._pages._experiment_cauldron_items.duplicate()
	var pt_launch_hints: Array[String] = g._pages._experiment_hint_ids.duplicate()
	var pt_launch_filter := g._pages._experiment_filter
	var pt_launch_status := g._pages._experiment_status.text
	var pt_launch_recipe := g._pages._experiment_recipe_line.text
	var pt_launch_pair := g._pair_key("fire", "water")
	g._online._target_state = _personal_target_fixture()
	g._online._net_enabled = false
	g._engine.known_recipes[pt_launch_pair] = true
	g._engine.known_recipe_defs[pt_launch_pair] = {"a": "fire", "b": "water", "out": "steam"}
	g._pages._experiment_cauldron_items = ["fire", "water"]
	g._pages._experiment_launch_pair()
	# Отказ офлайн освобождает котёл: прежнее удержание пары и было «зависанием».
	Selftest.check("active target offline launch releases cauldron without spending",
		g._pages._experiment_cauldron_items.is_empty() and g._engine._experiment_pending_pair.is_empty())
	Selftest.check("target launch copy does not claim reagent return",
		not g._pages._experiment_status.text.contains("Реагенты возвращены"))
	g._online._target_state = pt_launch_target
	g._online._net_enabled = pt_launch_net
	g._engine.known_recipes = pt_launch_known
	g._engine.known_recipe_defs = pt_launch_defs
	g._pages._experiment_cauldron_items = pt_launch_cauldron
	g._pages._experiment_hint_ids = pt_launch_hints
	g._pages._experiment_filter = pt_launch_filter
	g._pages._experiment_status.text = pt_launch_status
	g._pages._experiment_recipe_line.text = pt_launch_recipe
	_render_personal_target(g)

	var recipes_saved: Dictionary = g._engine.known_recipes.duplicate()
	g._engine.known_recipes.clear()
	g._engine.known_recipes[g._pair_key("fire", "water")] = true
	g._engine.known_recipes[g._pair_key("earth", "fire")] = true
	var frontier_plan := g._guild._plan_known_frontier("brick")
	Selftest.check("known frontier points to experiment", not frontier_plan.get("frontier", []).is_empty())
	g._engine.known_recipes = recipes_saved
	Selftest.check("mode retort staged", g._engine._mode_unlocked("retort"))
	# доска v2 Task 5: вкладки «Круг»/«Неделя» сняты — механики живут на доске
	# контрактов, в MODES их больше быть не должно.
	Selftest.check("modes have no circle/week tabs",
		not (Modes.MODES.filter(func(m): return ["circle", "week"].has(String(m["key"]))) as Array).size())
