"""Install and launch the built release only on an isolated GitHub Windows runner.

This checks installation, a responsive native Flutter window, update backups,
and preservation of exclusions. It does not assert real VPN connectivity.
"""
import argparse
import ctypes
from ctypes import wintypes
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run_setup(installer: Path, target: Path, log: Path) -> None:
    result = subprocess.run(
        [str(installer), '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART',
         '/SP-', f'/DIR={target}', f'/LOG={log}'],
        timeout=180, check=False,
    )
    if result.returncode != 0:
        raise RuntimeError(f'Installer returned {result.returncode}; see {log.name}')


def window_for_process(pid: int):
    user32 = ctypes.WinDLL('user32', use_last_error=True)
    callback_type = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)
    user32.EnumWindows.argtypes = [callback_type, wintypes.LPARAM]
    user32.EnumWindows.restype = wintypes.BOOL
    user32.GetWindowThreadProcessId.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.DWORD)]
    user32.IsWindowVisible.argtypes = [wintypes.HWND]
    user32.GetWindowTextW.argtypes = [wintypes.HWND, wintypes.LPWSTR, ctypes.c_int]
    user32.GetClassNameW.argtypes = [wintypes.HWND, wintypes.LPWSTR, ctypes.c_int]
    user32.GetWindowRect.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.RECT)]
    found = []

    @callback_type
    def inspect(hwnd, _):
        owner = wintypes.DWORD()
        user32.GetWindowThreadProcessId(hwnd, ctypes.byref(owner))
        if owner.value != pid or not user32.IsWindowVisible(hwnd):
            return True
        title = ctypes.create_unicode_buffer(512)
        kind = ctypes.create_unicode_buffer(256)
        rect = wintypes.RECT()
        user32.GetWindowTextW(hwnd, title, len(title))
        user32.GetClassNameW(hwnd, kind, len(kind))
        user32.GetWindowRect(hwnd, ctypes.byref(rect))
        if kind.value == 'FLUTTER_RUNNER_WIN32_WINDOW' and rect.right - rect.left > 300:
            found.append((hwnd, title.value, kind.value))
        return True

    user32.EnumWindows(inspect, 0)
    return found[0] if found else None


def launch_and_check(target: Path, log: Path) -> dict:
    user32 = ctypes.WinDLL('user32', use_last_error=True)
    user32.SendMessageTimeoutW.argtypes = [
        wintypes.HWND, wintypes.UINT, wintypes.WPARAM, wintypes.LPARAM,
        wintypes.UINT, wintypes.UINT, ctypes.POINTER(ctypes.c_size_t),
    ]
    user32.SendMessageTimeoutW.restype = wintypes.LPARAM
    essential = {
        'PATH', 'SYSTEMROOT', 'SYSTEMDRIVE', 'WINDIR', 'COMSPEC', 'APPDATA',
        'LOCALAPPDATA', 'PROGRAMDATA', 'PROGRAMFILES', 'PROGRAMFILES(X86)',
        'COMMONPROGRAMFILES', 'COMMONPROGRAMFILES(X86)', 'TEMP', 'TMP',
        'USERPROFILE', 'USERNAME', 'USERDOMAIN', 'HOMEDRIVE', 'HOMEPATH',
        'PATHEXT', 'PROCESSOR_ARCHITECTURE', 'OS', 'NUMBER_OF_PROCESSORS',
    }
    # The tested app receives Windows essentials, not CI credentials or tokens.
    app_env = {key: value for key, value in os.environ.items() if key.upper() in essential}
    with log.open('wb') as output:
        process = subprocess.Popen(
            [str(target / 'Hiddify.exe')], cwd=target,
            stdout=output, stderr=subprocess.STDOUT, env=app_env,
        )
        try:
            deadline = time.monotonic() + 60
            window = None
            while time.monotonic() < deadline:
                if process.poll() is not None:
                    raise RuntimeError(f'Hiddify exited at startup: {process.returncode}')
                window = window_for_process(process.pid)
                if window:
                    break
                time.sleep(0.5)
            if not window:
                raise RuntimeError('A visible native Flutter window did not appear')
            for _ in range(20):
                if process.poll() is not None:
                    raise RuntimeError('Hiddify exited after opening its window')
                result = ctypes.c_size_t()
                # WM_NULL + SMTO_ABORTIFHUNG verifies the native UI thread responds.
                if not user32.SendMessageTimeoutW(window[0], 0, 0, 0, 2, 3000, ctypes.byref(result)):
                    raise RuntimeError('The native window stopped responding')
                time.sleep(0.5)
            return {'window_title': window[1], 'window_class': window[2],
                    'visible': True, 'responsive': True, 'stability_seconds': 10}
        finally:
            subprocess.run(['taskkill', '/PID', str(process.pid), '/T', '/F'],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=30)
            try:
                process.wait(timeout=15)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=15)


