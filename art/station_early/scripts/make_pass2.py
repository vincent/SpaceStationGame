"""Headless pass-2 driver: build, save .blend, render 3 views, export glTF, print stats.

blender -b --factory-startup --python art/station_early/scripts/make_pass2.py [-- --no-render] [-- --no-export]
"""
import json
import os
import shutil
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
g = {"__file__": os.path.join(HERE, "build_station.py"), "__name__": "build_station"}
exec(open(g["__file__"]).read(), g)

PREVIEW_MODS = ("OUTLINE", "CUT_PREVIEW")
MODULES = {"capsule": "CAPSULE", "wreck_core": "WRECK_CORE"}


def set_preview_mods(objs, on, only=PREVIEW_MODS):
    for o in objs:
        for md in o.modifiers:
            if md.name in only:
                md.show_viewport = md.show_render = on


def module_stats(coll):
    objs = list(bpy.data.collections[coll].all_objects)
    set_preview_mods(objs, False)
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    tris, mats, per = 0, set(), {}
    for o in objs:
        if o.type != "MESH":
            continue
        me = o.evaluated_get(dg).to_mesh()
        me.calc_loop_triangles()
        n = len(me.loop_triangles)
        used = {me.materials[t.material_index].name for t in me.loop_triangles if me.materials}
        if o.material_slots:  # object-level overrides
            used = {o.material_slots[t.material_index].material.name for t in me.loop_triangles}
        mats |= used
        tris += n
        per[o.name] = n
        o.evaluated_get(dg).to_mesh_clear()
    set_preview_mods(objs, True)
    top = sorted(per.items(), key=lambda kv: -kv[1])[:8]
    return {"triangles": tris, "materials": sorted(mats), "objects": len(objs), "heaviest": top}


GAME_DIR = os.path.join(os.path.dirname(os.path.dirname(ROOT)), "assets", "models", "station_early")


def export_module(root_name, coll):
    """glTF with the module origin (layout centre) at 0, a flat top level (hull,
    slot_*, part_*, light_*... are direct children of the imported scene root, as
    Module expects), "@module" suffixes stripped, preview modifiers off."""
    objs = [o for o in bpy.data.collections[coll].all_objects if o.name != root_name]
    root = bpy.data.objects[root_name]
    extra = []
    if root_name == "wreck_core":  # the game cuts this box open (Module.get_cut_aabb)
        extra = [bpy.data.objects["CUT_BOX"]]
    set_preview_mods(objs, False)
    outlined = [o for o in objs if "OUTLINE" in o.modifiers]
    for o in outlined:  # modifier-free linked duplicates export as shared meshes
        o.modifiers.remove(o.modifiers["OUTLINE"])
    renamed = []

    def rename(o, want):
        clash = bpy.data.objects.get(want)
        if clash is not None and clash != o:
            renamed.append((clash, clash.name))
            clash.name = want + "#tmp"
        renamed.append((o, o.name))
        o.name = want

    for o in objs:  # "hull@capsule" -> "hull"
        if "@" in o.name:
            rename(o, o.name.split("@")[0])
    for o in extra:
        rename(o, "cut_box")
    origin = root.location.copy()
    root.location = (0, 0, 0)
    bpy.context.view_layer.update()
    saved = []
    for o in objs:
        if o.parent == root:
            mw = o.matrix_world.copy()
            saved.append((o, o.matrix_parent_inverse.copy(), o.matrix_basis.copy()))
            o.parent = None
            o.matrix_world = mw
    for o in extra:
        o.location -= origin
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    for o in objs + extra:
        o.select_set(True)
    props = bpy.ops.export_scene.gltf.get_rna_type().properties.keys()
    want = dict(export_format="GLB", use_selection=True, export_yup=True, export_apply=True,
                export_extras=True, export_lights=False, export_cameras=False,
                export_vertex_color="ACTIVE", export_all_vertex_colors=False,
                export_attributes=False, export_materials="EXPORT", export_texcoords=True)
    kw = {k: v for k, v in want.items() if k in props}
    missing = sorted(set(want) - set(kw))
    path = os.path.join(ROOT, "export", root_name + ".glb")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=path, **kw)
    for o in extra:
        o.location += origin
    root.location = origin
    for o, inv, basis in saved:
        o.parent = root
        o.matrix_parent_inverse = inv
        o.matrix_basis = basis
    for o, name in reversed(renamed):
        o.name = name
    for o in outlined:
        g["add_outline"](o, 0.06)
    set_preview_mods(objs, True)
    os.makedirs(GAME_DIR, exist_ok=True)
    shutil.copy(path, GAME_DIR)
    print("EXPORTED", path, "missing opts:", missing)
    return path


def render(name, cut_on, target=None, ortho=None):
    s = bpy.context.scene
    hull = bpy.data.objects["hull@wreck_core"]
    hull.modifiers["CUT_PREVIEW"].show_render = cut_on
    hull.modifiers["CUT_PREVIEW"].show_viewport = cut_on
    g["frame_camera"](s.camera, target or g["CAM_TARGET"], ortho or g["CAM_ORTHO"])
    s.render.filepath = os.path.join(ROOT, "renders", name)
    bpy.ops.render.render(write_still=True)
    print("RENDERED", name)


g["build"]()
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(ROOT, "station_early.blend"))
stats = {m: module_stats(c) for m, c in MODULES.items()}
print("STATS", json.dumps(stats, indent=1))
with open(os.path.join(ROOT, "export", "stats.json") if os.path.isdir(os.path.join(ROOT, "export"))
          else os.path.join(ROOT, "stats.json"), "w") as f:
    json.dump(stats, f, indent=1)
if "--no-export" not in ARGS:
    for m, c in MODULES.items():
        export_module(m, c)
    shutil.copy(os.path.join(ROOT, "export", "station_palette.png"), GAME_DIR)
if "--no-render" not in ARGS:
    only = [a.split("=", 1)[1] for a in ARGS if a.startswith("--only=")]
    jobs = [("render_closed.png", False, None, None), ("render_cut.png", True, None, None),
            ("render_roomA.png", True, g["ROOM_A_TARGET"], g["ROOM_A_ORTHO"])]
    for name, cut_on, t, o in jobs:
        if not only or name in only:
            render(name, cut_on, t, o)
    render_restore = g["frame_camera"](bpy.context.scene.camera, g["CAM_TARGET"], g["CAM_ORTHO"])
bpy.data.objects["hull@wreck_core"].modifiers["CUT_PREVIEW"].show_render = True
bpy.data.objects["hull@wreck_core"].modifiers["CUT_PREVIEW"].show_viewport = True
bpy.ops.wm.save_mainfile()
print("DONE")
