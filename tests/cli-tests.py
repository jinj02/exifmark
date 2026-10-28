#!/usr/bin/env python3
"""Full CLI tests using independent Pillow decoding. Development dependency: Pillow."""
import json
import math
from pathlib import Path
import subprocess
import tempfile
from PIL import Image, ImageChops, ImageOps, ImageStat

ROOT = Path(__file__).resolve().parents[1]
BINARY = ROOT / 'exifmark.lrplugin/bin/exifmark-render'
checks = 0


def check(value, message):
    global checks
    checks += 1
    assert value, message


def render(directory, source, output, theme='white', quality=0.95, layout=None, **fields):
    request = dict(version=1, input=str(source), output=str(output), theme=theme,
                   camera='ILCE-7M4', lens='FE 24-70mm F2.8 GM II · 35mm',
                   exposure='f/2.8 · 1/250s · ISO 100', capturedAt='2026.10.27 09:41', quality=quality)
    request.update(fields)
    if layout is not None:
        request['layout'] = layout
    path = directory / 'request.json'
    path.write_text(json.dumps(request, ensure_ascii=False))
    return subprocess.run([str(BINARY), '--request', str(path)], capture_output=True, text=True)


def check_brand_spacing(image, photo_width, footer_height, background):
    image = image.convert('RGB')
    rows = range(image.height - footer_height + 1, image.height - 1)

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
    check(1 <= gap <= math.ceil(photo_width * 0.02), f'Divider too far from text: {gap}px')


def layout_dimensions(photo_width, photo_height, layout, jpeg=False):
    border = math.floor(photo_width * 0.02 + 0.5) if layout != 'bottomOnly' else 0
    footer = math.floor(photo_width * 0.08 + 0.5)
    if jpeg:
        border = math.ceil(border / 8) * 8
        footer = math.ceil(max(1, footer) / 8) * 8
        photo_width = math.ceil(photo_width / 8) * 8
        photo_height = math.ceil(photo_height / 8) * 8
    return (photo_width + border * 2, photo_height + border + footer), border, footer


def check_borders(image, photo_width, photo_height, border, background):
    if border <= 2:
        return
    strips = [
        (0, 0, image.width, border - 2),
        (0, border + 2, border - 2, border + photo_height - 2),
        (border + photo_width + 2, border + 2, image.width, border + photo_height - 2),
    ]
    for strip in strips:
        means = ImageStat.Stat(image.crop(strip)).mean
        check(all(abs(mean - background) < 4 for mean in means), 'Wrong border background or photo position')


