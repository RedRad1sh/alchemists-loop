extends Control
class_name AchievementMapView

const GRAPH_SCRIPT = preload("res://addons/medusa/nodes/graph.gd")
const MAP_ATOM_SCRIPT = preload("res://game/meta/achievement_map_atom.gd")
const MAP_LINE_SCRIPT = preload("res://game/meta/achievement_map_line.gd")

const NODE_LOCKED := 0
const NODE_AVAILABLE := 1
const NODE_UNLOCKED := 2
const GRAPH_TOP := 8.0
const GRAPH_BOTTOM := 12.0
const NODE_ROW_STEP := 76.0

const SECTION_ORDER := ["atlas", "workshop", "world", "mastery", "spirit", "echoes", "other"]
const SECTION_TITLES := {
	"atlas": "АТЛАС АЛХИМИКА",
	"workshop": "КОТЁЛ И МАСТЕРСТВО",
	"world": "ОТКРЫТИЯ МИРА",
	"mastery": "СТИХИИ И УЛУЧШЕНИЯ",
	"spirit": "СВЕТИК",
	"echoes": "ОТГОЛОСКИ МИРА",
	"other": "НОВЫЕ ПУТИ",
}
const SECTION_ACCENTS := {
	"atlas": Color(0.34, 0.82, 0.73),
	"workshop": Color(0.94, 0.66, 0.39),
	"world": Color(0.61, 0.72, 0.98),
	"mastery": Color(0.89, 0.76, 0.46),
	"spirit": Color(0.89, 0.61, 0.82),
	"echoes": Color(0.52, 0.78, 0.88),
	"other": Color(0.70, 0.73, 0.80),
}
const REGION_BY_KIND := {
	"items": "atlas",
	"recipes": "atlas",
	"successes": "workshop",
	"fails": "workshop",
	"world_first": "world",
	"challenge": "world",
	"legend": "world",
	"upgrades": "mastery",
	"sets": "mastery",
	"affinity": "spirit",
	"resonance": "echoes",
}
const KIND_ORDER := [
	"items",
	"recipes",
	"successes",
	"fails",
	"world_first",
	"challenge",
	"legend",
	"upgrades",
	"sets",
	"affinity",
	"resonance",
]
const KIND_TITLES := {
	"items": "ВЕЩЕСТВА",
	"recipes": "РЕЦЕПТЫ",
	"successes": "УДАЧНЫЕ ВАРКИ",
	"fails": "ТУМАНЫ",
	"world_first": "ПЕРВООТКРЫТИЯ",
	"challenge": "ЦЕЛИ ДНЯ",
	"legend": "ЛЕГЕНДЫ",
	"upgrades": "УЛУЧШЕНИЯ",
	"sets": "КОМПЛЕКТЫ СТИХИЙ",
	"affinity": "ДРУЖБА",
	"resonance": "ОТГОЛОСКИ",
}
const KIND_GLYPHS := {
	"items": "crystal",
	"recipes": "glass",
	"successes": "steam",
	"fails": "mist",
	"world_first": "spark",
	"challenge": "lightning",
	"legend": "gold",
	"upgrades": "tool",
	"sets": "sun",
	"affinity": "flower",
	"resonance": "ring3",
}

var _game: Game
var _region_list: VBoxContainer
var _summary_title: Label
var _summary_hint: Label
var _detail_title: Label
var _detail_state: Label
var _detail_body: Label
var _detail_reward: Label

var _node_by_id: Dictionary = {}
var _entry_by_id: Dictionary = {}
var _status_by_id: Dictionary = {}
var _track_count_labels: Dictionary = {}
var _section_count_labels: Dictionary = {}
var _graph_specs: Array = []
var _structure_signature := ""
var _selected_id := ""


func setup(game: Game) -> void:
	_game = game
	mouse_filter = Control.MOUSE_FILTER_PASS
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build_layout()
	refresh(true)


func _ready() -> void:
	# Graph._ready() defaults to STOP; reset it after Medusa's setup so screen
	# drags can bubble through to the containing ScrollContainer on mobile.
	for spec in _graph_specs:
		_configure_graph_after_ready(spec["graph"])
	call_deferred("_layout_all_graphs")


