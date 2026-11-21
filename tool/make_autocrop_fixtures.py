#!/usr/bin/env python3
"""Synthetic photos for the on-device auto-crop check.

Each scene copies a situation users reported (paper on patterned cloth,
an ID card with a dark top half on a busy cloth, a small card on dark
cloth, a dark photo print, a bank card on pink cloth). No real documents
or faces are used, so the fixtures can live in the public repository.

Writes integration_test/autocrop_fixture_data.dart (generated in CI, not
committed): every scene as base64 JPEG plus its true corner positions
(normalized, clockwise from top-left). With --jpg DIR it also writes the
JPEGs for viewing.
"""
import base64
import math
import os
import sys

import cv2
import numpy as np

OUT = os.path.join(os.path.dirname(__file__), '..', 'integration_test',
                   'autocrop_fixture_data.dart')
rng = np.random.default_rng(20261120)


def cloth(w, h, base, accent, accent2, kind):
    img = np.zeros((h, w, 3), np.float32)
    img[:] = base
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    if kind == 'paisley':
        for _ in range(int(w * h / 900)):
            cx, cy = rng.uniform(0, w), rng.uniform(0, h)
            r = rng.uniform(4, 14)
            color = accent if rng.random() < .6 else accent2
            cv2.ellipse(img, (int(cx), int(cy)), (int(r), int(r * .6)),
                        rng.uniform(0, 180), 0, 360, color, -1)
        stripes = (np.sin((xx + yy) / 18.0) > .85)[..., None]
        img = np.where(stripes, np.array(accent2, np.float32), img)
    elif kind == 'denim':
        weave = (np.sin(xx / 1.7 + yy / 2.3) * 14 + np.sin(yy / 3.1) * 8)
        img += weave[..., None]
    elif kind == 'plaid':
        bands = ((np.sin(xx / 25) > .6) | (np.sin(yy / 25) > .6))[..., None]
        img = np.where(bands, np.array(accent, np.float32), img)
        img += (np.sin(xx / 2.0) * 6)[..., None]
    elif kind == 'floral':
        # Light satin bedsheet with maroon/pink flowers and a maroon
        # diagonal border (reference screenshot 386535), plus a pale blue
        # pillow on the left.
        img += (np.sin(xx / 3.0 + yy / 5.0) * 6)[..., None]
        for _ in range(int(w * h / 5000)):
            cx, cy = rng.uniform(0, w), rng.uniform(0, h)
            r = rng.uniform(10, 34)
            for k in range(6):
                ang = k * np.pi / 3 + rng.uniform(0, .5)
                px, py = cx + np.cos(ang) * r * .6, cy + np.sin(ang) * r * .6
                cv2.ellipse(img, (int(px), int(py)), (int(r * .55), int(r * .3)),
                            np.degrees(ang), 0, 360, accent, 2)
            cv2.circle(img, (int(cx), int(cy)), int(r * .25), accent2, -1)
        for off in (-.2, .25):
            band = np.abs((xx - yy * .45) / w - .55 - off) < .025
            img[band] = accent
            dots = band & (np.sin(yy / 6) > .6)
            img[dots] = (210, 200, 230)
        pillow = xx < w * .28 + (yy - h * .5) * .08
        img[pillow] = (225, 200, 175)
        img[pillow] += (np.sin(yy[pillow] / 9) * 5)[..., None]
    elif kind == 'dark':
        img += (np.sin(xx / 6 + np.sin(yy / 11) * 3) * 18)[..., None]
        for _ in range(60):
            cv2.circle(img, (int(rng.uniform(0, w)), int(rng.uniform(0, h))),
                       int(rng.uniform(6, 26)), accent, 2)
    img += rng.normal(0, 6, img.shape)
    return np.clip(img, 0, 255).astype(np.uint8)


