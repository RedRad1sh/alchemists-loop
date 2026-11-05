extends RefCounted
class_name SuiteHouseV2


static func run(g: Game) -> void:
	_save_and_guest(g)
	_catalog()
	_placement()
	_layout()
	_tasks()
	_rewards(g)
	_assets()
	await _runtime(g)
	await _camera(g)
	await _ui_batch(g)
	_final()


static func _assets() -> void:
	var missing: Array = []
	for id in HouseItems.ITEMS:
		var path := String(HouseItems.ITEMS[id]["sprite"])
		if not ResourceLoader.exists(path):
			missing.append(path)
	Selftest.check("hv2 every catalog sprite exists", missing.is_empty())
	Selftest.check("hv2 room glb exists",
		ResourceLoader.exists("res://assets/house/room/room_with_ceiling.glb"))
	Selftest.check("hv2 blob shadow exists",
		ResourceLoader.exists("res://assets/house/shadows/blob_soft.png"))
	var bad_canvas: Array = []
	for id in HouseItems.ITEMS:
		var it: Dictionary = HouseItems.ITEMS[id]
		var tex: Texture2D = load(String(it["sprite"]))
		if tex == null:
			bad_canvas.append(String(id) + " нет спрайта")
			continue
		var alpha: Rect2 = it.get("alpha", Rect2(Vector2.ZERO, tex.get_size()))
		if alpha.position.x < 0.0 or alpha.position.y < 0.0 \
				or alpha.end.x > tex.get_width() + 0.5 or alpha.end.y > tex.get_height() + 0.5:
			bad_canvas.append(String(id) + " alpha вне текстуры")
		var refl := String(it.get("refl", ""))
		if refl != "" and not ResourceLoader.exists(refl):
			bad_canvas.append(String(id) + " нет отражения")
	Selftest.check("hv2 every sprite loads with its alpha rect inside the canvas", bad_canvas.is_empty())
	var missing_ui: Array = []
	for path in ["res://assets/house/ui/wood_panel.png", "res://assets/house/ui/velvet.png"]:
		if not ResourceLoader.exists(path):
			missing_ui.append(path)
	Selftest.check("hv2 tray textures exist", missing_ui.is_empty())
	var opaque_corner: Array = []
	for id in HouseItems.ITEMS:
		var path := String(HouseItems.ITEMS[id]["sprite"])
		# get_image() у импортированной текстуры возвращает сжатый в VRAM образ,
		# из него нельзя читать пиксели — читаем исходный файл.
		var img := Image.load_from_file(ProjectSettings.globalize_path(path))
		if img == null or img.get_pixelv(Vector2i(0, 0)).a != 0.0:
			opaque_corner.append(String(id))
	Selftest.check("hv2 every item sprite has a transparent canvas corner", opaque_corner.is_empty())


static func _runtime(g: Game) -> void:
	var view := RoomView.new()
	view.size = Vector2(540, 960)
	g.add_child(view)
	await g.get_tree().process_frame
	# Все проверки дальше — null-safe: gate обязан краснить сломанные mirror/items
	# через Selftest.check, а не падать на Nil и обрывать всю секцию.
	Selftest.check("hv2 room view built the glb", view._room != null)
	Selftest.check("hv2 room aabb is non-empty", view._room_aabb.size.x > 6.0 and view._room_aabb.size.y > 2.0)
	Selftest.check("hv2 room ceiling is hidden from the iso camera", _ceiling_hidden(view))
	view.set_built(true)
	view.set_layout(HouseLayout.default_placements())
	await g.get_tree().process_frame
	Selftest.check("hv2 nine items spawned", view._items.size() == 9)
	var first: FurnitureItem = view._items[0] if view._items.size() > 0 else null
	Selftest.check("hv2 item has a sprited box",
		first != null and first._sprite != null and first._sprite.mesh != null)
	Selftest.check("hv2 item reflection is mirrored below the floor",
		first != null and first._reflection != null and first._reflection.visible \
		and first._reflection.get_aabb().end.y <= 0.001 \
		and first._sprite.get_aabb().end.y > 0.0)
	Selftest.check("hv2 item has a planar shadow", first != null and first._shadow != null)
	# Прежняя формулировка краснеть не умела: при `_zoom == 1.0`
	# `_camera.size >= _fit_size` истинно по построению. Кадр проверяем
	# проекцией восьми углов AABB — тест краснеет, если fit меньше комнаты.
	var corners := view._camera != null and view._fit_size > 5.0
	for corner in 8:
		var p: Vector2 = view._camera.unproject_position(view._room_aabb.get_endpoint(corner)) / view._px_scale
		corners = corners and Rect2(Vector2.ZERO, view.size).grow(1.0).has_point(p)
	Selftest.check("hv2 camera fit covers the room", corners)
	# Проверка правки 4: порядок отрисовки — жёсткий контракт кадра
	# (зеркало −10, отражение −5, пол 0, тень +1, спрайт +5). Литералы, а не
	# константы кода: сверка с константой краснела бы только от её удаления.
	var order_ok := first != null \
		and first._sprite_mat != null and first._sprite_mat.render_priority == 5 \
		and first._reflection_mat != null and first._reflection_mat.render_priority == -5 \
		and first._shadow_mat != null and first._shadow_mat.render_priority == 1
	Selftest.check("hv2 draw order: reflection -5, shadow +1, sprite +5", order_ok)
	# Пол реальной комнаты: TRANSPARENCY_ALPHA на приоритете 0 — без этого
	# отражения (−5/−10) не просвечивают, а тень (+1) легла бы под пол.
	Selftest.check("hv2 draw order: room floor is alpha-transparent at priority 0",
		_floor_alpha_at_priority(view, 0))
	# Регрессия (правка 2): тонировка одной комнаты не пишет в кэшированные
	# ресурсы GLB и не заражает вторую комнату в том же процессе.
	_tint_isolation(g)
	# Стенной предмет стоит над полом на своей высоте, напольный — на y = 0.
	var wall_item: FurnitureItem = null
	var floor_item: FurnitureItem = null
	for it in view._items:
		var fi := it as FurnitureItem
		if fi == null:
			continue
		if int(fi.placement.get("wall", -1)) >= 0 and wall_item == null:
			wall_item = fi
		elif int(fi.placement.get("wall", -1)) < 0 and floor_item == null:
			floor_item = fi
	var planes_ok := wall_item != null and floor_item != null \
		and wall_item._sprite != null and floor_item._sprite != null
	if planes_ok:
		var wb: Vector3 = HouseItems.get_item(wall_item.item_id)["box"]
		var want_y := float(wall_item.placement.get("y", 0.0)) - wb.y * 0.5
		# Окно после удвоения высотой 2,15 м в стене 2,4 м, поэтому его низ может
		# отстоять от пола максимум на 0,25 м — прежний порог 0,5 м был меркой
		# метровых предметов.
		planes_ok = want_y > 0.05 \
			and is_equal_approx(wall_item.position.y, want_y) \
			and is_equal_approx(floor_item.position.y, 0.0) \
			and wall_item._sprite.global_position.y > floor_item._sprite.global_position.y + 0.05
	Selftest.check("hv2 wall item sits off the floor plane, floor item on it", planes_ok)
	g.remove_child(view)
	view.free()


