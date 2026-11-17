"""Builds Google Play screenshots from raw device captures.

Each image is 9:16 (Play's required shape): a chalkboard-green band with a
headline, and the app screen below it in a rounded frame.

Usage:
    python3 tool/brand/store_screenshots.py RAW_DIR OUT_DIR

RAW_DIR holds full-screen captures (1600x2560 tablet) named as in SHOTS.
Writes OUT_DIR/tablet/NN-name.png (1440x2560) and OUT_DIR/phone/NN-name.png
(1080x1920).
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

BOARD_TOP = (16, 94, 80)
BOARD_BOTTOM = (8, 52, 46)
CHALK = (248, 250, 252)
MINT = (209, 250, 229)
SPARK = (250, 204, 21)
FONT = '/usr/share/fonts/truetype/lato/Lato-Black.ttf'
FONT_REG = '/usr/share/fonts/truetype/lato/Lato-Semibold.ttf'

# (raw file, headline, accent word in the headline, subline)
SHOTS = [
    ('t_written.png', 'Write it. Solve it.', 'Solve', 'The answer appears in your handwriting'),
    ('t_offer.png', 'Instant answers', 'Instant', 'Sums are read on your device, even offline'),
    ('t_check.png', 'Check my work', 'Check', 'Finds the first wrong line and explains why'),
    ('t_mindmap.png', 'Mind maps in seconds', 'seconds', 'Type a topic, get an editable map'),
    ('t_graph.png', 'Plot any equation', 'Plot', 'Interactive graphs right on the board'),
    ('t_pyth.png', 'Geometry, made clear', 'clear', 'Neat shapes and worked solutions'),
]

W, H = 1440, 2560          # tablet canvas (9:16)
CROP = (6, 64, 1594, 2516)  # drop status bar, gesture bar and edge pixels


def gradient(w, h):
    img = Image.new('RGB', (w, h))
    d = ImageDraw.Draw(img)
    for y in range(h):
        t = y / (h - 1)
        d.line([(0, y), (w, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(BOARD_TOP, BOARD_BOTTOM)))
    return img


def rounded(img, r):
    mask = Image.new('L', img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, img.width - 1, img.height - 1], r, fill=255)
    out = Image.new('RGBA', img.size)
    out.paste(img, (0, 0), mask)
    return out


def headline(draw, text, accent, y, size):
    font = ImageFont.truetype(FONT, size)
    words = text.split(' ')
    widths = [draw.textlength(w + ' ', font=font) for w in words]
    total = sum(widths) - draw.textlength(' ', font=font)
    x = (W - total) / 2
    for w, ww in zip(words, widths):
        draw.text((x, y), w, font=font, fill=SPARK if accent and accent in w else CHALK)
        x += ww


def compose(raw_path, title, accent, sub):
    canvas = gradient(W, H).convert('RGBA')
    d = ImageDraw.Draw(canvas)
    headline(d, title, accent, 150, 118)
    sf = ImageFont.truetype(FONT_REG, 54)
    tw = d.textlength(sub, font=sf)
    d.text(((W - tw) / 2, 318), sub, font=sf, fill=MINT)

    shot = Image.open(raw_path).convert('RGB').crop(CROP)
    target_w = 1240
    shot = shot.resize((target_w, round(shot.height * target_w / shot.width)), Image.LANCZOS)
    x, y = (W - target_w) // 2, 480
    max_h = H - y + 60  # let the frame run slightly off the bottom edge
    if shot.height > max_h:
        shot = shot.crop((0, 0, shot.width, max_h))

    shadow = Image.new('RGBA', canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle([x, y + 24, x + shot.width, y + shot.height + 24], 48, fill=(0, 0, 0, 120))
    canvas = Image.alpha_composite(canvas, shadow.filter(ImageFilter.GaussianBlur(36)))
    frame = Image.new('RGBA', (shot.width + 20, shot.height + 20), (255, 255, 255, 0))
    frame_mask = rounded(Image.new('RGB', frame.size, (226, 232, 240)), 56)
    canvas.alpha_composite(frame_mask, (x - 10, y - 10))
    canvas.alpha_composite(rounded(shot, 48), (x, y))
    return canvas.convert('RGB')


def main(raw_dir, out_dir):
    for sub in ('tablet', 'phone'):
        os.makedirs(os.path.join(out_dir, sub), exist_ok=True)
    for i, (raw, title, accent, sub) in enumerate(SHOTS, 1):
        img = compose(os.path.join(raw_dir, raw), title, accent, sub)
        name = f'{i:02d}-{raw[2:-4]}.png'
        img.save(os.path.join(out_dir, 'tablet', name), optimize=True)
        img.resize((1080, 1920), Image.LANCZOS).save(os.path.join(out_dir, 'phone', name), optimize=True)
        print(name)


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
