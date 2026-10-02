@tool
## A centralized registry for managing AtomData resources using reference counting.
##
## MedusaDB tracks unique resources by their StringName ID and maintains a count
## of how many times each resource has been registered.
class_name MedusaDB extends Resource


class ResourceEntry:          ## Internal wrapper to store the resource data alongside its reference count.
	var data: AtomData
	var count: int

	func _init(data: AtomData, count: int):
		self.data = data
		self.count = count
var registry: Dictionary = {} ## The main storage: maps [StringName] (Resource ID) to its [ResourceEntry].


## Adds a resource to the database.
## If the resource ID already exists, increments its reference count.
func register_resource(data: AtomData) -> void:
	if not data or data.id == &"": return

	if registry.has(data.id):
		var entry: ResourceEntry = registry[data.id]
		entry.count += 1
	else:
		registry[data.id] = ResourceEntry.new(data, 1)

## Decrements the reference count of a resource.
## If the count reaches zero, the resource is removed from the registry.
func unregister_resource(data: AtomData) -> void:
	if not data or data.id == &"": return

	if registry.has(data.id):
		var entry: ResourceEntry = registry[data.id]
		entry.count -= 1

		if entry.count <= 0: registry.erase(data.id)

## Returns `true` if a resource with the given [param id] exists in the database.
func has_resource(id: StringName) -> bool:
	return registry.has(id)

## Returns the [AtomData] associated with the given [param id].
## Returns `null` if the ID is not found.
func get_resource(id: StringName) -> AtomData:
	if registry.has(id): return registry[id].data
	return null

## Returns the current number of active registrations for the specified [param id].
func get_resource_count(id: StringName) -> int:
	if registry.has(id): return registry[id].count
	return 0

## Returns an [Array] containing all unique [AtomData] currently stored in the registry.
func get_all_resources() -> Array[AtomData]:
	var result: Array[AtomData] = []
	for key in registry: result.append(registry[key].data)
	return result

## Clears all entries from the database.
## Useful for manual cleanup during scene transitions or level changes.
func clear_database() -> void:
	registry.clear()
