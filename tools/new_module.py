#!/usr/bin/env python3
"""Creates or syncs the Godot side of a kit module from its sidecar
(art/modules/export/<id>.json, written by tools/art.sh <id>):

  data/modules/<id>.tres            created with placeholder gameplay values the first
                                    time; afterwards only layout, slots (new letters),
                                    slot_sizes, massing and slot_frames are synced
  src/station/modules/<id>.tscn     inherited scene of the .glb (created once; then
                                    interior_ascii is synced)
  assets/models/modules/*.import    import settings (module_import.gd, lossless palette)

Usage: tools/new_module.py <id> [--name="Display name"] [--description="..."]
Then: tools/import.sh && tools/test.sh. Gameplay values (costs, power, production,
what each slot accepts) are hand-edited in the .tres afterwards.
"""
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def godot_str(s):
    return s.replace("\\", "\\\\").replace('"', '\\"')


def node_name(mid):
    return "".join(w.capitalize() for w in mid.split("_"))


def fields(side):
    slots = side["slots"]
    sizes = {k: v for k, v in side["slot_sizes"].items() if v != 2}
    frames = ", ".join('&"%s": Vector3(%s, %s, %s)' % (k, *v) for k, v in slots.items())
    massing = ", ".join("Rect2(%s, %s, %s, %s)" % tuple(r) for r in side["massing"])
    out = {
        "layout": '"%s"' % godot_str(side["layout"]),
        "slot_frames": "Dictionary[StringName, Vector3]({%s})" % frames,
        "massing": "Array[Rect2]([%s])" % massing,
        "slot_sizes": "Dictionary[StringName, int]({%s})" % ", ".join(
            '&"%s": %d' % kv for kv in sorted(sizes.items())),
    }
    return out


def set_field(text, key, value):
    """Replace `key = ...` (value may span lines when it is a string) or append it."""
    pat = re.compile(r'^%s = (".*?(?<!\\)"|[^\n]*)$' % re.escape(key), re.M | re.S)
    if pat.search(text):
        return pat.sub(lambda _m: "%s = %s" % (key, value), text, count=1)
    return text.rstrip("\n") + "\n%s = %s\n" % (key, value)


def write_tres(mid, side, name, description):
    path = os.path.join(ROOT, "data", "modules", mid + ".tres")
    if not os.path.exists(path):
        accepts = ", ".join('&"%s": PackedStringArray("module")' % k for k in side["slots"])
        text = """[gd_resource type="Resource" script_class="ModuleDef" format=3]

[ext_resource type="Script" path="res://src/core/module_def.gd" id="1_def"]

[resource]
script = ExtResource("1_def")
id = &"%s"
display_name = "%s"
description = "%s"
scene_path = "res://src/station/modules/%s.tscn"
kind = &"module"
size_class = 2
buildable = true
build_cost = Dictionary[StringName, int]({&"scrap_metal": 5})
build_minutes = 120.0
repair_cost = Dictionary[StringName, int]({&"scrap_metal": 2})
power_output = 0.0
power_draw = 0.0
slots = Dictionary[StringName, PackedStringArray]({%s})
attach_slot = &"A"
""" % (mid, godot_str(name), godot_str(description), mid, accepts)
        print("created", os.path.relpath(path, ROOT))
    else:
        text = open(path).read()
        m = re.search(r"^slots = Dictionary\[StringName, PackedStringArray\]\(\{(.*)\}\)$", text, re.M)
        have = set(re.findall(r'&"(\w+)":', m.group(1))) if m else set()
        missing = [k for k in side["slots"] if k not in have]
        if m and missing:
            body = m.group(1) + "".join(', &"%s": PackedStringArray("module")' % k for k in missing)
            text = text.replace(m.group(0), "slots = Dictionary[StringName, PackedStringArray]({%s})"
                                % body.lstrip(", "))
        extra = sorted(have - set(side["slots"]))
        if extra:
            print("WARNING: %s declares slots the art doesn't have: %s" % (mid, extra))
        print("synced", os.path.relpath(path, ROOT))
    for k, v in fields(side).items():
        text = set_field(text, k, v)
    open(path, "w").write(text)


def write_scene(mid, side):
    path = os.path.join(ROOT, "src", "station", "modules", mid + ".tscn")
    ascii_ = '"%s"' % godot_str(side["layout"])
    if os.path.exists(path):
        text = set_field(open(path).read(), "interior_ascii", ascii_)
        open(path, "w").write(text)
        print("synced", os.path.relpath(path, ROOT))
        return
    open(path, "w").write("""[gd_scene format=3]

[ext_resource type="PackedScene" path="res://assets/models/modules/%s.glb" id="1_art"]
[ext_resource type="Script" path="res://src/station/module.gd" id="2_module"]
[ext_resource type="Texture2D" path="res://assets/models/modules/kit_palette.png" id="3_palette"]

[node name="%s" instance=ExtResource("1_art")]
script = ExtResource("2_module")
module_id = &"%s"
interior_ascii = %s
hull_color = Color(0.604, 0.561, 0.753, 1)
trim_color = Color(0.208, 0.173, 0.314, 1)
cap_tint = Color(0.937, 0.89, 1, 1)
light_color = Color(1, 0.816, 0.659, 1)
art_palette = ExtResource("3_palette")
""" % (mid, node_name(mid), mid, ascii_))
    print("created", os.path.relpath(path, ROOT))


def write_imports(mid):
    d = os.path.join(ROOT, "assets", "models", "modules")
    glb = os.path.join(d, mid + ".glb.import")
    if not os.path.exists(glb):
        open(glb, "w").write("""[remap]

importer="scene"
importer_version=1
type="PackedScene"

[deps]

source_file="res://assets/models/modules/%s.glb"

[params]

nodes/use_name_suffixes=true
meshes/ensure_tangents=true
meshes/generate_lods=true
meshes/create_shadow_meshes=true
import_script/path="res://src/tools/module_import.gd"
""" % mid)
        print("created", os.path.relpath(glb, ROOT))
    pal = os.path.join(d, "kit_palette.png.import")
    if not os.path.exists(pal):
        open(pal, "w").write("""[remap]

importer="texture"
type="CompressedTexture2D"

[deps]

source_file="res://assets/models/modules/kit_palette.png"

[params]

compress/mode=0
mipmaps/generate=false
detect_3d/compress_to=0
""")
        print("created", os.path.relpath(pal, ROOT))


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(2)
    mid = sys.argv[1]
    opts = dict(a[2:].split("=", 1) for a in sys.argv[2:] if a.startswith("--") and "=" in a)
    side_path = os.path.join(ROOT, "art", "modules", "export", mid + ".json")
    if not os.path.exists(side_path):
        sys.exit("no sidecar %s: run tools/art.sh %s first" % (side_path, mid))
    side = json.load(open(side_path))
    if side.get("errors"):
        sys.exit("the art has kit errors, fix them first: %s" % side["errors"])
    write_imports(mid)
    write_tres(mid, side, opts.get("name", mid.replace("_", " ").capitalize()), opts.get("description", ""))
    write_scene(mid, side)


if __name__ == "__main__":
    main()
