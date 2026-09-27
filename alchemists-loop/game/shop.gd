extends RefCounted
class_name Shop

# Лавка алхимика — UI поверх фасада Monetization. Здесь нет логики SKU,
# начислений или SDK: экран только показывает каталог, добровольные rewarded и
# приватность/экспорт данных.

# T22: журнал уже выданных покупок переживает удаление локальных данных (он в
# отдельном файле, см. autoload/user_data.gd), поэтому кнопка это обещает.
const DELETE_BUTTON_LABEL := "Удалить данные: журнал покупок останется"

var g: Game
var _dim: ColorRect
var _popup: CenterContainer
var _list: VBoxContainer
var _status: Label
var _consent_dim: ColorRect
var _consent_popup: CenterContainer
var _delete_armed := false
var _delete_button: Button

func _init(game: Game) -> void:
	g = game
	Monetization.initialized.connect(_on_monetization_initialized)
	Monetization.purchase_started.connect(_on_purchase_started)
	Monetization.purchase_succeeded.connect(_on_purchase_succeeded)
	Monetization.purchase_failed.connect(_on_purchase_failed)
	Monetization.rewarded_finished.connect(_on_rewarded_finished)
	Net.account_export_result.connect(_on_account_export_result)
	Net.account_delete_result.connect(_on_account_delete_result)

func build() -> void:
	_build_shop_popup()
	_build_consent_popup()

func open() -> void:
	_rebuild()
	_dim.visible = true
	_popup.visible = true
	Sfx.click()
	if not App.consent_is_decided():
		_open_consent()

func close() -> void:
	_dim.visible = false
	_popup.visible = false
	Sfx.click()

func _build_shop_popup() -> void:
	_dim = ColorRect.new()
	_dim.name = "ShopDim"
	_dim.color = Color(0, 0, 0, 0.62)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.visible = false
	g.add_child(_dim)
	_popup = CenterContainer.new()
	_popup.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_popup.visible = false
	g.add_child(_popup)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", g._panel_style(Color(0.07, 0.11, 0.17, 0.98), 20))
	_popup.add_child(card)
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(370, 0)
	col.add_theme_constant_override("separation", 8)
	card.add_child(col)
	var title := g._label("ЛАВКА АЛХИМИКА", 21)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(1.0, 0.88, 0.45))
	col.add_child(title)
	var subtitle := g._label("Ускорения личной лаборатории и уют. Мировая гонка не продаётся.", 12)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.add_theme_color_override("font_color", Color(0.63, 0.71, 0.78))
	col.add_child(subtitle)
	_status = g._label("", 12)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_status)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 370)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 7)
	scroll.add_child(_list)
	var consent := g._small_button("Настроить согласия и приватность", Vector2(0, 40))
	consent.pressed.connect(_open_consent)
	col.add_child(consent)
	var export_btn := g._small_button("Экспортировать мои данные", Vector2(0, 40))
	export_btn.pressed.connect(_export_data)
	col.add_child(export_btn)
	var privacy := g._small_button("Политика конфиденциальности", Vector2(0, 40))
	privacy.pressed.connect(_open_privacy_policy)
	col.add_child(privacy)
	_delete_button = g._small_button(DELETE_BUTTON_LABEL, Vector2(0, 40))
	_delete_button.pressed.connect(_delete_data)
	col.add_child(_delete_button)
	var close_btn := g._small_button("Закрыть", Vector2(150, 44))
	close_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close_btn.pressed.connect(close)
	col.add_child(close_btn)