func _build_layout() -> void:
	var margin := MarginContainer.new()
	margin.name = "MapMargins"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 4)
	margin.add_theme_constant_override("margin_right", 4)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 4)
	margin.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(margin)

	var column := VBoxContainer.new()
	column.name = "MapColumn"
	column.add_theme_constant_override("separation", 7)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.mouse_filter = Control.MOUSE_FILTER_PASS
	margin.add_child(column)

	var summary := PanelContainer.new()
	summary.name = "MapSummary"
	summary.add_theme_stylebox_override(
		"panel", _game._panel_style(Color(0.08, 0.13, 0.18, 0.96), 14)
	)
	summary.mouse_filter = Control.MOUSE_FILTER_PASS
	column.add_child(summary)
	var summary_box := VBoxContainer.new()
	summary_box.add_theme_constant_override("separation", 1)
	summary_box.mouse_filter = Control.MOUSE_FILTER_PASS
	summary.add_child(summary_box)
	_summary_title = _game._label("", 13)
	_summary_title.add_theme_color_override("font_color", Color(0.96, 0.84, 0.57))
	summary_box.add_child(_summary_title)
	_summary_hint = _game._label(
		"Коснись знака: здесь цель, прогресс и награда. Перетаскивай карту, чтобы прокручивать.", 10
	)
	_summary_hint.add_theme_color_override("font_color", Color(0.62, 0.72, 0.77))
	summary_box.add_child(_summary_hint)

	var scroll := ScrollContainer.new()
	scroll.name = "AchievementMapScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	column.add_child(scroll)
	_region_list = VBoxContainer.new()
	_region_list.name = "AchievementRegions"
	_region_list.add_theme_constant_override("separation", 9)
	_region_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_region_list.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_region_list.mouse_filter = Control.MOUSE_FILTER_PASS
	scroll.add_child(_region_list)

	var detail_panel := PanelContainer.new()
	detail_panel.name = "AchievementDetails"
	detail_panel.custom_minimum_size = Vector2(0.0, 126.0)
	detail_panel.add_theme_stylebox_override(
		"panel", _game._panel_style(Color(0.07, 0.11, 0.16, 0.98), 14)
	)
	detail_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(detail_panel)
	var detail_box := VBoxContainer.new()
	detail_box.add_theme_constant_override("separation", 1)
	detail_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	detail_panel.add_child(detail_box)
	_detail_title = _game._label("Выбери знак на карте", 13)
	_detail_title.add_theme_color_override("font_color", Color(0.95, 0.88, 0.68))
	detail_box.add_child(_detail_title)
	_detail_state = _game._label("", 10)
	_detail_state.add_theme_color_override("font_color", Color(0.60, 0.83, 0.77))
	detail_box.add_child(_detail_state)
	_detail_body = _game._label("", 10)
	_detail_body.add_theme_color_override("font_color", Color(0.75, 0.81, 0.83))
	detail_box.add_child(_detail_body)
	_detail_reward = _game._label("", 10)
	_detail_reward.add_theme_color_override("font_color", Color(0.91, 0.78, 0.50))
	detail_box.add_child(_detail_reward)


func refresh(force_rebuild: bool = false) -> void:
	if _game == null or _region_list == null:
		return
	var sections := _collect_sections()
	var signature := _make_structure_signature(sections)
	if force_rebuild or signature != _structure_signature:
		_structure_signature = signature
		_rebuild_regions(sections)
	_update_map_state(sections)
	_refresh_summary()


func compute_track_states(entries: Array, completed: Dictionary) -> Dictionary:
	# Completion is authoritative; among unfinished milestones, every node at
	# the nearest remaining threshold is available and later thresholds stay shut.
	var ordered: Array = entries.duplicate()
	ordered.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool:
			var left_param := int(left.get("param", 1))
			var right_param := int(right.get("param", 1))
			if left_param == right_param:
				return String(left.get("id", "")) < String(right.get("id", ""))
			return left_param < right_param
	)
	var result: Dictionary = {}
	var next_threshold := -1
	for entry in ordered:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var node_id := String(entry.get("id", ""))
		if node_id.is_empty():
			continue
		if completed.has(node_id):
			result[node_id] = NODE_UNLOCKED
			continue
		var threshold := int(entry.get("param", 1))
		if next_threshold == -1:
			next_threshold = threshold
		result[node_id] = NODE_AVAILABLE if threshold == next_threshold else NODE_LOCKED
	return result


