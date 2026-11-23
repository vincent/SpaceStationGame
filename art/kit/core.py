"""Module kit, core: palette, preview materials, mesh builder (MB), capsule-style
rounded hulls, canopy-style chamfered hulls, greeble kit. Shared by every
art/modules/<id>.py.

Conventions: docs/ART_PIPELINE.md. Blender is Z up; Godot (x, y, z) = Blender (x, z, -y).
"""
import math

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector



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
    # module kit additions. APPEND ONLY: the swatch index is the position in this
    # dict, so reordering would recolour every exported module.
    "gold": "#C9A227", "solar": "#24356E", "leaf": "#4FA65A", "leaf_dk": "#2E6B3E",
    "fabric": "#DCD3BE", "fabric_dk": "#B9AE96", "hot": "#E2552D", "glass_lt": "#3A5A8C",
    "colony": "#9A8FC0", "colony_dk": "#5E5585", "white": "#F4F1EA", "mint": "#5EF2A0",
    # canopy style (glass-roofed modules, docs/MODULE_CATALOG.md)
    "ivory": "#D8D3CC", "navy": "#3E4A63", "trim_gold": "#D99A2B", "canopy": "#8F92B4",
    "deck": "#8B91AD", "soil": "#5B4036", "strut": "#E4DFD8",
    # weathered canopy style (the derelict wreck) and visitors
    "ivory_old": "#ABA393", "navy_faded": "#4F5566", "gold_faded": "#9C7A3A",
    "scorch": "#2A2420", "canopy_dk": "#3F4160", "strut_old": "#B3AC9F",
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


# ================================================================ chamfered hulls (canopy style)
def wall_prism(mb, a, b, profile, t):
    """Closed wall solid: the (s, z) outline `profile` (s = metres along a->b) on
    the vertical plane through plan points a, b, extruded `t` to the left of a->b
    (the inside of a CCW plan outline). One watertight solid even with a stepped /
    broken top. Returns its faces."""
    a, b = Vector((*a, 0.0)), Vector((*b, 0.0))
    d = (b - a).normalized()
    n = Vector((-d.y, d.x, 0.0)) * t
    front = [mb.bm.verts.new(a + d * s + Vector((0, 0, z))) for s, z in profile]
    back = [mb.bm.verts.new(v.co + n) for v in front]
    faces = [mb.bm.faces.new(front), mb.bm.faces.new(list(reversed(back)))]
    k = len(front)
    for i in range(k):
        j = (i + 1) % k
        faces.append(mb.bm.faces.new((front[j], front[i], back[i], back[j])))
    bmesh.ops.recalc_face_normals(mb.bm, faces=faces)
    return faces


def step_profile(length, tops, z0):
    """(s, z) outline for wall_prism: bottom at z0 from 0 to `length`, top stepping
    through `tops` = [(s_end, z), ...] (each top runs from the previous s_end)."""
    pts = [(0.0, z0), (length, z0)]
    for i in reversed(range(len(tops))):
        s, z = tops[i]
        s0 = tops[i - 1][0] if i else 0.0
        pts += [(min(s, length), z), (s0, z)]
    out = []
    for p in pts:  # drop repeated points (equal neighbouring tops)
        if not out or abs(out[-1][0] - p[0]) > 1e-6 or abs(out[-1][1] - p[1]) > 1e-6:
            out.append(p)
    return out


def chamfer_profile(y0, y1, z0, z1, kb, kt, split, grow=0.0):
    """Octagonal section (chamfered rectangle) in YZ: keel chamfers `kb`, roof
    chamfers `kt`, plus a vertex on each vertical side at z `split` (where the
    glass canopy starts). `grow` offsets it outward. Always 10 points."""
    y0, y1, z0, z1 = y0 - grow, y1 + grow, z0 - grow, z1 + grow
    return [(y0 + kb, z0), (y1 - kb, z0), (y1, z0 + kb), (y1, split), (y1, z1 - kt),
            (y1 - kt, z1), (y0 + kt, z1), (y0, z1 - kt), (y0, split), (y0, z0 + kb)]


def nose_point(p, z0, k):
    """Section point `p` (y, z) shrunk for a chamfered end nose: y towards 0 by
    k[0], z towards the keel `z0` by k[1] (the floor line stays level)."""
    return (p[0] * k[0], z0 + (p[1] - z0) * k[1])


def chamfer_hull(mb, x0, x1, y0, y1, z0, z1, kb, kt, split, nose=(1.0, 1.0),
                 squeeze=(0.72, 0.85), stations=()):
    """Faceted tube: `chamfer_profile` lofted along X, full section from x0 to x1
    (seams at `stations`), chamfered noses `nose` m beyond each end, scaled by
    `squeeze` (y, z). Centred on y = 0. Watertight. Returns its faces."""
    prof = chamfer_profile(y0, y1, z0, z1, kb, kt, split)
    small = [nose_point(p, z0, squeeze) for p in prof]
    xs = [(x0 - nose[0], small)] if nose[0] else []
    xs += [(x, prof) for x in sorted({x0, x1, *[x for x in stations if x0 < x < x1]})]
    if nose[1]:
        xs.append((x1 + nose[1], small))
    loops = [[mb.bm.verts.new((x, py, pz)) for py, pz in pr] for x, pr in xs]
    return _loft(mb, loops)