func _build_consent_popup() -> void:
	_consent_dim = ColorRect.new()
	_consent_dim.name = "ConsentDim"
	_consent_dim.color = Color(0, 0, 0, 0.74)
	_consent_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_consent_dim.visible = false
	g.add_child(_consent_dim)
	_consent_popup = CenterContainer.new()
	_consent_popup.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_consent_popup.visible = false
	g.add_child(_consent_popup)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", g._panel_style(Color(0.07, 0.11, 0.17, 0.99), 20))
	_consent_popup.add_child(card)
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(350, 0)
	col.add_theme_constant_override("separation", 10)
	card.add_child(col)
	var title := g._label("СОГЛАСИЯ", 21)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(1.0, 0.88, 0.45))
	col.add_child(title)
	var text := g._label("Чтобы показывать аналитику и рекламу, сначала выбери режим.\n\nИгра сохраняет прогресс на устройстве. Для общего мира отправляются только игровой ник, случайный ID установки и события первооткрытий. Сырые платёжные токены не сохраняются.", 13)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_theme_color_override("font_color", Color(0.78, 0.84, 0.9))
	col.add_child(text)
	var allow := g._small_button("Разрешить аналитику и персональную рекламу", Vector2(0, 50), 1)
	allow.pressed.connect(_consent_allow)
	col.add_child(allow)
	var contextual := g._small_button("Только необходимое (без аналитики и рекламы)", Vector2(0, 50))
	contextual.pressed.connect(_consent_contextual)
	col.add_child(contextual)
	var policy := g._label("Согласие можно изменить позже в Лавке. Реклама не показывается во время варки и церемонии открытия.", 11)
	policy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	policy.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	policy.add_theme_color_override("font_color", Color(0.56, 0.64, 0.72))
	col.add_child(policy)

func _open_consent() -> void:
	_consent_dim.visible = true
	_consent_popup.visible = true

func _close_consent() -> void:
	_consent_dim.visible = false
	_consent_popup.visible = false

func _consent_allow() -> void:
	App.set_consent(true, true)
	_close_consent()
	_status.text = "Согласия сохранены: аналитика и персонализированная реклама разрешены."
	_rebuild()

func _consent_contextual() -> void:
	App.set_consent(false, false)
	_close_consent()
	_status.text = "Сохранён режим без аналитики и персонализированной рекламы."
	_rebuild()

func _rebuild() -> void:
	if _list == null:
		return
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	var state := Monetization.status_text()
	_status.text = state
	_status.add_theme_color_override("font_color", Color(0.55, 0.85, 0.82) if Monetization.billing_available else Color(0.76, 0.68, 0.58))
	var products := Monetization.get_products()
	for raw in products:
		if not (raw is Dictionary):
			continue
		var product: Dictionary = raw
		_list.add_child(_product_row(product))
	var divider := HSeparator.new()
	_list.add_child(divider)
	var ads_title := g._label("Награды за просмотр по желанию", 14)
	ads_title.add_theme_color_override("font_color", Color(0.95, 0.82, 0.46))
	_list.add_child(ads_title)
	for raw_placement in Monetization.ads_config.get("placements", []):
		if raw_placement is Dictionary:
			_list.add_child(_ad_row(raw_placement as Dictionary))
	var ads_note := g._label("Лимит: %d наград за просмотр в день, пауза между показами — %d с." % [int(Monetization.ads_config.get("rewarded_daily_cap", 5)), int(Monetization.ads_config.get("rewarded_cooldown_sec", 150))], 11)
	ads_note.add_theme_color_override("font_color", Color(0.56, 0.64, 0.72))
	_list.add_child(ads_note)

