"""Refinery (canopy style, mockup 1000037501): a hexagonal glass-roofed plant room, a
big reclaimer vat in the middle, tanks and crates in the corners, an intake grille.
Attach M-P (A, -X) . offers B (+X, M-P). Mount: chimney (roof). Reclaims water."""
import math

from kit import core
from kit.module import C, box, mask

ID = "refinery"
LAYOUT = """\
#####
#C..#
a.#.b
#...#
#####"""
SEED = 59

APOTHEM = 4.6
FACE = APOTHEM - 3.0
PLAN = core.regular_polygon(6, APOTHEM)
Z1 = 3.8


def build(m):
    hull = m.canopy_polygon(PLAN, z1=Z1, kt=1.4)
    m.port("A", [hull], face=FACE, plate=2.0)
    m.port("B", [hull], face=FACE, plate=2.0)

    def grille(mb):  # intake grille on the south-west flat, warm marker lights
        a = math.radians(240)
        out = Vector((math.cos(a), math.sin(a), 0))
        side = Vector((-out.y, out.x, 0))
        c = out * (APOTHEM + 0.02)
        for i in range(5):
            z = -0.1 + i * 0.22
            p, q = c - side * 1.3 + Vector((0, 0, z)), c + side * 1.3 + Vector((0, 0, z + 0.12))
            core.beam(mb, (p + q) / 2 - side * 1.3, (p + q) / 2 + side * 1.3, 0.12, C["navy"], mask(0.3))
        for s in (-1.7, 1.7):
            p = c + side * s + Vector((0, 0, 0.8))
            box(mb, p - Vector((0.1, 0.1, 0.1)), p + Vector((0.1, 0.1, 0.1)), C["amber"], mask(0.0, 1.0))
    m.piece(grille, massing=False, name="_grille")

    m.light("main", 0.0, 0.0)
    m.mount("chimney", (1.5, 1.5, Z1 + 0.01))
    m.cut_box(-APOTHEM, APOTHEM, -APOTHEM, APOTHEM, 7.0)

    def plant(mb):  # vat on the blocked centre cell, pipes out, tanks in the hex corners
        box(mb, (-1.0, -1.0, -0.2), (1.0, 1.0, 0.0), C["deck"], mask(0.1), mat=1)
        mb.cyl(0.9, 0.3, (0, 0, 0.15), (0, 0, 0), C["trim_gold"], mask(0.2), mat=1, seg=6)
        mb.cyl(0.75, 1.4, (0, 0, 1.0), (0, 0, 0), C["steel_lt"], mask(0.3), mat=1, seg=8)
        mb.cyl(0.5, 0.5, (0, 0, 1.95), (0, 0, 0), C["navy"], mask(0.2), mat=1, r2=0.2, seg=8)
        for a in (30, 150, 270):
            r = math.radians(a)
            d = Vector((math.cos(r), math.sin(r), 0))
            core.beam(mb, d * 0.7 + Vector((0, 0, 1.6)), d * 2.9 + Vector((0, 0, 1.6)), 0.18, C["navy"], mask(0.2), mat=1)
        for a in (90, 210, 330):   # tanks in the corner zones outside the room square
            r = math.radians(a)
            x, y = 4.0 * math.cos(r), 4.0 * math.sin(r)
            mb.cyl(0.55, 1.6, (x, y, 0.8), (0, 0, 0), C["navy"], mask(0.3), mat=1, seg=8)
            mb.cyl(0.6, 0.12, (x, y, 1.0), (0, 0, 0), C["trim_gold"], mask(0.2), mat=1, seg=8)
        for x, y in ((-2.6, -2.6), (2.6, 2.6)):    # crates
            box(mb, (x - 0.4, y - 0.4, 0.0), (x + 0.4, y + 0.4, 0.7), C["crate"], mask(0.3), mat=1)
    m.prop("plant", plant)


from kit.module import Vector  # noqa: E402
