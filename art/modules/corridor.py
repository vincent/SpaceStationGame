"""Corridor (canopy style): a connector, a faceted glass-roofed box (8 m) between two
octagonal ports, a mid strut and two portholes on each side wall. Attach M-P (A, north end) . offers
B (south end, M-P)."""
from kit import core
from kit.module import C, box, mask

ID = "corridor"
LAYOUT = """\
#a#
#.#
#L#
#.#
#b#"""
SEED = 61
BUDGET = 2500

HX = 1.9                          # half width: the port plates (3.8 m) just fit
FACE = 1.0                        # hull end beyond the room boundary at each door
HY = 3.0 + FACE
Z1 = 3.2
PLAN = [(-HX, -HY), (HX, -HY), (HX, 0.0), (HX, HY), (-HX, HY), (-HX, 0.0)]   # mid vertices: a strut rib


def build(m):
    hull = m.canopy_polygon(PLAN, z1=Z1, kt=1.0)
    m.frame(lambda mb: core.beam(mb, (-(HX - 0.9), 0.0, Z1), (HX - 0.9, 0.0, Z1), 0.2, C["strut"],
                                 mask(0.15)))   # roof cross strut over the mid rib
    m.port("A", [hull], face=FACE, plate=2.0)
    m.port("B", [hull], face=FACE, plate=2.0)
    m.porthole_at([((sx * HX, y, 0.55), (sx, 0, 0)) for sx in (1, -1) for y in (-1.8, 1.8)], r=0.3)

    m.light("main", 0.0, 0.0)
    m.cut_box(-HX, HX, -HY, HY, 6.0)

    def decor(mb):  # navy floor runner between the doors, handrails on the walls
        box(mb, (-0.45, -HY + 0.3, 0.0), (0.45, HY - 0.3, 0.03), C["navy"], mask(0.2), mat=1)
        for sx in (1, -1):
            x = sx * (HX - 0.38)
            box(mb, (x - 0.04, -3.0, 0.95), (x + 0.04, 3.0, 1.01), C["trim_gold"], mask(0.2), mat=1)
    m.prop("decor", decor)
