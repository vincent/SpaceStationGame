"""
build_crew_pod.py  -  low-poly "crew module" for a mobile space-station game.
Blender (tested 5.3) -> glTF 2.0 (.glb) -> Godot 4 Mobile.

Run (headless, re-runnable, wipes the scene first):
    blender -b --factory-startup -P build_crew_pod.py -- [output_dir]
Output dir defaults to the folder of this script. Produces:
    module_crew_pod.glb, module_crew_pod.blend, T_Palette.png,
    preview_oblique.png, preview_oblique_spec_z45.png, preview_wire.png, preview_uv.png,
    report.json

Game mode (Space Station Tycoon, docs/ART_PIPELINE.md conventions):
    blender -b --factory-startup -P build_crew_pod.py -- --game=<repo> [preview_dir]
Same design scaled 1.35x to the game's 2 m cells, re-origined on the layout centre,
hollow dock with a doorway, full glass roof (the cutaway opens it), kit_palette
colours, slot_A / prop_* / frame_roof / cut_box names, no pillar (a neighbour).
Writes <repo>/assets/models/modules/crew_pod.glb + art/modules/export/crew_pod.json
(then: tools/new_module.py crew_pod). Previews go to ./game/.

Axis notes (Blender is Z-up, glTF is Y-up; the exporter converts):
    Blender +X = glTF +X (dock axis points -X), Blender +Z = glTF +Y (up),
    Blender -Y = glTF +Z.  The porthole wall faces Blender -Y (= glTF +Z).
Everything is built procedurally as quads with explicit winding, per-face colour
swatch, wear/emissive mask and UV-island tag; UVs are exact unfoldings (zero stretch)
packed at one global texel density into a 256 px flat-colour atlas.
"""
import bpy, bmesh, math, os, sys, json, collections
import numpy as np
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
GAME = next((os.path.abspath(a.split('=', 1)[1]) for a in argv if a.startswith('--game=')), None)
_pos = [a for a in argv if not a.startswith('--')]
OUT = os.path.abspath(_pos[0]) if _pos else (os.path.join(HERE, 'game') if GAME else HERE)
os.makedirs(OUT, exist_ok=True)

# ----------------------------------------------------------------------------- palette
PAL = {  # sRGB hex
    'cream': 'D9D6CF', 'shade': 'A8A3A6', 'navy': '44506A', 'mustard': 'D4A24E',
    'terracotta': 'C8694F',
    'floor': '8E9AB8', 'console': 'C8694F', 'top': 'E6C98A', 'red': 'B84A48',
    'locker': 'B9B6BE', 'inavy': '44506A',
    'glow': 'FFD97A', 'screen': '7FD4FF', 'glass': 'A9A9CC',
}
def srgb(h): return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))
def _s2l(c): return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
def lin(h): return tuple(_s2l(c) for c in srgb(h))

C8 = 1.0 / math.cos(math.radians(22.5))      # apothem -> circumradius for octagons
VIEW = Vector((-0.6, -0.6, 0.5)).normalized()  # toward the preview camera: seams go opposite


# ----------------------------------------------------------------------------- mesh builder
class MB:
    """Quad mesh builder. Faces carry colour swatch, material, uv tag, wear and emissive mask."""
    def __init__(s, name, origin=(0, 0, 0)):
        s.name, s.origin = name, Vector(origin)
        s.V, s.vmap, s.F, s.shell = [], {}, [], 0

    def new_shell(s):  # separate dedupe namespace (closed sub-parts never share verts)
        s.shell += 1

    def v(s, p):
        p = Vector(p)
        k = (s.shell, round(p.x, 5), round(p.y, 5), round(p.z, 5))
        i = s.vmap.get(k)
        if i is None:
            i = len(s.V); s.V.append(p); s.vmap[k] = i
        return i

    def normal(s, vids):
        n = Vector((0, 0, 0)); m = len(vids)
        for i in range(m):
            a, b = s.V[vids[i]], s.V[vids[(i + 1) % m]]
            n.x += (a.y - b.y) * (a.z + b.z); n.y += (a.z - b.z) * (a.x + b.x); n.z += (a.x - b.x) * (a.y + b.y)
        return n

    def f(s, pts, col, mat='M_Hull', hint=None, tag=None, wear=0.0, emit=0.0):
        vids = [p if isinstance(p, int) else s.v(p) for p in pts]
        assert len(vids) == 4 and len(set(vids)) == 4, (s.name, pts)
        if hint is not None and s.normal(vids).dot(Vector(hint)) < 0:
            vids = vids[::-1]
        s.F.append(dict(v=vids, col=col, mat=mat, tag=tag, wear=wear, emit=emit))
        return len(s.F) - 1

    def extrude(s, fids, newpos, col, mat='M_Hull', tag=None, wear=0.0, emit=0.0):
        """Extrude a face region; side faces wound from the region's boundary edges."""
        cnt = collections.Counter()
        for fi in fids:
            vs = s.F[fi]['v']
            for i in range(4):
                cnt[frozenset((vs[i], vs[(i + 1) % 4]))] += 1
        bnd = []
        for fi in fids:
            vs = s.F[fi]['v']
            for i in range(4):
                a, b = vs[i], vs[(i + 1) % 4]
                if cnt[frozenset((a, b))] == 1:
                    bnd.append((a, b))
        nm = {}
        for fi in fids:
            for vi in s.F[fi]['v']:
                if vi not in nm:
                    nm[vi] = s.v(newpos(s.V[vi]))
        for fi in fids:
            s.F[fi]['v'] = [nm[x] for x in s.F[fi]['v']]
        out = []
        for a, b in bnd:
            s.F.append(dict(v=[a, b, nm[b], nm[a]], col=col, mat=mat, tag=tag, wear=wear, emit=emit))
            out.append(len(s.F) - 1)
        return out


def quad_ok(q, minlen=0.02, minsin=0.05):
    sgn = None; worst = 1.0
    for i in range(4):
        a, b, c = q[i], q[(i + 1) % 4], q[(i + 2) % 4]
        e1, e2 = b - a, c - b
        if e1.length < minlen: return None
        cr = e1.x * e2.y - e1.y * e2.x
        sn = abs(cr) / (e1.length * e2.length)
        if sn < minsin: return None
        if sgn is None: sgn = cr > 0
        elif (cr > 0) != sgn: return None
        worst = min(worst, sn)
    return worst


