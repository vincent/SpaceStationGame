"""Docking adapter (canopy style): a flared glass-roofed collar that steps a standard
hatch up to a large one: narrow at the M port, wide at the L port (violet collar).
Attach M-P (A, north) . offers B (south, L-P)."""
from kit.module import C, box, mask

ID = "adapter_ml"
LAYOUT = """\
#a#
#L#
#b#"""
SEED = 83
BUDGET = 1800
SIZES = {"B": 3}

FACE = 1.0
HY = 1.0 + FACE
NARROW, WIDE = 1.95, 2.9          # half widths at the M and L ends
Z1 = 3.3
PLAN = [(-WIDE, -HY), (WIDE, -HY), (NARROW, HY), (-NARROW, HY)]


def build(m):
    hull = m.canopy_polygon(PLAN, z1=Z1, kt=1.0)
    m.port("A", [hull], face=FACE, plate=2.0)
    m.port("B", [hull], face=FACE)

    m.light("main", 0.0, 0.0)
    m.cut_box(-WIDE, WIDE, -HY, HY, 6.0)

    def decor(mb):  # floor runner widening towards the large hatch, hazard stripes
        box(mb, (-0.45, 0.0, 0.0), (0.45, HY - 0.3, 0.03), C["navy"], mask(0.2), mat=1)
        box(mb, (-1.2, -HY + 0.3, 0.0), (1.2, 0.0, 0.03), C["navy"], mask(0.2), mat=1)
        for x in (-1.0, -0.5, 0.0, 0.5, 1.0):
            box(mb, (x - 0.12, -HY + 0.35, 0.03), (x + 0.12, -HY + 0.75, 0.04), C["trim_gold"], mask(0.2), mat=1)
    m.prop("decor", decor)
