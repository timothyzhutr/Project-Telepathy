"""A screenshot supplies only the starting Chinese/English bias, before text exists."""
import argparse
import base64
import hashlib
import io
import json
from pathlib import Path
import random
import time
import uuid

import httpx
from PIL import Image

from benchmark import validate_answer, summarize
from render import render

STYLES = {
    'english': ('Which language is mainly used in the conversation or document above the blue input box? '
                'Ignore app menus and sidebars.', {'chinese': 'Chinese', 'english': 'English'}),
    'chinese': ('蓝色输入框上方的当前对话或正文主要使用哪种语言？忽略菜单和侧栏。',
                {'chinese': '中文', 'english': '英文'}),
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--image-tokens', type=int, default=512)
    parser.add_argument('--styles', nargs='+', choices=list(STYLES), default=list(STYLES))
    args = parser.parse_args()
    source = Path(__file__).with_name('prior-cases.json')
    dataset = json.loads(source.read_text())
    args.output.mkdir(parents=True, exist_ok=True)
    selected_styles = {k: STYLES[k] for k in args.styles}
    manifest = {'dataset_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
                'styles': selected_styles, 'image_tokens': args.image_tokens, 'starting_prior_only': True,
                'controls_unscored': True, 'notes': 'Scope narrowed following user clarification; these reuse earlier synthetic contexts.'}
    (args.output / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
    rows = []
    with httpx.Client(timeout=60, trust_env=False) as client, (args.output / 'responses.jsonl').open('w') as receipts:
        ready = client.get('http://127.0.0.1:19876/health')
        ready.raise_for_status()
        (args.output / 'health.json').write_text(json.dumps(ready.json(), indent=2) + '\n')
        for style, (question, definitions) in selected_styles.items():
            for rotation in range(2):
                options = list(definitions)
                if rotation:
                    options.reverse()
                cases = list(dataset['cases'])
                random.Random(20261017 + rotation).shuffle(cases)
                batch = []
                for case in cases:
                    image = render(case, dataset['canvas'], dataset['focused_input_bounds'])
                    buffer = io.BytesIO()
                    image.save(buffer, format='PNG')
                    encoded = base64.b64encode(buffer.getvalue()).decode()
                    reset = client.post('http://127.0.0.1:19877/completion', json={
                        'prompt': 'Reset context ' + uuid.uuid4().hex, 'n_predict': 1})
                    reset.raise_for_status()
                    payload = {'state': {'observation': uuid.uuid4().hex, 'situation': 'Before typing into the blue input box.'},
                               'images': ['data:image/png;base64,' + encoded],
                               'questions': {'language': {'type': 'choice', 'instructions': question,
                                   'criteria': {k: definitions[k] for k in options}}}}
                    row = {'id': case['id'], 'group': case['group'], 'expected': case['expected'],
                           'style': style, 'order': options, 'image_tokens': args.image_tokens,
                           'request_sha256': hashlib.sha256(json.dumps(payload, ensure_ascii=False).encode()).hexdigest()}
                    start = time.perf_counter()
                    try:
                        response = client.post('http://127.0.0.1:19876/v1/systemone', json=payload)
                        row['client_ms'] = (time.perf_counter() - start) * 1000
                        response.raise_for_status()
                        body = response.json()
                        answer = body['answers']['language']
                        if set(answer['probabilities']) != {'chinese', 'english'}:
                            raise ValueError('Incomplete binary distribution')
                        validate_answer({'choice': answer['choice'], 'probabilities':
                                         {**answer['probabilities'], 'uncertain': 0}})
                        assert body['usage']['output_tokens'] == 1
                        row.update(choice=answer['choice'], probabilities=answer['probabilities'], response=body,
                                   cached_tokens=response.headers.get('x-openjev-cached-tokens'))
                    except (httpx.HTTPError, ValueError, KeyError) as exc:
                        row['error'] = str(exc)
                    rows.append(row)
                    batch.append(row)
                    receipts.write(json.dumps(row, ensure_ascii=False) + '\n')
                    receipts.flush()
                print(json.dumps({'style': style, 'order': options,
                                  'scored': summarize([r for r in batch if r['expected']]),
                                  'controls': [{k: r.get(k) for k in ['id', 'choice', 'probabilities']} for r in batch if not r['expected']]}, ensure_ascii=False), flush=True)
    report = {}
    for style in selected_styles:
        batches = []
        for options in [['chinese', 'english'], ['english', 'chinese']]:
            selected = [r for r in rows if r['style'] == style and r['order'] == options]
            batches.append({'order': options, 'scored': summarize([r for r in selected if r['expected']]),
                            'controls': [{k: r.get(k) for k in ['id', 'choice', 'probabilities']} for r in selected if not r['expected']]})
        decisions = {c['id']: [r.get('choice') for r in rows if r['style'] == style and r['id'] == c['id']]
                     for c in dataset['cases'] if c['expected']}
        report[style] = {'orders': batches, 'option_order_changed': sum(len(set(v)) > 1 for v in decisions.values()),
                         'decisions': decisions}
    (args.output / 'summary.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')


if __name__ == '__main__':
    main()
