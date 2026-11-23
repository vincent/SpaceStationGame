#!/usr/bin/env python3
"""
migrate_webp.py - one-shot: convert art/paint PNGs made before the switch to WebP (idempotent).

    tools/paint/.venv/bin/python tools/paint/migrate_webp.py [art/paint]

cand*/<cfg>_<k>.png -> .webp q90 (+ meta.json file names), aligned*/*.png and paint_*.png -> .webp q90,
contact_*.png -> .jpg q85, renders (<cfg>_beauty/_plane/_faceid.png) -> LOSSLESS .webp (checked pixel-exact
before the PNG is removed: the id passes are decoded exactly).
"""
import glob, json, os, sys
from multiprocessing import Pool
import cv2

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
LOSSLESS = [cv2.IMWRITE_WEBP_QUALITY, 101]   # > 100 = lossless in OpenCV
RENDERS = ('_beauty.png', '_plane.png', '_faceid.png')


def convert(job):
    src, dst, params = job
    img = cv2.imread(src, cv2.IMREAD_UNCHANGED)
    assert img is not None, src
    assert cv2.imwrite(dst, img, params), dst
    if params == LOSSLESS:
        back = cv2.imread(dst, cv2.IMREAD_UNCHANGED)
        assert back is not None and back.shape == img.shape and (back == img).all(), 'not exact: ' + dst
    os.remove(src)
    return os.path.getsize(dst)


def main():
    base = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, 'art', 'paint')
    webp, jpg = [cv2.IMWRITE_WEBP_QUALITY, 90], [cv2.IMWRITE_JPEG_QUALITY, 85]
    jobs = []
    for d in glob.glob(os.path.join(base, '*', 'y*')):
        for p in glob.glob(os.path.join(d, 'cand*', '*.png')) + glob.glob(os.path.join(d, 'aligned*', '*.png')) \
                + glob.glob(os.path.join(d, 'paint_*.png')):
            jobs.append((p, p[:-4] + '.webp', webp))
        for p in glob.glob(os.path.join(d, 'contact_*.png')):
            jobs.append((p, p[:-4] + '.jpg', jpg))
        for p in glob.glob(os.path.join(d, '*.png')):
            if p.endswith(RENDERS):
                jobs.append((p, p[:-4] + '.webp', LOSSLESS))
    with Pool() as pool:
        total = sum(pool.map(convert, jobs, chunksize=4))
    for meta in glob.glob(os.path.join(base, '*', 'y*', 'cand*', 'meta.json')):
        text = open(meta).read()
        data = json.loads(text)
        for c in data.values():
            for e in c.get('candidates', []):
                if e.get('file', '').endswith('.png'):
                    e['file'] = e['file'][:-4] + '.webp'
        new = json.dumps(data, indent=1)
        if new != text:
            open(meta, 'w').write(new)
    print('migrate_webp: %d files, %.1f MB written' % (len(jobs), total / 1e6))


if __name__ == '__main__':
    main()
