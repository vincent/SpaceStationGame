class_name PlayerRoutine
extends Node
## Idle-game life: left alone for a while, the castaway looks after
## themselves, driven by needs and the station clock — sleep at night, eat at
## meal times, stargaze when morale is low, otherwise salvage scrap. Any
## order from the player interrupts the routine immediately.

enum Phase { IDLE, WALKING, HOLDING }

## Real seconds without orders before a routine starts.
const IDLE_SECONDS := 10.0
## Meal windows, [from, to) in hours.
const MEAL_HOURS: Array[Vector2] = [Vector2(7, 9), Vector2(12, 14), Vector2(19, 21)]

@export var player: Player
@export var enabled: bool = true

var phase := Phase.IDLE
var target: Interactable
var current_tag: StringName = &""

var _idle := 0.0
var _hold_left := 0.0
var _issuing := false
var _anim: Tween


func _ready() -> void:
	player.move_started.connect(_on_move_started)
	player.arrived.connect(_on_arrived)
	GameClock.time_advanced.connect(_on_time_advanced)
	EventBus.game_reset.connect(interrupt)


## What the castaway wants to do now (a routine tag), from needs and clock.
static func choose(hour: float, food: float, energy: float, morale: float, can_eat: bool) -> StringName:
	var night := hour >= 22.0 or hour < 6.0
	if energy < 25.0 or (night and energy < 80.0):
		return &"sleep"
	if can_eat and (food < 30.0 or (food < 75.0 and _is_meal_time(hour))):
		return &"eat"
	if morale < 45.0:
		return &"stargaze"
	return &"work"


static func _is_meal_time(hour: float) -> bool:
	for window in MEAL_HOURS:
		if hour >= window.x and hour < window.y:
			return true
	return false


func interrupt() -> void:
	if phase == Phase.HOLDING:
		GameState.end_activity()
	phase = Phase.IDLE
	target = null
	current_tag = &""
	_idle = 0.0
	if _anim:
		_anim.kill()
		player.model.scale = Vector3.ONE


func _process(delta: float) -> void:
	if not enabled or phase != Phase.IDLE:
		return
	var hud := get_tree().get_first_node_in_group(&"hud") as HUD
	if player.is_moving() or not player.navigation_ready or (hud and hud.is_menu_open()):
		_idle = 0.0
		return
	_idle += delta
	if _idle >= IDLE_SECONDS:
		_idle = 0.0
		start_routine()


## Picks and starts a routine now. Returns false if nothing suitable exists.
func start_routine() -> bool:
	var kitchen := _nearest(&"eat")
	var can_eat := kitchen != null and kitchen.get_actions().any(func(a: InteractionAction) -> bool: return a.enabled)
	var needs := GameState.needs
	var tag := choose(fposmod(GameClock.total_minutes / 60.0, 24.0), needs.get_value(Needs.FOOD),
		needs.get_value(Needs.ENERGY), needs.get_value(Needs.MORALE), can_eat)
	var spot := _nearest(tag)
	if spot == null and tag != &"work":
		tag = &"work"
		spot = _nearest(tag)
	if spot == null:
		_stretch()
		return false
	current_tag = tag
	target = spot
	phase = Phase.WALKING
	_issuing = true
	player.move_to(spot.get_approach_position())
	_issuing = false
	return true


func _nearest(tag: StringName) -> Interactable:
	var best: Interactable = null
	var best_d := INF
	for node in get_tree().get_nodes_in_group(StringName("routine_%s" % tag)):
		var it := node as Interactable
		var d := it.global_position.distance_to(player.global_position)
		if d < best_d:
			best = it
			best_d = d
	return best


func _on_move_started(_target: Vector3) -> void:
	if not _issuing:
		interrupt()  # the player gave an order


func _on_arrived() -> void:
	if phase != Phase.WALKING or target == null:
		return
	var to_target := target.global_position - player.global_position
	to_target.y = 0.0
	if to_target.length_squared() > 0.001:
		player.model.rotation.y = atan2(to_target.x, to_target.z)
	var activity := target.perform_routine()
	if activity == &"":
		target.finish_routine()
		phase = Phase.IDLE
		return
	GameState.begin_activity(activity)
	phase = Phase.HOLDING
	_hold_left = target.routine_minutes
	_breathe()


func _on_time_advanced(minutes: float) -> void:
	if phase != Phase.HOLDING:
		return
	_hold_left -= minutes
	if _hold_left <= 0.0:
		var done := target
		GameState.end_activity()
		phase = Phase.IDLE
		target = null
		_idle = IDLE_SECONDS * 0.7  # chain the next routine soon
		if is_instance_valid(done):
			done.finish_routine()
		if _anim:
			_anim.kill()
			player.model.scale = Vector3.ONE
		_stretch()


## Small idle animations: a stretch after an activity, slow breathing during.
func _stretch() -> void:
	var t := player.create_tween().set_trans(Tween.TRANS_SINE)
	t.tween_property(player.model, "scale", Vector3(0.94, 1.1, 0.94), 0.35)
	t.tween_property(player.model, "scale", Vector3.ONE, 0.45)


func _breathe() -> void:
	_anim = player.create_tween().set_loops().set_trans(Tween.TRANS_SINE)
	_anim.tween_property(player.model, "scale", Vector3(1.02, 0.97, 1.02), 1.4)
	_anim.tween_property(player.model, "scale", Vector3.ONE, 1.4)
