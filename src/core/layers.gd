@tool
class_name Layers
## Physics layer bitmasks. Keep in sync with [layer_names] in project.godot.

const WORLD := 1 << 0          # floor, furniture bodies
const PLAYER := 1 << 1
const INTERACTABLE := 1 << 2   # Area3D pick shapes of station objects
const WALLS := 1 << 3          # walls: block movement, ignored by tap raycasts
const MODULE_PICK := 1 << 4    # Area3D boxes of whole modules / ghost slots (station view taps)

## What a tap on the screen can hit.
const TAP_MASK := WORLD | INTERACTABLE