def main() -> None:
    if os.name != 'nt' or os.environ.get('GITHUB_ACTIONS') != 'true':
        raise RuntimeError('Run this verification only on an isolated GitHub Windows runner')
    parser = argparse.ArgumentParser()
    parser.add_argument('installer', type=Path)
    parser.add_argument('expected_core', type=Path)
    parser.add_argument('report_dir', type=Path)
    parser.add_argument('--source-commit', required=True)
    args = parser.parse_args()
    runner_temp = Path(os.environ['RUNNER_TEMP']).resolve()
    # Upstream 4.0.4 also crashes when its installation path is non-ASCII.
    # Keep the native runtime in a supported path; exclusions remain Unicode.
    target = runner_temp / 'HiddifyExclusionsSmoke'
    if target.exists():
        raise RuntimeError('Verification directory already exists')
    report_dir = args.report_dir.resolve()
    report_dir.mkdir(parents=True, exist_ok=True)
    report = {'source_commit': args.source_commit, 'installer_sha256': digest(args.installer),
              'real_vpn_connectivity': 'not_tested', 'status': 'running'}
    profile = Path(os.environ['APPDATA']) / 'Hiddify' / 'hiddify'
    exclusion_file = profile / 'program_exclusions.json'
    sentinel = profile / 'application_exclusions_ci_sentinel.txt'
    if exclusion_file.exists() or sentinel.exists():
        raise RuntimeError('Existing exclusions found; refusing to overwrite runner state')
    try:
        run_setup(args.installer.resolve(), target, report_dir / 'install.log')
        required = ['Hiddify.exe', 'HiddifyCli.exe', 'hiddify-core.dll', 'flutter_windows.dll',
                    'libcronet.dll', 'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll',
                    'data/app.so', 'data/icudtl.dat', 'data/flutter_assets/AssetManifest.bin']
        for relative in required:
            if not (target / relative).is_file():
                raise RuntimeError(f'Installed runtime file missing: {relative}')
        core_hash = digest(args.expected_core)
        if digest(target / 'hiddify-core.dll') != core_hash:
            raise RuntimeError('Installed core differs from the verified build')
        if (target / 'data/app.so').read_bytes()[:4] != b'\x7fELF':
            raise RuntimeError('Installed AOT snapshot is missing')
        report['clean_install'] = 'passed'
        profile.mkdir(parents=True, exist_ok=True)
        sentinel.write_text('preserve settings during install/update/uninstall', encoding='utf-8')
        fixture = target / 'test-fixtures' / 'Программа (1).exe'
        fixture.parent.mkdir(parents=True, exist_ok=True)
        import shutil
        shutil.copy2(Path(os.environ['WINDIR']) / 'System32/notepad.exe', fixture)
        exclusion_file.write_text(json.dumps({'schema': 1, 'programs': [
            {'path': str(fixture), 'enabled': True}
        ]}, ensure_ascii=False), encoding='utf-8')
        expected_settings = digest(exclusion_file)
        report['first_launch'] = launch_and_check(target, report_dir / 'first_launch.log')
        if digest(exclusion_file) != expected_settings:
            raise RuntimeError('Launching changed exclusions unexpectedly')
        run_setup(args.installer.resolve(), target, report_dir / 'update.log')
        backups = list((target / 'application-exclusions-backup').glob('*/hiddify-core.dll'))
        if not backups or not any(digest(path) == core_hash for path in backups):
            raise RuntimeError('Update did not preserve the previous core in its backup')
        if digest(exclusion_file) != expected_settings or not sentinel.exists():
            raise RuntimeError('Update changed or removed stored settings')
        report['update_and_backup'] = 'passed'
        report['settings_preserved_after_update'] = 'passed'
        report['second_launch'] = launch_and_check(target, report_dir / 'second_launch.log')
        uninstall = subprocess.run(
            [str(target / 'unins000.exe'), '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART'],
            check=False, timeout=120,
        )
        if uninstall.returncode != 0:
            raise RuntimeError(f'Uninstaller returned {uninstall.returncode}')
        if (target / 'Hiddify.exe').exists():
            raise RuntimeError('Uninstall did not remove the installed executable')
        if digest(exclusion_file) != expected_settings or not sentinel.exists():
            raise RuntimeError('Uninstall removed stored settings')
        report['uninstall_preserves_settings'] = 'passed'
        report['status'] = 'passed'
    except Exception as error:
        report['status'] = 'failed'
        report['error'] = str(error)
        raise
    finally:
        (report_dir / 'WINDOWS_SMOKE_REPORT.json').write_text(
            json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8',
        )
        exclusion_file.unlink(missing_ok=True)
        sentinel.unlink(missing_ok=True)


if __name__ == '__main__':
    main()
