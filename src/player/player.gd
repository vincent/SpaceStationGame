class_name Player
extends Walker
## The castaway. Walks along the navigation mesh to a tapped point, or to an
## object's approach point and then asks for its action menu.

## How close (m) the player must get to an object's approach point.
@export var interact_reach: float = 0.8

var _pending: Interactable


func _ready() -> void:
	super()
	add_to_group(&"player")
	collision_layer = Layers.PLAYER
	paint(Palette.YELLOW, Palette.NEON_CYAN)


func move_to(target: Vector3) -> void:
	_pending = null
	super(target)


func interact_with(target: Interactable) -> void:
	_pending = target
	var approach := target.get_approach_position()
	if _flat_distance(global_position, approach) <= interact_reach:
		_arrive()
	else:
		_go(approach)


func stop() -> void:
	super()
	_pending = null


func _arrive() -> void:
	super()
	if _pending == null:
		return
	var target := _pending
	_pending = null
	if _flat_distance(global_position, target.get_approach_position()) > interact_reach * 1.5:
		EventBus.toast.emit("Can't reach the %s." % target.display_name.to_lower())
		return
	face_point(target.global_position)
	EventBus.interaction_requested.emit(target)
