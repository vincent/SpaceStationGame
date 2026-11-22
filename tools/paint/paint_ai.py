#!/usr/bin/env python3
"""
paint_ai.py - AI paint-over of the render passes through OpenRouter (image output models).

    tools/paint/.venv/bin/python tools/paint/paint_ai.py <id> [--cfg=closed,cut,interior] [--n=4]
        [--model=google/gemini-2.5-flash-image] [--size=2K] [--dry-run] [--yaw=0]

Reads  art/paint/<id>/y<yaw>/<cfg>_beauty.png  (+ optional style refs in art/paint/style/*.png|jpg)
Writes art/paint/<id>/y<yaw>/cand/<cfg>_<k>.png and .../cand/meta.json
Needs OPENROUTER_API_KEY in the environment (never stored in the repo).
--dry-run writes the beauty render itself as candidates (tests the rest of the pipeline offline).
"""
import base64, json, os, sys, time
import cv2
import numpy as np
import requests

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
URL = 'https://openrouter.ai/api/v1/chat/completions'
RATIOS = ['1:1', '2:3', '3:2', '3:4', '4:3', '4:5', '5:4', '9:16', '16:9', '21:9']

STYLE = (
    "Repaint it as a finished 'ligne claire' science-fiction illustration (European bande dessinee): "
    "fine, even, black ink outlines on every silhouette, crease and panel edge; mostly flat colours "
    "with only one soft shade tone per surface; dense but small mechanical surface detail drawn ON the "
    "existing surfaces - panel seams, rivets, vents, hatches, small labels and stencilled numbers, "
    "decals, scuffs and light grime along edges. Keep the existing colour of every surface "
    "(ivory/off-white hull, navy blue details, mustard-gold trim bands, faded red stripe). "
    "Lights and screens glow (warm yellow / cyan).")
STRICT = (
    "STRICT RULES: this is a paint-over that will be projected back onto the 3D model, so keep the "
    "exact same framing, camera, perspective, silhouette and scale. Every edge, opening and shape "
    "must stay exactly where it is in the input; do not move, add or remove geometry or objects, "
    "do not extend anything beyond the existing silhouette. Surfaces that look opaque stay opaque: "
    "never make a panel transparent and never invent what is behind it. Keep the background a "
    "perfectly flat uniform dark navy (#1b1d30) with nothing on it - no stars, no shadow, no text, "
    "no border.")
VIEW = {
    'closed': "The input is a flat-shaded 3D render of one module of a space station, seen from the "
              "fixed game camera. The roof is an OPAQUE dark lilac canopy in a light frame: paint it as "
              "solid tinted panels with a soft reflection, nothing visible through it.",
    'cut': "The input is a flat-shaded 3D render of one module of a space station, seen from the fixed "
           "game camera, in a cutaway diorama view: the roof and the upper walls are sliced off at "
           "waist height so the room inside is visible (floor, consoles, table, tank, locker, crates). "
           "The flat pale-cream tops of the sliced walls are section cuts: keep them flat pale cream "
           "with a thin ink outline. The inside of the walls is plain: paint it, but do NOT add or "
           "redraw furniture - the furniture is painted separately.",
    'interior': "The input is a flat-shaded 3D render of the furniture of a small space-station cabin "
                "(floor plate, consoles, bench, table, tank, gas canisters, locker, crate, a screen), "
                "seen from the fixed game camera with the walls removed. Each object is a simple block "
                "and must stay EXACTLY that block: same outline, same faces, same size and place - "
                "do not replace it by a different object, do not add any object, cable or clutter. "
                "Only add drawn detail on its existing faces (buttons, gauges, handles, labels, panel "
                "lines, vents, wear), so it reads as that piece of furniture.",
}


def log(*a): print('PAINT', *a, flush=True)


def pad_to_ratio(img, bg):
    """Pad img to the nearest supported aspect ratio; returns padded image, ratio string, box."""
    h, w = img.shape[:2]
    best = min(RATIOS, key=lambda r: abs(np.log((int(r.split(':')[0]) / int(r.split(':')[1])) / (w / h))))
    a, b = map(int, best.split(':')); target = a / b
    if w / h < target: W, H = int(round(h * target)), h
    else: W, H = w, int(round(w / target))
    out = np.empty((H, W, 3), np.uint8); out[:] = bg
    x0, y0 = (W - w) // 2, (H - h) // 2
    out[y0:y0 + h, x0:x0 + w] = img
    return out, best, (x0, y0, w, h, W, H)


