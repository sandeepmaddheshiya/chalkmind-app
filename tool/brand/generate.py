"""Generates every Chalkmind icon/brand asset from chalkmind_icon.py.

Run from the project root:  python3 tool/brand/generate.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from PIL import Image, ImageDraw, ImageFont  # noqa: E402
from chalkmind_icon import (  # noqa: E402
    BOARD_BOTTOM, BOARD_TOP, CHALK, SPARK, render_glyph_only, render_tile, _gradient,
)

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
RES = os.path.join(ROOT, 'android', 'app', 'src', 'main', 'res')
DENSITIES = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}
FONT = '/usr/share/fonts/truetype/lato/Lato-Black.ttf'
FONT_REG = '/usr/share/fonts/truetype/lato/Lato-Semibold.ttf'


def out(*parts):
    path = os.path.join(ROOT, *parts)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    return path


def hex_rgb(c):
    return '#%02X%02X%02X' % c


# 1. Android legacy launcher icons (pre-Android 8)
for d, k in DENSITIES.items():
    render_tile(int(48 * k)).save(os.path.join(RES, f'mipmap-{d}', 'ic_launcher.png'))

# 2. Android adaptive icon (Android 8+): foreground + monochrome per density.
#    The glyph is kept inside the 66dp safe zone of the 108dp canvas.
for d, k in DENSITIES.items():
    size = int(108 * k)
    render_glyph_only(size, glyph_scale=0.64).save(os.path.join(RES, f'mipmap-{d}', 'ic_launcher_foreground.png'))
    render_glyph_only(size, glyph_scale=0.64, monochrome=True).save(
        os.path.join(RES, f'mipmap-{d}', 'ic_launcher_monochrome.png'))

with open(out('android', 'app', 'src', 'main', 'res', 'drawable', 'ic_launcher_background.xml'), 'w') as f:
    f.write(f'''<?xml version="1.0" encoding="utf-8"?>
<!-- Chalkmind adaptive icon background: chalkboard-green gradient. -->
<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="rectangle">
    <gradient
        android:angle="315"
        android:startColor="{hex_rgb(BOARD_TOP)}"
        android:endColor="{hex_rgb(BOARD_BOTTOM)}"
        android:type="linear" />
</shape>
''')

with open(out('android', 'app', 'src', 'main', 'res', 'mipmap-anydpi-v26', 'ic_launcher.xml'), 'w') as f:
    f.write('''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@drawable/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
    <monochrome android:drawable="@mipmap/ic_launcher_monochrome" />
</adaptive-icon>
''')

# 3. Google Play: 512x512 store icon (full-bleed; Play applies its own mask)
render_tile(512, rounded=False).convert('RGB').save(out('store', 'play_icon_512.png'))

# 4. Google Play: 1024x500 feature graphic
W, H = 1024, 500
fg = _gradient(W).resize((W, W)).crop((0, 262, W, 262 + H)).convert('RGBA')
icon = render_tile(300)
fg.alpha_composite(icon, (90, (H - 300) // 2))
d = ImageDraw.Draw(fg)
title = ImageFont.truetype(FONT, 92)
sub = ImageFont.truetype(FONT_REG, 36)
small = ImageFont.truetype(FONT_REG, 28)
d.text((440, 128), 'Chalkmind', font=title, fill=CHALK)
d.text((444, 248), 'AI whiteboard for teaching', font=sub, fill=(209, 250, 229))
d.text((444, 294), '& learning', font=sub, fill=(209, 250, 229))
d.text((444, 362), 'Solve  ·  Explain  ·  Annotate PDFs', font=small, fill=SPARK)
fg.convert('RGB').save(out('store', 'feature_graphic_1024x500.png'))

# 5. Web / PWA icons and favicon
render_tile(192).save(out('web', 'icons', 'Icon-192.png'))
render_tile(512).save(out('web', 'icons', 'Icon-512.png'))
render_tile(192, rounded=False, glyph_scale=0.72).save(out('web', 'icons', 'Icon-maskable-192.png'))
render_tile(512, rounded=False, glyph_scale=0.72).save(out('web', 'icons', 'Icon-maskable-512.png'))
render_tile(64).save(out('web', 'favicon.png'))

# 6. In-app logo
render_tile(512).save(out('assets', 'brand', 'chalkmind_logo.png'))

print('Chalkmind brand assets generated.')
