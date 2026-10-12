import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/program_exclusions/program_exclusion.dart';
import 'package:hiddify/features/program_exclusions/program_exclusions_controller.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/singbox/model/singbox_config_enum.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

String programExclusionsTitle(BuildContext context) =>
    Localizations.localeOf(context).languageCode == 'ru' ? 'Исключения программ' : 'Application exclusions';

class ProgramExclusionsPage extends ConsumerStatefulWidget {
  const ProgramExclusionsPage({super.key});

  @override
  ConsumerState<ProgramExclusionsPage> createState() => _ProgramExclusionsPageState();
}

class _ProgramExclusionsPageState extends ConsumerState<ProgramExclusionsPage> {
  List<ProgramExclusion>? _draft;
  bool _busy = false;
  bool _retryApply = false;
  String? _message;

  String _text(String ru, String en) => Localizations.localeOf(context).languageCode == 'ru' ? ru : en;

  bool _same(List<ProgramExclusion> a, List<ProgramExclusion> b) =>
      jsonEncode(a.map((e) => e.toJson()).toList()) == jsonEncode(b.map((e) => e.toJson()).toList());

  Future<void> _add() async {
    setState(() => _busy = true);
    try {
      final files = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['exe'],
        allowMultiple: true,
        dialogTitle: _text('Выберите программы для работы без VPN', 'Choose applications to bypass the VPN'),
      );
      if (files == null || !mounted) return;
      final added = <ProgramExclusion>[];
      for (final selected in files.files) {
        final path = selected.path;
        if (path == null || !await File(path).exists()) {
          throw const FormatException('Executable file is missing');
        }
        added.add(ProgramExclusion(path));
      }
      if (!mounted) return;
      setState(() {
        _draft = uniquePrograms([...?_draft, ...added]);
        _message = _text('Нажмите «Применить», чтобы сохранить изменения.', 'Click Apply to save your changes.');
      });
    } catch (error) {
      if (mounted) {
        setState(() => _message = _text('Не удалось добавить программу: $error', 'Could not add application: $error'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _apply() async {
    final draft = _draft;
    if (draft == null || _busy) return;
    setState(() {
      _busy = true;
      _retryApply = false;
      _message = _text('Сохраняем и применяем исключения…', 'Saving and applying exclusions…');
    });
    try {
      await ref.read(programExclusionsProvider.notifier).save(draft);
      final wasConnected = ref.read(connectionNotifierProvider).valueOrNull?.isConnected == true;
      if (wasConnected) {
        final profile = await ref.read(activeProfileProvider.future);
        await ref.read(connectionNotifierProvider.notifier).reconnect(profile);
        final result = ref.read(connectionNotifierProvider);
        if (result.hasError) {
          throw StateError(_text('Переподключение завершилось ошибкой.', 'Reconnection failed.'));
        }
      }
      if (!mounted) return;
      final mode = ref.read(ConfigOptions.serviceMode);
      final isTun = mode == ServiceMode.tun || mode == ServiceMode.tunService;
      setState(() {
        _message = wasConnected && isTun
            ? _text(
                'Сохранено. Исключения переданы движку VPN. Перезапустите выбранные программы, чтобы открыть новые соединения.',
                'Saved and sent to the VPN engine. Restart selected applications to open new connections.',
              )
            : _text(
                'Сохранено. Исключения включатся при следующем подключении в режиме VPN.',
                'Saved. Exclusions will take effect on your next connection in VPN mode.',
              );
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _retryApply = true;
          _message = _text('Не удалось применить: $error', 'Could not apply: $error');
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final saved = ref.watch(programExclusionsProvider);
    final connection = ref.watch(connectionNotifierProvider);
    final mode = ref.watch(ConfigOptions.serviceMode);
    final isTun = mode == ServiceMode.tun || mode == ServiceMode.tunService;
    return Scaffold(
      appBar: AppBar(title: Text(programExclusionsTitle(context))),
      body: saved.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _text(
              'Не удалось прочитать исключения. Настройки не изменены.\n$error',
              'Could not read exclusions. Settings were not changed.\n$error',
            ),
          ),
        ),
        data: (entries) {
          _draft ??= entries.toList();
          final draft = _draft!;
          final dirty = !_same(draft, entries);
          final switching = connection.valueOrNull?.isSwitching == true || connection.isLoading;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                _text(
                  'Выбранные программы подключаются к интернету напрямую. Остальные используют обычные правила Hiddify.',
                  'Selected applications connect directly to the internet. Other applications use your usual Hiddify rules.',
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isTun
                            ? _text(
                                'Режим VPN выбран · включено исключений: ${entries.where((e) => e.enabled).length}',
                                'VPN mode selected · enabled exclusions: ${entries.where((e) => e.enabled).length}',
                              )
                            : _text(
                                'Исключения сейчас не действуют: выбран режим прокси.',
                                'Exclusions are inactive: proxy mode is selected.',
                              ),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (!isTun) ...[
                        const SizedBox(height: 8),
                        Text(
                          _text(
                            'В настройках подключения выберите VPN или VPN через службу. Только эти режимы позволяют надёжно различать программы.',
                            'Choose VPN or VPN via service in connection settings. These modes allow reliable application routing.',
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _busy ? null : () => context.goNamed('inboundOptions'),
                          icon: const Icon(Icons.settings_ethernet),
                          label: Text(_text('Настройки подключения', 'Connection settings')),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: _busy ? null : _add,
                    icon: const Icon(Icons.add),
                    label: Text(_text('Добавить .exe', 'Add .exe')),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _busy || switching || (!dirty && !_retryApply) ? null : _apply,
                    icon: const Icon(Icons.check),
                    label: Text(_text('Применить', 'Apply')),
                  ),
                  TextButton(
                    onPressed: _busy || !dirty
                        ? null
                        : () => setState(() {
                            _draft = entries.toList();
                            _message = null;
                          }),
                    child: Text(_text('Отменить изменения', 'Discard changes')),
                  ),
                ],
              ),
              if (_busy) ...[const SizedBox(height: 12), const LinearProgressIndicator()],
              if (_message != null)
                Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: SelectableText(_message!)),
              if (draft.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 28),
                  child: Text(
                    _text(
                      'Исключений пока нет. Можно выбрать несколько программ сразу.',
                      'No exclusions yet. You can select several applications at once.',
                    ),
                  ),
                ),
              for (var i = 0; i < draft.length; i++)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.desktop_windows_outlined),
                    title: Text(draft[i].name),
                    subtitle: SelectableText(draft[i].path),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Switch(
                          value: draft[i].enabled,
                          onChanged: _busy
                              ? null
                              : (enabled) => setState(() {
                                  _draft = [...draft];
                                  _draft![i] = draft[i].copyWith(enabled: enabled);
                                  _message = null;
                                }),
                        ),
                        IconButton(
                          tooltip: _text('Убрать исключение', 'Remove exclusion'),
                          icon: const Icon(Icons.delete_outline),
                          onPressed: _busy
                              ? null
                              : () => setState(() {
                                  _draft = [...draft]..removeAt(i);
                                  _message = null;
                                }),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              Text(
                _text(
                  'Выбирайте .exe, который создаёт сетевые соединения. Если программа использует отдельный сетевой процесс, добавьте и его. Настройки прокси внутри самой программы должны быть выключены. DNS Windows может обслуживаться общей системной службой.',
                  'Select the .exe that creates network connections. Add a separate network helper if used. Disable proxy settings inside the selected application. Windows DNS may be handled by a shared system service.',
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Text(
                _text(
                  'Доработка «Исключения программ» 1.0 · Hiddify 4.0.4',
                  'Application exclusions 1.0 · Hiddify 4.0.4',
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          );
        },
      ),
    );
  }
}
