extends SceneTree

func _initialize() -> void:
	var script: Script = load("res://game/ui/avatar.gd")
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/avatar_reference.json"))
	var failed := 0
	if script.get_script_method_list().filter(func(m): return m.name == "portrait_svg").is_empty():
		printerr("FAIL native SVG portrait renderer is missing")
		quit(1)
		return
	for c in fixture.cases:
		var actual: Dictionary = script.call("spec_for", c.seed, c.gender)
		var expected: Dictionary = c.spec.duplicate()
		for key in expected:
			if expected[key] is float:
				expected[key] = int(expected[key])
		if actual != expected:
			printerr("FAIL reference ", c.seed, " ", c.gender, " ", actual, " expected ", c.spec)
			failed += 1
	var rendered: Array = []
	for p in fixture.portraits:
		var svg: String = script.call("portrait_svg", p.spec)
		rendered.append({"spec": p.spec, "svg": svg, "reference": p.svg})
		if _shapes(svg) != _shapes(p.svg):
			printerr("FAIL approved SVG shapes ", p.spec.archetype, " ", p.spec.hairStyle)
			failed += 1
		var image := Image.new()
		var err := image.load_svg_from_string(svg, 2.0)
		if err != OK or image.get_width() != 360 or image.get_pixel(0, 0).a > 0.0 or image.get_pixel(180, 176).a < 0.9:
			printerr("FAIL raster ", p.spec.archetype, " ", err)
			failed += 1
		for key in ["face", "nose", "expression", "outfit", "accessory"]:
			var changed: Dictionary = p.spec.duplicate()
			changed[key] = (int(changed[key]) + 1) % (4 if key in ["expression", "accessory"] else 3)
			if script.call("portrait_svg", changed) == svg:
				printerr("FAIL unchanged geometry ", key)
				failed += 1
	if OS.has_environment("AVATAR_PARITY_OUTPUT"):
		var output := FileAccess.open(OS.get_environment("AVATAR_PARITY_OUTPUT"), FileAccess.WRITE)
		output.store_string(JSON.stringify(rendered))
	print("Avatar native test: ", failed, " failures; ", fixture.cases.size(), " reference vectors; ", fixture.portraits.size(), " raster portraits")
	quit(1 if failed else 0)

func _shapes(svg: String) -> Array:
	var parser := XMLParser.new()
	parser.open_buffer(svg.to_utf8_buffer())
	var shapes: Array = []
	var in_defs := false
	while parser.read() == OK:
		if parser.get_node_type() == XMLParser.NODE_ELEMENT_END and parser.get_node_name() == "defs":
			in_defs = false
		if parser.get_node_type() != XMLParser.NODE_ELEMENT:
			continue
		var node := parser.get_node_name()
		if node == "defs":
			in_defs = true
		if in_defs or node not in ["path", "circle", "ellipse"]:
			continue
		var attrs := {"tag": node}
		for i in parser.get_attribute_count():
			attrs[parser.get_attribute_name(i)] = parser.get_attribute_value(i)
		shapes.append(attrs)
	return shapes
