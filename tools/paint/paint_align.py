#!/usr/bin/env python3
"""
paint_align.py - snap AI paintings back onto the geometry, score them, pick the best.

    tools/paint/.venv/bin/python tools/paint/paint_align.py <id> --yaw=<0|90|180|270> [--max-flow=12] [--pick=closed:2,cut:0]

For each configuration (closed, cut, interior) and each candidate in art/paint/<id>/y<yaw>/cand/ (.webp, or .png):
  1. geometry lines  = boundaries of <cfg>_plane.png (object/plane ids) + silhouette
  2. painting lines  = Canny edges of the candidate
  3. global ECC affine fit of the blurred painting lines onto the geometry lines
  4. local DIS optical flow (smoothed, capped at --max-flow px) for the remaining wobble
  5. score = symmetric mean chamfer distance (px) between the two line sets, inside the silhouette
Writes art/paint/<id>/y<yaw>/paint_<cfg>.webp (best or --pick, background bled outwards so mip-maps and
bilinear filtering never pull the backdrop onto the model), aligned/<cfg>_<k>.webp, contact_<cfg>.jpg
and align.json; the game atlas assets/models/modules/<id>_paint_<yaw>.webp (q90, Godot VRAM-compresses it
anyway) is built from the in-memory picks.
paint_*, aligned/ and contact_* are local only (gitignored): --skip-ai rebuilds them from cand/.
"""
import glob, json, os, sys
import cv2
import numpy as np

WEBP = [cv2.IMWRITE_WEBP_QUALITY, 90]   # intermediates and game atlas (Godot VRAM-compresses it anyway)

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def log(*a): print('PAINT', *a, flush=True)


