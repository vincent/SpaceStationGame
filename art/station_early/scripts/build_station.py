"""Pass 2 (detail) of the early-game diorama: capsule docked to the wreck core.

Headless:  blender -b --factory-startup --python art/station_early/scripts/make_pass2.py
In a live Blender:  exec(open(PATH).read()); build()

Conventions follow docs/ART_PIPELINE.md and src/tools/module_import_rules.gd:
  hull            one watertight, thick shell per module (exported as "hull")
  slot_<X>        empties; their local -Y (Blender) == +Z (Godot) points out
  part_<name>     explodable / upgradable parts (extras "explode_dir", Godot axes)
  light_<name>    light anchors          <name>-col / <name>-nav   collision / walkable
  prop_<name>     interior clutter (plain meshes)
  greebles_<mod>  parent of all greeble instances (linked duplicates of GREEBLE_KIT)
Names that would collide between modules carry an "@module" suffix that the
exporter strips ("hull@capsule" -> "hull").
Colour attributes: "Base" = flat preview colour (Blender only),
                   "Masks" = R wear, G emissive, B trim (exported as COLOR_0).
"""
import math
import os
import random

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector, noise

HERE = os.path.dirname(os.path.abspath(__file__)) if "__file__" in dir() else \
    "/home/vincent/Workspace/Perso/space-station-tycoon/art/station_early/scripts"
ROOT = os.path.dirname(HERE)


# ================================================================ palette
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
    # derived neutrals (mixes of the palette, used sparingly)
    "steel": "#3A3D47", "steel_lt": "#5A5D6A", "rust": "#7A3B22",
    "rust_dk": "#4E2A1E", "glass": "#0E1226", "crate": "#5B4A3A",
    # weathered capsule livery (the wreck is the capsule's faded, older sibling)
    "red_faded": "#A8483A", "offwhite_old": "#C8C2B4",
}
C = {k: hexcol(v) for k, v in PAL.items()}
NOMASK = (0.0, 0.0, 0.0, 1.0)


def mask(r=0.0, g=0.0, b=0.0):
    return (r, g, b, 1.0)


def E(rx=0.0, ry=0.0, rz=0.0):
    return Euler((math.radians(rx), math.radians(ry), math.radians(rz)))


# face presets: rotation that maps kit local +Z (outward) onto the face normal,
# kit local +Y onto "up the wall"
FACE = {
    "-Y": E(90, 0, 0), "+X": E(90, 0, 90), "+Z": E(0, 0, 0),
    "-X": E(90, 0, -90), "+Y": E(90, 0, 180),
}


# ================================================================ scene reset
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
    out = {}
    for n in ["CAPSULE", "WRECK_CORE", "GREEBLE_KIT", "LIGHTS", "CAMERA",
              "CUT_PREVIEW", "BACKGROUND"]:
        c = bpy.data.collections.new(n)
        bpy.context.scene.collection.children.link(c)
        out[n] = c
    out["GREEBLE_KIT"].hide_render = True
    return out


# ================================================================ materials
def toon_group():
    """3-step constant ramp on light intensity, tinted by the light's hue:
    out = Base * ramp(max(L.rgb)) * mix(white, L / max(L.rgb), 0.85)."""
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


def _vmath(nt, op, a, b, c=None):
    node = nt.nodes.new("ShaderNodeVectorMath")
    node.operation = op
    for i, src in enumerate((a, b, c)):
        if src is None:
            continue
        if isinstance(src, tuple):
            node.inputs[i].default_value = src[:3]
        else:
            nt.links.new(src, node.inputs[i])
    return node.outputs[0]


def _base_socket(nt, lighten=0.0, wear=True):
    """Base attribute, worn toward rust by Masks.R, optionally lightened."""
    at = nt.nodes.new("ShaderNodeAttribute")
    at.attribute_name = "Base"
    out = at.outputs["Color"]
    if wear:
        mk = nt.nodes.new("ShaderNodeAttribute")
        mk.attribute_name = "Masks"
        sep = nt.nodes.new("ShaderNodeSeparateColor")
        nt.links.new(mk.outputs["Color"], sep.inputs[0])
        k = nt.nodes.new("ShaderNodeMath")
        k.operation = "MULTIPLY"
        k.inputs[1].default_value = 0.55
        nt.links.new(sep.outputs[0], k.inputs[0])
        diff = _vmath(nt, "SUBTRACT", C["rust_dk"], out)
        out = _vmath(nt, "MULTIPLY_ADD", diff, k.outputs[0], out)
    if lighten:
        out = _vmath(nt, "MULTIPLY_ADD", out, (1 - lighten,) * 3,
                     tuple(c * lighten for c in C["cream"][:3]))
    return out


def toon_mat(name, lighten=0.0, fixed=None):
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
    if fixed is not None:
        rgb = n.new("ShaderNodeRGB")
        rgb.outputs[0].default_value = fixed
        l.new(rgb.outputs[0], grp.inputs["Base"])
        m.diffuse_color = fixed
    else:
        l.new(_base_socket(nt, lighten), grp.inputs["Base"])
    l.new(grp.outputs[0], em.inputs["Color"])
    l.new(em.outputs[0], out.inputs["Surface"])
    return m


