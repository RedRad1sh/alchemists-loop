class_name SigilGeneratorRegistry
extends RefCounted

## Реестр генераторов центрального объекта.
##
## Ключ — строка result_type в рецепте. Регистрация:
##   SigilGeneratorRegistry.register(&"crystal", SigilGenCrystal.new())
## Никаких правок в ядре, карточке или рендере.

static var _registry: Dictionary = {}
static var _ready: bool = false


static func _ensure() -> void:
	if _ready:
		return
	_ready = true
	register(&"object", SigilGenObject.new())
	register(&"abstraction", SigilGenAbstraction.new())
	register(&"planet", SigilGenPlanet.new())
	register(&"creature", SigilGenCreature.new())
	register(&"relic", SigilGenRelic.new())


static func register(type_name: StringName, generator: SigilIconGenerator) -> void:
	_ensure()
	_registry[String(type_name)] = generator


static func unregister(type_name: StringName) -> void:
	_registry.erase(String(type_name))


static func has(type_name: StringName) -> bool:
	_ensure()
	return _registry.has(String(type_name))


static func get_generator(type_name: StringName) -> SigilIconGenerator:
	_ensure()
	if _registry.has(String(type_name)):
		return _registry[String(type_name)]
	push_warning("SigilGeneratorRegistry: тип '%s' не зарегистрирован, беру object" % type_name)
	return _registry.get("object", SigilGenObject.new())


static func types() -> PackedStringArray:
	_ensure()
	var out := PackedStringArray()
	for k in _registry.keys():
		out.append(str(k))
	out.sort()
	return out


static func describe() -> String:
	_ensure()
	var lines := PackedStringArray()
	for t in types():
		var g := get_generator(StringName(t))
		lines.append("%-13s %s" % [t, g.description()])
	return "\n".join(lines)