def ids(img):
    q = np.clip(img.astype(np.int32) // 4, 0, 63)
    return q[..., 0] | (q[..., 1] << 6) | (q[..., 2] << 12)


def geometry(work, cfg):
    plane = ids(cv2.imread(os.path.join(work, cfg + '_plane.png')))
    mask = plane > 0
    e = np.zeros(plane.shape, bool)
    dx = plane[:, 1:] != plane[:, :-1]; dy = plane[1:, :] != plane[:-1, :]
    e[:, 1:] |= dx; e[:, :-1] |= dx; e[1:, :] |= dy; e[:-1, :] |= dy    # both sides: no half-pixel bias
    lines = e.astype(np.uint8) * 255
    return lines, mask


def edges(img):
    g = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    g = cv2.bilateralFilter(g, 7, 40, 7)
    return cv2.Canny(g, 40, 110)


def soft(e, s=5):
    return cv2.GaussianBlur(e.astype(np.float32) / 255.0, (0, 0), s)


def chamfer(a, b, mask):
    """mean distance a->b and b->a (px), restricted to the dilated silhouette."""
    m = cv2.dilate(mask.astype(np.uint8), np.ones((9, 9), np.uint8)) > 0
    da = cv2.distanceTransform((b == 0).astype(np.uint8), cv2.DIST_L2, 3)
    db = cv2.distanceTransform((a == 0).astype(np.uint8), cv2.DIST_L2, 3)
    pa = (a > 0) & m; pb = (b > 0) & m
    if pa.sum() == 0 or pb.sum() == 0:
        return 99.0
    return float((np.minimum(da[pa], 30).mean() + np.minimum(db[pb], 30).mean()) / 2)


def coverage(geo, ai, mask):
    """mean distance from each geometry line pixel to the nearest painted edge (px): are all the
    real edges drawn? Extra surface detail is not penalised (that direction is what we want)."""
    m = cv2.dilate(mask.astype(np.uint8), np.ones((9, 9), np.uint8)) > 0
    d = cv2.distanceTransform((ai == 0).astype(np.uint8), cv2.DIST_L2, 3)
    p = (geo > 0) & m
    return float(np.minimum(d[p], 30).mean()) if p.any() else 99.0


def silhouette_iou(img, mask, bg):
    """overlap of the painted object (pixels far from the background colour) with the model's."""
    diff = np.abs(img.astype(np.int32) - np.array(bg, np.int32)).sum(axis=2)
    sil = cv2.morphologyEx((diff > 40).astype(np.uint8), cv2.MORPH_OPEN, np.ones((5, 5), np.uint8)) > 0
    return float((sil & mask).sum() / max((sil | mask).sum(), 1))


def align(img, geo_lines, mask, max_flow):
    h, w = geo_lines.shape
    small = 0.5
    ge = cv2.resize(soft(geo_lines, 4), None, fx=small, fy=small)
    ae = cv2.resize(soft(edges(img), 4), None, fx=small, fy=small)
    warp = np.eye(2, 3, dtype=np.float32)
    try:
        _, warp = cv2.findTransformECC(ge, ae, warp, cv2.MOTION_AFFINE,
                                       (cv2.TERM_CRITERIA_EPS | cv2.TERM_CRITERIA_COUNT, 200, 1e-6), None, 5)
        warp[:, 2] /= small
    except cv2.error:
        warp = np.eye(2, 3, dtype=np.float32)
    img1 = cv2.warpAffine(img, warp, (w, h), flags=cv2.INTER_LINEAR | cv2.WARP_INVERSE_MAP,
                          borderMode=cv2.BORDER_REPLICATE)
    # local: flow from geometry lines to painting lines, sample the painting along it
    g8 = (soft(geo_lines, 2) * 255).clip(0, 255).astype(np.uint8)
    a8 = (soft(edges(img1), 2) * 255).clip(0, 255).astype(np.uint8)
    dis = cv2.DISOpticalFlow_create(cv2.DISOPTICAL_FLOW_PRESET_MEDIUM)
    flow = dis.calc(g8, a8, None)
    # trust the flow only near geometry lines, interpolate smoothly elsewhere (normalized convolution)
    wgt = soft(geo_lines, 1.5) * mask.astype(np.float32)
    flow = cv2.GaussianBlur(flow * wgt[..., None], (0, 0), 10) / np.maximum(cv2.GaussianBlur(wgt, (0, 0), 10), 1e-3)[..., None]
    mag = np.linalg.norm(flow, axis=2, keepdims=True)
    flow = flow * np.minimum(1.0, max_flow / np.maximum(mag, 1e-6))
    gx, gy = np.meshgrid(np.arange(w, dtype=np.float32), np.arange(h, dtype=np.float32))
    img2 = cv2.remap(img1, gx + flow[..., 0], gy + flow[..., 1], cv2.INTER_LINEAR, borderMode=cv2.BORDER_REPLICATE)
    if chamfer(edges(img2), geo_lines, mask) >= chamfer(edges(img1), geo_lines, mask):
        return img1, warp, 0.0          # local warp did not help: keep the global fit only
    return img2, warp, float(mag.max())


def bleed(img, mask, px=24):
    """Replace everything outside the silhouette by the nearest inside colour (px rings)."""
    out = img.copy(); m = mask.copy().astype(np.uint8)
    k = np.ones((3, 3), np.uint8)
    for _ in range(px):
        grown = cv2.dilate(m, k)
        ring = (grown > 0) & (m == 0)
        if not ring.any():
            break
        acc = cv2.blur(out.astype(np.float32) * m[..., None], (3, 3))
        cnt = cv2.blur(m.astype(np.float32), (3, 3))[..., None]
        out[ring] = (acc / np.maximum(cnt, 1e-6))[ring].astype(np.uint8)
        m = grown
    return out


def main():
    mid = sys.argv[1]
    opt = dict(a[2:].split('=', 1) for a in sys.argv[2:] if a.startswith('--') and '=' in a)
    max_flow = float(opt.get('max-flow', 12))
    pick = dict(p.split(':') for p in opt['pick'].split(',')) if 'pick' in opt else {}
    yaw = int(opt.get('yaw', 0))
    work = os.path.join(ROOT, 'art', 'paint', mid, 'y%d' % yaw)
    variant = opt.get('variant', '')
    if variant == 'default': variant = ''
    sfx = '_' + variant if variant else ''
    configs = json.load(open(os.path.join(work, 'camera.json'))).get('configs', ['closed', 'cut', 'interior'])
    adir = os.path.join(work, 'aligned' + sfx)
    os.makedirs(adir, exist_ok=True)
    report, final = {}, {}   # final: picked paintings kept in memory (lossless into the atlas)
    for cfg in configs:
        geo_lines, mask = geometry(work, cfg)
        cands = sorted(p for ext in ('png', 'webp') for p in glob.glob(os.path.join(work, 'cand' + sfx, cfg + '_*.' + ext)))
        if not cands:
            log(cfg, 'no candidates'); continue
        floor = chamfer(edges(cv2.imread(os.path.join(work, cfg + '_beauty.png'))), geo_lines, mask)
        log(cfg, 'chamfer floor (the render itself): %.2f px' % floor)
        rows, outs = [], {}
        for path in cands:
            k = os.path.splitext(os.path.basename(path))[0].split('_')[-1]
            img = cv2.imread(path)
            if img.shape[:2] != mask.shape:
                img = cv2.resize(img, (mask.shape[1], mask.shape[0]), interpolation=cv2.INTER_LANCZOS4)
            before = chamfer(edges(img), geo_lines, mask)
            out, warp, fmax = align(img, geo_lines, mask, max_flow)
            after = chamfer(edges(out), geo_lines, mask)
            if after > before:                       # alignment made it worse: keep the raw painting
                out, warp, fmax, after = img, np.eye(2, 3), 0.0, before
            # colour drift vs the render inside the silhouette (consistency between views)
            ref = cv2.imread(os.path.join(work, cfg + '_beauty.png'))
            drift = float(np.abs(cv2.blur(out, (31, 31)).astype(int) - cv2.blur(ref, (31, 31)).astype(int))[mask].mean())
            outs[k] = out
            cv2.imwrite(os.path.join(adir, '%s_%s.webp' % (cfg, k)), out, WEBP)
            cov = coverage(geo_lines, edges(out), mask)
            iou = silhouette_iou(out, mask, ref[2, 2].tolist())
            score = cov + 40.0 * (1.0 - iou)          # px-equivalent: lower is better
            rows.append(dict(k=k, score=round(score, 2), coverage=round(cov, 2), iou=round(iou, 3),
                             chamfer_before=round(before, 2), chamfer_after=round(after, 2),
                             affine=np.round(warp, 4).tolist(), flow_max=round(fmax, 1), colour_drift=round(drift, 1)))
            log(cfg, k, 'score %.2f (edges %.2f px, silhouette IoU %.3f) chamfer %.2f -> %.2f, drift %.1f'
                % (score, cov, iou, before, after, drift))
        best = pick.get(cfg) or min(rows, key=lambda r: r['score'])['k']
        final[cfg] = bleed(outs[best], mask)
        cv2.imwrite(os.path.join(work, 'paint_%s%s.webp' % (cfg, sfx)), final[cfg], WEBP)
        report[cfg] = dict(chamfer_floor=round(floor, 2), candidates=rows, picked=best)
        # contact sheet: candidate + geometry lines in red, score in the corner
        tiles = []
        for r in rows:
            t = outs[r['k']].copy()
            t[geo_lines > 0] = (0, 0, 255)
            t = cv2.resize(t, None, fx=0.5, fy=0.5, interpolation=cv2.INTER_AREA)
            label = '%s #%s  score %.1f  IoU %.2f%s' % (cfg, r['k'], r['score'], r['iou'],
                                                                 '  << PICK' if r['k'] == best else '')
            cv2.putText(t, label, (16, 40), cv2.FONT_HERSHEY_SIMPLEX, 1.1, (255, 255, 255), 3, cv2.LINE_AA)
            tiles.append(t)
        while len(tiles) % 2: tiles.append(np.zeros_like(tiles[0]))
        sheet = np.vstack([np.hstack(tiles[i:i + 2]) for i in range(0, len(tiles), 2)])
        cv2.imwrite(os.path.join(work, 'contact_%s%s.jpg' % (cfg, sfx)), sheet, [cv2.IMWRITE_JPEG_QUALITY, 85])
        log(cfg, 'picked', best)
    json.dump(report, open(os.path.join(work, 'align%s.json' % sfx), 'w'), indent=1)
    # atlas for the game: one row per configuration, closed / cut / interior (matches paint_blender)
    parts = [final[c] if c in final else cv2.imread(os.path.join(work, 'paint_%s%s.webp' % (c, sfx))) for c in configs]
    if all(p is not None for p in parts):
        atlas = os.path.join(ROOT, 'assets', 'models', 'modules', '%s_paint_%d%s.webp' % (mid, yaw, sfx))
        cv2.imwrite(atlas, np.vstack(parts), WEBP)
        log('atlas', os.path.relpath(atlas, ROOT), np.vstack(parts).shape[1::-1])


if __name__ == '__main__':
    main()
