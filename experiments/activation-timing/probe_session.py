"""Install only the diagnostic executable; restore bytes/signature on exit/timeout."""
import hashlib
import json
from pathlib import Path
import shutil
import signal
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]
RUNTIME = ROOT/'.runtime/activation-timing'
APP = Path.home()/'Library/Input Methods/Telepathy.app'
TARGET = APP/'Contents/MacOS/Telepathy'
SIGNATURE = APP/'Contents/_CodeSignature'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    backup = RUNTIME/'original'
    if backup.exists():
        raise RuntimeError('A probe backup already exists; inspect/restore it before running again')
    subprocess.run(['codesign','--verify','--deep','--strict',str(APP)],check=True)
    # Refuse before entering cleanup: a pre-existing app must never be stopped
    # merely because this experiment could not begin.
    if subprocess.run(['pgrep','-x','Telepathy'],capture_output=True).returncode==0:
        raise RuntimeError('Telepathy is already running; preserve its state first')
    source = subprocess.check_output([str(RUNTIME/'input-source')],text=True).strip()
    backup.mkdir()
    shutil.copy2(TARGET,backup/'Telepathy')
    shutil.copytree(SIGNATURE,backup/'_CodeSignature')
    original = digest(TARGET)
    state = {'original_executable_sha256':original,'original_source':source,'restored':False}
    def save():
        (RUNTIME/'installation.json').write_text(json.dumps(state,indent=2)+'\n')
    save()
    stopping = False
    def stop(*_):
        nonlocal stopping
        stopping = True
    signal.signal(signal.SIGTERM,stop)
    signal.signal(signal.SIGINT,stop)
    try:
        shutil.copy2(RUNTIME/'Telepathy',TARGET)
        subprocess.run(['codesign','--force','--sign','-',str(APP)],check=True)
        subprocess.run(['codesign','--verify','--deep','--strict',str(APP)],check=True)
        (RUNTIME/'events.jsonl').touch(mode=0o600)
        (RUNTIME/'enabled').touch()
        state.update(installed=True,probe_executable_sha256=digest(TARGET))
        save()
        print('Diagnostic executable installed; automatic restoration deadline is 20 minutes.',flush=True)
        deadline = time.monotonic()+1200
        while not stopping and not (RUNTIME/'stop').exists() and time.monotonic()<deadline:
            time.sleep(.25)
    finally:
        (RUNTIME/'enabled').unlink(missing_ok=True)
        subprocess.run([str(RUNTIME/'input-source'),source],capture_output=True)
        subprocess.run([str(TARGET),'--quit'],capture_output=True,timeout=8)
        deadline = time.monotonic()+8
        while subprocess.run(['pgrep','-x','Telepathy'],capture_output=True).returncode==0 and time.monotonic()<deadline:
            time.sleep(.1)
        if subprocess.run(['pgrep','-x','Telepathy'],capture_output=True).returncode==0:
            subprocess.run(['pkill','-x','Telepathy'],check=True)
        shutil.copy2(backup/'Telepathy',TARGET)
        shutil.rmtree(SIGNATURE)
        shutil.copytree(backup/'_CodeSignature',SIGNATURE)
        subprocess.run(['codesign','--verify','--deep','--strict',str(APP)],check=True)
        state['restored'] = digest(TARGET)==original
        save()
        print('Original packaged executable and signature restored:',state['restored'],flush=True)


if __name__=='__main__':
    main()
