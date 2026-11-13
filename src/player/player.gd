class_name Player
extends Walker
## The castaway. Walks along the navigation mesh to a tapped point, or to an
## object's approach point and then uses it: runs the action picked on the
## HUD card (ObjectPanel), if any, after announcing the arrival
## (EventBus.interaction_requested).

## The object (and action) the player is walking to changed; nulls = none.
signal pending_changed(target: Interactable, action: InteractionAction)

## How close (m) the player must get to an object's approach point.
@export var interact_reach: float = 0.8

var _pending: Interactable
var _pending_action: InteractionAction


func _ready() -> void:
	super()
	add_to_group(&"player")
	collision_layer = Layers.PLAYER
	paint(Palette.YELLOW, Palette.NEON_CYAN)


func move_to(target: Vector3) -> void:
	_set_pending(null, null)
	super(target)


## Walks to `target`; on arrival runs `action` (one of its get_actions()).
func interact_with(target: Interactable, action: InteractionAction = null) -> void:
	_set_pending(target, action)
	var approach := target.get_approach_position()
	if _flat_distance(global_position, approach) <= interact_reach:
		_arrive()
	else:
		_go(approach)


func stop() -> void:
	super()
	_set_pending(null, null)


func pending_action() -> InteractionAction:
	return _pending_action


func _set_pending(target: Interactable, action: InteractionAction) -> void:
	if target == _pending and action == _pending_action:
		return
	_pending = target
	_pending_action = action
	pending_changed.emit(target, action)


func _arrive() -> void:
	super()
	if _pending == null:
		return
	var target := _pending
	var action := _pending_action
	_set_pending(null, null)
	if _flat_distance(global_position, target.get_approach_position()) > interact_reach * 1.5:
		EventBus.toast.emit("Can't reach the %s." % target.display_name.to_lower())
		return
	face_point(target.global_position)
	EventBus.interaction_requested.emit(target)
	if action and action.enabled and action.callback.is_valid():
		action.callback.call()