def data_url(img):
    ok, buf = cv2.imencode('.png', img); assert ok
    return 'data:image/png;base64,' + base64.b64encode(buf.tobytes()).decode()


def decode(url):
    raw = base64.b64decode(url.split(',', 1)[1])
    return cv2.imdecode(np.frombuffer(raw, np.uint8), cv2.IMREAD_COLOR)


def call(model, prompt, images, ratio, size, key):
    content = [{'type': 'text', 'text': prompt}] + [{'type': 'image_url', 'image_url': {'url': u}} for u in images]
    body = {'model': model, 'messages': [{'role': 'user', 'content': content}],
            'modalities': ['image', 'text'], 'usage': {'include': True},
            'image_config': {'aspect_ratio': ratio, **({'image_size': size} if size else {})}}
    for attempt in range(3):
        r = requests.post(URL, headers={'Authorization': 'Bearer ' + key, 'Content-Type': 'application/json',
                                        'X-Title': 'paint-projection-proto'}, json=body, timeout=300)
        if r.status_code == 200:
            js = r.json()
            msg = js['choices'][0]['message']
            imgs = msg.get('images') or []
            if imgs:
                return decode(imgs[0]['image_url']['url']), js.get('usage', {})
            log('no image in response:', (msg.get('content') or '')[:200])
        else:
            log('HTTP', r.status_code, r.text[:300])
        time.sleep(3 * (attempt + 1))
    return None, {}


def main():
    mid = sys.argv[1]
    opt = dict(a[2:].split('=', 1) if '=' in a else (a[2:], '1') for a in sys.argv[2:] if a.startswith('--'))
    cfgs = opt.get('cfg', 'closed,cut,interior').split(',')
    n = int(opt.get('n', 4)); model = opt.get('model', 'google/gemini-2.5-flash-image')
    size = opt.get('size', '2K') or None; dry = 'dry-run' in opt
    work = os.path.join(ROOT, 'art', 'paint', mid, 'y' + opt.get('yaw', '0')); cand = os.path.join(work, 'cand')
    os.makedirs(cand, exist_ok=True)
    key = os.environ.get('OPENROUTER_API_KEY')
    if not dry and not key:
        sys.exit('OPENROUTER_API_KEY is not set (or use --dry-run)')
    sdir = os.path.join(ROOT, 'art', 'paint', 'style')
    styles = sorted(os.path.join(sdir, f) for f in os.listdir(sdir)) if os.path.isdir(sdir) else []
    styles = [s for s in styles if s.lower().endswith(('.png', '.jpg', '.jpeg', '.webp'))][:5]
    meta_path = os.path.join(cand, 'meta.json')
    meta = json.load(open(meta_path)) if os.path.exists(meta_path) else {}
    for cfg in cfgs:
        src = cv2.imread(os.path.join(work, cfg + '_beauty.png'))
        bg = src[2, 2].tolist()
        padded, ratio, box = pad_to_ratio(src, bg)
        prompt = VIEW[cfg] + ' ' + STYLE + ' ' + STRICT
        if styles:
            prompt += (' The first image is the render to repaint; the following image(s) are STYLE '
                       'REFERENCES ONLY (line work, colouring and level of detail) - do not copy their content.')
        images = [data_url(padded)] + [data_url(cv2.imread(s)) for s in styles]
        entries = []
        for k in range(n):
            t0 = time.time()
            if dry:
                out, usage = padded.copy(), {'cost': 0}
            else:
                out, usage = call(model, prompt, images, ratio, size, key)
            if out is None:
                log(cfg, k, 'failed'); continue
            # back to the render frame: scale to the padded size, crop the padding
            x0, y0, w, h, W, H = box
            out = cv2.resize(out, (W, H), interpolation=cv2.INTER_LANCZOS4)[y0:y0 + h, x0:x0 + w]
            path = os.path.join(cand, '%s_%d.png' % (cfg, k))
            cv2.imwrite(path, out)
            entries.append(dict(file=os.path.basename(path), cost=usage.get('cost'), seconds=round(time.time() - t0, 1)))
            log(cfg, k, 'ok', entries[-1])
        meta[cfg] = dict(model='dry-run' if dry else model, ratio=ratio, prompt=prompt,
                         styles=[os.path.basename(s) for s in styles], candidates=entries)
    json.dump(meta, open(meta_path, 'w'), indent=1)
    total = sum((e['cost'] or 0) for c in meta.values() for e in c['candidates'])
    log('total cost (USD, as reported):', round(total, 4))


if __name__ == '__main__':
    main()