func _product_row(product: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	var title := String(product.get("title", product.get("id", "Товар")))
	var price := String(product.get("price_hint", "цена в магазине"))
	var button := g._small_button("Купить · %s" % price, Vector2(0, 42), 1)
	var product_id := String(product.get("id", ""))
	if Monetization.is_product_owned(product_id):
		button.text = "%s ✓" % title
		button.disabled = true
	else:
		button.text = "%s · %s" % [title, price]
		button.pressed.connect(_buy.bind(product_id))
	box.add_child(button)
	var desc := g._label(String(product.get("description", "")), 11)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_color_override("font_color", Color(0.58, 0.67, 0.74))
	box.add_child(desc)
	return box

func _ad_row(placement: Dictionary) -> Control:
	var button := g._small_button("Посмотреть: %s" % String(placement.get("title", "награда")), Vector2(0, 42), 2)
	var placement_id := String(placement.get("id", ""))
	button.pressed.connect(_watch_ad.bind(placement_id))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	box.add_child(button)
	var desc := g._label(String(placement.get("description", "")), 11)
	desc.add_theme_color_override("font_color", Color(0.58, 0.67, 0.74))
	box.add_child(desc)
	return box

func _buy(product_id: String) -> void:
	if not Monetization.purchase(product_id):
		_status.text = "Покупка пока недоступна: подключи выбранный Android-плагин и тестовый аккаунт."

func _watch_ad(placement_id: String) -> void:
	if not Monetization.show_rewarded(placement_id):
		_status.text = "Награда за просмотр сейчас недоступна. Проверь согласие, сеть и тестовый рекламный идентификатор."

func _on_monetization_initialized(_store: String, _billing: bool, _ads: bool) -> void:
	if _popup != null and _popup.visible:
		_rebuild()

func _on_purchase_started(product_id: String) -> void:
	_status.text = "Открываем платёжную форму: %s…" % product_id

func _on_purchase_succeeded(product_id: String, _provider: String) -> void:
	_status.text = "Готово: покупка применена — %s." % product_id
	_rebuild()

func _on_purchase_failed(product_id: String, code: String, message: String) -> void:
	_status.text = "Покупка не завершена%s: %s (%s)." % [" «%s»" % product_id if product_id != "" else "", message, code]

func _on_rewarded_finished(placement_id: String, _reward: Dictionary) -> void:
	_status.text = "Награда получена: %s." % placement_id
	_rebuild()

func _open_privacy_policy() -> void:
	if not App.open_privacy_policy():
		_status.text = "Ссылка на политику ещё не настроена: ALCHEMY_PRIVACY_URL."

func _export_data() -> void:
	g._saves._save_game()
	var game_data := {}
	var file := FileAccess.open(g.SAVE_PATH, FileAccess.READ)
	if file != null:
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		file.close()
		if parsed is Dictionary:
			game_data = parsed
	var path := "user://alchemists_loop_export.json"
	var out := FileAccess.open(path, FileAccess.WRITE)
	if out == null:
		_status.text = "Не удалось создать экспорт."
		return
	out.store_string(JSON.stringify({
		"exported_at": Time.get_datetime_string_from_system(true),
		"app": "Alchemist's Loop",
		"user_data": UserData.export_data(),
		"analytics_events": Analytics.export_data(),
		"game_save": game_data,
	}, "\t"))
	out.close()
	if g._online._net_enabled and g._online._device_id != "":
		Net.export_account(g._online._device_id)
		_status.text = "Локальный экспорт готов; запрашиваем серверную копию…"
	else:
		_status.text = "Экспорт готов: %s" % ProjectSettings.globalize_path(path)

func _on_account_export_result(result: Dictionary) -> void:
	if result.get("ok", false) != true:
		_status.text = "Локальный экспорт готов; серверный экспорт недоступен."
		return
	var path := "user://alchemists_loop_server_export.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(result, "\t"))
		file.close()
		_status.text = "Серверный экспорт готов: %s" % ProjectSettings.globalize_path(path)
	else:
		_status.text = "Сервер ответил, но файл экспорта не удалось создать."

func _on_account_delete_result(result: Dictionary) -> void:
	if result.get("ok", false) == true:
		_status.text = "Серверные данные удалены; локальные данные тоже очищены."
	else:
		_status.text = "Локальные данные очищены, но сервер пока недоступен — повтори удаление позже."

func _delete_data() -> void:
	# #8: маркер незавершённого серверного удаления переживает вайп. Если он
	# остался (сервер был недоступен в прошлый раз) — повторный нажим шлёт
	# DELETE по сохранённому device_id, а не по уже стёртой локальной идентичности.
	var pending := UserData.get_account_delete_pending()
	if pending != "":
		if g._online._net_enabled:
			Net.delete_account(pending)
		_status.text = "Повторяю удаление с сервера…"
		return
	if not _delete_armed:
		_delete_armed = true
		_delete_button.text = "Нажми ещё раз — покупки останутся в журнале"
		_status.text = "Будут удалены локальный прогресс, согласия и ID установки. Мировые вещества останутся, авторство будет анонимизировано сервером. На устройстве сохранится журнал уже выданных покупок (отпечаток чека, SKU и время) — это платёжная защита от повторной выдачи, а не прогресс."
		return
	var device_id := g._online._device_id
	if device_id != "":
		UserData.mark_account_delete_pending(device_id)
	if g._online._net_enabled and device_id != "":
		Net.delete_account(device_id)
	g._saves._delete_local_save()
	UserData.delete_all_local_data()
	Analytics.clear_local_queue()
	g._online._forget_net_identity()
	_status.text = "Локальные данные удалены, журнал покупок сохранён. Перезапусти игру для новой установки."
	_delete_armed = false
	_delete_button.text = DELETE_BUTTON_LABEL