static func _camera(g: Game) -> void:
	var view := RoomView.new()
	view.size = Vector2(540, 960)
	g.add_child(view)
	await g.get_tree().process_frame
	var fit := view._fit_size
	var before := view._camera.size
	view.zoom_at(1.2, Vector2(270, 480))
	Selftest.check("hv2 zoom magnifies and clamps at 2.2x",
		view._camera.size < before and view._camera.size >= fit / 2.2 - 0.001)
	view.zoom_at(100.0, Vector2(270, 480))
	Selftest.check("hv2 max zoom magnifies 2.2x",
		is_equal_approx(view._camera.size, fit / 2.2))
	view.zoom_at(1e-6, Vector2(270, 480))
	Selftest.check("hv2 min zoom is fit", is_equal_approx(view._camera.size, fit))
	var target0 := view._target
	view.pan_screen(Vector2(60, 0))
	Selftest.check("hv2 pan moves the target", view._target.distance_to(target0) > 0.001)
	view.pan_screen(Vector2(10000, 10000))
	Selftest.check("hv2 pan stays inside the room bounds",
		absf(view._target.x) <= Placement.ROOM_HALF and absf(view._target.z) <= Placement.ROOM_HALF)
	# Пан идёт вдоль basis.y камеры, у которой мировая Y ≈ cos(pitch) ≈ 0.816:
	# без клампа по высоте тот же мега-пан уводит точку наблюдения на сотни
	# метров, x и z при этом зажаты, и проверка выше остаётся зелёной.
	Selftest.check("hv2 pan keeps the look-at height inside the grown room box",
		view._target.y >= -Placement.ROOM_HALF - 0.001
		and view._target.y <= Placement.WALL_H + Placement.ROOM_HALF + 0.001)
	view.reset_camera()
	Selftest.check("hv2 reset returns to fit", is_equal_approx(view._camera.size, view._fit_size))
	Selftest.check("hv2 reset returns the look-at to the room centre",
		view._target.is_zero_approx() and is_zero_approx(view._tray_lift_px))
	var p0 := view.spirit_screen_pos()
	view.zoom_at(1.5, Vector2(270, 480))
	var p1 := view.spirit_screen_pos()
	Selftest.check("hv2 spirit screen position follows the camera",
		p0.distance_to(p1) > 0.5)
	# Открытый лоток закрывает низ экрана, поэтому комната обязана уезжать
	# ВВЕРХ: экранные координаты духа после set_tray_lift(+) меньше по Y.
	view.set_tray_lift(420.0)
	var p2 := view.spirit_screen_pos()
	Selftest.check("hv2 tray lift moves the room up the screen",
		is_equal_approx(p2.x, p1.x) and p2.y < p1.y - 1.0)
	view.set_tray_lift(0.0)
	var p3 := view.spirit_screen_pos()
	Selftest.check("hv2 closing the tray puts the room back exactly",
		is_equal_approx(p1.x, p3.x) and is_equal_approx(p1.y, p3.y))
	# Якорь зума: мировая точка под пальцем обязана остаться под пальцем.
	# Проверки размера кадра выше этого не видят — они зелёны и при неверном
	# якоре, поэтому тут отдельная проверка проекции до/после zoom_at.
	view.reset_camera()
	var anchor := view.spirit_anchor()
	var q0 := view._camera.unproject_position(anchor)
	view.zoom_at(1.6, q0)
	var q1 := view._camera.unproject_position(anchor)
	Selftest.check("hv2 zoom keeps the point under the finger",
		q0.distance_to(q1) <= 1.0)
	# Тот же якорь при открытом лотке: подъём входит в якорную поправку
	# zoom_at (член -up*_lift_offset()), без него точка под пальцем уезжает
	# на десятки пикселей, а проверка без лотка этого не заметит.
	view.set_tray_lift(200.0)
	var q2 := view._camera.unproject_position(anchor)
	view.zoom_at(1.5, q2)
	var q3 := view._camera.unproject_position(anchor)
	Selftest.check("hv2 zoom keeps the point under the finger while the tray is lifted",
		q2.distance_to(q3) <= 1.0)
	g.remove_child(view)
	view.free()


static func _ceiling_hidden(view: RoomView) -> bool:
	if view._room == null:
		return false
	var found := 0
	for node in view._room.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if not String(mi.name).to_lower().contains("ceiling"):
			continue
		if mi.visible:
			return false
		found += 1
	return found > 0


static func _floor_alpha_at_priority(view: RoomView, want: int) -> bool:
	if view._room == null:
		return false
	var surfaces := 0
	for node in view._room.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if not String(mi.name).to_lower().contains("floor"):
			continue
		for i in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(i) as BaseMaterial3D
			if mat == null or mat.transparency != BaseMaterial3D.TRANSPARENCY_ALPHA \
					or mat.render_priority != want:
				return false
			surfaces += 1
	return surfaces > 0


static func _tint_isolation(g: Game) -> void:
	var world_a := Node3D.new()
	world_a.name = "TintIsolationWorldA"
	var world_b := Node3D.new()
	world_b.name = "TintIsolationWorldB"
	g.add_child(world_a)
	g.add_child(world_b)
	var built_a := RoomBuilder.build(world_a)
	var room_a: Node3D = built_a.get("room")
	var room_b: Node3D = RoomBuilder.build(world_b).get("room")
	var originals := []
	for root in [room_a]:
		for node in root.find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			for i in mi.mesh.get_surface_count():
				var mat := mi.get_active_material(i) as BaseMaterial3D
				if mat != null:
					originals.append([mi, i, mat.albedo_color, mat.render_priority, mat.transparency])
	if room_a == null or room_b == null:
		Selftest.check("hv2 tinting one room does not contaminate another room", false)
	else:
		var probe_wall := Color(0.11, 0.85, 0.19)
		var probe_floor := Color(0.87, 0.13, 0.62)
		var before := []  # [MeshInstance3D, поверхность, albedo до тонировки]
		for node in room_b.find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			var lower := String(mi.name).to_lower()
			if not (lower.contains("wall") or lower.contains("floor")):
				continue
			for i in mi.mesh.get_surface_count():
				var mat := mi.get_active_material(i) as BaseMaterial3D
				if mat != null:
					before.append([mi, i, mat.albedo_color])
		RoomBuilder.tint_room(room_a, probe_wall, probe_floor)
		var clean := not before.is_empty()
		for entry in before:
			var mi := entry[0] as MeshInstance3D
			var mat := mi.get_active_material(int(entry[1])) as BaseMaterial3D
			if mat == null or mat.albedo_color != (entry[2] as Color):
				clean = false
		Selftest.check("hv2 tinting one room does not contaminate another room", clean)
		RoomBuilder.tint_room(room_a, Color.WHITE, Color.WHITE)
		var restored := not originals.is_empty()
		for entry in originals:
			var mi := entry[0] as MeshInstance3D
			var mat := mi.get_active_material(int(entry[1])) as BaseMaterial3D
			restored = restored and mat != null and mat.albedo_color == entry[2] \
				and mat.render_priority == entry[3] and mat.transparency == entry[4]
		Selftest.check("hv2 tint then white restores original room materials", restored)
	g.remove_child(world_a)
	world_a.free()
	g.remove_child(world_b)
	world_b.free()


