"""Assemble an Apple Silicon app from the active dependency closure."""
import json,plistlib,shutil,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];BUILD=ROOT/'.build';APP=ROOT/'dist/Telepathy.app';VERSION='0.1.8'
def run(*args):subprocess.run(list(map(str,args)),check=True,cwd=ROOT)
def main():
    dist=BUILD/'rime/dist';source=ROOT/'native';stock=BUILD/'squirrel-package/Payload/Squirrel.app/Contents'
    sdk=subprocess.check_output(['xcrun','--show-sdk-path'],text=True).strip()
    run('xcrun','clang','-target','arm64-apple-macosx26.2','-c','-Wall','-Wextra','-I'+str(dist/'include'),source/'Sources/Coverage.c','-o',BUILD/'coverage.o')
    run('xcrun','swiftc','-target','arm64-apple-macosx26.2','-swift-version','5','-enable-bare-slash-regex','-O','-module-name','TelepathyNative',
        '-import-objc-header',source/'vendor/squirrel/sources/Squirrel-Bridging-Header.h','-I',dist/'include','-I',source/'vendor/include','-I',source/'Sources',
        '-I',Path(sdk)/'System/Library/Frameworks/Tk.framework/Versions/8.5/Headers','-L',dist/'lib','-lrime','-framework','AppKit','-framework','InputMethodKit',
        '-framework','Carbon','-Xlinker','-rpath','-Xlinker','@executable_path/../Frameworks',
        *sorted((source/'vendor/squirrel/sources').glob('*.swift')),*sorted((source/'Sources').glob('*.swift')),BUILD/'coverage.o','-o',BUILD/'Telepathy')
    if APP.exists():shutil.rmtree(APP)
    contents=APP/'Contents';(contents/'MacOS').mkdir(parents=True)
    shutil.copyfile(BUILD/'Telepathy',contents/'MacOS/Telepathy');(contents/'MacOS/Telepathy').chmod(0o755)
    frameworks=contents/'Frameworks';(frameworks/'rime-plugins').mkdir(parents=True)
    # Predict and Sparkle are unused. The active schema requires Lua and Octagram.
    for src,dst in [(dist/'lib/librime.1.17.0.dylib',frameworks/'librime.1.dylib')]+[(dist/f'lib/rime-plugins/librime-{p}.dylib',frameworks/f'rime-plugins/librime-{p}.dylib') for p in ('lua','octagram')]:
        run('lipo',src,'-thin','arm64','-output',dst)
        run('codesign','--force','--sign','-',dst)
    inventory=json.loads((BUILD/'package-data/inventory.json').read_text())
    for name,info in inventory.items():
        src=BUILD/'package-data'/name;dst=contents/name
        import hashlib
        with src.open('rb') as stream:digest=hashlib.file_digest(stream,'sha256').hexdigest()
        if src.stat().st_size!=info['bytes'] or digest!=info['sha256']:raise ValueError('Runtime inventory mismatch: '+name)
        dst.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(src,dst)
    shutil.copyfile(BUILD/'package-data/inventory.json',contents/'Resources/data-inventory.json')
    resources=contents/'Resources';resources.mkdir(exist_ok=True)
    run(__import__('sys').executable,ROOT/'scripts/build_branding.py')
    for name in ('Telepathy.icns','Telepathy.pdf'):shutil.copyfile(ROOT/'assets/branding'/name,resources/name)
    for locale in ('en','zh-Hans'):
        shutil.copytree(stock/f'Resources/{locale}.lproj',resources/f'{locale}.lproj')
        localized={'CFBundleName':'Telepathy','CFBundleDisplayName':'Telepathy','local.telepathy.inputmethod.Telepathy.Hans':'Telepathy'}
        (resources/f'{locale}.lproj/InfoPlist.strings').write_bytes(plistlib.dumps(localized))
    shutil.copytree(ROOT/'licenses',resources/'licenses',ignore=shutil.ignore_patterns('__pycache__','*.pyc'));shutil.copyfile(ROOT/'LICENSE',resources/'LICENSE');shutil.copyfile(ROOT/'CREDITS.md',resources/'CREDITS.md')
    shutil.copytree(BUILD/'worker-dist/TelepathyWorker.app',contents/'Helpers/TelepathyWorker.app',symlinks=True)
    plist=plistlib.loads((stock/'Info.plist').read_bytes())
    def rename(v):
        if isinstance(v,dict):return {rename(k):rename(x) for k,x in v.items()}
        if isinstance(v,list):return [rename(x) for x in v]
        if isinstance(v,str):return v.replace('im.rime.inputmethod.Squirrel','local.telepathy.inputmethod.Telepathy').replace('rime.pdf','Telepathy.pdf')
        return v
    plist=rename(plist)
    for key in list(plist):
        if key.startswith(('SU','DT')) or key in ('BuildMachineOSBuild','CFBundleIconName'):plist.pop(key)
    plist.update(CFBundleExecutable='Telepathy',CFBundleName='Telepathy',CFBundleDisplayName='Telepathy',CFBundleIdentifier='local.telepathy.inputmethod.Telepathy',CFBundleVersion=VERSION,
        CFBundleShortVersionString=VERSION,CFBundleIconFile='Telepathy',LSMinimumSystemVersion='26.2',InputMethodConnectionName='Telepathy_Connection',
        InputMethodServerControllerClass='TelepathyNative.SquirrelInputController',InputMethodServerDelegateClass='TelepathyNative.SquirrelInputController')
    modes=plist['ComponentInputModeDict'];modes['tsInputModeListKey'].pop('local.telepathy.inputmethod.Telepathy.Hant',None)
    modes['tsVisibleInputModeOrderedArrayKey']=['local.telepathy.inputmethod.Telepathy.Hans']
    (contents/'Info.plist').write_bytes(plistlib.dumps(plist))
    # Native libraries and the PyInstaller helper are already signed inside-out.
    run('codesign','--force','--sign','-',APP);run('codesign','--verify','--deep','--strict',APP)
    run(contents/'MacOS/Telepathy','--verify-runtime')
    for name in ('Install Telepathy.command','Download Kev Model.command'):shutil.copy2(ROOT/'packaging'/name,ROOT/'dist'/name)
    for name in ('README.md','README.zh-CN.md','CREDITS.md','LICENSE'):shutil.copy2(ROOT/name,ROOT/'dist'/name)
    # The release's README uses the same relative images as GitHub.
    for name in ('assets/branding/Telepathy-128.png','docs/images/telepathy-native-demo.png'):
        target=ROOT/'dist'/name;target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(ROOT/name,target)
    print(APP)
if __name__=='__main__':main()
