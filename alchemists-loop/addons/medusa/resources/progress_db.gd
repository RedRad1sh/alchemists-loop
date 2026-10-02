@tool
## Manages player-specific progression by tracking unlocked resources and their current levels.
##
## ProgressDB acts as a bridge between static data in [MedusaDB] and persistent player state.
## It handles unlocking new items/skills and managing their level-based upgrades.
class_name ProgressDB extends Resource


@export var database: MedusaDB        ## Reference to the global [MedusaDB] containing resource metadata.
@export var registry: Dictionary = {} ## Saves progress as: `ID (StringName) : Level (int)`

signal resource_unlocked(id: StringName)                 ## Emitted when a resource is first added to the registry.
signal resource_upgraded(id: StringName, new_level: int) ## Emitted when the level of the existing resource increases.


## Unlocks a resource by setting its level to 1.
## Does nothing if the resource is already unlocked.
func unlock(id: StringName) -> void:
	if not registry.has(id):
		registry[id] = 1
		resource_unlocked.emit(id)

## Increments the level of a resource if it is already unlocked.
## The upgrade is validated against the [member MedusaDB.database] to ensure
## it doesn't exceed the max_level defined in the [AtomData].
func upgrade(id: StringName) -> void:
	if registry.has(id):
		var current_level = registry[id]
		var data = database.get_resource(id)

		if data and current_level < data.progression.max_level:
			registry[id] += 1
			resource_upgraded.emit(id, registry[id])

## Returns the current level of the resource associated with [param id].
## Returns `0` if the resource has not been unlocked yet.
func get_level(id: StringName) -> int:
	return registry.get(id, 0)

## Returns `true` if the resource has been unlocked (level > 0).
func is_unlocked(id: StringName) -> bool:
	return registry.has(id)