static func _save_and_guest(g: Game) -> void:
	var prev_house := g._home._cosmetic_house
	var prev_unlocked: Array = g._home.house_unlocked.duplicate()
	var prev_placements: Array[Dictionary] = []
	prev_placements.assign(g._home.house_placements)
	g._home._cosmetic_house = true
	g._home.house_unlocked = ["bed", "door"]
	g._home.house_placements = HouseLayout.default_placements()
	var block := g._saves._house_block()
	Selftest.check("hv2 save block has only new fields",
		block.has("house_unlocked") and block.has("house_placements")
		and not block.has("house_furniture") and not block.has("house_layout") and not block.has("house_owned"))
	g._home.house_unlocked.clear()
	g._home.house_placements.clear()
	g._saves._apply_house_block(block)
	Selftest.check("hv2 save block roundtrip", g._home.house_unlocked.size() == 2
		and g._home.house_placements.size() == 9)
	var json := g._home._house_json()
	Selftest.check("hv2 house json is v2 with items",
		int(json.get("v", 0)) == 2 and json.has("items") and not json.has("furniture") and not json.has("layout"))
	var guest := Home._parse_guest_house(json)
	Selftest.check("hv2 guest parses v2 items", guest["built"] and (guest["items"] as Array).size() == 9)
	var old := Home._parse_guest_house({"v": 1, "built": true, "furniture": {"bed": "bed"}})
	Selftest.check("hv2 guest rejects non-v2", not old["built"] and (old["items"] as Array).is_empty())
	var junk := Home._parse_guest_house({"v": 2, "built": true, "items": [
		{"id": "nope", "x": 0, "z": 0, "y": 0, "flip": false, "wall": -1},
		{"id": "bed", "x": NAN, "z": 0, "y": 0, "flip": false, "wall": -1},
		{"id": "bed", "x": 0, "z": 0, "y": 0, "flip": false, "wall": -1},
	]})
	Selftest.check("hv2 guest drops junk and keeps the valid item",
		(junk["items"] as Array).size() == 1 and String(junk["items"][0]["id"]) == "bed")
	g._home._cosmetic_house = prev_house
	g._home.house_unlocked = prev_unlocked
	g._home.house_placements = prev_placements


static func _catalog() -> void:
	Selftest.check("hv2 catalog has 25 items", HouseItems.ITEMS.size() == 25)
	var per_cat := {}
	var base_total := 0
	var ids_ok := true
	var fields_ok := true
	var costs_ok := true
	var walls_ok := true
	for raw_id in HouseItems.ITEMS:
		var id := String(raw_id)
		var it: Dictionary = HouseItems.ITEMS[raw_id]
		ids_ok = ids_ok and String(it.get("id", "")) == id
		var box: Vector3 = it.get("box", Vector3.ZERO)
		fields_ok = fields_ok and box.x > 0.0 and box.y > 0.0 and box.z > 0.0 \
			and float(it.get("ppm", 0.0)) > 0.0 \
			and String(it.get("sprite", "")).begins_with("res://assets/house/items/") \
			and HouseItems.CATS.has(String(it.get("cat", "")))
		var is_reward := bool(it.get("reward", false))
		costs_ok = costs_ok and (int(it.get("cost", -1)) == 0 if is_reward else int(it.get("cost", 0)) > 0)
		var cat := String(it.get("cat", ""))
		var want_wall := cat in ["window", "door"]
		walls_ok = walls_ok and bool(it.get("wall", false)) == want_wall
		if not is_reward:
			per_cat[cat] = int(per_cat.get(cat, 0)) + 1
			base_total += 1
	Selftest.check("hv2 catalog ids match keys", ids_ok)
	# Бесплатный стартовый предмет домика берётся по категории, поэтому у каждой
	# категории обязан быть хотя бы один непокупной (reward=false) вариант.
	var starter_ok := true
	for cat in HouseItems.CATS:
		var starter := HouseItems.base_item(String(cat))
		starter_ok = starter_ok and starter != "" \
			and String(HouseItems.get_item(starter).get("cat", "")) == String(cat) \
			and not bool(HouseItems.get_item(starter).get("reward", false))
	Selftest.check("hv2 catalog has six categories with nineteen base items",
		per_cat.size() == 6 and base_total == 19)
	Selftest.check("hv2 every category has a base starter item", starter_ok)
	Selftest.check("hv2 every item has positive box/ppm/path and known category", fields_ok)
	Selftest.check("hv2 rewards are free, everything else costs ether", costs_ok)
	Selftest.check("hv2 wall flag matches category", walls_ok)
	var rewards := ["window_contract", "window_seal", "window_guild",
		"door_guild", "bed_carved", "planetarium_ember"]
	var rewards_ok := true
	for rid in rewards:
		var it := HouseItems.get_item(String(rid))
		rewards_ok = rewards_ok and not it.is_empty() and bool(it.get("reward", false)) \
			and String(it.get("tint", "")) != ""
	Selftest.check("hv2 six contract/circle reward ids exist and are tinted", rewards_ok)
	for rid in ContractsBalance.DECOR:
		Selftest.check("hv2 contract decor id exists: " + String(rid), HouseItems.exists(String(rid)))
	for rid in Game.CIRCLE_DECOR_REWARDS.values():
		Selftest.check("hv2 circle decor id exists: " + String(rid), HouseItems.exists(String(rid)))


