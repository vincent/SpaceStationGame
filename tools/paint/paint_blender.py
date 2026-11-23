"""
paint_blender.py - camera-projection painting, Blender side (render + project).

    blender -b <id>.blend -P tools/paint/paint_blender.py -- render  --module=<id> --yaw=<0|90|180|270> [--res=2048]
    blender -b <id>.blend -P tools/paint/paint_blender.py -- project --module=<id>

Reads art/modules/build/<id>.blend (written by tools/art.sh or the module's build script).
Work dir: art/paint/<id>/y<yaw>/ (one per module direction: the camera is fixed, a module attached
at another yaw shows other faces, so each direction gets its own painting).

render  : orthographic camera matching src/camera/diorama_camera.gd (pitch -28, yaw 25,
          module rotated by --yaw), two configurations:
            closed : what station view shows (props hidden)
            cut    : what room view shows (geometry inside cut_box removed, props shown)
          and three passes each:
            <cfg>_beauty.webp  flat-shaded kit colours (input for the AI painter)
            <cfg>_plane.webp   per (object, plane) flat colour  -> geometry lines (alignment)
            <cfg>_faceid.webp  per original face id (24-bit)     -> visibility (projection)
          all LOSSLESS WebP (quality 100): the id passes are decoded exactly (older work dirs may still
          hold .png renders; render_file() reads either)
          plus camera.json and faces.json (id -> object, polygon).
project : for every direction with a camera.json, picks for every face the configuration in which
          it is most visible and projects it through that camera into the direction's atlas
          (rows closed / cut / interior). UV layers after UVMap, in this order (Godot names):
            Paint0 -> UV2, Paint90 -> CUSTOM0.xy, Paint180 -> CUSTOM0.zw, Paint270 -> CUSTOM1.xy
          Faces a direction never saw get (-1, -1) there (shader: palette fallback). Exports
          assets/models/modules/<id>.glb with the kit settings.
"""
import bpy, bmesh, json, math, os, sys
import numpy as np
from mathutils import Matrix, Vector

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
CMD = argv[0] if argv else 'render'
OPT = dict(a[2:].split('=', 1) for a in argv[1:] if a.startswith('--') and '=' in a)
MID = OPT['module']
YAW = float(OPT.get('yaw', 0))
RES = int(OPT.get('res', 2048))
YAWS = (0, 90, 180, 270)
def work_dir(yaw): return os.path.join(ROOT, 'art', 'paint', MID, 'y%d' % int(yaw))


def render_file(work, name):
    """Render pass <name> (e.g. closed_faceid) in `work`: lossless .webp, or a .png made before WebP."""
    webp = os.path.join(work, name + '.webp')
    return webp if os.path.exists(webp) else os.path.join(work, name + '.png')
WORK = work_dir(YAW)

# game camera (src/camera/diorama_camera.gd): rotation_degrees = (pitch, yaw, 0), Euler YXZ
PITCH, CAM_YAW = -28.0, 25.0
MARGIN = 1.06
def _lin(c): return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
BG = tuple(_lin(c / 255) for c in (0x1b, 0x1d, 0x30))   # in-game backdrop (linear for Workbench)
CAP = tuple(_lin(c) for c in (0.93, 0.87, 0.74))        # project.godot cut_cap_color (section fill)
G2B = Matrix(((1, 0, 0), (0, 0, -1), (0, 1, 0)))  # Godot (Y-up) -> Blender (Z-up)


def log(*a): print('PAINT', *a, flush=True)


# ----------------------------------------------------------------------------- scene
def render_objects():
    """Mesh objects that the game draws (helpers, cut_box, -col/-nav excluded)."""
    out = []
    for ob in bpy.data.objects:
        if ob.type != 'MESH' or ob.name == 'cut_box' or ob.hide_render:
            continue        # hide_render: helpers and the kit's GREEBLE_KIT templates
        if any(c.name == 'GREEBLE_KIT' for c in ob.users_collection):
            continue
        if ob.name.endswith(('-col', '-nav', '_col', '_nav')) or ob.get('helper'):
            continue
        out.append(ob)
    return out


