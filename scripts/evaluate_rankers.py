"""Frozen synthetic comparison through production eligibility and language routing.

Never reads personal text or changes the installed input method. Fresh candidate
snapshots use isolated copies of the packaged non-learning Rime profile.
"""
import argparse
import ctypes
import hashlib
import json
import os
import shutil
import statistics
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path[:0] = [str(ROOT / 'worker'), str(ROOT / 'vendor/kev')]


def evaluate_decision(ranker, case, *, strategy, use_cache):
    from decision import DecisionService
    class StrategyRanker:
        def rank(self, prefix, pending, words, **kwargs):
            return ranker.rank(prefix, pending, words, use_cache=use_cache, strategy=strategy)
    body = {key: case[key] for key in ('prefix', 'pinyin', 'pending', 'candidates', 'candidate_ends')}
    return DecisionService(StrategyRanker()).decision(dict(body, revision=0, strategy=strategy))


def summarize(rows):
    labeled = [row for row in rows if row['acceptable']]
    supplied = [row for row in labeled if row['target_supplied']]
    ranked = [row for row in rows if row['ranked']]
    result = dict(cases=len(rows), labeled_cases=len(labeled), target_supplied=len(supplied),
        missing_target=len(labeled)-len(supplied), inference_cases=len(ranked),
        inference_after_english_routing=sum(row['route']!='english' for row in ranked),
        single_eligible_or_unavailable=len(rows)-len(ranked),
        no_context_cases=sum(row['category']=='no-context' for row in rows),
        no_fit_cases=sum(row['category']=='no-fit' for row in rows),
        baseline_correct=sum(row['baseline'] in row['acceptable'] for row in labeled),
        baseline_correct_when_target_supplied=sum(row['baseline'] in row['acceptable'] for row in supplied))
    for arm in ('kev', 'continuation'):
        result[arm+'_correct'] = sum(row[arm] in row['acceptable'] for row in labeled)
        result[arm+'_correct_when_target_supplied'] = sum(row[arm] in row['acceptable'] for row in supplied)
        result[arm+'_no_context_keep'] = sum(row[arm+'_keep'] for row in rows if row['category']=='no-context')
        result[arm+'_no_fit_keep'] = sum(row[arm+'_keep'] for row in rows if row['category']=='no-fit')
        result[arm+'_cache_hits'] = sum(row[arm+'_cache_hit'] for row in ranked)
        result[arm+'_cache_choice_changes'] = sum(row[arm+'_cache_choice_changed'] for row in ranked)
        for kind, field in [('fresh', arm+'_ms'), ('cached', arm+'_cached_ms')]:
            result[arm+'_median_'+kind+'_ms'] = statistics.median(row[field] for row in ranked) if ranked else 0
        if rows and arm+'_effective' in rows[0]:
            result[arm+'_effective_correct'] = sum(row[arm+'_effective'] in row['acceptable'] for row in labeled)
    if rows and 'expected_language' in rows[0]:
        result['route_matched'] = sum(row['route']==row['expected_language'] for row in rows)
        result['route_false_english'] = sum(row['route']=='english' and row['expected_language']=='chinese' for row in rows)
        result['route_english'] = sum(row['route']=='english' for row in rows)
    return result


def capture_cases(labels, output):
    """Compile a small C API bridge; candidate coverage uses native production C."""
    dist = ROOT / '.build/rime/dist'
    shared = ROOT / '.build/package-data/SharedSupport'
    profile = ROOT / '.build/package-data/Resources/Profile'
    with tempfile.TemporaryDirectory(prefix='telepathy-static-ranker-') as directory:
        temporary = Path(directory)
        bridge = temporary / 'capture.dylib'
        subprocess.run(['xcrun', 'clang', '-Wall', '-Wextra', '-shared', '-fPIC',
            '-I'+str(dist/'include'), '-I'+str(ROOT/'native/Sources'),
            str(ROOT/'experiments/prediction/capture_rime.c'), str(ROOT/'native/Sources/Coverage.c'),
            '-L'+str(dist/'lib'), '-lrime', '-Wl,-rpath,'+str(dist/'lib'), '-o', str(bridge)], check=True)
        user = temporary / 'Rime'
        shutil.copytree(profile, user)
        lib = ctypes.CDLL(str(bridge))
        lib.tp_open.argtypes = [ctypes.c_char_p]*2
        lib.tp_lookup.argtypes = [ctypes.c_char_p]
        lib.tp_text.argtypes = [ctypes.c_int]
        lib.tp_text.restype = ctypes.c_char_p
        lib.tp_end.argtypes = [ctypes.c_int]
        lib.tp_version.restype = ctypes.c_char_p
        previous = Path.cwd()
        os.chdir(shared)
        opened = False
        try:
            opened = bool(lib.tp_open(str(shared).encode(), str(user).encode()))
            if not opened:
                raise RuntimeError('Cannot initialize the packaged Wanxiang profile')
            version = lib.tp_version().decode()
            rows = []
            for case in labels:
                if not lib.tp_lookup(case['pinyin'].encode()):
                    raise RuntimeError('No Rime snapshot for '+case['id'])
                count = min(lib.tp_count(), 12)
                words = [lib.tp_text(i).decode() for i in range(count)]
                ends = [lib.tp_end(i) for i in range(count)]
                if not words or any(end<=0 for end in ends):
                    raise RuntimeError('Invalid native candidate coverage for '+case['id'])
                rows.append(dict(case, candidates=words, candidate_ends=ends, librime_version=version))
        finally:
            if opened:
                lib.tp_close()
            os.chdir(previous)
    output.write_text(json.dumps(rows, ensure_ascii=False, indent=2)+'\n')
    return rows