static func _placement() -> void:
	# Метрики напольных предметов в комнате удвоены (`HouseItems.ITEM_SCALE`),
	# поэтому ожидаемые габариты = 2 × значения из .asset: кровать 1,0×0,781 м →
	# 2,0×1,562 м. Настенные (`WALL_ITEM_SCALE`) остаются в метриках оригинала.
	var bed := {"id": "bed", "x": 0.95, "z": -2.3, "y": 0.0, "flip": false, "wall": -1}
	var fp := Placement.footprint(bed)
	Selftest.check("hv2 bed footprint follows box", absf(fp.size.x - 2.0) < 0.001
		and absf(fp.size.y - 1.562) < 0.001)
	var shelf := {"id": "window", "x": -3.406, "z": 0.90, "y": 1.55, "flip": false, "wall": 0}
	var sfp := Placement.footprint(shelf)
	Selftest.check("hv2 wall footprint is depth x span",
		is_equal_approx(sfp.position.x, -Placement.ROOM_HALF)
		and absf(sfp.size.x - 0.146734) < 0.001 and absf(sfp.size.y - 1.0) < 0.001)
	Selftest.check("hv2 clamp keeps floor item inside room",
		Placement.clamp_record({"id": "bed", "x": 99.0, "z": -99.0, "y": 5.0, "flip": false, "wall": -1})["x"] <= 3.431 - 0.02 - 1.0 + 0.001)
	Selftest.check("hv2 clamp pins wall item to its wall",
		is_equal_approx(float(Placement.clamp_record(shelf)["x"]), -3.431 + 0.146734 * 0.5))
	Selftest.check("hv2 wall y stays inside the wall",
		float(Placement.clamp_record({"id": "window", "x": -3.4, "z": 0.0, "y": 9.0, "flip": false, "wall": 0})["y"]) <= 2.4 - 0.5372 + 0.001)
	Selftest.check("hv2 snap moves to 0.1 grid",
		absf(float(Placement.snap_record({"id": "table", "x": 0.06, "z": 0.04, "y": 0.0, "flip": false, "wall": -1})["x"]) - 0.1) < 0.001
		and absf(float(Placement.snap_record({"id": "table", "x": 0.06, "z": 0.04, "y": 0.0, "flip": false, "wall": -1})["z"])) < 0.001)
	Selftest.check("hv2 touching boxes have zero gap",
		Placement.gap(Rect2(0, 0, 1, 1), Rect2(1, 0, 1, 1)) < 0.001)
	Selftest.check("hv2 diagonal gap uses the largest axis gap",
		absf(Placement.gap(Rect2(0, 0, 1, 1), Rect2(1.2, 1.3, 1, 1)) - 0.3) < 0.001)
	var table := {"id": "table", "x": 1.9, "z": -0.5, "y": 0.0, "flip": false, "wall": -1}
	Selftest.check("hv2 non-overlapping floor items are valid",
		Placement.valid(table, [bed]))
	Selftest.check("hv2 overlapping floor items are invalid",
		not Placement.valid({"id": "table_merchant", "x": 1.9, "z": -0.5, "y": 0.0, "flip": false, "wall": -1}, [table]))
	Selftest.check("hv2 rug is a non-colliding floor layer",
		Placement.valid({"id": "table_merchant", "x": -1.6, "z": -2.0, "y": 0.0, "flip": false, "wall": -1},
			[{"id": "rug", "x": -1.6, "z": -2.0, "y": 0.0, "flip": false, "wall": -1}]))
	Selftest.check("hv2 wall and floor items do not collide",
		Placement.valid(bed, [door_placement()]))
	Selftest.check("hv2 move that reduces overlap is allowed",
		Placement.move_allowed({"id": "table_merchant", "x": 1.9, "z": -0.5, "y": 0.0, "flip": false, "wall": -1},
			{"id": "table_merchant", "x": 1.9, "z": 0.0, "y": 0.0, "flip": false, "wall": -1}, [table], -1))
	Selftest.check("hv2 push_out removes the overlap",
		Placement.valid(Placement.push_out(
			{"id": "table_merchant", "x": 1.9, "z": -0.5, "y": 0.0, "flip": false, "wall": -1}, [table], -1), [table]))
	var walls_ok := true
	for wall in [0, 1]:
		var obstacle := Placement.clamp_record({"id": "window", "x": 0.9, "z": 0.9,
			"y": 1.55, "flip": false, "wall": wall})
		var window := Placement.clamp_record({"id": "window_alt", "x": 0.0, "z": 0.0,
			"y": 0.5, "flip": false, "wall": wall})
		walls_ok = walls_ok and not Placement.valid(window, [obstacle]) \
			and Placement.valid(Placement.snap_record(Placement.push_out(window, [obstacle], -1)), [obstacle])
	Selftest.check("hv2 wall push_out moves along both walls and survives snap", walls_ok)


static func _layout() -> void:
	var model := HouseLayout.new()
	Selftest.check("hv2 unlock validates id", not model.unlock("nope") and model.unlocked.is_empty())
	Selftest.check("hv2 unlock adds once", model.unlock("bed") and not model.unlock("bed")
		and model.unlocked == ["bed"])
	var p := {"id": "bed", "x": 0.95, "z": -2.28, "y": 0.0, "flip": false, "wall": -1}
	Selftest.check("hv2 add placement", model.add_placement(p) and model.placements.size() == 1)
	var full := HouseLayout.new()
	for i in HouseLayout.MAX_ITEMS:
		full.add_placement({"id": "table_merchant", "x": 0.0, "z": 0.0, "y": 0.0, "flip": false, "wall": -1})
	Selftest.check("hv2 41st placement rejected",
		full.placements.size() == HouseLayout.MAX_ITEMS
		and not full.add_placement({"id": "table_merchant", "x": 0.0, "z": 0.0, "y": 0.0, "flip": false, "wall": -1}))
	var round := HouseLayout.parse(model.to_dict())
	Selftest.check("hv2 roundtrip keeps unlocked and placements",
		round.unlocked == model.unlocked and round.placements.size() == 1
		and String(round.placements[0]["id"]) == "bed")
	var junk := HouseLayout.parse({
		"unlocked": ["bed", "nope", 42],
		"placements": [
			{"id": "nope", "x": 0, "z": 0, "y": 0, "flip": false, "wall": -1},
			{"id": "table", "x": NAN, "z": 0, "y": 0, "flip": false, "wall": -1},
			{"id": "table", "x": 0, "z": INF, "y": 0, "flip": false, "wall": -1},
			{"id": "table", "x": "oops", "z": 0, "y": 0, "flip": false, "wall": -1},
			{"id": "table", "x": 99, "z": -99, "y": 0, "flip": false, "wall": -1}
		]})
	Selftest.check("hv2 unknown ids are dropped", junk.unlocked == ["bed"] and junk.placements.size() == 1)
	Selftest.check("hv2 non-finite coords are dropped and the rest clamps",
		junk.placements.size() == 1 and float(junk.placements[0]["x"]) <= 3.411)
	var move := HouseLayout.parse({"unlocked": [], "placements": [p]})
	Selftest.check("hv2 move_at replaces one placement",
		move.move_at(0, {"id": "rug", "x": 0.0, "z": 0.0, "y": 0.0, "flip": false, "wall": -1})
		and String(move.placements[0]["id"]) == "rug")
	Selftest.check("hv2 remove_at drops one", move.remove_at(0) and move.placements.is_empty())


static func _tasks() -> void:
	var seeded := HouseLayout.default_placements()
	Selftest.check("hv2 layout B has nine pieces", seeded.size() == 9)
	var by_cat := {}
	for p in seeded:
		by_cat[String(HouseItems.get_item(String(p["id"]))["cat"])] = p
	Selftest.check("hv2 layout B covers every category", by_cat.size() == 6)
	var satisfied := []
	for task in Game.HOUSE_TASKS:
		if Home.house_task_satisfied(task, seeded):
			satisfied.append(String(task["id"]))
	Selftest.check("hv2 layout B satisfies only the onboarding task",
		satisfied == ["rug_under_bed"])
	var door := {"id": "door", "x": -1.6, "z": -3.387, "y": 1.15, "flip": false, "wall": 1}
	# Дверь после удвоения имеет глубину 0,112 м, ковёр — 2,0 м по z: центр ковра
	# на -2,02 даёт зазор 0,3 м, на -2,32 ковёр касается двери.
	var rug_far := {"id": "rug", "x": -1.6, "z": -2.02, "y": 0.0, "flip": false, "wall": -1}
	var rug_near := {"id": "rug", "x": -1.6, "z": -2.32, "y": 0.0, "flip": false, "wall": -1}
	Selftest.check("hv2 near rule rejects a 0.3 m gap",
		not Home.house_task_satisfied(_task("door_by_rug"), [door, rug_far]))
	Selftest.check("hv2 near rule accepts a zero gap",
		Home.house_task_satisfied(_task("door_by_rug"), [door, rug_near]))
	var bed := {"id": "bed", "x": -2.9, "z": -2.0, "y": 0.0, "flip": false, "wall": -1}
	var win_low := {"id": "window", "x": -3.406, "z": -2.0, "y": 1.15, "flip": false, "wall": 0}
	var win_side := {"id": "window", "x": 2.5, "z": -3.04, "y": 1.5, "flip": false, "wall": 1}
	Selftest.check("hv2 over rule needs y >= 1.2",
		not Home.house_task_satisfied(_task("window_over_bed"), [bed, win_low]))
	Selftest.check("hv2 over rule needs the projection to cross",
		not Home.house_task_satisfied(_task("window_over_bed"), [bed, win_side]))
	Selftest.check("hv2 over rule passes above the bed",
		Home.house_task_satisfied(_task("window_over_bed"),
			[bed, {"id": "window", "x": -3.406, "z": -2.0, "y": 1.5, "flip": false, "wall": 0}]))
	var ids_ok := true
	var rewards_ok := true
	var tasks := {}
	for t in Game.HOUSE_TASKS:
		tasks[String(t["id"])] = true
		ids_ok = ids_ok and String(t["give"]) != "" and HouseItems.exists(String(t["give"]))
		var it := HouseItems.get_item(String(t["give"]))
		rewards_ok = rewards_ok and bool(it.get("reward", false))
	Selftest.check("hv2 six tasks exist", tasks.size() == 6)
	Selftest.check("hv2 every task grants a real reward id", ids_ok)
	Selftest.check("hv2 every task grants a reward-only item", rewards_ok)


