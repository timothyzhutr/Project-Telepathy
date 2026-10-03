"""Preserve upstream notices and the licenses of bundled Python distributions."""
import ast,base64,importlib.metadata as md,json,shutil,subprocess,sys,urllib.request
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'licenses'
UPSTREAM=[
('librime-BSD-3-Clause.txt','rime/librime','1.17.0','LICENSE'),
('librime-lua-BSD-3-Clause.txt','hchunhui/librime-lua','ec52e48','LICENSE'),
('librime-octagram-BSD-3-Clause.txt','lotem/librime-octagram','dfcc151','LICENSE'),
('Wanxiang-CC-BY-4.0.txt','amzxyz/rime-wanxiang','v18.0.15','LICENSE'),
('RIME-LMDG-CC-BY-4.0.txt','amzxyz/RIME-LMDG','wanxiang','LICENSE'),
('Qwen-Apache-2.0.txt','QwenLM/Qwen3.5','main','LICENSE')]
def github(repo,ref,path):
    response=json.loads(subprocess.check_output(['gh','api',f'repos/{repo}/contents/{path}?ref={ref}'],timeout=30))
    if response.get('content'):return base64.b64decode(response['content'])
    with urllib.request.urlopen(response['download_url']) as r:return r.read()
def main():
    OUT.mkdir(exist_ok=True)
    for name,repo,ref,path in UPSTREAM:
        if not (OUT/name).exists():(OUT/name).write_bytes(github(repo,ref,path))
    shutil.copyfile(ROOT/'native/vendor/squirrel/LICENSE.txt',OUT/'Squirrel-GPL-3.0.txt')
    # Rime statically links these third-party dependencies. Refs match librime's submodule pins.
    deps=[] if all((OUT/(name+'-LICENSE.txt')).exists() for name in ('glog','leveldb','marisa-trie','opencc','yaml-cpp')) else json.loads(subprocess.check_output(['gh','api','repos/rime/librime/contents/deps?ref=1.17.0'],timeout=30))
    repos={'glog':('google/glog','COPYING'),'leveldb':('google/leveldb','LICENSE'),'marisa-trie':('s-yata/marisa-trie','COPYING.md'),'opencc':('BYVoid/OpenCC','LICENSE'),'yaml-cpp':('jbeder/yaml-cpp','LICENSE')}
    for dep in deps:
        if dep['name'] in repos:
            repo,path=repos[dep['name']];target=OUT/(dep['name']+'-LICENSE.txt')
            if not target.exists():target.write_bytes(github(repo,dep['sha'],path))
    extra=[('Lua-MIT.txt','https://www.lua.org/license.html'),('Boost-Software-License-1.0.txt','https://raw.githubusercontent.com/boostorg/boost/boost-1.89.0/LICENSE_1_0.txt'),('utf8cpp-LICENSE.txt','https://raw.githubusercontent.com/nemtrif/utfcpp/v4.0.6/LICENSE')]
    for name,url in extra:
        if not (OUT/name).exists():
            with urllib.request.urlopen(url,timeout=30) as r:(OUT/name).write_bytes(r.read())
    # Darts clone is embedded in Octagram/OpenCC; preserve the release header's notice.
    if not (OUT/'darts-clone-LICENSE.txt').exists():
        with urllib.request.urlopen('https://raw.githubusercontent.com/s-yata/darts-clone/master/COPYING.md',timeout=30) as r:(OUT/'darts-clone-LICENSE.txt').write_bytes(r.read())
    shutil.copyfile(Path(sys.base_prefix)/'lib/python3.12/LICENSE.txt',OUT/'Python-PSF.txt')
    # Frozen TOCs identify distributions actually collected, including statically imported dependencies.
    toc=ast.literal_eval((ROOT/'.build/pyinstaller/worker/PYZ-00.toc').read_text())
    names={row[0].split('.')[0] for row in toc[1]}
    packages=md.packages_distributions();distributions={dist for name in names for dist in packages.get(name,[])}
    info=[]
    for name in sorted(distributions):
        if name.lower() in ('pyinstaller','peft','accelerate'):continue
        dist=md.distribution(name);dest=OUT/'python'/dist.metadata['Name'];files=[]
        for f in dist.files or []:
            if (any(part.lower().startswith(('license','copying','notice')) for part in Path(str(f)).parts)
                and Path(str(f)).suffix.lower() not in ('.py','.pyc','.so','.dylib','.h','.c','.cpp')):
                src=dist.locate_file(f)
                if src.is_file():
                    # Keep nested third-party notices without any source checkout paths.
                    relative=Path(str(f));parts=relative.parts
                    index=next(i for i,p in enumerate(parts) if p.lower().startswith(('license','copying','notice')))
                    target=dest.joinpath(*parts[index:]);target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(src,target);files.append(str(target.relative_to(OUT)))
        if not files and name in ('sentencepiece','tokenizers'):
            target=dest/'LICENSE';target.parent.mkdir(parents=True,exist_ok=True)
            repo,ref=('google/sentencepiece','v0.2.2') if name=='sentencepiece' else ('huggingface/tokenizers','v0.23.2')
            target.write_bytes(github(repo,ref,'LICENSE'));files.append(str(target.relative_to(OUT)))
        if not files:raise RuntimeError('No license files found: '+name)
        info.append(dict(name=dist.metadata['Name'],version=dist.version,license=dist.metadata.get('License-Expression') or dist.metadata.get('License'),notices=files))
    (OUT/'python-dependencies.json').write_text(json.dumps(info,ensure_ascii=False,indent=2)+'\n')
    # Bootloader redistribution exception is part of PyInstaller's license.
    pyinstaller=Path(__import__('PyInstaller').__file__).parent
    for file in ('COPYING.txt',):shutil.copyfile(pyinstaller.parent/'pyinstaller-6.22.3.dist-info/licenses'/file,OUT/('PyInstaller-'+file))
    print('Preserved licenses for',len(info),'Python runtime distributions and native/data dependencies.')
if __name__=='__main__':main()
