import os,subprocess,tempfile,unittest,shutil
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
class InstallerTests(unittest.TestCase):
    def test_failed_profile_backup_restores_app_without_deleting_profile(self):
        with tempfile.TemporaryDirectory(prefix='telepathy install ') as name:
            tmp=Path(name);home=tmp/'user';release=tmp/'release';release.mkdir();tools=tmp/'tools';tools.mkdir()
            source=release/'Telepathy.app/Contents/MacOS/Telepathy';source.parent.mkdir(parents=True);source.write_text('#!/bin/bash\nexit 0\n');source.chmod(0o755)
            old=home/'Library/Input Methods/Telepathy.app/Contents/MacOS/Telepathy';old.parent.mkdir(parents=True);old.write_text('#!/bin/bash\nexit 0\n');old.chmod(0o755)
            (old.parent/'old-marker').write_text('old app')
            profile=home/'Library/Telepathy/Rime';profile.mkdir(parents=True);(profile/'personal-marker').write_text('preserve this')
            shutil.copyfile(ROOT/'packaging/Install Telepathy.command',release/'Install Telepathy.command')
            wrapper=tools/'mv';wrapper.write_text('#!/bin/bash\nif [[ "$1" == "$TELEPATHY_INSTALL_ROOT/Library/Telepathy/Rime" ]]; then exit 1; fi\nexec /bin/mv "$@"\n');wrapper.chmod(0o755)
            env=dict(os.environ,TELEPATHY_INSTALL_ROOT=str(home),PATH=str(tools)+':'+os.environ['PATH'])
            result=subprocess.run(['/bin/bash',str(release/'Install Telepathy.command')],env=env,capture_output=True,text=True)
            self.assertNotEqual(result.returncode,0);self.assertIn('restoring',result.stdout)
            self.assertEqual((old.parent/'old-marker').read_text(),'old app')
            self.assertEqual((profile/'personal-marker').read_text(),'preserve this')
