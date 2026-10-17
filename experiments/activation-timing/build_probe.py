"""Compile the real controller with temporary timestamp hooks; source untouched."""
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'native'
BUILD = ROOT / '.runtime/activation-timing'


def replace_once(text, before, after):
    if text.count(before) != 1:
        raise ValueError('Probe anchor no longer matches the controller')
    return text.replace(before, after, 1)


def main():
    BUILD.mkdir(parents=True, exist_ok=True)
    controller = (SOURCE/'vendor/squirrel/sources/SquirrelInputController.swift').read_text()
    for before, after in [
        ('  private static let keyRollOver = 50', '  private let timingProbe = ActivationTimingProbe()\n  private static let keyRollOver = 50'),
        ('    guard let event = event else { return false }', '    guard let event = event else { return false }\n    timingProbe.key(event, client: sender)'),
        ('  override func activateServer(_ sender: Any!) {', '  override func activateServer(_ sender: Any!) {\n    timingProbe.activate(sender)'),
        ('  override func deactivateServer(_ sender: Any!) {', '  override func deactivateServer(_ sender: Any!) {\n    timingProbe.deactivate(sender)'),
        ('private var rankingEnabled: Bool { TelepathyPreferences.shared.enabled(.kev) }', 'private var rankingEnabled: Bool { false }'),
    ]:
        controller = replace_once(controller, before, after)
    (BUILD/'SquirrelInputController.swift').write_text(controller)
    main_source = (SOURCE/'vendor/squirrel/sources/Main.swift').read_text()
    main_source = replace_once(main_source, '    TelepathyWorkerController.shared.start()', '    // Timing probe: no model/helper process is started.')
    (BUILD/'Main.swift').write_text(main_source)
    def url(path):
        return 'URL(fileURLWithPath: '+__import__('json').dumps(str(path))+')'
    (BUILD/'Paths.swift').write_text('import Foundation\nenum ActivationTimingPaths {\n'
        'static let enabled = '+url(BUILD/'enabled')+'\nstatic let log = '+url(BUILD/'events.jsonl')+'\n}\n')
    sdk = Path(subprocess.check_output(['xcrun','--show-sdk-path'],text=True).strip())
    dist = ROOT/'.build/rime/dist'
    sources = [p for p in sorted((SOURCE/'vendor/squirrel/sources').glob('*.swift')) if p.name not in ['Main.swift','SquirrelInputController.swift']]
    sources += sorted((SOURCE/'Sources').glob('*.swift'))
    sources += [BUILD/'Main.swift', BUILD/'SquirrelInputController.swift', BUILD/'Paths.swift',
                Path(__file__).with_name('Probe.swift'),Path(__file__).with_name('TraceState.swift')]
    subprocess.run(list(map(str,['xcrun','swiftc','-target','arm64-apple-macosx26.2','-swift-version','5',
        '-enable-bare-slash-regex','-O','-module-name','TelepathyNative','-import-objc-header',
        SOURCE/'vendor/squirrel/sources/Squirrel-Bridging-Header.h','-I',dist/'include','-I',SOURCE/'vendor/include',
        '-I',SOURCE/'Sources','-I',sdk/'System/Library/Frameworks/Tk.framework/Versions/8.5/Headers',
        '-L',dist/'lib','-lrime','-framework','AppKit','-framework','InputMethodKit','-framework','Carbon',
        '-Xlinker','-rpath','-Xlinker','@executable_path/../Frameworks',*sources,ROOT/'.build/coverage.o','-o',BUILD/'Telepathy'])),check=True)
    print('Built the instrumented controller without modifying production sources')


if __name__=='__main__':
    main()
