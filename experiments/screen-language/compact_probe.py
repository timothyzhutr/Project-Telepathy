"""Exploratory shorter prompts after the frozen initial diagnostic; not held-out results."""
import argparse
import base64
import hashlib
import json
from pathlib import Path
import random
import time
import uuid

import httpx

from benchmark import validate_answer, summarize

STYLES = {
    'compact-en': {
        'question': 'Which language should the next reply use? Follow an explicit output-language request; '
                    'otherwise use the conversation language. Ignore menus and the unconverted letters in '
                    'the input field. With insufficient evidence, choose uncertain.',
        'options': {'chinese': 'Chinese', 'english': 'English', 'uncertain': 'Uncertain'},
    },
    'compact-zh': {
        'question': '判断蓝框输入框接下来应该使用的语言。优先遵循明确的回复或翻译目标语言，否则参考当前对话。'
                    '忽略菜单、侧栏和输入框里尚未转换的拼音。证据不足请选择不确定。',
        'options': {'chinese': '中文', 'english': '英文', 'uncertain': '不确定'},
    },
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--fixtures', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    dataset_path = Path(__file__).with_name('cases.json')
    dataset = json.loads(dataset_path.read_text())
    args.output.mkdir(parents=True, exist_ok=True)
    manifest = {'styles': STYLES, 'dataset_sha256': hashlib.sha256(dataset_path.read_bytes()).hexdigest(),
                'interpretation': 'Exploratory prompt variants chosen after observing initial failures. No held-out accuracy claim.',
                'cache_ram_mib': 0, 'image_token_budget': 512}
    (args.output / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
    rows = []
    with httpx.Client(timeout=60, trust_env=False) as client, (args.output / 'responses.jsonl').open('w') as receipts:
        for style, spec in STYLES.items():
            order = list(spec['options'])
            for mode in ['image', 'text']:
                for rotation in range(3 if mode == 'image' else 1):
                    options = order[rotation:] + order[:rotation]
                    cases = list(dataset['cases'])
                    random.Random(20261017 + rotation).shuffle(cases)
                    batch = []
                    for case in cases:
                        reset = client.post('http://127.0.0.1:19877/completion', json={
                            'prompt': 'Clear benchmark context ' + uuid.uuid4().hex, 'n_predict': 1})
                        reset.raise_for_status()
                        state = {'sample_id': uuid.uuid4().hex, 'focus': 'blue-outlined reply input'}
                        payload = {'state': state, 'questions': {'language': {'type': 'choice',
                            'instructions': spec['question'], 'criteria': {k: spec['options'][k] for k in options}}}}
                        if mode == 'image':
                            encoded = base64.b64encode((args.fixtures / (case['id'] + '.png')).read_bytes()).decode()
                            payload['images'] = ['data:image/png;base64,' + encoded]
                        else:
                            state['conversation'] = case['messages']
                            state['field_label'] = case.get('input_label', 'Reply / write here')
                        row = {'id': case['id'], 'style': style, 'mode': mode, 'order': options,
                               'group': case['group'], 'expected': case['expected'],
                               'request_sha256': hashlib.sha256(json.dumps(payload, ensure_ascii=False).encode()).hexdigest()}
                        start = time.perf_counter()
                        try:
                            response = client.post('http://127.0.0.1:19876/v1/systemone', json=payload)
                            row['client_ms'] = (time.perf_counter() - start) * 1000
                            response.raise_for_status()
                            body = response.json()
                            answer = validate_answer(body['answers']['language'])
                            assert body['usage']['output_tokens'] == 1
                            row.update(choice=answer['choice'], probabilities=answer['probabilities'], response=body,
                                       cached_tokens=response.headers.get('x-openjev-cached-tokens'))
                        except (httpx.HTTPError, ValueError, KeyError) as exc:
                            row['error'] = str(exc)
                        rows.append(row)
                        batch.append(row)
                        receipts.write(json.dumps(row, ensure_ascii=False) + '\n')
                        receipts.flush()
                    print(json.dumps({'style': style, 'mode': mode, 'rotation': rotation, **summarize(batch)}, ensure_ascii=False), flush=True)
    report = {}
    for style, spec in STYLES.items():
        order = list(spec['options'])
        report[style] = {}
        for mode in ['image', 'text']:
            primary = [r for r in rows if r['style'] == style and r['mode'] == mode and r['order'] == order]
            report[style][mode] = summarize(primary)
            report[style][mode]['groups'] = {g: summarize([r for r in primary if r['group'] == g])
                                            for g in ['context', 'explicit', 'ambiguous']}
        image_rows = [r for r in rows if r['style'] == style and r['mode'] == 'image']
        decisions = {c['id']: [r.get('choice') for r in image_rows if r['id'] == c['id']] for c in dataset['cases']}
        report[style]['option_order'] = {'changed': sum(len(set(v)) > 1 for v in decisions.values()), 'decisions': decisions}
    (args.output / 'summary.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')


if __name__ == '__main__':
    main()
