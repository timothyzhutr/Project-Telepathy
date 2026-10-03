# Inference dependency closure: do not collect every optional Torch submodule.
from PyInstaller.utils.hooks import collect_dynamic_libs,copy_metadata,get_package_paths
binaries=collect_dynamic_libs('torch')
datas=copy_metadata('torch')
module_collection_mode='pyz+py' # TorchScript inspects Python source at import time.

from pathlib import Path
path=Path(get_package_paths('torch')[1])/'bin/torch_shm_manager'
binaries.append((str(path),'torch/bin'))
