"""Portable, pinned model store. Model bytes are never bundled in the app."""
import hashlib,json,os,sys
from pathlib import Path

def data_dir():
    return Path(os.environ.get('TELEPATHY_DATA_DIR',str(Path.home()/'Library/Application Support/Telepathy'))).expanduser()

def manifest_path():
    root=Path(getattr(sys,'_MEIPASS',Path(__file__).resolve().parents[1]))
    return root/'assets/models.lock.json'

def manifest(): return json.loads(manifest_path().read_text())

def validate_models(root, lock):
    paths={role:Path(root)/role for role in ('kev','base')}
    for role,path in paths.items():
        for f in lock[role]['files']:
            p=path/f['name']
            if not p.is_file(): raise FileNotFoundError('Model files are missing; run --download-model.')
            if p.stat().st_size != f['bytes']: raise ValueError('Model size mismatch: '+role+'/'+f['name'])
            with p.open('rb') as stream: digest=hashlib.file_digest(stream,'sha256').hexdigest()
            if digest != f['sha256']: raise ValueError('Model checksum mismatch: '+role+'/'+f['name'])
    return paths

def download_models(root):
    # Downloads happen only through this explicit command. Never use stored credentials.
    os.environ['HF_HUB_DISABLE_IMPLICIT_TOKEN']='1'
    from huggingface_hub import hf_hub_download
    lock=manifest()
    for role in ('kev','base'):
        info=lock[role]
        for f in info['files']:
            print('Downloading '+info['repo']+'/'+f['name'],flush=True)
            hf_hub_download(repo_id=info['repo'],filename=f['name'],revision=info['revision'],local_dir=Path(root)/role,token=False)
    validate_models(root,lock)
    print('Kev and Qwen model files verified. Inference runs offline.',flush=True)
