class_name EncounterDB
extends RefCounted
## Registry of EncounterDef resources (data/encounters/*.tres).

const DEFAULT_DIR := "res://data/encounters"

var _encounters: Dictionary[StringName, EncounterDef] = {}


func load_dir(dir: String = DEFAULT_DIR) -> void:
	for file in DirAccess.get_files_at(dir):
		var path := dir.path_join(file.trim_suffix(".remap"))
		if path.ends_with(".tres") or path.ends_with(".res"):
			var res := load(path)
			if res is EncounterDef:
				register(res)


func register(def: EncounterDef) -> void:
	assert(def.id != &"", "EncounterDef without id: %s" % def.resource_path)
	assert(not _encounters.has(def.id), "Duplicate encounter id: %s" % def.id)
	_encounters[def.id] = def


func get_encounter(id: StringName) -> EncounterDef:
	return _encounters.get(id)


func ids() -> Array[StringName]:
	var out: Array[StringName] = _encounters.keys()
	out.sort()
	return out


## Encounters listening to one trigger, in id order.
func for_trigger(trigger: StringName) -> Array[EncounterDef]:
	var out: Array[EncounterDef] = []
	for id in ids():
		if _encounters[id].trigger == trigger:
			out.append(_encounters[id])
	return out
