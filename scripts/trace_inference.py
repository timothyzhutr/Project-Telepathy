"""Refresh the dynamic-import allowlist by exercising the active inference path."""
import json,sys
from pathlib import Path
root=Path(__file__).resolve().parents[1]
sys.path[:0]=[str(root/'worker'),str(root/'vendor/kev')]
from kev_ranker import KevRanker
ranker=KevRanker(Path(sys.argv[1]))
ranker.rank('这份方案还需要大家一起讨论','yijian',['意见','一件','已建','宜建','亿间','一键','异见','衣间','一肩','义剑','一减','医监'])
ranker.rank('这份方案还需要大家一起讨论','yijian',['意见','一件','已建','宜建','亿间','一键','异见','衣间','一肩','义剑','一减','医监'],strategy='continuation')
ranker.route('I think ', 'he', ['和', '喝', '何'])
prefixes=('torch','transformers','mlx','mlx_lm','huggingface_hub','tokenizers','safetensors','numpy','pydantic')
modules=sorted(name for name,module in sys.modules.items() if module is not None and name.split('.')[0] in prefixes)
(root/'packaging/inference-imports.json').write_text(json.dumps(modules,indent=2)+'\n')
print('Recorded',len(modules),'runtime modules')
