#!/usr/bin/env python3
"""Unpack and run the actual deliverable from a separate directory."""
import json
import shutil
import subprocess
import tempfile
import zipfile
from pathlib import Path
from PIL import Image

root = Path(__file__).resolve().parents[1]
archive = root / 'dist/exify-0.1.0-macos.zip'
with zipfile.ZipFile(archive) as package:
    executable = package.getinfo('exify.lrplugin/bin/exify-render')
    assert (executable.external_attr >> 16) & 0o111, 'Executable permission missing from ZIP'
    assert all(p.filename.startswith('exify.lrplugin/') for p in package.infolist())
    assert not any('__MACOSX' in p.filename or '.DS_Store' in p.filename for p in package.infolist())

with tempfile.TemporaryDirectory(prefix='exify-install-') as folder:
    directory = Path(folder)
    subprocess.run(['/usr/bin/ditto', '-x', '-k', str(archive), str(directory)], check=True)
    binary = directory / 'exify.lrplugin/bin/exify-render'
    subprocess.run(['/usr/bin/codesign', '--verify', '--strict', str(binary)], check=True)
    architectures = subprocess.check_output(['/usr/bin/lipo', '-archs', str(binary)], text=True)
    assert 'arm64' in architectures and 'x86_64' in architectures
    subprocess.run([str(binary), '--version'], check=True, capture_output=True)
    source = directory / 'source.tif'; Image.new('RGB', (480,320), (60,100,140)).save(source)
    request = dict(version=1, input=str(source), output=str(directory/'result.jpg'), theme='white',
                   camera='ILCE-7M4', lens='FE 35mm F1.8 · 35mm', exposure='f/2.8 · 1/250s · ISO 100',
                   capturedAt='2026.10.27 09:41', quality=0.9)
    path = directory/'request.json'; path.write_text(json.dumps(request))
    result = subprocess.run([str(binary), '--request', str(path)], capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    assert Image.open(directory/'result.jpg').size == (480,368)
    shutil.rmtree(binary.parent/'ExifyRenderer_ExifyCore.bundle')
    request['output'] = str(directory/'missing-logo.jpg'); path.write_text(json.dumps(request))
    result = subprocess.run([str(binary), '--request', str(path)], capture_output=True, text=True)
    assert result.returncode == 1 and 'SONY' in result.stderr, result.stderr
    assert not (directory/'missing-logo.jpg').exists()
print('Package validation: signatures, both architectures, relocated render and missing resources passed')
