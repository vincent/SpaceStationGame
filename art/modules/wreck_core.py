"""Wreck core (deck style, weathered): the abandoned station the castaway docks to.
An open-topped L-shaped deck: room A (the walkable layout) is a roofed cabin with a
rust roof; north of it the derelict wing lies open to space, its walls broken into
uneven teeth, rust panels inside, a banded tank, a cargo container, pipes and floor
hatches that glow when powered, a roofed shack with a mast, a docking tube elbow off
the west end and a few floating debris cubes.
Slots: A (+X, the capsule docks here), B and V (-X; V takes visitor ships), C (south,
next to the bay window W). Mounts: roof_a (shack roof: wreck_reactor), roof_b (wing
deck: wreck_radiator). Part: dish (wreck_dish upgrade, on the shack roof)."""
import math

from kit import core
from kit.module import C, box, mask

ID = "wreck_core"
LAYOUT = """\
######
vC..S#
b....a
##Wc##"""
SEED = 7
BUDGET = 15000

HX, HY = 4.3, 2.3                 # room A: room x -4..4, y -2..2 + 0.3 walls
T = 0.3
ZR = 3.1                          # room A wall top (under the roof slab)
WY0, WY1 = 3.7, 10.1              # west wing y range: kept north of 3.7 so a 9.2 m module fits on B
WX0 = -18.0                       # west end of the wing
DECK = -0.15                      # deck top (just under the game's floor tiles)
SHACK = (0.0, HX - T, 7.0, WY1 - T)   # shack room on the wing's NE corner (x0, x1, y0, y1)
SZ = 3.0                          # shack wall top
TANK = (-14.5, -10.0, 8.2, 1.0)   # tank x0, x1, y, radius


