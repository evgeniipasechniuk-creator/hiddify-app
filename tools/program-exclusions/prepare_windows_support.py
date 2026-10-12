"""Reuse verified upstream 4.0.4 CLI and Cronet, with the rebuilt core DLL."""
import hashlib
import shutil
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path

URL = 'https://github.com/hiddify/hiddify-app/releases/download/v4.0.4/Hiddify-Windows-Portable-x64.zip'
SHA256 = '1caecfcc2fec8885eed43dcf55c845b10e3221368413bf78e9df4d980d5bf02c'


if __name__ == '__main__':
    root = Path(__file__).resolve().parents[2]
    output = root / 'hiddify-core/bin'
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as temporary:
        archive = Path(temporary) / 'upstream.tar'
        subprocess.run(['curl', '-L', '--fail', '--retry', '2', '-o', str(archive), URL], check=True)
        if hashlib.sha256(archive.read_bytes()).hexdigest() != SHA256:
            raise ValueError('Official support archive checksum mismatch')
        # Upstream's .zip asset actually contains a TAR archive.
        with tarfile.open(archive) as bundle:
            bundle.extractall(temporary, filter='data')
        source = Path(temporary) / 'Hiddify'
        for name in ('HiddifyCli.exe', 'libcronet.dll'):
            shutil.copy2(source / name, output / name)
    rebuilt = Path(sys.argv[1])
    if not rebuilt.is_file():
        raise ValueError('The rebuilt core DLL is missing')
    shutil.copy2(rebuilt, output / 'hiddify-core.dll')
    print('Support binaries verified and prepared')
