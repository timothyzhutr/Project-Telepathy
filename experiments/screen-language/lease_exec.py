"""Run a research command while the production worker's singleton lock is held.

No preferences change. A previous live installed helper is restored after the
research child exits, including on errors. The parent never loads model weights.
"""
import argparse
import fcntl
import json
from pathlib import Path
import subprocess
import time
import urllib.error
import urllib.request


def health():
    try:
        with urllib.request.urlopen('http://127.0.0.1:18765/api/health', timeout=1) as response:
            body = json.load(response)
            if body.get('app') == 'Telepathy':
                return body
    except (OSError, ValueError):
        return None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--record', type=Path, required=True)
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ['--'] else args.command
    if not command:
        raise SystemExit('A research command is required')
    before = health()
    if before:
        request = urllib.request.Request('http://127.0.0.1:18765/api/shutdown', data=b'{}',
                                         headers={'Content-Type': 'application/json'})
        with urllib.request.urlopen(request, timeout=3) as response:
            response.read()
    lock_path = Path.home() / 'Library/Application Support/Telepathy/.worker.lock'
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    report = {'before': before, 'singleton_lock': 'production .worker.lock',
              'preferences_changed': False, 'command': command}
    args.record.parent.mkdir(parents=True, exist_ok=True)
    child = None
    with lock_path.open('a+') as lock:
        deadline = time.monotonic() + 30
        while True:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if time.monotonic() > deadline:
                    raise RuntimeError('Cannot acquire the installed worker lock')
                time.sleep(.1)
        try:
            assert health() is None, 'A production model is still serving'
            child = subprocess.Popen(command)
            report['research_pid'] = child.pid
            report['exit_code'] = child.wait()
        finally:
            if child is not None and child.poll() is None:
                child.terminate()
                try:
                    child.wait(timeout=15)
                except subprocess.TimeoutExpired:
                    child.kill()
                    child.wait()
            report['research_exited_before_unlock'] = child is None or child.poll() is not None
            fcntl.flock(lock, fcntl.LOCK_UN)
    if before:
        enabled = subprocess.run(['defaults', 'read', 'local.telepathy.inputmethod.Telepathy', 'KevEnabled'],
                                 capture_output=True, text=True)
        if enabled.returncode != 0 or enabled.stdout.strip() != '0':
            if health() is None:
                executable = Path.home() / 'Library/Input Methods/Telepathy.app/Contents/Helpers/TelepathyWorker.app/Contents/MacOS/TelepathyWorker'
                with args.record.with_suffix('.restore.log').open('w') as log:
                    subprocess.Popen([str(executable), '--serve', '--wait-lock'], stdin=subprocess.DEVNULL,
                                     stdout=log, stderr=log, start_new_session=True)
            deadline = time.monotonic() + 60
            while time.monotonic() < deadline:
                current = health()
                if current and current.get('status') == 'ready':
                    break
                time.sleep(.25)
            report['restored'] = health()
    args.record.write_text(json.dumps(report, indent=2) + '\n')
    raise SystemExit(report.get('exit_code', 1))


if __name__ == '__main__':
    main()
