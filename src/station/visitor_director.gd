class_name VisitorDirector
extends Node
## Docking visitors: now and then a trader ship approaches a free visitor
## slot ("V" on the wreck, needs power for the docking beacon), clamps on,
## stays a few hours or until a trade, then leaves. Visitors change the
## silhouette for a while and are never saved.

## Chance per game hour that a ship shows up when a dock is free.
const ARRIVAL_CHANCE := 0.2
const STAY_MINUTES := 6.0 * 60.0
const LEAVE_AFTER_TRADE_MINUTES := 45.0
const APPROACH_SECONDS := 3.5
const APPROACH_DISTANCE := 40.0

@export var station: Station

var visitor_uid := 0
var stay_left := 0.0
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.randomize()
	GameClock.hour_passed.connect(_on_hour_passed)
	GameClock.time_advanced.connect(_on_time_advanced)
	EventBus.trade_completed.connect(func() -> void: stay_left = minf(stay_left, LEAVE_AFTER_TRADE_MINUTES))
	EventBus.game_reset.connect(func() -> void: visitor_uid = 0)
	EventBus.visitor_requested.connect(func() -> void:
		if visitor_uid == 0 and not arrive():
			EventBus.toast.emit("No powered docking port: the ship can't dock."))
	station.module_attached.connect(_on_module_attached)


## [parent_uid, slot] of a free, powered docking slot, or [] if none.
func find_dock() -> Array:
	var st := GameState.station
	for uid in st.uids():
		var rec := st.get_record(uid)
		if not rec.powered:
			continue
		var def := st.get_def(uid)
		for slot in st.free_slots(uid):
			if def.slots[slot].has("visitor"):
				return [uid, slot]
	return []


## Brings a trader in now. Returns false when no dock is free.
func arrive() -> bool:
	if visitor_uid != 0:
		return false
	var dock := find_dock()
	if dock.is_empty():
		return false
	visitor_uid = GameState.station.add_module(&"trader_ship", dock[0], dock[1], StationState.State.REPAIRED, 0.45, false)
	if visitor_uid == 0:
		return false
	stay_left = STAY_MINUTES
	EventBus.toast.emit("A trader ship is docking.")
	GameState.story_event(&"visitor", &"trader_ship")
	return true


func depart() -> void:
	if visitor_uid == 0:
		return
	var ship := station.get_module(visitor_uid)
	var player := get_tree().get_first_node_in_group(&"player") as Node3D
	if ship and player and station.module_at(player.global_position) == ship:
		stay_left = 30.0  # don't leave with the castaway aboard
		return
	var uid := visitor_uid
	visitor_uid = 0
	EventBus.toast.emit("The trader undocks.")
	if ship == null:
		GameState.station.remove_module(uid)
		return
	station.detach(ship)
	var away := ship.global_position + _outward(ship) * APPROACH_DISTANCE + Vector3(0, 6, 0)
	var t := ship.create_tween()
	t.tween_property(ship, "global_position", away, APPROACH_SECONDS).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_callback(func() -> void: GameState.station.remove_module(uid))


func _outward(ship: Module) -> Vector3:
	var slot := ship.get_attach_slot()
	return -slot.global_basis.z if slot else Vector3.FORWARD


## Approach path: the ship glides in from far away along the slot axis,
## then the docking clamp bumps.
func _on_module_attached(module: Module) -> void:
	if module.def == null or module.def.kind != &"visitor":
		return
	var rest := module.global_transform
	module.global_position = rest.origin + _outward(module) * APPROACH_DISTANCE + Vector3(0, 6, 0)
	var t := module.create_tween()
	t.tween_property(module, "global_position", rest.origin, APPROACH_SECONDS) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_callback(func() -> void: EventBus.sfx.emit(&"clamp"))
	t.tween_property(module, "scale", Vector3(1.04, 0.97, 1.04), 0.08)
	t.tween_property(module, "scale", Vector3.ONE, 0.2).set_trans(Tween.TRANS_ELASTIC)
	t.tween_callback(module.sync_navigation_transform)


func _on_hour_passed(_hour: int) -> void:
	if visitor_uid == 0 and rng.randf() < ARRIVAL_CHANCE:
		arrive()


func _on_time_advanced(minutes: float) -> void:
	if visitor_uid == 0:
		return
	stay_left -= minutes
	if stay_left <= 0.0:
		depart()
