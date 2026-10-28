#!/usr/bin/env python3
"""Unpack and run the actual deliverable from a separate directory."""
import argparse
import hashlib
import json
import platform
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path
from PIL import Image

root = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(root / 'scripts'))
from release import cli_version, parse_version, source_version

parser = argparse.ArgumentParser(description='Verify the actual plugin ZIP')
parser.add_argument('archive', type=Path)
archive = parser.parse_args().archive.resolve()
assert archive.is_file(), f'Missing package: {archive}'
checksum_path = archive.with_suffix('.zip.sha256')
assert checksum_path.is_file(), f'Missing checksum: {checksum_path}'
assert checksum_path.read_text() == f'{hashlib.sha256(archive.read_bytes()).hexdigest()}  {archive.name}\n'
with zipfile.ZipFile(archive) as package:
    executable = package.getinfo('exifmark.lrplugin/bin/exifmark-render')
    assert (executable.external_attr >> 16) & 0o111, 'Executable permission missing from ZIP'
    assert all(p.filename.startswith('exifmark.lrplugin/') for p in package.infolist())
    assert all('..' not in Path(p.filename).parts for p in package.infolist())
    assert not any('__MACOSX' in p.filename or '.DS_Store' in p.filename for p in package.infolist())
    required = {
        'Info.lua', 'ExportFilter.lua', 'Metadata.lua', 'Settings.lua', 'Json.lua', 'PluginInfo.lua',
        'README.txt', 'NOTICE.txt', 'licenses/libjpeg-turbo-LICENSE.md', 'licenses/README.ijg',
        'bin/exifmark-render', 'bin/ExifmarkRenderer_ExifmarkCore.bundle/sony-white.pdf',
        'bin/ExifmarkRenderer_ExifmarkCore.bundle/sony-black.pdf', 'build-info.json',
        'bin/ExifmarkRenderer_ExifmarkCore.bundle/CameraNames.json',
    }
    for svg in (root / 'assets').glob('*.svg'):
        for theme in ['black', 'white']:
            required.add(f'bin/ExifmarkRenderer_ExifmarkCore.bundle/{svg.stem}-{theme}.pdf')
    assert {'exifmark.lrplugin/' + name for name in required} <= set(package.namelist())
    information = json.loads(package.read('exifmark.lrplugin/build-info.json'))
    packaged_version = parse_version(package.read('exifmark.lrplugin/Info.lua').decode())
    assert packaged_version[:3] == source_version(root)
    assert packaged_version[3] == information['build'] > 0
    assert information['version'] == '.'.join(map(str, packaged_version[:3]))
    assert information['short_commit'] == information['commit'][:12]
    assert information['archive'] == archive.name
    assert information['commit'] == subprocess.check_output(['git', '-C', str(root), 'rev-parse', 'HEAD'], text=True).strip()
    assert information['build'] == int(subprocess.check_output(['git', '-C', str(root), 'rev-list', '--count', 'HEAD'], text=True))

with tempfile.TemporaryDirectory(prefix='exifmark-install-') as folder:
    directory = Path(folder)
    subprocess.run(['/usr/bin/ditto', '-x', '-k', str(archive), str(directory)], check=True)
    binary = directory / 'exifmark.lrplugin/bin/exifmark-render'
    subprocess.run(['/usr/bin/codesign', '--verify', '--strict', str(binary)], check=True)
    architectures = subprocess.check_output(['/usr/bin/lipo', '-archs', str(binary)], text=True)
    assert 'arm64' in architectures and 'x86_64' in architectures
    assert platform.machine() in architectures
    actual_version = subprocess.check_output([str(binary), '--version'], text=True).strip()
    assert actual_version == cli_version(information), actual_version
    source = directory / 'source.tif'; Image.new('RGB', (480,320), (60,100,140)).save(source)
    request = dict(version=1, input=str(source), output=str(directory/'result.jpg'), theme='white',
                   camera='ILCE-7M4', lens='FE 35mm F1.8 · 35mm', exposure='f/2.8 · 1/250s · ISO 100',
                   capturedAt='2026.10.27 09:41', quality=0.9)
    path = directory/'request.json'; path.write_text(json.dumps(request))
    result = subprocess.run([str(binary), '--request', str(path)], capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    assert Image.open(directory/'result.jpg').size == (500,368)
    # Prove the relocated installation resolves its own catalog, independently of build paths.
    request['cameraMake'] = 'SONY'; path.write_text(json.dumps(request))
    result = subprocess.run([str(binary), '--request', str(path)], capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    mapped_pixels = Image.open(directory/'result.jpg').tobytes()
    request['cameraCustomName'] = 'SONY α7 IV'; path.write_text(json.dumps(request))
    result = subprocess.run([str(binary), '--request', str(path)], capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    assert Image.open(directory/'result.jpg').tobytes() == mapped_pixels
    request.pop('cameraCustomName')
    request['layout'] = 'bottomOnly'; path.write_text(json.dumps(request))
    result = subprocess.run([str(binary), '--request', str(path)], capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    assert Image.open(directory/'result.jpg').size == (480,358)
    request['output'] = str(directory/'card.tif'); path.write_text(json.dumps(request))
    result = subprocess.run([str(binary), '--request', str(path)], capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    with Image.open(directory/'card.tif') as card:
        assert card.format == 'TIFF' and card.size == (480,358)
    original_jpeg = (directory/'result.jpg').read_bytes()
    install = directory/'install.json'
    install.write_text(json.dumps(dict(input=str(directory/'result.jpg'), output=str(directory/'installed.jpg'))))
    result = subprocess.run([str(binary), '--install-jpeg', str(install)], capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    assert (directory/'installed.jpg').read_bytes() == original_jpeg
    # Exercise every style from the relocated binary, including the JPEG coefficient path.
    request['input'] = str(directory/'installed.jpg')
    request['focalLength'] = '35mm'
    for theme in ['white', 'black', 'blurred']:
        for style in ['detailed', 'centered']:
            request.update(theme=theme, watermarkStyle=style, output=str(directory/f'{theme}-{style}.jpg'))
            path.write_text(json.dumps(request))
            result = subprocess.run([str(binary), '--request', str(path)], capture_output=True, text=True)
            assert result.returncode == 0, result.stderr
            assert Image.open(request['output']).format == 'JPEG'
    shutil.rmtree(binary.parent/'ExifmarkRenderer_ExifmarkCore.bundle')
    request['output'] = str(directory/'missing-logo.jpg'); path.write_text(json.dumps(request))
    result = subprocess.run([str(binary), '--request', str(path)], capture_output=True, text=True)
    assert result.returncode == 1 and '字标资源' in result.stderr, result.stderr
    assert not (directory/'missing-logo.jpg').exists()
print(f'Package validation: {platform.machine()}, version, checksum, signatures, both architectures, relocated render and missing resources passed')