def emissive_mat(name, strength):
    """Glows Base * Masks.G (G = emissive mask)."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    at = nt.nodes.new("ShaderNodeAttribute")
    at.attribute_name = "Base"
    mk = nt.nodes.new("ShaderNodeAttribute")
    mk.attribute_name = "Masks"
    sep = nt.nodes.new("ShaderNodeSeparateColor")
    k = nt.nodes.new("ShaderNodeMath")
    k.operation = "MULTIPLY"
    k.inputs[1].default_value = strength
    nt.links.new(mk.outputs["Color"], sep.inputs[0])
    nt.links.new(sep.outputs[1], k.inputs[0])
    nt.links.new(at.outputs["Color"], em.inputs["Color"])
    nt.links.new(k.outputs[0], em.inputs["Strength"])
    nt.links.new(em.outputs[0], out.inputs["Surface"])
    return m


def flat_emit_mat(name, color, strength=1.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = color
    em.inputs["Strength"].default_value = strength
    nt.links.new(em.outputs[0], out.inputs["Surface"])
    m.diffuse_color = color
    return m


M = {}


def make_materials():
    toon_group()
    # the 3 game materials, shared by both modules (slot order is fixed)
    M["hull"] = toon_mat("M_hull")
    M["interior"] = toon_mat("M_interior", lighten=0.2)
    M["emissive"] = emissive_mat("M_emissive", 5.0)
    # preview-only
    M["ink"] = flat_emit_mat("M_ink_outline", C["ink"])
    M["ink"].use_backface_culling = True
    M["ink"].use_backface_culling_shadow = True  # outline shells must not block lights
    M["cap"] = toon_mat("M_cut_cap", fixed=C["cream"])
    return [M["hull"], M["interior"], M["emissive"]]


HULL, INT, EMI = 0, 1, 2


# ================================================================ mesh builder
class MB:
    """Accumulates coloured primitives into one bmesh (Base + Masks per corner)."""

    def __init__(self):
        self.bm = bmesh.new()
        self.base = self.bm.loops.layers.float_color.new("Base")
        self.mask = self.bm.loops.layers.float_color.new("Masks")

    def _tag(self, verts, xform, color, msk, mat):
        bmesh.ops.transform(self.bm, matrix=xform, verts=verts)
        faces = {f for v in verts for f in v.link_faces}
        for f in faces:
            f.material_index = mat
            for lo in f.loops:
                lo[self.base] = color
                lo[self.mask] = msk
        return faces

    @staticmethod
    def _m(loc, rot, scale):
        r = rot if isinstance(rot, Euler) else E(*rot)
        return (Matrix.Translation(Vector(loc)) @ r.to_matrix().to_4x4()
                @ Matrix.Diagonal(Vector(scale).to_4d()))

    def box(self, mn, mx, color, msk=NOMASK, mat=HULL, rot=(0, 0, 0), taper=None):
        mn, mx = Vector(mn), Vector(mx)
        v = bmesh.ops.create_cube(self.bm, size=1.0)["verts"]
        if taper:  # scale the -Y end in X (for streaks / wedges)
            for vv in v:
                if vv.co.y < 0:
                    vv.co.x *= taper
        return self._tag(v, self._m((mn + mx) / 2, rot, mx - mn), color, msk, mat)

    def cyl(self, r, depth, loc, rot, color, msk=NOMASK, mat=HULL, r2=None, seg=12):
        v = bmesh.ops.create_cone(self.bm, cap_ends=True, cap_tris=False, segments=seg,
                                  radius1=r, radius2=r if r2 is None else r2,
                                  depth=depth)["verts"]
        return self._tag(v, self._m(loc, rot, (1, 1, 1)), color, msk, mat)

    def ring(self, r_out, r_in, depth, loc, rot, color, msk=NOMASK, mat=HULL, seg=24):
        """Closed tube (annulus extruded along local Z)."""
        rings = []
        for r, z in ((r_out, -depth / 2), (r_out, depth / 2), (r_in, depth / 2), (r_in, -depth / 2)):
            rings.append([self.bm.verts.new((r * math.cos(2 * math.pi * i / seg),
                                             r * math.sin(2 * math.pi * i / seg), z)) for i in range(seg)])
        new_faces = []
        for k in range(4):
            a, b = rings[k], rings[(k + 1) % 4]
            for i in range(seg):
                j = (i + 1) % seg
                new_faces.append(self.bm.faces.new((a[i], a[j], b[j], b[i])))
        bmesh.ops.recalc_face_normals(self.bm, faces=new_faces)
        return self._tag([v for r in rings for v in r], self._m(loc, rot, (1, 1, 1)), color, msk, mat)

    def sphere(self, r, loc, scale, color, msk=NOMASK, mat=HULL, seg=16, rings=8, rot=(0, 0, 0)):
        v = bmesh.ops.create_uvsphere(self.bm, u_segments=seg, v_segments=rings, radius=r)["verts"]
        return self._tag(v, self._m(loc, rot, scale), color, msk, mat)

    def text(self, body, size, loc, rot, color, msk=NOMASK, mat=HULL, depth=0.012):
        cu = bpy.data.curves.new("_txt", "FONT")
        cu.body = body
        cu.size = size
        cu.extrude = depth
        cu.resolution_u = 2
        cu.align_x = "CENTER"
        cu.align_y = "CENTER"
        ob = bpy.data.objects.new("_txt", cu)
        bpy.context.scene.collection.objects.link(ob)
        bpy.context.view_layer.update()
        me = bpy.data.meshes.new_from_object(ob.evaluated_get(bpy.context.evaluated_depsgraph_get()))
        bpy.data.objects.remove(ob)
        bpy.data.curves.remove(cu)
        me.transform(self._m(loc, rot, (1, 1, 1)) @ Matrix.Translation((0, 0, depth)))
        self.append_mesh(me, color, msk, mat)
        bpy.data.meshes.remove(me)

    def append_mesh(self, me, color=None, msk=None, mat=None):
        n0 = len(self.bm.faces)
        self.bm.from_mesh(me)
        self.bm.faces.ensure_lookup_table()
        for f in self.bm.faces[n0:]:
            if mat is not None:
                f.material_index = mat
            for lo in f.loops:
                if color is not None:
                    lo[self.base] = color
                if msk is not None:
                    lo[self.mask] = msk

    def tube(self, pts, r, color, msk=NOMASK, mat=HULL, res=6):
        """Bezier cable through pts, baked to mesh."""
        cu = bpy.data.curves.new("_cable", "CURVE")
        cu.dimensions = "3D"
        cu.bevel_depth = r
        cu.bevel_resolution = 1
        cu.resolution_u = res
        cu.use_fill_caps = True
        sp = cu.splines.new("BEZIER")
        sp.bezier_points.add(len(pts) - 1)
        for bp, p in zip(sp.bezier_points, pts):
            bp.co = p
            bp.handle_left_type = bp.handle_right_type = "AUTO"
        ob = bpy.data.objects.new("_cable", cu)
        bpy.context.scene.collection.objects.link(ob)
        bpy.context.view_layer.update()
        me = bpy.data.meshes.new_from_object(ob.evaluated_get(bpy.context.evaluated_depsgraph_get()))
        bpy.data.objects.remove(ob)
        bpy.data.curves.remove(cu)
        self.append_mesh(me, color, msk, mat)
        bpy.data.meshes.remove(me)

    def to_mesh(self, name, mats):
        me = bpy.data.meshes.new(name)
        self.bm.to_mesh(me)
        self.bm.free()
        for m in mats:
            me.materials.append(m)
        _activate_masks(me)
        smooth(me)
        return me

    def to_object(self, name, coll, mats, origin=None):
        if origin is None:  # bounding-box centre
            vs = [v.co for v in self.bm.verts]
            origin = (Vector(map(min, zip(*vs))) + Vector(map(max, zip(*vs)))) / 2 if vs else Vector()
        origin = Vector(origin)
        bmesh.ops.translate(self.bm, vec=-origin, verts=self.bm.verts)
        ob = bpy.data.objects.new(name, self.to_mesh(name, mats))
        ob.location = origin
        coll.objects.link(ob)
        return ob


# ================================================================ rounded hulls (capsule style)
def rr_profile(y0, y1, z0, z1, radii, grow=0.0, seg=6):
    """Rounded-rectangle loop in YZ (counter-clockwise seen from +X). radii =
    (front-bottom, front-top, back-top, back-bottom) = corners (y0,z0) (y0,z1) (y1,z1) (y1,z0).
    `grow` offsets the outline outward (negative = inset). Always 4 * (seg + 1) points."""
    y0, y1, z0, z1 = y0 - grow, y1 + grow, z0 - grow, z1 + grow
    corners = (((y0, z0), (1, 1), math.pi), ((y1, z0), (-1, 1), 1.5 * math.pi),
               ((y1, z1), (-1, -1), 0.0), ((y0, z1), (1, -1), 0.5 * math.pi))
    rs = (radii[0], radii[3], radii[2], radii[1])
    pts = []
    for ((cy, cz), (sy, sz), a0), r in zip(corners, rs):
        r = max(0.02, r + grow)
        oy, oz = cy + sy * r, cz + sz * r
        for i in range(seg + 1):
            a = a0 + (math.pi / 2) * i / seg
            pts.append((oy + r * math.cos(a), oz + r * math.sin(a)))
    return pts


def _loft(mb, loops, cap0=True, cap1=True):
    """Closed solid from a list of equal-length vertex loops (bmesh verts)."""
    faces = []
    n = len(loops[0])
    for a, b in zip(loops, loops[1:]):
        for i in range(n):
            j = (i + 1) % n
            faces.append(mb.bm.faces.new((a[i], a[j], b[j], b[i])))
    if cap0:
        faces.append(mb.bm.faces.new(list(reversed(loops[0]))))
    if cap1:
        faces.append(mb.bm.faces.new(loops[-1]))
    bmesh.ops.recalc_face_normals(mb.bm, faces=faces)
    return faces


def rounded_hull(mb, x0, x1, y0, y1, z0, z1, radii, dome=(0.0, 0.0), squeeze=0.45,
                 step=1.6, seg=4, grow=0.0):
    """Capsule-style hull: a rounded-rectangle section lofted along X, ring every
    `step` m (panel seams), ends optionally domed over `dome` m (section scaled down
    to `squeeze`). Watertight. Returns its faces (uncoloured)."""
    prof = rr_profile(y0, y1, z0, z1, radii, grow, seg)
    cy, cz = (y0 + y1) / 2, (z0 + z1) / 2
    xs = []  # (x, scale)
    d0, d1 = dome
    nd = 3
    for i in range(nd if d0 else 0):
        t = (math.pi / 2) * (1 - i / nd)
        xs.append((x0 + d0 * (1 - math.sin(t)), squeeze + (1 - squeeze) * math.cos(t)))
    a, b = x0 + d0, x1 - d1
    n = max(1, round((b - a) / step))
    xs += [(a + (b - a) * i / n, 1.0) for i in range(n + 1)]
    for i in range(1, nd + 1 if d1 else 1):
        t = (math.pi / 2) * i / nd
        xs.append((b + d1 * math.sin(t), squeeze + (1 - squeeze) * math.cos(t)))
    loops = [[mb.bm.verts.new((x, cy + (py - cy) * k, cz + (pz - cz) * k)) for py, pz in prof]
             for x, k in xs]
    return _loft(mb, loops)


def rounded_band(mb, x0, x1, y0, y1, z0, z1, radii, grow=0.12, inset=0.08, seg=4):
    """Closed ring band hugging a rounded hull section (like the capsule RCS ring):
    a tube from `inset` inside the skin to `grow` outside, x0..x1."""
    po = rr_profile(y0, y1, z0, z1, radii, grow, seg)
    pi = rr_profile(y0, y1, z0, z1, radii, -inset, seg)
    rings = [[mb.bm.verts.new((x, py, pz)) for py, pz in pr]
             for x, pr in ((x0, po), (x1, po), (x1, pi), (x0, pi))]
    faces = []
    n = len(po)
    for k in range(4):
        a, b = rings[k], rings[(k + 1) % 4]
        for i in range(n):
            j = (i + 1) % n
            faces.append(mb.bm.faces.new((a[i], a[j], b[j], b[i])))
    bmesh.ops.recalc_face_normals(mb.bm, faces=faces)
    return faces


def livery(mb, faces, split_z, rng, faded=0.3, wear=0.15):
    """Paint faces like the capsule: offwhite above split_z (trim mask), red below;
    a share of the panels is faded / older (the wreck's weathered livery)."""
    panels = {}  # fade whole ~2 m hull panels, not single faces
    for f in faces:
        c = f.calc_center_median()
        top = c.z > split_z
        key = (round(c.x / 2.2), round(c.y / 2.0), round(c.z / 2.0), top)
        if key not in panels:
            panels[key] = rng.random() < faded
        old = panels[key]
        if top:
            col, msk = C["offwhite_old" if old else "offwhite"], mask(wear, 0, 1)
        else:
            col, msk = C["red_faded" if old else "red"], mask(wear + 0.1)
        f.material_index = HULL
        for lo in f.loops:
            lo[mb.base] = col
            lo[mb.mask] = msk


def paint(mb, faces, color, msk, mat=HULL):
    for f in faces:
        f.material_index = mat
        for lo in f.loops:
            lo[mb.base] = color
            lo[mb.mask] = msk


def smooth(me, angle=35.0):
    """Smooth shading, edges sharper than `angle` stay hard (toon-friendly)."""
    me.shade_smooth()
    me.set_sharp_from_angle(angle=math.radians(angle))


def _activate_masks(me):
    ca = me.color_attributes
    if "Masks" in ca:
        ca.active_color = ca["Masks"]
        ca.render_color_index = list(ca.keys()).index("Masks")


def bake(ob, keep_mods=()):
    """Apply all modifiers (except keep_mods) into a new mesh in place."""
    saved = {}
    for md in ob.modifiers:
        if md.name in keep_mods:
            saved[md.name] = md.show_viewport
            md.show_viewport = False
    bpy.context.view_layer.update()
    me = bpy.data.meshes.new_from_object(ob.evaluated_get(bpy.context.evaluated_depsgraph_get()))
    old = ob.data
    ob.data = me
    for md in list(ob.modifiers):
        if md.name not in keep_mods:
            ob.modifiers.remove(md)
        else:
            md.show_viewport = saved[md.name]
    if old.users == 0:
        bpy.data.meshes.remove(old)
    _activate_masks(me)
    smooth(me)
    return ob


def solidify_in(ob, t):
    md = ob.modifiers.new("WALL", "SOLIDIFY")
    md.thickness = t
    md.offset = -1.0
    md.use_even_offset = True
    md.material_offset = 1  # inner shell -> interior material
    return md


def add_outline(ob, thickness=0.06):
    if ob.type != "MESH":
        return
    if M["ink"].name not in [m.name for m in ob.data.materials if m]:
        ob.data.materials.append(M["ink"])
    md = ob.modifiers.new("OUTLINE", "SOLIDIFY")
    md.thickness = thickness
    md.offset = 1.0
    md.use_flip_normals = True
    md.use_rim = False
    md.material_offset = 100  # clamps to the last slot = ink
    md.show_in_editmode = False


def empty(name, loc, coll, kind="PLAIN_AXES", size=0.5, rot=(0, 0, 0)):
    e = bpy.data.objects.new(name, None)
    e.empty_display_type = kind
    e.empty_display_size = size
    e.location = loc
    e.rotation_euler = E(*rot)
    coll.objects.link(e)
    return e


def parent_keep(child, parent):
    child.parent = parent
    child.matrix_parent_inverse = parent.matrix_basis.inverted()


# ================================================================ greeble kit
KIT = {}


def build_kit(cols):
    """Each kit item: closed solid(s), local +Z = out of the surface, base at z=0,
    local +Y = up the wall. Instances are linked duplicates of these meshes."""
    co = cols["GREEBLE_KIT"]
    mats = [M["hull"], M["interior"], M["emissive"]]
    shelf = [0]

    def done(name, mb):
        ob = mb.to_object(name, co, mats, origin=Vector())
        ob.location = (70 + shelf[0] * 3, 40, 0)
        shelf[0] += 1
        KIT[name] = ob.data

    mb = MB()  # pipe, 1 m along X
    mb.cyl(0.1, 1.0, (0, 0, 0.11), (0, 90, 0), C["steel"], mask(0.2), seg=10)
    done("gk_pipe", mb)
    mb = MB()
    mb.cyl(0.055, 1.0, (0, 0, 0.065), (0, 90, 0), C["darkblue"], mask(0.1), seg=8)
    done("gk_pipe_thin", mb)
    mb = MB()  # pipe flange / clamp
    mb.cyl(0.16, 0.08, (0, 0, 0.12), (0, 90, 0), C["steel_lt"], mask(0.5), seg=10)
    done("gk_clamp", mb)
    mb = MB()  # vent: housing + slats
    mb.box((-0.45, -0.3, 0), (0.45, 0.3, 0.12), C["steel"], mask(0.6))
    for i in range(4):
        y = -0.21 + i * 0.14
        mb.box((-0.38, y - 0.03, 0.12), (0.38, y + 0.03, 0.16), C["ink"], mask(0.8))
    done("gk_vent", mb)
    for nm, col, b in (("gk_panel_blue", "darkblue", 1.0), ("gk_panel_violet", "violet", 1.0),
                       ("gk_panel_grey", "steel", 0.0), ("gk_panel_white", "offwhite_old", 1.0),
                       ("gk_panel_red", "red_faded", 0.0)):
        mb = MB()  # patched plate with 4 bolts
        mb.box((-0.5, -0.5, 0), (0.5, 0.5, 0.04), C[col], mask(0.3, 0, b))
        for sx in (-0.42, 0.42):
            for sy in (-0.42, 0.42):
                mb.box((sx - 0.03, sy - 0.03, 0.04), (sx + 0.03, sy + 0.03, 0.07), C["steel_lt"], mask(0.9))
        done(nm, mb)
    mb = MB()  # tank lying along X
    mb.cyl(0.5, 1.6, (0, 0, 0.52), (0, 90, 0), C["darkblue"], mask(0.3, 0, 1), seg=14)
    for sx in (-0.8, 0.8):
        mb.sphere(0.5, (sx, 0, 0.52), (0.35, 1, 1), C["darkblue"], mask(0.4, 0, 1), seg=14, rings=6)
    for sx in (-0.45, 0.45):
        mb.cyl(0.53, 0.1, (sx, 0, 0.52), (0, 90, 0), C["steel_lt"], mask(0.7), seg=14)
    mb.box((-0.6, -0.3, 0), (0.6, 0.3, 0.1), C["steel"], mask(0.5))
    done("gk_tank", mb)
    mb = MB()  # small machinery box
    mb.box((-0.3, -0.2, 0), (0.3, 0.2, 0.3), C["steel"], mask(0.4))
    mb.box((-0.15, -0.12, 0.3), (0.1, 0.12, 0.4), C["steel_lt"], mask(0.6))
    mb.cyl(0.05, 0.25, (0.2, 0, 0.42), (0, 0, 0), C["ink"], mask(0.2), seg=6)
    done("gk_box", mb)
    for nm, col in (("gk_crate", "crate"), ("gk_crate_blue", "darkblue")):
        mb = MB()  # crate, 0.8 m, sits on the floor (+Z up)
        mb.box((-0.4, -0.4, 0), (0.4, 0.4, 0.8), C[col], mask(0.4))
        for sx in (-0.25, 0.25):
            mb.box((sx - 0.04, -0.42, -0.0), (sx + 0.04, 0.42, 0.82), C["offwhite"], mask(0.3))
        mb.box((-0.12, -0.415, 0.5), (0.12, -0.405, 0.65), C["neon"], mask(0.2))  # label
        done(nm, mb)
    mb = MB()  # cable bundle, 1 m along X (one pink accent)
    for i, (y, col) in enumerate(((-0.08, "ink"), (0.0, "darkblue"), (0.08, "violet"))):
        mb.cyl(0.035, 1.0, (0, y, 0.04), (0, 90, 0), C[col], mask(0.1), seg=6)
    done("gk_cables", mb)
    mb = MB()  # hazard strip, 2 m: alternating yellow / ink chevrons
    for i in range(10):
        x0 = -1.0 + i * 0.2
        mb.box((x0, -0.1, 0), (x0 + 0.2, 0.1, 0.02), C["neon"] if i % 2 == 0 else C["ink"],
               mask(0.35, 0, 1), rot=(0, 0, 0))
    done("gk_hazard", mb)
    mb = MB()  # rust streak, hangs down (-Y) from its origin
    mb.box((-0.12, -1.4, 0), (0.12, 0.0, 0.012), C["rust"], mask(1.0), taper=0.25)
    done("gk_rust_streak", mb)
    mb = MB()  # chipped-paint fleck
    mb.box((-0.18, -0.09, 0), (0.18, 0.09, 0.01), C["steel_lt"], mask(0.6), rot=(0, 0, 12))
    mb.box((0.05, -0.16, 0), (0.22, 0.02, 0.01), C["steel_lt"], mask(0.6), rot=(0, 0, -20))
    done("gk_chip", mb)
    mb = MB()  # bolt row, 1 m
    for i in range(6):
        x = -0.45 + i * 0.18
        mb.box((x - 0.035, -0.035, 0), (x + 0.035, 0.035, 0.04), C["steel_lt"], mask(0.9))
    done("gk_bolts", mb)
    mb = MB()  # porthole rim
    mb.cyl(0.6, 0.1, (0, 0, 0.05), (0, 0, 0), C["steel_lt"], mask(0.6), seg=16)
    for a in range(0, 360, 60):
        r = math.radians(a)
        mb.box((0.48 * math.cos(r) - 0.03, 0.48 * math.sin(r) - 0.03, 0.1),
               (0.48 * math.cos(r) + 0.03, 0.48 * math.sin(r) + 0.03, 0.13), C["ink"], mask(0.9))
    done("gk_porthole_rim", mb)
    mb = MB()  # taped note (interior)
    mb.box((-0.1, -0.13, 0), (0.1, 0.13, 0.008), C["offwhite"], mask(0.2), rot=(0, 0, 6))
    mb.box((-0.07, 0.1, 0.008), (0.07, 0.14, 0.014), C["neon"], mask(0.0))
    done("gk_note", mb)
    mb = MB()  # floor plate with seam (interior)
    mb.box((-0.6, -0.6, 0), (0.6, 0.6, 0.03), C["steel"], mask(0.5))
    mb.box((-0.6, -0.02, 0.03), (0.6, 0.02, 0.04), C["ink"], mask(0.8))
    done("gk_floor_plate", mb)
    for txt in ("07", "A-01", "B-2", "C", "C-3", "SR-7", "DOCK", "14"):
        mb = MB()
        mb.text(txt, 0.6, (0, 0, 0), (0, 0, 0), C["offwhite"], mask(0.45))
        done("gk_stencil_" + txt.replace("-", ""), mb)
    for ob in co.objects:
        ob.hide_render = True


_count = {}


def put(kit, loc, face="+Z", spin=0.0, scale=(1, 1, 1), coll=None, parent=None,
        interior=False, name=None, lift=0.012):
    """Linked duplicate of a kit mesh on a surface (1 cm proud by default)."""
    me = KIT[kit]
    _count[kit] = _count.get(kit, 0) + 1
    ob = bpy.data.objects.new(name or f"gb_{kit[3:]}_{_count[kit]:02d}", me)
    rot = FACE[face].to_matrix() @ E(0, 0, spin).to_matrix()
    nrm = rot @ Vector((0, 0, 1))
    ob.location = Vector(loc) + nrm * lift
    ob.rotation_euler = rot.to_euler()
    ob.scale = scale
    if interior:  # object-level material override: hull slot -> interior material
        ob.material_slots[0].link = "OBJECT"
        ob.material_slots[0].material = M["interior"]
    coll.objects.link(ob)
    if parent:
        parent_keep(ob, parent)
    return ob


def pipe_run(a, b, face, coll, parent, kit="gk_pipe", clamps=True, interior=False):
    a, b = Vector(a), Vector(b)
    d = b - a
    length = d.length
    rot = FACE[face].to_matrix()
    # spin so kit local X follows a->b
    local = rot.inverted() @ d
    spin = math.degrees(math.atan2(local.y, local.x))
    put(kit, (a + b) / 2, face, spin, (length, 1, 1), coll, parent, interior)
    if clamps:
        n = max(2, int(length / 2.0))
        for i in range(n + 1):
            put("gk_clamp", a + d * (i / n), face, spin, coll=coll, parent=parent,
                interior=interior)


# ================================================================ modules
# Module grids (must match the interior_ascii of src/station/modules/*.tscn):
#   wreck_core  "######" / "vC..S#" / "b....a" / "##W#c#"   6 x 4 cells
#   capsule     "#####"  / "aP.B#"  / "#..K#" / "#####"      5 x 4 cells
# One cell = 2 m. Game floor top (y = 0) = Blender z 0.3. ASCII column -> +X,
# ASCII row -> -Y (Godot +Z = Blender -Y). Module origin = layout centre on the floor.
CELL = 2.0
FLOOR_Z = 0.3
WRECK_ORIGIN = Vector((7.2, -3.7, FLOOR_Z))
CAP_ORIGIN = Vector((16.8, -5.7, FLOOR_Z))
DOOR_Y = -4.7  # row of the capsule doorway (wreck slot A / capsule slot A)
SLOT_OUT = 0.15  # slot markers sit just outside the hull (Slot.GAP)


def cell_xy(origin, cols, rows, c, r):
    """Blender XY of grid cell (c, r) for a module with `cols` x `rows` cells."""
    return (origin.x - (cols - 1) * CELL / 2 + c * CELL, origin.y + (rows - 1) * CELL / 2 - r * CELL)


def build_wreck(cols, mats):
    co = cols["WRECK_CORE"]
    root = empty("wreck_core", WRECK_ORIGIN, co, "ARROWS", 1.5)
    gparent = empty("greebles_wreck", WRECK_ORIGIN, co, "PLAIN_AXES", 0.3)
    parent_keep(gparent, root)
    owned = []

    def own(ob):
        owned.append(ob)
        return ob

    # ---------------------------------------------------------- hull (one object)
    pieces, cutters = [], []

    def shell(build, thick=None, holes=()):
        mb = MB()
        build(mb)
        ob = mb.to_object("_piece", co, mats)
        if thick:
            solidify_in(ob, thick)
        if holes:
            cm = MB()
            for mn, mx in holes:
                cm.box(mn, mx, C["steel"], mask(0.6))
            cutter = cm.to_object("_holes", co, mats)
            md = ob.modifiers.new("DOORS", "BOOLEAN")
            md.operation = "DIFFERENCE"
            md.solver = "EXACT"
            md.object = cutter
            cutters.append(cutter)
        pieces.append(ob)

    dz = (FLOOR_Z, FLOOR_Z + 2.4)
    room_a_doors = [  # doorway holes (slot doors), 1.6 m wide, 2.4 m high
        ((11.0, DOOR_Y - 0.8, dz[0]), (11.5, DOOR_Y + 0.8, dz[1])),   # A  (+X, capsule)
        ((2.4, DOOR_Y - 0.8, dz[0]), (3.4, DOOR_Y + 0.8, dz[1])),     # B  (-X)
        ((2.4, -3.5, dz[0]), (3.4, -1.9, dz[1])),                     # V  (-X, visitors)
        ((9.4, -6.5, dz[0]), (11.0, -5.5, dz[1])),                    # C  (front)
    ]
    # Capsule-style hull: rounded sections, offwhite over red, ring bands. The wreck
    # is the capsule's older sibling: faded panels, rust, a torn-open window.
    HUB = dict(x0=-14, x1=11.5, y0=-1.5, y1=6, z0=0, z1=7, radii=(1.2, 1.8, 1.4, 1.2))
    POD = dict(x0=-4, x1=5, y0=0, y1=5, z0=6.9, z1=10.0, radii=(1.0, 1.0, 1.0, 1.0))
    TANK = dict(x0=-18, x1=-5, y0=0.2, y1=5.0, z0=6.8, z1=11.6, radii=(2.3,) * 4)
    ROOM_A = dict(x0=2.9, x1=11.5, y0=-6, y1=-1.4, z0=-0.02, z1=4, radii=(0.3, 1.2, 0.7, 0.3))

    def sect(d):
        return d["y0"], d["y1"], d["z0"], d["z1"], d["radii"]

    def body(d, split, dome=(0.0, 0.0), squeeze=0.45, step=1.6):
        def build(mb):
            f = rounded_hull(mb, d["x0"], d["x1"], *sect(d), dome=dome, squeeze=squeeze, step=step)
            livery(mb, f, split, random)
        return build

    shell(body(HUB, 3.1, dome=(1.8, 0.0), squeeze=0.6, step=2.2), 0.3)  # main hub (room B)
    shell(body(POD, 8.2, dome=(1.2, 1.2), squeeze=0.4, step=2.2), 0.3)  # upper pod (room C)
    shell(body(TANK, 8.6, dome=(2.0, 2.0), squeeze=0.3, step=2.2), 0.3)  # long tank
    # Room A: interior x 3.2..11.2, y -5.7..-1.7 (4 x 2 cells), floor top at z 0.28;
    # flat floor, flat front wall up to z 2.8 (doorway C, bay window), flat ends
    shell(body(ROOM_A, 2.0, step=2.15), 0.3, room_a_doors)

    def trim(mb):  # solid trim: ring bands, the torn window, portholes
        for x in (-9.0, -2.0, 5.0):
            paint(mb, rounded_band(mb, x - 0.3, x + 0.3, *sect(HUB)), C["offwhite"], mask(0.3, 0, 1))
        paint(mb, rounded_band(mb, 10.85, 11.5, *sect(HUB), grow=0.1), C["steel_lt"], mask(0.4))
        for x in (-15.2, -11.5, -7.8):
            paint(mb, rounded_band(mb, x - 0.25, x + 0.25, *sect(TANK), grow=0.14), C["offwhite"],
                  mask(0.3, 0, 1))
        paint(mb, rounded_band(mb, 0.25, 0.75, *sect(POD), grow=0.1), C["red"], mask(0.3))
        for x0, x1 in ((2.9, 3.35), (11.05, 11.5)):  # Room A end rings (doorways stay open)
            paint(mb, rounded_band(mb, x0, x1, *sect(ROOM_A), grow=0.12), C["offwhite"], mask(0.3, 0, 1))
        paint(mb, rounded_band(mb, 6.95, 7.35, *sect(ROOM_A), grow=0.08), C["red"], mask(0.3))
        # the torn-open window of room B (dark gap + bent frame bars)
        mb.box((-11.8, -1.56, 2.0), (-7.8, -1.45, 4.55), C["ink"], mask(0.9))
        for x in (-11.2, -10.1, -9.0):
            mb.box((x, -1.85, 2.0), (x + 0.22, -1.5, 4.55), C["steel_lt"], mask(0.8))
        mb.box((-11.8, -1.8, 3.2), (-7.8, -1.6, 3.4), C["steel_lt"], mask(0.8))
        for x in (-6.0, -3.5, -1.0, 1.5):
            mb.cyl(0.45, 0.16, (x, -1.53, 3.0), (90, 0, 0), C["glass"], mask(0.6))
        for x in (-2.0, 0.5, 3.0):
            mb.cyl(0.4, 0.16, (x, -0.03, 8.45), (90, 0, 0), C["glass"], mask(0.6))

    shell(trim)
    for ob in pieces:
        bake(ob)
    for cutter in cutters:
        bpy.data.objects.remove(cutter)
    hb = bmesh.new()
    for ob in pieces:
        me = ob.data
        me.transform(ob.matrix_world)
        hb.from_mesh(me)
        bpy.data.objects.remove(ob)
        bpy.data.meshes.remove(me)
    mlay = hb.loops.layers.float_color["Masks"]
    for f in hb.faces:
        for lo in f.loops:
            p = lo.vert.co
            n = noise.noise(p * 0.35)
            r = max(lo[mlay][0], 0.55 * max(0.0, n + 0.15), 0.6 if p.z < 0.9 else 0.0)
            c = lo[mlay]
            lo[mlay] = (min(1.0, r), c[1], c[2], 1.0)
    hme = bpy.data.meshes.new("hull@wreck_core")
    hb.to_mesh(hme)
    hb.free()
    smooth(hme)
    for m in mats + [M["cap"]]:
        hme.materials.append(m)
    _activate_masks(hme)
    hull = own(bpy.data.objects.new("hull@wreck_core", hme))
    co.objects.link(hull)

    # ---------------------------------------------------------- parts
    def part(name, build, origin=None, coll=co):
        mb = MB()
        build(mb)
        return own(mb.to_object(name, coll, mats, origin))

    def truss(mb):
        mb.box((-34, 1.6, 8.6), (-17.0, 3.6, 9.4), C["steel_lt"], mask(0.4))
        for x in range(-33, -19, 3):
            mb.box((x, 1.5, 7.6), (x + 0.3, 3.7, 10.4), C["offwhite_old"], mask(0.6, 0, 1))
            mb.box((x, 2.4, 7.6), (x + 3.0, 2.8, 7.8), C["steel_lt"], mask(0.6), rot=(0, -18, 0))
        mb.cyl(0.6, 1.6, (-24.5, 2.6, 10.0), (0, 90, 0), C["red_faded"], mask(0.4), seg=12)
    part("part_truss", truss)

    def solar(mb):
        frame = C["offwhite"]
        for i in range(4):
            y0 = -6 + i * 1.9
            mb.box((-29, y0, 9.0), (-21, y0 + 1.75, 9.1), C["darkblue"], mask(0.3, 0, 1))
            mb.box((-29, y0 + 1.75, 9.0), (-21, y0 + 1.9, 9.14), frame, mask(0.4, 0, 1))
        for x in (-29, -25, -21.1):
            mb.box((x, -6, 9.0), (x + 0.12, 1.6, 9.14), frame, mask(0.4, 0, 1))
        mb.box((-25.2, 1.6, 8.9), (-24.8, 2.4, 9.2), C["steel"], mask(0.5))
    sp = part("part_solar_panel", solar, origin=(-25, 2.0, 9.0))
    sp.rotation_euler = E(-14, 6, -8)

    def solar_broken(mb):
        for i in range(2):
            y0 = -5.5 + i * 2.2
            mb.box((-20.5, y0, 8.4), (-17.5, y0 + 2.0, 8.5), C["darkblue"], mask(0.5, 0, 1))
        mb.box((-20.5, -1.3, 8.35), (-17.5, -1.15, 8.55), C["offwhite_old"], mask(0.6, 0, 1))
    sp2 = part("part_solar_broken", solar_broken, origin=(-19, -1.2, 8.5))
    sp2.rotation_euler = E(-35, 18, 12)

    part("part_antenna_a", lambda mb: (
        mb.cyl(0.07, 4.0, (3.0, 1.2, 12.0), (0, 0, 0), C["steel_lt"], mask(0.4), seg=6),
        mb.cyl(0.25, 0.08, (3.0, 1.2, 13.0), (0, 0, 0), C["offwhite"], mask(0.4), seg=8),
        mb.box((2.92, 1.12, 13.9), (3.08, 1.28, 14.02), C["pink"], mask(0, 1.0), mat=EMI),
    ), origin=(3.0, 1.2, 10.0))
    part("part_antenna_b", lambda mb: mb.cyl(0.05, 2.6, (2.0, 3.8, 11.3), (8, -6, 0), C["steel_lt"], mask(0.4), seg=6),
         origin=(2.0, 3.8, 10.0))
    part("part_dish", lambda mb: (
        mb.cyl(1.3, 0.35, (-2.0, 3.5, 11.1), (35, 0, 20), C["offwhite"], mask(0.5, 0, 1), r2=0.3, seg=16),
        mb.cyl(0.1, 1.0, (-2.0, 3.5, 10.4), (0, 0, 0), C["steel_lt"], mask(0.4), seg=6),
    ), origin=(-2.0, 3.5, 10.0))

    def torn(mb):
        mb.box((-11.8, -1.75, 4.55), (-8.6, -1.6, 5.5), C["offwhite_old"], mask(0.8, 0, 1))
        mb.box((-11.8, -1.8, 4.75), (-8.6, -1.7, 4.95), C["red_faded"], mask(0.8))
    tp = part("part_torn_plate", torn, origin=(-10.2, -1.6, 4.6))
    tp.rotation_euler = E(-38, 0, -6)

    # decorative docking rings on the upper hull (future modules; not game slots)
    part("part_dock_ring_top", lambda mb: (
        mb.ring(1.3, 0.9, 0.5, (0.5, 2.5, 10.2), (0, 0, 0), C["offwhite"], mask(0.4, 0, 1), seg=20),
        mb.cyl(0.9, 0.08, (0.5, 2.5, 10.05), (0, 0, 0), C["ink"], mask(0.3), seg=20),
        mb.ring(1.42, 1.3, 0.14, (0.5, 2.5, 10.3), (0, 0, 0), C["neon"], mask(0.3, 0, 1), seg=20),
    ))
    part("part_dock_ring_side", lambda mb: (
        mb.ring(1.3, 0.9, 0.5, (11.75, 2.25, 3.6), (0, 90, 0), C["offwhite"], mask(0.4, 0, 1), seg=20),
        mb.cyl(0.9, 0.08, (11.55, 2.25, 3.6), (0, 90, 0), C["ink"], mask(0.3), seg=20),
        mb.ring(1.42, 1.3, 0.14, (11.85, 2.25, 3.6), (0, 90, 0), C["neon"], mask(0.3, 0, 1), seg=20),
    ))

    lx, ly = 6.2, -5.25  # work lamp, against the front wall

    def lamp(mb):
        mb.cyl(0.3, 0.06, (lx, ly, 0.31), (0, 0, 0), C["steel"], mask(0.6), seg=10)
        mb.cyl(0.04, 1.6, (lx, ly, 1.1), (0, 0, 0), C["steel_lt"], mask(0.4), seg=6)
        mb.cyl(0.22, 0.3, (lx, ly + 0.05, 1.95), (-60, 0, 15), C["neon"], mask(0.3), r2=0.12, seg=10)
        mb.cyl(0.17, 0.05, (lx + 0.04, ly + 0.2, 1.85), (-60, 0, 15), C["amber"], mask(0, 1.0), mat=EMI, seg=10)
        mb.box((lx - 0.1, ly - 0.1, 0.3), (lx + 0.1, ly + 0.1, 0.36), C["ink"], mask(0.2))
    part("part_worklamp", lamp, origin=(lx, ly, FLOOR_Z))

    # ---------------------------------------------------------- empties: slots, light, nav
    slots = [
        empty("slot_A@wreck_core", (11.5 + SLOT_OUT, DOOR_Y, FLOOR_Z), co, "SINGLE_ARROW", 0.8, (0, 0, 90)),
        empty("slot_B@wreck_core", (2.9 - SLOT_OUT, DOOR_Y, FLOOR_Z), co, "SINGLE_ARROW", 0.8, (0, 0, -90)),
        empty("slot_V@wreck_core", (2.9 - SLOT_OUT, -2.7, FLOOR_Z), co, "SINGLE_ARROW", 0.8, (0, 0, -90)),
        empty("slot_C@wreck_core", (10.2, -6.0 - SLOT_OUT, FLOOR_Z), co, "SINGLE_ARROW", 0.8, (0, 0, 0)),
    ]
    for s in slots:
        s["note"] = "local -Y (Blender) = +Z (Godot) points out of the module"
    light = empty("light_worklamp", (lx, ly + 0.4, FLOOR_Z + 2.1), co, "SPHERE", 0.2)
    mb = MB()
    mb.box((3.2, -5.7, FLOOR_Z - 0.04), (11.2, -1.7, FLOOR_Z - 0.02), C["cream"])
    nav = mb.to_object("roomA_floor-nav", co, mats)
    nav.hide_render = True
    nav.display_type = "WIRE"
    for ob in slots + [light, nav]:
        own(ob)

    # ---------------------------------------------------------- Room A interior (props)
    # Game furniture owns cells C (4.2, -2.7), S (10.2, -2.7) and the window W (front
    # wall, x 8.2); props hug the walls and stay out of the doorways.
    def prop(name, build):
        mb = MB()
        build(mb)
        return own(mb.to_object(name, co, mats))

    def table(mb):  # crate used as a table + what's on it, against the back wall
        tx, ty = 7.0, -2.2
        mb.box((tx - 0.5, ty - 0.45, FLOOR_Z), (tx + 0.5, ty + 0.45, 1.1), C["crate"], mask(0.4), mat=INT)
        for sx in (-0.25, 0.25):
            mb.box((tx + sx - 0.04, ty - 0.47, FLOOR_Z), (tx + sx + 0.04, ty + 0.47, 1.12), C["offwhite"], mask(0.3), mat=INT)
        mb.cyl(0.06, 0.12, (tx - 0.2, ty - 0.1, 1.18), (0, 0, 0), C["red"], mask(0.2), mat=INT, seg=8)
        mb.cyl(0.05, 0.1, (tx + 0.25, ty + 0.15, 1.17), (0, 0, 0), C["steel_lt"], mask(0.3), mat=INT, seg=8)
        mb.box((tx - 0.05, ty - 0.3, 1.12), (tx + 0.4, ty, 1.13), C["offwhite"], mask(0.1), mat=INT, rot=(0, 0, 14))
        mb.box((tx - 0.45, ty + 0.05, 1.12), (tx - 0.2, ty + 0.3, 1.2), C["darkblue"], mask(0.2), mat=INT)
    prop("prop_crate_table", table)

    def toolbox(mb):
        mb.box((8.3, -5.6, FLOOR_Z), (9.0, -5.25, 0.6), C["red"], mask(0.4), mat=INT, rot=(0, 0, -8))
        mb.box((8.55, -5.45, 0.6), (8.75, -5.4, 0.68), C["ink"], mask(0.2), mat=INT, rot=(0, 0, -8))
        mb.box((7.6, -5.5, FLOOR_Z), (8.0, -5.4, 0.33), C["steel_lt"], mask(0.3), mat=INT, rot=(0, 0, 30))
    prop("prop_toolbox", toolbox)

    def debris(mb):
        mb.box((4.9, -5.6, FLOOR_Z), (5.7, -5.0, 0.42), C["violet"], mask(0.8, 0, 1), mat=INT, rot=(0, 8, 25))
        mb.box((9.6, -3.5, FLOOR_Z), (9.95, -3.2, 0.5), C["steel"], mask(0.7), mat=INT, rot=(0, 0, 40))
        mb.box((5.5, -3.6, FLOOR_Z), (5.8, -3.4, 0.4), C["steel_lt"], mask(0.6), mat=INT, rot=(10, 0, 15))
        mb.cyl(0.08, 1.2, (8.0, -4.0, 0.38), (0, 90, 35), C["steel"], mask(0.5), mat=INT, seg=8)
    prop("prop_debris", debris)

    def wall_kit(mb):  # pipes on the back wall + cable trays + floor seams
        for z, r in ((3.45, 0.11), (3.15, 0.07)):
            mb.cyl(r, 8.0, (7.2, -1.7 - r - 0.02, z), (0, 90, 0), C["steel"], mask(0.5), mat=INT, seg=10)
        mb.cyl(0.09, 3.1, (8.9, -1.82, 1.85), (0, 0, 0), C["darkblue"], mask(0.4), mat=INT, seg=8)
        for x in (4.0, 6.0, 8.0, 10.0):
            mb.box((x - 0.05, -1.95, 3.0), (x + 0.05, -1.7, 3.6), C["steel_lt"], mask(0.6), mat=INT)
        for x in (4.2, 6.2, 8.2, 10.2):
            mb.box((x - 0.02, -5.7, FLOOR_Z - 0.02), (x + 0.02, -1.7, FLOOR_Z - 0.01), C["ink"], mask(0.6), mat=INT)
    prop("prop_roomA_fittings", wall_kit)

    def cables(mb):
        # the extension cable: through doorway A (capsule) along the front wall to the lamp
        mb.tube([(12.2, -5.3, FLOOR_Z + 0.04), (10.9, -5.45, FLOOR_Z + 0.04), (9.6, -5.55, FLOOR_Z + 0.04),
                 (7.4, -5.62, FLOOR_Z + 0.04), (6.5, -5.4, FLOOR_Z + 0.05)], 0.05, C["neon"], mask(0.1), INT, res=4)
        mb.tube([(3.6, -1.8, FLOOR_Z + 0.03), (4.8, -1.9, FLOOR_Z + 0.03), (5.6, -2.1, FLOOR_Z + 0.03),
                 (6.4, -1.85, FLOOR_Z + 0.03)], 0.035, C["ink"], mask(0.3), INT, res=4)
        mb.tube([(9.0, -1.8, FLOOR_Z + 0.03), (9.6, -2.0, FLOOR_Z + 0.03), (11.0, -1.9, FLOOR_Z + 0.03)],
                0.03, C["darkblue"], mask(0.3), INT)
        for x, h in ((5.0, 1.5), (5.3, 1.0), (7.0, 0.8), (9.1, 1.8)):
            mb.tube([(x, -1.85, 3.0), (x + 0.15, -2.05, 3.0 - h), (x + 0.4, -1.9, 3.0)], 0.03,
                    C["ink"] if x != 5.3 else C["pink"], mask(0.2), INT, res=4)
    prop("prop_cables", cables)

    G = gparent
    for loc, spin, kit in (((8.3, -2.15, FLOOR_Z), 5, "gk_crate"), ((8.3, -2.15, 1.12), 20, "gk_crate_blue")):
        own(put(kit, loc, "+Z", spin, coll=co, parent=G, interior=True, lift=0.0))
    for loc, spin in (((6.8, -1.7, 2.1), 4), ((7.25, -1.7, 2.35), -8), ((5.6, -1.7, 2.0), 10), ((9.8, -1.7, 2.2), -5)):
        own(put("gk_note", loc, "-Y", spin, coll=co, parent=G, interior=True, lift=0.0))
    for x, y in ((5.0, -3.7), (8.8, -3.0)):
        own(put("gk_floor_plate", (x, y, FLOOR_Z - 0.02), "+Z", 0, coll=co, parent=G, interior=True, lift=0.0))
    own(put("gk_vent", (8.0, -1.7, 2.6), "-Y", 0, coll=co, parent=G, interior=True))
    own(put("gk_rust_streak", (8.0, -1.7, 2.3), "-Y", 0, coll=co, parent=G))

    # ---------------------------------------------------------- exterior greebles
    def g(kit, loc, face, spin=0.0, scale=(1, 1, 1)):
        return own(put(kit, loc, face, spin, scale, co, G))

    # front face of the hub (y = -1.5): flat between z 1.2 and 5.2
    pipe_run((-12, -1.5, 1.45), (2.9, -1.5, 1.45), "-Y", co, G)
    pipe_run((-12, -1.5, 1.8), (2.9, -1.5, 1.8), "-Y", co, G, kit="gk_pipe_thin", clamps=False)
    pipe_run((-12, -1.5, 5.0), (11.5, -1.5, 5.0), "-Y", co, G, kit="gk_cables", clamps=False)
    for x in (-6.0, -3.5, -1.0, 1.5):
        g("gk_porthole_rim", (x, -1.5, 3.0), "-Y")
        g("gk_rust_streak", (x + 0.15, -1.5, 2.45), "-Y", 0, (1, 0.9 + 0.2 * random.random(), 1))
    for x in (-4.75, 0.25):
        g("gk_vent", (x, -1.5, 4.1), "-Y")
        g("gk_rust_streak", (x - 0.2, -1.5, 3.8), "-Y", 0, (1.3, 1.1, 1))
    g("gk_hazard", (8.5, -1.5, 4.6), "-Y", 0, (1.6, 1, 1))
    g("gk_stencil_07", (3.0, -1.5, 4.55), "-Y", 0, (1.4, 1.4, 1))
    g("gk_stencil_B2", (-2.3, -1.5, 2.0), "-Y")
    for x, z, k in ((-7.0, 4.4, "gk_panel_white"), (-1.0, 4.5, "gk_panel_grey"), (6.0, 4.4, "gk_panel_red"),
                    (-11.0, 1.9, "gk_panel_red"), (-7.0, 2.3, "gk_panel_white"), (1.9, 2.0, "gk_panel_grey")):
        g(k, (x, -1.5, z), "-Y", random.uniform(-3, 3), (1.2, 0.9, 1))
    for x, z in ((-10.5, 1.8), (-2.6, 3.9), (-5.2, 2.1), (2.4, 3.8), (10.6, 4.2), (-11.6, 4.8), (-8.3, 4.9), (4.2, 4.9)):
        g("gk_chip", (x, -1.5, z), "-Y", random.uniform(0, 180))
    g("gk_bolts", (-9.8, -1.5, 5.2), "-Y", 0, (4, 1, 1))
    g("gk_bolts", (7.5, -1.5, 4.2), "-Y", 0, (8, 1, 1))
    g("gk_rust_streak", (-11.0, -1.5, 1.95), "-Y", 0, (1.5, 0.6, 1))
    g("gk_rust_streak", (-8.4, -1.5, 1.95), "-Y", 0, (1.2, 0.5, 1))
    g("gk_rust_streak", (5.6, -1.5, 4.9), "-Y", 0, (1, 0.5, 1))
    g("gk_rust_streak", (9.6, -1.5, 4.9), "-Y", 0, (1, 0.45, 1))
    # Room A outer wall (below the cut, clear of doorway C)
    g("gk_hazard", (6.1, -6.0, 0.85), "-Y", 0, (2.9, 1, 1))
    g("gk_stencil_A01", (4.0, -6.0, 0.45), "-Y", 0, (0.7, 0.7, 1))
    g("gk_rust_streak", (8.6, -6.0, 0.72), "-Y", 0, (0.8, 0.3, 1))
    g("gk_rust_streak", (4.9, -6.0, 1.3), "-Y", 0, (0.9, 0.6, 1))
    g("gk_chip", (8.9, -6.0, 1.6), "-Y", 40)
    # top deck of the hub (z = 7, flat between y 0.3 and 4.6); the game adds
    # part_reactor (10.4, 4.4) and part_radiator (9.6, 0.8) there: keep that corner clear
    for (x, y), spn in (((7.0, 3.6), 0), ((7.0, 1.6), 0)):
        g("gk_tank", (x, y, 7.0), "+Z", spn)
    for x, y in ((8.6, 0.6), (-8.0, 0.6)):
        g("gk_vent", (x, y, 7.0), "+Z")
    pipe_run((-12, 0.45, 7.0), (9.0, 0.45, 7.0), "+Z", co, G)
    pipe_run((5.6, 0.6, 7.0), (5.6, 4.4, 7.0), "+Z", co, G, kit="gk_pipe_thin", clamps=False)
    for x, y in ((-3.0, 0.7), (-10.5, 0.8)):
        g("gk_box", (x, y, 7.0), "+Z", random.uniform(0, 90))
    for x, y, k in ((-7.0, 1.0, "gk_panel_grey"), (8.6, 2.6, "gk_panel_red")):
        g(k, (x, y, 7.0), "+Z", random.uniform(-10, 10), (1.2, 1.0, 1))
    g("gk_stencil_14", (7.0, 0.8, 7.0), "+Z", 90, (1.2, 1.2, 1))
    # upper pod (room C): flat top z 10 between x -2.8..3.8, y 1..4
    g("gk_hazard", (0.5, 3.9, 10.0), "+Z", 0, (1.2, 1, 1))
    g("gk_hazard", (0.5, 1.1, 10.0), "+Z", 0, (1.2, 1, 1))
    g("gk_stencil_DOCK", (-1.6, 1.5, 10.0), "+Z", 0, (0.6, 0.6, 1))
    g("gk_stencil_C3", (2.6, 0.0, 8.45), "-Y", 0, (0.7, 0.7, 1))
    for x in (-2.0, 0.5, 3.0):
        g("gk_porthole_rim", (x, 0.0, 8.45), "-Y", 0, (0.85, 0.85, 1))
        g("gk_rust_streak", (x + 0.1, 0.0, 8.0), "-Y", 0, (0.8, 0.4, 1))
    # +X face of the hub (x = 11.5)
    g("gk_hazard", (11.5, 2.25, 5.35), "+X", 0, (1.4, 1, 1))
    g("gk_hazard", (11.5, 2.25, 1.75), "+X", 0, (1.4, 1, 1))
    g("gk_stencil_C", (11.5, 4.6, 4.2), "+X", 0, (1.2, 1.2, 1))
    g("gk_vent", (11.5, -0.1, 5.0), "+X")
    g("gk_rust_streak", (11.5, -0.3, 4.7), "+X", 0, (1.2, 1.4, 1))
    g("gk_panel_red", (11.5, 4.4, 1.8), "+X", 5, (1.0, 1.0, 1))
    pipe_run((11.5, 0.6, 1.3), (11.5, 0.6, 5.6), "+X", co, G, kit="gk_pipe_thin", clamps=False)
    g("gk_chip", (11.5, 3.6, 5.4), "+X", 30)
    g("gk_chip", (11.5, 1.0, 1.4), "+X", 120)
    # long tank
    pipe_run((-15.5, 2.6, 11.6), (-7.5, 2.6, 11.6), "+Z", co, G, kit="gk_cables", clamps=False)
    g("gk_box", (-13.4, 1.9, 11.55), "+Z", 20)
    g("gk_box", (-9.6, 3.3, 11.55), "+Z", 70)
    g("gk_rust_streak", (-13.0, 0.2, 9.4), "-Y", 0, (1.2, 1.0, 1))
    g("gk_stencil_SR7", (-11.5, 0.2, 9.0), "-Y", 0, (1.0, 1.0, 1))

    for ob in owned:
        if ob.parent is None:
            parent_keep(ob, root)
    return root, hull, owned


def build_capsule(cols, mats):
    """9.8 m pod (r 2.5), axis 1 m above the game floor; 3 x 2 walkable cells inside
    (furniture bodies cut the navmesh, so the floor must be 2 cells wide)."""
    co = cols["CAPSULE"]
    root = empty("capsule", CAP_ORIGIN, co, "ARROWS", 1.2)
    gparent = empty("greebles_capsule", CAP_ORIGIN, co, "PLAIN_AXES", 0.3)
    parent_keep(gparent, root)
    owned = []

    def own(ob):
        owned.append(ob)
        return ob

    cx, y, ax = CAP_ORIGIN.x, CAP_ORIGIN.y, FLOOR_Z + 1.0
    R, half = 2.5, 2.4
    dy = DOOR_Y  # the doorway row (row 1) is 1 m off the capsule axis
    # ---------------------------------------------------------- hull: capsule shape, two-tone
    mb = MB()
    v = bmesh.ops.create_uvsphere(mb.bm, u_segments=32, v_segments=16, radius=R)["verts"]
    bmesh.ops.rotate(mb.bm, verts=v, matrix=E(0, 90, 0).to_matrix())
    for vv in v:  # stretch the sphere into a capsule: hemispheres + 4 m cylinder
        if vv.co.x > 1e-4:
            vv.co.x += half
        elif vv.co.x < -1e-4:
            vv.co.x -= half
    faces = mb._tag(v, Matrix.Translation((cx, y, ax)), C["red"], mask(0.1), HULL)
    for f in faces:
        if f.calc_center_median().z > ax + 1.2:
            for lo in f.loops:
                lo[mb.base] = C["offwhite"]
                lo[mb.mask] = mask(0.1, 0, 1)
    hull = own(mb.to_object("hull@capsule", co, mats, origin=(cx, y, ax)))
    solidify_in(hull, 0.2)
    cut = MB()
    cut.box((cx - 5.2, dy - 0.8, FLOOR_Z), (cx - 3.6, dy + 0.8, FLOOR_Z + 2.4), C["steel_lt"], mask(0.5))  # dock door
    cut.box((cx - 0.3, y - 3.3, FLOOR_Z + 0.6), (cx + 1.1, y - 1.5, FLOOR_Z + 2.3), C["offwhite"], mask(0.5))  # side hatch
    cutter = cut.to_object("_hatch_cutter", co, mats)
    md = hull.modifiers.new("HATCH", "BOOLEAN")
    md.operation = "DIFFERENCE"
    md.solver = "EXACT"
    md.object = cutter
    bake(hull)
    bpy.data.objects.remove(cutter)

    def part(name, build, origin=None):
        m = MB()
        build(m)
        return own(m.to_object(name, co, mats, origin))

    tz = FLOOR_Z + 1.2  # docking tube axis (door centre)
    part("part_nose_collar", lambda m: (  # docking tube to Room A (ends 0.22 m off the wreck)
        m.ring(1.8, 1.5, 0.9, (12.17, dy, tz), (0, 90, 0), C["offwhite"], mask(0.3), seg=24),
        m.ring(2.0, 1.5, 0.14, (12.55, dy, tz), (0, 90, 0), C["steel"], mask(0.5), seg=24),
        m.ring(2.0, 1.5, 0.14, (11.8, dy, tz), (0, 90, 0), C["neon"], mask(0.3, 0, 1), seg=24),
    ))

    def rcs(m):
        m.ring(2.72, 2.42, 0.4, (cx + 1.2, y, ax), (0, 90, 0), C["offwhite"], mask(0.2), seg=32)
        for a in (45, 135, 225, 315):
            r = math.radians(a)
            p = Vector((cx + 1.2, y + 2.85 * math.cos(r), ax + 2.85 * math.sin(r)))
            m.box(p - Vector((0.2,) * 3), p + Vector((0.2,) * 3), C["steel_lt"], mask(0.4))
            for d in (-1, 1):
                m.cyl(0.06, 0.18, (p.x + d * 0.28, p.y, p.z), (0, 90, 0), C["ink"], mask(0.3), seg=6)
    part("part_rcs_ring", rcs)

    def canopy(m):
        c = Vector((cx - 3.2, y, ax + 1.75))
        m.sphere(0.9, c, (1.1, 0.95, 0.6), C["glass"], mask(0.0), seg=16, rings=8)
        m.sphere(0.65, c + Vector((-0.05, -0.25, 0.08)), (0.9, 0.6, 0.4), C["cyan"], mask(0, 0.45), mat=EMI, seg=12, rings=6)
        for dx in (-0.45, 0.2):
            m.box((c.x + dx - 0.05, y - 0.85, c.z - 0.1), (c.x + dx + 0.05, y + 0.85, c.z + 0.55), C["offwhite"], mask(0.3))
    part("part_canopy", canopy)
    # the engine bell is the "capsule_thruster" upgrade part (hidden until bought in game)
    tail = cx + half + R  # 21.7
    part("part_thruster", lambda m: (
        m.cyl(0.55, 1.1, (tail + 0.95, y, ax), (0, 90, 0), C["steel"], mask(0.6), r2=0.95, seg=16),
        m.cyl(0.3, 0.4, (tail + 0.25, y, ax), (0, 90, 0), C["steel_lt"], mask(0.5), seg=10),
    ))

    def door(m):
        m.box((-0.7, -0.07, -0.85), (0.7, 0.07, 0.85), C["offwhite"], mask(0.3))
        m.box((-0.45, -0.1, -0.1), (0.45, -0.07, 0.1), C["red"], mask(0.2))
        m.box((-0.7, -0.09, 0.72), (0.7, -0.07, 0.85), C["neon"], mask(0.2))
    d = part("part_hatch_door", door, origin=Vector())
    d.location = (cx + 1.1 + 0.45, y - 2.5 - 0.55, FLOOR_Z + 1.45)
    d.rotation_euler = E(0, 0, -50)
    part("part_antenna", lambda m: (
        m.cyl(0.04, 1.6, (cx + 2.6, y + 0.6, ax + 2.9), (0, -12, 0), C["steel_lt"], mask(0.3), seg=6),
        m.box((cx + 2.75 - 0.06, y + 0.54, ax + 3.66), (cx + 2.75 + 0.06, y + 0.66, ax + 3.78), C["pink"], mask(0, 1), mat=EMI),
    ))

    # ---------------------------------------------------------- cabin props (walls only:
    # the bed, the kitchen and the player spawn are game furniture on the 3 floor cells)
    def cabin(m):
        wy = y + 1.75  # back wall (+Y) at mid height
        m.box((cx - 0.8, wy, FLOOR_Z + 1.2), (cx + 0.8, wy + 0.3, FLOOR_Z + 2.2), C["steel"], mask(0.2), mat=INT)
        m.box((cx - 0.7, wy - 0.02, FLOOR_Z + 1.65), (cx - 0.05, wy, FLOOR_Z + 2.1), C["cyan"], mask(0, 1), mat=EMI)
        m.box((cx + 0.05, wy - 0.02, FLOOR_Z + 1.65), (cx + 0.7, wy, FLOOR_Z + 2.1), C["cyan"], mask(0, 1), mat=EMI)
        m.box((cx - 0.2, wy - 0.02, FLOOR_Z + 1.3), (cx + 0.2, wy, FLOOR_Z + 1.45), C["pink"], mask(0, 1), mat=EMI)
        m.box((cx - 2.0, y - 0.25, ax + 2.16), (cx + 2.0, y + 0.25, ax + 2.23), C["amber"], mask(0, 1), mat=EMI)
        m.box((cx + 1.3, wy - 0.1, FLOOR_Z + 2.0), (cx + 2.6, wy + 0.3, FLOOR_Z + 2.06), C["steel_lt"], mask(0.3), mat=INT)
        for i, dx in enumerate((1.45, 1.75, 2.05, 2.35)):
            h = 0.22 if i % 2 == 0 else 0.16
            m.box((cx + dx - 0.12, wy, FLOOR_Z + 2.06), (cx + dx + 0.12, wy + 0.22, FLOOR_Z + 2.06 + h), C["crate"], mask(0.2), mat=INT)
        m.box((cx - 2.2, wy, FLOOR_Z + 1.7), (cx - 1.7, wy + 0.2, FLOOR_Z + 2.05), C["offwhite"], mask(0.1), mat=INT)
        m.box((cx - 2.0, wy - 0.01, FLOOR_Z + 1.8), (cx - 1.9, wy, FLOOR_Z + 1.95), C["red"], mask(0), mat=INT)
        m.box((cx - 1.98, wy - 0.01, FLOOR_Z + 1.84), (cx - 1.92, wy, FLOOR_Z + 1.91), C["offwhite"], mask(0), mat=INT)
    pc = MB()
    cabin(pc)
    own(pc.to_object("prop_capsule_cabin", co, mats))

    G = gparent

    def g(kit, loc, face, spin=0.0, scale=(1, 1, 1)):
        return own(put(kit, loc, face, spin, scale, co, G))

    g("gk_stencil_SR7", (cx - 2.0, y - 2.48, ax + 0.2), "-Y", 0, (0.9, 0.9, 1))
    g("gk_hazard", (cx + 0.4, y - 2.2, ax + 1.15), "-Y", 0, (0.8, 1, 1))
    g("gk_bolts", (cx - 0.4, y - 2.5, ax - 0.25), "-Y", 0, (1.5, 1, 1))
    lights = MB()  # running lights either side of the open hatch
    for dx in (-0.5, 1.3):
        lights.box((cx + dx - 0.05, y - 2.58, FLOOR_Z + 1.0), (cx + dx + 0.05, y - 2.38, FLOOR_Z + 1.9), C["amber"], mask(0, 1), mat=EMI)
    own(lights.to_object("prop_hatch_lights", co, mats))

    slot = empty("slot_A@capsule", (11.5 + SLOT_OUT, dy, FLOOR_Z), co, "SINGLE_ARROW", 0.8, (0, 0, -90))
    slot["note"] = "local -Y (Blender) = +Z (Godot) points out of the module"
    light = empty("light_cabin", (cx, y, FLOOR_Z + 2.1), co, "SPHERE", 0.2)
    nb = MB()
    nb.box((cx - 3.0, y - 2.0, FLOOR_Z - 0.04), (cx + 3.0, y + 2.0, FLOOR_Z - 0.02), C["cream"])
    nav = nb.to_object("capsule_floor-nav", co, mats)
    nav.hide_render = True
    nav.display_type = "WIRE"
    for ob in (slot, light, nav):
        own(ob)
    for ob in owned:
        if ob.parent is None:
            parent_keep(ob, root)
    return root, hull, owned


def build_debris(cols, mats):
    co = cols["BACKGROUND"]
    mb = MB()  # a torn hull plate with ribs (it came off the tear)
    mb.box((-1.6, -0.08, -1.0), (1.6, 0.08, 1.0), C["offwhite_old"], mask(0.7, 0, 1))
    mb.box((-1.6, 0.08, 0.2), (1.6, 0.12, 0.5), C["red_faded"], mask(0.6))
    for x in (-1.1, 0.0, 1.1):
        mb.box((x - 0.1, -0.35, -1.0), (x + 0.1, -0.08, 1.0), C["steel"], mask(0.8))
    a = mb.to_object("debris_plate", co, mats, origin=Vector())
    a.location = (16.0, 4.0, 14.5)
    a.rotation_euler = E(40, 25, 60)
    mb = MB()
    mb.box((-0.5, -0.4, -0.3), (0.5, 0.4, 0.3), C["steel"], mask(0.6))
    mb.cyl(0.1, 1.4, (0.6, 0, 0.1), (0, 70, 20), C["steel_lt"], mask(0.5), seg=8)
    b = mb.to_object("debris_chunk", co, mats, origin=Vector())
    b.location = (18.5, 2.5, 13.2)
    b.rotation_euler = E(15, 50, 10)
    mb = MB()
    mb.tube([(0, 0, 0), (0.8, 0.3, 0.4), (1.3, -0.2, 0.9)], 0.06, C["ink"], mask(0.3))
    c = mb.to_object("debris_cable", co, mats, origin=Vector())
    c.location = (17.2, 3.0, 12.4)
    return [a, b, c]


# ================================================================ cut, lights, camera, background
def make_cut(cols, hull):
    co = cols["CUT_PREVIEW"]
    mb = MB()
    # bottom = game floor + CutawayController.CUT_HEIGHT (1.15 m); the game uses the
    # exported "cut_box" for its X/Z extent and top
    mb.box((3.2, -8.0, FLOOR_Z + 1.15), (11.2, -1.8, 6.0), C["cream"])
    cut = mb.to_object("CUT_BOX", co, [M["cap"]])
    cut.display_type = "WIRE"
    cut.hide_render = True
    md = hull.modifiers.new("CUT_PREVIEW", "BOOLEAN")
    md.operation = "DIFFERENCE"
    md.solver = "EXACT"
    md.use_self = True
    md.object = cut
    md.material_mode = "TRANSFER"
    return cut


def make_lights(cols, fwd, right):
    co = cols["LIGHTS"]
    ld = bpy.data.lights.new("light_key", "SUN")
    ld.color = (0.72, 0.80, 1.0)
    ld.energy = 0.75
    ld.angle = math.radians(1.0)
    key = bpy.data.objects.new("light_key", ld)
    from_vec = (-right * 1.0 + Vector((0, 0, 1.4)) - fwd * 0.4).normalized()
    key.rotation_euler = from_vec.to_track_quat("Z", "Y").to_euler()
    co.objects.link(key)
    lp = bpy.data.lights.new("light_worklamp", "POINT")
    lp.color = C["amber"][:3]
    lp.energy = 1400
    lp.shadow_soft_size = 0.08
    lp.use_shadow = False  # spills through the cut edges onto the surrounding hull
    lp.use_custom_distance = True
    lp.cutoff_distance = 11.0
    lamp = bpy.data.objects.new("light_worklamp_point", lp)
    lamp.location = (6.3, -4.85, 1.85)
    co.objects.link(lamp)


def make_world():
    w = bpy.data.worlds.get("World") or bpy.data.worlds.new("World")
    bpy.context.scene.world = w
    w.use_nodes = True
    nt = w.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputWorld")
    bg = nt.nodes.new("ShaderNodeBackground")
    bg.inputs["Color"].default_value = (0.035, 0.022, 0.07, 1)
    lp = nt.nodes.new("ShaderNodeLightPath")
    blk = nt.nodes.new("ShaderNodeBackground")
    blk.inputs["Color"].default_value = (0, 0, 0, 1)
    mix = nt.nodes.new("ShaderNodeMixShader")
    nt.links.new(lp.outputs["Is Camera Ray"], mix.inputs[0])
    nt.links.new(bg.outputs[0], mix.inputs[1])
    nt.links.new(blk.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], out.inputs["Surface"])


