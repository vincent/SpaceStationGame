"""Rescue capsule (canopy style, its own livery): the castaway's pod, an elongated
octagon with red walls under a glass dome on a white strut frame, an offwhite
stripe, amber octagonal portholes, the SR-7 hull name and glowing pads under the
keel. Docks to the wreck by its port A (-X end, the double doorway, a long tube).
Parts: antenna, thruster, solar_wings (capsule_* upgrades)."""
from kit import core
from kit.module import C, box, mask

ID = "capsule"
LAYOUT = """\
#####
aP.B#
a..K#
#####"""
SEED = 3
BUDGET = 6000

HX, HY = 4.0, 2.8                 # hull half extents (room x -3..3, y -2..2 inside)
CW, CE = 0.9, 1.3                 # plan chamfers: west (port end), east (engine end)
Z1 = 3.6                          # top of the dome
KT = 1.0                          # roof chamfer (wall top = Z1 - KT)
LIVERY = dict(wall="red", stripe="offwhite", glass="canopy", frame_color="strut")
PLAN = [(-HX + CW, -HY), (HX - CE, -HY), (HX, -HY + CE), (HX, HY - CE),
        (HX - CE, HY), (-HX + CW, HY), (-HX, HY - CW), (-HX, -HY + CW)]


def build(m):
    hull = m.canopy_polygon(PLAN, z1=Z1, kt=KT, **LIVERY)
    m.port("A", [hull], face=HX - 3.0, depth=0.9)

    # deck plate: fills the floor between the game's tiles and the walls
    m.piece(lambda mb: core.paint(mb, core.polygon_hull(mb, core.offset_polygon(PLAN, 0.32),
                                                        [(0.0, -0.4), (0.0, -0.03)]),
                                  C["deck"], mask(0.3)), massing=False, name="_floor")

    mid_e = ((HX - CE / 2, -HY + CE / 2), (HX - CE / 2, HY - CE / 2))
    m.porthole_at([((x, sy * HY, 0.42), (0, sy, 0)) for x in (-0.6, 1.6) for sy in (1, -1)]
                  + [((x, y, 0.42), (0.7071, 0.7071 if y > 0 else -0.7071, 0)) for x, y in mid_e], r=0.28)

    marks = []
    for sy in (1, -1):              # navy seam between the portholes, glowing pads under the keel
        marks.append(((0.5, sy * (HY + 0.01), 0.35), (0, sy, 0), 0.12, 0.9, "navy", mask(0.3)))
    m.decals(marks)

    def pads(mb):
        for x in (-2.4, 2.0):
            for sy in (1, -1):
                box(mb, (x - 0.45, sy * 1.6 - 0.15, -0.68), (x + 0.45, sy * 1.6 + 0.15, -0.58), C["amber"],
                    mask(0.0, 1.0))
    m.piece(pads, massing=False, name="_pads")
    # hull name (font meshes are not watertight: not part of the hull)
    m.frame(lambda mb: mb.text("SR-7", 0.5, (-2.3, -HY - 0.08, 0.42), (90, 0, 0), C["offwhite"], mask(0.2)))

    def antenna(mb):
        mb.cyl(0.06, 1.4, (1.0, -0.6, Z1 + 0.7), (0, 0, 0), C["offwhite"], mask(0.2), seg=6)
        mb.cyl(0.45, 0.15, (1.0, -0.6, Z1 + 1.4), (30, 0, -30), C["offwhite"], mask(0.2), r2=0.1, seg=10)
        mb.cyl(0.08, 0.08, (1.0, -0.6, Z1 + 1.45), (0, 0, 0), C["amber"], mask(0.0, 1.0), seg=6)
    m.part("antenna", antenna)

    def thruster(mb):  # engine bell on the east face
        z = 0.5
        mb.cyl(0.42, 0.4, (HX + 0.15, 0, z), (0, 90, 0), C["anthracite"], mask(0.3), seg=8)
        mb.cyl(0.45, 0.9, (HX + 0.75, 0, z), (0, 90, 0), C["steel"], mask(0.3), r2=0.62, seg=10)
        core.prism_ring(mb, (HX + 1.15, 0, z), (1, 0, 0), 0.7, 0.58, 0.1, C["red"], mask(0.3))
    m.part("thruster", thruster)

    def wings(mb):  # small solar wings off both side walls, between the portholes
        z, x = 0.45, 0.5
        for sy in (1, -1):
            y0, y1 = sorted((sy * (HY + 0.05), sy * (HY + 3.4)))
            core.beam(mb, (x, y0, z), (x, y1, z), 0.12, C["offwhite"], mask(0.3))
            ya, yb = sorted((sy * (HY + 0.6), sy * (HY + 3.4)))
            box(mb, (x - 1.4, ya, z - 0.03), (x + 1.4, yb, z + 0.03), C["solar"], mask(0.05, 0.0, 1.0))
            for xx in (x - 1.4, x + 1.4):
                box(mb, (xx - 0.05, ya, z - 0.05), (xx + 0.05, yb, z + 0.05), C["offwhite"], mask(0.3))
    m.part("solar_wings", wings)

    m.light("cabin", 0.0, 0.0)
    m.cut_box(-HX - 1.0, HX, -HY - 0.6, HY + 0.6, 6.0)

    def cabin(mb):  # wall screen, ration shelf, first-aid box
        yn, ys = HY - 0.3, -HY + 0.3     # inner wall faces
        box(mb, (-1.3, yn - 0.06, 1.0), (0.3, yn, 1.8), C["anthracite"], mask(0.2), mat=1)
        box(mb, (-1.2, yn - 0.07, 1.1), (0.2, yn - 0.06, 1.7), C["cyan"], mask(0.0, 0.8), mat=1)
        box(mb, (-0.4, ys, 0.9), (0.9, ys + 0.3, 0.98), C["offwhite"], mask(0.2), mat=1)
        for x in (-0.25, 0.15, 0.55):
            box(mb, (x - 0.12, ys + 0.05, 0.98), (x + 0.12, ys + 0.25, 1.25), C["amber"], mask(0.1), mat=1)
        box(mb, (-2.4, ys, 1.2), (-1.9, ys + 0.15, 1.6), C["offwhite"], mask(0.2), mat=1)
        box(mb, (-2.2, ys + 0.15, 1.33), (-2.1, ys + 0.16, 1.47), C["red"], mask(0.2), mat=1)
    m.prop("cabin", cabin)
