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
	# дальше задачи добавляют свои секции


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
	var wrong_size: Array = []
	for id in HouseItems.ITEMS:
		var tex: Texture2D = load(String(HouseItems.ITEMS[id]["sprite"]))
		if tex == null or tex.get_width() != 512 or tex.get_height() != 512:
			wrong_size.append(String(id))
	Selftest.check("hv2 every sprite is a 512 px square canvas", wrong_size.is_empty())
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
	Selftest.check("hv2 room view built the glb", view._room != null and view._mirror != null)
	Selftest.check("hv2 room aabb is non-empty", view._room_aabb.size.x > 6.0 and view._room_aabb.size.y > 2.0)
	Selftest.check("hv2 room mirror flips y",
		view._mirror != null and is_equal_approx(view._mirror.scale.y, -1.0))
	view.set_built(true)
	view.set_layout(HouseLayout.default_placements())
	await g.get_tree().process_frame
	Selftest.check("hv2 nine items spawned", view._items.size() == 9)
	var first: FurnitureItem = view._items[0] if view._items.size() > 0 else null
	Selftest.check("hv2 item has a sprited box",
		first != null and first._sprite != null and first._sprite.mesh != null)
	Selftest.check("hv2 item has a mirrored copy with scale.y=-1",
		first != null and first._reflection != null and is_equal_approx(first._reflection.scale.y, -1.0))
	Selftest.check("hv2 item has a planar shadow", first != null and first._shadow != null)
	Selftest.check("hv2 camera fit is positive and covers the room",
		view._camera != null and view._fit_size > 5.0 and view._camera.size >= view._fit_size)
	# Проверка правки 4: порядок отрисовки — жёсткий контракт кадра
	# (зеркало −10, отражение −5, пол 0, тень +1, спрайт +5). Литералы, а не
	# константы кода: сверка с константой краснела бы только от её удаления.
	var order_ok := first != null \
		and first._sprite_mat != null and first._sprite_mat.render_priority == 5 \
		and first._reflection_mat != null and first._reflection_mat.render_priority == -5 \
		and first._shadow_mat != null and first._shadow_mat.render_priority == 1
	Selftest.check("hv2 draw order: reflection -5, shadow +1, sprite +5", order_ok)
	# Тотально: каждая видимая поверхность зеркала на −10 (пол в копии скрыт —
	# старая проверка пропускала поверхности с приоритетом 0).
	Selftest.check("hv2 draw order: every visible mirror surface is at -10",
		_mirror_surfaces_all_at(view, -10))
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
		planes_ok = want_y > 0.05 \
			and is_equal_approx(wall_item.position.y, want_y) \
			and is_equal_approx(floor_item.position.y, 0.0) \
			and wall_item._sprite.global_position.y > floor_item._sprite.global_position.y + 0.5
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
	Selftest.check("hv2 zoom clamps between fit and 2.2x",
		view._camera.size > before and view._camera.size <= fit * 2.2 + 0.001)
	view.zoom_at(100.0, Vector2(270, 480))
	Selftest.check("hv2 max zoom is fit * 2.2",
		is_equal_approx(view._camera.size, fit * 2.2))
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


static func _mirror_surfaces_all_at(view: RoomView, want: int) -> bool:
	if view._mirror == null or view._mirror.get_child_count() == 0:
		return false
	var surfaces := 0
	for node in (view._mirror.get_child(0) as Node).find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if not mi.visible:
			continue
		for i in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(i) as BaseMaterial3D
			if mat == null or mat.render_priority != want:
				return false
			surfaces += 1
	return surfaces > 0


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
	var room_a: Node3D = RoomBuilder.build(world_a).get("room")
	var room_b: Node3D = RoomBuilder.build(world_b).get("room")
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
	g._home.house_unlocked = ["bed", "shelf"]
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
	Selftest.check("hv2 catalog has 24 items", HouseItems.ITEMS.size() == 24)
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
		var want_wall := cat in ["window", "shelf", "fireplace"]
		walls_ok = walls_ok and bool(it.get("wall", false)) == want_wall
		if not is_reward:
			per_cat[cat] = int(per_cat.get(cat, 0)) + 1
			base_total += 1
	Selftest.check("hv2 catalog ids match keys", ids_ok)
	Selftest.check("hv2 catalog has 9 categories with 2 base variants each",
		per_cat.size() == 9 and base_total == 18 and not per_cat.values().has(1) and per_cat.values().max() == 2
		and per_cat.values().min() == 2)
	Selftest.check("hv2 every item has positive box/ppm/path and known category", fields_ok)
	Selftest.check("hv2 rewards are free, everything else costs ether", costs_ok)
	Selftest.check("hv2 wall flag matches category", walls_ok)
	var rewards := ["window_contract", "window_seal", "window_guild",
		"fireplace_ember", "fireplace_log", "fireplace_heart"]
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
	var bed := {"id": "bed", "x": 0.95, "z": -2.28, "y": 0.0, "flip": false, "wall": -1}
	var fp := Placement.footprint(bed)
	Selftest.check("hv2 bed footprint follows box", absf(fp.size.x - 1.7) < 0.001
		and absf(fp.size.y - 2.2) < 0.001)
	var shelf := {"id": "shelf", "x": -3.406, "z": 0.90, "y": 1.55, "flip": false, "wall": 0}
	var sfp := Placement.footprint(shelf)
	Selftest.check("hv2 wall footprint is depth x span",
		sfp.position.x >= -3.432 and sfp.position.x <= -3.405
		and absf(sfp.size.x - 0.25) < 0.001 and absf(sfp.size.y - 1.2) < 0.001)
	Selftest.check("hv2 clamp keeps floor item inside room",
		Placement.clamp_record({"id": "bed", "x": 99.0, "z": -99.0, "y": 5.0, "flip": false, "wall": -1})["x"] <= 3.431 - 0.02 - 0.85 + 0.001)
	Selftest.check("hv2 clamp pins wall item to its wall",
		is_equal_approx(float(Placement.clamp_record(shelf)["x"]), -3.431 + 0.125))
	Selftest.check("hv2 wall y stays inside the wall",
		float(Placement.clamp_record({"id": "window", "x": -3.4, "z": 0.0, "y": 9.0, "flip": false, "wall": 0})["y"]) <= 2.4 - 0.5 + 0.001)
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
		not Placement.valid({"id": "chair", "x": 1.9, "z": -0.5, "y": 0.0, "flip": false, "wall": -1}, [table]))
	Selftest.check("hv2 rug is a non-colliding floor layer",
		Placement.valid({"id": "chair", "x": -1.6, "z": -2.0, "y": 0.0, "flip": false, "wall": -1},
			[{"id": "rug", "x": -1.6, "z": -2.0, "y": 0.0, "flip": false, "wall": -1}]))
	Selftest.check("hv2 wall and floor items do not collide",
		Placement.valid(bed, [fireplace_placement()]))
	Selftest.check("hv2 move that reduces overlap is allowed",
		Placement.move_allowed({"id": "chair", "x": 1.9, "z": -0.5, "y": 0.0, "flip": false, "wall": -1},
			{"id": "chair", "x": 1.9, "z": 0.0, "y": 0.0, "flip": false, "wall": -1}, [table], -1))
	Selftest.check("hv2 push_out removes the overlap",
		Placement.valid(Placement.push_out(
			{"id": "chair", "x": 1.9, "z": -0.5, "y": 0.0, "flip": false, "wall": -1}, [table], -1), [table]))


