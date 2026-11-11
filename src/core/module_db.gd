class_name ModuleDB
extends RefCounted
## Registry of ModuleDef and UpgradeDef resources loaded from data folders.

const MODULES_DIR := "res://data/modules"
const UPGRADES_DIR := "res://data/upgrades"

var _modules: Dictionary[StringName, ModuleDef] = {}
var _upgrades: Dictionary[StringName, UpgradeDef] = {}


func load_dirs(modules_dir: String = MODULES_DIR, upgrades_dir: String = UPGRADES_DIR) -> void:
	for res in _load_all(modules_dir):
		if res is ModuleDef:
			register_module(res)
	for res in _load_all(upgrades_dir):
		if res is UpgradeDef:
			register_upgrade(res)


func register_module(def: ModuleDef) -> void:
	assert(def.id != &"", "ModuleDef without id: %s" % def.resource_path)
	assert(not _modules.has(def.id), "Duplicate module id: %s" % def.id)
	_modules[def.id] = def


func register_upgrade(def: UpgradeDef) -> void:
	assert(def.id != &"", "UpgradeDef without id: %s" % def.resource_path)
	assert(not _upgrades.has(def.id), "Duplicate upgrade id: %s" % def.id)
	_upgrades[def.id] = def


func get_module(id: StringName) -> ModuleDef:
	return _modules.get(id)


func get_upgrade(id: StringName) -> UpgradeDef:
	return _upgrades.get(id)


func module_ids() -> Array[StringName]:
	var out: Array[StringName] = _modules.keys()
	out.sort()
	return out


func upgrade_ids() -> Array[StringName]:
	var out: Array[StringName] = _upgrades.keys()
	out.sort()
	return out


## Upgrades of one module type, in id order.
func upgrades_for(module_id: StringName) -> Array[UpgradeDef]:
	var out: Array[UpgradeDef] = []
	for id in upgrade_ids():
		if _upgrades[id].module_id == module_id:
			out.append(_upgrades[id])
	return out


## Buildable module types that fit a slot.
func buildable_for(accepts: PackedStringArray, slot_size_class: int = 3) -> Array[ModuleDef]:
	var out: Array[ModuleDef] = []
	for id in module_ids():
		var def := _modules[id]
		if def.buildable and def.fits(accepts, slot_size_class):
			out.append(def)
	return out


static func _load_all(dir: String) -> Array[Resource]:
	var out: Array[Resource] = []
	for file in DirAccess.get_files_at(dir):
		var path := dir.path_join(file.trim_suffix(".remap"))
		if path.ends_with(".tres") or path.ends_with(".res"):
			var res := load(path)
			if res != null:
				out.append(res)
	return out
