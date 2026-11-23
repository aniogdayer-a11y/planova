import 'dart:io';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:auto_task_scheduler/main.dart';
import 'package:auto_task_scheduler/providers/planner_provider.dart';
import 'package:auto_task_scheduler/services/database_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (!const bool.fromEnvironment('CAPTURE_PREVIEWS')) return;
    final configFile = File('.dart_tool/package_config.json').absolute;
    final config = jsonDecode(await configFile.readAsString());
    final flutterPackage = (config['packages'] as List).firstWhere(
      (p) => p['name'] == 'flutter',
    );
    final sdk = Directory.fromUri(
      configFile.uri.resolve(flutterPackage['rootUri'] as String),
    ).parent.parent;
    final roboto = File(
      '${sdk.path}/engine/src/flutter/txt/third_party/fonts/Roboto-Regular.ttf',
    );
    final fallback = File('C:/Windows/Fonts/segoeui.ttf');
    final font = await roboto.exists() ? roboto : fallback;
    if (await font.exists()) {
      final loader = FontLoader('Roboto')
        ..addFont(Future.value(ByteData.sublistView(await font.readAsBytes())));
      await loader.load();
    }
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  testWidgets('screens fit small phones and larger text without overflow', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    late DatabaseService db;
    late PlannerProvider provider;
    await tester.runAsync(() async {
      db = await DatabaseService.inMemory();
      provider = PlannerProvider(database: db);
      await provider.ready;
      provider.preparePlanDraft();
      provider.addDraftTask('Design poster', duration: 50);
      provider.addDraftTask('Review notes', duration: 30);
      await provider.generateDraft(useGemini: false);
      await provider.saveDraft();
    });
    final boundaryKey = GlobalKey();
    for (final width in [320.0, 390.0, 820.0, 1440.0]) {
      tester.view.physicalSize = Size(width, 844);
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: AutoTaskSchedulerApp(plannerProvider: provider),
        ),
      );
      await tester.pumpAndSettle();
      for (var tab = 0; tab < 5; tab++) {
        provider.setTabIndex(tab);
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: 'Tab $tab at width $width',
        );
        if (width == 390 && const bool.fromEnvironment('CAPTURE_PREVIEWS')) {
          await tester.runAsync(() async {
            final boundary =
                boundaryKey.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final image = await boundary.toImage(pixelRatio: 2);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final file = File(
              'build/previews/${['home', 'tasks', 'tips', 'profile', 'settings'][tab]}.png',
            );
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
      }
    }
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    for (var tab = 0; tab < 5; tab++) {
      provider.setTabIndex(tab);
      await tester.pumpAndSettle();
      expect(
        tester.takeException(),
        isNull,
        reason: 'Tab $tab with larger text',
      );
    }
    await tester.pumpWidget(const SizedBox.shrink());
    provider.dispose();
    await tester.runAsync(db.close);
  });
}