def page(w, h):
    p = np.full((h, w, 3), 246, np.uint8)
    y = int(h * .07)
    cv2.putText(p, 'Settlement and Dispute Management', (int(w * .08), y),
                cv2.FONT_HERSHEY_SIMPLEX, w / 1100, (30, 30, 30), 2)
    for block in range(3):
        top = y + int(h * .05) + block * int(h * .3)
        rows = 7
        for r in range(rows + 1):
            yy = top + r * int(h * .03)
            cv2.line(p, (int(w * .08), yy), (int(w * .92), yy), (40, 40, 40), 1)
        for x in (.08, .18, .36, .75, .92):
            cv2.line(p, (int(w * x), top), (int(w * x), top + rows * int(h * .03)),
                     (40, 40, 40), 1)
        for r in range(rows):
            yy = top + r * int(h * .03) + int(h * .022)
            cv2.putText(p, f'0{r + 1}   12{r}4   Mr. Name Surname {r}   SO',
                        (int(w * .1), yy), cv2.FONT_HERSHEY_SIMPLEX, w / 2000,
                        (25, 25, 25), 1)
    return p


def id_card(w, h):
    c = np.full((h, w, 3), 238, np.uint8)
    top = int(h * .58)
    c[:top] = (70, 40, 20)  # dark navy (BGR)
    for _ in range(140):
        cv2.circle(c, (int(rng.uniform(w * .45, w)), int(rng.uniform(0, top))),
                   int(rng.uniform(2, 6)), (120, 170, 140), -1)
    cv2.rectangle(c, (int(w * .08), int(h * .2)), (int(w * .55), top),
                  (170, 90, 40), -1)
    cv2.circle(c, (int(w * .31), int(h * .36)), int(w * .1), (90, 110, 150), -1)
    for i, t in enumerate(['MD NAME SURNAME', 'DEPUTY OFFICER', 'BRANCH']):
        cv2.putText(c, t, (int(w * .06), top + int(h * (.08 + i * .06))),
                    cv2.FONT_HERSHEY_SIMPLEX, w / 900, (40, 40, 40), 2)
    return c


def bank_card(w, h):
    c = np.zeros((h, w, 3), np.uint8)
    for x in range(w):
        t = x / w
        c[:, x] = (150 - 60 * t, 110 - 40 * t, 70)
    cv2.rectangle(c, (int(w * .1), int(h * .35)), (int(w * .22), int(h * .52)),
                  (60, 170, 200), -1)
    cv2.putText(c, '1234 5678 9012 3456', (int(w * .08), int(h * .72)),
                cv2.FONT_HERSHEY_SIMPLEX, w / 700, (235, 235, 235), 2)
    return c