static func _rewards(g: Game) -> void:
	Selftest.check("hv2 all catalog ids pass decor_exists", _all_decor_exist())
	Selftest.check("hv2 old ids no longer pass decor_exists",
		not Contracts.decor_exists("rug_1") and not Contracts.decor_exists("bed_3"))
	var unlocked_before := g._home.house_unlocked.duplicate()
	g._home.house_unlocked.clear()
	Selftest.check("hv2 contract reward unlocks only the id",
		g._home._unlock_item("window_contract") and g._home.house_unlocked == ["window_contract"])
	Selftest.check("hv2 second unlock is a no-op", not g._home._unlock_item("window_contract"))
	g._home.house_unlocked.clear()
	for rid in Game.CIRCLE_DECOR_REWARDS.values():
		g._home._unlock_item(String(rid))
	Selftest.check("hv2 circle rewards unlock all three reward ids",
		g._home.house_unlocked.size() == 3 and g._home.house_unlocked.has("bed_carved"))
	g._home.house_unlocked = unlocked_before


static func _all_decor_exist() -> bool:
	for id in HouseItems.ITEMS:
		if not Contracts.decor_exists(String(id)):
			return false
	return true


static func _task(id: String) -> Dictionary:
	for t in Game.HOUSE_TASKS:
		if String(t["id"]) == id:
			return t
	return {}


static func door_placement() -> Dictionary:
	return {"id": "door", "x": -1.6, "z": -3.387, "y": 0.8356, "flip": false, "wall": 1}


static func _ui_batch(g: Game) -> void:
	# Esc закрывает верхнюю модалку: предыдущие сюиты могут оставить свою. Снимаем их
	# ДО снимка мира, чтобы restore не возвращал чужое окно и не оставлял его открытым.
	for _drain in 12:
		if not g._close_top_modal():
			break
	# Снимаем весь затронутый мир, а не оставляем false/пустые массивы следующей сюите.
	var h := g._home
	var home_before := {}
	for key in ["_cosmetic_house", "house_unlocked", "house_placements", "house_tasks_done",
			"_shop_cat", "_house_spirit_t", "_house_spirit_lean"]:
		var value: Variant = h.get(key)
		home_before[key] = value.duplicate(true) if value is Array else value
	var engine_before := {}
	for key in ["ether", "ether_overflow", "status_text", "regen_clock", "autosave_clock"]:
		engine_before[key] = g._engine.get(key)
	var spirit_before := {}
	for key in ["_companion_unlocked", "_companion_affinity", "_companion_level", "_companion_idle_clock"]:
		spirit_before[key] = g._spirit.get(key)
	var screen_before := h._house_screen.visible
	var tray_before := h._house_tray_open
	var tab_before := "decor"
	for id in h._house_tab_scrolls:
		if (h._house_tab_scrolls[id] as Control).visible:
			tab_before = String(id)
	var ui_before := []
	for node in [g._spirit._companion_dim, g._spirit._companion_dlg]:
		ui_before.append(_node_state(node, ["visible", "z_index", "modulate", "scale"]))
	for node in [g._spirit._companion_dlg_title, g._spirit._companion_dlg_text,
			g._spirit._companion_dlg_aff, g._spirit._companion_dlg_name, h._house_popup_title, h._host_showcase_lbl]:
		ui_before.append(_node_state(node, ["text"]))
	ui_before.append(_node_state(g._spirit._companion_dlg_name_row, ["visible"]))
	ui_before.append(_node_state(g._spirit._companion, ["z_index", "_base_key"]))
	ui_before.append(_node_state(h._house_spirit_node, ["position", "scale", "rotation", "_base_key", "_hearts", "_override_key", "_override_left"]))
	ui_before.append(_node_state(h._host_spirit, ["visible", "_aura"]))
	ui_before.append(_node_state(h._host_flame, ["color"]))
	var hearts_processing: bool = h._house_spirit_node.is_processing()
	var cameras_before := []
	var materials_before := []
	for view in [h._house_room, h._house_popup_view]:
		cameras_before.append(_node_state(view, ["built", "placements", "_zoom", "_target", "_tray_lift_px", "_tray_top_px"]))
		for root in [view._room]:
			for raw_mesh in root.find_children("*", "MeshInstance3D", true, false):
				var mesh := raw_mesh as MeshInstance3D
				for surface in mesh.mesh.get_surface_count():
					materials_before.append([mesh, surface, mesh.get_surface_override_material(surface)])
	var frozen := g._saves._save_frozen
	g._saves._save_frozen = true
	# Покупки/награды тестируем отдельно от бонуса эфира за повышение дружбы.
	g._spirit._companion_unlocked = false
	await _screen(g)
	_shop(g)
	await _touch_input(g)
	await _spirit_and_guest(g)
	h._close_house_screen()
	# Дожидаемся штатного закрытия Juice, чтобы его tween не испортил restore.
	await g.get_tree().create_timer(0.25).timeout
	for key in home_before:
		h.set(key, home_before[key])
	for key in engine_before:
		g._engine.set(key, engine_before[key])
	for key in spirit_before:
		g._spirit.set(key, spirit_before[key])
	h._set_house_tab(tab_before)
	if screen_before:
		h._open_house_screen()
		if tray_before:
			h._open_house_tray()
	for state in cameras_before:
		_restore_node_state(state)
		var view := state["node"] as RoomView
		view._rebuild_items()
		view._apply_camera()
	for material in materials_before:
		(material[0] as MeshInstance3D).set_surface_override_material(material[1], material[2])
	for state in ui_before:
		_restore_node_state(state)
	h._house_spirit_node.set_process(hearts_processing)
	g._engine._refresh()
	g._saves._save_frozen = frozen
	Selftest.check("hv2 UI fixtures restore the economy and house",
		g._engine.ether == engine_before["ether"]
		and g._engine.ether_overflow == engine_before["ether_overflow"]
		and h._cosmetic_house == home_before["_cosmetic_house"]
		and h.house_unlocked == home_before["house_unlocked"]
		and h.house_placements == home_before["house_placements"]
		and h.house_tasks_done == home_before["house_tasks_done"]
		and g._spirit._companion_affinity == spirit_before["_companion_affinity"])


static func _node_state(node: Node, keys: Array) -> Dictionary:
	var values := {}
	for key in keys:
		var value: Variant = node.get(key)
		values[key] = value.duplicate(true) if value is Array else value
	return {"node": node, "values": values}


static func _restore_node_state(state: Dictionary) -> void:
	for key in state["values"]:
		state["node"].set(key, state["values"][key])


