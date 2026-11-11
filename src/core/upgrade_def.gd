class_name UpgradeDef
extends Resource
## An upgrade bought in a module's exploded view. Installing it reveals the
## part node `part_node` of the module scene and applies `effects` once.
##
## Known effects (summed over all installed upgrades):
##   power_output, power_draw          -> station power budget
##   food_decay, energy_decay, morale_decay -> added to Needs decay per hour

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
