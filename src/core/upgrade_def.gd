class_name UpgradeDef
extends Resource
## An upgrade bought in a module's exploded view. Installing it reveals the
## part node `part_node` of the module scene and applies `effects` once.
## See docs/CONTENT_PIPELINE.md ("Upgrades").
##
## Where the part comes from (first match wins):
##   1. an authored `Parts/<part_node>` in the module scene (Blender `part_*`
##      object, or a node placed by hand) — the part belongs to that module;
##   2. `mount`: Module spawns a ModulePart named `part_node` on the module's
##      `mount_<mount>` marker, built from `part_scene` (art) or the procedural
##      placeholder `part_kind` / `part_length` / `part_mirror`.
##
## Known effects (EFFECTS, summed over all installed upgrades):
##   power_output, power_draw          -> station power budget
##   food_decay, energy_decay, morale_decay -> added to Needs decay per hour

const EFFECTS: Array[StringName] = [
	&"power_output", &"power_draw", &"food_decay", &"energy_decay", &"morale_decay",
]

@export var id: StringName
@export var module_id: StringName
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var part_node: StringName
@export var cost: Dictionary[StringName, int] = {}
@export var minutes: float = 60.0
## Upgrade ids that must be installed first (on the same module).
@export var requires: Array[StringName] = []
@export var effects: Dictionary[StringName, float] = {}
## Story flags set when the upgrade is installed (encounters read them with
## flag("name")). The "upgraded" encounter trigger fires as well.
@export var sets_flags: Array[StringName] = []

@export_group("Mounted part")
## Marker `mount_<mount>` of the module scene where the part is spawned.
## Empty = the part is authored in the module scene (Parts/<part_node>).
@export var mount: StringName = &""
## Art for the part (a glTF / scene, palette materials). Unset = placeholder.
@export var part_scene: PackedScene
## Procedural placeholder used while there is no art (ModulePart.Kind).
@export var part_kind: ModulePart.Kind = ModulePart.Kind.CUSTOM
@export var part_length: float = 2.0
@export var part_mirror: bool = false
## Exploded-view direction (module local). Zero = the mount's up axis.
@export var explode_dir: Vector3 = Vector3.ZERO


## Problems with this definition alone (no scene checks), for tests / tools.
func validate(items: ItemDB = null) -> PackedStringArray:
	var errors: PackedStringArray = []
	if id == &"" or module_id == &"" or part_node == &"":
		errors.append("%s: id, module_id and part_node are required" % resource_path)
	if not String(part_node).begins_with("part_"):
		errors.append("%s: part_node must start with part_" % id)
	for effect: StringName in effects:
		if not EFFECTS.has(effect):
			errors.append("%s: unknown effect %s (known: %s)" % [id, effect, EFFECTS])
	if requires.has(id):
		errors.append("%s requires itself" % id)
	if mount != &"" and part_scene == null and part_kind == ModulePart.Kind.CUSTOM:
		errors.append("%s: a mounted part needs part_scene or a part_kind placeholder" % id)
	if items != null:
		for item: StringName in cost:
			if items.get_item(item) == null:
				errors.append("%s: cost uses unknown item %s" % [id, item])
	return errors