def is_prop(ob): return ob.name.startswith('prop_')
def is_interior(ob): return ob.name.startswith(('prop_', 'deck', 'floor'))   # painted from the interior pass
def is_part(ob): return ob.name.startswith('part_')       # upgrade parts: hidden until bought
# Views (= atlas rows, top-down). With the parts pass, hull views are rendered WITHOUT the parts so the
# hull behind a part not yet bought is painted for real; parts get their own view.
PARTS_PASS = OPT.get('parts-pass', '1') == '1'
CONFIGS = ('closed', 'cut', 'interior', 'parts') if PARTS_PASS else ('closed', 'cut', 'interior')
def is_uncut(ob): return ob.name.startswith(('prop_', 'frame'))


def camera_matrix():
    """World matrix of the game camera in Blender space; the module's yaw is applied by rotating
    the camera the other way around the module origin."""
    rg = Matrix.Rotation(math.radians(CAM_YAW - YAW), 3, 'Y') @ Matrix.Rotation(math.radians(PITCH), 3, 'X')
    rb = G2B @ rg                     # Blender camera also looks down local -Z with +Y up
    return rb


def fit_camera(sc, obs):
    rb = camera_matrix()
    inv = rb.transposed()
    pts = [inv @ (ob.matrix_world @ v.co) for ob in obs for v in ob.data.vertices]
    xs = [p.x for p in pts]; ys = [p.y for p in pts]; zs = [p.z for p in pts]
    cx, cy = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
    w, h = (max(xs) - min(xs)) * MARGIN, (max(ys) - min(ys)) * MARGIN
    resx = RES; resy = int(math.ceil(RES * h / w / 8.0) * 8)
    w = h * resx / resy if resy * w / resx < h else w   # keep square pixels
    cam_d = bpy.data.cameras.new('PAINT_CAM'); cam_d.type = 'ORTHO'
    cam_d.sensor_fit = 'HORIZONTAL'; cam_d.ortho_scale = w
    cam_d.clip_start = 0.01; cam_d.clip_end = 1000
    cam = bpy.data.objects.new('PAINT_CAM', cam_d); sc.collection.objects.link(cam)
    zfar = max(zs) + 50
    cam.matrix_world = Matrix.Translation(rb @ Vector((cx, cy, zfar))) @ rb.to_4x4()
    sc.camera = cam
    sc.render.resolution_x, sc.render.resolution_y = resx, resy
    sc.render.resolution_percentage = 100
    info = dict(module=MID, yaw=YAW, pitch=PITCH, cam_yaw=CAM_YAW, res=[resx, resy], configs=list(CONFIGS),
                width_m=w, height_m=w * resy / resx,
                world_to_cam=[list(r) for r in cam.matrix_world.inverted()])
    return cam, info


def project_px(info, p):
    """Blender world point -> pixel (x right, y down) in a render."""
    M = Matrix(info['world_to_cam']); c = M @ Vector(p)
    resx, resy = info['res']
    u = c.x / info['width_m'] + 0.5; v = c.y / info['height_m'] + 0.5
    return u * resx, (1 - v) * resy


# ----------------------------------------------------------------------------- configurations
def cut_copy(ob, cutter):
    """Copy of ob with what lies inside the cut_box removed, as the toon_cut shader does (discard):
    slice along the box planes, delete the faces inside, no caps (the game draws the back faces as
    the section fill: see back_shell). Works on non-watertight meshes, keeps every attribute."""
    lo = Vector([min((cutter.matrix_world @ Vector(c))[i] for c in cutter.bound_box) for i in range(3)])
    hi = Vector([max((cutter.matrix_world @ Vector(c))[i] for c in cutter.bound_box) for i in range(3)])
    me = ob.data.copy()
    bm = bmesh.new(); bm.from_mesh(me)
    bm.transform(ob.matrix_world)
    planes = [((0, 0, lo.z), (0, 0, 1)), ((lo.x, 0, 0), (1, 0, 0)), ((hi.x, 0, 0), (1, 0, 0)),
              ((0, lo.y, 0), (0, 1, 0)), ((0, hi.y, 0), (0, 1, 0))]
    for co, no in planes:
        geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
        bmesh.ops.bisect_plane(bm, geom=geom, plane_co=co, plane_no=no, dist=1e-5)
    eps = 1e-4
    inside = [f for f in bm.faces if all(lo[i] - eps <= f.calc_center_median()[i] <= hi[i] + eps for i in range(3))]
    bmesh.ops.delete(bm, geom=inside, context='FACES')
    bm.transform(ob.matrix_world.inverted())
    bm.to_mesh(me); bm.free()
    return me


