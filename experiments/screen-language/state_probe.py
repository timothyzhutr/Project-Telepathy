"""Compare fresh and cached text scores before/after vision on one model."""
import argparse
import json
import os
from pathlib import Path
import time

from shared_ranking import ROOT, make_vision_ranker
from shared_supplement import scenes
from shared_vision import read_options


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--model', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    os.environ.update(HF_HUB_OFFLINE='1', TRANSFORMERS_OFFLINE='1')
    import mlx.core as mx
    mx.set_default_device(mx.gpu)
    mx.set_cache_limit(128 << 20)
    ranker, model, processor = make_vision_ranker(args.model)
    cases = json.loads(Path(__file__).with_name('heldout-cases.json').read_text())['cases']
    frozen = json.loads((ROOT/'experiments/language-routing/cases.json').read_text())
    long_case = max((c for c in frozen if c['category']=='chinese-regression'), key=lambda c:len(c['prefix']))
    long_words = [w for w, end in zip(long_case['candidates'],long_case['candidate_ends']) if end>=long_case['candidate_ends'][0]]
    prefixes = [('short-zh','这个职位拥有决定预算分配的',['权力','权利','全力']),
                ('long-zh',long_case['prefix'],long_words),
                ('short-en','I would like to make a ',['test','plan','meeting'])]
    rows = []
    for name, prefix, words in prefixes:
        before = ranker.continuation_scorer.score(prefix, words, use_cache=False)
        ranker.continuation_scorer.score(prefix, words, use_cache=True)
        for index in [0,17,18,24]:
            image = scenes(cases[index], bool(index%2))
            messages = [{'role':'user','content':[{'type':'image'}]}, {'role':'user','content':
                '蓝色输入框上方的当前对话或正文主要使用哪种语言？忽略菜单和侧栏。\nA: 中文\nB: 英文'}]
            started = time.perf_counter()
            vision = read_options(model, processor, messages, ['chinese','english'], image=image)
            cached = ranker.continuation_scorer.score(prefix, words, use_cache=True)
            assert cached['cache_hit']
            fresh = ranker.continuation_scorer.score(prefix, words, use_cache=False)
            delta_cached = max(abs(a-b) for a,b in zip(before['scores'],cached['scores']))
            delta_fresh = max(abs(a-b) for a,b in zip(before['scores'],fresh['scores']))
            assert delta_cached < 1e-5 and delta_fresh < 1e-5, (name,delta_cached,delta_fresh)
            rows.append({'prefix_id':name, 'image_id':cases[index]['id'], 'context_tokens':fresh['context_tokens'],
                'max_cached_delta':delta_cached, 'max_fresh_delta':delta_fresh,
                'image_ms':vision['request_ms'], 'image_then_cached_and_fresh_word_ms':(time.perf_counter()-started)*1000,
                'model_instance_id':id(model)})
    args.output.write_text(json.dumps({'model_instance_id':id(model),'checks':rows,'all_passed':True},indent=2)+'\n')
    print('Passed',len(rows),'image/text interleavings')


if __name__=='__main__':
    main()