def build(m):
    rng = m.rng
    # ---------------------------------------------------------- deck + walls
    m.deck([(-HX, -HY), (HX, -HY), (HX, WY1), (WX0, WY1), (WX0, WY0), (-HX, WY0)], top=DECK,
           rects=[(-HX, -HY, HX, WY1), (WX0, WY0, -HX, WY1)])

    # room A: closed cabin (the cutaway opens it), outer line CCW, walls inside it
    south = m.wall((-HX, -HY), (HX, -HY), ZR, name="_wall_s")
    east = m.wall((HX, -HY + T), (HX, HY - T), ZR, name="_wall_e")
    north = m.wall((HX, HY), (-HX, HY), ZR, name="_wall_n")
    west = m.wall((-HX, HY - T), (-HX, -HY + T), ZR, name="_wall_w")
    m.piece(lambda mb: box(mb, (-HX - 0.1, -HY - 0.1, ZR - 0.1), (HX + 0.1, HY + 0.1, ZR + 0.15),
                           C["rust"], mask(0.5)), massing=False, name="_roof")
    m.doorway("A", east)
    m.doorway("B", west)
    m.doorway("V", west)
    m.doorway("C", south)
    m.hole(south, (-1.8, -HY - 0.3, 0.6), (-0.2, -HY + 0.6, 2.05))     # bay window W

    # wing: open to space, broken walls (lower towards the camera: south and east)
    m.wall((HX, HY), (HX, WY1 - T), [(2.2, 1.6), (3.4, 2.3), (4.6, 1.2), (8.0, SZ + 0.1)], name="_wall_we")
    m.wall((HX, WY1), (WX0, WY1), [(4.6, SZ + 0.1), (6.5, 2.6), (9.0, 3.2), (10.2, 1.5), (11.0, 0.7),
                                   (14.5, 2.9), (17.0, 2.4), (22.3, 3.0)], inner="ivory_old",
           name="_wall_wn")
    m.wall((WX0, WY1 - T), (WX0, WY0 + T), [(1.8, 2.8), (3.6, 2.2), (6.4, 2.7)], inner="ivory_old",
           name="_wall_ww")
    m.wall((WX0, WY0), (-HX, WY0), [(3.0, 1.7), (4.5, 1.0), (7.5, 1.9), (8.5, 0.8), (10.5, 1.6),
                                    (13.7, 2.2)], name="_wall_ws")
    m.wall((-HX, WY0 - 0.01), (-HX, HY), [(0.6, 1.5), (1.4, 0.9)], name="_wall_wc")
    m.wall((-9.0, WY1 - T), (-9.0, 6.6), [(1.2, 2.2), (2.2, 1.3), (3.2, 0.6)], t=0.25, name="_part")

    # shack on the wing: two walls (the wing walls close it), a door, a rust roof
    sx0, sx1, sy0, sy1 = SHACK
    shack_s = m.wall((sx0, sy0), (sx1, sy0), SZ + 0.1, name="_shack_s")
    m.wall((sx0, sy1), (sx0, sy0 + T), SZ + 0.1, name="_shack_w")
    m.hole(shack_s, (2.4, sy0 - 0.2, -0.01), (3.4, sy0 + 0.5, 2.1))
    m.piece(lambda mb: box(mb, (sx0 - 0.35, sy0 - 0.35, SZ), (HX + 0.1, WY1 + 0.3, SZ + 0.22),
                           C["rust"], mask(0.5)), massing=False, name="_shack_roof")

    # ---------------------------------------------------------- wing dressing (hull: always visible)
    def tank(mb):  # banded tank lying on cradles
        x0, x1, y, r = TANK
        mb.cyl(r, x1 - x0, ((x0 + x1) / 2, y, r + 0.05), (0, 90, 0), C["ivory"], mask(0.3), seg=8)
        for x, s in ((x0, -1), (x1, 1)):
            mb.cyl(r * 0.92, 0.5, (x + s * 0.2, y, r + 0.05), (0, 90, 0), C["ivory_old"], mask(0.3),
                   r2=r * 0.55 if s > 0 else r * 0.92, seg=8)
        for x in (x0 + 1.2, x1 - 1.2):
            core.prism_ring(mb, (x - 0.15, y, r + 0.05), (1, 0, 0), r + 0.08, r * 0.8, 0.3,
                            C["trim_gold"], mask(0.3))
            box(mb, (x - 0.5, y - r * 0.8, DECK - 0.05), (x + 0.5, y + r * 0.8, 0.45), C["navy"], mask(0.4))
    m.piece(tank, massing=False, name="_tank")

    def container(mb):  # cargo container with chamfered lid
        faces = core.wall_prism(mb, (-7.2, 5.2), (-3.4, 5.2),
                                [(0, DECK - 0.05), (3.8, DECK - 0.05), (3.8, 1.0), (3.3, 1.5), (0.5, 1.5),
                                 (0, 1.0)], 2.0)
        core.paint(mb, faces, C["rust"], mask(0.4))
        box(mb, (-7.0, 5.14, 0.2), (-6.6, 5.26, 0.95), C["rust_dk"], mask(0.4))
        box(mb, (-4.0, 5.14, 0.2), (-3.6, 5.26, 0.95), C["rust_dk"], mask(0.4))
    m.piece(container, massing=False, name="_container")

    def fittings(mb):  # pipes along the north wall, a gold handrail, crates, glowing floor hatches
        for z in (0.9, 1.35):
            core.beam(mb, (WX0 + 0.6, WY1 - T - 0.2, z), (-9.4, WY1 - T - 0.2, z), 0.16, C["steel_lt"],
                      mask(0.5))
        for x in (-16.0, -12.0):
            box(mb, (x - 0.1, WY1 - T - 0.35, 0.7), (x + 0.1, WY1 - T + 0.05, 1.5), C["navy"], mask(0.4))
        y = WY0 + 0.9
        core.beam(mb, (-8.3, y, 1.0), (-4.9, y, 1.0), 0.08, C["trim_gold"], mask(0.3))
        for x in (-8.3, -6.6, -4.9):
            core.beam(mb, (x, y, DECK), (x, y, 1.0), 0.08, C["trim_gold"], mask(0.3))
        for x, yy, s in ((-16.4, 5.0, 0.45), (-15.6, 4.8, 0.35), (1.0, 3.6, 0.4)):
            box(mb, (x - s, yy - s, DECK - 0.02), (x + s, yy + s, DECK + 2 * s), C["crate"], mask(0.6))
        for x, yy, w, h in ((-15.5, 7.0, 1.4, 0.9), (-8.0, 5.2, 1.0, 0.8), (-1.5, 5.5, 1.6, 0.9),
                            (2.5, 4.6, 1.0, 1.0)):
            box(mb, (x - w / 2, yy - h / 2, DECK - 0.05), (x + w / 2, yy + h / 2, DECK + 0.04), C["amber"],
                mask(0.0, 1.0))
    m.piece(fittings, massing=False, name="_fittings")

    # docking tube off the west end, elbowing down
    m.banded_tube([(WX0 - 0.1, 5.4, 1.1), (WX0 - 2.4, 5.4, 1.1), (WX0 - 2.4, 5.4, -3.2)], 0.75,
                  color="ivory", band="trim_gold", collar="navy")

    # ---------------------------------------------------------- outside: trims, portholes, wear
    m.porthole_at([((x, -HY, 1.45), (0, -1, 0)) for x in (-3.2, 3.2)]
                  + [((HX, 1.2, 1.45), (1, 0, 0))]
                  + [((x, WY0, 0.5), (0, -1, 0)) for x in (-16.5, -12.0, -6.0)])
    marks = []
    for x0, x1 in ((-HX + 0.4, -2.0), (2.0, HX - 0.4)):           # gold trim strips, room A south
        marks.append((((x0 + x1) / 2, -HY - 0.01, 2.35), (0, -1, 0), x1 - x0, 0.14, "gold_faded", mask(0.3)))
    marks.append(((HX + 0.01, 0.0, 2.35), (1, 0, 0), 3.4, 0.14, "gold_faded", mask(0.3)))
    for x in (-15.0, -9.5, -5.3):                                  # wing south wall
        marks.append(((x, WY0 - 0.01, 0.15), (0, -1, 0), 1.2, 0.12, "gold_faded", mask(0.3)))
    for x in (-16.0, -13.0, -6.5, -2.5):                          # rust panels inside the north wall
        marks.append(((x, WY1 - T - 0.01, 1.1), (0, -1, 0), 1.6, 1.1, "rust", mask(0.6)))
    marks.append(((WX0 + T + 0.01, 7.0, 1.1), (1, 0, 0), 1.8, 1.1, "rust", mask(0.6)))
    marks.append(((1.2, SHACK[2] - 0.01, 2.0), (0, -1, 0), 1.8, 0.5, "glass", mask(0.2)))   # shack window
    for _ in range(6):                                              # scorch and rust streaks
        x = rng.uniform(WX0 + 1.0, -5.0)
        marks.append(((x, WY0 - 0.01, rng.uniform(0.0, 0.5)), (0, -1, 0), rng.uniform(0.4, 1.0),
                      rng.uniform(0.2, 0.45), rng.choice(("scorch", "rust", "rust_dk")), mask(0.7)))
    m.decals(marks)

    def debris(mb):  # floating hull scraps
        for at, s, rot, col in (((WX0 - 1.5, WY1 + 1.5, 4.2), 0.35, (20, 30, 10), "trim_gold"),
                                ((-6.0, WY1 + 2.2, 5.0), 0.25, (10, -20, 35), "ivory"),
                                ((HX + 1.6, WY1 + 0.8, 4.4), 0.5, (0, 15, 25), "ivory_old"),
                                ((-12.0, WY1 + 1.0, 3.6), 0.3, (30, 0, -20), "rust")):
            mb.box([a - s for a in at], [a + s for a in at], C[col], mask(0.4), rot=rot)
    m.frame(debris)

    def mast(mb):  # cross mast on the shack roof
        x, y = 0.6, SHACK[3] - 0.4
        core.beam(mb, (x, y, SZ + 0.2), (x, y, SZ + 3.4), 0.18, C["steel_lt"], mask(0.3))
        core.beam(mb, (x - 0.9, y + 0.9, SZ + 2.6), (x + 0.9, y - 0.9, SZ + 2.6), 0.14, C["steel_lt"], mask(0.3))
    m.frame(mast)

    def dish(mb):  # the wreck_dish upgrade: a repaired dish on the shack roof
        cx, cy, cz = 2.0, SHACK[3] - 0.6, SZ + 0.22
        mb.cyl(0.1, 1.2, (cx, cy, cz + 0.6), (0, 0, 0), C["strut"], mask(0.2), seg=6)
        mb.cyl(1.0, 0.3, (cx, cy, cz + 1.3), (35, 0, 20), C["ivory"], mask(0.2), r2=0.2, seg=12)
        mb.cyl(0.08, 0.6, (cx, cy, cz + 1.55), (35, 0, 20), C["trim_gold"], mask(0.2), seg=6)
    m.part("dish", dish)

    m.mount("roof_a", (3.2, (SHACK[2] + SHACK[3]) / 2, SZ + 0.23))
    m.mount("roof_b", (-16.2, 8.2, DECK + 0.01))
    m.light("work", -1.5, 0.0)
    m.light("east", 2.5, -0.5)
    m.cut_box(-HX, HX, -HY - 0.6, HY - T - 0.02, 7.0)   # the back (north) wall stays whole

    def junk(mb):  # room A: crates and debris against the walls, a cable to the work lamp
        for x, y, s in ((-0.6, 1.55, 0.5), (0.1, 1.6, 0.4), (-0.25, 1.55, 0.35)):
            z0 = 0.0 if s > 0.36 else 0.5
            box(mb, (x - s, y - s * 0.8, z0), (x + s, y + s * 0.8, z0 + s), C["crate"], mask(0.6), mat=1)
        box(mb, (3.3, -1.8, 0.0), (3.85, -0.9, 0.3), C["steel"], mask(0.5), mat=1)
        mb.tube([(HX - 0.35, -1.0, 0.02), (1.0, -0.6, 0.02), (-1.2, 0.3, 0.02), (-1.5, 0.0, 1.8)], 0.035,
                C["neon"], mask(0.0, 0.3), mat=1)
        for x, y, a in ((1.7, 0.9, 30), (-2.4, -1.4, -50)):
            mb.box((x - 0.4, y - 0.15, 0.0), (x + 0.4, y + 0.15, 0.04), C["steel_lt"], mask(0.6), mat=1,
                   rot=(0, 0, a))
    m.prop("junk", junk)

    def lamp(mb):  # work lamp on a tripod (the "work" light)
        for k in range(3):
            a = math.radians(120 * k)
            core.beam(mb, (-1.5, 0.0, 1.8), (-1.5 + 0.5 * math.cos(a), 0.5 * math.sin(a), 0.0), 0.04,
                      C["steel_lt"], mask(0.3))
        mb.box((-1.75, -0.2, 1.75), (-1.25, 0.2, 2.05), C["neon"], mask(0.0, 0.9), mat=1)
    m.prop("lamp", lamp)
