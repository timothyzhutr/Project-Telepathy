"""Measure normal typing/image memory without the full-vocabulary reference arm."""
import argparse
import json
import os
from pathlib import Path
import resource
import subprocess

from shared_ranking import make_vision_ranker
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
    snapshots = []

    def snapshot(stage):
        mx.synchronize()
        mapped = subprocess.run(['vmmap','-summary',str(os.getpid())], capture_output=True, text=True)
        footprint = [line.strip() for line in mapped.stdout.splitlines() if 'Physical footprint' in line]
        snapshots.append({'stage':stage,'mlx_active_bytes':mx.get_active_memory(),
            'mlx_cache_bytes':mx.get_cache_memory(),'mlx_peak_bytes':mx.get_peak_memory(),
            'rss_bytes':int(subprocess.check_output(['ps','-o','rss=','-p',str(os.getpid())]))*1024,
            'vmmap_exit_code':mapped.returncode,'physical_footprint_lines':footprint})

    snapshot('loaded')
    for i in range(4):
        ranker.rank('这个职位拥有决定预算分配的','quanli',['权力','权利','全力'],use_cache=bool(i%2))
    snapshot('after_text')
    cases = json.loads(Path(__file__).with_name('heldout-cases.json').read_text())['cases']
    for case in cases[:3]:
        read_options(model,processor,[{'role':'user','content':[{'type':'image'}]},
            {'role':'user','content':'蓝色输入框上方的当前对话或正文主要使用哪种语言？\nA: 中文\nB: 英文'}],
            ['chinese','english'],image=scenes(case,False))
        ranker.rank('作为消费者，我们依法享有的','quanli',['权利','权力'],use_cache=False)
    snapshot('after_three_images_and_text')
    args.output.write_text(json.dumps({'model_instance_id':id(model),'snapshots':snapshots,
        'process_peak_rss_bytes_macos':resource.getrusage(resource.RUSAGE_SELF).ru_maxrss},indent=2)+'\n')
    print(json.dumps(snapshots,indent=2))


if __name__=='__main__':
    main()
