@tool
## Base data container representing a unique game element (skill, item, unit, etc.).
##
## AtomData defines the static properties and metadata of a resource.
## It is intended to be used with [MedusaDB] for registration and [ProgressDB] for leveling.
class_name AtomData extends Resource

@export_category("Atom")
@export var id: StringName = &""         ## Unique identifier used in databases ("skill_fireball").
@export var title: String = "New Skill"  ## Display name for the UI ("Fireball").
@export var tags: Array[StringName] = [] ## Classification tags for filtering or logic (["fire", "magic"]).
## Defines progression constraints.
## Expected keys: `max_level (int)`, `cost`
@export var progression: Dictionary = {
	"max_level": 1,
	"cost": 1
	}

@export_group("Visuals")
@export var icon: Texture2D
@export var locked_animation_library: AnimationLibrary
@export var unlocked_animation_library: AnimationLibrary
@export var available_animation_library: AnimationLibrary
@export var hidden_animation_library: AnimationLibrary
@export var disabled_animation_library: AnimationLibrary
