#!/usr/bin/env python3
"""Regenerate the two bundled vector PDFs. Development-only dependency: fonttools."""
from pathlib import Path
import xml.etree.ElementTree as ET
from fontTools.pens.recordingPen import RecordingPen
from fontTools.svgLib.path import parse_path

root = Path(__file__).resolve().parents[1]
svg = ET.parse(root / 'assets/sony.svg').getroot()
_, _, width, height = map(float, svg.attrib['viewBox'].split())
commands = []
for element in svg.iter('{http://www.w3.org/2000/svg}path'):
    pen = RecordingPen()
    parse_path(element.attrib['d'], pen)
    for operation, points in pen.value:
        values = ' '.join(f'{value:.6f}' for point in points for value in point)
        if operation == 'moveTo': commands.append(f'{values} m')
        elif operation == 'lineTo': commands.append(f'{values} l')
        elif operation == 'curveTo': commands.append(f'{values} c')
        elif operation == 'closePath': commands.append('h')
        else: raise ValueError(f'Unsupported vector operation: {operation}')

resource = root / 'renderer/Sources/ExifmarkCore/Resources'
resource.mkdir(parents=True, exist_ok=True)
for name, fill in [('black', 0), ('white', 1)]:
    stream = (f'q\n1 0 0 -1 0 {height:.6f} cm\n{fill} g\n'
              + '\n'.join(commands) + '\nf\nQ\n').encode('ascii')
    objects = [
        b'<< /Type /Catalog /Pages 2 0 R >>',
        b'<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
        (f'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 {width} {height}] '
         '/Resources << >> /Contents 4 0 R >>').encode('ascii'),
        f'<< /Length {len(stream)} >>\nstream\n'.encode() + stream + b'endstream',
    ]
    data = bytearray(b'%PDF-1.4\n%\xe2\xe3\xcf\xd3\n')
    offsets = [0]
    for index, content in enumerate(objects, 1):
        offsets.append(len(data))
        data.extend(f'{index} 0 obj\n'.encode() + content + b'\nendobj\n')
    xref = len(data)
    data.extend(f'xref\n0 {len(offsets)}\n0000000000 65535 f \n'.encode())
    for offset in offsets[1:]: data.extend(f'{offset:010d} 00000 n \n'.encode())
    data.extend((f'trailer\n<< /Size {len(offsets)} /Root 1 0 R >>\n'
                 f'startxref\n{xref}\n%%EOF\n').encode())
    path = resource / f'sony-{name}.pdf'
    path.write_bytes(data)
    print(path.relative_to(root))