def business_card(w, h):
    c = np.full((h, w, 3), 244, np.uint8)
    cv2.circle(c, (w // 2, int(h * .22)), int(h * .13), (60, 60, 60), 3)
    cv2.circle(c, (w // 2, int(h * .22)), int(h * .06), (60, 60, 60), -1)
    lines = ['Md. Name Surname', 'Deputy Junior Officer', 'BANK PLC.',
             'Mobile : 01325-053260', 'E-mail : name@example.com']
    for i, t in enumerate(lines):
        cv2.putText(c, t, (int(w * .08), int(h * (.48 + i * .1))),
                    cv2.FONT_HERSHEY_SIMPLEX, w / 1100, (35, 35, 35), 2)
    return c


def driver_license(w, h):
    c = np.zeros((h, w, 3), np.uint8)
    for y in range(h):
        t = y / h
        c[y, :] = (235 - 30 * t, 215 - 10 * t, 205 + 20 * t)
    c[:int(h * .16)] = (120, 60, 30)
    cv2.putText(c, 'DRIVING LICENCE', (int(w * .06), int(h * .11)),
                cv2.FONT_HERSHEY_SIMPLEX, w / 900, (240, 240, 240), 2)
    cv2.rectangle(c, (int(w * .06), int(h * .24)), (int(w * .3), int(h * .78)),
                  (150, 160, 175), -1)
    for i in range(6):
        cv2.putText(c, f'{i + 1}. FIELD VALUE {i * 37}',
                    (int(w * .36), int(h * (.3 + i * .09))),
                    cv2.FONT_HERSHEY_SIMPLEX, w / 1500, (40, 40, 40), 1)
    return c


def photo_print(w, h):
    c = np.full((h, w, 3), 250, np.uint8)
    inner = (int(w * .04), int(h * .04), int(w * .96), int(h * .96))
    c[inner[1]:inner[3], inner[0]:inner[2]] = (55, 45, 40)
    cv2.ellipse(c, (w // 2, int(h * .42)), (int(w * .2), int(h * .22)), 0, 0, 360,
                (120, 150, 190), -1)
    cv2.rectangle(c, (int(w * .2), int(h * .65)), (int(w * .8), int(h * .96)),
                  (30, 30, 30), -1)
    return c


def place(bg, obj, quad, shadow=0.0, blur=1.0):
    h, w = bg.shape[:2]
    oh, ow = obj.shape[:2]
    src = np.float32([[0, 0], [ow, 0], [ow, oh], [0, oh]])
    dst = np.float32([[x * w, y * h] for x, y in quad])
    m = cv2.getPerspectiveTransform(src, dst)
    warped = cv2.warpPerspective(obj, m, (w, h))
    mask = cv2.warpPerspective(np.full((oh, ow), 255, np.uint8), m, (w, h))
    out = bg.astype(np.float32)
    if shadow:
        sh = cv2.GaussianBlur(mask, (0, 0), 9).astype(np.float32) / 255
        sh = np.roll(sh, (8, 6), (0, 1))
        out *= (1 - shadow * sh)[..., None]
    a = (cv2.GaussianBlur(mask, (3, 3), 0).astype(np.float32) / 255)[..., None]
    out = out * (1 - a) + warped.astype(np.float32) * a
    # uneven light like a phone photo
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    light = 1 - .18 * ((xx / w - .3) ** 2 + (yy / h - .2) ** 2)
    out *= light[..., None]
    out = cv2.GaussianBlur(out, (0, 0), blur)
    out += rng.normal(0, 3, out.shape)
    return np.clip(out, 0, 255).astype(np.uint8)


SCENES = []
QR_TEXT = 'https://docscanner.example/qr-check?id=42'


def clip_bottom(quad):
    """Visible part of a quad whose bottom corners lie below the frame."""
    (x0, y0), (x1, y1), (x2, y2), (x3, y3) = quad

    def at_bottom(ax, ay, bx, by):
        t = (1 - ay) / (by - ay)
        return (ax + (bx - ax) * t, 1.0)

    return [(x0, y0), (x1, y1), at_bottom(x1, y1, x2, y2),
            at_bottom(x0, y0, x3, y3)]


def clip_right_bottom(quad):
    """Visible part of a quad that runs off the right and bottom edges."""
    (x0, y0), (x1, y1), _, (x3, y3) = quad

    def at(ax, ay, bx, by, x=None, y=None):
        t = (x - ax) / (bx - ax) if x is not None else (y - ay) / (by - ay)
        return (ax + (bx - ax) * t, ay + (by - ay) * t)

    top_right = at(x0, y0, x1, y1, x=1.0)
    bottom_left = at(x0, y0, x3, y3, y=1.0)
    return [(x0, y0), top_right, (1.0, 1.0), bottom_left]


def clip_top_bottom(quad):
    """Visible part of a quad that runs off the top and bottom edges."""
    (x0, y0), (x1, y1), (x2, y2), (x3, y3) = quad

    def at(ax, ay, bx, by, y):
        t = (y - ay) / (by - ay)
        return (ax + (bx - ax) * t, y)

    return [at(x0, y0, x3, y3, 0.0), at(x1, y1, x2, y2, 0.0),
            at(x1, y1, x2, y2, 1.0), at(x0, y0, x3, y3, 1.0)]


def scene(name, bg, obj, quad, **kw):
    SCENES.append((name, place(bg, obj, quad, **kw), quad))


def main():
    W, H = 900, 1200
    scene('paper_on_denim', cloth(W, H, (120, 80, 50), (0, 0, 0), (0, 0, 0), 'denim'),
          page(820, 1160),
          [(.08, .14), (.93, .10), (.95, .86), (.05, .90)], shadow=.35)
    scene('dark_top_id_card_on_paisley',
          cloth(W, H, (120, 160, 195), (60, 90, 170), (70, 70, 120), 'paisley'),
          id_card(540, 860),
          [(.36, .27), (.73, .28), (.72, .70), (.34, .69)], shadow=.25)
    scene('white_card_on_dark_cloth',
          cloth(W, H, (60, 30, 45), (90, 50, 110), (0, 0, 0), 'dark'),
          id_card(860, 540)[:, :, :] * 0 + np.uint8(240),
          [(.12, .30), (.55, .27), (.57, .52), (.13, .55)], shadow=.2)
    scene('photo_print_on_cloth',
          cloth(W, H, (95, 110, 170), (60, 60, 140), (40, 40, 90), 'paisley'),
          photo_print(560, 720),
          [(.25, .22), (.74, .20), (.77, .78), (.23, .80)], shadow=.3)
    scene('bank_card_on_pink_plaid',
          cloth(W, H, (150, 120, 200), (110, 80, 170), (0, 0, 0), 'plaid'),
          bank_card(860, 540),
          [(.16, .38), (.83, .33), (.86, .63), (.18, .69)], shadow=.2)

    # Harder scenes, closer to the 386418 video: a landscape phone photo of
    # a sheet that nearly fills the frame and runs off the bottom edge, a
    # white page on a light table, a creased page, and a small receipt.
    w2, h2 = 1280, 720
    bg = cloth(w2, h2, (120, 80, 50), (0, 0, 0), (0, 0, 0), 'denim')
    bg[int(h2 * .8):] = (bg[int(h2 * .8):] * .35).astype(np.uint8)
    cut = [(.06, .04), (.97, .02), (.99, 1.10), (.04, 1.12)]
    scene('page_runs_off_bottom', bg, page(1100, 1000), cut, shadow=.3)
    SCENES[-1] = (SCENES[-1][0], SCENES[-1][1], clip_bottom(cut))
    # 386450/386455: phone photos where the sheet fills the frame and runs
    # off two edges, with a strip of cloth on the other sides.
    bg = cloth(w2, h2, (110, 75, 45), (0, 0, 0), (0, 0, 0), 'denim')
    off2 = [(.07, .06), (1.12, .02), (1.15, 1.2), (.05, 1.18)]
    scene('page_off_right_and_bottom', bg, page(1100, 1000), off2, shadow=.25)
    SCENES[-1] = (SCENES[-1][0], SCENES[-1][1], clip_right_bottom(off2))
    bg = cloth(W, H, (70, 60, 120), (40, 40, 90), (60, 50, 110), 'paisley')
    big = [(.04, .05), (1.10, .03), (1.12, 1.15), (.03, 1.12)]
    gray = (page(820, 1160).astype(np.float32) * .78).astype(np.uint8)
    scene('dim_page_fills_frame', bg, gray, big, shadow=.2)
    SCENES[-1] = (SCENES[-1][0], SCENES[-1][1], clip_right_bottom(big))
    scene('white_page_on_light_table',
          cloth(W, H, (196, 204, 210), (0, 0, 0), (0, 0, 0), 'denim')
          * 0 + np.uint8(200) + rng.normal(0, 4, (H, W, 3)).astype(np.uint8),
          page(820, 1160),
          [(.10, .09), (.90, .12), (.88, .91), (.08, .88)], shadow=.15)
    creased = page(820, 1160)
    creased[560:600] = (creased[560:600] * np.linspace(.7, 1, 40)[:, None, None]
                        ).astype(np.uint8)
    scene('creased_page_on_paisley',
          cloth(W, H, (120, 160, 195), (60, 90, 170), (70, 70, 120), 'paisley'),
          creased, [(.12, .12), (.86, .08), (.90, .88), (.10, .92)], shadow=.3)
    scene('small_receipt_on_plaid',
          cloth(W, H, (60, 90, 140), (40, 60, 100), (0, 0, 0), 'plaid'),
          page(400, 700), [(.40, .36), (.62, .35), (.63, .70), (.41, .71)],
          shadow=.25)

    # Card templates on a floral bedsheet (screenshot 386535): General
    # (business card), ID card, driver licence and bank card, held inside
    # the camera's card frame with some tilt.
    sheet = lambda: cloth(900, 1200, (200, 205, 212), (70, 40, 140),
                          (150, 110, 200), 'floral')
    scene('id_card_on_floral_sheet', sheet(), id_card(856, 540),
          [(.10, .33), (.90, .31), (.92, .62), (.08, .64)], shadow=.25)
    scene('driver_license_on_floral_sheet', sheet(), driver_license(856, 540),
          [(.12, .35), (.88, .36), (.90, .63), (.10, .61)], shadow=.25)
    scene('bank_card_on_floral_sheet', sheet(), bank_card(856, 540),
          [(.09, .34), (.90, .33), (.88, .61), (.11, .62)], shadow=.25)
    scene('business_card_on_floral_sheet', sheet(), business_card(856, 520),
          [(.11, .33), (.91, .35), (.89, .62), (.09, .60)], shadow=.25)
    scene('small_business_card_on_floral_sheet', sheet(), business_card(856, 520),
          [(.30, .52), (.70, .50), (.72, .66), (.31, .68)], shadow=.2)

    # 386313: a notice photographed on a blue partition; the page runs off
    # the top and bottom, and a light wall rail crosses the photo behind it,
    # touching both sides of the sheet.
    bg = cloth(w2, h2, (120, 80, 50), (0, 0, 0), (0, 0, 0), 'denim')
    bg[int(h2 * .65):int(h2 * .69)] = 200
    tall = [(.04, -.08), (.93, -.08), (.89, 1.08), (.09, 1.08)]
    scene('page_with_wall_rail', bg, page(900, 1300), tall, shadow=.2)
    SCENES[-1] = (SCENES[-1][0], SCENES[-1][1], clip_top_bottom(tall))

    lines = ['// GENERATED by tool/make_autocrop_fixtures.py. Do not edit.',
             'const autoCropScenes = <String, (String, List<double>)>{']
    jpg_dir = sys.argv[2] if len(sys.argv) > 2 and sys.argv[1] == '--jpg' else None
    for name, img, quad in SCENES:
        ok, data = cv2.imencode('.jpg', img, [cv2.IMWRITE_JPEG_QUALITY, 90])
        assert ok
        if jpg_dir:
            os.makedirs(jpg_dir, exist_ok=True)
            with open(os.path.join(jpg_dir, f'{name}.jpg'), 'wb') as f:
                f.write(data.tobytes())
        enc = base64.b64encode(data.tobytes()).decode()
        flat = ', '.join(f'{v:.4f}' for point in quad for v in point)
        lines.append(f"  '{name}': (")
        for i in range(0, len(enc), 76):
            lines.append(f"    '{enc[i:i + 76]}'")
        lines[-1] += ','
        lines.append(f'    [{flat}],')
        lines.append('  ),')
    lines.append('};')
    card_names = [n for n, _, _ in SCENES if any(
        k in n for k in ('card', 'license'))]
    lines.append('/// Card scenes, also checked with the card-camera detector.')
    lines.append('const cardSceneNames = <String>[')
    for n in card_names:
        lines.append(f"  '{n}',")
    lines.append('];')
    # A page photo with a printed QR code, for the live/still code reader.
    qr = cv2.QRCodeEncoder.create().encode(QR_TEXT)
    qr = cv2.resize(qr, (qr.shape[1] * 8, qr.shape[0] * 8),
                    interpolation=cv2.INTER_NEAREST)
    sheet = page(820, 1160)
    pad = cv2.copyMakeBorder(cv2.cvtColor(qr, cv2.COLOR_GRAY2BGR), 24, 24, 24, 24,
                             cv2.BORDER_CONSTANT, value=(255, 255, 255))
    sheet[800:800 + pad.shape[0], 480:480 + pad.shape[1]] = pad
    qr_scene = place(cloth(900, 1200, (120, 80, 50), (0, 0, 0), (0, 0, 0), 'denim'),
                     sheet, [(.08, .10), (.92, .07), (.95, .90), (.06, .93)], shadow=.2)
    ok, data = cv2.imencode('.jpg', qr_scene, [cv2.IMWRITE_JPEG_QUALITY, 90])
    assert ok
    enc = base64.b64encode(data.tobytes()).decode()
    lines.append(f"const qrCodeText = '{QR_TEXT}';")
    lines.append('const qrCodeScene =')
    for i in range(0, len(enc), 76):
        lines.append(f"    '{enc[i:i + 76]}'")
    lines[-1] += ';'
    if jpg_dir:
        with open(os.path.join(jpg_dir, 'qr_code_on_page.jpg'), 'wb') as f:
            f.write(data.tobytes())
    with open(OUT, 'w') as f:
        f.write('\n'.join(lines) + '\n')
    print('wrote', len(SCENES), 'scenes to', os.path.abspath(OUT))


if __name__ == '__main__':
    sys.exit(main())