CAM_ROT = (62.0, 0.0, 25.0)
CAM_TARGET = Vector((5.72, -7.96, 6.26))
CAM_ORTHO = 50.0
ROOM_A_TARGET = Vector((8.6, -4.4, 1.6))
ROOM_A_ORTHO = 15.0


def cam_vectors(cam):
    r = cam.rotation_euler.to_matrix()
    return r @ Vector((0, 0, -1)), r @ Vector((1, 0, 0))


def frame_camera(cam, target, ortho):
    fwd, _ = cam_vectors(cam)
    cam.data.ortho_scale = ortho
    cam.location = target - fwd * 150
    bg = bpy.data.objects.get("bg_starfield")
    if bg:
        bg.scale = (ortho * 0.6, ortho * 0.6 * 9 / 16, 1)
    pl = bpy.data.objects.get("bg_planet")
    if pl:
        k = ortho / CAM_ORTHO
        pl.location = (-ortho * 0.40, -ortho * 0.33, -300)
        pl.scale = (6 * k, 6 * k, 6 * k)


def make_camera(cols):
    cd = bpy.data.cameras.new("Camera")
    cd.type = "ORTHO"
    cd.clip_start = 0.1
    cd.clip_end = 1000
    cam = bpy.data.objects.new("Camera", cd)
    cam.rotation_euler = E(*CAM_ROT)
    cols["CAMERA"].objects.link(cam)
    bpy.context.scene.camera = cam
    frame_camera(cam, CAM_TARGET, CAM_ORTHO)
    return cam