func _collect_sections() -> Array:
	var buckets: Dictionary = {}
	for raw in Game.ACHIEVEMENTS:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var achievement: Dictionary = raw
		var node_id := String(achievement.get("id", ""))
		if node_id.is_empty():
			continue
		var kind := String(achievement.get("kind", "other"))
		var region := String(REGION_BY_KIND.get(kind, "other"))
		var track := _ensure_track(buckets, region, kind)
		var entries: Array = track["entries"]
		var entry: Dictionary = {
			"id": node_id,
			"title": String(achievement.get("title", node_id)),
			"kind": kind,
			"param": int(achievement.get("param", 1)),
			"achievement": achievement,
			"is_resonance": false,
		}
		entries.append(entry)
		track["entries"] = entries

	var resonance_track := _ensure_track(buckets, "echoes", "resonance")
	var resonance_entries: Array = resonance_track["entries"]
	for raw_mile in Game.RES_MILES:
		var mile := int(raw_mile)
		var resonance_entry: Dictionary = {
			"id": "res_%d" % mile,
			"title": "%d повторов эха" % mile,
			"kind": "resonance",
			"param": mile,
			"is_resonance": true,
		}
		resonance_entries.append(resonance_entry)
	resonance_track["entries"] = resonance_entries

	var sections: Array = []
	for region in SECTION_ORDER:
		if not buckets.has(region):
			continue
		var tracks_by_kind: Dictionary = buckets[region]
		var kinds: Array = tracks_by_kind.keys()
		kinds.sort_custom(
			func(left: String, right: String) -> bool:
				var left_order := KIND_ORDER.find(left)
				var right_order := KIND_ORDER.find(right)
				if left_order == -1:
					left_order = KIND_ORDER.size()
				if right_order == -1:
					right_order = KIND_ORDER.size()
				if left_order == right_order:
					return left < right
				return left_order < right_order
		)
		var tracks: Array = []
		for kind_variant in kinds:
			var kind := String(kind_variant)
			var track: Dictionary = tracks_by_kind[kind]
			var entries: Array = track["entries"]
			entries.sort_custom(
				func(left: Dictionary, right: Dictionary) -> bool:
					var left_param := int(left.get("param", 1))
					var right_param := int(right.get("param", 1))
					if left_param == right_param:
						return String(left.get("id", "")) < String(right.get("id", ""))
					return left_param < right_param
			)
			track["entries"] = entries
			tracks.append(track)
		var section: Dictionary = {
			"id": region,
			"title": String(SECTION_TITLES.get(region, SECTION_TITLES["other"])),
			"accent": SECTION_ACCENTS.get(region, SECTION_ACCENTS["other"]),
			"tracks": tracks,
		}
		sections.append(section)
	return sections


func _ensure_track(buckets: Dictionary, region: String, kind: String) -> Dictionary:
	if not buckets.has(region):
		buckets[region] = {}
	var tracks: Dictionary = buckets[region]
	if not tracks.has(kind):
		tracks[kind] = {
			"kind": kind,
			"title": String(KIND_TITLES.get(kind, kind.replace("_", " ").to_upper())),
			"entries": [],
		}
		buckets[region] = tracks
	return tracks[kind]


func _make_structure_signature(sections: Array) -> String:
	var parts := PackedStringArray()
	for section in sections:
		parts.append(String(section["id"]))
		for track in section["tracks"]:
			parts.append(String(track["kind"]))
			for entry in track["entries"]:
				parts.append(
					(
						"%s:%s:%d:%s"
						% [
							String(entry["id"]),
							String(entry["kind"]),
							int(entry["param"]),
							String(entry["title"])
						]
					)
				)
	return "|".join(parts)


