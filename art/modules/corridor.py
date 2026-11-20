"""Corridor (canopy style): the shortest connector, a faceted glass-roofed box between
two octagonal ports, a porthole on each side wall. Attach M-P (A, north end) . offers
B (south end, M-P)."""
from kit.module import C, box, mask

ID = "corridor"
LAYOUT = """\
#a#
#L#
#b#"""
SEED = 61
BUDGET = 1500

HX = 1.9                          # half width: the port plates (3.8 m) just fit
FACE = 1.0                        # hull end beyond the room boundary at each door
HY = 1.0 + FACE
Z1 = 3.2
PLAN = [(-HX, -HY), (HX, -HY), (HX, HY), (-HX, HY)]


def build(m):
    hull = m.canopy_polygon(PLAN, z1=Z1, kt=1.0)
    m.port("A", [hull], face=FACE, plate=2.0)
    m.port("B", [hull], face=FACE, plate=2.0)
    m.porthole_at([((sx * HX, 0.0, 0.55), (sx, 0, 0)) for sx in (1, -1)], r=0.3)

    m.light("main", 0.0, 0.0)
    m.cut_box(-HX, HX, -HY, HY, 6.0)

    def decor(mb):  # navy floor runner between the doors, handrails on the walls
        box(mb, (-0.45, -HY + 0.3, 0.0), (0.45, HY - 0.3, 0.03), C["navy"], mask(0.2), mat=1)
        for sx in (1, -1):
            x = sx * (HX - 0.38)
            box(mb, (x - 0.04, -1.0, 0.95), (x + 0.04, 1.0, 1.01), C["trim_gold"], mask(0.2), mat=1)
    m.prop("decor", decor)
