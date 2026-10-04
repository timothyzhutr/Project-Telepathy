"""Create a source-free executable release archive, preserving executable modes and symlinks."""
import hashlib,stat,subprocess,zipfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];DIST=ROOT/'dist';VERSION='0.1.6'
def main():
    subprocess.run([__import__('sys').executable,str(ROOT/'scripts/verify_package.py'),str(DIST/'Telepathy.app')],check=True)
    out=ROOT/'.build/release';out.mkdir(parents=True,exist_ok=True)
    prefix=f'Telepathy-{VERSION}-macos-arm64';archive=out/(prefix+'.zip')
    with zipfile.ZipFile(archive,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=6) as z:
        for path in sorted(DIST.rglob('*')):
            name=prefix+'/'+str(path.relative_to(DIST));mode=path.lstat().st_mode
            if path.is_symlink():
                entry=zipfile.ZipInfo(name);entry.create_system=3;entry.external_attr=(stat.S_IFLNK|0o755)<<16
                z.writestr(entry,__import__('os').readlink(path))
            elif path.is_file():z.write(path,name)
            elif path.is_dir():
                entry=zipfile.ZipInfo(name+'/');entry.create_system=3;entry.external_attr=(stat.S_IFDIR|0o755)<<16
                z.writestr(entry,b'')
    with archive.open('rb') as f:digest=hashlib.file_digest(f,'sha256').hexdigest()
    (out/'SHA256SUMS').write_text(digest+'  '+archive.name+'\n')
    print('Release:',archive.name,'bytes:',archive.stat().st_size,'SHA-256:',digest)
if __name__=='__main__':main()