def back_shell(me):
    """Flipped copy of a cut-material mesh: with back-face culling on, what the camera sees of it is
    exactly what toon_cut paints as the flat section fill (back faces through the cut)."""
    sh = me.copy()
    bm = bmesh.new(); bm.from_mesh(sh)
    bmesh.ops.reverse_faces(bm, faces=bm.faces[:])
    bm.to_mesh(sh); bm.free()
    a = sh.attributes.get('paint_fid')
    if a is not None:
        a.data.foreach_set('value', [0] * len(sh.polygons))     # fid 0 = section fill colour
    return sh


def build_config(sc, obs, cfg):
    """Temporary objects for one configuration, each carrying corner attributes
    PaintBase (kit colour), PaintPlane, PaintFace. Returns the list of temp objects."""
    coll = bpy.data.collections.new('PAINT_' + cfg); sc.collection.children.link(coll)
    cutter = bpy.data.objects.get('cut_box')
    temps = []
    for ob in obs:
        if cfg == 'closed' and is_prop(ob):
            continue
        if cfg == 'interior' and not is_interior(ob):
            continue        # props and floor alone: the painter cannot redesign the room around them
        if cfg == 'parts' and not is_part(ob):
            continue
        if cfg in ('closed', 'cut') and PARTS_PASS and is_part(ob):
            continue
        if cfg == 'cut' and cutter is not None and not is_uncut(ob):
            me = cut_copy(ob, cutter)
        else:
            me = ob.data.copy()
        if not me.polygons:
            continue
        meshes = [(ob.name, me)]
        if cfg in ('closed', 'cut') and not is_uncut(ob):
            meshes.append((ob.name + '#back', back_shell(me)))
        for name, m in meshes:
            t = bpy.data.objects.new('T_' + cfg + '_' + name, m); t.matrix_world = ob.matrix_world.copy()
            coll.objects.link(t); temps.append(t)
            m.materials.clear()
    for ob in obs:
        ob.hide_render = True
    return coll, temps


def enc(i):
    """24-bit id -> float colour robust to +-1 code value errors (6 bits per channel)."""
    return [((i >> s) & 63) * 4 + 2 for s in (0, 6, 12)]


def dec(img):
    q = (img[..., :3].astype(np.int32) - 2 + 2) // 4    # round to nearest step of 4
    q = np.clip(q, 0, 63)
    return q[..., 0] | (q[..., 1] << 6) | (q[..., 2] << 12)


def write_attrs(temps, fid_of):
    """fid_of(t, poly) -> original face id (0 = none). Also builds plane ids."""
    planes = {}
    for oi, t in enumerate(temps):
        me = t.data
        base_src = me.color_attributes.get('Base')
        base = np.ones(len(me.loops) * 4, dtype=np.float32) * 0.6
        if base_src is not None and base_src.domain == 'CORNER':
            base_src.data.foreach_get('color', base)
        pid = me.attributes.get('paint_fid')
        fids = np.zeros(len(me.polygons), dtype=np.int32)
        if pid is not None:
            pid.data.foreach_get('value', fids)
        base = base.reshape(-1, 4)
        for p in me.polygons:
            if fids[p.index] == 0:        # boolean cap: the game shows its section fill here
                base[list(p.loop_indices)] = (*CAP, 1.0)
        base = base.ravel()
        pcol, fcol = [], []
        mw = t.matrix_world; nm = mw.to_3x3().inverted().transposed()
        for p in me.polygons:
            n = (nm @ p.normal).normalized(); d = n.dot(mw @ p.center)
            key = (t.name.split('_', 2)[2], round(n.x, 2), round(n.y, 2), round(n.z, 2), round(d, 2))
            k = planes.setdefault(key, len(planes) + 1)
            pc = [c / 255 for c in enc(k * 2654435761 % (1 << 18))] + [1.0]   # scrambled -> distinct neighbours
            fc = [c / 255 for c in enc(int(fids[p.index]))] + [1.0]
            for _ in p.loop_indices:
                pcol += pc; fcol += fc
        for name, data in (('PaintBase', base), ('PaintPlane', pcol), ('PaintFace', fcol)):
            a = me.color_attributes.new(name=name, type='FLOAT_COLOR', domain='CORNER')
            a.data.foreach_set('color', data)


