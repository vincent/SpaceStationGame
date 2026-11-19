"""Module kit: builds ONE station module from its spec (art/modules/<id>.py), checks it
against the game's rules, exports the glTF + a sidecar JSON, renders previews.

Coordinates: the module origin is the centre of its ASCII layout, on the floor
(Blender z = 0 = Godot floor top). Blender (x, y, z) = Godot (x, -z, y): ASCII
columns run along +X, ASCII rows along -Y. One cell = 2 m.

A spec looks like:

    ID = "hub_node"
    LAYOUT = '''##c##
    a.L.b
    ...'''
    def build(m):              # m: Module
        hub = m.piece(lambda mb: m.rounded(mb, ...), thick=0.3)
        m.doorway("A", hub)    # hole + collar + slot_A from the layout letter
        m.light("main", 0, 0)
        ...

Everything named by the conventions in docs/ART_PIPELINE.md ("Object names").
"""
import json
import math
import os
import random

import bmesh
import bpy
from mathutils import Matrix, Vector

from . import core
from .core import C, EMI, HULL, INT, MB, mask

CELL = 2.0
SLOT_GAP = 0.15          # Slot.GAP: slot markers sit this far outside the hull
WALL = 0.3               # art walls: thick, on the room boundary
KEEL = -0.6              # bottom of the hull (Godot HullMesher.KEEL_BOTTOM)
HEADROOM = 2.6           # walls at least this high above the floor
LIGHT_Z = 2.1
# hatch size (1 = S, 2 = M, 3 = L) -> doorway hole (width, height)
DOOR = {1: (1.0, 2.0), 2: (1.6, 2.4), 3: (3.4, 2.4)}
# collar colour per hatch size: you can read a slot's size from the art
COLLAR = {1: "cyan", 2: "neon", 3: "violet"}
# canopy style: opaque walls up to here, glass above. == CutawayController.CUT_HEIGHT,
# so the cutaway removes exactly the glass and the walls stay.
GLASS_Z = 1.15
WALKABLE = ".PLDBKSCTG" + "abcdefghijklmnopqrstuvwxyz"
LETTERS = "abcdefghijklmnopqrstuvwxyz"

ART = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPO = os.path.dirname(ART)
OUT_DIR = os.path.join(ART, "modules", "export")
RENDER_DIR = os.path.join(ART, "modules", "renders")
BLEND_DIR = os.path.join(ART, "modules", "build")
GAME_DIR = os.path.join(REPO, "assets", "models", "modules")
PALETTE_NAME = "kit_palette.png"
PALETTE_GRID = 8
PALETTE_SWATCH = 16


def parse(text):
    lines = text.replace("\r", "").split("\n")
    while lines and not lines[0].strip():
        lines.pop(0)
    while lines and not lines[-1].strip():
        lines.pop()
    return lines


def box(mb, a, b, color, msk=core.NOMASK, mat=HULL):
    """MB.box between any two corners (MB.box needs min < max on every axis, or
    the box turns inside out)."""
    a, b = Vector(a), Vector(b)
    return mb.box([min(a[i], b[i]) for i in range(3)], [max(a[i], b[i]) for i in range(3)], color, msk, mat)


