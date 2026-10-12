"""Compare verified upstream startup with the rebuilt core on Windows CI."""
import hashlib
import json
import os
from pathlib import Path
import runpy
import shutil
import subprocess
import sys
import tarfile

from smoke_windows import launch_and_check


def main() -> None:
    if os.name != 'nt' or os.environ.get('GITHUB_ACTIONS') != 'true':
        raise RuntimeError('Use an isolated Windows GitHub runner')
    expected_core = Path(sys.argv[1]).resolve()
    output = Path(sys.argv[2]).resolve()
    output.mkdir(parents=True, exist_ok=True)
    root = Path(os.environ['RUNNER_TEMP']) / 'hiddify-startup-diagnostics'
    root.mkdir(parents=True, exist_ok=False)
    settings = runpy.run_path(str(Path(__file__).with_name('prepare_windows_support.py')))
    archive = root / 'upstream.tar'
    subprocess.run(['curl', '-L', '--fail', '--retry', '2', '-o', str(archive), settings['URL']],
                   check=True, timeout=180)
    if hashlib.sha256(archive.read_bytes()).hexdigest() != settings['SHA256']:
        raise RuntimeError('Original portable checksum mismatch')
    with tarfile.open(archive) as bundle:
        bundle.extractall(root / 'upstream', filter='data')
    original = root / 'upstream/Hiddify'
    report = {'original_sha256': settings['SHA256'], 'cases': {}}
    cases = [('original_ascii', False, False), ('original_unicode', False, True),
             ('modified_core_ascii', True, False), ('modified_core_unicode', True, True)]
    for name, modified, unicode_path in cases:
        target = root / (name + (' Проверка' if unicode_path else ''))
        shutil.copytree(original, target)
        if modified:
            shutil.copy2(expected_core, target / 'hiddify-core.dll')
        try:
            info = launch_and_check(target, output / (name + '.log'))
            report['cases'][name] = {'status': 'passed', **info}
        except Exception as error:
            report['cases'][name] = {'status': 'failed', 'error': str(error)}
        (output / 'STARTUP_DIAGNOSTICS.json').write_text(
            json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
        for log in target.glob('hiddify_portable_data/**/*.log'):
            text = log.read_text(encoding='utf-8', errors='replace')[-30000:]
            (output / (name + '_' + log.name)).write_text(text, encoding='utf-8')
    commands = {
        'application_events.json': "Get-WinEvent -FilterHashtable @{LogName='Application';Id=1000,1001;StartTime=(Get-Date).AddMinutes(-20)} -ErrorAction SilentlyContinue | Select-Object TimeCreated,Id,Message | ConvertTo-Json -Depth 4",
        'video_controllers.json': 'Get-CimInstance Win32_VideoController | Select-Object Name,DriverVersion,VideoProcessor | ConvertTo-Json',
        'sessions.txt': 'qwinsta',
    }
    for name, command in commands.items():
        result = subprocess.run(['pwsh', '-NoProfile', '-Command', command],
                                capture_output=True, timeout=30)
        (output / name).write_bytes(result.stdout + result.stderr)
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
