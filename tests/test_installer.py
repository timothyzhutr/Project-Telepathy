import os,subprocess,tempfile,unittest,shutil
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
class InstallerTests(unittest.TestCase):
    def fixture(self, tmp, fail=False):
        home=tmp/'user';release=tmp/'release';release.mkdir()
        native='Telepathy.app/Contents/MacOS/Telepathy'
        for base in (release,home/'Library/Input Methods'):
            path=base/native;path.parent.mkdir(parents=True)
            path.write_text('#!/bin/bash\n'+('[[ "${1:-}" != "--verify-runtime" ]]\n' if fail and base==release else 'exit 0\n'))
            path.chmod(0o755)
        (release/'Telepathy.app/Contents/Resources/Profile').mkdir(parents=True)
        backups=home/'Library/Application Support/Telepathy/InstallBackups'
        for i in range(4):
            old=backups/f'2020010{i+1}-120000/Telepathy.app'
            old.mkdir(parents=True);(old/'marker').write_text(str(i))
        personal=backups/'personal';personal.mkdir();(personal/'marker').write_text('keep')
        incomplete=backups/'20200105-120000/new.app';incomplete.mkdir(parents=True)
        shutil.copyfile(ROOT/'packaging/Install Telepathy.command',release/'Install Telepathy.command')
        return home,release,backups

    def test_success_keeps_two_recent_backups_without_touching_unrelated_or_incomplete_folders(self):
        with tempfile.TemporaryDirectory(prefix='telepathy retention ') as name:
            home,release,backups=self.fixture(Path(name))
            result=subprocess.run(['/bin/bash',str(release/'Install Telepathy.command')],env=dict(os.environ,TELEPATHY_INSTALL_ROOT=str(home)),capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)
            retained=[p for p in backups.iterdir() if (p/'Telepathy.app').is_dir()]
            self.assertEqual(len(retained),2,'Successful installs must bound backup storage')
            self.assertTrue((backups/'20200104-120000/Telepathy.app/marker').exists())
            self.assertTrue((backups/'personal/marker').exists())
            self.assertTrue((backups/'20200105-120000/new.app').exists())

    def test_failed_install_preserves_every_previous_backup(self):
        with tempfile.TemporaryDirectory(prefix='telepathy retention failure ') as name:
            home,release,backups=self.fixture(Path(name),fail=True)
            result=subprocess.run(['/bin/bash',str(release/'Install Telepathy.command')],env=dict(os.environ,TELEPATHY_INSTALL_ROOT=str(home)),capture_output=True,text=True)
            self.assertNotEqual(result.returncode,0)
            for i in range(4):self.assertTrue((backups/f'2020010{i+1}-120000/Telepathy.app/marker').exists())
            self.assertTrue((home/'Library/Input Methods/Telepathy.app/Contents/MacOS/Telepathy').exists())

    def test_success_preserves_an_interrupted_install_after_staging_moved(self):
        with tempfile.TemporaryDirectory(prefix='telepathy interrupted install ') as name:
            home,release,backups=self.fixture(Path(name))
            interrupted=backups/'20190101-120000';(interrupted/'Telepathy.app').mkdir(parents=True)
            (interrupted/'.install-in-progress').write_text('')
            result=subprocess.run(['/bin/bash',str(release/'Install Telepathy.command')],env=dict(os.environ,TELEPATHY_INSTALL_ROOT=str(home)),capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)
            self.assertTrue((interrupted/'Telepathy.app').exists(),'A SIGKILL leaves no new.app but its recovery backup must survive')

    def test_upgrade_stops_only_the_previous_installed_helper(self):
        with tempfile.TemporaryDirectory(prefix='telepathy legacy upgrade ') as name:
            tmp=Path(name);home=tmp/'user';release=tmp/'release';release.mkdir()
            native='Telepathy.app/Contents/MacOS/Telepathy'
            for base in (release,home/'Library/Input Methods'):
                path=base/native;path.parent.mkdir(parents=True);path.write_text('#!/bin/bash\nexit 0\n');path.chmod(0o755)
            profile=release/'Telepathy.app/Contents/Resources/Profile';profile.mkdir(parents=True)
            (profile/'fixture.yaml').write_text('profile: test\n')
            relative='Telepathy.app/Contents/Helpers/TelepathyWorker.app/Contents/MacOS/TelepathyWorker'
            old=home/'Library/Input Methods'/relative;old.parent.mkdir(parents=True)
            source=tmp/'legacy.c';source.write_text('#include <unistd.h>\nint main(void) { for (;;) pause(); }\n')
            subprocess.run(['xcrun','clang',str(source),'-o',str(old)],check=True)
            unrelated=tmp/'other helper';shutil.copy2(old,unrelated)
            legacy=subprocess.Popen([str(old),'--serve']);other=subprocess.Popen([str(unrelated),'--serve'])
            try:
                self.assertIsNone(legacy.poll());self.assertIsNone(other.poll())
                shutil.copyfile(ROOT/'packaging/Install Telepathy.command',release/'Install Telepathy.command')
                result=subprocess.run(['/bin/bash',str(release/'Install Telepathy.command')],env=dict(os.environ,TELEPATHY_INSTALL_ROOT=str(home)),capture_output=True,text=True,timeout=20)
                self.assertEqual(result.returncode,0,result.stdout+result.stderr)
                self.assertIsNotNone(legacy.poll(),'An upgrade must stop the old helper even when it has no shutdown endpoint')
                self.assertIsNone(other.poll(),'A differently located helper must not be stopped')
                self.assertTrue((home/'Library/Telepathy/Rime/fixture.yaml').exists())
            finally:
                for process in (legacy,other):
                    if process.poll() is None:process.terminate()
                    process.wait(timeout=3)
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
