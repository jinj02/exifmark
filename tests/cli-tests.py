#!/usr/bin/env python3
"""Full CLI tests using independent Pillow decoding. Development dependency: Pillow."""
import json
import math
from pathlib import Path
import subprocess
import tempfile
from PIL import Image, ImageChops, ImageOps, ImageStat

ROOT = Path(__file__).resolve().parents[1]
BINARY = ROOT / 'exify.lrplugin/bin/exify-render'
checks = 0


def check(value, message):
    global checks
    checks += 1
    assert value, message


def render(directory, source, output, theme='white', quality=0.95, **fields):
    request = dict(version=1, input=str(source), output=str(output), theme=theme,
                   camera='ILCE-7M4', lens='FE 24-70mm F2.8 GM II · 35mm',
                   exposure='f/2.8 · 1/250s · ISO 100', capturedAt='2026.10.27 09:41', quality=quality)
    request.update(fields)
    path = directory / 'request.json'
    path.write_text(json.dumps(request, ensure_ascii=False))
    return subprocess.run([str(BINARY), '--request', str(path)], capture_output=True, text=True)


def check_brand_spacing(image, photo_height, background):
    image = image.convert('RGB')
    footer_height = image.height - photo_height
    rows = range(photo_height + 1, image.height - 1)

    def visible(x, y):
        return sum(abs(c-background) for c in image.getpixel((x, y))) / 3 > 32

    # Identify the divider by its continuous vertical ink, independently of its position.
    line_columns = []
    for x in range(int(image.width * 0.54), int(image.width * 0.96)):
        run = longest = 0
        for y in rows:
            run = run + 1 if visible(x, y) else 0
            longest = max(longest, run)
        if longest >= math.ceil(footer_height * 0.30):
            line_columns.append(x)
    check(bool(line_columns), 'Missing vertical divider')
    line_right = max(line_columns)
    text_columns = [x for x in range(line_right + 1, image.width)
                    if any(visible(x, y) for y in rows)]
    check(bool(text_columns), 'Missing right-side text')
    gap = min(text_columns) - line_right - 1
    check(1 <= gap <= math.ceil(image.width * 0.02), f'Divider too far from text: {gap}px')


with tempfile.TemporaryDirectory(prefix='exify-cli-') as folder:
    directory = Path(folder)
    original = Image.new('RGB', (320, 240))
    original.paste((210, 30, 20), (0, 0, 160, 120))
    original.paste((20, 180, 35), (160, 0, 320, 120))
    original.paste((20, 35, 215), (0, 120, 160, 240))
    original.paste((225, 195, 20), (160, 120, 320, 240))
    for orientation in range(1, 9):
        source = directory / f'orientation-{orientation}.jpg'
        exif = Image.Exif(); exif[274] = orientation
        original.save(source, quality=100, subsampling=0, exif=exif)
        output = directory / f'result-{orientation}.jpg'
        result = render(directory, source, output)
        check(result.returncode == 0, result.stderr)
        expected = ImageOps.exif_transpose(Image.open(source))
        actual = Image.open(output)
        check(actual.size == (expected.width, expected.height + round(expected.width * 0.1)), 'Wrong oriented dimensions')
        crop = actual.crop((0, 0, expected.width, expected.height))
        # Compare far from quadrant edges to allow JPEG chroma subsampling.
        for x, y in [(30, 30), (expected.width-30, 30), (30, expected.height-30), (expected.width-30, expected.height-30)]:
            delta = max(abs(a-b) for a,b in zip(crop.getpixel((x,y)), expected.getpixel((x,y))))
            check(delta < 8, f'Orientation {orientation} wrong at {(x,y)}: {delta}')
        check(actual.getexif().get(274, 1) == 1, 'Unnormalized EXIF orientation')

    for theme, gray in [('white', 255), ('black', 0)]:
        source = directory / 'orientation-1.jpg'
        output = directory / f'theme-{theme}.jpg'
        result = render(directory, source, output, theme=theme, exposure='f/2.8 · 1/60s · ISO 100')
        check(result.returncode == 0, result.stderr)
        actual = Image.open(output)
        check(max(abs(c-gray) for c in actual.getpixel((2, actual.height-2))) < 3, 'Wrong footer background')
        check(34853 not in actual.getexif(), 'GPS reintroduced')
        check(272 not in actual.getexif(), 'Catalog camera text reintroduced as embedded metadata')
        check_brand_spacing(actual, original.height, gray)
        # The reserved gaps remain empty, even with a very long camera/lens string.
        output = directory / f'overflow-{theme}.jpg'
        result = render(directory, source, output, theme=theme, camera='超长相机型号'*50, lens='LONG镜头'*100,
                        exposure='f/22 · 1/8000s · ISO 102400')
        check(result.returncode == 0, result.stderr)
        actual = Image.open(output)
        for fraction in [0.55]:
            gap = actual.crop((int(320*fraction), 244, int(320*fraction)+3, 268))
            check(all(abs(mean-gray) < 5 for mean in ImageStat.Stat(gap).mean), 'Text or logo overflowed its region')
        check_brand_spacing(actual, original.height, gray)

    for name in ["中文 空格 ' $() ` & ;.tif", 'missing-fields.tif']:
        source = directory / name
        original.save(source)
        before = source.read_bytes()
        output = directory / (name + '.jpg')
        result = render(directory, source, output, camera='', lens='', exposure='', capturedAt='')
        check(result.returncode == 0, result.stderr)
        check(source.read_bytes() == before, 'Input modified')

    source = directory / 'orientation-1.jpg'
    output = directory / 'existing.jpg'
    output.write_bytes(b'original contents')
    result = render(directory, source, output, quality=-1)
    check(result.returncode != 0, 'Invalid quality accepted')
    check(output.read_bytes() == b'original contents', 'Failure changed existing output')
    request = directory / 'invalid.json'; request.write_text('{broken')
    result = subprocess.run([str(BINARY), '--request', str(request)], capture_output=True)
    check(result.returncode != 0, 'Invalid JSON accepted')
    check(not list(directory.glob('.exify-*.jpg')), 'Leaked intermediate output')
print(f'CLI validation: {checks} assertions passed')