static func _screen(g: Game) -> void:
	var h := g._home
	h._cosmetic_house = false
	h.house_unlocked.clear()
	h.house_placements.clear()
	h.house_tasks_done.clear()
	h._refresh_house_screen()
	Selftest.check("hv2 house screen owns a room view", h._house_room != null)
	Selftest.check("hv2 unbuilt house shows the build overlay", h._house_overlay != null and h._house_overlay.visible)
	g._engine.ether_overflow = 0
	g._engine.ether = Game.HOUSE_COST - 1
	h._buy_house()
	Selftest.check("hv2 build rejects insufficient ether", not h._cosmetic_house and g._engine.ether == Game.HOUSE_COST - 1)
	g._engine.ether = Game.HOUSE_COST
	h._buy_house()
	var base_ok := true
	for cat in HouseItems.CATS:
		base_ok = base_ok and h.house_unlocked.has(HouseItems.base_item(String(cat)))
	Selftest.check("hv2 build spends ether and unlocks one base item per category", h._cosmetic_house and base_ok and g._engine._available_ether() == 0)
	Selftest.check("hv2 build seeds layout B", h.house_placements.size() == 9)
	Selftest.check("hv2 build hides the overlay", h._house_overlay != null and not h._house_overlay.visible)
	Selftest.check("hv2 build completes only the onboarding task", h.house_tasks_done == ["rug_under_bed"])
	h._open_house_screen()
	h._open_house_tray()
	await g.get_tree().create_timer(0.25).timeout
	Selftest.check("hv2 tray opens", h._house_tray_open and h._house_tray != null and h._house_tray.visible)
	Selftest.check("hv2 room lift is half the actual tray height", h._house_room != null and h._house_tray != null
		and is_equal_approx(h._house_room._tray_lift_px, h._house_tray_room_rect().size.y * 0.5))
	Selftest.check("hv2 esc closes tray before screen", g._close_top_modal() and not h._house_tray_open and h._house_screen.visible)
	await g.get_tree().create_timer(0.25).timeout
	if h._house_room != null:
		h._house_room.zoom_at(1.5, Vector2(270, 480))
		h._house_room.pan_screen(Vector2(24, -16))
		var camera_size: float = h._house_room._camera.size
		var target: Vector3 = h._house_room._target
		h._open_house_tray()
		await g.get_tree().create_timer(0.25).timeout
		h._close_house_tray()
		await g.get_tree().create_timer(0.25).timeout
		Selftest.check("hv2 closing tray preserves zoom and pan and removes lift", is_equal_approx(h._house_room._camera.size, camera_size)
			and h._house_room._target.is_equal_approx(target) and is_zero_approx(h._house_room._tray_lift_px)
			and not h._house_tray.visible)
	h._close_house_screen()
	h._refresh_house_screen()
	Selftest.check("hv2 refreshing a closed screen keeps the room hidden", not h._house_screen.visible
		and h._house_room != null and not h._house_room.is_visible_in_tree())


static func _card_button(h: Home, id: String) -> Button:
	if h._house_cards == null:
		return null
	var card := h._house_cards.get_node_or_null(NodePath(id))
	return card.find_child("Action", true, false) as Button if card != null else null


static func _shop(g: Game) -> void:
	var h := g._home
	h._cosmetic_house = true
	h.house_unlocked.clear()
	h.house_placements.clear()
	h._refresh_house_screen()
	g._engine.ether_overflow = 0
	g._engine.ether = 0
	Selftest.check("hv2 buy unknown item fails", not h._buy_house_item("nope"))
	Selftest.check("hv2 buy reward item fails", not h._buy_house_item("window_contract"))
	Selftest.check("hv2 buy rejects insufficient ether", not h._buy_house_item("rug_alt") and h.house_unlocked.is_empty())
	g._engine.ether = 10000
	var eth0 := g._engine.ether
	Selftest.check("hv2 buy alt item spends ether and unlocks", h._buy_house_item("rug_alt") and g._engine.ether == eth0 - 130 and h.house_unlocked.has("rug_alt"))
	Selftest.check("hv2 repeat buy is a no-op", not h._buy_house_item("rug_alt") and g._engine.ether == eth0 - 130)
	h._on_room_placement({"id": "rug_alt", "x": 0.0, "z": 0.0, "y": 0.0, "flip": false, "wall": -1})
	Selftest.check("hv2 placing an unlocked item adds a placement", h.house_placements.size() == 1)
	Selftest.check("hv2 placing a locked item does nothing", not h._on_room_placement({"id": "bed", "x": 0.0, "z": 0.0, "y": 0.0, "flip": false, "wall": -1}) and h.house_placements.size() == 1)
	for i in HouseLayout.MAX_ITEMS - 1:
		h.house_placements.append({"id": "rug_alt", "x": 0.0, "z": 0.0, "y": 0.0, "flip": false, "wall": -1})
	Selftest.check("hv2 41st placement is rejected with a hint", not h._on_room_placement({"id": "rug_alt", "x": 0.0, "z": 0.0, "y": 0.0, "flip": false, "wall": -1}) and h.house_placements.size() == 40 and g._engine.status_text.contains("40"))
	h.house_placements.clear()
	h.house_tasks_done.clear()
	h._complete_house_task(_task("table_at_window"))
	h._set_shop_cat("window")
	var earned := _card_button(h, "window_guild")
	var locked := _card_button(h, "window_contract")
	Selftest.check("hv2 earned reward card offers placement", earned != null and not earned.disabled and earned.text == "Поставить")
	Selftest.check("hv2 locked reward card is not sold", locked != null and locked.disabled and locked.text == "За поручение")
	var pic := h._house_cards.get_node_or_null("window_guild/Content/Picture") as TextureRect if h._house_cards != null else null
	Selftest.check("hv2 reward card uses catalog tint", pic != null and pic.self_modulate == Color("#4d7ab7"))
	if earned != null:
		earned.pressed.emit()
	Selftest.check("hv2 earned card starts a ghost without appending", h.house_placements.is_empty()
		and h._house_room.get("_touch") != null and h._house_room.get("_touch").ghost_exists())
	if h._house_room.has_method("begin_placement"):
		var at := h._house_room._camera.unproject_position(Vector3(0, 1.3, -Placement.ROOM_HALF))
		_mouse(h._house_room, at, true)
		_motion(h._house_room, at + Vector2(12, 0), Vector2(12, 0))
		_mouse(h._house_room, at + Vector2(12, 0), false)
	Selftest.check("hv2 earned reward placed on pointer release", h.house_placements.size() == 1 and h.house_placements[0]["id"] == "window_guild")
	h.house_placements.clear()
	h._refresh_house_screen()
	h._set_shop_cat("rug")
	for i in 2:
		var rug := _card_button(h, "rug_alt")
		if rug != null:
			rug.pressed.emit()
		if h._house_room.has_method("begin_placement"):
			var at := h._house_room._camera.unproject_position(Vector3.ZERO)
			_mouse(h._house_room, at, true)
			_mouse(h._house_room, at, false)
	Selftest.check("hv2 unlocked item allows unlimited free copies", h.house_placements.size() == 2 and g._engine.ether == eth0 - 130)