class Module:
    def __init__(self, mid, layout, budget=15000, seed=1, sizes=None):
        """`sizes`: slot letter -> hatch size (1..3), default 2 (M)."""
        self.id = mid
        self.layout = "\n".join(parse(layout))
        self.grid = parse(layout)
        self.rows = len(self.grid)
        self.cols = max(len(r) for r in self.grid)
        self.budget = budget
        self.sizes = sizes or {}
        self.rng = random.Random(seed)
        random.seed(seed)
        self.errors = []
        self.pieces = []       # [object, cutters, massing rect (Godot x0, z0, x1, z1) or None]
        self.slots = {}        # letter -> (x, z, yaw degrees), Godot
        self.massing = []
        self.parts = []
        core.reset()
        self.coll = self._collection(mid)
        self.kit_coll = self._collection("GREEBLE_KIT")
        self.kit_coll.hide_render = True
        self.kit_coll.hide_viewport = True
        self.tmp_coll = self._collection("TMP")
        self.tmp_coll.hide_render = True  # NOT hide_viewport: hidden objects aren't evaluated
        self.mats = core.make_materials()
        core.build_kit(self.kit_coll)
        self.greebles = core.empty("greebles_" + mid, (0, 0, 0), self.coll, size=0.3)
        self.cut = None

    @staticmethod
    def _collection(name):
        c = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(c)
        return c

    # ------------------------------------------------------------ grid
    def char(self, c, r):
        if 0 <= r < self.rows and 0 <= c < len(self.grid[r]):
            return self.grid[r][c]
        return " "

    def cell(self, c, r, z=0.0):
        """Blender position of the centre of cell (c, r)."""
        return Vector(((c - (self.cols - 1) / 2) * CELL, -(r - (self.rows - 1) / 2) * CELL, z))

    def cells(self, chars):
        return [(c, r) for r in range(self.rows) for c in range(len(self.grid[r]))
                if self.grid[r][c] in chars]

    def bounds(self, chars=".PLDBKSCTG"):
        """Blender (x0, x1, y0, y1) of the cell edges around `chars` cells (default:
        the room, without doorway cells)."""
        cs = self.cells(chars)
        xs = [self.cell(c, r).x for c, r in cs]
        ys = [self.cell(c, r).y for c, r in cs]
        return min(xs) - CELL / 2, max(xs) + CELL / 2, min(ys) - CELL / 2, max(ys) + CELL / 2

    def outward(self, c, r):
        """Godot (dx, dz) from a doorway cell towards outer space."""
        for dc, dr in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            if self.char(c + dc, r + dr) == " ":
                return dc, dr
        self.errors.append("doorway at %s is not on the layout boundary" % ((c, r),))
        return 0, 1

    # ------------------------------------------------------------ hull
    def piece(self, build, thick=None, massing=True, name="_piece"):
        """One closed solid of the hull. `build(mb)` fills a mesh builder; `thick`
        solidifies it inwards (shell with an interior face). `massing`: include its
        plan rectangle in the footprint (False for parts above the module roofs)."""
        mb = MB()
        build(mb)
        rect = None
        if massing and mb.bm.verts:
            xs = [v.co.x for v in mb.bm.verts]
            ys = [v.co.y for v in mb.bm.verts]
            rect = (min(xs), -max(ys), max(xs), -min(ys))
        ob = mb.to_object(name, self.tmp_coll, self.mats)
        if thick:
            core.solidify_in(ob, thick)
        self.pieces.append([ob, [], rect])
        return len(self.pieces) - 1

    def rounded(self, mb, x0, x1, y0, y1, z0, z1, radii, dome=(0.0, 0.0), squeeze=0.45,
                step=1.6, livery=None, split=None, color="colony", trim=True):
        """Capsule-style hull section lofted along X (core.rounded_hull), painted:
        `livery=(top, bottom)` two-tone split at z `split`, else one colour."""
        faces = core.rounded_hull(mb, x0, x1, y0, y1, z0, z1, radii, dome=dome,
                                  squeeze=squeeze, step=step)
        if livery:
            top, bottom = livery
            for f in faces:
                hi = f.calc_center_median().z > split
                core.paint(mb, [f], C[top if hi else bottom], mask(0.2, 0, 1 if hi and trim else 0))
        else:
            core.paint(mb, faces, C[color], mask(0.2, 0, 1 if trim else 0))
        return faces

    def band(self, mb, x0, x1, y0, y1, z0, z1, radii, color="white", grow=0.12):
        faces = core.rounded_band(mb, x0, x1, y0, y1, z0, z1, radii, grow=grow)
        core.paint(mb, faces, C[color], mask(0.3, 0, 1))
        return faces

    # ------------------------------------------------------------ canopy style
    def canopy_tube(self, x0, x1, y1, z1=3.4, kb=0.45, kt=1.3, nose=(1.0, 1.0),
                    squeeze=(0.72, 0.85), ribs=(), thick=WALL, strut=0.2, glow=0.0,
                    glass="canopy", frame=True):
        """Glass-canopy tube centred on y = 0 (half width `y1`): octagonal section,
        ivory below GLASS_Z, glass above (cut away in room view), chamfered noses
        beyond x0..x1, a gold stripe along the wall top and a white strut frame
        (`frame`: never cut, always visible). Ribs at x0, x1 and `ribs`.
        Returns the hull piece index."""
        y0, z0 = -y1, KEEL
        stations = sorted({x0, x1, *ribs})

        def body(mb):
            faces = core.chamfer_hull(mb, x0, x1, y0, y1, z0, z1, kb, kt, GLASS_Z, nose,
                                      squeeze, stations)
            for f in faces:
                if abs(f.normal.x) > 0.95 or f.calc_center_median().z < GLASS_Z:
                    core.paint(mb, [f], C["ivory"], mask(0.2))
                else:
                    core.paint(mb, [f], C[glass], mask(0.02, glow, 0 if glass == "canopy" else 1))
        hull = self.piece(body, thick=thick)

        def stripe(mb):
            lo, hi = GLASS_Z - 0.34, GLASS_Z - 0.1
            for sy in (1, -1):
                box(mb, (x0, sy * (y1 - 0.05), lo), (x1, sy * (y1 + 0.06), hi), C["trim_gold"], mask(0.3))
                for xa, n in ((x0, -nose[0]), (x1, nose[1])):
                    if n:
                        a = Vector((xa, sy * (y1 + 0.03), (lo + hi) / 2))
                        py, pz = core.nose_point((sy * y1, (lo + hi) / 2), z0, squeeze)
                        core.beam(mb, a, (xa + n, py + sy * 0.03, pz), hi - lo, C["trim_gold"], mask(0.3))
        self.piece(stripe, massing=False, name="_stripe")

        def struts(mb):
            prof = core.chamfer_profile(y0, y1, z0, z1, kb, kt, GLASS_Z, grow=strut / 2)[3:9]
            col, msk = C["strut"], mask(0.15)

            def chain(x, pts):
                for p, q in zip(pts, pts[1:]):
                    core.beam(mb, (x, *p), (x, *q), strut, col, msk)
            for py, pz in prof:                                   # rails
                core.beam(mb, (x0, py, pz), (x1, py, pz), strut, col, msk)
            for x in stations:                                    # ribs
                chain(x, prof)
            for xa, n in ((x0, -nose[0]), (x1, nose[1])):       # noses
                if not n:
                    continue
                small = [core.nose_point(p, z0, squeeze) for p in prof]
                for p, q in zip(prof, small):
                    core.beam(mb, (xa, *p), (xa + n, *q), strut, col, msk)
                chain(xa + n, small)
        if frame:
            self.frame(struts)
        return hull

    def canopy_polygon(self, pts, z1=3.6, kb=0.45, kt=1.2, roof=None, thick=WALL,
                       strut=0.2, spokes=False):
        """Glass-canopy room over a plan polygon (CCW, Blender XY): ivory walls below
        GLASS_Z, glass above, gold band, white strut frame along every step. `roof` =
        [(inset, z), ...] above the wall top (default: one chamfer of `kt` up to z1;
        give several rings for a dome). `spokes`: struts from the top ring to the
        centre. Returns the hull piece index."""
        z0 = KEEL
        upper = roof or [(kt, z1)]
        wall_top = z1 - kt if roof is None else roof[0][1] - 0.9
        steps = [(kb, z0), (0.0, z0 + kb), (0.0, GLASS_Z), (0.0, wall_top)] + list(upper)

        def body(mb):
            faces = core.polygon_hull(mb, pts, steps)
            for f in faces:
                if f.calc_center_median().z < GLASS_Z:
                    core.paint(mb, [f], C["ivory"], mask(0.2))
                else:
                    core.paint(mb, [f], C["canopy"], mask(0.02))
        hull = self.piece(body, thick=thick)

        def band(mb):
            faces = core.polygon_band(mb, pts, GLASS_Z - 0.34, GLASS_Z - 0.1)
            core.paint(mb, faces, C["trim_gold"], mask(0.3))
        self.piece(band, massing=False, name="_band")

        def frame(mb):
            col, msk = C["strut"], mask(0.15)
            rings = [[Vector((x, y, z)) for x, y in core.offset_polygon(pts, inset - strut / 2)]
                     for inset, z in steps[2:]]
            for ring in rings:
                for i in range(len(ring)):
                    core.beam(mb, ring[i - 1], ring[i], strut, col, msk)
            for a, b in zip(rings, rings[1:]):
                for p, q in zip(a, b):
                    core.beam(mb, p, q, strut, col, msk)
            if spokes:
                top = rings[-1]
                c = sum(top, Vector()) / len(top)
                for p in top:
                    core.beam(mb, p, c, strut, col, msk)
        self.frame(frame)
        return hull

    def portholes(self, xs, y1, z=0.5, r=0.34, sides=(1, -1)):
        """Octagonal amber portholes on the side walls (y = +-y1) of a canopy tube,
        navy rims; they glow when powered (G mask)."""
        def build(mb):
            for sy in sides:
                out = Vector((0, sy, 0))
                for x in xs:
                    at = Vector((x, sy * (y1 - 0.02), z))
                    core.prism_ring(mb, at, out, r + 0.1, r - 0.02, 0.1, C["navy"], mask(0.3))
                    mb.cyl(r, 0.08, at + out * 0.03, (90, 0, 0), C["amber"], mask(0.0, 1.0), seg=8)
        self.piece(build, massing=False, name="_portholes")

    def porthole_at(self, spots, r=0.34):
        """Octagonal amber portholes at [(position, outward normal)] (glow when powered)."""
        def build(mb):
            for at, out in spots:
                at, out = Vector(at), Vector(out).normalized()
                core.prism_ring(mb, at - out * 0.02, out, r + 0.1, r - 0.02, 0.1, C["navy"], mask(0.3))
                mb.cyl(r, 0.08, at + out * 0.02, out.to_track_quat("Z", "Y").to_euler(), C["amber"],
                       mask(0.0, 1.0), seg=8)
        self.piece(build, massing=False, name="_portholes")

    def frame(self, build):
        """Exterior structure that is never cut and always visible (canopy struts)."""
        mb = MB()
        build(mb)
        return mb.to_object("frame", self.coll, self.mats)

    def port(self, letter, pieces, face, depth=0.4, plate=2.1):
        """Canopy-style docking port: an octagonal bulkhead plate on the hull face,
        a navy tube stub and a band coloured by hatch size, then the doorway
        (hole through `pieces` + the port, slot marker beyond the stub). `face` =
        hull surface beyond the room boundary at the door."""
        letter = letter.upper()
        cs = self.cells(letter.lower())
        if not cs:
            self.errors.append("slot %s: no '%s' in the layout" % (letter, letter.lower()))
            return
        size = self.sizes.get(letter, 2)
        ox, oz = self.outward(*cs[0])
        out = Vector((ox, -oz, 0))
        centre = sum((self.cell(c, r) for c, r in cs), Vector()) / len(cs)
        w, h = DOOR[size]
        r_in = math.hypot(w / 2, h / 2) / math.cos(math.pi / 8) + 0.08  # door fits inside
        at = centre - out * (CELL / 2) + out * face + Vector((0, 0, h / 2))

        def build(mb):
            core.prism_ring(mb, at - out * 0.05, out, max(plate, r_in + 0.4), r_in, 0.2, C["ivory"], mask(0.2))
            core.prism_ring(mb, at, out, r_in + 0.2, r_in, depth, C["navy"], mask(0.3))
            core.prism_ring(mb, at + out * (depth * 0.55), out, r_in + 0.3, r_in, depth * 0.3,
                            C[COLLAR[size]], mask(0.3))
        p = self.piece(build, massing=False, name="_port")
        pieces = list(pieces) if isinstance(pieces, (list, tuple)) else [pieces]
        self.doorway(letter, pieces + [p], face=face + depth, collar=False, size=size)

    def hole(self, piece, mn, mx):
        """Cut a box out of a hull piece (windows, open hatches)."""
        self.pieces[piece][1].append((Vector(mn), Vector(mx)))

    def doorway(self, letter, piece, face=WALL, collar=True, size=None):
        """Doorway of slot `letter` (layout letter, lower case in the ASCII): a hole
        through `piece` on the room boundary, a collar coloured by hatch size, and
        the slot_X marker `face + SLOT_GAP` outside the room boundary. `face` = how
        far the hull's outer surface sits beyond the room boundary at the door.
        `piece`: one piece index or a list (every piece the hole goes through)."""
        letter = letter.upper()
        cs = self.cells(letter.lower())
        if not cs:
            self.errors.append("slot %s: no '%s' in the layout" % (letter, letter.lower()))
            return
        size = size or self.sizes.get(letter, 2)
        ox, oz = self.outward(*cs[0])
        out = Vector((ox, -oz, 0))                     # Blender
        centre = sum((self.cell(c, r) for c, r in cs), Vector()) / len(cs)
        edge = centre - out * (CELL / 2)               # room boundary at the door
        w, h = DOOR[size]
        side = Vector((-out.y, out.x, 0))
        a = edge - out * 0.25 - side * (w / 2)
        b = edge + out * (face + 0.3) + side * (w / 2)
        for p in (piece if isinstance(piece, (list, tuple)) else [piece]):
            self.hole(p, (min(a.x, b.x), min(a.y, b.y), -0.01), (max(a.x, b.x), max(a.y, b.y), h))
        if collar:
            self.collar(edge + out * face, out, w, h, COLLAR[size])
        self.slot(letter, edge + out * (face + SLOT_GAP), (ox, oz))

    def collar(self, at, out, w, h, color):
        """Hatch frame proud of the hull face (closed boxes, part of the hull)."""
        def build(mb):
            side = Vector((-out.y, out.x, 0))
            t, d = 0.18, 0.12
            for s in (-1, 1):  # jambs
                p = at + side * s * (w / 2 + t / 2)
                box(mb, p - side * t / 2 - out * 0.05, p + side * t / 2 + out * d + Vector((0, 0, h + t)),
                    C[color], mask(0.3))
            p = at + Vector((0, 0, h))                      # lintel
            box(mb, p - side * (w / 2 + t) - out * 0.05, p + side * (w / 2 + t) + out * d + Vector((0, 0, t)),
                C[color], mask(0.3))
        self.piece(build, massing=False, name="_collar")

    # ------------------------------------------------------------ markers & parts
    def slot(self, letter, loc, out):
        """slot_X empty: local -Y (Blender) = Godot +Z = out of the module."""
        ox, oz = out
        yaw = math.degrees(math.atan2(ox, oz))
        e = core.empty("slot_" + letter, (loc.x, loc.y, 0.0), self.coll, "SINGLE_ARROW", 0.8,
                       rot=(0, 0, yaw))
        self.slots[letter] = (round(loc.x, 3), round(-loc.y, 3), round(yaw, 1))
        return e

    def light(self, name, x, y, z=LIGHT_Z):
        return core.empty("light_" + name, (x, y, z), self.coll, "SPHERE", 0.2)

    def mount(self, name, loc, normal=(0, 0, 1)):
        """Upgrade mount: +Z (Blender) = surface normal."""
        e = core.empty("mount_" + name, loc, self.coll, "ARROWS", 0.6)
        e.rotation_euler = Vector(normal).to_track_quat("Z", "Y").to_euler()
        return e

    def part(self, name, build):
        mb = MB()
        build(mb)
        ob = mb.to_object("part_" + name, self.coll, self.mats)
        self.parts.append(ob)
        return ob

    def prop(self, name, build):
        mb = MB()
        build(mb)
        return mb.to_object("prop_" + name, self.coll, self.mats)

    def greeble(self, kit, loc, face="+Z", spin=0.0, scale=(1, 1, 1), interior=False):
        return core.put(kit, loc, face, spin, scale, self.coll, self.greebles, interior)

    def pipe(self, a, b, face, kit="gk_pipe", interior=False):
        core.pipe_run(a, b, face, self.coll, self.greebles, kit=kit, interior=interior)

    def cut_box(self, x0, x1, y0, y1, top):
        """Region the cutaway opens (X/Y extent and top; bottom is floor + 1.15)."""
        mb = MB()
        mb.box((x0, y0, 1.15), (x1, y1, top), C["cream"])
        self.cut = mb.to_object("cut_box", self.coll, [core.M["cap"]])
        self.cut.display_type = "WIRE"
        self.cut.hide_render = True
        return self.cut

    # ------------------------------------------------------------ finish
    def finish(self):
        """Apply the hole booleans, merge every piece into one `hull`, check it."""
        bm = bmesh.new()
        dg = bpy.context.evaluated_depsgraph_get
        for ob, cutters, rect in self.pieces:
            for i, (mn, mx) in enumerate(cutters):
                cm = MB()
                cm.box(mn, mx, C["steel"], mask(0.6))
                cut = cm.to_object("_hole", self.tmp_coll, self.mats)
                md = ob.modifiers.new("HOLE%d" % i, "BOOLEAN")
                md.operation = "DIFFERENCE"
                md.solver = "EXACT"
                md.object = cut
            bpy.context.view_layer.update()
            me = bpy.data.meshes.new_from_object(ob.evaluated_get(dg()))
            me.transform(ob.matrix_world)
            bm.from_mesh(me)
            bpy.data.meshes.remove(me)
            if rect:
                self.massing.append(rect)
        me = bpy.data.meshes.new("hull")
        bm.to_mesh(me)
        bm.free()
        for m in self.mats:
            me.materials.append(m)
        core._activate_masks(me)
        core.smooth(me)
        self.hull = bpy.data.objects.new("hull", me)
        self.coll.objects.link(self.hull)
        for ob in list(self.tmp_coll.objects):
            bpy.data.objects.remove(ob, do_unlink=True)
        centre = Vector((0, 0, 1.5))
        for ob in self.parts:
            d = ob.matrix_world.translation - centre
            d = d.normalized() if d.length > 1e-3 else Vector((0, 0, 1))
            ob["explode_dir"] = [round(d.x, 3), round(d.z, 3), round(-d.y, 3)]
        self._bake_palette_uvs()
        self.validate()

    # ------------------------------------------------------------ checks
    def validate(self):
        e = self.errors
        bm = bmesh.new()
        bm.from_mesh(self.hull.data)
        open_edges = sum(1 for ed in bm.edges if not ed.is_manifold)
        bm.free()
        if open_edges:
            e.append("hull is not watertight: %d non-manifold edges" % open_edges)
        tris = self.triangles()
        if tris > self.budget:
            e.append("%d triangles > budget %d" % (tris, self.budget))
        letters = {ch.upper() for row in self.grid for ch in row if ch in LETTERS}
        for letter in sorted(letters - set(self.slots)):
            e.append("layout slot %s has no doorway()" % letter)
        for letter, (x, z, yaw) in self.slots.items():
            if abs((yaw + 45) % 90 - 45) > 0.5:
                e.append("slot %s yaw %.1f is not a multiple of 90" % (letter, yaw))
            for x0, z0, x1, z1 in self.massing:
                if x0 + 0.05 < x < x1 - 0.05 and z0 + 0.05 < z < z1 - 0.05:
                    e.append("slot %s (%.2f, %.2f) lies inside the hull footprint %s"
                             % (letter, x, z, (x0, z0, x1, z1)))
            # the game puts the doorway's nav link 1.15 m inside: it must be walkable
            yr = math.radians(yaw)
            dx, dz = x - math.sin(yr) * (CELL / 2 + SLOT_GAP), z - math.cos(yr) * (CELL / 2 + SLOT_GAP)
            c = round(dx / CELL + (self.cols - 1) / 2)
            r = round(dz / CELL + (self.rows - 1) / 2)
            if self.char(c, r) not in WALKABLE:
                e.append("slot %s: its door point (%.2f, %.2f) is not on a walkable cell" % (letter, dx, dz))
        self._check_room_fits()
        if self.cut is None and self.cells(".PLDBKSCTG"):
            e.append("walkable module without cut_box()")
        for msg in e:
            print("KIT ERROR:", msg)
        return e

    def _check_room_fits(self):
        """Every walkable cell (not doorways) must lie in the room: its corners at
        floor and head height, and its centre at full headroom, are neither inside
        the wall nor outside the hull. Ray parity: going up AND down from a room
        point crosses an even number (>= 2) of hull surfaces (a point under an
        overhang, outside the hull, has nothing below it)."""
        from mathutils.bvhtree import BVHTree
        dg = bpy.context.evaluated_depsgraph_get()
        tree = BVHTree.FromObject(self.hull, dg)
        bad = []
        for c, r in self.cells(".PLDBKSCTG"):
            centre = self.cell(c, r)
            pts = [centre + Vector((sx * (CELL / 2 - 0.1), sy * (CELL / 2 - 0.1), z))
                   for sx in (-1, 1) for sy in (-1, 1) for z in (0.05, 1.9)]
            pts.append(centre + Vector((0, 0, HEADROOM - 0.05)))
            for p in pts:
                ns = []
                for d in (Vector((0, 0, 1)), Vector((0, 0, -1))):
                    n, o = 0, p.copy()
                    for _ in range(64):
                        hit = tree.ray_cast(o, d)
                        if hit[0] is None:
                            break
                        n += 1
                        o = hit[0] + d * 1e-4
                    ns.append(n)
                if min(ns) == 0 or any(n % 2 for n in ns):
                    bad.append(((c, r), tuple(round(v, 2) for v in p), min(ns) if min(ns) == 0 else 1))
                    break
        for cell, p, n in bad:
            self.errors.append("layout cell %s doesn't fit in the room: %s is %s" % (
                cell, p, "outside the hull" if n == 0 else "inside the wall"))

    def triangles(self):
        n = 0
        for ob in self.coll.all_objects:
            if ob.type == "MESH" and not ob.name.startswith("cut_box"):
                me = ob.data
                me.calc_loop_triangles()
                n += len(me.loop_triangles)
        return n

    # ------------------------------------------------------------ palette
    def _bake_palette_uvs(self):
        """Every face corner -> UV of its colour's swatch in the FIXED kit palette
        (core.PAL order), so all kit modules share one texture."""
        index = {tuple(round(v, 4) for v in core.C[k][:3]): i for i, k in enumerate(core.PAL)}
        g = PALETTE_GRID
        meshes = {ob.data.name: ob.data for ob in self.coll.all_objects
                  if ob.type == "MESH" and "Base" in ob.data.color_attributes}
        bad = set()
        for me in meshes.values():
            uv = me.uv_layers.get("UVMap") or me.uv_layers.new(name="UVMap")
            for li, d in enumerate(me.color_attributes["Base"].data):
                k = tuple(round(v, 4) for v in d.color[:3])
                i = index.get(k)
                if i is None:
                    bad.add(k)
                    i = 0
                uv.data[li].uv = ((i % g + 0.5) / g, (i // g + 0.5) / g)
        for k in bad:
            self.errors.append("colour %s is not in the kit palette (core.PAL)" % (k,))

    @staticmethod
    def write_palette(path):
        g, sw = PALETTE_GRID, PALETTE_SWATCH
        assert len(core.PAL) <= g * g
        n = g * sw
        px = [0.0] * (n * n * 4)
        for i, k in enumerate(core.PAL):
            gx, gy = i % g, i // g
            srgb = [v * 12.92 if v <= 0.0031308 else 1.055 * v ** (1 / 2.4) - 0.055
                    for v in core.C[k][:3]] + [1.0]
            for yy in range(gy * sw, (gy + 1) * sw):
                for xx in range(gx * sw, (gx + 1) * sw):
                    o = (yy * n + xx) * 4
                    px[o:o + 4] = srgb
        img = bpy.data.images.new("kit_palette", n, n, alpha=False)
        img.pixels = px
        img.filepath_raw = path
        img.file_format = "PNG"
        img.save()

    # ------------------------------------------------------------ output
    def sidecar(self):
        return {
            "id": self.id, "layout": self.layout,
            "slots": {k: list(v) for k, v in sorted(self.slots.items())},
            "slot_sizes": {k: self.sizes.get(k, 2) for k in sorted(self.slots)},
            "massing": [[round(x0, 3), round(z0, 3), round(x1 - x0, 3), round(z1 - z0, 3)]
                        for x0, z0, x1, z1 in self.massing],
            "triangles": self.triangles(), "errors": self.errors,
        }

    def export(self):
        os.makedirs(OUT_DIR, exist_ok=True)
        os.makedirs(GAME_DIR, exist_ok=True)
        for ob in bpy.context.view_layer.objects:
            ob.select_set(False)
        for ob in self.coll.all_objects:
            ob.select_set(True)
        props = bpy.ops.export_scene.gltf.get_rna_type().properties.keys()
        want = dict(export_format="GLB", use_selection=True, export_yup=True, export_apply=True,
                    export_extras=True, export_lights=False, export_cameras=False,
                    export_vertex_color="ACTIVE", export_all_vertex_colors=False,
                    export_attributes=False, export_materials="EXPORT", export_texcoords=True)
        kw = {k: v for k, v in want.items() if k in props}
        path = os.path.join(GAME_DIR, self.id + ".glb")
        bpy.ops.export_scene.gltf(filepath=path, **kw)
        self.write_palette(os.path.join(GAME_DIR, PALETTE_NAME))
        with open(os.path.join(OUT_DIR, self.id + ".json"), "w") as f:
            json.dump(self.sidecar(), f, indent=1)
        print("KIT EXPORTED", path)

    def save_blend(self):
        os.makedirs(BLEND_DIR, exist_ok=True)
        bpy.ops.wm.save_as_mainfile(filepath=os.path.join(BLEND_DIR, self.id + ".blend"))

    def render(self):
        """Two previews: closed (station view) and cut open (room view)."""
        s = bpy.context.scene
        for engine in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE", "BLENDER_WORKBENCH"):
            try:
                s.render.engine = engine
                break
            except TypeError:
                continue
        s.render.resolution_x, s.render.resolution_y = 1280, 720
        try:
            s.eevee.taa_render_samples = 16
        except AttributeError:
            pass
        try:
            s.view_settings.view_transform = "Standard"
        except TypeError:
            pass
        world = bpy.data.worlds.new("space")
        world.use_nodes = True
        bg = next(n for n in world.node_tree.nodes if n.type == "BACKGROUND")
        bg.inputs[0].default_value = (0.012, 0.01, 0.04, 1)
        s.world = world
        sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
        sun.data.energy = 3.0
        sun.data.color = (0.8, 0.85, 1.0)
        sun.rotation_euler = core.E(40, 10, 150)
        s.collection.objects.link(sun)
        fill = bpy.data.objects.new("fill", bpy.data.lights.new("fill", "SUN"))
        fill.data.energy = 0.8
        fill.data.color = (1.0, 0.6, 0.85)
        fill.rotation_euler = core.E(70, 0, -30)
        s.collection.objects.link(fill)
        lamps = []
        for name in [o.name for o in self.coll.all_objects if o.name.startswith("light_")]:
            ob = bpy.data.objects[name]
            pl = bpy.data.objects.new("pl_" + name, bpy.data.lights.new("pl_" + name, "POINT"))
            pl.data.energy = 150
            pl.data.color = C["amber"][:3]
            pl.location = ob.matrix_world.translation
            s.collection.objects.link(pl)
            lamps.append(pl)
        cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
        cam.data.type = "ORTHO"
        s.collection.objects.link(cam)
        s.camera = cam
        pts = [Vector(c) for ob in self.coll.all_objects if ob.type == "MESH" and ob != self.cut
               for c in (ob.matrix_world @ Vector(b) for b in ob.bound_box)]
        lo = Vector([min(p[i] for p in pts) for i in range(3)])
        hi = Vector([max(p[i] for p in pts) for i in range(3)])
        centre = (lo + hi) / 2
        cam.data.clip_end = 2000
        os.makedirs(RENDER_DIR, exist_ok=True)
        # iso: camera on the +X / -Y side, 35 deg above the horizon (sees -Y, +X, top)
        jobs = [("closed", False, (55, 0, 45), 1.35), ("top", False, (0, 0, 0), 1.2)]
        if self.cut is not None:
            jobs.append(("cut", True, (55, 0, 45), 1.35))
        for tag, cut_on, rot, zoom in jobs:
            cam.rotation_euler = core.E(*rot)
            fwd = cam.rotation_euler.to_matrix() @ Vector((0, 0, -1))
            cam.location = centre - fwd * 500
            cam.data.ortho_scale = max((hi - lo).length * zoom, 6)
            for pl in lamps:
                pl.hide_render = not cut_on
            md = None
            if cut_on:
                md = self.hull.modifiers.new("CUT_PREVIEW", "BOOLEAN")
                md.operation = "DIFFERENCE"
                md.solver = "EXACT"
                md.use_self = True
                md.object = self.cut
                for ob in self.coll.all_objects:
                    if ob == self.greebles or ob.parent == self.greebles:
                        ob.hide_render = True
            s.render.filepath = os.path.join(RENDER_DIR, "%s_%s.png" % (self.id, tag))
            bpy.ops.render.render(write_still=True)
            if md:
                self.hull.modifiers.remove(md)
            print("KIT RENDERED", s.render.filepath)


__all__ = ["Module", "box", "MB", "C", "mask", "HULL", "INT", "EMI", "CELL", "WALL", "KEEL", "HEADROOM",
           "DOOR", "GLASS_Z", "Matrix", "Vector", "core"]
