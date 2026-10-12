import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/program_exclusions/program_exclusion.dart';
import 'package:hiddify/features/program_exclusions/program_exclusions_controller.dart';
import 'package:hiddify/features/program_exclusions/program_exclusions_page.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MemoryExclusions extends ProgramExclusionsController {
  MemoryExclusions(this.entries, {this.waitForSave});
  final List<ProgramExclusion> entries;
  final Completer<void>? waitForSave;
  List<ProgramExclusion>? saved;

  @override
  Future<List<ProgramExclusion>> build() async => entries;

  @override
  Future<void> save(List<ProgramExclusion> programs) async {
    saved = programs;
    await waitForSave?.future;
    state = AsyncData(uniquePrograms(programs));
  }
}

class OfflineConnection extends ConnectionNotifier {
  @override
  Stream<ConnectionStatus> build() => Stream.value(const Disconnected());
}

class FailingConnection extends ConnectionNotifier {
  @override
  Stream<ConnectionStatus> build() => Stream.value(const Connected());

  @override
  Future<void> reconnect(ProfileEntity? profile) async {
    state = AsyncError(StateError('reconnect failed'), StackTrace.current);
  }
}

class EmptyProfile extends ActiveProfile {
  @override
  Stream<ProfileEntity?> build() => Stream.value(null);
}

Future<void> mountPage(
  WidgetTester tester,
  MemoryExclusions controller, {
  String mode = 'vpn',
  bool failReconnect = false,
}) async {
  SharedPreferences.setMockInitialValues({'service-mode': mode});
  final preferences = await SharedPreferences.getInstance();
  tester.view.physicalSize = const Size(1000, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        programExclusionsProvider.overrideWith(() => controller),
        connectionNotifierProvider.overrideWith(failReconnect ? FailingConnection.new : OfflineConnection.new),
        activeProfileProvider.overrideWith(EmptyProfile.new),
        sharedPreferencesProvider.overrideWith((ref) => preferences),
      ],
      child: const MaterialApp(
        locale: Locale('ru'),
        supportedLocales: [Locale('ru'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: ProgramExclusionsPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Proxy mode clearly states that exclusions are inactive', (tester) async {
    await mountPage(tester, MemoryExclusions([ProgramExclusion(r'C:\Alfa\Terminal.exe')]), mode: 'system-proxy');
    expect(find.text('Исключения сейчас не действуют: выбран режим прокси.'), findsOneWidget);
    expect(find.text('Настройки подключения'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Toggle is a draft until Apply and shows progress while saving', (tester) async {
    final gate = Completer<void>();
    final controller = MemoryExclusions([ProgramExclusion(r'C:\Alfa\Terminal.exe')], waitForSave: gate);
    await mountPage(tester, controller);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(controller.saved, isNull);
    await tester.tap(find.text('Применить'));
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(controller.saved!.single.enabled, false);
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('Сохранено. Исключения включатся при следующем подключении в режиме VPN.'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('Removing and discarding changes restore the saved selection', (tester) async {
    final controller = MemoryExclusions([ProgramExclusion(r'C:\Alfa\Terminal.exe')]);
    await mountPage(tester, controller);
    await tester.tap(find.byTooltip('Убрать исключение'));
    await tester.pumpAndSettle();
    expect(find.text('Terminal.exe'), findsNothing);
    await tester.tap(find.text('Отменить изменения'));
    await tester.pumpAndSettle();
    expect(find.text('Terminal.exe'), findsOneWidget);
    expect(controller.saved, isNull);
  });

  testWidgets('Failed reconnect is visible and Apply remains available after saving', (tester) async {
    final controller = MemoryExclusions([ProgramExclusion(r'C:\Alfa\Terminal.exe')]);
    await mountPage(tester, controller, failReconnect: true);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Применить'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Не удалось применить:'), findsOneWidget);
    final button = tester.widget<ButtonStyleButton>(
      find
          .ancestor(
            of: find.text('Применить'),
            matching: find.byWidgetPredicate((widget) => widget is ButtonStyleButton),
          )
          .first,
    );
    expect(button.onPressed, isNotNull);
    expect(controller.saved!.single.enabled, false);
  });
}
