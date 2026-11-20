"""Cross hub (canopy style): a square node under a stepped glass dome, an octagonal
port on all four sides. Attach M-P (A, south) . offers B (west), C (east),
D (north), M-P."""
from kit.module import C, box, mask

ID = "hub_x"
LAYOUT = """\
#d#
bLc
#a#"""
SEED = 79
BUDGET = 2600

H = 2.0
FACE = H - 1.0
PLAN = [(-H, -H), (H, -H), (H, H), (-H, H)]
DOME = [(0.55, 2.9), (1.15, 3.45), (1.6, 3.7)]


def build(m):
    hull = m.canopy_polygon(PLAN, roof=DOME, wall_top=2.2, spokes=True)
    for letter in "ABCD":
        m.port(letter, [hull], face=FACE, plate=2.0)

    m.light("main", 0.0, 0.0)
    m.mount("lantern", (0.0, 0.0, DOME[-1][1] + 0.01))
    m.cut_box(-H, H, -H, H, 6.0)

    def decor(mb):  # gold ring on the floor, amber lamp pad in the middle
        box(mb, (-H + 0.3, -0.35, 0.0), (H - 0.3, 0.35, 0.03), C["navy"], mask(0.2), mat=1)
        box(mb, (-0.35, -H + 0.3, 0.0), (0.35, H - 0.3, 0.03), C["navy"], mask(0.2), mat=1)
        box(mb, (-0.5, -0.5, 0.03), (0.5, 0.5, 0.05), C["amber"], mask(0.0, 0.7), mat=1)
    m.prop("decor", decor)