def offset_polygon(pts, d):
    """Mitred offset of a counter-clockwise plan polygon [(x, y)]: d > 0 moves the
    edges inward by d, d < 0 outward. Works on concave outlines (stars) too."""
    n = len(pts)
    out = []
    for i in range(n):
        p0, p1, p2 = Vector(pts[i - 1]), Vector(pts[i]), Vector(pts[(i + 1) % n])
        e0, e1 = (p1 - p0).normalized(), (p2 - p1).normalized()
        n0, n1 = Vector((-e0.y, e0.x)), Vector((-e1.y, e1.x))   # inward for CCW
        b = n0 + n1
        b = b.normalized() if b.length > 1e-6 else n0
        out.append(tuple(p1 + b * (d / max(0.25, b.dot(n0)))))
    return out


def regular_polygon(n, apothem, phase=0.0):
    """CCW n-gon with flats at distance `apothem`; phase 0 puts a flat facing +X."""
    r = apothem / math.cos(math.pi / n)
    return [(r * math.cos(phase + math.pi / n + 2 * math.pi * i / n),
             r * math.sin(phase + math.pi / n + 2 * math.pi * i / n)) for i in range(n)]


def polygon_hull(mb, pts, steps):
    """Vertical prism over the plan polygon `pts` with a stepped section: `steps` =
    [(inset, z), ...] bottom to top (keel chamfer, walls, roof chamfer or dome rings).
    Watertight. Returns its faces."""
    loops = [[mb.bm.verts.new((x, y, z)) for x, y in offset_polygon(pts, inset)]
             for inset, z in steps]
    return _loft(mb, loops)


def polygon_band(mb, pts, lo, hi, grow=0.06, inset=0.05):
    """Closed ring band around a polygon hull, from `inset` inside to `grow` outside."""
    po, pi = offset_polygon(pts, -grow), offset_polygon(pts, inset)
    rings = [[mb.bm.verts.new((x, y, z)) for x, y in pr]
             for pr, z in ((po, lo), (po, hi), (pi, hi), (pi, lo))]
    faces = []
    n = len(pts)
    for k in range(4):
        a, b = rings[k], rings[(k + 1) % 4]
        for i in range(n):
            j = (i + 1) % n
            faces.append(mb.bm.faces.new((a[i], a[j], b[j], b[i])))
    bmesh.ops.recalc_face_normals(mb.bm, faces=faces)
    return faces


def prism_ring(mb, centre, axis, r_out, r_in, depth, color, msk=NOMASK, mat=HULL, n=8):
    """Closed n-gon annulus around `axis` (flat at the bottom for n = 8), from
    `centre` to `centre + axis * depth`."""
    a = Vector(axis).normalized()
    up = Vector((0, 0, 1))
    side = up.cross(a).normalized()
    c0 = Vector(centre)
    rings = []
    for r, d in ((r_out, 0.0), (r_out, depth), (r_in, depth), (r_in, 0.0)):
        rings.append([mb.bm.verts.new(c0 + a * d + (side * math.cos(t) + up * math.sin(t)) * r)
                      for t in (math.pi / n + 2 * math.pi * i / n for i in range(n))])
    faces = []
    for k in range(4):
        p, q = rings[k], rings[(k + 1) % 4]
        for i in range(n):
            j = (i + 1) % n
            faces.append(mb.bm.faces.new((p[i], p[j], q[j], q[i])))
    bmesh.ops.recalc_face_normals(mb.bm, faces=faces)
    paint(mb, faces, color, msk, mat)
    return faces


def beam(mb, a, b, w, color, msk=NOMASK, mat=HULL):
    """Square beam w x w from a to b (ends extended by w / 2 so joints close)."""
    a, b = Vector(a), Vector(b)
    d = b - a
    if d.length < 1e-4:
        return set()
    up = "Z" if abs(d.normalized().z) < 0.99 else "Y"
    rot = d.normalized().to_track_quat("X", up).to_matrix().to_4x4()
    v = bmesh.ops.create_cube(mb.bm, size=1.0)["verts"]
    xf = Matrix.Translation((a + b) / 2) @ rot @ Matrix.Diagonal(Vector((d.length + w, w, w)).to_4d())
    return mb._tag(v, xf, color, msk, mat)


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


def build_kit(co):
    """Each kit item: closed solid(s), local +Z = out of the surface, base at z=0,
    local +Y = up the wall. Instances are linked duplicates of these meshes.
    `co`: a hidden collection holding the kit meshes."""
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


