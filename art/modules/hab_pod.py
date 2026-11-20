"""Hab pod (canopy style): the cheap early room, a small faceted glass-roofed cabin
with chamfered corners, a bay window in its north wall and amber portholes. Attach
M-P (A, south). Mount: garden (roof, the hab_garden upgrade)."""
from kit.module import C, GLASS_Z, box, mask

ID = "hab_pod"
LAYOUT = """\
##W##
#.L.#
#C..#
##a##"""
SEED = 37
BUDGET = 3000

HX = 3.4                          # room x -3..3 + walls; fits wreck slot B (clears its wing)
NORTH = 2.3                       # the bay window wall: on the room boundary (y = 2)
FACE = 0.9                        # south port face beyond the room boundary
SOUTH = -(2.0 + FACE)
K = 1.0                           # plan corner chamfer
Z1 = 3.4
# square north corners: the room reaches the north wall (and a small chamfer would
# turn inside out under the roof inset)
PLAN = [(-HX + K, SOUTH), (HX - K, SOUTH), (HX, SOUTH + K), (HX, NORTH), (-HX, NORTH),
        (-HX, SOUTH + K)]


def build(m):
    hull = m.canopy_polygon(PLAN, z1=Z1, kt=1.2)
    m.port("A", [hull], face=FACE, plate=2.0)
    m.hole(hull, (-0.8, NORTH - 0.6, 0.6), (0.8, NORTH + 0.3, 2.05))   # bay window W
    m.porthole_at([((sx * HX, y, 0.55), (sx, 0, 0)) for sx in (1, -1) for y in (-0.9, 0.9)])

    def outside(mb):  # navy hatch panels on the south flat, belly light strip
        for x in (-2.0, 2.0):
            box(mb, (x - 0.35, SOUTH - 0.04, 0.05), (x + 0.35, SOUTH + 0.02, 0.85), C["navy"], mask(0.2))
        box(mb, (-1.6, NORTH - 0.02, -0.25), (1.6, NORTH + 0.04, -0.12), C["amber"], mask(0.0, 1.0))
    m.piece(outside, massing=False, name="_outside")

    m.light("main", 0.0, 0.0)
    m.mount("garden", (1.6, -0.6, Z1 + 0.01))
    m.cut_box(-HX, HX, SOUTH, NORTH, 7.0)

    def decor(mb):  # rug, a bunk against the east wall, shelf by the window
        box(mb, (-1.4, -1.2, 0.0), (1.4, 1.0, 0.03), C["fabric"], mask(0.1), mat=1)
        box(mb, (2.15, -1.8, 0.0), (3.25, 0.4, 0.45), C["ivory"], mask(0.2), mat=1)
        box(mb, (2.2, -1.75, 0.45), (3.2, 0.35, 0.6), C["deck"], mask(0.1), mat=1)
        box(mb, (-2.6, 1.55, 0.0), (-1.4, 1.95, 1.1), C["ivory"], mask(0.2), mat=1)
        box(mb, (-2.55, 1.5, 0.75), (-1.45, 1.55, 0.9), C["navy"], mask(0.2), mat=1)
    m.prop("decor", decor)
