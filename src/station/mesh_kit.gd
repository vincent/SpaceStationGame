@tool
class_name MeshKit
extends RefCounted
## Small procedural-mesh builder on top of SurfaceTool. Every shape it emits
## is a closed solid with outward-facing triangles, so meshes built from it
## stay watertight (required by the cutaway's back-face capping).
##
## Vertex colours carry the toon_cut masks: R = wear, G = emissive, B = trim.
## When `grime_top > grime_bottom`, R also rises towards `grime_bottom` (dirt
## collects low on the hull).

var grime_bottom := 0.0
var grime_top := 0.0
## Applied to everything emitted after it is set (rigid transforms only).
var xform := Transform3D.IDENTITY

var _st := SurfaceTool.new()
var _count := 0


func _init() -> void:
	_st.begin(Mesh.PRIMITIVE_TRIANGLES)


func is_empty() -> bool:
	return _count == 0


func commit() -> ArrayMesh:
	if _count == 0:
		return null
	_st.index()
	return _st.commit()


## Quad p0..p3 (cyclic order, either winding) facing `normal`.
func quad(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, normal: Vector3, color: Color) -> void:
	tri(p0, p1, p2, normal, color)
	tri(p0, p2, p3, normal, color)


## Triangle facing `normal`. Godot treats clockwise triangles as front faces.
func tri(a: Vector3, b: Vector3, c: Vector3, normal: Vector3, color: Color) -> void:
	if xform != Transform3D.IDENTITY:
		a = xform * a
		b = xform * b
		c = xform * c
		normal = (xform.basis * normal).normalized()
	if (b - a).cross(c - a).dot(normal) > 0.0:
		var tmp := b
		b = c
		c = tmp
	for p: Vector3 in [a, b, c]:
		_st.set_normal(normal)
		_st.set_color(_vertex_color(color, p.y))
		_st.add_vertex(p)
	_count += 1


func box(center: Vector3, size: Vector3, color: Color) -> void:
	var h := size * 0.5
	for axis in 3:
		for sgn: float in [-1.0, 1.0]:
			var n := Vector3.ZERO
			n[axis] = sgn
			var u := Vector3.ZERO
			u[(axis + 1) % 3] = h[(axis + 1) % 3]
			var v := Vector3.ZERO
			v[(axis + 2) % 3] = h[(axis + 2) % 3]
			var c := center + n * h[axis]
			quad(c - u - v, c + u - v, c + u + v, c - u + v, n, color)


## Axis-aligned box from its min and max corners.
func box_between(from: Vector3, to: Vector3, color: Color) -> void:
	box((from + to) * 0.5, (to - from).abs(), color)


## Closed cylinder along local `axis` (0 = X, 1 = Y, 2 = Z).
func cylinder(center: Vector3, radius: float, length: float, axis: int, color: Color, segments: int = 10) -> void:
	var a := Vector3.ZERO
	a[axis] = 1.0
	var u := Vector3.ZERO
	u[(axis + 1) % 3] = 1.0
	var v := Vector3.ZERO
	v[(axis + 2) % 3] = 1.0
	var top := center + a * length * 0.5
	var bottom := center - a * length * 0.5
	for i in segments:
		var t0 := TAU * i / segments
		var t1 := TAU * (i + 1) / segments
		var d0 := (u * cos(t0) + v * sin(t0)) * radius
		var d1 := (u * cos(t1) + v * sin(t1)) * radius
		var side_n := (d0 + d1).normalized()
		quad(bottom + d0, bottom + d1, top + d1, top + d0, side_n, color)
		tri(top, top + d0, top + d1, a, color)
		tri(bottom, bottom + d1, bottom + d0, -a, color)


## The 12 edges of an AABB as thin square sticks (ghost outlines).
func box_edges(aabb: AABB, thickness: float, color: Color) -> void:
	var lo := aabb.position
	var hi := aabb.end
	var t := thickness * 0.5
	for axis in 3:
		var o1 := (axis + 1) % 3
		var o2 := (axis + 2) % 3
		for s1: float in [lo[o1], hi[o1]]:
			for s2: float in [lo[o2], hi[o2]]:
				var from := Vector3.ZERO
				var to := Vector3.ZERO
				from[axis] = lo[axis] - t
				to[axis] = hi[axis] + t
				from[o1] = s1 - t
				to[o1] = s1 + t
				from[o2] = s2 - t
				to[o2] = s2 + t
				box_between(from, to, color)


func _vertex_color(color: Color, y: float) -> Color:
	if grime_top <= grime_bottom:
		return color
	var g := 1.0 - clampf((y - grime_bottom) / (grime_top - grime_bottom), 0.0, 1.0)
	return Color(maxf(color.r, g * 0.8), color.g, color.b, color.a)
