"""Wreck core (weathered canopy style): the abandoned station the castaway docks to.
Room A (the walkable layout) is a small canopy room, its glass partly smashed; behind
it a neck leads to the long derelict wing (closed art): faded ivory walls, dark broken
panes, scorch and rust, a roof pod, a broken solar truss and a dead dish mount.
Slots: A (+X, the capsule docks here), B and V (-X; V takes visitor ships), C (south,
next to the bay window W). Doorways are old flush hatch collars, on the room walls.
Mounts: roof_a / roof_b (wing roof: wreck_reactor / wreck_radiator). Part: dish
(wreck_dish upgrade)."""
import math

from kit import core
from kit.module import C, GLASS_Z, box, mask

ID = "wreck_core"
LAYOUT = """\
######
vC..S#
b....a
##Wc##"""
SEED = 7
BUDGET = 15000

OLD = dict(wall="ivory_old", stripe="gold_faded", frame_color="strut_old")
HX, HY = 4.3, 2.3                 # room A: room x -4..4, y -2..2 + 0.3 walls
Z1 = 3.4
WING_Y = 6.9                      # wing axis (Blender y; Godot z = -6.9)
WING_HY = 3.2                     # wing y 3.7..10.1: a 9.2 m module on slot B clears it
WX0, WX1 = -18.0, 1.5
WZ1 = 4.4
POD = (-12.5, -5.5)               # roof pod on the wing
POD_Z = WZ1 - 0.7


