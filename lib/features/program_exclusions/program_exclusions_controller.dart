import 'dart:io';

import 'package:hiddify/core/directories/directories_provider.dart';
import 'package:hiddify/features/program_exclusions/program_exclusion.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path/path.dart' as p;

final programExclusionsProvider = AsyncNotifierProvider<ProgramExclusionsController, List<ProgramExclusion>>(
  ProgramExclusionsController.new,
);

class ProgramExclusionsController extends AsyncNotifier<List<ProgramExclusion>> {
  late ProgramExclusionStore _store;

  @override
  Future<List<ProgramExclusion>> build() async {
    final dirs = await ref.watch(appDirectoriesProvider.future);
    _store = ProgramExclusionStore(File(p.join(dirs.baseDir.path, 'program_exclusions.json')));
    return _store.load();
  }

  Future<void> save(List<ProgramExclusion> programs) async {
    final next = uniquePrograms(programs);
    await _store.save(next);
    state = AsyncData(next);
  }
}
