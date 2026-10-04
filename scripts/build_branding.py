"""Render the original SVG artwork using macOS CoreGraphics and iconutil.

No image library or third-party renderer is required. Edit Telepathy.svg to
change the mark; the tile's palette and dimensions live in Telepathy-app.svg.
"""
import argparse
import json
import re
import subprocess
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BRANDING = ROOT / 'assets/branding'
SVG = '{http://www.w3.org/2000/svg}'


def specification():
    mark = ET.parse(BRANDING / 'Telepathy.svg').getroot()
    tile = ET.parse(BRANDING / 'Telepathy-app.svg').getroot()
    paths = []
    for node in mark.iter(SVG + 'path'):
        tokens = re.findall(r'[A-Za-z]|-?(?:\d*\.\d+|\d+)', node.attrib['d'])
        commands, index = [], 0
        counts = {'M': 2, 'L': 2, 'H': 1, 'V': 1, 'C': 6}
        while index < len(tokens):
            command = tokens[index]
            if command not in counts:
                raise ValueError('The branding renderer supports absolute M/L/H/V/C SVG paths.')
            count = counts[command]
            commands.append([command, *map(float, tokens[index + 1:index + count + 1])])
            index += count + 1
        paths.append(commands)
    group = mark.find(SVG + 'g')
    tile_rect = tile.find(f"{SVG}rect[@id='tile-shape']")
    tile_mark = tile.find(f"{SVG}g[@id='mark']")
    transform = list(map(float, re.findall(r'-?(?:\d*\.\d+|\d+)', tile_mark.attrib['transform'])))
    return {
        'paths': paths,
        'circles': [[float(node.attrib[k]) for k in ('cx', 'cy', 'r')]
                    for node in mark.iter(SVG + 'circle')],
        'stroke': float(group.attrib['stroke-width']),
        'tile': [float(tile_rect.attrib[k]) for k in ('x', 'y', 'width', 'height', 'rx')],
        'gradient': [node.attrib['stop-color'] for node in tile.iter(SVG + 'stop')],
        'markColor': tile_mark.attrib['stroke'],
        'markTransform': transform,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output-dir', type=Path, default=BRANDING)
    parser.add_argument('--preview', action='store_true', help='Also render the small-size study in docs/branding.')
    args = parser.parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='telepathy-branding-') as work:
        work = Path(work)
        spec = work / 'artwork.json'
        spec.write_text(json.dumps(specification()))
        executable = work / 'render-branding'
        subprocess.run(['xcrun', 'swiftc', str(ROOT / 'scripts/render_branding.swift'),
                        '-o', str(executable)], check=True)
        subprocess.run([str(executable), str(spec), str(args.output_dir.resolve()), str(work)], check=True)
        subprocess.run(['iconutil', '-c', 'icns', str(work / 'Telepathy.iconset'),
                        '-o', str(args.output_dir / 'Telepathy.icns')], check=True)
        if args.preview:
            import shutil
            preview = ROOT / 'docs/branding/brand-preview.png'
            preview.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(work / 'brand-preview.png', preview)
    print(args.output_dir.resolve())


if __name__ == '__main__':
    main()