static func _layout() -> void:
	var model := HouseLayout.new()
	Selftest.check("hv2 unlock validates id", not model.unlock("nope") and model.unlocked.is_empty())
	Selftest.check("hv2 unlock adds once", model.unlock("bed") and not model.unlock("bed")
		and model.unlocked == ["bed"])
	var p := {"id": "bed", "x": 0.95, "z": -2.28, "y": 0.0, "flip": false, "wall": -1}
	Selftest.check("hv2 add placement", model.add_placement(p) and model.placements.size() == 1)
	var full := HouseLayout.new()
	for i in HouseLayout.MAX_ITEMS:
		full.add_placement({"id": "chair", "x": 0.0, "z": 0.0, "y": 0.0, "flip": false, "wall": -1})
	Selftest.check("hv2 41st placement rejected",
		full.placements.size() == HouseLayout.MAX_ITEMS
		and not full.add_placement({"id": "chair", "x": 0.0, "z": 0.0, "y": 0.0, "flip": false, "wall": -1}))
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
	Selftest.check("hv2 layout B covers every category", by_cat.size() == 9)
	var satisfied := []
	for task in Game.HOUSE_TASKS:
		if Home.house_task_satisfied(task, seeded):
			satisfied.append(String(task["id"]))
	Selftest.check("hv2 layout B satisfies only the onboarding task",
		satisfied == ["hearth_on_rug"])
	var desk := {"id": "table", "x": 1.9, "z": -0.5, "y": 0.0, "flip": false, "wall": -1}
	var chair_far := {"id": "chair", "x": 1.9, "z": 0.5, "y": 0.0, "flip": false, "wall": -1}
	var chair_near := {"id": "chair", "x": 1.9, "z": -0.1, "y": 0.0, "flip": false, "wall": -1}
	Selftest.check("hv2 near rule rejects a 0.3 m gap",
		not Home.house_task_satisfied(_task("chair_at_table"), [desk, chair_far]))
	Selftest.check("hv2 near rule accepts a zero gap",
		Home.house_task_satisfied(_task("chair_at_table"), [desk, chair_near]))
	var bed := {"id": "bed", "x": 0.95, "z": -2.28, "y": 0.0, "flip": false, "wall": -1}
	var shelf_low := {"id": "shelf", "x": 0.95, "z": -2.28, "y": 1.15, "flip": false, "wall": 1}
	var shelf_side := {"id": "shelf", "x": 2.5, "z": -2.28, "y": 1.55, "flip": false, "wall": 1}
	Selftest.check("hv2 over rule needs y >= 1.2",
		not Home.house_task_satisfied(_task("shelf_over_bed"), [bed, shelf_low]))
	Selftest.check("hv2 over rule needs the projection to cross",
		not Home.house_task_satisfied(_task("shelf_over_bed"), [bed, shelf_side]))
	Selftest.check("hv2 over rule passes above the bed",
		Home.house_task_satisfied(_task("shelf_over_bed"),
			[bed, {"id": "shelf", "x": 0.95, "z": -2.28, "y": 1.55, "flip": false, "wall": 1}]))
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
	g._home.house_unlocked.clear()
	Selftest.check("hv2 contract reward unlocks only the id",
		g._home._unlock_item("window_contract") and g._home.house_unlocked == ["window_contract"])
	Selftest.check("hv2 second unlock is a no-op", not g._home._unlock_item("window_contract"))
	g._home.house_unlocked.clear()
	for rid in Game.CIRCLE_DECOR_REWARDS.values():
		g._home._unlock_item(String(rid))
	Selftest.check("hv2 circle rewards unlock all three fireplace ids",
		g._home.house_unlocked.size() == 3 and g._home.house_unlocked.has("fireplace_heart"))
	g._home.house_unlocked.clear()


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


static func fireplace_placement() -> Dictionary:
	return {"id": "fireplace", "x": -1.6, "z": -3.156, "y": 0.0, "flip": false, "wall": 1}