static func _spirit_and_guest(g: Game) -> void:
	var h := g._home
	h._open_house_screen()
	var node = h._house_spirit_node
	Selftest.check("hv2 house spirit is interactive", node != null and node.mouse_filter == Control.MOUSE_FILTER_STOP)
	var old_t: float = h.get("_house_spirit_t") if h.get("_house_spirit_t") != null else 0.0
	h._house_spirit_tick(0.1)
	Selftest.check("hv2 visible house spirit breathes", node != null and node.scale != Vector2.ONE)
	if node != null:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = true
		node._gui_input(ev)
	Selftest.check("hv2 spirit tap opens friendship dialog and hearts", node != null and node.get("_hearts").size() == 3
		and g._spirit._companion_dlg.visible and g._spirit._companion_dlg.z_index > h._house_screen.z_index)
	var touch_buttons := g._spirit._companion_dlg.find_children("*", "Button", true, false)
	var touch_ok := not touch_buttons.is_empty()
	for button in touch_buttons:
		touch_ok = touch_ok and (button as Button).custom_minimum_size.y >= 48
	Selftest.check("hv2 friendship dialog keeps 48 px touch buttons", touch_ok)
	g._spirit._companion_close_dialog()
	h._close_house_screen()
	var parked: Variant = h.get("_house_spirit_t")
	h._house_spirit_tick(0.5)
	Selftest.check("hv2 hidden house spirit tick is parked", parked != null and h.get("_house_spirit_t") == parked and float(parked) > old_t)
	var parsed := h._parse_guest_house({"v": 2, "built": true, "items": HouseLayout.default_placements(), "world_first": 4})
	Selftest.check("hv2 guest layout keeps nine items", (parsed["items"] as Array).size() == 9)
	var view := RoomView.new()
	view.size = Vector2(400, 700)
	g.add_child(view)
	await g.get_tree().process_frame
	view.set_built(true)
	view.set_layout(parsed["items"])
	view.read_only = true
	view.begin_placement("bed", Vector2(200, 350))
	Selftest.check("hv2 guest room is read-only", not view._touch.ghost_exists())
	var pos := view.spirit_screen_pos()
	Selftest.check("hv2 spirit screen position is finite", is_finite(pos.x) and is_finite(pos.y))
	g.remove_child(view)
	view.free()
	h._apply_player_house("Люмина", {"v": 2, "built": true, "items": parsed["items"], "world_first": 4, "aura": "rose"})
	Selftest.check("hv2 actual guest popup uses read-only room", h._house_popup_view is RoomView and h._house_popup_view.get("read_only") == true)
	var showcase := h._house_popup.find_child("HostShowcase", true, false) as Label
	Selftest.check("hv2 guest showcase keeps bottles flame caption", showcase != null and showcase.text.contains("4")
		and showcase.text.contains("после связи") and h._host_flame != null
		and h._host_flame.polygon.size() >= 3 and h._host_flame.color == h._showcase_flame_color())