def build(m):
    rng = m.rng
    room = m.canopy_tube(-HX, HX, HY, z1=Z1, kt=1.3, nose=(0.0, 0.0), ribs=(0.0,),
                         broken=0.35, **OLD)
    wing = m.canopy_tube(WX0, WX1, WING_HY, z1=WZ1, kt=1.5, nose=(1.6, 0.9), squeeze=(0.7, 0.85),
                         ribs=[WX0 + 4.0 * i for i in range(1, 5)], broken=0.5,
                         at=(0.0, WING_Y, 0.0), **OLD)
    m.canopy_tube(POD[0], POD[1], 1.7, z1=2.1, kt=0.8, nose=(0.6, 0.6), broken=0.4,
                  at=(0.0, WING_Y + 0.4, POD_Z), **OLD)

    def neck(mb):  # short closed tube from room A's north wall into the wing
        faces = core.polygon_hull(mb, [(-1.5, HY - 0.2), (1.5, HY - 0.2), (1.5, WING_Y - WING_HY + 0.3),
                                       (-1.5, WING_Y - WING_HY + 0.3)],
                                  [(0.3, -0.4), (0.0, -0.1), (0.0, 2.2), (0.5, 2.7)])
        core.paint(mb, faces, C["navy_faded"], mask(0.5))
    m.piece(neck, name="_neck")

    for letter in "ABCV":
        m.doorway(letter, room)
    m.hole(room, (-1.8, -HY - 0.3, 0.6), (-0.2, -HY + 0.6, 2.05))     # bay window W

    def damage(mb):  # torn gash in the wing, bent plates, scorch, rust streaks, patches
        sy = WING_Y - WING_HY
        box(mb, (-9.6, sy - 0.06, 0.1), (-7.2, sy + 0.02, 1.05), C["ink"], mask(0.6))
        for x, a in ((-9.4, 25), (-7.5, -35), (-8.4, 60)):
            mb.box((x - 0.05, sy - 0.25, 0.3), (x + 0.05, sy - 0.15, 1.3), C["strut_old"], mask(0.5),
                   rot=(a, 0, 0))
        mb.box((-11.2, sy - 0.18, -0.1), (-10.0, sy - 0.1, 0.9), C["ivory_old"], mask(0.7), rot=(0, 0, 18))
    m.piece(damage, massing=False, name="_damage")

    marks = []
    sy = WING_Y - WING_HY - 0.01
    for i in range(9):            # wing south wall: scorch and rust streaks
        x = rng.uniform(WX0 + 0.5, WX1 - 0.5)
        col = rng.choice(("scorch", "rust", "rust_dk"))
        marks.append(((x, sy, rng.uniform(0.0, 0.7)), (0, -1, 0), rng.uniform(0.5, 1.6),
                      rng.uniform(0.25, 0.8), col, mask(0.7)))
    for x in (-15.5, -4.2):      # patched hull plates
        marks.append(((x, sy, 0.45), (0, -1, 0), 1.2, 0.7, "steel_lt", mask(0.5)))
    for x in (-3.0, 2.6):        # room A south wall
        marks.append(((x, -HY - 0.01, 0.35), (0, -1, 0), 0.9, 0.35, "scorch", mask(0.7)))
    marks.append(((HX + 0.01, 1.2, 0.6), (1, 0, 0), 1.0, 0.4, "rust", mask(0.7)))
    m.decals(marks)

    # old portholes, some dark
    m.porthole_at([((x, WING_Y - WING_HY, 0.55), (0, -1, 0)) for x in (-16.5, -13.5, -5.5, -2.0)])

    def dock_rings(mb):  # decorative old docking rings on the wing's west nose and roof
        core.prism_ring(mb, (WX0 - 1.55, WING_Y, 1.4), (-1, 0, 0), 1.25, 0.95, 0.35, C["gold_faded"], mask(0.6))
        core.prism_ring(mb, (-2.5, WING_Y, WZ1 - 0.05), (0, 0, 1), 1.1, 0.8, 0.3, C["navy_faded"], mask(0.6))
    m.piece(dock_rings, massing=False, name="_rings")

    def truss(mb):  # broken solar truss off the wing's west end, one panel left, one torn
        y, z = WING_Y + 1.6, 3.2
        x0, x1 = WX0 - 0.6, WX0 - 9.0
        for dy, dz in ((-0.35, -0.35), (0.35, -0.35), (-0.35, 0.35), (0.35, 0.35)):
            core.beam(mb, (x0, y + dy, z + dz), (x1, y + dy, z + dz), 0.1, C["strut_old"], mask(0.5))
        for i in range(8):
            xa, xb = x0 - i * (x0 - x1) / 8, x0 - (i + 1) * (x0 - x1) / 8
            core.beam(mb, (xa, y - 0.35, z - 0.35), (xb, y + 0.35, z + 0.35), 0.07, C["strut_old"], mask(0.5))
        box(mb, (x1 + 0.5, y + 0.6, z - 0.04), (x1 + 4.5, y + 3.4, z + 0.02), C["solar"], mask(0.6, 0.0, 1.0))
        mb.box((x1 + 4.8, y + 0.5, z - 0.04), (x1 + 7.4, y + 2.4, z + 0.02), C["solar"], mask(0.6, 0.0, 1.0),
               rot=(0, 25, -12))
    m.frame(truss)

    def dish(mb):  # the wreck_dish upgrade: a repaired dish on the roof pod
        cx, cy, cz = -9.0, WING_Y + 0.4, POD_Z + 2.1
        mb.cyl(0.1, 1.2, (cx, cy, cz + 0.6), (0, 0, 0), C["strut"], mask(0.2), seg=6)
        mb.cyl(1.2, 0.35, (cx, cy, cz + 1.35), (35, 0, 20), C["ivory"], mask(0.2), r2=0.25, seg=12)
        mb.cyl(0.08, 0.6, (cx, cy, cz + 1.6), (35, 0, 20), C["trim_gold"], mask(0.2), seg=6)
    m.part("dish", dish)

    def antennas(mb):  # dead masts on the wing roof
        for x, h in ((-15.0, 2.2), (0.0, 1.5)):
            mb.cyl(0.06, h, (x, WING_Y - 1.2, WZ1 + h / 2), (0, 0, 0), C["strut_old"], mask(0.5), seg=6)
        mb.box((-15.4, WING_Y - 1.25, WZ1 + 1.7), (-14.6, WING_Y - 1.15, WZ1 + 1.75), C["strut_old"],
               mask(0.5), rot=(0, 20, 0))
    m.frame(antennas)

    m.mount("roof_a", (-2.0, WING_Y - 0.9, WZ1 + 0.01))
    m.mount("roof_b", (-16.0, WING_Y + 0.6, WZ1 + 0.01))
    m.light("work", -1.5, 0.0)
    m.light("east", 2.5, -0.5)
    m.cut_box(-HX, HX, -HY - 0.6, HY - 0.05, 7.0)

    def junk(mb):  # room A: crates and debris against the walls, a cable to the work lamp
        for x, y, s in ((-0.6, 1.55, 0.5), (0.1, 1.6, 0.4), (-0.25, 1.55, 0.35)):
            box(mb, (x - s, y - s * 0.8, 0.0 if s > 0.36 else 0.5), (x + s, y + s * 0.8, (0.0 if s > 0.36 else 0.5) + s),
                C["crate"], mask(0.6), mat=1)
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
    _ = GLASS_Z