def make_background(cols, cam):
    co = cols["BACKGROUND"]
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
    gt = n.new("ShaderNodeMath")
    gt.operation = "GREATER_THAN"
    gt.inputs[1].default_value = 0.93
    lt = n.new("ShaderNodeMath")
    lt.operation = "LESS_THAN"
    lt.inputs[1].default_value = 0.07
    mul = n.new("ShaderNodeMath")
    mul.operation = "MULTIPLY"
    em = n.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (0.85, 0.85, 1.0, 1)
    l.new(tc.outputs["UV"], vor.inputs["Vector"])
    l.new(vor.outputs["Color"], sep.inputs[0])
    l.new(sep.outputs[0], gt.inputs[0])
    l.new(vor.outputs["Distance"], lt.inputs[0])
    l.new(gt.outputs[0], mul.inputs[0])
    l.new(lt.outputs[0], mul.inputs[1])
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
    sf.visible_shadow = False

    pm = bpy.data.materials.new("M_planet")
    pm.use_nodes = True
    nt = pm.node_tree
    nt.nodes.clear()
    n, l = nt.nodes, nt.links
    out = n.new("ShaderNodeOutputMaterial")
    geo = n.new("ShaderNodeNewGeometry")
    dot = n.new("ShaderNodeVectorMath")
    dot.operation = "DOT_PRODUCT"
    dot.inputs[1].default_value = (cam.rotation_euler.to_matrix() @ Vector((0.9, 0.55, -0.6))).normalized()
    ramp = n.new("ShaderNodeValToRGB")
    ramp.color_ramp.interpolation = "CONSTANT"
    e = ramp.color_ramp.elements
    e[0].position, e[0].color = 0.0, (0.004, 0.004, 0.012, 1)
    e[1].position, e[1].color = 0.55, hexcol("#9AA6E8")
    e.new(0.3).color = hexcol("#3A3F86")
    em = n.new("ShaderNodeEmission")
    l.new(geo.outputs["Normal"], dot.inputs[0])
    l.new(dot.outputs["Value"], ramp.inputs[0])
    l.new(ramp.outputs[0], em.inputs["Color"])
    l.new(em.outputs[0], out.inputs["Surface"])
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=64, v_segments=32, radius=1.0)
    me = bpy.data.meshes.new("bg_planet")
    bm.to_mesh(me)
    bm.free()
    me.materials.append(pm)
    me.shade_smooth()
    planet = bpy.data.objects.new("bg_planet", me)
    co.objects.link(planet)
    planet.parent = cam
    planet.visible_shadow = False
    frame_camera(cam, CAM_TARGET, CAM_ORTHO)