static func _mouse(view: RoomView, at: Vector2, down: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.position = at
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = down
	view._gui_input(ev)


static func _motion(view: RoomView, at: Vector2, relative: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = at
	ev.relative = relative
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT
	view._gui_input(ev)


static func _finger(view: RoomView, index: int, at: Vector2, down: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = index
	ev.position = at
	ev.pressed = down
	view._gui_input(ev)


static func _finger_drag(view: RoomView, index: int, at: Vector2, relative: Vector2) -> void:
	var ev := InputEventScreenDrag.new()
	ev.index = index
	ev.position = at
	ev.relative = relative
	view._gui_input(ev)


static func _record(id: String, x := 0.0, z := 0.0, y := 0.0, wall := -1) -> Dictionary:
	return {"id": id, "x": x, "z": z, "y": y, "wall": wall, "flip": false}


static func _touch_input(g: Game) -> void:
	var view := RoomView.new()
	view.size = Vector2(540, 960)
	g.add_child(view)
	await g.get_tree().process_frame
	view.set_built(true)
	Selftest.check("hv2 RoomView exposes touch placement", view.has_method("begin_placement"))
	if not view.has_method("begin_placement"):
		g.remove_child(view)
		view.free()
		return
	var t = view.get("_touch")
	var placed := []
	view.placement_requested.connect(func(p: Dictionary) -> void: placed.append(p.duplicate(true)))
	var center := view._camera.unproject_position(Vector3.ZERO)
	var next := view._camera.unproject_position(Vector3(1.13, 0, 0.42))
	view.begin_placement("table", center)
	_finger(view, 3, center, true)
	_finger_drag(view, 3, next, next - center)
	var ghost: Dictionary = t._ghost.duplicate(true)
	var target := view._target
	_finger(view, 7, center, true)
	_finger_drag(view, 7, center + Vector2(100, 100), Vector2(100, 100))
	_finger(view, 7, center, false)
	Selftest.check("hv2 secondary touch cannot move ghost camera or commit", t._ghost == ghost and view._target == target and placed.is_empty())
	# Touch-emulated mouse must not place a second copy.
	_mouse(view, next, false)
	Selftest.check("hv2 mouse release cannot commit touch-owned ghost", placed.is_empty())
	_finger(view, 3, next, false)
	Selftest.check("hv2 primary touch releases exactly one snapped placement", placed.size() == 1 and placed[0]["x"] == 1.1
		and placed[0]["z"] == 0.4 and not t.ghost_exists() and not t.ghost_valid())
	view.set_layout([_record("bed")])
	view.begin_placement("table", center)
	_mouse(view, center, true)
	Selftest.check("hv2 new occupied ghost stays red without push out", not t.ghost_valid())
	_mouse(view, center, false)
	Selftest.check("hv2 invalid release leaves no placement or stale last id", placed.size() == 1 and t.last_placed_id == "" and not t.ghost_valid())
	view.set_layout([])
	view.begin_placement("table", center)
	_mouse(view, center, true)
	_motion(view, next, next - center)
	_mouse(view, next, false)
	Selftest.check("hv2 mouse motion and release move tray ghost", placed.size() == 2 and placed[1]["x"] == 1.1)
	var outside := view._camera.unproject_position(Vector3(10, 0, 10))
	view.begin_placement("table", outside)
	_mouse(view, outside, true)
	_mouse(view, outside, false)
	Selftest.check("hv2 far outside tray hit is rejected not clamped", placed.size() == 2)
	# Pinch spread magnifies, contraction shrinks, midpoint motion pans.
	view.cancel_placement()
	_finger(view, 0, Vector2(170, 480), true)
	_finger(view, 1, Vector2(370, 480), true)
	_finger_drag(view, 1, Vector2(470, 480), Vector2(100, 0))
	Selftest.check("hv2 two finger spread zooms in", view._zoom > 1.0)
	var zoom := view._zoom
	_finger_drag(view, 1, Vector2(390, 480), Vector2(-80, 0))
	Selftest.check("hv2 pinch contraction zooms out", view._zoom < zoom)
	target = view._target
	_finger_drag(view, 0, Vector2(190, 500), Vector2(20, 20))
	_finger_drag(view, 1, Vector2(410, 500), Vector2(20, 20))
	Selftest.check("hv2 pinch midpoint pans camera", view._target != target)
	view.cancel_placement()
	target = view._target
	_finger_drag(view, 1, Vector2(500, 600), Vector2(90, 100))
	Selftest.check("hv2 canceled gesture cannot leak panning", view._target == target and t._fingers.is_empty() and not t._panning)
	view.reset_camera()
	# Wall height and real geometry changes on both planes.
	view.begin_placement("window", view._camera.unproject_position(Vector3(-Placement.ROOM_HALF, 1.1, 0)))
	_mouse(view, center, true)
	# Окно в метриках оригинала занимает 1,074 м из стены 2,4 м, поэтому центр
	# живёт в коридоре [0,54; 1,86] и проба обязана попасть внутрь: иначе clamp
	# подменит высоту, и проверка «высота указателя не теряется» станет ложью.
	# Начало (1,1) и проба (1,2) различимы, чтобы тест краснел, если движение не
	# обновляет призрак.
	var wall_at := view._camera.unproject_position(Vector3(-Placement.ROOM_HALF, 1.2, 0))
	_motion(view, wall_at, Vector2(0, -40))
	Selftest.check("hv2 wall pointer preserves vertical y on left plane", t._ghost["wall"] == 0 and absf(t._ghost["y"] - 1.2) < 0.01)
	var old_mesh: Mesh = view._ghost_node._sprite.mesh
	var old_refl_mesh: Mesh = view._ghost_node._reflection.mesh
	wall_at = view._camera.unproject_position(Vector3(0, 1.3, -Placement.ROOM_HALF))
	_motion(view, wall_at, Vector2(40, 0))
	Selftest.check("hv2 wall switch rebuilds sprite and reflection geometry", t._ghost["wall"] == 1
		and view._ghost_node._sprite.mesh != old_mesh \
		and view._ghost_node._reflection.mesh != old_refl_mesh)
	old_mesh = view._ghost_node._sprite.mesh
	_motion(view, wall_at + Vector2(1, 0), Vector2(1, 0))
	Selftest.check("hv2 ordinary wall motion reuses mesh", view._ghost_node._sprite.mesh == old_mesh)
	view.cancel_placement()
	Selftest.check("hv2 wall ray rejects beyond span", view.raycast_wall(view._camera.unproject_position(Vector3(-Placement.ROOM_HALF, 1, 10))).is_empty())
	# Large projected extents are pickable, not just a 44px center disk.
	view.set_layout([_record("bed")])
	var edge := view._camera.unproject_position(Vector3(0.65, 0.35, 0.5))
	Selftest.check("hv2 furniture picking includes projected extents", view.pick_item(edge) == 0)
	view.set_layout([_record("table_herbs"), _record("table", 0.1)])
	var pick_at := view._camera.unproject_position(Vector3(0, 0.35, 0))
	_mouse(view, pick_at, true)
	_motion(view, view._camera.unproject_position(Vector3(-0.15, 0, 0)), Vector2(-20, 0))
	Selftest.check("hv2 overlapping selected item can escape through real drag", t.ghost_exists() and t.ghost_valid() and Placement.move_allowed(view.placements[0], t._ghost, view.placements, 0))
	_motion(view, view._camera.unproject_position(Vector3(-1.13, 0, 0)), Vector2(-60, 0))
	_mouse(view, view._camera.unproject_position(Vector3(-1.13, 0, 0)), false)
	Selftest.check("hv2 selected move persists exact release snap", view.placements[0]["x"] == -1.1 and view.selected_index() == 0)
	view.set_layout(view.placements.duplicate(true))
	Selftest.check("hv2 equal refresh preserves selection", view.selected_index() == 0)
	view.set_layout([])
	Selftest.check("hv2 real rebuild clears stale selection", view.selected_index() == -1 and t.selected == -1)
	view.begin_placement("table", center)
	view.read_only = true
	Selftest.check("hv2 read only transition clears gesture state", not t.ghost_exists() and t._fingers.is_empty())
	view.begin_placement("table", center)
	_mouse(view, center, true)
	_mouse(view, center, false)
	Selftest.check("hv2 read only input leaves layout unchanged", view.placements.is_empty())
	view.read_only = false
	view.set_built(false)
	view.begin_placement("table", center)
	Selftest.check("hv2 unbuilt cannot start ghost", not t.ghost_exists())
	view.set_built(true)
	var full := Demo.full_house_layout()
	var all_valid := full.size() == 40
	for i in full.size():
		all_valid = all_valid and Placement.valid(full[i], full, i)
	view.set_layout(full)
	var reflections := 0
	var shadows := 0
	for node in view._items:
		reflections += int(node._reflection != null)
		shadows += int(node._shadow != null)
	Selftest.check("hv2 stress grid validates all forty placements", all_valid)
	Selftest.check("hv2 stress instantiates forty reflections and shadows", view._items.size() == 40 and reflections == 40 and shadows == 40)
	g.remove_child(view)
	view.free()
	var h := g._home
	h._cosmetic_house = true
	h.house_unlocked = ["table", "rug_alt"]
	h.house_placements.assign([_record("table")])
	h._open_house_screen()
	h._house_room.highlight(0)
	Selftest.check("hv2 selected toolbar visible with touch targets", h._house_toolbar.visible and h._house_flip_btn.custom_minimum_size.y >= 48)
	h._house_room.flip_selected()
	Selftest.check("hv2 toolbar flip reaches save model and shader", h.house_placements[0]["flip"]
		and h._house_room._items[0]._sprite_mat.get_shader_parameter("flip_x"))
	var moved := _record("table", 1.13, 0.42)
	h._house_room.commit_move(0, moved)
	Selftest.check("hv2 saved move and room use identical snapped record", h.house_placements == h._house_room.placements and h.house_placements[0]["x"] == 1.1
		and g._saves._house_block()["house_placements"] == h.house_placements)
	h._open_house_tray()
	h._set_house_tray_progress(1.0)
	Selftest.check("hv2 toolbar stays usable above open tray", h._house_toolbar.visible
		and h._house_toolbar.get_global_rect().end.y <= h._house_tray.get_global_rect().position.y + 0.5)
	h._close_house_tray()
	Selftest.check("hv2 closing tray keeps selected toolbar", h._house_toolbar.visible)
	h._house_room.remove_selected()
	Selftest.check("hv2 toolbar remove persists and hides toolbar", h.house_placements.is_empty() and not h._house_toolbar.visible)
	h._place_from_tray("rug_alt")
	var home_t = h._house_room._touch
	h._open_house_tray()
	Selftest.check("hv2 returning to tray cancels placement", not home_t.ghost_exists())
	h._close_house_tray()
	for i in 40:
		h.house_placements.append(_record("rug_alt"))
	h._refresh_house_screen()
	h._place_from_tray("rug_alt")
	_mouse(h._house_room, h._house_room._camera.unproject_position(Vector3.ZERO), true)
	_mouse(h._house_room, h._house_room._camera.unproject_position(Vector3.ZERO), false)
	Selftest.check("hv2 rejected 41st release leaves last placed id empty", h.house_placements.size() == 40 and home_t.last_placed_id == "")
	h._close_house_screen()
	Selftest.check("hv2 closing screen clears toolbar and pointer state", not h._house_toolbar.visible and home_t._fingers.is_empty() and not home_t.ghost_exists())


static func _final() -> void:
	var script: Script = load("res://game/home/home.gd")
	var legacy := []
	for p in script.get_script_property_list():
		if String(p.get("name", "")) in ["house_furniture", "house_layout", "house_owned"]:
			legacy.append(p["name"])
	Selftest.check("hv2 legacy Home properties removed", legacy.is_empty())
	var decor: Script = load("res://game/data/decor.gd")
	Selftest.check("hv2 legacy decor constant removed", not decor.get_script_constant_map().has("DECOR"))
