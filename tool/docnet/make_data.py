"""Synthetic training data for DocNet (DocScanner's own document mask model).

Every image is generated here: procedural backgrounds (cloth, wood, desks,
walls with rails), procedural documents (printed pages, forms, ID and bank
cards, photo prints, receipts, coloured paper), random perspective, pages
running off the frame, shadows, uneven light, blur, noise and JPEG.
No real photos are used, so the data carries no personal information.

    python3 tool/docnet/make_data.py out.npz 8000 [seed]

Writes x: (N, 160, 160, 3) uint8 RGB and y: (N, 80, 80) uint8 {0, 1}.
"""
import sys

import cv2
import numpy as np

IN = 160
OUT = 80


def rand_color(rng, lo=0, hi=255):
    return tuple(float(v) for v in rng.uniform(lo, hi, 3))


def background(rng, w, h):
    kind = rng.choice(['cloth', 'wood', 'plain', 'desk', 'wall', 'blobs',
                       'tiles', 'fractal', 'fractal', 'bright'])
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    img = np.zeros((h, w, 3), np.float32)
    base = np.array(rand_color(rng, 20, 230), np.float32)
    img[:] = base
    if kind == 'cloth':
        f1, f2 = rng.uniform(1.2, 4), rng.uniform(1.5, 5)
        img += (np.sin(xx / f1 + yy / f2) * rng.uniform(6, 20))[..., None]
        if rng.random() < .5:
            acc = np.array(rand_color(rng), np.float32)
            for _ in range(int(w * h / rng.uniform(500, 2500))):
                cv2.ellipse(img, (int(rng.uniform(0, w)), int(rng.uniform(0, h))),
                            (int(rng.uniform(2, 12)), int(rng.uniform(2, 8))),
                            rng.uniform(0, 180), 0, 360, acc.tolist(), -1)
    elif kind == 'wood':
        grain = np.sin(yy / rng.uniform(3, 9) + np.sin(xx / rng.uniform(20, 60)) * 3)
        img += (grain * rng.uniform(8, 25))[..., None]
    elif kind == 'plain':
        img += (rng.normal(0, 3, (h, w)))[..., None]
    elif kind == 'desk':
        img *= (0.7 + 0.3 * (xx / w))[..., None]
        for _ in range(int(rng.integers(0, 4))):
            cv2.rectangle(img, (int(rng.uniform(0, w)), int(rng.uniform(0, h))),
                          (int(rng.uniform(0, w)), int(rng.uniform(0, h))),
                          rand_color(rng), -1)
    elif kind == 'wall':
        weave = np.sin(xx / 1.7 + yy / 2.3) * 12
        img += weave[..., None]
        for _ in range(int(rng.integers(1, 3))):
            y0 = int(rng.uniform(.2, .9) * h)
            th = int(rng.uniform(.015, .05) * h) + 1
            img[y0:y0 + th] = rand_color(rng, 170, 235)
    elif kind == 'blobs':
        for _ in range(int(rng.integers(5, 25))):
            cv2.circle(img, (int(rng.uniform(0, w)), int(rng.uniform(0, h))),
                       int(rng.uniform(5, w / 4)), rand_color(rng), -1)
        img = cv2.GaussianBlur(img, (0, 0), rng.uniform(1, 6))
    elif kind == 'fractal':
        # Natural-looking texture: noise summed over several scales.
        tex = np.zeros((h, w), np.float32)
        for octave in range(5):
            cell = 2 ** (octave + 2)
            small = rng.normal(0, 1, (h // cell + 2, w // cell + 2)).astype(np.float32)
            tex += cv2.resize(small, (w, h), interpolation=cv2.INTER_CUBIC) * (1.6 ** -octave)
        tint = np.array(rand_color(rng, 10, 60), np.float32) / 60
        img += tex[..., None] * rng.uniform(8, 30) * tint
    elif kind == 'bright':
        # Light table or bedsheet: little contrast with white paper.
        img[:] = rng.uniform(175, 235)
        img += (np.sin(xx / rng.uniform(2, 6)) * rng.uniform(0, 6))[..., None]
    elif kind == 'tiles':
        s = rng.uniform(20, 70)
        lines = ((np.mod(xx, s) < 2) | (np.mod(yy, s) < 2))[..., None]
        img = np.where(lines, img * .7, img)
    img += rng.normal(0, rng.uniform(2, 8), img.shape)
    return np.clip(img, 0, 255).astype(np.uint8)


FONTS = [cv2.FONT_HERSHEY_SIMPLEX, cv2.FONT_HERSHEY_DUPLEX,
         cv2.FONT_HERSHEY_COMPLEX, cv2.FONT_HERSHEY_TRIPLEX,
         cv2.FONT_HERSHEY_PLAIN]
LETTERS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 .,:()-/&'


def words(rng, n):
    return ''.join(rng.choice(list(LETTERS), n))


def text_lines(rng, p, x0, y0, x1, y1, color=(30, 30, 30)):
    """Printed text rows (real glyphs), sometimes a table around them."""
    font = int(rng.choice(FONTS))
    scale = rng.uniform(.22, .5)
    thick = 1 if scale < .4 or rng.random() < .7 else 2
    (_, th), _ = cv2.getTextSize('Ag', font, scale, thick)
    step = int(th * rng.uniform(1.6, 2.6)) + 1
    y = y0 + th
    table = rng.random() < .45
    cols = sorted(rng.uniform(x0, x1, int(rng.integers(2, 5)))) if table else []
    top = y - th - 3
    while y < y1:
        chars = int((x1 - x0) / max(4, th * .6) * rng.uniform(.4, 1))
        cv2.putText(p, words(rng, max(1, chars)), (x0 + 2, y), font, scale,
                    color, thick, cv2.LINE_AA)
        if table:
            cv2.line(p, (x0, y + step // 3), (x1, y + step // 3), color, 1)
        y += step
    if table:
        for x in [x0, x1] + list(cols):
            cv2.line(p, (int(x), top), (int(x), min(y1, y - step + step // 3)),
                     color, 1)


def marks(rng, p):
    """Handwriting, stamps, highlighter, staples."""
    h, w = p.shape[:2]
    for _ in range(int(rng.integers(0, 3))):
        pts = np.cumsum(rng.normal(0, 6, (int(rng.integers(5, 25)), 2)), 0)
        pts += [rng.uniform(0, w), rng.uniform(0, h)]
        cv2.polylines(p, [pts.astype(np.int32)], False,
                      rand_color(rng, 0, 160), int(rng.integers(1, 3)), cv2.LINE_AA)
    if rng.random() < .2:
        c = (int(rng.uniform(0, w)), int(rng.uniform(0, h)))
        cv2.circle(p, c, int(rng.uniform(15, 40)), rand_color(rng, 0, 200), 2)
    if rng.random() < .15:
        y = int(rng.uniform(0, h))
        p[y:y + 8] = (p[y:y + 8] * np.array(rand_color(rng, 150, 255)) / 255).astype(np.uint8)


def paper_colour(rng):
    v = rng.uniform(200, 252)
    tint = rng.normal(0, 4, 3)
    return tuple(float(np.clip(v + t, 0, 255)) for t in tint)


def document(rng):
    kind = rng.choice(['page', 'page', 'page', 'form', 'id', 'bank', 'photo',
                       'receipt', 'colour', 'notebook'])
    if kind in ('page', 'form', 'colour', 'notebook'):
        w = int(rng.uniform(300, 420))
        h = int(w * rng.uniform(1.25, 1.5))
        if rng.random() < .25:
            w, h = h, w
        paper = paper_colour(rng) if kind != 'colour' else rand_color(rng, 150, 250)
        p = np.zeros((h, w, 3), np.uint8)
        p[:] = paper
        if kind == 'notebook':
            for y in range(int(h * .1), h, max(6, h // 30)):
                cv2.line(p, (0, y), (w, y), (200, 170, 140), 1)
        mx = int(w * rng.uniform(.04, .12))
        y = int(h * rng.uniform(.03, .1))
        while y < h * .9:
            block = int(h * rng.uniform(.08, .35))
            if rng.random() < .5:  # heading
                cv2.putText(p, words(rng, int(rng.integers(8, 30))), (mx, y + 10),
                            int(rng.choice(FONTS)), rng.uniform(.35, .6),
                            (20, 20, 20), 2, cv2.LINE_AA)
                y += 18
            text_lines(rng, p, mx, y, w - mx, min(int(h * .96), y + block))
            y += block + int(h * rng.uniform(.02, .08))
        marks(rng, p)
        if rng.random() < .2:  # dark header band
            p[:int(h * .08)] = rand_color(rng, 10, 120)
        return p
    if kind == 'receipt':
        w = int(rng.uniform(120, 180))
        h = int(w * rng.uniform(2, 3.5))
        p = np.zeros((h, w, 3), np.uint8)
        p[:] = paper_colour(rng)
        text_lines(rng, p, 8, 10, w - 8, h - 10)
        return p
    if kind == 'id':
        w = int(rng.uniform(300, 420))
        h = int(w / 1.585)
        if rng.random() < .3:
            w, h = h, w
        c = np.zeros((h, w, 3), np.uint8)
        c[:] = rand_color(rng, 150, 250)
        band = int(h * rng.uniform(.2, .6))
        c[:band] = rand_color(rng, 10, 200)
        cv2.rectangle(c, (int(w * .06), int(h * .25)), (int(w * .32), int(h * .85)),
                      rand_color(rng, 60, 200), -1)
        text_lines(rng, c, int(w * .38), int(h * .3), int(w * .94), int(h * .9))
        return c
    if kind == 'bank':
        w = int(rng.uniform(300, 420))
        h = int(w / 1.585)
        a = np.array(rand_color(rng, 10, 240), np.float32)
        b = np.array(rand_color(rng, 10, 240), np.float32)
        t = np.linspace(0, 1, w)[None, :, None]
        c = (a * (1 - t) + b * t).repeat(h, 0).astype(np.uint8)
        cv2.rectangle(c, (int(w * .1), int(h * .35)), (int(w * .22), int(h * .52)),
                      (200, 170, 60), -1)
        text_lines(rng, c, int(w * .08), int(h * .68), int(w * .8), int(h * .78),
                   (235, 235, 235))
        return c
    w = int(rng.uniform(250, 380))
    h = int(w * rng.uniform(1.2, 1.5))
    c = background(rng, w, h)
    border = int(w * rng.uniform(.03, .07))
    if border:
        c[:border] = c[-border:] = 250
        c[:, :border] = c[:, -border:] = 250
    return c


def random_quad(rng):
    """Normalised TL, TR, BR, BL, sometimes running off the frame."""
    size = rng.uniform(.25, 1.0)
    cx, cy = rng.uniform(.3, .7), rng.uniform(.3, .7)
    ar = rng.uniform(.6, 1.5)
    hw, hh = size / 2 * np.sqrt(ar), size / 2 / np.sqrt(ar)
    if rng.random() < .4:  # fill the frame, run off edges
        hw, hh = rng.uniform(.4, .65), rng.uniform(.42, .7)
    pts = np.array([[cx - hw, cy - hh], [cx + hw, cy - hh],
                    [cx + hw, cy + hh], [cx - hw, cy + hh]])
    ang = rng.uniform(-.5, .5) if rng.random() < .6 else rng.uniform(-.12, .12)
    rot = np.array([[np.cos(ang), -np.sin(ang)], [np.sin(ang), np.cos(ang)]])
    pts = (pts - [cx, cy]) @ rot.T + [cx, cy]
    pts += rng.normal(0, .03 * size, pts.shape)  # perspective
    return pts


def bend(rng, obj):
    """Curl or bow the sheet: rows shift by a smooth function of x and y.
    Returns the bent sheet and its mask (padding is transparent)."""
    oh, ow = obj.shape[:2]
    amp = rng.uniform(.01, .05) * oh * rng.choice([-1, 1])
    pad = int(abs(amp)) + 2
    yy, xx = np.mgrid[0:oh + 2 * pad, 0:ow].astype(np.float32)
    u = xx / ow
    v = (yy - pad) / oh
    if rng.random() < .5:
        d = amp * np.sin(np.pi * u) * (0.2 + 0.8 * v ** 2)   # curl at the bottom
    else:
        d = amp * (np.abs(2 * u - 1) ** 2 - 1) * (0.5 + 0.5 * v)  # book page
    src_y = ((yy - pad) - d).astype(np.float32)
    bent = cv2.remap(obj, xx, src_y, cv2.INTER_LINEAR,
                     borderMode=cv2.BORDER_CONSTANT, borderValue=0)
    mask = cv2.remap(np.full((oh, ow), 255, np.uint8), xx, src_y, cv2.INTER_NEAREST,
                     borderMode=cv2.BORDER_CONSTANT, borderValue=0)
    return bent, mask, pad


def place(rng, bg, obj, quad, allow_bend=False):
    h, w = bg.shape[:2]
    obj_mask = None
    pad = 0
    if allow_bend and rng.random() < .3:
        obj, obj_mask, pad = bend(rng, obj)
    if rng.random() < .5:  # crumpled / uneven paper shading
        oh_, ow_ = obj.shape[:2]
        low = cv2.resize(rng.normal(0, 1, (6, 6)).astype(np.float32), (ow_, oh_),
                         interpolation=cv2.INTER_CUBIC)
        obj = np.clip(obj.astype(np.float32) * (1 + rng.uniform(.02, .08) * low[..., None]),
                      0, 255).astype(np.uint8)
    oh, ow = obj.shape[:2]
    src = np.float32([[0, pad], [ow, pad], [ow, oh - pad], [0, oh - pad]])
    dst = np.float32(quad * [w, h])
    m = cv2.getPerspectiveTransform(src, dst)
    warped = cv2.warpPerspective(obj, m, (w, h), flags=cv2.INTER_LINEAR)
    if obj_mask is None:
        obj_mask = np.full((oh, ow), 255, np.uint8)
    mask = cv2.warpPerspective(obj_mask, m, (w, h))
    out = bg.astype(np.float32)
    if rng.random() < .7:
        sh = cv2.GaussianBlur(mask, (0, 0), rng.uniform(3, 15)).astype(np.float32) / 255
        sh = np.roll(sh, (int(rng.uniform(-10, 14)), int(rng.uniform(-10, 14))), (0, 1))
        out *= (1 - rng.uniform(.1, .5) * sh)[..., None]
    a = (cv2.GaussianBlur(mask, (3, 3), 0).astype(np.float32) / 255)[..., None]
    out = out * (1 - a) + warped.astype(np.float32) * a
    return out, mask


def clutter(rng, img):
    """Pens, phones, coins and cables around (and over) the document."""
    h, w = img.shape[:2]
    for _ in range(int(rng.integers(0, 4))):
        kind = rng.choice(['pen', 'phone', 'coin', 'cable'])
        color = rand_color(rng, 0, 255) if kind != 'phone' else rand_color(rng, 5, 40)
        if kind == 'pen':
            p0 = (int(rng.uniform(0, w)), int(rng.uniform(0, h)))
            ang = rng.uniform(0, np.pi)
            ln = rng.uniform(.15, .4) * w
            p1 = (int(p0[0] + ln * np.cos(ang)), int(p0[1] + ln * np.sin(ang)))
            cv2.line(img, p0, p1, color, int(rng.integers(4, 10)), cv2.LINE_AA)
        elif kind == 'phone':
            cx, cy = rng.uniform(0, w), rng.uniform(0, h)
            box = cv2.boxPoints(((cx, cy), (rng.uniform(.1, .2) * w, rng.uniform(.2, .35) * h),
                                 rng.uniform(0, 180)))
            cv2.fillPoly(img, [box.astype(np.int32)], color)
        elif kind == 'coin':
            cv2.circle(img, (int(rng.uniform(0, w)), int(rng.uniform(0, h))),
                       int(rng.uniform(.02, .05) * w), color, -1, cv2.LINE_AA)
        else:
            pts = np.cumsum(rng.normal(0, 25, (12, 2)), 0) + [rng.uniform(0, w), rng.uniform(0, h)]
            cv2.polylines(img, [pts.astype(np.int32)], False, color, int(rng.integers(2, 6)),
                          cv2.LINE_AA)
    return img


def sample(rng):
    aspect = rng.choice([4 / 3, 16 / 9, 3 / 4, 9 / 16, 1.0])
    w = 480 if aspect >= 1 else int(480 * aspect)
    h = int(w / aspect) if aspect >= 1 else 480
    bg = background(rng, w, h).astype(np.float32)
    # A distractor sheet behind the document sometimes.
    if rng.random() < .35:
        other = document(rng)
        bg, _ = place(rng, bg.astype(np.uint8), other, random_quad(rng) + rng.uniform(-.4, .4, 2))
    doc = document(rng)
    quad = random_quad(rng)
    if rng.random() < .3:
        bg = clutter(rng, bg)
    img, mask = place(rng, bg.astype(np.uint8), doc, quad, allow_bend=True)
    if rng.random() < .15:  # something lying on the page edge
        img = clutter(rng, img)
    # Lighting, colour temperature, shadow band.
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    light = 1 - rng.uniform(0, .45) * ((xx / w - rng.uniform(0, 1)) ** 2 +
                                       (yy / h - rng.uniform(0, 1)) ** 2)
    img *= light[..., None]
    img *= np.array(rng.uniform(.92, 1.06, 3), np.float32)
    img *= rng.uniform(.55, 1.15)
    if rng.random() < .3:
        x0 = rng.uniform(0, w)
        band = np.clip((xx - x0) / rng.uniform(20, 120), 0, 1)
        img *= (1 - rng.uniform(.2, .5) * (1 - band))[..., None]
    if rng.random() < .25:  # washed-out / greyish phone photo
        grey = img.mean(2, keepdims=True)
        img = img * .4 + grey * .6
    img = 255 * (np.clip(img, 0, 255) / 255) ** rng.uniform(.7, 1.4)
    if rng.random() < .4:  # lens vignetting
        r2 = ((xx / w - .5) ** 2 + (yy / h - .5) ** 2) * 2
        img *= (1 - rng.uniform(.1, .35) * r2)[..., None]
    img = cv2.GaussianBlur(img, (0, 0), rng.uniform(.3, 1.8))
    if rng.random() < .15:  # hand shake
        k = int(rng.integers(3, 9))
        kernel = np.zeros((k, k), np.float32)
        kernel[k // 2] = 1.0 / k
        rot = cv2.getRotationMatrix2D((k / 2 - .5, k / 2 - .5), rng.uniform(0, 180), 1)
        kernel = cv2.warpAffine(kernel, rot, (k, k))
        kernel /= max(kernel.sum(), 1e-6)
        img = cv2.filter2D(img, -1, kernel)
    img += rng.normal(0, rng.uniform(1, 6), img.shape)
    img = np.clip(img, 0, 255).astype(np.uint8)
    ok, enc = cv2.imencode('.jpg', img, [cv2.IMWRITE_JPEG_QUALITY, int(rng.uniform(55, 95))])
    img = cv2.imdecode(enc, cv2.IMREAD_COLOR)
    x = cv2.resize(img, (IN, IN), interpolation=cv2.INTER_AREA)
    y = (cv2.resize(mask, (OUT, OUT), interpolation=cv2.INTER_AREA) > 127).astype(np.uint8)
    return x[..., ::-1], y  # BGR → RGB


def main():
    out, n = sys.argv[1], int(sys.argv[2])
    rng = np.random.default_rng(int(sys.argv[3]) if len(sys.argv) > 3 else 1)
    xs = np.zeros((n, IN, IN, 3), np.uint8)
    ys = np.zeros((n, OUT, OUT), np.uint8)
    for i in range(n):
        xs[i], ys[i] = sample(rng)
    np.savez_compressed(out, x=xs, y=ys)
    print('wrote', n, 'samples to', out)


if __name__ == '__main__':
    main()
