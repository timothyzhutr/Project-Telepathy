"""Production continuation/routing logic on exactly one loaded text/vision model."""
import argparse
import gc
import hashlib
import json
import math
import os
import statistics
from pathlib import Path
import sys
import time
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT / 'worker'), str(ROOT / 'vendor/kev'), str(ROOT / 'scripts')]


def summarize(rows):
    def timings(values):
        values = sorted(values)
        if not values:
            return {'samples': 0, 'median': None, 'p95': None}
        x = (len(values) - 1) * .95
        low, high = math.floor(x), math.ceil(x)
        return {'samples': len(values), 'median': statistics.median(values),
                'p95': values[low] + (values[high] - values[low]) * (x - low)}
    summary = {}
    for group in ['old', 'fresh']:
        selected = [r for r in rows if r['group'] == group]
        labelled = [r for r in selected if r['acceptable']]
        inferred = [r for r in selected if r['fresh'].get('ranked') and r['fresh'].get('inferred')]
        summary[group] = {'cases': len(selected), 'labeled': len(labelled),
            'matching': sum(r['selected'] in r['acceptable'] for r in labelled),
            'missing_target': sum(not r['target_supplied'] for r in labelled),
            'fresh_worker_ms': timings([r['fresh']['request_ms'] for r in inferred]),
            'cached_worker_ms': timings([r['cached']['request_ms'] for r in inferred]),
            'cache_choice_changes': sum(r['fresh']['order'][0] != r['cached']['order'][0] for r in selected),
            'cache_hits': sum(r['cached'].get('cache_hit', False) for r in selected)}
    return summary


def make_vision_ranker(path):
    import mlx.core as mx
    from mlx_vlm import load
    from kev_ranker import KevRanker
    from continuation_scorer import ContinuationScorer
    from language_router import LanguageRouter
    model, processor = load(str(path), trust_remote_code=False, use_fast=False)
    # Only a view of the same model: no second module/weight load. Raw text
    # calls bypass multimodal RoPE metadata retained on the language wrapper.
    lm = SimpleNamespace(language_model=model.language_model,
                         make_cache=model.language_model.make_cache)
    ranker = object.__new__(KevRanker)
    ranker.mx = mx
    ranker.tok = processor.tokenizer
    ranker.engine = SimpleNamespace(lm=lm, text=model.language_model.model)
    ranker.continuation_scorer = ContinuationScorer(ranker)
    ranker.language_router = LanguageRouter(ranker)
    return ranker, model, processor