func _rebuild_regions(sections: Array) -> void:
	for child in _region_list.get_children():
		_region_list.remove_child(child)
		child.queue_free()
	_node_by_id.clear()
	_entry_by_id.clear()
	_status_by_id.clear()
	_track_count_labels.clear()
	_section_count_labels.clear()
	_graph_specs.clear()
	for section in sections:
		_build_section(section)
	if is_inside_tree():
		for spec in _graph_specs:
			_configure_graph_after_ready(spec["graph"])
		call_deferred("_layout_all_graphs")


func _build_section(section: Dictionary) -> void:
	var region := String(section["id"])
	var accent: Color = section["accent"]
	var panel := PanelContainer.new()
	panel.name = "Region_%s" % region
	panel.add_theme_stylebox_override(
		"panel", _game._panel_style(Color(0.09, 0.14, 0.19, 0.96), 14)
	)
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.add_child(box)

	var heading := HBoxContainer.new()
	heading.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(heading)
	var title := _game._label(String(section["title"]), 12)
	title.add_theme_color_override("font_color", accent)
	title.add_theme_font_size_override("font_size", 12)
	heading.add_child(title)
	var section_count := _game._label("", 10)
	section_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	section_count.add_theme_color_override("font_color", Color(0.60, 0.70, 0.75))
	section_count.custom_minimum_size = Vector2(56.0, 0.0)
	heading.add_child(section_count)
	_section_count_labels[region] = section_count

	var tracks: Array = section["tracks"]
	var track_headers := HBoxContainer.new()
	track_headers.add_theme_constant_override("separation", 2)
	track_headers.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(track_headers)
	for track in tracks:
		var track_header := _game._label(String(track["title"]), 9)
		track_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		track_header.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		track_header.add_theme_color_override("font_color", Color(0.57, 0.68, 0.74))
		track_header.custom_minimum_size = Vector2(0.0, 24.0)
		track_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		track_headers.add_child(track_header)
		_track_count_labels[_track_key(region, String(track["kind"]))] = track_header

	var graph = GRAPH_SCRIPT.new()
	graph.name = "Graph_%s" % region
	graph.custom_minimum_size = Vector2(0.0, 100.0)
	graph.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	graph.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	graph.mouse_filter = Control.MOUSE_FILTER_PASS
	graph.physics_enabled = false
	graph.draw_sleep_system_enable = true
	graph.enable_start_up_modulation = false
	graph.drag_input = false
	graph.atom_click_input = true
	graph.background_click_input = false
	graph.multi_drag_enabled = false
	graph.focus_system = 1  # Graph.FocusSystem.GODOT
	graph.selection_mode = 1  # Graph.SelectionMode.SOLO
	graph.highlight_mode = 0  # Graph.HighlightMode.OFF
	graph.initial_focus_atom = null
	graph.set_process(false)
	graph.set_physics_process(false)
	var line_style = MAP_LINE_SCRIPT.new()
	var muted_line: Color = accent
	muted_line.a = 0.48
	line_style.line_color = muted_line
	line_style.highlighted_line_color = accent.lightened(0.22)
	graph.graph_lines = line_style

	var graph_tracks: Array = []
	var max_rows := 1
	for track in tracks:
		var entries: Array = track["entries"]
		max_rows = maxi(max_rows, entries.size())
		var state_map := _get_track_states(track)
		var atoms: Array = []
		var previous_atom = null
		for entry in entries:
			var node_id := String(entry["id"])
			var node_status := int(state_map.get(node_id, NODE_LOCKED))
			var atom = MAP_ATOM_SCRIPT.new()
			atom.name = node_id
			atom.setup(
				node_id, _glyph_for_kind(String(entry["kind"])), _entry_caption(entry), node_status
			)
			atom.clicked.connect(_on_map_node_clicked.bind(node_id))
			if previous_atom != null:
				previous_atom.connect_to(atom)
			previous_atom = atom
			graph.add_child(atom)
			atoms.append(atom)
			_node_by_id[node_id] = atom
			_entry_by_id[node_id] = entry
			_status_by_id[node_id] = node_status
		var graph_track: Dictionary = {
			"kind": String(track["kind"]),
			"entries": entries,
			"nodes": atoms,
		}
		graph_tracks.append(graph_track)

	var graph_height := GRAPH_TOP + float(max_rows - 1) * NODE_ROW_STEP + 76.0 + GRAPH_BOTTOM
	graph.custom_minimum_size = Vector2(0.0, graph_height)
	graph.resized.connect(_on_graph_resized.bind(graph, graph_tracks))
	box.add_child(graph)
	_region_list.add_child(panel)
	_graph_specs.append({"graph": graph, "tracks": graph_tracks})
	if graph.is_inside_tree():
		_configure_graph_after_ready(graph)
		call_deferred("_layout_graph", graph, graph_tracks)


