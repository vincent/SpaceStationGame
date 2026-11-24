extends GutTest
## Crew NPCs in the real game scene: spawn, walk to their spots, survive a load.

const MAIN := preload("res://src/world/main.tscn")

var main: Node3D
var station: Station
var director: CrewDirector
var hab: int
var wreck: int


func before_each() -> void:
	GameClock.paused = true
	GameState.new_game()
	GameState.set_story_enabled(false)
	main = MAIN.instantiate()
	main.skip_intro = true
	add_child_autofree(main)
	station = main.get_node("Station")
	director = main.get_node("CrewDirector")
	(main.get_node("Player/Routine") as PlayerRoutine).enabled = false
	var player: Player = main.get_node("Player")
	await wait_until(func() -> bool: return player.navigation_ready, 5.0)
	var st := GameState.station
	wreck = st.find_module(&"wreck_core")
	st.repair(wreck)
	var node := st.add_module(&"hub_oct", wreck, &"B")
	hab = 0
	for slot in st.free_slots(node):
		if st.attach_error(&"dorm", node, slot) == "":
			hab = st.add_module(&"dorm", node, slot)
			break
	assert_gt(hab, 0, "dorm attached")
	await wait_seconds(0.8)  # arrival animation + navigation map sync


func after_all() -> void:
	GameClock.paused = false
	GameState.new_game()
	GameState.set_story_enabled(true)


func _recruit(n: int) -> Array[CrewNPC]:
	var out: Array[CrewNPC] = []
	for i in n:
		var m := GameState.station.crew.add()
		assert_not_null(m, "bunk %d" % i)
	for m in GameState.station.crew.members:
		var npc: CrewNPC = director.npcs.get(m.id)
		assert_not_null(npc, "NPC spawned for %s" % m.display_name)
		out.append(npc)
	await wait_until(func() -> bool: return out.all(func(n: CrewNPC) -> bool: return n.navigation_ready), 5.0)
	return out


func _module_of(npc: CrewNPC) -> int:
	var here := station.module_at(npc.global_position)
	return here.uid if here else 0


func test_recruits_spawn_at_home() -> void:
	var npcs := await _recruit(2)
	assert_eq(npcs.size(), 2)
	for npc in npcs:
		assert_true(npc.navigation_ready, "%s on the navmesh" % npc.member.display_name)
		assert_eq(_module_of(npc), hab, "%s starts in the habitat" % npc.member.display_name)


func test_crew_go_to_bed_at_night() -> void:
	var npcs := await _recruit(2)
	GameClock.advance(fposmod((23 - GameClock.hour()) * 60.0 - GameClock.minute(), 1440.0))
	await wait_physics_frames(2)
	for npc in npcs:
		assert_eq(npc.member.activity, &"sleeping")
		assert_true(npc.spot.has("bed"), "%s got a bunk" % npc.member.display_name)
		assert_eq(_module_of(npc), hab, "%s sleeps in the habitat" % npc.member.display_name)
	assert_ne(npcs[0].spot.bed, npcs[1].spot.bed, "one bunk each")


func test_worker_walks_to_the_job() -> void:
	var npcs := await _recruit(1)
	assert_eq(GameState.station.crew.staff(wreck), "")
	GameState.station.crew.members[0].activity = &"working"
	await wait_until(func() -> bool: return _module_of(npcs[0]) == wreck and not npcs[0].is_moving(), 10.0)
	assert_eq(_module_of(npcs[0]), wreck, "at work in the wreck")


func test_load_restores_npcs() -> void:
	await _recruit(2)
	var data: Dictionary = JSON.parse_string(JSON.stringify(GameState.to_dict()))
	GameState.station.crew.clear()
	await wait_physics_frames(2)
	assert_eq(director.npcs.size(), 0)
	GameState.from_dict(data)
	await wait_physics_frames(2)
	assert_eq(director.npcs.size(), 2)


func test_trashing_a_module_moves_the_crew_out() -> void:
	var npcs := await _recruit(2)
	var node: int = GameState.station.get_record(hab).parent
	GameState.station.get_record(hab).built = true  # as if the player built it
	var inside := npcs.filter(func(n: CrewNPC) -> bool: return _module_of(n) == hab)
	assert_false(inside.is_empty(), "someone at home in the dorm")
	assert_true(GameState.trash_module(hab))
	for npc: CrewNPC in inside:
		assert_eq(_module_of(npc), node, "%s moved to the hub" % npc.member.display_name)
	for m in GameState.station.crew.members:
		assert_ne(m.home_uid, hab, "re-homed")
