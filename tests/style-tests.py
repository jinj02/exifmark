#!/usr/bin/env python3
"""Independent pixel, geometry, contrast and JPEG-coefficient checks for composable styles."""
import itertools
import json
import math
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
    # All 12 combinations, portrait/landscape and a tiny canvas; TIFF preserves exact photo pixels.
    for size, theme, style, layout in itertools.product(
            [(1200, 800), (800, 1200), (17, 11)], ['white', 'black', 'blurred'],
            ['detailed', 'centered'], ['bordered', 'bottomOnly']):
        photo = Image.new('RGB', size, (65, 115, 155))
        photo.paste((190, 145, 75), (size[0]//2, 0, size[0], size[1]//2))
        photo.save(source)
        card, result, _ = render(folder, source, theme=theme, watermarkStyle=style, layout=layout)
        border = round(size[0]*0.02) if layout == 'bordered' else 0
        footer = math.floor(size[0]*0.08+0.5)
        check(card.size == (size[0]+2*border, size[1]+border+footer), 'Style changed canvas proportions')
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

    # Pure black or white ink throughout the footer, including the logo and detailed divider.
    for gray, style in itertools.product([30, 70, 190, 235], ['detailed', 'centered']):
        Image.new('RGB', (1200, 800), (gray,)*3).save(source)
        card, result, _ = render(folder, source, theme='blurred', watermarkStyle=style)
        band = card.crop((0, card.height-result['footerHeight'], card.width, card.height))
        low, high = band.convert('L').getextrema()
        if gray <= 70:
            check(high >= 250 and low >= gray-2, 'Dark background must use uniformly white ink')
        else:
            check(low <= 5 and high <= gray+2, 'Bright background must use uniformly black ink')

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
    empty, result, _ = render(folder, source, theme='blurred', cameraMake='', camera='', lens='',
                               focalLength='', exposure='', capturedAt='')
    for style in ['centered', 'detailed']:
        card, _, _ = render(folder, source, theme='blurred', watermarkStyle=style)
        actual = card.crop((0, card.height-result['footerHeight'], card.width, card.height)).convert('L')
        background = empty.crop((0, empty.height-result['footerHeight'], empty.width, empty.height)).convert('L')
        differences = [a-b for a, b in zip(actual.tobytes(), background.tobytes())]
        check(max(differences) <= 1 or min(differences) >= -1, 'Mixed background used inconsistent ink colors')
        check(max(differences)-min(differences) > 20, 'Mixed background lost the watermark')

    # Exercise thumbnail downsampling on a photo larger than the background's 2048px limit.
    large = photo.resize((3200, 2400)); large.save(source)
    card, _, _ = render(folder, source, theme='blurred', watermarkStyle='centered')
    check(card.size == (3328, 2720), 'Large background changed dimensions')
    check(card.crop((64, 64, 3264, 2464)).tobytes() == large.tobytes(), 'Large blurred background changed the photo')

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
    photo = photo.resize((800, 400))
    for orientation in range(1, 9):
        exif = Image.Exif(); exif[274] = orientation
        jpeg = folder / 'oriented.jpg'; photo.save(jpeg, quality=95, subsampling=0, exif=exif)
        card, _, _ = render(folder, jpeg, name='oriented-output.jpg', theme='blurred', watermarkStyle='centered')
        bitmap, _, _ = render(folder, jpeg, theme='blurred', watermarkStyle='centered')
        check(card.size == bitmap.size, 'Bitmap and JPEG geometry disagree')
        strip = (0, 0, card.width, round(card.width/1.04*0.02))
        delta = ImageStat.Stat(ImageChops.difference(card.crop(strip), bitmap.crop(strip)))
        check(max(delta.mean) < 6, f'Background orientation differs between render paths: {orientation}')

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
        photo_width = 299 if orientation >= 5 else 411
        border = math.ceil(math.floor(photo_width*0.02+0.5)/block)*block if layout == 'bordered' else 0
        footer = result['footerHeight']
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
