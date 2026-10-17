"""Render original synthetic fixtures; never captures the user's screen."""
import argparse
import hashlib
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

FONT = '/System/Library/Fonts/STHeiti Light.ttc'


def wrapped(draw, text, font, width):
    lines, line = [], ''
    for char in text:
        if char == '\n' or (line and draw.textlength(line + char, font=font) > width):
            lines.append(line)
            line = '' if char == '\n' else char
        else:
            line += char
    if line:
        lines.append(line)
    return lines


def render(case, canvas, bounds):
    image = Image.new('RGB', tuple(canvas), '#f5f6f8')
    draw = ImageDraw.Draw(image)
    normal = ImageFont.truetype(FONT, 25)
    small = ImageFont.truetype(FONT, 18)
    draw.rectangle((0, 0, canvas[0], 54), fill='#202733')
    draw.text((24, 16), 'Telepathy test fixture', font=small, fill='white')
    draw.rectangle((0, 54, 230, canvas[1]), fill='#e5e8ed')
    y = 88
    for item in case['sidebar']:
        for line in wrapped(draw, item, small, 192):
            draw.text((17, y), line, font=small, fill='#475364')
            y += 25
        y += 20
    draw.text((270, 78), 'Conversation / document', font=small, fill='#667085')
    y = 122
    for index, message in enumerate(case['messages']):
        lines = wrapped(draw, message, normal, 592)
        height = 38 + 36 * len(lines)
        assert y + height < bounds[1] - 20, case['id']
        draw.rounded_rectangle((270, y, 930, y + height), radius=16,
                               fill='#dcecf8' if index % 2 else '#ffffff')
        for j, line in enumerate(lines):
            draw.text((291, y + 17 + j * 36), line, font=normal, fill='#202733')
        y += height + 20
    draw.text((bounds[0], bounds[1] - 28), case.get('input_label', 'Reply / write here'),
              font=small, fill='#475364')
    draw.rounded_rectangle(tuple(bounds), radius=12, fill='white', outline='#2878d4', width=3)
    draw.text((bounds[0] + 19, bounds[1] + 25), case['raw'], font=normal, fill='#202733')
    caret = bounds[0] + 20 + draw.textlength(case['raw'], font=normal)
    draw.line((caret, bounds[1] + 24, caret, bounds[1] + 55), fill='#202733', width=2)
    return image


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    source = Path(__file__).with_name('cases.json')
    dataset = json.loads(source.read_text())
    args.output.mkdir(parents=True, exist_ok=True)
    manifest = {'dataset_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
                'font': FONT, 'canvas': dataset['canvas'], 'fixtures': []}
    for case in dataset['cases']:
        image = render(case, dataset['canvas'], dataset['focused_input_bounds'])
        path = args.output / (case['id'] + '.png')
        image.save(path)
        manifest['fixtures'].append({'id': case['id'], 'file': path.name,
                                     'sha256': hashlib.sha256(path.read_bytes()).hexdigest()})
    (args.output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(json.dumps({'fixtures': len(manifest['fixtures']), 'dataset_sha256': manifest['dataset_sha256']}))


if __name__ == '__main__':
    main()