def set_active(temps, name):
    for t in temps:
        ca = t.data.color_attributes
        ca.active_color = ca[name]
        try: ca.render_color_index = list(ca.keys()).index(name)
        except Exception: pass


def setup_render(sc):
    sc.render.engine = 'BLENDER_WORKBENCH'
    sc.display.shading.color_type = 'VERTEX'
    sc.display.shading.show_backface_culling = True     # back faces: see back_shell
    sc.render.film_transparent = False
    sc.world = sc.world or bpy.data.worlds.new('W')
    sc.render.image_settings.file_format = 'WEBP'
    sc.render.image_settings.color_mode = 'RGB'
    sc.render.image_settings.quality = 100     # 100 = lossless WebP: id passes must be exact
    sc.render.dither_intensity = 0.0          # id passes must be exact


def render_pass(sc, temps, attr, path, beauty):
    set_active(temps, attr)
    sh = sc.display.shading
    if beauty:
        sh.light = 'STUDIO'; sh.show_shadows = True; sh.shadow_intensity = 0.35
        sh.show_cavity = False; sh.show_object_outline = False
        sh.background_type = 'VIEWPORT'; sh.background_color = BG
        sc.display.render_aa = '8'
        sc.view_settings.view_transform = 'Standard'
        sh.show_specular_highlight = False
    else:
        sh.light = 'FLAT'; sh.show_shadows = False; sh.show_cavity = False
        sh.show_object_outline = False
        sh.background_type = 'VIEWPORT'; sh.background_color = (0, 0, 0)
        sc.display.render_aa = 'OFF'
        sc.view_settings.view_transform = 'Raw'
    sc.view_settings.look = 'None'
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)
    log('wrote', os.path.relpath(path, ROOT))


def tag_faces(obs):
    """Integer face attribute paint_fid on every original mesh (1-based, global)."""
    faces = {}; nxt = 1
    for ob in obs:
        me = ob.data
        a = me.attributes.get('paint_fid') or me.attributes.new('paint_fid', 'INT', 'FACE')
        ids = list(range(nxt, nxt + len(me.polygons))); nxt += len(me.polygons)
        a.data.foreach_set('value', ids)
        for p, i in zip(me.polygons, ids):
            faces[i] = [ob.name, p.index]
    return faces


def cmd_render():
    os.makedirs(WORK, exist_ok=True)
    sc = bpy.context.scene
    obs = render_objects()
    faces = tag_faces(obs)
    cam, info = fit_camera(sc, obs)
    setup_render(sc)
    info['configs'] = [c for c in CONFIGS if c != 'parts' or any(is_part(o) for o in obs)]
    for cfg in info['configs']:
        coll, temps = build_config(sc, obs, cfg)
        write_attrs(temps, None)
        render_pass(sc, temps, 'PaintBase', os.path.join(WORK, cfg + '_beauty.webp'), True)
        render_pass(sc, temps, 'PaintPlane', os.path.join(WORK, cfg + '_plane.webp'), False)
        render_pass(sc, temps, 'PaintFace', os.path.join(WORK, cfg + '_faceid.webp'), False)
        for t in temps:
            me = t.data; bpy.data.objects.remove(t); bpy.data.meshes.remove(me)
        bpy.data.collections.remove(coll)
    with open(os.path.join(WORK, 'camera.json'), 'w') as fh: json.dump(info, fh, indent=1)
    with open(os.path.join(WORK, 'faces.json'), 'w') as fh: json.dump(faces, fh)
    log('render done', info['res'])


# ----------------------------------------------------------------------------- project
def load_image(path):
    img = bpy.data.images.load(path, check_existing=False)
    img.colorspace_settings.name = 'Non-Color'
    w, h = img.size
    px = np.empty(w * h * 4, dtype=np.float32); img.pixels.foreach_get(px)
    bpy.data.images.remove(img)
    return np.flipud((px.reshape(h, w, 4) * 255 + 0.5).astype(np.int32))   # row 0 = top


