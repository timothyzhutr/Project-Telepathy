"""Fetch checksum-pinned build inputs, compile, and copy only the active profile."""
import argparse,hashlib,json,os,re,shutil,subprocess,tarfile,urllib.request,zipfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];BUILD=ROOT/'.build';CACHE=BUILD/'assets'
ASSETS=[
('engine.tar.bz2','rime','https://github.com/rime/librime/releases/download/1.17.0/rime-33e7814-macOS-universal.tar.bz2','11d8dc663c6ec06d5ccb6111ba664a9e7b631b703ac6acd07cffbac664021850'),
('Squirrel.pkg','rime','https://github.com/rime/squirrel/releases/download/1.1.2/Squirrel-1.1.2.pkg','614746013212937623d5bbab9901e9c43d1ec937aa32307d6b6092a05e308287'),
('rime-wanxiang-base.zip','wanxiang','https://github.com/amzxyz/rime-wanxiang/releases/download/v18.0.15/rime-wanxiang-base.zip','9f6cfaf4d9861846d1c0619713be9d1766c3588d6c5c0075b4c04f05c074f4b1'),
('wanxiang-lts-zh-hans.gram','wanxiang','https://github.com/amzxyz/RIME-LMDG/releases/download/LTS/wanxiang-lts-zh-hans.gram','873cbbb359fcf4df8b200183683ddc8be7b321eac4c864f8d2c7fc3136d4279f')]
def run(*args):subprocess.run(list(map(str,args)),check=True)
def sha(path):
    with path.open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
def fetch(existing=None):
    CACHE.mkdir(parents=True,exist_ok=True)
    for name,folder,url,digest in ASSETS:
        path=CACHE/name
        if not path.exists():
            local=existing/folder/name if existing else None
            if local and local.is_file():shutil.copyfile(local,path)
            else:
                print('Fetching '+name,flush=True);urllib.request.urlretrieve(url,path)
        if sha(path)!=digest:raise ValueError('Checksum mismatch: '+name)
    engine=BUILD/'rime';engine.mkdir(exist_ok=True)
    if not (engine/'dist/include/rime_api.h').exists():
        with tarfile.open(CACHE/'engine.tar.bz2') as a:a.extractall(engine,filter='data')
    stock=BUILD/'squirrel-package'
    if not stock.exists():run('pkgutil','--expand-full',CACHE/'Squirrel.pkg',stock)
    shared=BUILD/'wanxiang-source'
    if not shared.exists():
        shared.mkdir()
        with zipfile.ZipFile(CACHE/'rime-wanxiang-base.zip') as a:
            if any(not (shared/n).resolve().is_relative_to(shared.resolve()) for n in a.namelist()):raise ValueError('Unsafe zip path')
            a.extractall(shared)
    shutil.copyfile(CACHE/'wanxiang-lts-zh-hans.gram',shared/'wanxiang-lts-zh-hans.gram')
    squirrel=stock/'Payload/Squirrel.app/Contents'
    shutil.copyfile(squirrel/'SharedSupport/squirrel.yaml',shared/'squirrel.yaml')
    return engine/'dist',shared,squirrel

def compile_profile(dist,shared):
    user=BUILD/'profile-source';user.mkdir(exist_ok=True)
    (user/'default.custom.yaml').write_text('patch:\n  schema_list:\n    - schema: wanxiang\n  switcher/save_options: []\n  menu/page_size: 12\n')
    original=(shared/'wanxiang.schema.yaml').read_text()
    patch={'translator/enable_user_dict':False,'translator/contextual_suggestions':True,'add_user_dict/enable_auto_phrase':False,'menu/page_size':12}
    for key in ('add_user_dict','user_dict_set','custom_phrase','abbrev_phrase','wanxiang_english','wanxiang_mixedcode'):patch[key+'/enable_user_dict']=False
    for section in ('processors','translators','filters'):
        match=re.search(r'^  '+section+r':\n((?:    .*\n)+)',original,re.M)
        components=[line.strip().split(' #',1)[0][2:].strip() for line in match[1].splitlines() if line.strip().startswith('- ')]
        patch['engine/'+section]=[c for c in components if not any(r in c for r in ('context_reorder','super_sequence','input_statistics'))]
    (user/'wanxiang.custom.yaml').write_text('patch:\n'+''.join('  '+json.dumps(k)+': '+json.dumps(v)+'\n' for k,v in patch.items()))
    (user/'squirrel.custom.yaml').write_text('''patch:
  show_notifications_when: never
  keyboard_layout: default
  status_icon/show: false
  style/color_scheme: native
  style/color_scheme_dark: native
  style/candidate_list_layout: linear
  style/text_orientation: horizontal
  style/inline_preedit: true
  style/inline_candidate: false
  app_options: {}
''')
    tool=BUILD/'rime-tool'
    run('xcrun','clang','-Wall','-Wextra','-I'+str(dist/'include'),ROOT/'scripts/rime_tool.c','-L'+str(dist/'lib'),'-lrime','-Wl,-rpath,'+str(dist/'lib'),'-o',tool)
    run(tool,'deploy',shared,user)
    return user

