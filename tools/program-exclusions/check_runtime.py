import hashlib
import sys
from pathlib import Path


if __name__ == '__main__':
    runtime = Path(sys.argv[1])
    rebuilt = Path(sys.argv[2])
    for relative in ['Hiddify.exe', 'HiddifyCli.exe', 'hiddify-core.dll', 'flutter_windows.dll',
                     'libcronet.dll', 'data/app.so', 'data/icudtl.dat',
                     'data/flutter_assets/AssetManifest.bin']:
        file = runtime / relative
        if not file.is_file() or file.stat().st_size == 0:
            raise ValueError(f'Required runtime component missing: {relative}')
    if hashlib.sha256((runtime / 'hiddify-core.dll').read_bytes()).digest() != hashlib.sha256(rebuilt.read_bytes()).digest():
        raise ValueError('The application was bundled with the wrong core DLL')
    if (runtime / 'data/app.so').read_bytes()[:4] != b'\x7fELF':
        raise ValueError('AOT snapshot was not produced')
    print('Windows runtime components and rebuilt core verified')