def reference_scores(ranker, prefix, words):
    mx = ranker.mx
    prefix = ranker.cap(prefix)
    base = ranker.tok(prefix, add_special_tokens=False).input_ids
    sequences = [ranker.tok(prefix + word, add_special_tokens=False).input_ids for word in words]
    common = 0
    limit = min(len(base), min(map(len, sequences)) - 1)
    while common < limit and all(ids[common] == base[common] for ids in sequences):
        common += 1
    values = []
    for ids in sequences:
        from mlx_lm.models.cache import make_prompt_cache
        hidden = ranker.engine.text(mx.array([ids[:-1]], dtype=mx.int32),
                                   cache=make_prompt_cache(ranker.engine.lm))
        language = ranker.engine.lm.language_model
        head = getattr(language, 'lm_head', None)
        logits = head(hidden) if head is not None else language.model.embed_tokens.as_linear(hidden)
        logits = logits.astype(mx.float32)
        log_probs = logits - mx.logsumexp(logits, axis=-1, keepdims=True)
        score = sum(log_probs[0, j - 1, ids[j]] for j in range(common, len(ids)))
        mx.eval(score)
        values.append(score.item())
    return values


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--kind', choices=['kev', 'vision'], required=True)
    parser.add_argument('--model', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--with-images', action='store_true')
    args = parser.parse_args()
    os.environ.update(HF_HUB_OFFLINE='1', TRANSFORMERS_OFFLINE='1', TOKENIZERS_PARALLELISM='false')
    import mlx.core as mx
    mx.set_default_device(mx.gpu)
    mx.set_cache_limit(128 << 20)
    from kev_ranker import KevRanker
    started = time.perf_counter()
    if args.kind == 'kev':
        ranker = KevRanker(Path.home() / 'Library/Application Support/Telepathy/models')
        model, processor = ranker.engine.lm, None
    else:
        ranker, model, processor = make_vision_ranker(args.model)
    load_ms = (time.perf_counter() - started) * 1000
    print(json.dumps({'kind': args.kind, 'load_ms': load_ms, 'model_id': id(model)}), flush=True)
    checks = []
    for prefix, words in [('这个职位拥有决定预算分配的', ['权力', '权利', '全力']),
                          ('我前面试了几个小模型，感觉都', ['不太行', '不', '不太']),
                          ('作为消费者，我们依法享有的', ['权利', '权力'])]:
        actual = ranker.continuation_scorer.score(prefix, words, use_cache=False)['scores']
        expected = reference_scores(ranker, prefix, words)
        delta = max(abs(a - b) for a, b in zip(actual, expected))
        winner_matches = max(range(len(words)), key=lambda i: actual[i]) == max(range(len(words)), key=lambda i: expected[i])
        checks.append({'prefix': prefix, 'words': words, 'branched': actual, 'reference': expected,
                       'max_difference': delta, 'winner_matches': winner_matches,
                       'within_original_tolerance': delta < .1})
        print('reference', json.dumps(checks[-1], ensure_ascii=False), flush=True)
    from evaluate_rankers import evaluate_decision
    old_labels = json.loads((ROOT / 'experiments/prediction/labels.json').read_text())
    old = [dict(c, acceptable=old_labels[c['id']]) for c in json.loads(
        (ROOT / 'experiments/language-routing/cases.json').read_text()) if c['category'] == 'chinese-regression']
    fresh = json.loads((ROOT / 'experiments/prediction/fresh-cases.json').read_text())
    rows = []
    for group, cases in [('old', old), ('fresh', fresh)]:
        for case in cases:
            evaluate_decision(ranker, case, strategy='continuation', use_cache=True)
            fresh_result = evaluate_decision(ranker, case, strategy='continuation', use_cache=False)
            cached_result = evaluate_decision(ranker, case, strategy='continuation', use_cache=True)
            eligible = [w for w, end in zip(case['candidates'], case['candidate_ends']) if end >= case['candidate_ends'][0]]
            selected = case['candidates'][fresh_result['order'][0]]
            row = {'group': group, 'id': case['id'], 'acceptable': case['acceptable'],
                         'target_supplied': any(w in case['acceptable'] for w in eligible),
                         'selected': selected, 'fresh': fresh_result, 'cached': cached_result}
            if args.kind == 'vision' and case['prefix'].strip() and len(eligible) > 1:
                values = reference_scores(ranker, case['prefix'], eligible)
                row['full_reference_scores'] = values
                row['full_reference_selected'] = eligible[max(range(len(eligible)), key=lambda i: values[i])]
            rows.append(row)
            print(group, case['id'], selected, flush=True)
    from decision import DecisionService
    service = DecisionService(ranker)
    routes = []
    for case in json.loads((ROOT / 'experiments/language-routing/cases.json').read_text()):
        request = {k: case[k] for k in ['prefix', 'pinyin', 'pending', 'candidates', 'candidate_ends']}
        result = service.language(dict(request, revision=0))
        routes.append({'id': case['id'], 'expected': case['expected'], 'result': result})
    from mlx.utils import tree_flatten
    report = {'kind': args.kind, 'model_instance_id': id(model), 'load_ms': load_ms,
              'reference_checks': checks, 'ranking': {'summary': summarize(rows), 'rows': rows},
              'routing': {'cases': len(routes), 'matching': sum(r['result']['language'] == r['expected'] for r in routes),
                          'false_english': sum(r['expected'] == 'chinese' and r['result']['language'] == 'english' for r in routes), 'rows': routes},
              'model_weight_bytes': sum(x.nbytes for _, x in tree_flatten(model.parameters())),
              'mlx_peak_memory_bytes': mx.get_peak_memory()}
    if args.with_images:
        from shared_vision import check_images
        report['images'] = check_images(ranker, model, processor)
    import resource
    report['mlx_peak_memory_bytes_including_images'] = mx.get_peak_memory()
    report['process_peak_rss_bytes_macos'] = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({'ranking': report['ranking']['summary'], 'routing': {k: report['routing'][k] for k in ['cases', 'matching', 'false_english']}}, indent=2), flush=True)


if __name__ == '__main__':
    main()
