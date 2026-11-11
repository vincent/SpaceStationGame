@tool
class_name ModuleDef
extends Resource
## Definition of a station module type. One .tres per module in
## res://data/modules/. The look and interior live in the module scene;
## costs, power and slot rules live here so game logic stays scene-free.

@export var id: StringName
@export var display_name: String = ""
@export_multiline var description: String = ""
@export_file("*.tscn") var scene_path: String = ""
## &"module" (part of the station) or &"visitor" (docking ships).
@export var kind: StringName = &"module"
## A module fits a slot whose size class is >= its own.
@export_range(1, 3) var size_class: int = 1
## Can the player build it on a free slot?
@export var buildable: bool = false
@export var build_cost: Dictionary[StringName, int] = {}
@export var build_minutes: float = 120.0
@export var repair_cost: Dictionary[StringName, int] = {}
@export var repair_minutes: float = 120.0
@export var power_output: float = 0.0
@export var power_draw: float = 0.0
## Slot letter of the interior ASCII (upper case) -> what it accepts: module
## ids or kinds (e.g. ["module"], ["visitor"], ["capsule"]).
@export var slots: Dictionary[StringName, PackedStringArray] = {}
## The slot this module uses to attach to its parent.
@export var attach_slot: StringName = &"A"


## True if a slot accepting `accepts` takes a module of this definition.
func fits(accepts: PackedStringArray, slot_size_class: int = 3) -> bool:
	return size_class <= slot_size_class and (accepts.has(String(id)) or accepts.has(String(kind)))