func _get_track_states(track: Dictionary) -> Dictionary:
	var completed: Dictionary = {}
	for entry in track["entries"]:
		if _entry_is_done(entry):
			completed[String(entry["id"])] = true
	return compute_track_states(track["entries"], completed)


func _update_map_state(sections: Array) -> void:
	var next_selected_exists := false
	var first_available := ""
	for section in sections:
		var region := String(section["id"])
		var section_total := 0
		var section_done := 0
		for track in section["tracks"]:
			var kind := String(track["kind"])
			var track_key := _track_key(region, kind)
			var track_total := 0
			var track_done := 0
			var state_map := _get_track_states(track)
			for entry in track["entries"]:
				var node_id := String(entry["id"])
				var done := _entry_is_done(entry)
				var node_status := int(state_map.get(node_id, NODE_LOCKED))
				section_total += 1
				track_total += 1
				if done:
					section_done += 1
					track_done += 1
				if node_status == NODE_AVAILABLE and first_available.is_empty():
					first_available = node_id
				if node_id == _selected_id:
					next_selected_exists = true
				_entry_by_id[node_id] = entry
				_status_by_id[node_id] = node_status
				var atom = _node_by_id.get(node_id, null)
				if is_instance_valid(atom):
					atom.set_map_status(node_status)
					atom.set_caption(_entry_caption(entry))
					atom.map_selected = node_id == _selected_id
			var track_label: Label = _track_count_labels.get(track_key, null)
			if is_instance_valid(track_label):
				track_label.text = "%s  %d/%d" % [String(track["title"]), track_done, track_total]
		var section_label: Label = _section_count_labels.get(region, null)
		if is_instance_valid(section_label):
			section_label.text = "%d/%d" % [section_done, section_total]

	if not next_selected_exists:
		_selected_id = first_available
		if _selected_id.is_empty() and not _entry_by_id.is_empty():
			_selected_id = String(_entry_by_id.keys()[0])
	for node_id in _node_by_id:
		var atom = _node_by_id[node_id]
		if is_instance_valid(atom):
			atom.map_selected = String(node_id) == _selected_id
	var selected_entry: Dictionary = _entry_by_id.get(_selected_id, {})
	if not selected_entry.is_empty():
		_show_entry_details(selected_entry, int(_status_by_id.get(_selected_id, NODE_LOCKED)))
	else:
		_detail_title.text = "Достижений пока нет"
		_detail_state.text = ""
		_detail_body.text = "Новые пути появятся вместе с игровыми достижениями."
		_detail_reward.text = ""


func _refresh_summary() -> void:
	var completed := 0
	for raw in Game.ACHIEVEMENTS:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		if _game._progress_ui._ach_done.has(String(raw.get("id", ""))):
			completed += 1
	var echo_done := 0
	for mile in Game.RES_MILES:
		if _game._resonance._res_done.has(int(mile)):
			echo_done += 1
	_summary_title.text = (
		"Достижения %d/%d  ·  отголоски %d/%d"
		% [completed, Game.ACHIEVEMENTS.size(), echo_done, Game.RES_MILES.size()]
	)


