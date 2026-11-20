class_name StressLayout
extends RefCounted
## Grows a big station for performance stress tests (debug only).
##
## Breadth-first from the existing modules: every free slot gets a module
## (mostly branching ones — hubs, junctions, corridors — so the tree keeps
## growing, with leaves sprinkled in), trying every orientation, until
## `target` modules were added or no slot accepts anything (overlaps).
## Deterministic for a given `seed_value`.

const BRANCHING: Array[StringName] = [
	&"hub_x", &"hub_oct", &"junction_t", &"corridor", &"dorm", &"adapter_ml",
]
const LEAVES: Array[StringName] = [&"hab_pod", &"greenhouse", &"solar_array"]
## Chance a slot gets a leaf first (else a branching module first).
const LEAF_CHANCE := 0.25
## Open branches needed before a slot may get a leaf.
const MIN_FRONTIER_FOR_LEAVES := 4


## Adds up to `target` modules; returns how many were added.
static func grow(st: StationState, target: int, seed_value: int = 1) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var queue: Array[int] = st.uids()
	var added := 0
	while added < target and not queue.is_empty():
		var parent: int = queue.pop_front()
		for slot in st.free_slots(parent):
			if added >= target:
				break
			# Leaves only once enough branches are growing, or the tree dies out.
			for module_id in _candidates(rng, queue.size() >= MIN_FRONTIER_FOR_LEAVES):
				var uid := _try_attach(st, module_id, parent, slot)
				if uid != 0:
					added += 1
					queue.append(uid)
					break
	return added


static func _candidates(rng: RandomNumberGenerator, allow_leaves: bool) -> Array[StringName]:
	var branching := BRANCHING.duplicate()
	var leaves := LEAVES.duplicate()
	_shuffle(branching, rng)
	_shuffle(leaves, rng)
	return leaves + branching if allow_leaves and rng.randf() < LEAF_CHANCE else branching + leaves


static func _shuffle(list: Array[StringName], rng: RandomNumberGenerator) -> void:
	for i in range(list.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := list[i]
		list[i] = list[j]
		list[j] = tmp


static func _try_attach(st: StationState, module_id: StringName, parent: int, slot: StringName) -> int:
	var options := st.attach_options(module_id, parent, slot)
	if options.is_empty():
		return 0
	return st.add_module(module_id, parent, slot, StationState.State.REPAIRED, 0.3, false, options[0])
