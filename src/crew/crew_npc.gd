class_name CrewNPC
extends Walker
## A crew member walking around the station. Mirrors `member.activity` (set
## by CrewSchedule on the data side): asks the CrewDirector for a matching
## spot (bed, workstation, kitchen, free floor) and walks there. Never
## changes the game state.

## Seconds between checks of the member's activity.
const THINK_SECONDS := 0.6
## Idle crew wander to another spot after this long (seconds, random).
const WANDER_PAUSE := Vector2(4.0, 10.0)
## Lying in bed: model lifted onto the mattress.
const BED_HEIGHT := 0.45

var member: CrewMember
var director: CrewDirector
## Where the current spot wants us to look / lie (see CrewDirector.claim_spot).
var spot: Dictionary = {}

var _activity: StringName = &""
var _think := 0.0
var _wait := 0.0
var _anim: Tween


func _ready() -> void:
	super()
	add_to_group(&"crew")
	collision_layer = 0
	speed = randf_range(2.4, 3.0)
	paint(member.color() if member else Palette.NEON_CYAN, Palette.YELLOW)


func _process(delta: float) -> void:
	_think -= delta
	if _think > 0.0 or member == null or not navigation_ready:
		return
	_think = THINK_SECONDS
	if member.activity != _activity:
		_activity = member.activity
		go_for_activity()
	elif not is_moving() and _activity == &"idle":
		_wait -= THINK_SECONDS
		if _wait <= 0.0:
			go_for_activity()


## Picks a new spot for the current activity and walks there.
func go_for_activity() -> void:
	_unpose()
	_activity = member.activity
	spot = director.claim_spot(self, _activity)
	if spot.is_empty():
		_wait = WANDER_PAUSE.x
		return
	move_to(spot.pos)


## Jumps straight to a spot for the current activity (after a time skip).
func snap_to_activity() -> void:
	_unpose()
	_activity = member.activity
	spot = director.claim_spot(self, _activity)
	if spot.is_empty():
		return
	teleport(spot.pos)
	_arrive()


func _arrive() -> void:
	super()
	_wait = randf_range(WANDER_PAUSE.x, WANDER_PAUSE.y)
	if spot.has("face"):
		face_point(spot.face)
	if _activity == &"sleeping" and spot.has("bed"):
		_lie_on(spot.bed)
	elif _activity == &"working" or _activity == &"eating":
		_bob()


## Model lying on the bed (the body stays at the bedside for navigation).
func _lie_on(bed_pos: Vector3) -> void:
	model.global_position = Vector3(bed_pos.x, global_position.y + BED_HEIGHT, bed_pos.z)
	model.rotation = Vector3(-PI / 2.0, model.rotation.y, 0.0)


## Busy at a station: a small working bob.
func _bob() -> void:
	_anim = create_tween().set_loops()
	_anim.tween_property(model, ^"scale", Vector3(1.04, 0.95, 1.04), 0.45).set_trans(Tween.TRANS_SINE)
	_anim.tween_property(model, ^"scale", Vector3.ONE, 0.45).set_trans(Tween.TRANS_SINE)


func _unpose() -> void:
	if _anim:
		_anim.kill()
		_anim = null
	model.position = Vector3.ZERO
	model.rotation = Vector3(0.0, model.rotation.y, 0.0)
	model.scale = Vector3.ONE
