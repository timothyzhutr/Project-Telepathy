import json
from pathlib import Path
from PyInstaller.utils.hooks import collect_data_files,copy_metadata
root=Path(SPECPATH).parent
hidden=json.loads((root/'packaging/inference-imports.json').read_text())
# MLX loads the Metal shader library and package metadata dynamically.
datas=collect_data_files('mlx',include_py_files=False)+collect_data_files('mlx_lm',include_py_files=False)+collect_data_files('mlx_vlm',include_py_files=False)
for package in ('mlx','mlx-lm','mlx-metal','mlx-vlm','pillow','torchvision','pydantic','huggingface_hub','safetensors','tokenizers'):
    datas+=copy_metadata(package)
datas.append((str(root/'assets/models.lock.json'),'assets'))
a=Analysis([str(root/'worker/main.py')],pathex=[str(root/'worker'),str(root/'vendor/kev')],
    binaries=[],datas=datas,hiddenimports=hidden,hookspath=[str(root/'packaging/hooks')],
    excludes=['peft','accelerate','tensorflow','jax','triton','bitsandbytes','torchaudio','matplotlib','scipy','pandas','pytest','IPython','mlx_audio','miniaudio','cv2','datasets','fastapi','uvicorn','llguidance','kev'],noarchive=False)
# Optional-package availability probes can collect metadata even for excluded modules.
a.datas=[entry for entry in a.datas if not entry[0].startswith(('peft-','accelerate-'))]
# Keep one physical MLX library at its package location. dyld must resolve the
# colocated shader library there; a second root-level copy loses that lookup.
for library in ('libmlx.dylib','libjaccl.dylib'):
    nested='mlx/lib/'+library
    if any(entry[0]==nested for entry in a.binaries):
        a.binaries=[(library,nested,'SYMLINK') if entry[0]==library else entry for entry in a.binaries]
pyz=PYZ(a.pure)
exe=EXE(pyz,a.scripts,[],exclude_binaries=True,name='TelepathyWorker',debug=False,bootloader_ignore_signals=False,strip=False,upx=False,console=True,target_arch='arm64')
coll=COLLECT(exe,a.binaries,a.datas,strip=False,upx=False,name='TelepathyWorker')
app=BUNDLE(coll,name='TelepathyWorker.app',bundle_identifier='local.telepathy.worker',
    info_plist={'LSUIElement':True,'LSMinimumSystemVersion':'26.2','CFBundleShortVersionString':'0.2.0'})