def face_choice(work, faces, configs):
    """face id -> configuration index (row in that direction's atlas) or None (never visible)."""
    counts = {}
    for cfg in configs:
        path = render_file(work, cfg + '_faceid')
        if not os.path.exists(path):
            counts[cfg] = {}; continue
        ids = dec(load_image(path))
        u, c = np.unique(ids, return_counts=True)
        counts[cfg] = dict(zip(u.tolist(), c.tolist()))
    CLOSED_BIAS, MIN_PX = 1.1, 6
    choice = {}
    stats = {c: 0 for c in configs}; stats['fallback'] = 0
    for fid, (obname, _) in faces.items():
        i = int(fid)
        ob = bpy.data.objects[obname]
        if is_interior(ob):
            ch = 2 if counts['interior'].get(i, 0) >= MIN_PX else None
        elif 'parts' in configs and is_part(ob):
            ch = 3 if counts['parts'].get(i, 0) >= MIN_PX else None
        else:
            a, b = counts['closed'].get(i, 0) * CLOSED_BIAS, counts['cut'].get(i, 0)
            ch = None if max(a, b) < MIN_PX else (0 if a >= b else 1)
        choice[i] = ch
        stats[configs[ch] if ch is not None else 'fallback'] += 1
    return choice, stats


def cmd_project():
    obs = render_objects()
    faces_now = tag_faces(obs)
    dirs = {}
    for yaw in YAWS:
        w = work_dir(yaw)
        if not os.path.exists(os.path.join(w, 'camera.json')):
            log('y%d: no bake, palette only' % yaw); continue
        faces = {int(k): v for k, v in json.load(open(os.path.join(w, 'faces.json'))).items()}
        assert faces == faces_now, 'y%d: face ids differ from the render: re-render' % yaw
        info = json.load(open(os.path.join(w, 'camera.json')))
        info.setdefault('configs', ['closed', 'cut', 'interior'])     # bakes made before the parts pass
        choice, stats = face_choice(w, faces, info['configs'])
        dirs[yaw] = (info, choice)
        log('y%d faces' % yaw, stats)
    for ob in obs:
        me = ob.data
        fids = np.zeros(len(me.polygons), dtype=np.int32)
        me.attributes['paint_fid'].data.foreach_get('value', fids)
        mw = ob.matrix_world
        for yaw in YAWS:
            uv = me.uv_layers.get('Paint%d' % yaw) or me.uv_layers.new(name='Paint%d' % yaw)
            info, choice = dirs.get(yaw, (None, {}))
            for p in me.polygons:
                ch = choice.get(int(fids[p.index]))
                for li in p.loop_indices:
                    if ch is None:
                        uv.data[li].uv = (-1.0, 2.0)          # glTF/Godot v = 1 - 2 = -1
                        continue
                    resx, resy = info['res']
                    x, y = project_px(info, mw @ me.vertices[me.loops[li].vertex_index].co)
                    ay = y + ch * resy                         # atlas rows top-down: closed, cut, interior
                    uv.data[li].uv = (x / resx, 1.0 - ay / (len(info['configs']) * resy))
        me.attributes.remove(me.attributes['paint_fid'])
        me.uv_layers.active = me.uv_layers['UVMap']
        assert [u.name for u in me.uv_layers][:5] == ['UVMap', 'Paint0', 'Paint90', 'Paint180', 'Paint270'], ob.name
    # export like the kit, with all UV sets
    for ob in bpy.context.view_layer.objects: ob.select_set(False)
    for ob in bpy.data.objects:         # what the kit exports: the module, not the greeble templates
        if ob.type in ('MESH', 'EMPTY') and not ob.name.startswith(('CAM_', 'SUN_', 'PAINT_')) \
                and not any(c.name == 'GREEBLE_KIT' for c in ob.users_collection):
            ob.select_set(True)
    glb = os.path.join(ROOT, 'assets', 'models', 'modules', MID + '.glb')
    props = bpy.ops.export_scene.gltf.get_rna_type().properties.keys()
    want = dict(export_format='GLB', use_selection=True, export_yup=True, export_apply=True,
                export_extras=True, export_lights=False, export_cameras=False,
                export_vertex_color='ACTIVE', export_all_vertex_colors=False,
                export_attributes=False, export_materials='EXPORT', export_texcoords=True,
                export_active_vertex_color_when_no_material=True)
    bpy.ops.export_scene.gltf(filepath=glb, **{k: v for k, v in want.items() if k in props})
    log('exported', os.path.relpath(glb, ROOT), 'directions', sorted(dirs))


{'render': cmd_render, 'project': cmd_project}[CMD]()