func _show_entry_details(entry: Dictionary, node_status: int) -> void:
	var is_resonance := bool(entry.get("is_resonance", false))
	var target := maxi(1, int(entry.get("param", 1)))
	var progress := maxi(0, _entry_progress(entry))
	var done := _entry_is_done(entry)
	_detail_title.text = String(entry.get("title", "Достижение"))
	if done:
		_detail_state.text = "ВЫПОЛНЕНО"
		_detail_state.add_theme_color_override("font_color", Color(0.90, 0.77, 0.44))
	elif node_status == NODE_AVAILABLE:
		_detail_state.text = "СЛЕДУЮЩАЯ ВЕХА"
		_detail_state.add_theme_color_override("font_color", Color(0.50, 0.88, 0.77))
	else:
		_detail_state.text = "ЗАКРЫТО · сначала предыдущая веха"
		_detail_state.add_theme_color_override("font_color", Color(0.67, 0.72, 0.76))
	var requirement := _entry_requirement(entry)
	if requirement.is_empty():
		requirement = "Продолжай варить и открывать новое"
	var body := "%s\nПрогресс: %d/%d" % [requirement, mini(progress, target), target]
	if not done and node_status == NODE_LOCKED:
		body += "\nЭта ступень откроется после предыдущей в своей ветке."
	_detail_body.text = body
	if is_resonance:
		_detail_reward.text = "Награда: %s" % _game._resonance._res_mile_reward_text(target)
	else:
		var achievement: Dictionary = entry.get("achievement", {})
		_detail_reward.text = (
			"Награда: +%d ⚡ · навсегда +%d к капу и +%.3f/с"
			% [int(achievement.get("ether", 0)), Game.ACH_CAP, Game.ACH_REGEN]
		)


func _entry_is_done(entry: Dictionary) -> bool:
	if bool(entry.get("is_resonance", false)):
		return _game._resonance._res_done.has(int(entry.get("param", 0)))
	return _game._progress_ui._ach_done.has(String(entry.get("id", "")))


func _entry_progress(entry: Dictionary) -> int:
	if bool(entry.get("is_resonance", false)):
		return _game._resonance._res_total
	var achievement: Dictionary = entry.get("achievement", {})
	return _game._progress_ui._ach_progress(achievement)


func _entry_requirement(entry: Dictionary) -> String:
	if bool(entry.get("is_resonance", false)):
		return "Набери %d повторов чужих веществ" % int(entry.get("param", 1))
	var achievement: Dictionary = entry.get("achievement", {})
	return _game._progress_ui._ach_requirement(achievement)


func _entry_caption(entry: Dictionary) -> String:
	if String(entry.get("kind", "")) == "legend":
		return "★"
	return str(int(entry.get("param", 1)))


func _glyph_for_kind(kind: String) -> String:
	return String(KIND_GLYPHS.get(kind, "sigil5"))


func _track_key(region: String, kind: String) -> String:
	return "%s:%s" % [region, kind]


func _layout_all_graphs() -> void:
	for spec in _graph_specs:
		_layout_graph(spec["graph"], spec["tracks"])


func _on_graph_resized(graph: Control, tracks: Array) -> void:
	_layout_graph(graph, tracks)


func _layout_graph(graph: Control, tracks: Array) -> void:
	if not is_instance_valid(graph) or tracks.is_empty():
		return
	var graph_width := graph.size.x
	if graph_width <= 0.0:
		graph_width = maxf(280.0, _game.get_viewport_rect().size.x - 120.0)
	var lane_width := graph_width / float(tracks.size())
	for lane_index in tracks.size():
		var lane: Dictionary = tracks[lane_index]
		var atoms: Array = lane["nodes"]
		for row_index in atoms.size():
			var atom = atoms[row_index]
			var center_x := lane_width * (float(lane_index) + 0.5)
			atom.position = Vector2(
				center_x - atom.size.x * 0.5, GRAPH_TOP + float(row_index) * NODE_ROW_STEP
			)
	graph.queue_redraw()


func _configure_graph_after_ready(graph: Control) -> void:
	if not is_instance_valid(graph):
		return
	graph.mouse_filter = Control.MOUSE_FILTER_PASS
	graph.set_process(false)
	graph.set_physics_process(false)


func _on_map_node_clicked(_atom: Atom, node_id: String) -> void:
	_selected_id = node_id
	for candidate_id in _node_by_id:
		var atom = _node_by_id[candidate_id]
		if is_instance_valid(atom):
			atom.map_selected = String(candidate_id) == node_id
	var entry: Dictionary = _entry_by_id.get(node_id, {})
	if not entry.is_empty():
		_show_entry_details(entry, int(_status_by_id.get(node_id, NODE_LOCKED)))
	Sfx.click()