def evaluate_cases(ranker, cases):
    from decision import DecisionService
    router = DecisionService(ranker)
    rows = []
    for case in cases:
        body = {key: case[key] for key in ('prefix', 'pinyin', 'pending', 'candidates', 'candidate_ends')}
        route = router.language(dict(body, revision=0))
        indices = [i for i, end in enumerate(case['candidate_ends']) if end>=case['candidate_ends'][0]]
        words = [case['candidates'][i] for i in indices]
        row = dict(id=case['id'], category=case['category'], prefix=case['prefix'], pinyin=case['pending'],
            words=words, candidates=case['candidates'], candidate_ends=case['candidate_ends'],
            acceptable=case['acceptable'], target_supplied=any(word in case['acceptable'] for word in words),
            baseline=case['candidates'][0], expected_language=case.get('expected_language', 'chinese'),
            route=route['language'], route_result=route)
        for arm in ('kev', 'continuation'):
            # Warm relevant shapes once. The uncached pass then measures fresh
            # prefill without invalidating the exact-key cached prefix.
            warm = evaluate_decision(ranker, case, strategy=arm, use_cache=True)
            fresh = evaluate_decision(ranker, case, strategy=arm, use_cache=False)
            cached = evaluate_decision(ranker, case, strategy=arm, use_cache=True)
            chosen = case['candidates'][fresh['order'][0]]
            row.update({arm:chosen, arm+'_keep':fresh.get('keep', True), arm+'_ms':fresh.get('request_ms', 0),
                arm+'_cached_ms':cached.get('request_ms', 0), arm+'_cache_hit':cached.get('cache_hit', False),
                arm+'_cache_choice_changed':fresh['order'][0]!=cached['order'][0] or fresh.get('keep')!=cached.get('keep'),
                arm+'_effective':case['pending'] if route['language']=='english' else chosen,
                arm+'_result':fresh, arm+'_cached_result':cached, arm+'_warm_ms':warm.get('request_ms', 0)})
            row['ranked'] = fresh.get('ranked', False)
        rows.append(row)
        print(case['id'], 'target='+','.join(case['acceptable']), 'route='+row['route'],
              'kev='+row['kev'], 'continuation='+row['continuation'], flush=True)
    return dict(summary=summarize(rows), rows=rows)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--model-dir', type=Path, default=Path.home()/'Library/Application Support/Telepathy/models')
    parser.add_argument('--capture', action='store_true')
    parser.add_argument('--capture-only', action='store_true')
    parser.add_argument('--fresh-labels', type=Path, default=ROOT/'experiments/prediction/fresh-labels.json')
    parser.add_argument('--fresh-cases', type=Path, default=ROOT/'experiments/prediction/fresh-cases.json')
    parser.add_argument('--output', type=Path, default=ROOT/'experiments/prediction/continuation-results.json')
    args = parser.parse_args()
    labels = json.loads(args.fresh_labels.read_text())
    freeze = json.loads((ROOT/'experiments/prediction/fresh-freeze.json').read_text())
    digest = hashlib.sha256(args.fresh_labels.read_bytes()).hexdigest()
    if digest != freeze['labels_sha256']:
        raise ValueError('Frozen label digest changed')
    if args.capture or args.capture_only:
        capture_cases(labels, args.fresh_cases)
    if args.capture_only:
        print('Captured', len(labels), 'fresh static snapshots; no model scores run.')
        return
    fresh = json.loads(args.fresh_cases.read_text())
    if [{key: case[key] for key in label} for label, case in zip(labels, fresh)] != labels or len(fresh)!=len(labels):
        raise ValueError('Captured cases differ from frozen labels')
    original = [case for case in json.loads((ROOT/'experiments/language-routing/cases.json').read_text())
                if case['category']=='chinese-regression']
    old_labels = json.loads((ROOT/'experiments/prediction/labels.json').read_text())
    original = [dict(case, acceptable=old_labels[case['id']]) for case in original]
    from kev_ranker import KevRanker
    ranker = KevRanker(args.model_dir)
    report = dict(quantization='mxfp8', model_info=ranker.model_info,
                  label_sha256=digest, candidate_sha256=hashlib.sha256(args.fresh_cases.read_bytes()).hexdigest(),
                  old=evaluate_cases(ranker, original), fresh=evaluate_cases(ranker, fresh))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n')
    print(json.dumps({group:report[group]['summary'] for group in ('old', 'fresh')}, indent=2))


if __name__ == '__main__':
    main()
