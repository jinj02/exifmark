#!/usr/bin/env python3
"""Independent pixel, geometry, contrast and JPEG-coefficient checks for composable styles."""
import itertools
import json
import math
from collections import Counter
from pathlib import Path
import subprocess
import tempfile
from PIL import Image, ImageChops, ImageCms, ImageFile, ImageOps, ImageStat

ROOT = Path(__file__).resolve().parents[1]
BINARY = ROOT / 'exifmark.lrplugin/bin/exifmark-render'
checks = 0


def check(condition, message):
    global checks
    checks += 1
    assert condition, message


def render(folder, source, name='card.tif', **fields):
    output = folder / name
    request = dict(version=1, input=str(source), output=str(output), theme='white', layout='bordered',
                   cameraMake='NIKON CORPORATION', camera='NIKON Z 8', lens='NIKKOR Z 24-70mm · 54mm',
                   focalLength='54mm', exposure='f/4.5 · 1/500s · ISO 125', capturedAt='2026.10.28 09:41', quality=0.95)
    request.update(fields)
    path = folder / 'request.json'
    path.write_text(json.dumps(request, ensure_ascii=False))
    result = subprocess.run([str(BINARY), '--request', str(path)], capture_output=True, text=True)
    check(result.returncode == 0, f'{fields}: {result.stderr}')
    with Image.open(output) as image:
        pixels = ImageOps.exif_transpose(image).convert('RGB')
    return pixels, json.loads(result.stdout), output


def footer_mask(card, footer, gray):
    band = card.crop((0, card.height-footer, card.width, card.height))
    delta = ImageChops.difference(band, Image.new('RGB', band.size, (gray,)*3)).convert('L')
    return delta.point(lambda p: 255 if p > 18 else 0)


