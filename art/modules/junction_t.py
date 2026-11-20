"""T-junction (canopy style): a small square glass-roofed node with three octagonal
ports (west, east, south) and portholes on its closed north wall. Attach M-P (A,
south) . offers B (west), C (east), M-P."""
from kit.module import C, box, mask

ID = "junction_t"
LAYOUT = """\
###
bLc
#a#"""
SEED = 71
BUDGET = 2200

H = 2.0                           # half side: room cell + FACE
FACE = H - 1.0
Z1 = 3.3
PLAN = [(-H, -H), (H, -H), (H, H), (-H, H)]


def build(m):
    hull = m.canopy_polygon(PLAN, z1=Z1, kt=1.0)
    for letter in "ABC":
        m.port(letter, [hull], face=FACE, plate=2.0)
    m.porthole_at([((x, H, 0.55), (0, 1, 0)) for x in (-0.8, 0.8)], r=0.3)

    m.light("main", 0.0, 0.0)
    m.mount("beacon", (0.0, 0.0, Z1 + 0.01))
    m.cut_box(-H, H, -H, H, 6.0)

    def decor(mb):  # gold floor cross, a wall locker on the closed side
        box(mb, (-H + 0.3, -0.35, 0.0), (H - 0.3, 0.35, 0.03), C["navy"], mask(0.2), mat=1)
        box(mb, (-0.35, -H + 0.3, 0.0), (0.35, 0.35, 0.03), C["navy"], mask(0.2), mat=1)
        box(mb, (-0.6, H - 0.75, 0.0), (0.6, H - 0.32, 0.9), C["ivory"], mask(0.2), mat=1)
        box(mb, (-0.5, H - 0.77, 0.65), (0.5, H - 0.75, 0.8), C["navy"], mask(0.2), mat=1)
    m.prop("decor", decor)