def prune(shared,user):
    target=BUILD/'package-data'
    if target.exists():shutil.rmtree(target)
    support=target/'SharedSupport';profile=target/'Resources/Profile';support.mkdir(parents=True);(profile/'build').mkdir(parents=True)
    schemas=['wanxiang','wanxiang_abbrev','wanxiang_english','wanxiang_mixedcode','wanxiang_phrase','wanxiang_reverse']
    # Only deployed configuration and dictionaries: no duplicate raw dictionaries or personal databases.
    for file in (user/'build').iterdir():
        if file.suffix=='.bin' or file.name in [s+'.schema.yaml' for s in schemas]+['default.yaml','squirrel.yaml']:
            shutil.copyfile(file,profile/'build'/file.name)
    # Only the active system-color theme is used by the native panel.
    import yaml
    panel=profile/'build/squirrel.yaml';settings=yaml.safe_load(panel.read_text())
    settings['preset_color_schemes']={'native':settings['preset_color_schemes']['native']}
    panel.write_text(yaml.safe_dump(settings,allow_unicode=True,sort_keys=False))
    main=(profile/'build/wanxiang.schema.yaml').read_text()
    modules=set(re.findall(r'lua_\w+@\*wanxiang\.([\w]+)',main));modules.add('wanxiang')
    pending=list(modules)
    while pending:
        name=pending.pop();text=(shared/'lua/wanxiang'/f'{name}.lua').read_text()
        for dep in re.findall(r'require\([\"\x27]wanxiang[/\.]([\w]+)',text):
            if dep not in modules:modules.add(dep);pending.append(dep)
    for name in modules:
        dst=support/'lua/wanxiang'/f'{name}.lua';dst.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(shared/'lua/wanxiang'/f'{name}.lua',dst)
    combined=main+'\n'+''.join((shared/'lua/wanxiang'/f'{m}.lua').read_text() for m in modules)
    for file in (shared/'lua/data').iterdir():
        if file.name in combined:
            dst=support/'lua/data'/file.name;dst.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(file,dst)
    # A comment filter reads the small typo dictionary directly at runtime.
    for name in re.findall(r'dicts/[\w.-]+\.dict\.yaml',combined):
        if (shared/name).is_file():
            dst=support/name;dst.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(shared/name,dst)
    def opencc(name):
        src=shared/'opencc'/name;dst=support/'opencc'/name
        if dst.exists():return
        dst.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(src,dst)
        if src.suffix=='.json':
            for dep in re.findall(r'"file"\s*:\s*"([^"]+)"',src.read_text()):opencc(dep)
    for name in re.findall(r'opencc_config:\s*(\S+)',main):opencc(name)
    for name in ('wanxiang-lts-zh-hans.gram','version.txt'):
        if (shared/name).exists():shutil.copyfile(shared/name,support/name)
    # Lua utilities locate deployed dictionaries and version/config files via Rime.
    for name in ('default.yaml','squirrel.yaml'):shutil.copyfile(profile/'build'/name,support/name)
    inventory={str(p.relative_to(target)):dict(bytes=p.stat().st_size,sha256=sha(p)) for p in sorted(target.rglob('*')) if p.is_file()}
    (target/'inventory.json').write_text(json.dumps(inventory,indent=2)+'\n')
    (ROOT/'assets/upstream.lock.json').write_text(json.dumps([dict(file=n,url=u,sha256=h) for n,_,u,h in ASSETS],indent=2)+'\n')
    print('Runtime files:',len(inventory),'bytes:',sum(v['bytes'] for v in inventory.values()),'Lua modules:',len(modules))
    return target
if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--asset-cache',type=Path);args=parser.parse_args()
    dist,shared,stock=fetch(args.asset_cache);user=compile_profile(dist,shared);prune(shared,user)
