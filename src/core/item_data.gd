class_name ItemData
extends Resource
## Definition of an item type. One .tres file per item in res://data/items/.
## Inventories store only the `id` and a count; everything else lives here.
## Bulk items (resources: scrap, water, food) never sit in the inventory:
## they live in the station stock (StationStock). GameState's wallet
## (`count`, `has_all`, `give`, `pay`) routes each id to the right place.

@export var id: StringName
@export var display_name: String = ""
@export_multiline var description: String = ""
@export_range(1, 999) var max_stack: int = 10
## Placeholder visual until real icons exist.
@export var color: Color = Color.WHITE
@export var icon: Texture2D
## Can the player "use" it from the inventory?
@export var usable: bool = false
## Need changes applied when used, e.g. {"food": 15.0}.
@export var use_effects: Dictionary[StringName, float] = {}
@export var tags: PackedStringArray = []
## A station resource (StationStock) rather than a carried item.
@export var bulk: bool = false
