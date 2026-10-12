import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/program_exclusions/program_exclusion.dart';

void main() {
  test('Only absolute Windows EXE paths are accepted', () {
    for (final path in ['', 'app.exe', r'\app.exe', r'C:\app.dll', 'C:\\app.exe\n']) {
      expect(() => ProgramExclusion(path), throwsFormatException);
    }
    expect(ProgramExclusion('C:/Program Files/App/App.exe').path, r'C:\Program Files\App\App.exe');
    expect(ProgramExclusion(r'\\server\share\app.exe').name, 'app.exe');
  });

  test('Duplicates are case-insensitive; distinct full paths are retained', () {
    final entries = uniquePrograms([
      ProgramExclusion(r'C:\One\App.exe'),
      ProgramExclusion(r'c:\ONE\APP.exe'),
      ProgramExclusion(r'C:\Two\App.exe'),
    ]);
    expect(entries.length, 2);
    expect(() => entries.clear(), throwsUnsupportedError);
  });

  test('Disabling retains the selected executable', () {
    final entry = ProgramExclusion(r'C:\App.exe');
    final disabled = entry.copyWith(enabled: false);
    expect(disabled.enabled, false);
    expect(disabled.path, entry.path);
    expect(entry.enabled, true);
  });

  test('Reject malformed JSON entries rather than silently clearing exclusions', () {
    for (final value in [
      null,
      {},
      {'path': r'C:\App.exe'},
      {'path': r'C:\App.exe', 'enabled': 'yes'},
    ]) {
      expect(() => ProgramExclusion.fromJson(value), throwsFormatException);
    }
  });

  test('Settings survive saving, reload, toggling and removal', () async {
    final temp = await Directory.systemTemp.createTemp('hiddify-program-test-');
    addTearDown(() => temp.delete(recursive: true));
    final file = File('${temp.path}/program_exclusions.json');
    final store = ProgramExclusionStore(file);
    expect(store.load(), isEmpty);
    await store.save([
      ProgramExclusion(r'C:\Alfa\Terminal.exe'),
      ProgramExclusion(r'C:\Telegram\Telegram.exe', enabled: false),
    ]);
    final loaded = ProgramExclusionStore(file).load();
    expect(loaded.map((e) => e.path).toList(), [r'C:\Alfa\Terminal.exe', r'C:\Telegram\Telegram.exe']);
    expect(loaded.last.enabled, false);
    await store.save([loaded.last.copyWith(enabled: true)]);
    expect(store.load().single.enabled, true);
    expect(File('${file.path}.previous').existsSync(), true);
    await store.save([]);
    expect(store.load(), isEmpty);
  });

  test('Interrupted rename uses recovery copy; corrupt main file is reported', () async {
    final temp = await Directory.systemTemp.createTemp('hiddify-recovery-test-');
    addTearDown(() => temp.delete(recursive: true));
    final file = File('${temp.path}/program_exclusions.json');
    final backup = File('${file.path}.previous');
    await backup.writeAsString(
      jsonEncode({
        'schema': 1,
        'programs': [ProgramExclusion(r'C:\App.exe').toJson()],
      }),
    );
    final store = ProgramExclusionStore(file);
    expect(store.load().single.path, r'C:\App.exe');
    await file.writeAsString('{broken');
    expect(store.load, throwsFormatException);
    expect(await file.readAsString(), '{broken');
  });
}
