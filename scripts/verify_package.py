"""Audit the release itself, including dependency closure and executable linkage."""
import argparse,hashlib,json,plistlib,re,subprocess
from pathlib import Path

def verify(app):
    contents=Path(app).resolve()/'Contents'
    info=plistlib.loads((contents/'Info.plist').read_bytes())
    assert info['CFBundleIdentifier']=='local.telepathy.inputmethod.Telepathy'
    assert info['LSMinimumSystemVersion']=='26.2'
    assert 'TelepathyProjectRoot' not in info
    assert info['CFBundleIconFile']=='Telepathy'
    resources=contents/'Resources'
    assert (resources/'Telepathy.icns').is_file() and (resources/'Telepathy.pdf').is_file()
    assert not any((resources/name).exists() for name in ('Rime.icns','rime.pdf'))
    for mode in info['ComponentInputModeDict']['tsInputModeListKey'].values():
        for key in ('tsInputModeMenuIconFileKey','tsInputModeAlternateMenuIconFileKey','tsInputModePaletteIconFileKey'):
            assert mode[key]=='Telepathy.pdf' and (resources/mode[key]).is_file()
    inventory=json.loads((contents/'Resources/data-inventory.json').read_text())
    actual={str(p.relative_to(contents)) for folder in ('Resources/Profile','SharedSupport') for p in (contents/folder).rglob('*') if p.is_file()}
    assert actual==set(inventory),'Runtime files outside the audited inventory: '+str(actual-set(inventory))
    for name,expected in inventory.items():
        p=contents/name
        with p.open('rb') as stream:digest=hashlib.file_digest(stream,'sha256').hexdigest()
        assert p.stat().st_size==expected['bytes'] and digest==expected['sha256'],name
    files=[p for p in contents.rglob('*') if p.is_file()]
    assert not any(p.suffix in ('.pt','.safetensors') or p.name in ('user.yaml','Sparkle.framework','librime-predict.dylib') for p in files)
    assert not (contents/'Frameworks/Sparkle.framework').exists()
    subprocess.run(['codesign','--verify','--deep','--strict',str(contents.parent)],check=True)
    subprocess.run([str(contents/'MacOS/Telepathy'),'--verify-runtime'],check=True)
    binaries=[]
    for p in files:
        if p.is_symlink():continue
        with p.open('rb') as stream: magic=stream.read(4)
        if magic not in (b'\xcf\xfa\xed\xfe',b'\xfe\xed\xfa\xcf',b'\xca\xfe\xba\xbe'):continue
        binaries.append(p)
        architecture=subprocess.check_output(['lipo','-archs',str(p)],text=True).strip()
        assert architecture=='arm64',(str(p),architecture)
        linked=subprocess.check_output(['otool','-L',str(p)],text=True).splitlines()[1:]
        for line in linked:
            dependency=line.strip().split(' (',1)[0]
            assert dependency.startswith(('@','/usr/lib/','/System/Library/')),(str(p),dependency)
        load_commands=subprocess.check_output(['otool','-l',str(p)],text=True)
        for minimum in re.findall(r'\bminos ([\d.]+)',load_commands):
            assert tuple(map(int,minimum.split('.'))) <= (26,2),(str(p),minimum)
    assert (contents/'Resources/licenses/python-dependencies.json').is_file()
    assert not any('__pycache__' in p.parts or p.suffix == '.pyc' for p in (contents/'Resources/licenses').rglob('*'))
    assert (contents/'Helpers/TelepathyWorker.app/Contents/MacOS/TelepathyWorker').is_file()
    print(json.dumps(dict(runtime_files=len(inventory),mach_o_binaries=len(binaries),weights_bundled=False,architecture='arm64',minimum_macos='26.2')))
if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('app',type=Path);args=parser.parse_args();verify(args.app)