def setup_render():
    s = bpy.context.scene
    s.render.engine = "BLENDER_EEVEE"
    s.render.resolution_x, s.render.resolution_y = 1920, 1080
    s.render.resolution_percentage = 100
    s.eevee.taa_render_samples = 32
    s.eevee.use_shadows = True
    s.render.use_motion_blur = False
    try:
        s.view_settings.view_transform = "Standard"
    except TypeError as e:
        print("view transform:", e)
    s.view_settings.look = "None"
    tree = bpy.data.node_groups.new("BloomComp", "CompositorNodeTree")
    tree.interface.new_socket("Image", in_out="OUTPUT", socket_type="NodeSocketColor")
    rl = tree.nodes.new("CompositorNodeRLayers")
    gl = tree.nodes.new("CompositorNodeGlare")
    go = tree.nodes.new("NodeGroupOutput")
    for key, val in (("Type", "Bloom"), ("Quality", "High"), ("Threshold", 0.85),
                     ("Strength", 0.55), ("Size", 0.65)):
        sock = next((i for i in gl.inputs if i.name == key), None)
        if sock is not None:
            sock.default_value = val
    tree.links.new(rl.outputs["Image"], gl.inputs["Image"])
    tree.links.new(gl.outputs["Image"], go.inputs[0])
    s.compositing_node_group = tree
    s.render.use_compositing = True