with tempfile.TemporaryDirectory(prefix='exifmark-cli-') as folder:
    directory = Path(folder)
    original = Image.new('RGB', (320, 240))
    original.paste((210, 30, 20), (0, 0, 160, 120))
    original.paste((20, 180, 35), (160, 0, 320, 120))
    original.paste((20, 35, 215), (0, 120, 160, 240))
    original.paste((225, 195, 20), (160, 120, 320, 240))
    # Compare full rendered pixels against explicit expected text, exercising both render paths/layouts.
    for extension in ['jpg', 'tif']:
        source = directory / f'camera-names.{extension}'
        original.resize((1200, 800)).save(source)
        for layout in ['bordered', 'bottomOnly']:
            for theme in ['white', 'black']:
                for fields, expected in [
                    ({'cameraMake': 'SONY'}, 'SONY α7 IV'),
                    ({'cameraMake': 'Canon', 'camera': 'Canon EOS R5 Mark II'}, 'Canon EOS R5 Mark II'),
                    ({'cameraMake': 'SONY', 'cameraNameStyle': 'exif'}, 'ILCE-7M4'),
                    ({'cameraMake': 'SONY', 'camera': 'ILCE-7RM4A'}, 'SONY α7R IVA'),
                    ({'cameraMake': 'SONY', 'camera': 'ILCE-7M5'}, 'SONY α7 V'),
                    ({'cameraMake': 'SONY', 'camera': 'ILCE-7RM6'}, 'SONY α7R VI'),
                    ({'cameraMake': 'SONY', 'camera': 'ILCE-9'}, 'SONY α9'),
                    ({'cameraMake': 'SONY', 'camera': 'ILCE-9M2'}, 'SONY α9 II'),
                    ({'cameraMake': 'SONY', 'camera': 'ILCE-9M3'}, 'SONY α9 III'),
                    ({'cameraMake': 'SONY', 'camera': 'ILCE-1'}, 'SONY α1'),
                    ({'cameraMake': 'SONY', 'camera': 'ILCE-1M2'}, 'SONY α1 II'),
                    # Deliberately invented future syntax, including a new numeric family.
                    ({'cameraMake': 'SONY', 'camera': 'ILCE-7RM99A'}, 'SONY α7R XCIXA'),
                    ({'cameraMake': 'SONY', 'camera': 'ILCE-9M99'}, 'SONY α9 XCIX'),
                    ({'cameraMake': 'SONY', 'camera': 'ILCE-1M99'}, 'SONY α1 XCIX'),
                    ({'cameraMake': 'SONY', 'camera': 'ILCE-42RM14A'}, 'SONY α42R XIVA'),
                    ({'cameraMake': 'SONY', 'camera': 'ILCE-7CM2'}, 'SONY α7C II'),
                    ({'cameraMake': 'SONY', 'camera': 'ZV-E10M2'}, 'SONY ZV-E10 II'),
                    ({'cameraMake': 'SONY', 'camera': 'ILCE-7M0'}, 'SONY ILCE-7M0'),
                    ({'cameraMake': 'Unknown'}, 'Unknown ILCE-7M4'),
                    ({'cameraMake': 'SONY', 'cameraCustomName': '我的相机α7 IV'}, '我的相机α7 IV'),
                    ({'cameraMake': 'Canon', 'camera': 'Canon EOS R5', 'cameraNameStyle': 'exif'}, 'Canon EOS R5'),
                    ({'cameraMake': 'NIKON CORPORATION', 'camera': 'NIKON Z 8'}, 'Nikon Z 8'),
                    ({'cameraMake': 'SONY', 'camera': 'SONY α7 IV'}, 'SONY α7 IV'),
                    ({'cameraMake': 'SONY', 'cameraCustomName': 'SONY α7 IV'}, 'SONY α7 IV'),
                ]:
                    output = directory / 'camera-actual.jpg'
                    reference = directory / 'camera-reference.jpg'
                    result = render(directory, source, output, layout=layout, theme=theme, **fields)
                    check(result.returncode == 0, result.stderr)
                    reference_fields = dict(fields, cameraNameStyle='exif', cameraCustomName=expected)
                    result = render(directory, source, reference, layout=layout, theme=theme, **reference_fields)
                    check(result.returncode == 0, result.stderr)
                    check(ImageChops.difference(Image.open(output), Image.open(reference)).getbbox() is None,
                          f'Camera display text differs: {extension}, {layout}, {fields}')
                    check(272 not in Image.open(output).getexif(), 'Display name leaked into embedded EXIF')
    for orientation in range(1, 9):
        source = directory / f'orientation-{orientation}.jpg'
        exif = Image.Exif(); exif[274] = orientation
        original.save(source, quality=100, subsampling=0, exif=exif)
        expected = ImageOps.exif_transpose(Image.open(source))
        # Omitting layout exercises requests saved before this setting existed.
        for layout in [None, 'bordered', 'bottomOnly']:
            output = directory / f'result-{orientation}-{layout}.jpg'
            result = render(directory, source, output, layout=layout)
            check(result.returncode == 0, result.stderr)
            size, border, footer = layout_dimensions(expected.width, expected.height, layout, jpeg=True)
            stored = Image.open(output)
            check(stored.quantization == Image.open(source).quantization, 'JPEG quantization tables changed')
            actual = ImageOps.exif_transpose(stored)
            check(actual.size == size, 'Wrong oriented dimensions')
            check(json.loads(result.stdout) == dict(width=size[0], height=size[1], footerHeight=footer),
                  'Wrong reported canvas or footer dimensions')
            crop = actual.crop((border, border, border + expected.width, border + expected.height))
            # Compare far from quadrant edges to allow JPEG chroma subsampling.
            for x, y in [(30, 30), (expected.width-30, 30), (30, expected.height-30), (expected.width-30, expected.height-30)]:
                delta = max(abs(a-b) for a,b in zip(crop.getpixel((x,y)), expected.getpixel((x,y))))
                check(delta < 8, f'Orientation {orientation}, layout {layout} wrong at {(x,y)}: {delta}')
            check(actual.getexif().get(274, 1) == 1, 'Unnormalized EXIF orientation')
            check_borders(actual, expected.width, expected.height, border, 255)

    for theme, gray in [('white', 255), ('black', 0)]:
        for orientation in [1, 6]:
            source = directory / f'orientation-{orientation}.jpg'
            expected = ImageOps.exif_transpose(Image.open(source))
            for layout in ['bordered', 'bottomOnly']:
                output = directory / f'theme-{theme}-{orientation}-{layout}.jpg'
                result = render(directory, source, output, theme=theme, layout=layout, exposure='f/2.8 · 1/60s · ISO 100')
                check(result.returncode == 0, result.stderr)
                actual = ImageOps.exif_transpose(Image.open(output))
                size, border, footer = layout_dimensions(expected.width, expected.height, layout, jpeg=True)
                check(actual.size == size, 'Wrong themed dimensions')
                check(max(abs(c-gray) for c in actual.getpixel((2, actual.height-2))) < 3, 'Wrong footer background')
                check(34853 not in actual.getexif(), 'GPS reintroduced')
                check(272 not in actual.getexif(), 'Catalog camera text reintroduced as embedded metadata')
                check_borders(actual, expected.width, expected.height, border, gray)
                check_brand_spacing(actual, expected.width, footer, gray)
                # The reserved gap remains empty with long camera/lens strings.
                output = directory / f'overflow-{theme}-{orientation}-{layout}.jpg'
                result = render(directory, source, output, theme=theme, layout=layout,
                                cameraMake='SONY', camera='超长相机型号'*50, lens='LONG镜头'*100, exposure='f/22 · 1/8000s · ISO 102400')
                check(result.returncode == 0, result.stderr)
                actual = ImageOps.exif_transpose(Image.open(output))
                gap_x = border + int(expected.width * 0.55)
                gap = actual.crop((gap_x, actual.height - footer + 3, gap_x + 3, actual.height - 3))
                check(all(abs(mean-gray) < 5 for mean in ImageStat.Stat(gap).mean), 'Text or logo overflowed its region')
                check_brand_spacing(actual, expected.width, footer, gray)

    for name in ["中文 空格 ' $() ` & ;.tif", 'missing-fields.tif']:
        source = directory / name
        original.save(source)
        before = source.read_bytes()
        output = directory / (name + '.jpg')
        result = render(directory, source, output, camera='', lens='', exposure='', capturedAt='')
        check(result.returncode == 0, result.stderr)
        check(source.read_bytes() == before, 'Input modified')

    # Compare actual footer pixels to verify selection through both rendering paths.
    brands = [svg.stem for svg in sorted((ROOT / 'assets').glob('*.svg'))]
    for extension in ['tif', 'jpg']:
        source = directory / ('brands.' + extension)
        Image.new('RGB', (1200, 800), (60, 100, 140)).save(source)
        for theme, gray in [('white', 255), ('black', 0)]:
            samples = {}
            for brand in brands + ['unknown']:
                output = directory / f'{brand}-{theme}-{extension}.tif'
                result = render(directory, source, output, theme=theme, layout='bottomOnly',
                                cameraMake=brand, camera='', lens='', exposure='', capturedAt='')
                check(result.returncode == 0, result.stderr)
                with Image.open(output) as image:
                    footer = image.crop((0, 800, 1200, image.height)).convert('RGB')
                    delta = ImageChops.difference(footer, Image.new('RGB', footer.size, (gray,)*3))
                    box = delta.getbbox()
                    if brand == 'unknown':
                        check(box is None, 'Unknown manufacturer must leave brand region empty')
                    else:
                        check(box is not None, f'Missing {brand} logo')
                        logo_box = delta.crop((600, 0, 890, footer.height)).getbbox()
                        check(logo_box is not None and logo_box[2] - logo_box[0] >= 32,
                              f'{brand} was not scaled up to its display size')
                        check(box[1] >= 20 and box[3] <= 76, f'{brand} exceeds footer height')
                        samples[brand] = footer.crop((600, 0, 1200, footer.height)).tobytes()
            check(len(set(samples.values())) == len(brands), 'Manufacturers rendered duplicate logos')
            # TIFF Make, explicit catalog Make and model-only legacy requests.
            exif = Image.Exif(); exif[271] = 'Canon'; exif[272] = 'Canon EOS R5'
            Image.new('RGB', (1200, 800), (60, 100, 140)).save(source, exif=exif)
            for fields, expected in [({}, 'canon'), ({'cameraMake': 'NIKON CORPORATION'}, 'nikon'),
                                     ({'cameraMake': 'RICOH IMAGING COMPANY, LTD.', 'camera': 'PENTAX K-1'}, 'pentax')]:
                output = directory / 'selected.tif'
                request_fields = dict(camera='', lens='', exposure='', capturedAt='')
                request_fields.update(fields)
                result = render(directory, source, output, theme=theme, layout='bottomOnly', **request_fields)
                check(result.returncode == 0, result.stderr)
                with Image.open(output) as image:
                    check(image.crop((600, 800, 1200, image.height)).convert('RGB').tobytes() == samples[expected],
                          f'Wrong brand selection for {fields}')
            Image.new('RGB', (1200, 800), (60, 100, 140)).save(source)

    source = directory / 'orientation-1.jpg'
    output = directory / 'existing.jpg'
    output.write_bytes(b'original contents')
    result = render(directory, source, output, quality=-1)
    check(result.returncode != 0, 'Invalid quality accepted')
    check(output.read_bytes() == b'original contents', 'Failure changed existing output')
    result = render(directory, source, output, layout='invalid')
    check(result.returncode != 0, 'Invalid layout accepted')
    check(output.read_bytes() == b'original contents', 'Invalid layout changed existing output')
    request = directory / 'invalid.json'; request.write_text('{broken')
    result = subprocess.run([str(BINARY), '--request', str(request)], capture_output=True)
    check(result.returncode != 0, 'Invalid JSON accepted')
    check(not list(directory.glob('.exifmark-*.jpg')), 'Leaked intermediate output')
    # Direct TIFF requests retain the lossless compatibility path.
    pixels = bytes((i * 73 + i // 17 * 41) % 256 for i in range(511 * 383 * 3))
    uncompressed = Image.frombytes('RGB', (511, 383), pixels)
    source = directory / 'lossless-source.tif'
    uncompressed.save(source, compression='tiff_lzw')
    for layout in ['bordered', 'bottomOnly']:
        for theme, gray in [('white', 255), ('black', 0)]:
            for quality in [0, 1]:
                output = directory / f'lossless-{layout}-{theme}-{quality}.tif'
                result = render(directory, source, output, theme=theme, quality=quality, layout=layout)
                check(result.returncode == 0, result.stderr)
                with Image.open(output) as actual:
                    size, border, footer = layout_dimensions(511, 383, layout)
                    check(actual.format == 'TIFF', 'Staging file must be a real TIFF')
                    check(actual.size == size, 'Wrong TIFF canvas dimensions')
                    check(actual.tag_v2.get(259) in [1, 5, 8, 32946], 'Lossy TIFF compression used')
                    crop = actual.crop((border, border, border + 511, border + 383)).convert('RGB')
                    check(crop.tobytes() == pixels, 'TIFF staging changed photo pixels')
                    check_borders(actual.convert('RGB'), 511, 383, border, gray)

    # Installing the final JPEG preserves its encoding, quantization, EXIF and ICC bytes.
    final = directory / 'lightroom-final.jpg'
    exif = Image.Exif(); exif[270] = 'preserve final JPEG bytes'
    uncompressed.save(final, quality=73, progressive=True, exif=exif)
    final_bytes = final.read_bytes()
    output = directory / "installed ' $() ` &.jpg"
    output.write_bytes(b'previous output')
    path = directory / 'install.json'
    path.write_text(json.dumps(dict(input=str(final), output=str(output))))
    result = subprocess.run([str(BINARY), '--install-jpeg', str(path)], capture_output=True, text=True)
    check(result.returncode == 0, result.stderr)
    check(output.read_bytes() == final_bytes, 'Lightroom JPEG was re-encoded')
    check(final.read_bytes() == final_bytes, 'Lightroom source JPEG changed')
    for invalid in [source, directory / 'missing.jpg']:
        path.write_text(json.dumps(dict(input=str(invalid), output=str(output))))
        result = subprocess.run([str(BINARY), '--install-jpeg', str(path)], capture_output=True)
        check(result.returncode != 0, 'Invalid final JPEG accepted')
        check(output.read_bytes() == final_bytes, 'Failed install changed existing output')
    check(not list(directory.glob('.exifmark-*')), 'Leaked intermediate image')
print(f'CLI validation: {checks} assertions passed')
