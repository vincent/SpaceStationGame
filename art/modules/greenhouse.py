"""Greenhouse (canopy style pilot, mockup 1000037489): a long faceted tube, ivory walls
under a glass canopy on a white strut frame, gold stripe, raised planter beds inside.
Attach M-P (A, -X end) . offers B (+X end, M-P). Mount: lamp_rack (roof)."""
from kit.module import C, box, mask

ID = "greenhouse"
LAYOUT = """\
##########
#GG.GG.GG#
a........b
a........b
#GG.GG.GG#
##########"""
SEED = 31

X0, X1 = -8.0, 8.0                # full section over the room (x -8..8)
Y1 = 4.3                          # room y -4..4 + 0.3 walls
Z1 = 3.4
NOSE = 1.0                        # chamfered ends beyond the room: hull face at the doors
BEDS = (-6.0, 0.0, 6.0)           # bed centres (x), two G cells each, rows y = +-3


def build(m):
    hull = m.canopy_tube(X0, X1, Y1, z1=Z1, nose=(NOSE, NOSE), squeeze=(0.72, 0.92),
                         ribs=(-8 / 3, 8 / 3))

    def side(mb):  # dark hatch panels, belly light strips, the leaf emblem
        for sy in (1, -1):
            y = sy * (Y1 + 0.03)
            for x in (-5.0, 5.0):
                box(mb, (x - 0.55, y - 0.04, 0.05), (x + 0.55, y + 0.04, 0.85), C["navy"], mask(0.2))
            for x in (-6.5, 3.5):
                box(mb, (x - 0.6, y - 0.04, -0.2), (x + 0.6, y + 0.04, -0.1), C["white"], mask(0.0, 1.0))
            for spin, col in ((30, "leaf"), (-30, "leaf_dk")):
                sx = 1 if spin > 0 else -1
                mb.box((-0.3, -0.05, 0.0), (0.3, 0.05, 1.1), C[col], mask(0.1),
                       rot=(0, spin, 0))
                for v in list(mb.bm.verts)[-8:]:
                    v.co.x += sx * 0.32
                    v.co.y += y
                    v.co.z += 0.0
            box(mb, (-0.05, y - 0.06, -0.1), (0.05, y + 0.06, 0.5), C["leaf_dk"], mask(0.1))
    m.piece(side, massing=False, name="_side")

    m.port("A", [hull], face=NOSE)
    m.port("B", [hull], face=NOSE)

    m.light("west", -4.0, 0.0)
    m.light("east", 4.0, 0.0)
    m.mount("lamp_rack", (0.0, 0.0, Z1 + 0.01))
    m.cut_box(X0, X1, -Y1 - 0.6, Y1 + 0.6, 7.0)

    def beds(mb):  # raised plinths under the planter troughs (G cells)
        for x in BEDS:
            for y in (3.0, -3.0):
                box(mb, (x - 1.9, y - 0.75, 0.0), (x + 1.9, y + 0.75, 0.3), C["ivory"], mask(0.2), mat=1)
                box(mb, (x - 1.75, y - 0.6, 0.3), (x + 1.75, y + 0.6, 0.34), C["soil"], mask(0.3), mat=1)
    m.prop("beds", beds)
