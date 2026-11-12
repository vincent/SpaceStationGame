class_name ItemDB
extends RefCounted
## Registry of every ItemData, loaded from a folder of .tres files.

const DEFAULT_DIR := "res://data/items"

var _items: Dictionary[StringName, ItemData] = {}


## Loads every resource in `dir`. Handles the ".remap" names that exported
## builds use for converted resources.
func load_dir(dir: String = DEFAULT_DIR) -> void:
	for file in DirAccess.get_files_at(dir):
		var path := dir.path_join(file.trim_suffix(".remap"))
		if not (path.ends_with(".tres") or path.ends_with(".res")):
			continue
		var item := load(path) as ItemData
		if item == null:
			push_warning("ItemDB: %s is not an ItemData" % path)
			continue
		register(item)


func register(item: ItemData) -> void:
	assert(item.id != &"", "ItemData without id: %s" % item.resource_path)
	assert(not _items.has(item.id), "Duplicate item id: %s" % item.id)
	_items[item.id] = item


func has(id: StringName) -> bool:
	return _items.has(id)


func get_item(id: StringName) -> ItemData:
	return _items.get(id)


func ids() -> Array[StringName]:
	var out: Array[StringName] = _items.keys()
	out.sort()
	return out


## Bulk items are station resources (StationStock), not inventory items.
func is_bulk(id: StringName) -> bool:
	var item := get_item(id)
	return item != null and item.bulk


func max_stack(id: StringName) -> int:
	var item := get_item(id)
	return item.max_stack if item else 1
