"""Pass 1 block-out of the early-game diorama (capsule docked to wreck).

Run inside Blender (5.x):  exec(open(PATH).read())
Rebuilds everything from scratch; safe to re-run.
Units: 1 = 1 m, +Z up. Station long axis = X. Camera looks from (+X, -Y, +Z).
"""
import math
import os

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

ROOT_DIR = "/home/vincent/Workspace/Perso/space-station-tycoon/art/station_early"

# ---------------------------------------------------------------- palette
def _lin(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def hexcol(h, a=1.0):
    h = h.lstrip("#")
    return tuple(_lin(int(h[i:i + 2], 16) / 255) for i in (0, 2, 4)) + (a,)


PAL = {
    "anthracite": "#2B2D33", "darkblue": "#1B2340", "violet": "#4B3F8F",
    "red": "#D8402E", "offwhite": "#E8E4DA", "cream": "#E8DFC8",
    "amber": "#FFB547", "neon": "#FFD23F", "pink": "#FF4FA3",
    "cyan": "#3DE0E8", "ink": "#14121A",
    # derived (block-out only)
    "steel": "#3A3D47", "rust": "#6B3A2A", "glass": "#0E1226",
}
C = {k: hexcol(v) for k, v in PAL.items()}

# ---------------------------------------------------------------- reset
def reset():
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    for coll in list(bpy.data.collections):
        bpy.data.collections.remove(coll)
    for block in (bpy.data.meshes, bpy.data.materials, bpy.data.curves,
                  bpy.data.lights, bpy.data.cameras, bpy.data.node_groups):
        for d in list(block):
            block.remove(d)


def make_collections():
    names = ["CAPSULE", "WRECK_CORE", "GREEBLE_KIT", "LIGHTS", "CAMERA",
             "CUT_PREVIEW", "BACKGROUND"]
    out = {}
    for n in names:
        c = bpy.data.collections.new(n)
        bpy.context.scene.collection.children.link(c)
        out[n] = c
    return out


# ---------------------------------------------------------------- materials
def toon_group():
    """3-step constant ramp on light intensity, tinted by the light's hue.

    out = Base * ramp(max(L.rgb)) * mix(white, L / max(L.rgb), 0.85)
    Stepping the intensity (not each channel) keeps the amber lamp amber.
    """
    ng = bpy.data.node_groups.new("ToonRamp", "ShaderNodeTree")
    ng.interface.new_socket("Light", in_out="INPUT", socket_type="NodeSocketColor")
    ng.interface.new_socket("Base", in_out="INPUT", socket_type="NodeSocketColor")
    ng.interface.new_socket("Color", in_out="OUTPUT", socket_type="NodeSocketColor")
    n, l = ng.nodes, ng.links
    gi, go = n.new("NodeGroupInput"), n.new("NodeGroupOutput")
    sep = n.new("ShaderNodeSeparateColor")
    l.new(gi.outputs["Light"], sep.inputs[0])
    mx1, mx2 = n.new("ShaderNodeMath"), n.new("ShaderNodeMath")
    mx1.operation = mx2.operation = "MAXIMUM"
    l.new(sep.outputs[0], mx1.inputs[0])
    l.new(sep.outputs[1], mx1.inputs[1])
    l.new(mx1.outputs[0], mx2.inputs[0])
    l.new(sep.outputs[2], mx2.inputs[1])
    ramp = n.new("ShaderNodeValToRGB")
    ramp.color_ramp.interpolation = "CONSTANT"
    e = ramp.color_ramp.elements
    e[0].position, e[0].color = 0.0, (0.30, 0.28, 0.42, 1)  # cold violet shadow
    e[1].position, e[1].color = 0.07, (0.62, 0.62, 0.66, 1)
    e.new(0.55).color = (1, 1, 1, 1)
    l.new(mx2.outputs[0], ramp.inputs[0])
    eps = n.new("ShaderNodeMath")
    eps.operation = "MAXIMUM"
    eps.inputs[1].default_value = 1e-4
    l.new(mx2.outputs[0], eps.inputs[0])
    div = n.new("ShaderNodeVectorMath")
    div.operation = "DIVIDE"
    l.new(gi.outputs["Light"], div.inputs[0])
    l.new(eps.outputs[0], div.inputs[1])
    tint = n.new("ShaderNodeVectorMath")
    tint.operation = "MULTIPLY_ADD"
    tint.inputs[1].default_value = (0.85, 0.85, 0.85)
    tint.inputs[2].default_value = (0.15, 0.15, 0.15)
    l.new(div.outputs[0], tint.inputs[0])
    m1, m2 = n.new("ShaderNodeVectorMath"), n.new("ShaderNodeVectorMath")
    m1.operation = m2.operation = "MULTIPLY"
    l.new(ramp.outputs[0], m1.inputs[0])
    l.new(tint.outputs[0], m1.inputs[1])
    l.new(m1.outputs[0], m2.inputs[0])
    l.new(gi.outputs["Base"], m2.inputs[1])
    l.new(m2.outputs[0], go.inputs["Color"])
    return ng


def _base_input(nt, base):
    """base: RGBA tuple or attribute name string (+ optional lighten toward cream)."""
    n = nt.nodes
    if not isinstance(base[0], str):
        rgb = n.new("ShaderNodeRGB")
        rgb.outputs[0].default_value = base
        return rgb.outputs[0]
    name, lighten = base
    at = n.new("ShaderNodeAttribute")
    at.attribute_name = name
    if not lighten:
        return at.outputs["Color"]
    mix = n.new("ShaderNodeVectorMath")
    mix.operation = "MULTIPLY_ADD"  # attr*(1-k) + cream*k
    mix.inputs[1].default_value = (1 - lighten,) * 3
    mix.inputs[2].default_value = tuple(c * lighten for c in C["cream"][:3])
    nt.links.new(at.outputs["Color"], mix.inputs[0])
    return mix.outputs[0]


def toon_mat(name, base, emissive=None, emit_strength=0.0, cull=False):
    """Diffuse -> Shader to RGB -> ToonRamp -> Emission (+ emissive mix)."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    n, l = nt.nodes, nt.links
    out = n.new("ShaderNodeOutputMaterial")
    dif = n.new("ShaderNodeBsdfDiffuse")
    dif.inputs["Color"].default_value = (1, 1, 1, 1)
    s2r = n.new("ShaderNodeShaderToRGB")
    grp = n.new("ShaderNodeGroup")
    grp.node_tree = bpy.data.node_groups["ToonRamp"]
    em = n.new("ShaderNodeEmission")
    l.new(dif.outputs[0], s2r.inputs[0])
    l.new(s2r.outputs["Color"], grp.inputs["Light"])
    l.new(_base_input(nt, base), grp.inputs["Base"])
    l.new(grp.outputs[0], em.inputs["Color"])
    shader = em.outputs[0]
    if emissive is not None:
        em2 = n.new("ShaderNodeEmission")
        em2.inputs["Strength"].default_value = emit_strength
        l.new(_base_input(nt, emissive), em2.inputs["Color"])
        add = n.new("ShaderNodeAddShader")
        l.new(shader, add.inputs[0])
        l.new(em2.outputs[0], add.inputs[1])
        shader = add.outputs[0]
    l.new(shader, out.inputs["Surface"])
    m.use_backface_culling = cull
    m.diffuse_color = base if not isinstance(base[0], str) else (0.3, 0.3, 0.3, 1)
    return m


def flat_emit_mat(name, color, strength=1.0, cull=False):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = color
    em.inputs["Strength"].default_value = strength
    nt.links.new(em.outputs[0], out.inputs["Surface"])
    m.use_backface_culling = cull
    m.diffuse_color = color
    return m


def emissive_attr_mat(name, strength):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Strength"].default_value = strength
    nt.links.new(_base_input(nt, ("Base", 0)), em.inputs["Color"])
    nt.links.new(em.outputs[0], out.inputs["Surface"])
    return m


def make_materials():
    toon_group()
    M = {}
    # 3 materials per module: hull / interior / emissive (base colour from "Base" attribute)
    M["wreck_hull"] = toon_mat("M_wreck_hull", ("Base", 0))
    M["wreck_interior"] = toon_mat("M_wreck_interior", ("Base", 0.45))
    M["wreck_emissive"] = emissive_attr_mat("M_wreck_emissive", 4.0)
    M["capsule_hull"] = toon_mat("M_capsule_hull", ("Base", 0))
    M["capsule_interior"] = toon_mat("M_capsule_interior", ("Base", 0.15))
    M["capsule_emissive"] = emissive_attr_mat("M_capsule_emissive", 5.0)
    # preview-only (not exported as game materials)
    M["ink"] = flat_emit_mat("M_ink_outline", C["ink"], 1.0, cull=True)
    M["ink"].use_backface_culling_shadow = True  # outline shells must not block lights
    M["cap"] = toon_mat("M_cut_cap", C["cream"])
    return M


# ---------------------------------------------------------------- mesh helpers
def _finish(name, bm, color, mats, coll, loc=(0, 0, 0), rot=(0, 0, 0), mat_index=0):
    lay = bm.loops.layers.float_color.new("Base")
    for f in bm.faces:
        f.material_index = mat_index
        for lo in f.loops:
            lo[lay] = color
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for m in mats:
        me.materials.append(m)
    me.color_attributes.active_color_name = "Base"
    ob = bpy.data.objects.new(name, me)
    ob.location = loc
    ob.rotation_euler = Euler([math.radians(a) for a in rot])
    coll.objects.link(ob)
    return ob


def box(name, mn, mx, color, mats, coll, mat_index=0):
    mn, mx = Vector(mn), Vector(mx)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    d = mx - mn
    for v in bm.verts:
        v.co = Vector((v.co.x * d.x, v.co.y * d.y, v.co.z * d.z))
    return _finish(name, bm, color, mats, coll, (mn + mx) / 2, mat_index=mat_index)


def cyl(name, r, depth, loc, rot, color, mats, coll, r2=None, seg=24, mat_index=0):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=seg,
                          radius1=r, radius2=r if r2 is None else r2, depth=depth)
    return _finish(name, bm, color, mats, coll, loc, rot, mat_index)


def sphere(name, r, loc, scale, color, mats, coll, seg=24, rings=12, mat_index=0):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=rings, radius=r)
    for v in bm.verts:
        v.co = Vector((v.co.x * scale[0], v.co.y * scale[1], v.co.z * scale[2]))
    return _finish(name, bm, color, mats, coll, loc, mat_index=mat_index)


def hollow(ob, thickness, interior_offset=1):
    """Real wall thickness: inner shell gets the interior material."""
    mod = ob.modifiers.new("WALL", "SOLIDIFY")
    mod.thickness = thickness
    mod.offset = -1.0
    mod.use_even_offset = True
    mod.material_offset = interior_offset
    return mod


def outline(ob, ink, thickness=0.07):
    """Inverted hull outline (preview look; Godot uses its own outline shader)."""
    ob.data.materials.append(ink)
    mod = ob.modifiers.new("OUTLINE", "SOLIDIFY")
    mod.thickness = thickness
    mod.offset = 1.0
    mod.use_flip_normals = True
    mod.use_rim = False
    mod.material_offset = 100  # clamps to the last slot = ink
    mod.show_in_editmode = False
    return mod


def parent_keep(child, parent):
    child.parent = parent
    child.matrix_parent_inverse = parent.matrix_basis.inverted()


def empty(name, loc, coll, kind="PLAIN_AXES", size=0.6):
    e = bpy.data.objects.new(name, None)
    e.empty_display_type = kind
    e.empty_display_size = size
    e.location = loc
    coll.objects.link(e)
    return e


# ---------------------------------------------------------------- build
# Docking point shared by both modules: Room A's +X wall, capsule nose collar.
DOCK = Vector((11.5, -3.75, 2.0))


def build_wreck(cols, M):
    co = cols["WRECK_CORE"]
    hm = [M["wreck_hull"], M["wreck_interior"], M["wreck_emissive"]]
    root = empty("wreck_core", DOCK, co, "ARROWS", 1.5)
    obs = []

    def add(ob):
        obs.append(ob)
        return ob

    # --- main hub block (rooms B behind its front face)
    main = add(box("hull_main", (-14, -1.5, 0), (12, 6, 7), C["anthracite"], hm, co))
    hollow(main, 0.3)
    # violet panel band + dark blue lower skirt (block-out colour zones)
    add(box("hull_band", (-14.1, -1.62, 4.6), (12.1, 6.1, 5.4), C["violet"], hm, co))
    add(box("hull_skirt", (-14.1, -1.62, -0.4), (12.1, 6.1, 0.6), C["darkblue"], hm, co))
    # --- upper box (room C)
    up = add(box("hull_upper", (-4, 0, 7), (5, 5, 9.6), C["darkblue"], hm, co))
    hollow(up, 0.3)
    # --- big cylinder section on top-left
    cy = add(cyl("hull_cylinder", 2.4, 13, (-11.5, 2.6, 9.4), (0, 90, 0), C["anthracite"], hm, co))
    hollow(cy, 0.3)
    for i, x in enumerate((-16.5, -11.5, -6.5)):
        add(cyl(f"hull_cyl_rib{i}", 2.55, 0.5, (x, 2.6, 9.4), (0, 90, 0), C["violet"], hm, co))
    # --- ROOM A wing (cut open in preview)
    ra = add(box("hull_roomA", (3, -6, 0), (11.5, -1.5, 4), C["violet"], hm, co))
    hollow(ra, 0.3)
    ra.data.materials.append(M["cap"])  # slot 3: cut faces (boolean transfer)
    # --- truss running out of frame to the left + broken solar panel
    add(box("part_truss", (-34, 1.6, 8.6), (-18, 3.6, 9.4), C["steel"], hm, co))
    for i, x in enumerate(range(-32, -18, 3)):
        add(box(f"part_truss_strut{i}", (x, 1.5, 7.6), (x + 0.3, 3.7, 10.4), C["steel"], hm, co))
    sp = add(box("part_solar_panel", (-29, -6, 9.0), (-21, 1.6, 9.12), C["darkblue"], hm, co))
    sp.rotation_euler = Euler((math.radians(-14), math.radians(6), math.radians(-8)))
    sp2 = add(box("part_solar_panel_broken", (-20.5, -5.5, 8.4), (-17.5, -1.2, 8.5), C["darkblue"], hm, co))
    sp2.rotation_euler = Euler((math.radians(-35), math.radians(18), math.radians(12)))
    # --- antennas + dish on upper box
    add(cyl("part_antenna_a", 0.07, 4.0, (3.5, 1.2, 11.6), (0, 0, 0), C["steel"], hm, co, seg=8))
    add(cyl("part_antenna_b", 0.05, 2.6, (2.5, 3.8, 10.9), (8, -6, 0), C["steel"], hm, co, seg=8))
    add(cyl("part_dish", 1.3, 0.5, (-2.5, 3.5, 10.6), (35, 0, 20), C["steel"], hm, co, r2=0.25))
    # --- torn hull plate with ribs (front face of main block, left)
    add(box("hull_tear_void", (-12.6, -1.56, 2.0), (-8.6, -1.45, 5.6), C["ink"], hm, co))
    for i, x in enumerate((-12.0, -10.9, -9.8)):
        add(box(f"hull_tear_rib{i}", (x, -1.8, 2.0), (x + 0.22, -1.5, 5.6), C["steel"], hm, co))
    torn = add(box("part_torn_plate", (-12.6, -1.75, 5.6), (-9.4, -1.6, 7.0), C["anthracite"], hm, co))
    torn.rotation_euler = Euler((math.radians(28), 0, math.radians(-6)))
    # --- grimy portholes (rooms B and C), dark
    for i, x in enumerate((-6.5, -4.0, -1.5, 1.0)):
        add(cyl(f"hull_porthole_B{i}", 0.45, 0.12, (x, -1.53, 3.0), (90, 0, 0), C["glass"], hm, co))
    for i, x in enumerate((-2.5, 0.0, 2.5)):
        add(cyl(f"hull_porthole_C{i}", 0.4, 0.12, (x, -0.03, 8.4), (90, 0, 0), C["glass"], hm, co))
    # hazard + stencil hint (block-out: flat stripe)
    add(box("hull_hazard", (5.5, -1.6, 6.2), (11.8, -1.5, 6.6), C["neon"], hm, co))

    # --- docking / attachment points
    ring_a = add(cyl("part_dock_ring_A", 1.3, 0.5, (0.5, 2.5, 9.85), (0, 0, 0), C["steel"], hm, co))
    ring_b = add(cyl("part_dock_ring_B", 1.3, 0.5, (12.25, 2.25, 4.2), (0, 90, 0), C["steel"], hm, co))
    collar = add(cyl("part_dock_collar_capsule", 0.85, 0.5, (11.75, DOCK.y, DOCK.z), (0, 90, 0), C["steel"], hm, co))
    slots = [empty("slot_dock_capsule", DOCK, co, "SINGLE_ARROW"),
             empty("slot_dock_A", (0.5, 2.5, 10.1), co, "SINGLE_ARROW"),
             empty("slot_dock_B", (12.5, 2.25, 4.2), co, "SINGLE_ARROW")]
    slots[0].rotation_euler = (0, math.radians(90), 0)
    slots[2].rotation_euler = (0, math.radians(90), 0)

    # --- ROOM A interior (floor top z=0.3, inner walls x[3.3,11.2] y[-5.7,-1.8])
    ii = 1  # interior material index
    add(box("part_crate_table", (7.6, -4.6, 0.3), (8.6, -3.6, 1.1), C["rust"], hm, co, ii))
    add(box("part_console_dead", (4.2, -2.6, 0.3), (6.4, -1.8, 1.5), C["steel"], hm, co, ii))
    add(box("part_console_screen", (4.5, -2.65, 1.0), (6.1, -2.6, 1.4), C["glass"], hm, co, ii))
    add(box("part_crate_a", (9.6, -2.8, 0.3), (10.8, -1.8, 1.2), C["darkblue"], hm, co, ii))
    add(box("part_crate_b", (9.9, -2.6, 1.2), (10.6, -1.9, 1.8), C["rust"], hm, co, ii))
    add(box("part_debris_floor", (5.0, -5.0, 0.3), (5.8, -4.4, 0.55), C["steel"], hm, co, ii))
    # bay window on the left inner wall (x=3.3): dark glass + frame
    add(box("part_baywindow_frame", (3.25, -5.0, 1.0), (3.35, -2.5, 3.0), C["offwhite"], hm, co, ii))
    add(box("part_baywindow_glass", (3.3, -4.85, 1.15), (3.4, -2.65, 2.85), C["glass"], hm, co, ii))
    # hanging cables from the back wall top
    for i, (x, h) in enumerate(((5.0, 1.4), (7.0, 0.9), (9.0, 1.7))):
        add(cyl(f"part_cable_hang{i}", 0.04, h, (x, -2.0, 3.7 - h / 2), (0, 0, 0), C["ink"], hm, co, seg=6, mat_index=ii))
    # work lamp: stand + head (emissive face)
    add(cyl("part_lamp_stand", 0.05, 1.6, (6.4, -4.4, 1.1), (0, 0, 0), C["steel"], hm, co, seg=8, mat_index=ii))
    add(cyl("part_lamp_base", 0.3, 0.06, (6.4, -4.4, 0.33), (0, 0, 0), C["steel"], hm, co, seg=12, mat_index=ii))
    head = add(cyl("part_lamp_head", 0.22, 0.3, (6.4, -4.4, 1.95), (60, 0, -20), C["amber"], hm, co, r2=0.12, seg=12, mat_index=2))
    light_anchor = empty("light_worklamp", (6.4, -4.4, 2.05), co, "SPHERE", 0.2)

    # extension cable: capsule collar -> floor -> lamp base
    cu = bpy.data.curves.new("part_ext_cable", "CURVE")
    cu.dimensions = "3D"
    cu.bevel_depth = 0.045
    cu.bevel_resolution = 2
    sp_ = cu.splines.new("BEZIER")
    pts = [(11.25, -3.75, 1.7), (10.6, -3.9, 0.36), (8.9, -5.1, 0.36), (7.3, -3.2, 0.36), (6.6, -4.3, 0.36)]
    sp_.bezier_points.add(len(pts) - 1)
    for bp, p in zip(sp_.bezier_points, pts):
        bp.co = p
        bp.handle_left_type = bp.handle_right_type = "AUTO"
    tmp = bpy.data.objects.new("_cable_tmp", cu)
    co.objects.link(tmp)
    bpy.context.view_layer.update()
    me = bpy.data.meshes.new_from_object(tmp.evaluated_get(bpy.context.evaluated_depsgraph_get()))
    bpy.data.objects.remove(tmp)
    bpy.data.curves.remove(cu)
    bm = bmesh.new()
    bm.from_mesh(me)
    bpy.data.meshes.remove(me)
    cable = add(_finish("part_ext_cable", bm, C["neon"], hm, co, mat_index=ii))

    for ob in obs + slots + [light_anchor]:
        parent_keep(ob, root)
    return root, ra, obs, head


def build_capsule(cols, M):
    co = cols["CAPSULE"]
    hm = [M["capsule_hull"], M["capsule_interior"], M["capsule_emissive"]]
    root = empty("capsule", DOCK, co, "ARROWS", 1.2)
    obs = []

    def add(ob):
        obs.append(ob)
        return ob

    cx = DOCK.x + 0.5 + 2.0  # body centre (collar 0.5 m, body 4 m)
    y, z = DOCK.y, DOCK.z
    body = add(sphere("hull_capsule", 1.0, (cx, y, z), (2.0, 1.1, 1.1), C["red"], hm, co))
    hollow(body, 0.2)
    add(cyl("part_capsule_nose", 0.75, 0.35, (DOCK.x + 0.45, y, z), (0, 90, 0), C["offwhite"], hm, co))
    add(cyl("part_rcs_ring", 1.18, 0.3, (cx + 0.6, y, z), (0, 90, 0), C["offwhite"], hm, co))
    for i, a in enumerate((0, 90, 180, 270)):
        r = math.radians(a)
        add(box(f"part_rcs_quad{i}", (-0.12, -0.12, -0.12), (0.12, 0.12, 0.12), C["offwhite"], hm, co))
        obs[-1].location = (cx + 0.6, y + 1.28 * math.cos(r), z + 1.28 * math.sin(r))
    add(sphere("part_canopy", 0.7, (cx - 0.9, y, z + 0.55), (1.0, 0.85, 0.6), C["glass"], hm, co))
    add(sphere("part_canopy_glow", 0.55, (cx - 0.95, y - 0.12, z + 0.62), (0.9, 0.7, 0.45), C["cyan"], hm, co, mat_index=2))
    # detached engine bell, small gap behind the body
    add(cyl("part_engine_bell", 0.35, 0.8, (cx + 2.55, y, z), (0, 90, 0), C["steel"], hm, co, r2=0.6))
    # open side hatch facing camera (-Y): warm glowing opening + swung door
    add(box("part_hatch_opening", (cx - 0.1, y - 1.13, z - 0.65), (cx + 0.9, y - 0.95, z + 0.45), C["amber"], hm, co, mat_index=2))
    door = add(box("part_hatch_door", (-0.5, -0.06, -0.55), (0.5, 0.06, 0.55), C["offwhite"], hm, co))
    door.location = (cx + 1.35, y - 1.55, z - 0.1)
    door.rotation_euler = Euler((0, 0, math.radians(-55)))
    # hazard stripe on capsule
    add(box("part_capsule_stripe", (cx - 0.35, y - 1.12, z + 0.55), (cx + 1.2, y - 0.9, z + 0.7), C["neon"], hm, co))
    empty("light_capsule_screens", (cx, y, z + 0.2), co, "SPHERE", 0.2)
    for ob in obs + [bpy.data.objects["light_capsule_screens"]]:
        parent_keep(ob, root)
    return root, obs


def build_debris(cols, M):
    co = cols["WRECK_CORE"]
    hm = [M["wreck_hull"], M["wreck_interior"], M["wreck_emissive"]]
    a = box("part_debris_plate", (-1.6, -0.08, -1.0), (1.6, 0.08, 1.0), C["violet"], hm, co)
    a.location = (16.0, 4.0, 14.5)
    a.rotation_euler = Euler((math.radians(40), math.radians(25), math.radians(60)))
    b = box("part_debris_chunk", (-0.5, -0.4, -0.3), (0.5, 0.4, 0.3), C["anthracite"], hm, co)
    b.location = (18.5, 2.5, 13.2)
    b.rotation_euler = Euler((math.radians(15), math.radians(50), math.radians(10)))
    return [a, b]


def make_cut(cols, M, room):
    co = cols["CUT_PREVIEW"]
    cut = box("CUT_BOX", (3.3, -8.0, 1.1), (11.2, -1.8, 6.0), C["cream"], [M["cap"]], co)
    cut.display_type = "WIRE"
    cut.hide_render = True
    mod = room.modifiers.new("CUT_PREVIEW", "BOOLEAN")
    mod.operation = "DIFFERENCE"
    mod.solver = "EXACT"
    mod.object = cut
    mod.material_mode = "TRANSFER"
    # move the boolean right after WALL so outline wraps the cut result
    while room.modifiers.find("CUT_PREVIEW") > 1:
        room.modifiers.move(room.modifiers.find("CUT_PREVIEW"), 1)
    return cut


def make_lights(cols, cam_forward, cam_right):
    co = cols["LIGHTS"]
    # cold key from top-left (screen space), slightly toward camera
    ld = bpy.data.lights.new("light_key", "SUN")
    ld.color = (0.72, 0.80, 1.0)
    ld.energy = 0.55
    ld.angle = math.radians(1.0)
    key = bpy.data.objects.new("light_key", ld)
    from_vec = (-cam_right * 1.0 + Vector((0, 0, 1.4)) - cam_forward * 0.4).normalized()
    key.rotation_euler = from_vec.to_track_quat("Z", "Y").to_euler()
    co.objects.link(key)
    # the single warm point light at the work lamp
    lp = bpy.data.lights.new("light_worklamp", "POINT")
    lp.color = C["amber"][:3]
    lp.energy = 1400
    lp.shadow_soft_size = 0.08
    # no shadows: light spills through the cut edges onto the surrounding hull
    lp.use_shadow = False
    lp.use_custom_distance = True
    lp.cutoff_distance = 11.0
    lamp = bpy.data.objects.new("light_worklamp_point", lp)
    lamp.location = (6.85, -3.9, 1.75)
    co.objects.link(lamp)
    return key, lamp


def make_world():
    w = bpy.data.worlds.get("World") or bpy.data.worlds.new("World")
    bpy.context.scene.world = w
    w.use_nodes = True
    nt = w.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputWorld")
    bg = nt.nodes.new("ShaderNodeBackground")
    bg.inputs["Color"].default_value = (0.035, 0.022, 0.07, 1)  # faint violet ambient
    bg.inputs["Strength"].default_value = 1.0
    lp = nt.nodes.new("ShaderNodeLightPath")
    blk = nt.nodes.new("ShaderNodeBackground")
    blk.inputs["Color"].default_value = (0, 0, 0, 1)
    mix = nt.nodes.new("ShaderNodeMixShader")
    nt.links.new(lp.outputs["Is Camera Ray"], mix.inputs[0])
    nt.links.new(bg.outputs[0], mix.inputs[1])
    nt.links.new(blk.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], out.inputs["Surface"])


# ---------------------------------------------------------------- camera + background
CAM_ROT = (62.0, 0.0, 25.0)
CAM_TARGET = Vector((1.08, 0.0, 3.15))
CAM_ORTHO = 46.0


def make_camera(cols):
    cd = bpy.data.cameras.new("Camera")
    cd.type = "ORTHO"
    cd.ortho_scale = CAM_ORTHO
    cd.clip_start = 0.1
    cd.clip_end = 1000
    cam = bpy.data.objects.new("Camera", cd)
    cam.rotation_euler = Euler([math.radians(a) for a in CAM_ROT])
    fwd = cam.rotation_euler.to_matrix() @ Vector((0, 0, -1))
    right = cam.rotation_euler.to_matrix() @ Vector((1, 0, 0))
    cam.location = CAM_TARGET - fwd * 150
    cols["CAMERA"].objects.link(cam)
    bpy.context.scene.camera = cam
    return cam, fwd, right


def make_background(cols, cam):
    co = cols["BACKGROUND"]
    # starfield quad parented to camera (same trick as the game's Backdrop)
    m = bpy.data.materials.new("M_starfield")
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    n, l = nt.nodes, nt.links
    out = n.new("ShaderNodeOutputMaterial")
    tc = n.new("ShaderNodeTexCoord")
    vor = n.new("ShaderNodeTexVoronoi")
    vor.inputs["Scale"].default_value = 90.0
    sep = n.new("ShaderNodeSeparateColor")
    cmp_ = n.new("ShaderNodeMath")
    cmp_.operation = "GREATER_THAN"
    cmp_.inputs[1].default_value = 0.93  # sparse: only ~7% of cells hold a star
    dist = n.new("ShaderNodeMath")
    dist.operation = "LESS_THAN"
    dist.inputs[1].default_value = 0.07
    mul = n.new("ShaderNodeMath")
    mul.operation = "MULTIPLY"
    em = n.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (0.85, 0.85, 1.0, 1)
    l.new(tc.outputs["UV"], vor.inputs["Vector"])
    l.new(vor.outputs["Color"], sep.inputs[0])
    l.new(sep.outputs[0], cmp_.inputs[0])
    l.new(vor.outputs["Distance"], dist.inputs[0])
    l.new(cmp_.outputs[0], mul.inputs[0])
    l.new(dist.outputs[0], mul.inputs[1])
    l.new(mul.outputs[0], em.inputs["Strength"])
    l.new(em.outputs[0], out.inputs["Surface"])
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=1.0)
    uv = bm.loops.layers.uv.new("UVMap")
    for f in bm.faces:
        for lo in f.loops:
            lo[uv].uv = (lo.vert.co.x * 0.5 + 0.5, (lo.vert.co.y * 0.5 + 0.5) * 9 / 16)
    me = bpy.data.meshes.new("bg_starfield")
    bm.to_mesh(me)
    bm.free()
    me.materials.append(m)
    sf = bpy.data.objects.new("bg_starfield", me)
    co.objects.link(sf)
    sf.parent = cam
    sf.location = (0, 0, -400)
    sf.scale = (CAM_ORTHO * 0.6, CAM_ORTHO * 0.6 * 9 / 16, 1)
    sf.visible_shadow = False

    # crescent planet: emission-only, fixed "sun" vector baked into the shader
    pm = bpy.data.materials.new("M_planet")
    pm.use_nodes = True
    nt = pm.node_tree
    nt.nodes.clear()
    n, l = nt.nodes, nt.links
    out = n.new("ShaderNodeOutputMaterial")
    geo = n.new("ShaderNodeNewGeometry")
    dot = n.new("ShaderNodeVectorMath")
    dot.operation = "DOT_PRODUCT"
    lightdir = (cam.rotation_euler.to_matrix() @ Vector((-0.9, 0.35, -0.75))).normalized()
    dot.inputs[1].default_value = lightdir
    ramp = n.new("ShaderNodeValToRGB")
    ramp.color_ramp.interpolation = "CONSTANT"
    e = ramp.color_ramp.elements
    e[0].position, e[0].color = 0.0, (0.004, 0.004, 0.012, 1)
    e[1].position, e[1].color = 0.62, hexcol("#7C8FD6")
    e.new(0.42).color = hexcol("#2E3470")
    em = n.new("ShaderNodeEmission")
    l.new(geo.outputs["Normal"], dot.inputs[0])
    l.new(dot.outputs["Value"], ramp.inputs[0])
    l.new(ramp.outputs[0], em.inputs["Color"])
    l.new(em.outputs[0], out.inputs["Surface"])
    planet = sphere("bg_planet", 1.0, (0, 0, 0), (1, 1, 1), (0, 0, 0, 1), [pm], co, seg=64, rings=32)
    planet.parent = cam
    planet.location = (-CAM_ORTHO * 0.40, -CAM_ORTHO * 0.33, -300)
    planet.scale = (6, 6, 6)
    planet.visible_shadow = False
    return sf, planet


# ---------------------------------------------------------------- render setup
def setup_render():
    s = bpy.context.scene
    s.render.engine = "BLENDER_EEVEE"
    s.render.resolution_x, s.render.resolution_y = 1920, 1080
    s.render.resolution_percentage = 100
    s.render.film_transparent = False
    s.eevee.taa_render_samples = 32
    s.eevee.use_shadows = True
    s.render.use_motion_blur = False
    for vt in ("Standard",):
        try:
            s.view_settings.view_transform = vt
        except TypeError as e:
            print("view transform:", e)
    s.view_settings.look = "None"
    s.view_settings.exposure = 0
    s.view_settings.gamma = 1
    setup_bloom(s)


def setup_bloom(s):
    """Soft bloom via compositor Glare (EEVEE Next has no built-in bloom)."""
    tree = bpy.data.node_groups.new("BloomComp", "CompositorNodeTree")
    tree.interface.new_socket("Image", in_out="OUTPUT", socket_type="NodeSocketColor")
    n, l = tree.nodes, tree.links
    rl = n.new("CompositorNodeRLayers")
    gl = n.new("CompositorNodeGlare")
    go = n.new("NodeGroupOutput")

    def setin(node, key, val):
        for sock in node.inputs:
            if sock.name.lower() == key.lower() or sock.identifier.lower() == key.lower():
                sock.default_value = val
                return True
        print("no input", key, [i.name for i in node.inputs])
        return False

    setin(gl, "Type", "Bloom")
    setin(gl, "Quality", "High")
    setin(gl, "Threshold", 0.85)
    setin(gl, "Strength", 0.55)
    setin(gl, "Size", 0.65)
    l.new(rl.outputs["Image"], gl.inputs["Image"])
    l.new(gl.outputs["Image"], go.inputs[0])
    s.compositing_node_group = tree
    s.render.use_compositing = True


# ---------------------------------------------------------------- main
def build():
    reset()
    cols = make_collections()
    M = make_materials()
    make_world()
    cam, fwd, right = make_camera(cols)
    wreck_root, room, wreck_obs, _ = build_wreck(cols, M)
    cap_root, cap_obs = build_capsule(cols, M)
    debris = build_debris(cols, M)
    make_cut(cols, M, room)
    make_lights(cols, fwd, right)
    make_background(cols, cam)
    ink = M["ink"]
    for ob in list(cols["WRECK_CORE"].objects) + list(cols["CAPSULE"].objects):
        if ob.type == "MESH":
            outline(ob, ink, 0.07)
    # cable: outline via a second curve object is overkill for pass 1; keep plain
    setup_render()
    return cols


if __name__ == "__main__" or True:
    build()
    print("built:", len(bpy.data.objects), "objects")
