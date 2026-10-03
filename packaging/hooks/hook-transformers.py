from PyInstaller.utils.hooks import copy_metadata
# Only the tokenizer/cache APIs are used; model architectures are handled by MLX.
datas=[]
for package in ('transformers','torch','numpy','tokenizers','huggingface_hub','safetensors','packaging','PyYAML','regex','tqdm','filelock','requests','httpx'):
    try: datas+=copy_metadata(package)
    except Exception: pass
module_collection_mode='pyz+py'