# ================================================================ explode dirs
def set_explode_dirs(owned, centre):
    for ob in owned:
        if ob.name.startswith("part_"):
            d = (ob.matrix_world.translation - centre)
            d = d.normalized() if d.length > 1e-3 else Vector((0, 0, 1))
            ob["explode_dir"] = [round(d.x, 3), round(d.z, 3), round(-d.y, 3)]  # Godot axes


# ================================================================ palette atlas
PALETTE_GRID = 8      # swatches per side
PALETTE_SWATCH = 16   # pixels per swatch


def _srgb(c):
    return c * 12.92 if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055


def bake_palette(path):
    """Flat "Base" colours -> swatches of one small texture; every face corner gets
    the UV of its swatch (TEXCOORD_0), so the game shows the same colours with a
    single textured material per module. UVs are constant per face, so the
    texture is always sampled at mip 0 and swatches never bleed."""
    meshes = {}
    for cname in ("WRECK_CORE", "CAPSULE", "GREEBLE_KIT", "BACKGROUND"):
        for ob in bpy.data.collections[cname].all_objects:
            if ob.type == "MESH" and "Base" in ob.data.color_attributes:
                meshes[ob.data.name] = ob.data

    def key(c):
        return tuple(round(v, 4) for v in c[:3])

    index = {}
    for me in meshes.values():
        for d in me.color_attributes["Base"].data:
            index.setdefault(key(d.color), len(index))
    g, sw = PALETTE_GRID, PALETTE_SWATCH
    assert len(index) <= g * g, "palette overflow: %d colours" % len(index)
    n = g * sw
    px = [0.0] * (n * n * 4)
    for col, i in index.items():
        gx, gy = i % g, i // g
        srgb = [_srgb(v) for v in col] + [1.0]
        for yy in range(gy * sw, (gy + 1) * sw):
            for xx in range(gx * sw, (gx + 1) * sw):
                o = (yy * n + xx) * 4
                px[o:o + 4] = srgb
    img = bpy.data.images.get("station_palette") or bpy.data.images.new("station_palette", n, n, alpha=False)
    img.pixels = px
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    for me in meshes.values():
        uv = me.uv_layers.get("UVMap") or me.uv_layers.new(name="UVMap")
        for li, d in enumerate(me.color_attributes["Base"].data):
            i = index[key(d.color)]
            uv.data[li].uv = ((i % g + 0.5) / g, (i // g + 0.5) / g)
    print("PALETTE", len(index), "colours ->", path)


# ================================================================ main
def build():
    random.seed(7)
    _count.clear()
    KIT.clear()
    reset()
    cols = make_collections()
    mats = make_materials()
    make_world()
    cam = make_camera(cols)
    build_kit(cols)
    wroot, whull, wowned = build_wreck(cols, mats)
    croot, chull, cowned = build_capsule(cols, mats)
    build_debris(cols, mats)
    make_cut(cols, whull)
    fwd, right = cam_vectors(cam)
    make_lights(cols, fwd, right)
    make_background(cols, cam)
    set_explode_dirs(wowned, Vector((-1.0, 2.0, 5.0)))
    set_explode_dirs(cowned, CAP_ORIGIN + Vector((0, 0, 1.2)))
    for c in ("WRECK_CORE", "CAPSULE", "BACKGROUND"):
        for ob in cols[c].objects:
            if ob.type == "MESH" and not ob.hide_render and not ob.name.startswith("bg_"):
                add_outline(ob, 0.06)
    setup_render()
    bake_palette(os.path.join(ROOT, "export", "station_palette.png"))
    bpy.context.view_layer.update()
    return cols
