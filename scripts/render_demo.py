"""Render a public-safe README demo using the production AppKit candidate panel.

Run after build assets are prepared. The default run makes one local Kev
decision for synthetic text; --replay uses the checked-in synthetic snapshot.
No screen capture, clipboard access, or user document access is involved.
"""
import argparse
import plistlib
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / '.build'
SOURCE = ROOT / 'native'


def run(*args):
    subprocess.run(list(map(str, args)), check=True, cwd=ROOT)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--replay', action='store_true')
    args = parser.parse_args()
    image = ROOT / 'docs/images/telepathy-native-demo.png'
    snapshot = ROOT / 'docs/branding/native-demo.json'
    image.parent.mkdir(parents=True, exist_ok=True)
    snapshot.parent.mkdir(parents=True, exist_ok=True)
    dist = BUILD / 'rime/dist'
    sdk = subprocess.check_output(['xcrun', '--show-sdk-path'], text=True).strip()
    with tempfile.TemporaryDirectory(prefix='telepathy-native-demo-') as name:
        work = Path(name)
        contents = work / 'TelepathyDemo.app/Contents'
        (contents / 'MacOS').mkdir(parents=True)
        (contents / 'Info.plist').write_bytes(plistlib.dumps({
            'CFBundleIdentifier': 'local.telepathy.documentation.demo',
            'CFBundleExecutable': 'TelepathyDemo',
            'CFBundlePackageType': 'APPL',
        }))
        coverage = work / 'coverage.o'
        run('xcrun', 'clang', '-c', '-I' + str(dist / 'include'),
            SOURCE / 'Sources/Coverage.c', '-o', coverage)
        executable = contents / 'MacOS/TelepathyDemo'
        run('xcrun', 'swiftc', '-swift-version', '5', '-enable-bare-slash-regex',
            '-module-name', 'TelepathyNative', '-import-objc-header',
            SOURCE / 'vendor/squirrel/sources/Squirrel-Bridging-Header.h',
            '-I', dist / 'include', '-I', SOURCE / 'vendor/include', '-I', SOURCE / 'Sources',
            '-I', Path(sdk) / 'System/Library/Frameworks/Tk.framework/Versions/8.5/Headers',
            '-L', dist / 'lib', '-lrime', '-framework', 'AppKit',
            '-framework', 'InputMethodKit', '-framework', 'Carbon',
            '-Xlinker', '-rpath', '-Xlinker', (dist / 'lib').resolve(),
            *[p for p in sorted((SOURCE / 'vendor/squirrel/sources').glob('*.swift')) if p.name != 'Main.swift'],
            *sorted((SOURCE / 'Sources').glob('*.swift')),
            ROOT / 'scripts/demo_native.swift', coverage, '-o', executable)
        user = work / 'Rime'
        shutil.copytree(BUILD / 'package-data/Resources/Profile', user)
        arguments = [executable, BUILD / 'package-data/SharedSupport', user, image, snapshot]
        if args.replay:
            arguments.append('--replay')
        run(*arguments)
    print(image)


if __name__ == '__main__':
    main()
