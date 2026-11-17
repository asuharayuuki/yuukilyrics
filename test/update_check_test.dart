import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yuukilyrics/l10n/l10n.dart';
import 'package:yuukilyrics/services/update_check_service.dart';
import 'package:yuukilyrics/widgets/update_check_dialog.dart';

void main() {
  test(
    'compares published versions numerically and decodes release notes',
    () async {
      const tag = 'v2026.11.15';
      const notes = '## 本次更新\n\n- 更新说明';
      final client = MockClient((request) async {
        expect(
          request.url.path,
          '/repos/asuharayuuki/yuukilyrics/releases/latest',
        );
        return http.Response.bytes(
          utf8.encode(jsonEncode({'tag_name': tag, 'body': notes})),
          200,
        );
      });

      await http.runWithClient(() async {
        final older = (await UpdateCheckService.check('2026.9.14'))!;
        expect(older.isUpdate, isTrue);
        expect(older.notes, notes);
        expect(older.page.path, '/asuharayuuki/yuukilyrics/releases/tag/$tag');
        expect(
          (await UpdateCheckService.check('2026.11.15'))!.isUpdate,
          isFalse,
        );
        expect(
          (await UpdateCheckService.check('2026.12.1'))!.isUpdate,
          isFalse,
        );
      }, () => client);
    },
  );

  test('distinguishes no release from a failed request', () async {
    Future<AppRelease?> check(int status) => http.runWithClient(
      () => UpdateCheckService.check('2026.11.15'),
      () => MockClient((_) async => http.Response('', status)),
    );

    expect(await check(404), isNull);
    await expectLater(check(403), throwsA(isA<http.ClientException>()));
  });

  testWidgets('shows release notes and opens the matching release page', (
    tester,
  ) async {
    final release = AppRelease(
      tag: 'v2026.12.1',
      notes: '## 本次更新\n\n- 新增更新检查',
      isUpdate: true,
    );
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    final messenger = tester.binding.defaultBinaryMessenger;
    String? openedUrl;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'launch') {
        openedUrl = call.arguments['url'] as String?;
        return true;
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: UpdateCheckDialog(
          installedVersion: '2026.11.15',
          releaseCheck: Future.value(release),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('发现新版本'), findsOneWidget);
    expect(find.text('新增更新检查', findRichText: true), findsOneWidget);
    await tester.tap(find.text('打开发布页面'));
    await tester.pumpAndSettle();
    expect(openedUrl, release.page.toString());
  });
}