with tempfile.TemporaryDirectory(prefix='exifmark-styles-') as temporary:
    folder = Path(temporary)
    source = folder / 'source.tif'
    # All 12 combinations, including square, panoramic, rounding and one-pixel edge cases.
    # TIFF preserves exact photo pixels, independently of the background and type changes.
    for size, theme, style, layout in itertools.product(
            [(1200, 800), (800, 1200), (800, 800), (1600, 400), (667, 1000), (17, 11), (1, 1)],
            ['white', 'black', 'blurred'],
            ['detailed', 'centered'], ['bordered', 'bottomOnly']):
        photo = Image.new('RGB', size, (65, 115, 155))
        photo.paste((190, 145, 75), (size[0]//2, 0, size[0], size[1]//2))
        photo.save(source)
        card, result, _ = render(folder, source, theme=theme, watermarkStyle=style, layout=layout)
        short_edge = min(size)
        border = math.floor(short_edge*(0.05 if theme == 'blurred' else 0.03)+0.5) if layout == 'bordered' else 0
        footer = max(1, math.floor(short_edge*0.12+0.5))
        check(card.size == (size[0]+2*border, size[1]+border+footer),
              f'Wrong short-edge proportions: {size}, {theme}, {style}, {layout}')
        check(result == dict(width=card.width, height=card.height, footerHeight=footer), 'Wrong style dimensions')
        check(card.crop((border, border, border+size[0], border+size[1])).tobytes() == photo.tobytes(),
              'Style changed sharp photo pixels')
        if theme != 'blurred' and size[0] >= 800:
            gray = 255 if theme == 'white' else 0
            check(card.getpixel((0, card.height-1)) == (gray,)*3, 'Incorrect solid background')
            if style == 'centered':
                mask = footer_mask(card, footer, gray)
                for top, bottom in [(0, footer//2), (footer//2, footer)]:
                    box = mask.crop((0, top, card.width, bottom)).getbbox()
                    check(box is not None, 'Missing centered row')
                    check(abs((box[0]+box[2])/2-card.width/2) <= 4, 'Watermark row is off center')
                    check(box[0] >= border+size[0]*0.1-2 and box[2] <= border+size[0]*0.9+2,
                          'Centered row exceeded 80% width')

    # Equal short edges keep the same type scale across aspect ratios and frame layouts.
    # Use short labels so automatic fitting cannot hide an incorrect font scale.
    for theme, gray in [('white', 255), ('black', 0)]:
        reference = None
        for size, layout in itertools.product([(1200, 800), (800, 1200), (1600, 800)],
                                               ['bordered', 'bottomOnly']):
            Image.new('RGB', size, (65, 115, 155)).save(source)
            card, result, _ = render(folder, source, theme=theme, layout=layout,
                                       cameraCustomName='Test Z 8', lens='Prime 50mm',
                                       exposure='f/4 · ISO 100', capturedAt='2026.10.28')
            check(result['footerHeight'] == 96, 'Aspect ratio changed the footer scale')
            border = 24 if layout == 'bordered' else 0
            inset = 0 if layout == 'bordered' else 24
            mask = footer_mask(card, 96, gray)
            left = mask.crop((border+inset, 0, border+inset+250, 96))
            box = left.getbbox()
            check(box is not None and 0 <= box[0] <= 3, 'Detailed text lost photo-edge/inset alignment')
            if reference is None:
                reference = left.tobytes()
            check(left.tobytes() == reference, 'Equal short edges rendered different text sizes or row spacing')
            right = mask.crop((card.width//2, 0, card.width, 96)).getbbox()
            check(right is not None and abs(card.width//2+right[2]-(card.width-border-inset)) <= 3,
                  'Detailed parameters lost right-edge alignment')
            if inset:
                check(mask.crop((0, 0, inset, 96)).getbbox() is None,
                      'Bottom-only footer lost its left breathing room')
                check(mask.crop((card.width-inset, 0, card.width, 96)).getbbox() is None,
                      'Bottom-only footer lost its right breathing room')

    # Glass tint improves contrast; primary ink stays opaque and secondary text stays softer.
    for gray, style in itertools.product([30, 70, 190, 235], ['detailed', 'centered']):
        Image.new('RGB', (1200, 800), (gray,)*3).save(source)
        card, result, _ = render(folder, source, theme='blurred', watermarkStyle=style)
        band = card.crop((0, card.height-result['footerHeight'], card.width, card.height))
        low, high = band.convert('L').getextrema()
        background = round(gray*0.75) if gray <= 70 else round(gray*0.88+255*0.12)
        check(abs(band.getpixel((card.width//2, band.height-1))[0]-background) <= 2,
              'Glass tint did not follow the selected ink')
        counts = Counter(band.convert('L').tobytes())
        secondary = round(background*0.22+255*0.78) if gray <= 70 else round(background*0.32)
        check(sum(count for value, count in counts.items() if abs(value-secondary) <= 2) > 10,
              'Missing translucent secondary ink')
        if gray <= 70:
            check(high >= 250 and low >= background*0.5-2,
                  f'Dark glass lost white ink or its background: {gray}, {style}, {low}, {high}')
        else:
            check(low <= 5 and high <= background+2, 'Bright glass lost black ink or its background')

    # Sample the background underneath the watermark rather than the brighter main photo.
    photo = Image.new('RGB', (1200, 800), (245,)*3)
    photo.paste((30,)*3, (0, 500, 1200, 800)); photo.save(source)
    for style in ['centered', 'detailed']:
        card, result, _ = render(folder, source, theme='blurred', watermarkStyle=style)
        band = card.crop((0, card.height-result['footerHeight'], card.width, card.height))
        check(band.convert('L').getextrema()[1] >= 250, 'Footer background should select white ink')

    # Uneven backgrounds still use one shared ink color across both rows and both sides.
    photo = Image.new('RGB', (1200, 800), (210,)*3)
    photo.paste((40,)*3, (600, 0, 1200, 800)); photo.save(source)
    for style in ['centered', 'detailed']:
        card, result, _ = render(folder, source, theme='blurred', watermarkStyle=style)
        band = card.crop((40, card.height-result['footerHeight'], card.width-40, card.height)).convert('L')
        # Opposite opaque extrema would reveal a per-row/per-region switch in foreground color.
        counts = Counter(band.tobytes())
        black, white = sum(counts[v] for v in range(6)), sum(counts[v] for v in range(250, 256))
        check((black > 10) != (white > 10), 'Mixed background used inconsistent or missing primary ink')

    # Exercise thumbnail downsampling on a photo larger than the background's 2048px limit.
    large = photo.resize((3200, 2400)); large.save(source)
    card, _, _ = render(folder, source, theme='blurred', watermarkStyle='centered')
    check(card.size == (3440, 2808), 'Large background changed dimensions')
    check(card.crop((120, 120, 3320, 2520)).tobytes() == large.tobytes(), 'Large blurred background changed the photo')

    # Centered content omits lens/date, and independently displays focal length and camera naming choice.
    Image.new('RGB', (1200, 800), (90, 120, 150)).save(source)
    baseline, _, _ = render(folder, source, watermarkStyle='centered')
    hidden, _, _ = render(folder, source, watermarkStyle='centered', lens='hidden lens', capturedAt='hidden date')
    check(baseline.tobytes() == hidden.tobytes(), 'Centered style leaked lens/date')
    changed, _, _ = render(folder, source, watermarkStyle='centered', focalLength='105mm')
    check(baseline.tobytes() != changed.tobytes(), 'Centered style lost focal length')
    exif_name, _, _ = render(folder, source, watermarkStyle='centered', cameraNameStyle='exif')
    explicit, _, _ = render(folder, source, watermarkStyle='centered', cameraCustomName='Z 8')
    check(exif_name.tobytes() == explicit.tobytes(), 'Centered style ignored EXIF name selection')
    for make, model, expected in [('NIKON CORPORATION', 'NIKON Z 8', 'Z 8'),
                                  ('SONY', 'ILCE-7M4', 'α7 IV'),
                                  ('Canon', 'Canon EOS R5', 'EOS R5'),
                                  ('NIKON CORPORATION', 'NIKON Z 99', 'Z 99')]:
        for theme in ['white', 'black', 'blurred']:
            actual, _, _ = render(folder, source, theme=theme, watermarkStyle='centered', cameraMake=make, camera=model)
            expected_card, _, _ = render(folder, source, theme=theme, watermarkStyle='centered',
                                          cameraMake=make, camera=model, cameraCustomName=expected)
            check(actual.tobytes() == expected_card.tobytes(), f'Centered style repeated manufacturer: {make}, {theme}')
    for fields in [dict(camera='', cameraMake='', lens='', focalLength='', exposure='', capturedAt=''),
                   dict(camera='Unknown model', cameraMake='Acme', focalLength='', exposure=''),
                   dict(camera='相机VeryLongName'*100, exposure='f/22 · 1/8000s · ISO 102400'*100)]:
        card, result, _ = render(folder, source, watermarkStyle='centered', **fields)
        mask = footer_mask(card, result['footerHeight'], 255)
        box = mask.getbbox()
        if fields['camera'] == '':
            check(box is None, 'Missing fields should leave an empty footer')
        else:
            check(box is not None and box[0] >= 142 and box[2] <= card.width-142, 'Long/missing fields overflowed')
    legacy, _, _ = render(folder, source)
    detailed, _, _ = render(folder, source, watermarkStyle='detailed')
    check(legacy.tobytes() == detailed.tobytes(), 'Old requests changed watermark style')

    # The blur is visibly smooth and retains the original image's spatial color variation.
    photo = Image.new('RGB', (1200, 800))
    photo.paste((230, 70, 35), (0, 0, 600, 800))
    photo.paste((25, 65, 220), (600, 0, 1200, 800)); photo.save(source)
    card, result, _ = render(folder, source, theme='blurred', cameraMake='', camera='', lens='',
                             focalLength='', exposure='', capturedAt='')
    y = card.height-10
    check(card.getpixel((10, y))[0] > 200 and card.getpixel((card.width-10, y))[2] > 190,
          'Blur lost spatial colors or introduced transparent edges')
    ramp = [card.getpixel((x, y)) for x in range(card.width//2-25, card.width//2+25)]
    check(max(abs(a[0]-b[0]) for a, b in zip(ramp, ramp[1:])) < 12, 'Background has an unblurred seam')

    # Compare bitmap and coefficient paths in every orientation (dimensions align exactly with 4:4:4 MCUs).
    photo = photo.resize((1600, 800))
    for orientation in range(1, 9):
        exif = Image.Exif(); exif[274] = orientation
        jpeg = folder / 'oriented.jpg'; photo.save(jpeg, quality=95, subsampling=0, exif=exif)
        card, _, _ = render(folder, jpeg, name='oriented-output.jpg', theme='blurred', watermarkStyle='centered')
        bitmap, _, _ = render(folder, jpeg, theme='blurred', watermarkStyle='centered')
        check(card.size == bitmap.size, 'Bitmap and JPEG geometry disagree')
        for strip in [(0, 0, card.width, 40), (0, card.height-96, card.width, card.height),
                      (0, 40, 40, card.height-96), (card.width-40, 40, card.width, card.height-96)]:
            delta = ImageStat.Stat(ImageChops.difference(card.crop(strip), bitmap.crop(strip)))
            check(max(delta.mean) < 6, f'Background/footer orientation differs between render paths: {orientation}')

    # Inspect original quantization tables, sampling, and EVERY DCT coefficient, including partial edge blocks.
    inspector = folder / 'jpeg-coefficients'
    subprocess.run(['cc', '-I', str(ROOT/'.build/jpeg/include'), str(ROOT/'tests/jpeg-coefficients.c'),
                    str(ROOT/'.build/jpeg/lib/libjpeg.a'), '-o', str(inspector)], check=True)
    profile = ImageCms.ImageCmsProfile(ImageCms.createProfile('sRGB')).tobytes()
    photo = Image.frombytes('RGB', (411, 299), bytes((i*73+i//17*41) % 256 for i in range(411*299*3)))
    ImageFile.MAXBLOCK = max(ImageFile.MAXBLOCK, photo.width*photo.height*4)
    for orientation, sampling, style, layout in itertools.product(range(1, 9), [0, 2],
                                                                  ['detailed', 'centered'], ['bordered', 'bottomOnly']):
        jpeg = folder / 'coefficients.jpg'
        exif = Image.Exif(); exif[274] = orientation; exif[315] = 'preserved author'
        photo.save(jpeg, quality=73, subsampling=sampling, progressive=True, exif=exif, icc_profile=profile)
        original_bytes = jpeg.read_bytes()
        _, result, output = render(folder, jpeg, name='coefficients-output.jpg', theme='blurred',
                                   watermarkStyle=style, layout=layout)
        block = 8 if sampling == 0 else 16
        border = math.ceil(math.floor(299*0.05+0.5)/block)*block if layout == 'bordered' else 0
        footer = math.ceil(math.floor(299*0.12+0.5)/block)*block
        oriented = (304, 416) if orientation >= 5 else (416, 304)
        check(result == dict(width=oriented[0]+2*border, height=oriented[1]+border+footer,
                             footerHeight=footer), 'Wrong partial-MCU JPEG dimensions')
        if orientation >= 5:
            offset = (border if orientation in [5, 6] else footer, border)
        else:
            offset = (border, border if orientation in [1, 2] else footer)
        inspected = subprocess.run([str(inspector), str(jpeg), str(output), *map(str, offset)],
                                   capture_output=True, text=True)
        check(inspected.returncode == 0, inspected.stderr)
        with Image.open(output) as raw:
            check(raw.getexif().get(274) == orientation, 'JPEG lost original orientation')
            check(raw.info.get('icc_profile') == profile, 'JPEG lost ICC profile')
            check(raw.getexif().get(315) == 'preserved author', 'JPEG lost source metadata')
            check(34853 not in raw.getexif(), 'Watermark introduced GPS')
        check(jpeg.read_bytes() == original_bytes, 'Rendering modified the input JPEG')

    # Invalid new values protect an existing output and leak no temporary files.
    protected = folder / 'protected.jpg'; protected.write_bytes(b'previous output')
    for field, value in [('theme', 'invalid'), ('watermarkStyle', 'invalid')]:
        path = folder / 'invalid.json'
        request = dict(version=1, input=str(source), output=str(protected), theme='white',
                       camera='', lens='', exposure='', capturedAt='', quality=0.9)
        request[field] = value
        path.write_text(json.dumps(request))
        result = subprocess.run([str(BINARY), '--request', str(path)], capture_output=True)
        check(result.returncode != 0 and protected.read_bytes() == b'previous output', 'Invalid style changed output')
    check(not list(folder.glob('.exifmark-*')), 'Leaked temporary images')

print(f'Style validation: {checks} assertions passed')
