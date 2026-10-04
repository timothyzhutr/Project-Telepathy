import sys,unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'worker'))
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'vendor/kev'))
import mlx.core as mx
import mlx.nn as nn
from model_precision import configure_backbone

class TinyBackbone(nn.Module):
    def __init__(self):
        super().__init__()
        self.projection=nn.Linear(64,64,bias=False)
        self.embedding=nn.Embedding(64,64)
        self.norm=nn.LayerNorm(64)
        self.set_dtype(mx.bfloat16)

class PrecisionTests(unittest.TestCase):
    def test_default_compresses_weights_and_keeps_activation_precision(self):
        model=TinyBackbone();norm=model.norm.weight.tolist()
        original=model.projection.weight.tolist()
        info=configure_backbone(model)
        self.assertEqual(model.projection.weight.dtype,mx.uint32)
        self.assertEqual(model.embedding.weight.dtype,mx.uint32)
        self.assertEqual(model.projection.mode,'mxfp8')
        self.assertEqual(model.projection.group_size,32)
        self.assertEqual(model.norm.weight.tolist(),norm)
        self.assertEqual(model.projection(mx.ones((2,64),dtype=mx.bfloat16)).dtype,mx.bfloat16)
        restored=mx.dequantize(model.projection.weight,model.projection.scales,group_size=32,bits=8,mode='mxfp8')
        # Restored weights approximate the actual supplied values, not a new
        # randomly initialized layer. This also detects losing merged updates.
        self.assertLess(mx.max(mx.abs(restored-mx.array(original))).item(),.02)
        self.assertLess(info['backbone_weight_bytes'],info['unquantized_backbone_weight_bytes']*.6)
        self.assertEqual(info['quantization'],'mxfp8')
    def test_bf16_reference_path_leaves_weights_unchanged(self):
        model=TinyBackbone();original=model.projection.weight.tolist()
        info=configure_backbone(model,'bf16')
        self.assertEqual(model.projection.weight.dtype,mx.bfloat16)
        self.assertEqual(model.projection.weight.tolist(),original)
        self.assertEqual(info['backbone_weight_bytes'],info['unquantized_backbone_weight_bytes'])
        self.assertEqual(info['quantization'],'bf16')
    def test_invalid_mode_does_not_change_model(self):
        model=TinyBackbone()
        with self.assertRaises(ValueError):configure_backbone(model,'fp8-unsupported')
        self.assertEqual(model.projection.weight.dtype,mx.bfloat16)
    def test_head_uses_original_hidden_width_before_embedding_is_packed(self):
        from kev_ranker import KevRanker
        from kev.model import PointerHead
        model=nn.Module();model.language_model=nn.Module();model.language_model.model=nn.Module()
        model.language_model.model.embed_tokens=nn.Embedding(64,64)
        model.set_dtype(mx.bfloat16)
        checkpoint=SimpleNamespace(meta=SimpleNamespace(head_dim=256,temperature=2.35,
            head=PointerHead(64,dp=256).state_dict()))
        # Real MLX model/embedding conversion and official pointer-head loading;
        # replace checkpoint I/O and full-model inference only.
        with patch('kev_ranker.validate_models',return_value=dict(base=Path('/unused'),kev=Path('/unused'))), \
             patch('kev.checkpoint.Checkpoint',return_value=checkpoint), \
             patch('kev.model.load_tokenizer',return_value=SimpleNamespace(pad_token_id=0)), \
             patch('kev.mlx_model.load_base',return_value=model), \
             patch('kev.mlx_model.merge_lora'), \
             patch.object(KevRanker,'rank'),patch.object(KevRanker,'route'):
            try:ranker=KevRanker(Path('/unused'))
            except RuntimeError as error:self.fail('Could not load the full-width pointer checkpoint: '+str(error))
        self.assertEqual(tuple(ranker.engine.head.q.weight.shape),(256,64))
        self.assertEqual(ranker.engine.head.q.weight.dtype.__str__(),'torch.float32')
        self.assertEqual(model.language_model.model.embed_tokens.weight.dtype,mx.uint32)
        self.assertEqual(ranker.model_info['quantization'],'mxfp8')

if __name__=='__main__':unittest.main()
