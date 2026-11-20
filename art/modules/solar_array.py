"""Solar array (canopy style): a small glass-roofed maintenance cabin carrying a
gold truss with navy solar wings on both sides. Attach M-P (A, south). Parts:
array (always there), extension (the solar_extend upgrade: outer wing panels)."""
from kit import core
from kit.module import C, box, mask

ID = "solar_array"
LAYOUT = """\
#####
#.C.#
#.L.#
##a##"""
SEED = 41
BUDGET = 4000

HX = 3.4                          # fits wreck slot B (clears its wing)
FACE = 0.9
SOUTH = -(2.0 + FACE)
NORTH = 2.6
K = 1.0
Z1 = 3.2
# square north corners: the room reaches the north wall (and a small chamfer would
# turn inside out under the roof inset)
PLAN = [(-HX + K, SOUTH), (HX - K, SOUTH), (HX, SOUTH + K), (HX, NORTH), (-HX, NORTH),
        (-HX, SOUTH + K)]
TRUSS_Z = 2.3                     # wing spar height (on the roof chamfer)
W0, W1 = HX + 0.6, HX + 6.6       # inner wing: x from the cabin wall
E1 = W1 + 4.2                     # extension: outer panels up to here
PANEL = 1.6                       # half chord of a wing (along y)


def wing(mb, x0, x1):
    """Two navy panels (fore and aft of the spar) between x0 and x1, both sides,
    gold frames, a gold spar through them."""
    for sx in (1, -1):
        a, b = sorted((sx * x0, sx * x1))
        core.beam(mb, (a, 0, TRUSS_Z), (b, 0, TRUSS_Z), 0.22, C["trim_gold"], mask(0.3))
        for sy in (1, -1):
            y0, y1 = sorted((sy * 0.2, sy * (0.2 + 2 * PANEL)))
            box(mb, (a, y0, TRUSS_Z - 0.05), (b, y1, TRUSS_Z + 0.03), C["solar"], mask(0.05, 0.0, 1.0))
            for x in (a, b):
                box(mb, (x - 0.06, y0, TRUSS_Z - 0.06), (x + 0.06, y1, TRUSS_Z + 0.07), C["trim_gold"], mask(0.3))
            yo = y1 if sy > 0 else y0
            box(mb, (a, yo - 0.06, TRUSS_Z - 0.06), (b, yo + 0.06, TRUSS_Z + 0.07), C["trim_gold"], mask(0.3))
            k = int(abs(b - a) / 2.2)
            for i in range(1, k):                # cell seams
                x = a + (b - a) * i / k
                box(mb, (x - 0.03, y0, TRUSS_Z + 0.03), (x + 0.03, y1, TRUSS_Z + 0.05), C["navy"], mask(0.1))


def build(m):
    hull = m.canopy_polygon(PLAN, z1=Z1, kt=1.1)
    m.port("A", [hull], face=FACE, plate=2.0)
    m.porthole_at([((0.0, NORTH, 0.55), (0, 1, 0))])

    def joints(mb):  # gold rotary joints where the spar leaves the cabin, roof mast
        for sx in (1, -1):
            core.prism_ring(mb, (sx * (HX - 0.15), 0, TRUSS_Z), (sx, 0, 0), 0.55, 0.2, 0.9, C["trim_gold"], mask(0.3))
        mb.cyl(0.12, 1.6, (0, 0, Z1 + 0.8), (0, 0, 0), C["strut"], mask(0.2), seg=6)
        mb.cyl(0.3, 0.12, (0, 0, Z1 + 1.6), (0, 0, 0), C["amber"], mask(0.0, 1.0), seg=8)
    m.piece(joints, massing=False, name="_joints")

    m.part("array", lambda mb: wing(mb, W0, W1))
    m.part("extension", lambda mb: wing(mb, W1 + 0.2, E1))

    m.light("main", 0.0, 0.0)
    m.cut_box(-HX, HX, SOUTH, NORTH, 7.0)

    def decor(mb):  # battery cabinets along the walls, floor runner
        box(mb, (-0.45, SOUTH + 0.3, 0.0), (0.45, 1.0, 0.03), C["navy"], mask(0.2), mat=1)
        for x in (-2.6, 2.6):
            box(mb, (x - 0.5, -1.6, 0.0), (x + 0.5, 1.4, 1.0), C["ivory"], mask(0.2), mat=1)
            for y in (-1.0, 0.0, 1.0):
                box(mb, (x - 0.52, y - 0.3, 0.6), (x + 0.52, y + 0.3, 0.8), C["mint"], mask(0.0, 0.8), mat=1)
    m.prop("decor", decor)
