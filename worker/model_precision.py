"""Precision policy for the already merged backbone."""
def configure_backbone(model,quantization='mxfp8'):
    if quantization not in ('mxfp8','bf16'):raise ValueError('Unsupported backbone quantization')
    import mlx.core as mx
    import mlx.nn as nn
    from mlx.utils import tree_flatten
    size=sum(value.nbytes for _,value in tree_flatten(model.parameters()))
    if quantization=='mxfp8':nn.quantize(model,group_size=32,bits=8,mode='mxfp8')
    mx.eval(model.parameters())
    # Conversion is a one-time startup operation. Release temporary BF16
    # buffers before any prefix cache or inference graph is constructed.
    mx.clear_cache()
    return dict(quantization=quantization,
                backbone_weight_bytes=sum(value.nbytes for _,value in tree_flatten(model.parameters())),
                unquantized_backbone_weight_bytes=size)
