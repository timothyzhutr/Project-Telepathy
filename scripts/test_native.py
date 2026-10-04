"""Run native regressions after preparing the pinned build assets."""
import plistlib
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / '.build'
SOURCE = ROOT / 'native'

def run(*args):
    subprocess.run(list(map(str, args)), check=True)

def main():
    BUILD.mkdir(exist_ok=True)
    ranking = BUILD / 'ranking-tests'
    run('xcrun', 'swiftc', SOURCE / 'Sources/RankingState.swift',
        SOURCE / 'Tests/RankingStateTests.swift', '-o', ranking)
    run(ranking)
    intent = BUILD / 'intent-tests'
    run('xcrun', 'swiftc', SOURCE / 'Sources/InputIntentState.swift',
        SOURCE / 'Tests/InputIntentStateTests.swift', '-o', intent)
    run(intent)
    punctuation = BUILD / 'punctuation-tests'
    run('xcrun', 'swiftc', SOURCE / 'Sources/PunctuationPolicy.swift',
        SOURCE / 'Tests/PunctuationPolicyTests.swift', '-o', punctuation)
    run(punctuation)

    contents = BUILD / 'credits-tests.app/Contents'
    (contents / 'MacOS').mkdir(parents=True, exist_ok=True)
    (contents / 'Resources').mkdir(exist_ok=True)
    (contents / 'Info.plist').write_bytes(plistlib.dumps({
        'CFBundleIdentifier': 'local.telepathy.tests.credits',
        'CFBundleExecutable': 'CreditsOpenerTests',
        'CFBundlePackageType': 'APPL',
    }))
    shutil.copyfile(ROOT / 'CREDITS.md', contents / 'Resources/CREDITS.md')
    shutil.copyfile(ROOT / 'LICENSE', contents / 'Resources/LICENSE')
    shutil.copytree(ROOT / 'licenses', contents / 'Resources/licenses', dirs_exist_ok=True)
    dist = BUILD / 'rime/dist'
    sdk = subprocess.check_output(['xcrun', '--show-sdk-path'], text=True).strip()
    coverage = BUILD / 'credits-coverage.o'
    run('xcrun', 'clang', '-c', '-Wall', '-Wextra', '-I' + str(dist / 'include'),
        SOURCE / 'Sources/Coverage.c', '-o', coverage)
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
        SOURCE / 'Tests/CreditsOpenerTests.swift', SOURCE / 'Tests/ControllerEventTests.swift', coverage,
        '-o', contents / 'MacOS/CreditsOpenerTests')
    fixture = BUILD / 'foreground-tests.app/Contents'
    (fixture / 'MacOS').mkdir(parents=True, exist_ok=True)
    (fixture / 'Info.plist').write_bytes(plistlib.dumps({
        'CFBundleIdentifier': 'local.telepathy.tests.foreground',
        'CFBundleExecutable': 'CreditsOpenerTests',
        'CFBundlePackageType': 'APPL',
    }))
    shutil.copyfile(contents / 'MacOS/CreditsOpenerTests', fixture / 'MacOS/CreditsOpenerTests')
    (fixture / 'MacOS/CreditsOpenerTests').chmod(0o755)
    run(contents / 'MacOS/CreditsOpenerTests')

if __name__ == '__main__':
    main()
