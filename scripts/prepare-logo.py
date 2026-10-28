#!/usr/bin/env python3
"""Regenerate monochrome vector PDFs from bundled SVGs; requires fonttools."""
from pathlib import Path
import re
import xml.etree.ElementTree as ET
from fontTools.misc.transform import Transform
from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.qu2cuPen import Qu2CuPen
from fontTools.pens.recordingPen import RecordingPen
from fontTools.pens.transformPen import TransformPen
from fontTools.svgLib.path import parse_path

ROOT = Path(__file__).resolve().parents[1]
RESOURCE = ROOT / 'renderer/Sources/ExifmarkCore/Resources'


def transform(value):
    result = Transform()
    for name, arguments in re.findall(r'([a-zA-Z]+)\(([^)]*)\)', value):
        args = [float(n) for n in re.split(r'[\s,]+', arguments.strip())]
        if name == 'matrix' and len(args) == 6:
            result = result.transform(Transform(*args))
        elif name == 'translate' and len(args) in (1, 2):
            result = result.translate(args[0], args[1] if len(args) == 2 else 0)
        elif name == 'scale' and len(args) in (1, 2):
            result = result.scale(args[0], args[1] if len(args) == 2 else args[0])
        else:
            raise ValueError(f'Unsupported SVG transform: {name}({arguments})')
    return result


def paths(element, matrix=Transform(), fill='black', rule='nonzero'):
    tag = element.tag.split('}')[-1]
    if tag in ('defs', 'metadata', 'title', 'desc', 'namedview'):
        return
    style = dict(item.split(':', 1) for item in element.get('style', '').split(';') if ':' in item)
    fill = element.get('fill', style.get('fill', fill))
    rule = element.get('fill-rule', style.get('fill-rule', rule))
    matrix = matrix.transform(transform(element.get('transform', '')))
    if tag == 'path' and fill != 'none':
        pen = RecordingPen()
        parse_path(element.attrib['d'], TransformPen(Qu2CuPen(pen, max_err=0.001, all_cubic=True), matrix))
        yield pen, rule
    elif tag in ('rect', 'circle', 'ellipse', 'polygon', 'polyline', 'use', 'text'):
        raise ValueError(f'Convert SVG {tag} to paths first')
    for child in element:
        yield from paths(child, matrix, fill, rule)


def pdf(svg, name, fill):
    outlines = list(paths(ET.parse(svg).getroot()))
    bounds = BoundsPen(None)
    for pen, _ in outlines:
        pen.replay(bounds)
    x, y, right, bottom = bounds.bounds
    width, height = right - x, bottom - y
    commands = [f'q\n1 0 0 -1 {-x:.6f} {bottom:.6f} cm\n{fill} g']
    for pen, rule in outlines:
        for operation, points in pen.value:
            values = ' '.join(f'{value:.6f}' for point in points for value in point)
            if operation == 'moveTo': commands.append(f'{values} m')
            elif operation == 'lineTo': commands.append(f'{values} l')
            elif operation == 'curveTo': commands.append(f'{values} c')
            elif operation == 'closePath': commands.append('h')
            elif operation == 'endPath': pass
            else: raise ValueError(f'Unsupported vector operation: {operation}')
        commands.append('f*' if rule == 'evenodd' else 'f')
    stream = ('\n'.join(commands) + '\nQ\n').encode('ascii')
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
    path = RESOURCE / f'{svg.stem}-{name}.pdf'
    path.write_bytes(data)
    print(path.relative_to(ROOT))


if __name__ == '__main__':
    RESOURCE.mkdir(parents=True, exist_ok=True)
    for svg in sorted((ROOT / 'assets').glob('*.svg')):
        for name, fill in [('black', 0), ('white', 1)]:
            pdf(svg, name, fill)
