import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// One executable, not all processes with the same basename.
class ProgramExclusion {
  ProgramExclusion(String path, {this.enabled = true}) : path = normalizeExecutablePath(path);

  final String path;
  final bool enabled;

  String get name => p.windows.basename(path);
  String get identity => path.toLowerCase();

  ProgramExclusion copyWith({bool? enabled}) => ProgramExclusion(path, enabled: enabled ?? this.enabled);

  Map<String, Object> toJson() => {'path': path, 'enabled': enabled};

  factory ProgramExclusion.fromJson(Object? json) {
    if (json is! Map<String, dynamic> || json['path'] is! String || json['enabled'] is! bool) {
      throw const FormatException('Invalid program exclusion');
    }
    return ProgramExclusion(json['path'] as String, enabled: json['enabled'] as bool);
  }
}

String normalizeExecutablePath(String value) {
  final path = p.windows.normalize(value.replaceAll('/', r'\'));
  if (!p.windows.isAbsolute(path) ||
      !path.toLowerCase().endsWith('.exe') ||
      path.contains(RegExp('[\x00\r\n]')) ||
      !RegExp(r'^(?:[a-zA-Z]:\\|\\\\[^\\]+\\[^\\]+\\)').hasMatch(path)) {
    throw const FormatException('Select the full path to an .exe file');
  }
  return path;
}

List<ProgramExclusion> uniquePrograms(Iterable<ProgramExclusion> programs) {
  final unique = <String, ProgramExclusion>{};
  for (final entry in programs) {
    unique.putIfAbsent(entry.identity, () => entry);
  }
  if (unique.length > 200) throw const FormatException('Maximum 200 programs');
  return List.unmodifiable(unique.values);
}

/// Publishing state happens only after a successful durable write. A recovery
/// copy is retained across the Windows rename operation and failed writes.
class ProgramExclusionStore {
  ProgramExclusionStore(this.file);

  final File file;
  File get _backup => File('${file.path}.previous');

  List<ProgramExclusion> load() {
    final candidate = file.existsSync() ? file : _backup;
    if (!candidate.existsSync()) return const [];
    final json = jsonDecode(candidate.readAsStringSync());
    if (json is! Map<String, dynamic> || json['schema'] != 1 || json['programs'] is! List) {
      throw const FormatException('Unsupported exclusions file');
    }
    return uniquePrograms((json['programs'] as List).map(ProgramExclusion.fromJson));
  }

  Future<void> save(Iterable<ProgramExclusion> programs) async {
    final next = uniquePrograms(programs);
    await file.parent.create(recursive: true);
    final pending = File('${file.path}.pending');
    await pending.writeAsString(
      jsonEncode({'schema': 1, 'programs': next.map((e) => e.toJson()).toList()}),
      flush: true,
    );
    if (await file.exists()) await file.copy(_backup.path);
    try {
      await pending.rename(file.path);
    } catch (_) {
      // Do not remove a valid settings file to make a failed rename succeed.
      if (await pending.exists()) await pending.delete();
      rethrow;
    }
  }
}
