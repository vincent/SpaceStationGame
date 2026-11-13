@tool
class_name ModuleDef
extends Resource
## Definition of a station module type. One .tres per module in
## res://data/modules/. The look and interior live in the module scene;
## costs, power and slot rules live here so game logic stays scene-free.

## Hatch sizes: S = 1, M = 2 (the standard doorway), L = 3.
const SIZE_NAMES: Array[String] = ["", "S", "M", "L"]
const SIZE_LABELS: Array[String] = ["", "small", "standard", "large"]

@export var id: StringName
@export var display_name: String = ""
@export_multiline var description: String = ""
@export_file("*.tscn") var scene_path: String = ""
## &"module" (part of the station) or &"visitor" (docking ships).
@export var kind: StringName = &"module"
## Default size of this module's slots (see slot_sizes). A module fits a
## slot of its own size or larger (a collar covers the gap).
@export_range(1, 3) var size_class: int = 2
## Can the player build it on a free slot?
@export var buildable: bool = false
@export var build_cost: Dictionary[StringName, int] = {}
@export var build_minutes: float = 120.0
@export var repair_cost: Dictionary[StringName, int] = {}
@export var repair_minutes: float = 120.0
@export var power_output: float = 0.0
@export var power_draw: float = 0.0
## Resources made (+) / used (-) per game hour while running (see Production).
## Ids are bulk items, e.g. {&"food": 0.15, &"water": -0.15}.
@export var production: Dictionary[StringName, float] = {}
## Crew work places (see StationCrew.staffing: staffed modules produce more).
@export var jobs: int = 0
## Slot letter of the interior ASCII (upper case) -> what it accepts: module
## ids or kinds (e.g. ["module"], ["visitor"], ["capsule"]).
@export var slots: Dictionary[StringName, PackedStringArray] = {}
## The slot this module uses to attach to its parent by default (the player
## can rotate the module to attach by another slot).
@export var attach_slot: StringName = &"A"
## Slot sizes that differ from size_class (slot -> 1..3).
@export var slot_sizes: Dictionary[StringName, int] = {}
## Copy of the scene's `interior_ascii` (test_module_data keeps them equal):
## placement rules (StationGrid) read it without loading the scene.
@export_multiline var layout: String = ""
## Imported art: plan footprint in local metres (Rect2 x = x, y = z) replacing
## the layout cells. Leave out parts that float above the module roofs.
@export var massing: Array[Rect2] = []
## Imported art: slot frames that differ from the layout (slot -> x, z, yaw in
## degrees), matching the art's slot_* markers.
@export var slot_frames: Dictionary[StringName, Vector3] = {}


## Size of one of this module's slots (1 = S, 2 = M, 3 = L).
func slot_size(slot: StringName) -> int:
	return slot_sizes.get(slot, size_class)


## Crew beds: the `B` cells of the layout.
func crew_beds() -> int:
	return layout.count("B")


## Smallest of its slots: the smallest hatch it can attach by.
func min_slot_size() -> int:
	var out := size_class
	for slot: StringName in slots:
		out = mini(out, slot_size(slot))
	return out


## True if a slot accepting `accepts`, of size `slot_size_class`, takes a
## module of this definition (by at least one of its slots).
func fits(accepts: PackedStringArray, slot_size_class: int = 3) -> bool:
	return min_slot_size() <= slot_size_class and (accepts.has(String(id)) or accepts.has(String(kind)))