def fill_poly(mb, vids, hint, **attrs):
    """Quad-fill a convex planar polygon with an even vertex count (boundary may have
    collinear runs): a ring of quads to a strictly convex inner ellipse + a ladder."""
    N = len(vids); assert N % 2 == 0, N
    n = Vector(hint).normalized()
    up = Vector((0, 0, 1)) if abs(n.z) < 0.9 else Vector((0, 1, 0))
    vv = (up - n * up.dot(n)).normalized(); uu = vv.cross(n)
    P3 = [mb.V[i] for i in vids]; d = P3[0].dot(n)
    P2 = [Vector((p.dot(uu), p.dot(vv))) for p in P3]
    lo = Vector((min(p.x for p in P2), min(p.y for p in P2))); hi = Vector((max(p.x for p in P2), max(p.y for p in P2)))
    c, h = (lo + hi) / 2, (hi - lo) / 2
    area = sum(P2[i].x * P2[(i + 1) % N].y - P2[(i + 1) % N].x * P2[i].y for i in range(N))
    sg = 1 if area > 0 else -1
    L = [0.0]
    for i in range(1, N): L.append(L[-1] + (P2[i] - P2[i - 1]).length)
    tot = L[-1] + (P2[0] - P2[-1]).length
    th0 = math.atan2((P2[0].y - c.y) / h.y, (P2[0].x - c.x) / h.x)
    best = None
    for sc in (0.55, 0.5, 0.6, 0.45, 0.65, 0.4, 0.7):
        for bl in (0.5, 0.3, 0.7, 0.0, 1.0, 0.2, 0.8, 0.4, 0.6):
            for ph in (0.0, 0.05, -0.05, 0.1, -0.1):
                inner = []
                for i in range(N):
                    t = th0 + ph + sg * 2 * math.pi * (bl * i / N + (1 - bl) * L[i] / tot)
                    inner.append(Vector((c.x + sc * h.x * math.cos(t), c.y + sc * h.y * math.sin(t))))
                qs = [(P2[i], P2[(i + 1) % N], inner[(i + 1) % N], inner[i]) for i in range(N)]
                qs += [(inner[k], inner[k + 1], inner[N - k - 2], inner[N - k - 1]) for k in range(N // 2 - 1)]
                sc_ = [quad_ok(q) for q in qs]
                if None in sc_: continue
                score = min(sc_)
                if best is None or score > best[0]:
                    best = (score, inner)
    assert best, 'fill_poly failed'
    inner = [mb.v(uu * p.x + vv * p.y + n * d) for p in best[1]]
    for i in range(N):
        mb.f([vids[i], vids[(i + 1) % N], inner[(i + 1) % N], inner[i]], hint=n, **attrs)
    for k in range(N // 2 - 1):
        mb.f([inner[k], inner[k + 1], inner[N - k - 2], inner[N - k - 1]], hint=n, **attrs)


OCT_CAP = ((0, 1, 2, 3), (0, 3, 4, 7), (4, 5, 6, 7))


def lathe(mb, origin, axis, u, v, prof, segs, cap0=None, cap1=None, tagp='L'):
    """Octagonal surface of revolution. prof = [(s, apothem)], segs[i] = attrs for prof[i]->prof[i+1]
    (None = no faces). Flats face +-u / +-v. cap0/cap1 = attrs for the end caps (or None)."""
    mb.new_shell()
    origin, axis, u, v = Vector(origin), Vector(axis), Vector(u), Vector(v)
    dirs = [math.cos(math.radians(22.5 + 45 * k)) * u + math.sin(math.radians(22.5 + 45 * k)) * v for k in range(8)]
    R = [[mb.v(origin + axis * s_ + d * (r * C8)) for d in dirs] for (s_, r) in prof]
    for i, a in enumerate(segs):
        if a is None: continue
        (s0, r0), (s1, r1) = prof[i], prof[i + 1]
        ds, dr = s1 - s0, r1 - r0
        lip = abs(ds) < 1e-9
        for k in range(8):
            rad = (dirs[k] + dirs[(k + 1) % 8]).normalized()
            hint = axis * (-dr) + rad * ds
            mb.f([R[i][k], R[i][(k + 1) % 8], R[i + 1][(k + 1) % 8], R[i + 1][k]],
                 hint=hint, tag=None if (lip or abs(dr) > 1e-9) else f'{tagp}{i}', **a)
    for cap, ring, sgn in ((cap0, R[0], -1), (cap1, R[-1], 1)):
        if cap:
            for q in OCT_CAP:
                mb.f([ring[j] for j in q], hint=axis * sgn, **cap)
    return R


def prism(mb, base, z0, h, side, top, tops=((0, 1, 2, 3),), bottom=None, tag='P'):
    """Vertical prism from a CCW footprint (no bottom unless asked). Sides form one strip island."""
    mb.new_shell()
    n = len(base)
    B = [mb.v((x, y, z0)) for x, y in base]; T = [mb.v((x, y, z0 + h)) for x, y in base]
    for i in range(n):
        j = (i + 1) % n
        dx, dy = base[j][0] - base[i][0], base[j][1] - base[i][1]
        mb.f([B[i], B[j], T[j], T[i]], hint=(dy, -dx, 0), tag=tag, **side)
    for q in tops:
        mb.f([T[k] for k in q], hint=(0, 0, 1), **top)
    if bottom:
        for q in tops:
            mb.f([B[k] for k in q], hint=(0, 0, -1), **bottom)


def box(mb, x0, x1, y0, y1, z0, z1, side, top, bottom=None, tag='B'):
    prism(mb, [(x0, y0), (x1, y0), (x1, y1), (x0, y1)], z0, z1 - z0, side, top, bottom=bottom, tag=tag)


# ============================================================================= GEOMETRY
X0, X1, T = 0.5, 5.5, 0.25          # cabin span along X, wall thickness
PX, ZC, S, RO, RI = (2.9, 4.4), -0.36, 0.30, 0.28, 0.20   # portholes: centres, cell half, frame/pane circumradius
SB = RO * math.sin(math.radians(22.5))
SLOT = (3.625, 3.675)
LIGHTS = ((0.8, 1.22), (4.78, 5.2))
XB = sorted({X0, X1, *SLOT, *[a for l in LIGHTS for a in l],
             *[round(p + o, 5) for p in PX for o in (-S, -SB, SB, S)]})
XI = [X0 + T] + XB[1:-1] + [X1 - T]
RIM = lambda y: 0.4 + 0.15 * y      # tilted cutaway plane: z=0.1 at the front wall, 0.7 at the back wall
B_, C_ = Vector((-2, -0.7)), Vector((-1.5, -1.2))
cham = lambda t: tuple(B_ + (C_ - B_) * t)
PO = [(-2, 0.1), (-2, -0.02), (-2, -0.06), (-2, -0.66), (-2, -0.7), cham(0.35), cham(0.52),
      (-1.5, -1.2), (1.5, -1.2), (2, -0.7), (2, 0.0), (2, 0.7)]
# inner shell (offset 0.25 inward, top on the same tilted plane)
k_ = 2.7 - T * math.sqrt(2)
PI_ = [(-1.75, RIM(-1.75)), (-1.75, 1.75 - k_), (-(k_ - 0.95), -0.95), (k_ - 0.95, -0.95), (1.75, 1.75 - k_), (1.75, RIM(1.75))]
CEN = (0.0, -0.25)
# game mode: hollow dock (bore apothem 0.7, floor flush with the deck), shorter tube
DOCK_Z = -0.15 if GAME else 0.0
BORE = 0.7
TUBE_X0 = -0.03 if GAME else 0.0     # clear of the collar's navy lip
TUBE_L = 1.2 if GAME else 1.5


def build_hull():
    mb = MB('hull')
    A = dict
    cream = A(col='cream'); shade = A(col='shade', wear=0.55)
    trim, slot, lights = [], [], {0: [], 1: []}
    P3 = lambda x, yz: (x, yz[0], yz[1])
    # ---- outer strips
    for i in range(len(PO) - 1):
        p, q = PO[i], PO[i + 1]
        hint = (0, (p[0] + q[0]) / 2 - CEN[0], (p[1] + q[1]) / 2 - CEN[1])
        for j in range(len(XB) - 1):
            x0, x1 = XB[j], XB[j + 1]
            if i == 2 and any(px - S - 1e-6 <= x0 and x1 <= px + S + 1e-6 for px in PX):
                continue  # porthole cells are built below
            pts = [P3(x0, p), P3(x1, p), P3(x1, q), P3(x0, q)]
            if i == 0:
                trim.append(mb.f(pts, 'terracotta', hint=hint))
            elif i == 2 and (x0, x1) == SLOT:
                slot.append(mb.f(pts, 'navy', hint=hint, wear=0.5))
            elif i in (1, 2, 3, 9, 10):
                mb.f(pts, hint=hint, **cream)
            elif i == 5 and (x0, x1) in LIGHTS:
                lights[LIGHTS.index((x0, x1))].append(mb.f(pts, 'glow', 'M_Emissive', hint=hint, emit=1.0))
            else:
                mb.f(pts, hint=hint, **shade)
    # ---- porthole cells (flat-topped octagon, all-quad ring to the square cell)
    for n, px in enumerate(PX):
        Y = -2.0
        oc = lambda r, k: (px + r * math.cos(math.radians(22.5 + 45 * k)), Y, ZC + r * math.sin(math.radians(22.5 + 45 * k)))
        O = [mb.v(oc(RO, k)) for k in range(8)]; I = [mb.v(oc(RI, k)) for k in range(8)]
        c = lambda dx, dz: mb.v((px + dx, Y, ZC + dz))
        Ctr, Ctl, Cbl, Cbr = c(S, S), c(-S, S), c(-S, -S), c(S, -S)
        Tp, Tm, Bm, Bp = c(SB, S), c(-SB, S), c(-SB, -S), c(SB, -S)
        hint = (0, -1, 0)
        for quad in ((O[7], Cbr, Ctr, O[0]), (O[0], Ctr, Tp, O[1]), (O[1], Tp, Tm, O[2]), (O[2], Tm, Ctl, O[3]),
                     (O[3], Ctl, Cbl, O[4]), (O[4], Cbl, Bm, O[5]), (O[5], Bm, Bp, O[6]), (O[6], Bp, Cbr, O[7])):
            mb.f(list(quad), 'cream', hint=hint, wear=0.45)
        frame = [mb.f([O[k], O[(k + 1) % 8], I[(k + 1) % 8], I[k]], 'navy', hint=hint, wear=0.6) for k in range(8)]
        pane = [mb.f([I[j] for j in q], 'glow', 'M_Emissive', hint=hint, emit=1.0) for q in OCT_CAP]
        mb.extrude(frame + pane, lambda p: p + Vector((0, -0.03, 0)), 'navy', tag=f'pf{n}', wear=0.6)   # raised ring
        mb.extrude(pane, lambda p: p + Vector((0, 0.13, 0)), 'navy', tag=f'pr{n}', wear=0.6)            # 0.1 recess
    mb.extrude(slot, lambda p: p + Vector((0, 0.03, 0)), 'navy', tag='slot', wear=0.5)
    mb.extrude(trim, lambda p: p + Vector((0, -0.02, 0)), 'terracotta', wear=0.5)
    nch = Vector((0, -1, -1)).normalized() * 0.02
    for n in lights:
        mb.extrude(lights[n], lambda p: p + nch, 'glow', 'M_Emissive', tag=f'lb{n}', emit=1.0)
    # ---- end walls (outer), rims, inner shell
    for x, sgn in ((X0, -1), (X1, 1)):
        fill_poly(mb, [mb.v(P3(x, p)) for p in PO], (sgn, 0, 0), col='cream')
    up = (0, -0.15, 1)
    for (po, pi) in ((PO[0], PI_[0]), (PO[-1], PI_[-1])):
        for j in range(len(XB) - 1):
            mb.f([P3(XB[j], po), P3(XB[j + 1], po), P3(XI[j + 1], pi), P3(XI[j], pi)], 'cream', hint=up, wear=0.45)
    for x, xi in ((X0, X0 + T), (X1, X1 - T)):
        mb.f([P3(x, PO[0]), P3(x, PO[-1]), P3(xi, PI_[-1]), P3(xi, PI_[0])], 'cream', hint=up, wear=0.45)
    for i in range(len(PI_) - 1):
        p, q = PI_[i], PI_[i + 1]
        hint = (0, CEN[0] - (p[0] + q[0]) / 2, CEN[1] - (p[1] + q[1]) / 2)
        for j in range(len(XI) - 1):
            mb.f([P3(XI[j], p), P3(XI[j + 1], p), P3(XI[j + 1], q), P3(XI[j], q)], 'cream', hint=hint)
    for x, sgn in ((X0 + T, 1), (X1 - T, -1)):
        a, b, c, d, e, f = [P3(x, p) for p in PI_]
        mb.f([a, b, e, f], 'cream', hint=(sgn, 0, 0)); mb.f([b, c, d, e], 'cream', hint=(sgn, 0, 0))
    return mb


def build_porthole_glass():
    mb = MB('hull_porthole_glass')
    for px in PX:
        mb.new_shell()
        I = [mb.v((px + RI * math.cos(math.radians(22.5 + 45 * k)), -1.95, ZC + RI * math.sin(math.radians(22.5 + 45 * k)))) for k in range(8)]
        for q in OCT_CAP:
            mb.f([I[j] for j in q], 'glass', 'M_Glass', hint=(0, -1, 0))
    return mb


XM = 3.0
ARCH = [(-2, 0.1), (-2, 0.7), (-1.5, 1.2), (1.5, 1.2), (2, 0.7), (2, 0.6)]
RAILS = [((-2, 0.165), (0, -1)), ((-2, 0.7), (-0.924, 0.383)), ((-1.5, 1.2), (-0.383, 0.924)),
         ((1.5, 1.2), (0.383, 0.924)), ((2, 0.7), (0.924, 0.383))]
W = 0.06


def build_roof_frame():
    mb = MB('part_roof_frame', origin=(XM, 0, 0.4))
    for n, xc in enumerate((X0 + W, XM, X1 - W)):
        mb.new_shell()
        P = [Vector((0, y, z)) for y, z in ARCH]; m = len(P); X = Vector((1, 0, 0))
        sd = [(P[i + 1] - P[i]).normalized() for i in range(m - 1)]
        sn = [Vector((0, -d.z, d.y)) for d in sd]
        off = []
        for i in range(m):
            if i == 0: off.append(sn[0] * W)
            elif i == m - 1: off.append(sn[-1] * W)
            else:
                mm = (sn[i - 1] + sn[i]).normalized(); off.append(mm * (W / mm.dot(sn[i])))
        base = Vector((xc, 0, 0))
        Sx = [[mb.v(base + P[i] + off[i] - X * W), mb.v(base + P[i] + off[i] + X * W),
               mb.v(base + P[i] - off[i] + X * W), mb.v(base + P[i] - off[i] - X * W)] for i in range(m)]
        for i in range(m - 1):
            a, b = Sx[i], Sx[i + 1]
            mb.f([a[0], a[1], b[1], b[0]], 'cream', hint=sn[i], tag=f'arch{n}o')
            mb.f([a[1], a[2], b[2], b[1]], 'cream', hint=X)
            mb.f([a[2], a[3], b[3], b[2]], 'cream', hint=-sn[i], tag=f'arch{n}i')
            mb.f([a[3], a[0], b[0], b[3]], 'cream', hint=-X)
        mb.f(Sx[0], 'cream', hint=-sd[0], wear=0.4); mb.f(Sx[-1], 'cream', hint=sd[-1], wear=0.4)
    for r, ((y, z), nd) in enumerate(RAILS):
        for s, (xa, xb) in enumerate(((X0 + 2 * W, XM - W), (XM + W, X1 - 2 * W))):
            mb.new_shell()
            nn = Vector((0, nd[0], nd[1])).normalized(); mm = Vector((0, -nn.z, nn.y)); c = Vector((0, y, z))
            cs = [c + nn * W + mm * W, c - nn * W + mm * W, c - nn * W - mm * W, c + nn * W - mm * W]
            Aa = [mb.v(Vector((xa, 0, 0)) + q) for q in cs]; Bb = [mb.v(Vector((xb, 0, 0)) + q) for q in cs]
            for k in range(4):
                mid = (cs[k] + cs[(k + 1) % 4]) / 2 - c
                mb.f([Aa[k], Aa[(k + 1) % 4], Bb[(k + 1) % 4], Bb[k]], 'cream', hint=mid, tag=f'rail{r}{s}')
            mb.f(Aa, 'cream', hint=(-1, 0, 0), wear=0.4); mb.f(Bb, 'cream', hint=(1, 0, 0), wear=0.4)
    return mb


def build_canopy():
    mb = MB('part_canopy', origin=(XM, 0, 0.4))
    g = dict(col='glass', mat='M_Glass')
    prof = ARCH[:5]
    for xa, xb in ((X0 + 2 * W, XM - W), (XM + W, X1 - 2 * W)):
        for i in ((0, 1, 2, 3) if GAME else (3,)):   # spec: back roof chamfer bay only (front wall, front chamfer and roof stay open: cutaway)
            (y0, z0), (y1, z1) = prof[i], prof[i + 1]
            hint = (0, (y0 + y1) / 2, (z0 + z1) / 2 - 0.1)
            mb.f([(xa, y0, z0), (xb, y0, z0), (xb, y1, z1), (xa, y1, z1)], hint=hint, **g)
    for x, sgn in ((X0 + W, -1), (X1 - W, 1)):
        P = lambda y, z: (x, y, z)
        M = P(0.0, RIM(0.0))
        mb.f([P(-2, 0.1), M, P(-1.5, 1.2), P(-2, 0.7)], hint=(sgn, 0, 0), **g)
        mb.f([M, P(2, 0.7), P(1.5, 1.2), P(-1.5, 1.2)], hint=(sgn, 0, 0), **g)
    return mb


def build_collar():
    mb = MB('part_collar', origin=(X0, 0, 0))
    cr, mu, nv = dict(col='cream'), dict(col='mustard'), dict(col='navy', wear=0.5)
    lip = lambda c: dict(col=c, wear=0.5)
    prof = [(0, 1.4), (0.14, 1.4), (0.14, 1.44), (0.30, 1.44), (0.30, 1.4), (0.42, 1.4), (0.5, 1.32),
            (0.5, 1.0), (0.53, 1.0), (0.53, 0.82), (0.5, 0.82)]
    segs = [cr, lip('mustard'), mu, lip('mustard'), cr, dict(col='cream', wear=0.55), cr, nv, nv, nv]
    caps = dict(cap0=cr, cap1=cr)
    if GAME:   # hollow ring: navy bore back to the hull face, closed loop profile
        prof = prof[:10] + [(0.53, BORE), (0.0, BORE), (0.0, 1.4)]
        segs = segs[:9] + [nv, nv, cr]; caps = {}
    mb.origin = Vector((X0, 0, DOCK_Z))
    lathe(mb, (X0, 0, DOCK_Z), (-1, 0, 0), (0, 1, 0), (0, 0, 1), prof, segs, tagp='col', **caps)
    return mb


def build_tube():
    mb = MB('part_dock_tube', origin=(0, 0, 0))
    cr = dict(col='cream'); nv = dict(col='navy', wear=0.5); mu = dict(col='mustard', wear=0.3)
    prof = [(0, 0.7), (0.575, 0.7), (0.575, 0.85), (0.925, 0.85), (0.925, 0.7), (1.2, 0.7), (1.2, 0.74),
            (1.35, 0.74), (1.35, 0.7), (1.5, 0.7)]
    segs = [cr, nv, nv, nv, cr, mu, mu, mu, cr]
    caps = dict(cap0=cr, cap1=cr)
    if GAME:   # walkable: 1.6 m across, hollow, shorter so the door point stays on the layout
        f = TUBE_L / 1.5
        prof = [(s_ * f, r + 0.1) for s_, r in prof] + [(TUBE_L, BORE), (0.0, BORE), (0.0, 0.8)]
        segs = segs + [cr, nv, cr]; caps = {}
    mb.origin = Vector((TUBE_X0, 0, DOCK_Z))
    lathe(mb, (TUBE_X0, 0, DOCK_Z), (-1, 0, 0), (0, 1, 0), (0, 0, 1), prof, segs, tagp='tube', **caps)
    return mb


PIL_X, PIL_TOP, PIL_H, PIL_R = -1.5 - 0.8, 0.85, 5.0, 0.8


def build_pillar():
    mb = MB('part_pillar', origin=(-1.5, 0, 0))
    cr = dict(col='cream'); mu = dict(col='mustard', wear=0.3); nv = dict(col='navy', wear=0.5)
    r, rb = PIL_R, PIL_R + 0.03
    prof = [(0, r), (1.9, r), (1.9, rb), (2.1, rb), (2.1, r), (3.9, r), (3.9, rb), (4.4, rb), (4.4, r), (5.0, r)]
    segs = [cr, mu, mu, mu, cr, nv, nv, nv, cr]
    lathe(mb, (PIL_X, 0, PIL_TOP), (0, 0, -1), (1, 0, 0), (0, 1, 0), prof, segs,
          cap0=cr, cap1=dict(col='cream', wear=0.6), tagp='pil')
    return mb


ZF = -0.85   # deck top


def build_interior():
    out = []
    I = 'M_Interior'
    def side(c, w=0.0): return dict(col=c, mat=I, wear=w)
    mb = MB('interior_floor_deck', origin=(3.0, 0, ZF)); mb.new_shell()
    mb.f([(0.75, -1.48, ZF), (5.25, -1.48, ZF), (5.25, 1.48, ZF), (0.75, 1.48, ZF)], hint=(0, 0, 1), **side('floor'))
    for y in (-1.48, 1.48):
        mb.f([(0.75, y, ZF - 0.1), (5.25, y, ZF - 0.1), (5.25, y, ZF), (0.75, y, ZF)], hint=(0, y, 0), **side('floor', 0.4))
    out.append(mb)
    mb = MB('interior_console_bench', origin=(1.0, 1.15, ZF))
    L = [(1.0, -0.1), (1.75, -0.1), (1.75, 0.85), (2.6, 0.85), (2.6, 1.45), (1.75, 1.45), (1.0, 1.45), (1.0, 0.85)]
    prism(mb, L, ZF, 0.55, side('console'), side('top'), tops=((0, 1, 2, 7), (7, 2, 5, 6), (2, 3, 4, 5)))
    out.append(mb)
    mb = MB('interior_console_counter', origin=(2.15, -1.2, ZF))
    box(mb, 1.0, 3.3, -1.45, -0.95, ZF, ZF + 0.9, side('console'), side('top')); out.append(mb)
    for nm, (x0, x1, y0, y1) in (('a', (2.0, 3.2, -0.25, 0.45)), ('b', (3.6, 4.25, 0.85, 1.45))):
        mb = MB(f'interior_table_{nm}', origin=((x0 + x1) / 2, (y0 + y1) / 2, ZF))
        box(mb, x0, x1, y0, y1, ZF + 0.46, ZF + 0.52, side('top'), side('top'), bottom=side('top'))
        for lx in (x0 + 0.1, x1 - 0.2):
            prism(mb, [(lx, y0 + 0.1), (lx + 0.1, y0 + 0.1), (lx + 0.1, y1 - 0.1), (lx, y1 - 0.1)], ZF, 0.46,
                  side('inavy'), side('inavy'), tops=(), tag='leg')
        out.append(mb)
    mb = MB('interior_tank', origin=(3.05, 1.0, ZF))
    lathe(mb, (3.05, 1.0, ZF), (0, 0, 1), (1, 0, 0), (0, 1, 0), [(0, 0.4), (0.7, 0.4)], [side('console')],
          cap1=side('console', 0.3), tagp='tank'); out.append(mb)
    mb = MB('interior_canisters', origin=(4.77, -1.2, ZF))
    for cx in (4.55, 4.98):
        lathe(mb, (cx, -1.2, ZF), (0, 0, 1), (1, 0, 0), (0, 1, 0), [(0, 0.2), (1.0, 0.2)], [side('red')],
              cap1=side('locker', 0.3), tagp=f'can{cx}')
    out.append(mb)
    mb = MB('interior_locker', origin=(4.8, 1.0, ZF))
    box(mb, 4.4, 5.2, 0.6, 1.4, ZF, ZF + 2.0, side('locker'), side('locker', 0.3)); out.append(mb)
    mb = MB('interior_crate', origin=(3.85, -1.1, ZF))
    box(mb, 3.5, 4.2, -1.4, -0.8, ZF, ZF + 0.6, side('locker'), side('locker', 0.3)); out.append(mb)
    mb = MB('interior_screen', origin=(2.0, -1.2, ZF + 0.9))
    box(mb, 1.6, 2.4, -1.4, -1.0, ZF + 0.9, ZF + 0.92, dict(col='screen', mat='M_Emissive', emit=1.0),
        dict(col='screen', mat='M_Emissive', emit=1.0)); out.append(mb)
    return out


def build_helpers():
    col = MB('hull_col')
    pr = [(-2, -0.7), (-1.5, -1.2), (1.5, -1.2), (2, -0.7), (2, 0.7), (1.5, 1.2), (-1.5, 1.2), (-2, 0.7)]
    A = [col.v((X0, y, z)) for y, z in pr]; Bv = [col.v((X1, y, z)) for y, z in pr]
    for k in range(8):
        (y0, z0), (y1, z1) = pr[k], pr[(k + 1) % 8]
        col.f([A[k], A[(k + 1) % 8], Bv[(k + 1) % 8], Bv[k]], 'cream', hint=(0, (y0 + y1) / 2, (z0 + z1) / 2))
    for q in OCT_CAP:
        col.f([A[j] for j in q], 'cream', hint=(-1, 0, 0)); col.f([Bv[j] for j in q], 'cream', hint=(1, 0, 0))
    nav = MB('hull_nav')
    nav.f([(0.8, -1.4, ZF), (5.2, -1.4, ZF), (5.2, 1.4, ZF), (0.8, 1.4, ZF)], 'floor', hint=(0, 0, 1))
    return col, nav


# ============================================================================= UV UNFOLD
def unfold(mb):
    """Islands = edge-connected faces with same swatch+material and (same tag, or untagged & coplanar).
    Each island is unfolded by hinge rotation from a root face (exact, zero stretch)."""
    nF = len(mb.F)
    N = [mb.normal(F['v']).normalized() for F in mb.F]
    D = [N[i].dot(mb.V[mb.F[i]['v'][0]]) for i in range(nF)]
    ef = collections.defaultdict(list)
    for fi, F in enumerate(mb.F):
        vs = F['v']
        for i in range(4):
            ef[tuple(sorted((vs[i], vs[(i + 1) % 4])))].append(fi)

    def same(f, g):
        A, B = mb.F[f], mb.F[g]
        if A['col'] != B['col'] or A['mat'] != B['mat']: return False
        if A['tag'] or B['tag']: return A['tag'] == B['tag']
        return N[f].dot(N[g]) > 0.99999 and abs(D[f] - D[g]) < 1e-4

    adj = [[] for _ in range(nF)]
    for e, fs in ef.items():
        if len(fs) == 2 and same(*fs):
            adj[fs[0]].append((fs[1], e)); adj[fs[1]].append((fs[0], e))
    seen = [False] * nF; islands = []; uv = [None] * nF; isl_of = [0] * nF
    for f0 in range(nF):
        if seen[f0]: continue
        comp, st = [], [f0]; seen[f0] = True
        while st:
            f = st.pop(); comp.append(f)
            for g, _ in adj[f]:
                if not seen[g]: seen[g] = True; st.append(g)
        root = max(comp, key=lambda f: N[f].dot(VIEW)) if mb.F[f0]['tag'] else min(comp)
        n = N[root]
        up = Vector((0, 0, 1)) if abs(n.z) < 0.95 else Vector((0, 1, 0))
        vv = (up - n * up.dot(n)).normalized(); uu = vv.cross(n)
        uv[root] = {vi: Vector((mb.V[vi].dot(uu), mb.V[vi].dot(vv))) for vi in mb.F[root]['v']}
        dq = collections.deque([root]); done = {root}
        while dq:
            f = dq.popleft()
            for g, (a, b) in adj[f]:
                if g in done: continue
                A2, B2 = uv[f][a], uv[f][b]
                a3, b3 = mb.V[a], mb.V[b]
                e3 = (b3 - a3).normalized(); p3 = N[g].cross(e3)
                e2 = (B2 - A2).normalized(); p2 = Vector((-e2.y, e2.x))
                uv[g] = {vi: A2 + e2 * (mb.V[vi] - a3).dot(e3) + p2 * (mb.V[vi] - a3).dot(p3) for vi in mb.F[g]['v']}
                done.add(g); dq.append(g)
        for f in comp: isl_of[f] = len(islands)
        pts = [p for f in comp for p in uv[f].values()]
        lo = Vector((min(p.x for p in pts), min(p.y for p in pts))); hi = Vector((max(p.x for p in pts), max(p.y for p in pts)))
        islands.append(dict(faces=comp, lo=lo, w=hi.x - lo.x, h=hi.y - lo.y, col=mb.F[f0]['col'], mb=mb))
    # seams = UV discontinuities; hard = normal change
    seams, hard = set(), set()
    for e, fs in ef.items():
        if len(fs) != 2:
            seams.add(e); hard.add(e); continue
        f, g = fs
        if N[f].dot(N[g]) < 0.99995: hard.add(e)
        if isl_of[f] != isl_of[g] or any((uv[f][x] - uv[g][x]).length > 1e-5 for x in e):
            seams.add(e)
    mb.uv, mb.N, mb.ef, mb.seams, mb.hard, mb.isl_of = uv, N, ef, seams, hard, isl_of
    return islands


def pack(islands, size=256, pad=3):
    order = sorted(range(len(islands)), key=lambda i: (-islands[i]['h'], -islands[i]['w']))
    def attempt(k):
        x = y = pad; rowh = 0; pos = {}
        for i in order:
            w, h = islands[i]['w'] * k, islands[i]['h'] * k
            if x + w + pad > size:
                y += math.ceil(rowh) + pad; x = pad; rowh = 0
            if x + w + pad > size: return None
            pos[i] = (x, y); x += math.ceil(max(w, 1e-6)) + pad; rowh = max(rowh, h)
        return pos if y + math.ceil(rowh) + pad <= size else None
    lo, hi = 1.0, 400.0
    for _ in range(50):
        mid = (lo + hi) / 2
        if attempt(mid): lo = mid
        else: hi = mid
    return lo, attempt(lo)


# ============================================================================= BLENDER
def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.unit_settings.system = 'METRIC'; sc.unit_settings.scale_length = 1.0
    return sc


def make_materials(img):
    mats = {}
    def base(name):
        m = bpy.data.materials.new(name); m.use_nodes = True
        bs = m.node_tree.nodes.get('Principled BSDF')
        bs.inputs['Roughness'].default_value = 0.9; bs.inputs['Metallic'].default_value = 0.0
        m.use_backface_culling = True
        return m, bs
    for name in ('M_Hull', 'M_Interior', 'M_Emissive'):
        m, bs = base(name)
        tx = m.node_tree.nodes.new('ShaderNodeTexImage'); tx.image = img; tx.interpolation = 'Closest'
        tx.location = (-400, 200)
        m.node_tree.links.new(tx.outputs['Color'], bs.inputs['Base Color'])
        if name == 'M_Emissive':
            m.node_tree.links.new(tx.outputs['Color'], bs.inputs['Emission Color'])
            bs.inputs['Emission Strength'].default_value = 2.0
        mats[name] = m
    m, bs = base('M_Glass')
    bs.inputs['Base Color'].default_value = (*lin(PAL['glass']), 1.0)
    bs.inputs['Alpha'].default_value = 0.35
    if hasattr(m, 'surface_render_method'): m.surface_render_method = 'BLENDED'
    if hasattr(m, 'blend_method'): m.blend_method = 'BLEND'
    mats['M_Glass'] = m
    return mats


def to_object(mb, coll, mats, size, k, place, with_uv=True):
    used = sorted({vi for F in mb.F for vi in F['v']})
    remap = {o: i for i, o in enumerate(used)}
    me = bpy.data.meshes.new(mb.name)
    me.from_pydata([tuple(mb.V[o] - mb.origin) for o in used], [], [[remap[x] for x in F['v']] for F in mb.F])
    me.update()
    ob = bpy.data.objects.new(mb.name, me); ob.location = mb.origin; coll.objects.link(ob)
    slots = []
    for F in mb.F:
        if F['mat'] not in slots: slots.append(F['mat'])
    if with_uv:
        for s in slots: me.materials.append(mats[s])
        me.polygons.foreach_set('material_index', [slots.index(F['mat']) for F in mb.F])
    me.polygons.foreach_set('use_smooth', [False] * len(mb.F))
    # corner data
    ca = me.color_attributes.new(name='Color', type='FLOAT_COLOR', domain='CORNER')
    cols, uvs = [], []
    for fi, F in enumerate(mb.F):
        for vi in F['v']:
            cols += [F['wear'], F['emit'], 0.0, 1.0]
            if with_uv:
                x0, y0, isl = place[(id(mb), mb.isl_of[fi])]
                p = mb.uv[fi][vi] - isl['lo']
                uvs += [(x0 + p.x * k) / size, (y0 + p.y * k) / size]
    ca.data.foreach_set('color', cols)
    me.color_attributes.active_color = ca
    try: me.color_attributes.render_color_index = me.color_attributes.active_color_index
    except Exception: pass
    if with_uv:
        ul = me.uv_layers.new(name='UVMap')
        ul.uv.foreach_set('vector', uvs)
    for e in me.edges:
        key = tuple(sorted((used[e.vertices[0]], used[e.vertices[1]])))
        e.use_edge_sharp = key in mb.hard
        e.use_seam = with_uv and key in mb.seams
    me.validate(); me.update()
    return ob


def hygiene(ob, closed_expected, ref_center):
    me = ob.data; bm = bmesh.new(); bm.from_mesh(me)
    ref_center = ref_center - ob.location      # mesh data is in object-local space
    r = dict(tris=sum(len(f.verts) - 2 for f in bm.faces), faces=len(bm.faces),
             ngons=sum(len(f.verts) > 4 for f in bm.faces), tri_faces=sum(len(f.verts) == 3 for f in bm.faces))
    r['boundary_edges'] = sum(e.is_boundary for e in bm.edges)
    r['multi_face_edges'] = sum(len(e.link_faces) > 2 for e in bm.edges)
    r['wire_edges'] = sum(e.is_wire for e in bm.edges)
    r['loose_verts'] = sum(len(v.link_edges) == 0 for v in bm.verts)
    r['non_contiguous_edges'] = sum((len(e.link_faces) == 2 and not e.is_contiguous) for e in bm.edges)
    r['non_manifold'] = r['boundary_edges'] + r['multi_face_edges'] + r['wire_edges'] + r['non_contiguous_edges'] + sum(
        (not v.is_manifold) for v in bm.verts if v.link_faces)
    keys = collections.Counter(frozenset(v.index for v in f.verts) for f in bm.faces)
    r['doubled_faces'] = sum(c - 1 for c in keys.values() if c > 1)
    r['min_edge_m'] = round(min(e.calc_length() for e in bm.edges), 4)
    # near-duplicate verts (what Merge-by-Distance 0.0001 would merge)
    co = np.array([v.co[:] for v in bm.verts]); q = np.round(co / 1e-4).astype(np.int64)
    r['merge_by_distance_candidates'] = int(len(q) - len(np.unique(q, axis=0)))
    # flipped faces: closed shells -> negative volume; open shells -> normal vs shell/ref centre
    flipped = 0; shells = 0; seen = set()
    for f in bm.faces:
        if f.index in seen: continue
        comp, st = [], [f]; seen.add(f.index)
        while st:
            g = st.pop(); comp.append(g)
            for e in g.edges:
                for h in e.link_faces:
                    if h.index not in seen: seen.add(h.index); st.append(h)
        shells += 1
        closed = all(not e.is_boundary for g in comp for e in g.edges)
        if closed:
            vol = sum(g.calc_center_median().dot(g.normal) * g.calc_area() for g in comp) / 3
            if vol < 0: flipped += len(comp)
        else:
            vs = [v.co for g in comp for v in g.verts]
            c = (Vector(np.min(vs, 0)) + Vector(np.max(vs, 0))) / 2
            vote = sum(g.normal.dot(g.calc_center_median() - c) * g.calc_area() for g in comp)
            if abs(vote) < 1e-3 * sum(g.calc_area() for g in comp):
                vote = sum(g.normal.dot(g.calc_center_median() - ref_center) * g.calc_area() for g in comp)
            if vote < 0: flipped += len(comp)
    r['shells'] = shells; r['flipped_faces'] = int(flipped) + r['non_contiguous_edges']
    r['watertight'] = (r['non_manifold'] == 0)
    bm.free()
    r['seams'] = sum(e.use_seam for e in me.edges); r['sharp_edges'] = sum(e.use_edge_sharp for e in me.edges)
    return r


def uv_checks(ob, k, size):
    me = ob.data
    if not me.uv_layers: return {}
    uv = np.zeros(len(me.loops) * 2); me.uv_layers[0].uv.foreach_get('vector', uv); uv = uv.reshape(-1, 2)
    worst = 0.0
    for p in me.polygons:
        ls = list(p.loop_indices)
        for i in range(len(ls)):
            a, b = ls[i], ls[(i + 1) % len(ls)]
            l3 = (me.vertices[me.loops[a].vertex_index].co - me.vertices[me.loops[b].vertex_index].co).length
            l2 = np.linalg.norm(uv[a] - uv[b]) * size / k
            worst = max(worst, abs(l2 - l3))
    return dict(uv_min=round(float(uv.min()), 4), uv_max=round(float(uv.max()), 4), max_edge_stretch_m=round(worst, 6))


def empty(coll, name, loc, rot=(0, 0, 0), size=0.4, props=None):
    e = bpy.data.objects.new(name, None); e.empty_display_type = 'ARROWS'; e.empty_display_size = size
    e.location = loc; e.rotation_euler = [math.radians(a) for a in rot]; e.hide_render = True
    for kk, vv in (props or {}).items(): e[kk] = vv
    coll.objects.link(e); return e


# ============================================================================= MAIN
def main():
    sc = reset_scene()
    coll = bpy.data.collections.new('MODULE_CrewPod'); sc.collection.children.link(coll)
    textured = [build_hull(), build_porthole_glass(), build_roof_frame(), build_canopy(), build_collar(),
                build_tube(), build_pillar(), *build_interior()]
    helpers = build_helpers()
    islands = []
    for mb in textured: islands += unfold(mb)
    for mb in helpers: unfold(mb)
    SIZE = 256
    k, pos = pack(islands, SIZE, pad=3)
    place = {}
    px = np.zeros((SIZE, SIZE, 4), dtype=np.float32); px[:, :] = (0.5, 0.5, 0.5, 1.0)
    count = collections.Counter()
    for i, isl in enumerate(islands):
        mb = isl['mb']; idx = count[id(mb)]; count[id(mb)] += 1
        x0, y0 = pos[i]
        place[(id(mb), idx)] = (x0, y0, isl)
        xa, xb = max(0, x0 - 1), min(SIZE, math.ceil(x0 + isl['w'] * k) + 1)
        ya, yb = max(0, y0 - 1), min(SIZE, math.ceil(y0 + isl['h'] * k) + 1)
        px[ya:yb, xa:xb, :3] = srgb(PAL[isl['col']])
    img = bpy.data.images.new('T_Palette', SIZE, SIZE, alpha=False)
    img.pixels.foreach_set(px.ravel())
    img.filepath_raw = os.path.join(OUT, 'T_Palette.png'); img.file_format = 'PNG'; img.save()
    img.filepath = img.filepath_raw
    mats = make_materials(img)
    objs = {}
    for mb in textured:
        objs[mb.name] = to_object(mb, coll, mats, SIZE, k, place)
    for mb in helpers:
        ob = to_object(mb, coll, mats, SIZE, k, place, with_uv=False)
        ob.hide_render = True; ob.display_type = 'WIRE'; ob['helper'] = 'collision' if mb.name == 'hull_col' else 'navmesh'
        objs[mb.name] = ob
    for nm, d in (('part_collar', (-1, 0, 0)), ('part_dock_tube', (-1, 0, 0)), ('part_pillar', (0, -1, 0)),
                  ('part_roof_frame', (0, 1, 0)), ('part_canopy', (0, 1, 0))):
        objs[nm]['explode_dir'] = [float(c) for c in d]     # glTF (Y-up) axes, exported as node extras
    # slots / helpers (empties).  Blender local +Y -> glTF local -Z (Godot forward)
    empty(coll, 'slot_dock_main', (0, 0, 0), (0, 0, 90), props={'slot': 'dock_main', 'facing_gltf': [-1.0, 0.0, 0.0]})
    empty(coll, 'slot_pillar_bottom', (PIL_X, 0, PIL_TOP - PIL_H), (-90, 0, 0), props={'slot': 'pillar_bottom', 'facing_gltf': [0.0, -1.0, 0.0]})
    empty(coll, 'light_cabin', (3.0, 0, ZF + 1.8), props={'light': 'omni', 'color': '#FFD97A'})
    for nm, x in (('light_porthole_L', PX[0]), ('light_porthole_R', PX[1])):
        empty(coll, nm, (x, -2.5, ZC), (0, 0, 180), size=0.2, props={'light': 'omni', 'color': '#FFD97A'})

    # ---------------------------------------------------------------- checks
    rep = dict(texel_density_px_per_m=round(k, 3), atlas=SIZE, islands=len(islands), objects={})
    for nm, ob in objs.items():
        closed = nm == 'hull' or nm.startswith('part_') and nm != 'part_canopy'
        r = hygiene(ob, closed, Vector((3.0, 0, -3.0)) if nm == 'hull_nav' else Vector((3.0, 0, -0.25)))
        r.update(uv_checks(ob, k, SIZE)); r['materials'] = [m.name for m in ob.data.materials]
        rep['objects'][nm] = r
    render_objs = [n for n in objs if n not in ('hull_col', 'hull_nav')]
    rep['tris_total_render'] = sum(rep['objects'][n]['tris'] for n in render_objs)
    rep['tris_total_incl_helpers'] = sum(r['tris'] for r in rep['objects'].values())
    rep['non_manifold_hull_and_parts'] = sum(rep['objects'][n]['non_manifold'] for n in objs
                                             if n == 'hull' or (n.startswith('part_') and n != 'part_canopy'))
    rep['flipped_total'] = sum(r['flipped_faces'] for r in rep['objects'].values())
    rep['materials'] = [m.name for m in bpy.data.materials]
    rep['images'] = [i.name for i in bpy.data.images]

    # ---------------------------------------------------------------- export
    lc = bpy.context.view_layer.layer_collection.children['MODULE_CrewPod']
    bpy.context.view_layer.active_layer_collection = lc
    glb = os.path.join(OUT, 'module_crew_pod.glb')
    bpy.ops.export_scene.gltf(filepath=glb, export_format='GLB', use_active_collection=True,
                              export_apply=True, export_yup=True, export_materials='EXPORT',
                              export_cameras=False, export_lights=False, export_extras=True,
                              export_vertex_color='ACTIVE', export_all_vertex_colors=False,
                              export_image_format='AUTO')
    rep['glb'] = inspect_glb(glb)

    # ---------------------------------------------------------------- previews
    render_previews(sc, objs, mats, coll)
    draw_uv_preview(textured, objs, px, SIZE)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, 'module_crew_pod.blend'))
    with open(os.path.join(OUT, 'report.json'), 'w') as fh: json.dump(rep, fh, indent=1)
    print('REPORT_JSON', json.dumps(rep))


def inspect_glb(path):
    import struct
    with open(path, 'rb') as fh: data = fh.read()
    ln = struct.unpack_from('<I', data, 12)[0]; js = json.loads(data[20:20 + ln])
    binoff = 20 + ln + 8
    def acc_minmax(i):
        a = js['accessors'][i]; return a.get('min'), a.get('max')
    out = dict(nodes=len(js['nodes']), meshes=len(js['meshes']), images=len(js.get('images', [])),
               textures=len(js.get('textures', [])), extensions=js.get('extensionsUsed', []),
               materials=[{kk: m.get(kk) for kk in ('name', 'alphaMode', 'doubleSided', 'emissiveFactor', 'extensions')} for m in js['materials']],
               samplers=js.get('samplers'))
    out['extras'] = {n['name']: n.get('extras') for n in js['nodes'] if n.get('extras')}
    col = [p['attributes'].get('COLOR_0') for m in js['meshes'] for p in m['primitives']]
    out['primitives_with_COLOR_0'] = sum(c is not None for c in col)
    out['primitives'] = len(col)
    # read hull COLOR_0 range
    vals = []
    for m in js['meshes']:
        for p in m['primitives']:
            ci = p['attributes'].get('COLOR_0')
            if ci is None: continue
            a = js['accessors'][ci]; bv = js['bufferViews'][a['bufferView']]
            n = a['count'] * (4 if a['type'] == 'VEC4' else 3)
            ct = {5126: ('f', 4), 5123: ('H', 2), 5121: ('B', 1)}[a['componentType']]
            arr = struct.unpack_from('<%d%s' % (n, ct[0]), data, binoff + bv.get('byteOffset', 0) + a.get('byteOffset', 0))
            if ct[0] != 'f': arr = [x / (65535 if ct[0] == 'H' else 255) for x in arr]
            vals += list(arr)
    if vals:
        v = np.array(vals).reshape(-1, 4 if len(vals) % 4 == 0 else 3)
        out['COLOR_0_R_values'] = sorted({round(float(x), 2) for x in v[:, 0]})
        out['COLOR_0_G_values'] = sorted({round(float(x), 2) for x in v[:, 1]})
        out['COLOR_0_B_max'] = round(float(v[:, 2].max()), 3)
    return out


def look_at_cam(sc, coll, rot_deg, objs, res=(1800, 1200), name='CAM_preview'):
    cam = bpy.data.cameras.new(name); cam.type = 'ORTHO'
    co = bpy.data.objects.new(name, cam); coll.objects.link(co)
    co.rotation_euler = [math.radians(a) for a in rot_deg]
    bpy.context.view_layer.update()
    R = co.rotation_euler.to_matrix()
    d, rt, up = R @ Vector((0, 0, -1)), R @ Vector((1, 0, 0)), R @ Vector((0, 1, 0))
    pts = [o.matrix_world @ Vector(c) for o in objs for c in o.bound_box]
    cen = sum(pts, Vector()) / len(pts)
    xs = [(p - cen).dot(rt) for p in pts]; ys = [(p - cen).dot(up) for p in pts]
    cen = cen + rt * (max(xs) + min(xs)) / 2 + up * (max(ys) + min(ys)) / 2
    w, h = max(xs) - min(xs), max(ys) - min(ys)
    cam.ortho_scale = max(w, h * res[0] / res[1]) * 1.12
    co.location = cen - d * 40; cam.clip_end = 200
    sc.camera = co; sc.render.resolution_x, sc.render.resolution_y = res
    return co


def render_previews(sc, objs, mats, coll, extra=True):
    pc = bpy.data.collections.new('PREVIEW_Render'); sc.collection.children.link(pc)
    vis = [o for n, o in objs.items() if not o.hide_render]
    # world: navy background for camera rays, soft neutral fill for lighting
    w = bpy.data.worlds.new('W_Preview'); sc.world = w; w.use_nodes = True
    nt = w.node_tree; nt.nodes.clear()
    o = nt.nodes.new('ShaderNodeOutputWorld'); mix = nt.nodes.new('ShaderNodeMixShader')
    lp = nt.nodes.new('ShaderNodeLightPath'); bg1 = nt.nodes.new('ShaderNodeBackground'); bg2 = nt.nodes.new('ShaderNodeBackground')
    bg1.inputs['Color'].default_value = (0.55, 0.57, 0.68, 1); bg1.inputs['Strength'].default_value = 0.9
    bg2.inputs['Color'].default_value = (*lin('1B1D33'), 1); bg2.inputs['Strength'].default_value = 1.0
    nt.links.new(lp.outputs['Is Camera Ray'], mix.inputs[0]); nt.links.new(bg1.outputs[0], mix.inputs[1])
    nt.links.new(bg2.outputs[0], mix.inputs[2]); nt.links.new(mix.outputs[0], o.inputs[0])
    sun = bpy.data.lights.new('SUN_preview', 'SUN'); sun.energy = 2.6; sun.angle = math.radians(3)
    so = bpy.data.objects.new('SUN_preview', sun); pc.objects.link(so)
    so.rotation_euler = [math.radians(a) for a in (52, 0, -68)]
    sc.render.engine = 'BLENDER_EEVEE'
    try: sc.eevee.taa_render_samples = 64
    except Exception: pass
    sc.view_settings.view_transform = 'Standard'; sc.view_settings.look = 'None'
    sc.render.film_transparent = False
    for rot, fn in (((60, 0, -45), 'preview_oblique.png'), ((60, 0, 45), 'preview_oblique_spec_z45.png'))[:2 if extra else 1]:
        look_at_cam(sc, pc, rot, vis, name='CAM_' + fn[:-4])
        sc.render.filepath = os.path.join(OUT, fn); bpy.ops.render.render(write_still=True)
    # wireframe: workbench, flat object colours + wireframe-modifier twins
    look_at_cam(sc, pc, (60, 0, -45), vis, name='CAM_wire')
    twins = []
    for ob in vis:
        ob.color = (0.86, 0.86, 0.9, 1)
        t = ob.copy(); t.name = ob.name + '_WIRE'; pc.objects.link(t)
        m = t.modifiers.new('wf', 'WIREFRAME'); m.thickness = 0.022; m.use_even_offset = True; m.offset = 0.0
        t.color = (0.08, 0.09, 0.22, 1); twins.append(t)
    sc.render.engine = 'BLENDER_WORKBENCH'
    sh = sc.display.shading; sh.light = 'FLAT'; sh.color_type = 'OBJECT'
    w.color = (0.97, 0.97, 0.98)
    sc.render.filepath = os.path.join(OUT, 'preview_wire.png'); bpy.ops.render.render(write_still=True)
    for t in twins: bpy.data.objects.remove(t)
    for ob in vis: ob.color = (1, 1, 1, 1)
    sc.render.engine = 'BLENDER_EEVEE'
    sc.camera = bpy.data.objects['CAM_preview_oblique']


def draw_uv_preview(textured, objs, px, SIZE, scale=4):
    img = np.repeat(np.repeat(px, scale, 0), scale, 1).copy()
    S = SIZE * scale
    def line(a, b, colr):
        n = int(max(abs(b[0] - a[0]), abs(b[1] - a[1])) * S) + 2
        t = np.linspace(0, 1, n)
        xs = np.clip(((a[0] + (b[0] - a[0]) * t) * S).astype(int), 0, S - 1)
        ys = np.clip(((a[1] + (b[1] - a[1]) * t) * S).astype(int), 0, S - 1)
        img[ys, xs, :3] = colr
    for mb in textured:
        me = objs[mb.name].data
        uv = np.zeros(len(me.loops) * 2); me.uv_layers[0].uv.foreach_get('vector', uv); uv = uv.reshape(-1, 2)
        seam = {tuple(sorted(e.vertices)) for e in me.edges if e.use_seam}
        for p in me.polygons:
            ls = list(p.loop_indices)
            for i in range(len(ls)):
                a, b = ls[i], ls[(i + 1) % len(ls)]
                key = tuple(sorted((me.loops[a].vertex_index, me.loops[b].vertex_index)))
                line(uv[a], uv[b], (0.85, 0.05, 0.1) if key in seam else (0.1, 0.1, 0.15))
    im = bpy.data.images.new('UV_preview', S, S, alpha=False)
    im.pixels.foreach_set(img.ravel()); im.filepath_raw = os.path.join(OUT, 'preview_uv.png'); im.file_format = 'PNG'; im.save()
    bpy.data.images.remove(im)


# ============================================================================= GAME MODE
G_ID = 'crew_pod'
G_SCALE, G_FLOOR = 1.35, -0.03      # deck top just under the game's floor tiles (y = 0)
G_LAYOUT = "#####\na...#\na...#\n#####"   # room = 3 x 2 cells (x -3..3, z -2..2), door A on -X
KIT_MAP = {'cream': 'ivory', 'shade': 'ivory_old', 'navy': 'navy', 'mustard': 'trim_gold',
           'terracotta': 'red_faded', 'floor': 'deck', 'console': 'red_faded', 'top': 'fabric',
           'red': 'red', 'locker': 'offwhite_old', 'inavy': 'navy', 'glow': 'amber',
           'screen': 'cyan', 'glass': 'canopy'}
G_RENAME = {'part_roof_frame': 'frame_roof', 'interior_floor_deck': 'deck'}
G_MAT = Matrix.Translation((0, 0, G_FLOOR)) @ Matrix.Scale(G_SCALE, 4) @ Matrix.Translation((-3.0, 0, -ZF))


def game_materials(kc):
    mats = {}
    for name in ('M_Hull', 'M_Interior', 'M_Emissive', 'M_Glass'):
        m = bpy.data.materials.new(name); m.use_nodes = True
        nt = m.node_tree; bs = nt.nodes.get('Principled BSDF')
        bs.inputs['Roughness'].default_value = 0.9; bs.inputs['Metallic'].default_value = 0.0
        at = nt.nodes.new('ShaderNodeAttribute'); at.attribute_name = 'Base'; at.location = (-400, 200)
        nt.links.new(at.outputs['Color'], bs.inputs['Base Color'])
        if name == 'M_Emissive':
            nt.links.new(at.outputs['Color'], bs.inputs['Emission Color'])
            bs.inputs['Emission Strength'].default_value = 2.0
        if name == 'M_Glass':
            bs.inputs['Alpha'].default_value = 0.35
            if hasattr(m, 'surface_render_method'): m.surface_render_method = 'BLENDED'
        m.use_backface_culling = True
        mats[name] = m
    return mats


def game_attrs(ob, mb, mats, kc):
    """Materials + kit colour ('Base', linear) per corner; 'Color' (masks) stays active."""
    me = ob.data
    slots = []
    for F in mb.F:
        if F['mat'] not in slots: slots.append(F['mat'])
    for sl in slots: me.materials.append(mats[sl])
    me.polygons.foreach_set('material_index', [slots.index(F['mat']) for F in mb.F])
    base = me.color_attributes.new(name='Base', type='FLOAT_COLOR', domain='CORNER')
    cols = []
    for F in mb.F:
        cols += (list(kc.C[KIT_MAP[F['col']]][:3]) + [1.0]) * len(F['v'])
    base.data.foreach_set('color', cols)
    _activate_color(me)


def _activate_color(me):
    ca = me.color_attributes
    ca.active_color = ca['Color']
    try: ca.render_color_index = list(ca.keys()).index('Color')
    except Exception: pass


def _box_mesh(name, lo, hi):
    bm = bmesh.new(); bmesh.ops.create_cube(bm, size=1.0)
    lo, hi = Vector(lo), Vector(hi)
    for v in bm.verts:
        v.co = (lo + hi) / 2 + Vector([a * b for a, b in zip(v.co, hi - lo)])
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    return me


def cut_doorway(hull, mats, kc, coll):
    """Doorway A: a notch through the -X end wall, as wide as the dock bore, from the deck
    up through the rim (EXACT boolean keeps the hull watertight; cut faces = ivory)."""
    me = _box_mesh('_door', (X0 - 0.05, -BORE, ZF - 0.01), (X0 + T + 0.05, BORE, 1.5))
    me.materials.append(mats['M_Hull'])
    for nm, val in (('Color', (0.45, 0.0, 0.0, 1.0)), ('Base', tuple(kc.C['ivory'][:3]) + (1.0,))):
        a = me.color_attributes.new(name=nm, type='FLOAT_COLOR', domain='CORNER')
        a.data.foreach_set('color', list(val) * len(me.loops))
    cut = bpy.data.objects.new('_door', me); coll.objects.link(cut)
    md = hull.modifiers.new('DOOR', 'BOOLEAN'); md.operation = 'DIFFERENCE'; md.solver = 'EXACT'; md.object = cut
    if hasattr(md, 'material_mode'): md.material_mode = 'TRANSFER'
    bpy.context.view_layer.update()
    new = bpy.data.meshes.new_from_object(hull.evaluated_get(bpy.context.evaluated_depsgraph_get()))
    old = hull.data; hull.modifiers.remove(md); hull.data = new
    bpy.data.meshes.remove(old); new.name = 'hull'
    bpy.data.objects.remove(cut, do_unlink=True); bpy.data.meshes.remove(me)
    new.polygons.foreach_set('use_smooth', [False] * len(new.polygons))
    _activate_color(new)


def to_game_space(ob, keep_origin):
    """Bake G_MAT into the mesh; parts/props keep their (moved) origin, the rest sits at 0."""
    new_loc = G_MAT @ ob.location if keep_origin else Vector()
    ob.data.transform(Matrix.Translation(-new_loc) @ G_MAT @ Matrix.Translation(ob.location))
    ob.location = new_loc


def bake_palette_uvs(ob, kc, grid=8):
    """Same rule as the kit (art/kit/module.py): each corner -> its swatch centre in kit_palette.png."""
    index = {tuple(round(v, 4) for v in kc.C[k][:3]): i for i, k in enumerate(kc.PAL)}
    me = ob.data; uv = me.uv_layers.get('UVMap') or me.uv_layers.new(name='UVMap')
    bad = set()
    for li, d in enumerate(me.color_attributes['Base'].data):
        key = tuple(round(v, 4) for v in d.color[:3]); i = index.get(key)
        if i is None: bad.add(key); i = 0
        uv.data[li].uv = ((i % grid + 0.5) / grid, (i // grid + 0.5) / grid)
    return bad


def main_game():
    sys.path.insert(0, os.path.join(GAME, 'art'))
    from kit import core as kc
    sc = reset_scene()
    coll = bpy.data.collections.new('MODULE_CrewPod'); sc.collection.children.link(coll)
    mats = game_materials(kc)
    builders = [build_hull(), build_porthole_glass(), build_roof_frame(), build_canopy(), build_collar(),
                build_tube(), *build_interior()]       # no pillar: in the game the column is a neighbour
    objs = {}
    for mb in builders:
        unfold(mb)                                  # marks hard edges (sharp) as in spec mode
        ob = to_object(mb, coll, mats, None, None, None, with_uv=False)
        game_attrs(ob, mb, mats, kc); objs[mb.name] = ob
    cut_doorway(objs['hull'], mats, kc, coll)
    errors = []
    final = {}
    for nm, ob in objs.items():
        new = G_RENAME.get(nm) or ('prop_' + nm[len('interior_'):] if nm.startswith('interior_') else nm)
        ob.name = new; ob.data.name = new
        to_game_space(ob, keep_origin=new.startswith(('part_', 'prop_')))
        for key in bake_palette_uvs(ob, kc):
            errors.append('%s: colour %s not in kit_palette' % (new, key))
        final[new] = ob
    objs = final
    objs['part_collar']['explode_dir'] = [-1.0, 0.0, 0.0]
    objs['part_dock_tube']['explode_dir'] = [-1.0, 0.0, 0.0]
    objs['part_canopy']['explode_dir'] = [0.0, 1.0, 0.0]
    # slot A: 0.15 m (Slot.GAP) beyond the tube end, floor level, local -Y (Blender) = Godot +Z = out (-X)
    tube_end = (G_MAT @ Vector((TUBE_X0 - TUBE_L, 0, 0))).x
    sx = round(tube_end - 0.15, 3)
    empty(coll, 'slot_A', (sx, 0, 0), (0, 0, -90), size=0.8)
    empty(coll, 'light_cabin', (0, 0, 2.1), size=0.2)
    cb = bpy.data.objects.new('cut_box', _box_mesh('cut_box', (-4.1, -3.0, 1.15), (3.5, 2.8, 6.0)))
    cb.data.materials.append(mats['M_Hull']); cb.display_type = 'WIRE'; cb.hide_render = True
    coll.objects.link(cb)

    # ---------------------------------------------------------------- checks
    bpy.context.view_layer.update()                 # matrix_world after the moves above
    def plan(ob):
        ws = [ob.matrix_world @ v.co for v in ob.data.vertices]
        x0, x1 = min(w.x for w in ws), max(w.x for w in ws); y0, y1 = min(w.y for w in ws), max(w.y for w in ws)
        return (x0, -y1, x1, -y0)   # Godot (x, z) rect
    massing = [plan(objs[n]) for n in ('hull', 'part_collar', 'part_dock_tube')]
    rep = dict(mode='game', scale=G_SCALE, objects={})
    for nm, ob in objs.items():
        r = hygiene(ob, True, Vector((0, 0, 1.0)))
        rep['objects'][nm] = {k: r[k] for k in ('tris', 'non_manifold', 'flipped_faces', 'ngons', 'shells')}
    for nm in ('hull', 'part_collar', 'part_dock_tube', 'frame_roof'):
        if rep['objects'][nm]['non_manifold']:
            errors.append('%s not watertight: %d' % (nm, rep['objects'][nm]['non_manifold']))
    flipped = sum(r['flipped_faces'] for r in rep['objects'].values())
    if flipped: errors.append('%d flipped faces' % flipped)
    for x0, z0, x1, z1 in massing:
        if x0 + 0.05 < sx < x1 - 0.05 and z0 + 0.05 < 0 < z1 - 0.05:
            errors.append('slot A inside the footprint')
    rows = G_LAYOUT.split('\n'); door_x = sx + 1.15     # Module: door = slot - out * (CELL/2 + GAP)
    c, rr = round(door_x / 2 + (len(rows[0]) - 1) / 2), round(0 / 2 + (len(rows) - 1) / 2)
    if not (0 <= c < len(rows[0]) and rows[rr][c] in '.abcdefghijklmnopqrstuvwxyz'):
        errors.append('door point x=%.2f is not on a walkable cell' % door_x)
    tris = sum(r['tris'] for r in rep['objects'].values())
    rep.update(tris_total=tris, slot_A=[sx, 0.0, -90.0], massing=massing, errors=errors)
    for e in errors: print('GAME ERROR:', e)

    # ---------------------------------------------------------------- export (kit settings)
    for ob in bpy.context.view_layer.objects: ob.select_set(False)
    for ob in coll.all_objects: ob.select_set(True)
    glb = os.path.join(GAME, 'assets', 'models', 'modules', G_ID + '.glb')
    props = bpy.ops.export_scene.gltf.get_rna_type().properties.keys()
    want = dict(export_format='GLB', use_selection=True, export_yup=True, export_apply=True,
                export_extras=True, export_lights=False, export_cameras=False,
                export_vertex_color='ACTIVE', export_all_vertex_colors=False,
                export_attributes=False, export_materials='EXPORT', export_texcoords=True)
    bpy.ops.export_scene.gltf(filepath=glb, **{k: v for k, v in want.items() if k in props})
    side = {"id": G_ID, "layout": G_LAYOUT, "slots": {"A": [sx, 0.0, -90.0]}, "slot_sizes": {"A": 2},
            "massing": [[round(x0, 3), round(z0, 3), round(x1 - x0, 3), round(z1 - z0, 3)] for x0, z0, x1, z1 in massing],
            "triangles": tris, "errors": errors}
    with open(os.path.join(GAME, 'art', 'modules', 'export', G_ID + '.json'), 'w') as fh: json.dump(side, fh, indent=1)
    rep['glb'] = inspect_glb(glb)
    render_previews(sc, objs, mats, coll, extra=False)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, G_ID + '.blend'))
    with open(os.path.join(OUT, 'report_game.json'), 'w') as fh: json.dump(rep, fh, indent=1)
    print('GAME_REPORT', json.dumps({k: rep[k] for k in ('tris_total', 'slot_A', 'errors')}))


main_game() if GAME else main()
