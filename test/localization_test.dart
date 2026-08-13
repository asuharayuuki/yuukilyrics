import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuukilyrics/l10n/generated/app_localizations.dart';
import 'package:yuukilyrics/main.dart';

void main() {
  test('uses Chinese for Chinese system locales', () {
    expect(
      resolveAppLocale(
        const Locale.fromSubtags(languageCode: 'zh', countryCode: 'CN'),
        AppLocalizations.supportedLocales,
      ),
      const Locale('zh'),
    );
  });

  test('uses Japanese for Japanese and unsupported system locales', () {
    expect(
      resolveAppLocale(const Locale('ja'), AppLocalizations.supportedLocales),
      const Locale('ja'),
    );
    expect(
      resolveAppLocale(const Locale('en'), AppLocalizations.supportedLocales),
      const Locale('ja'),
    );
  });

  test('debug locale override accepts Japanese and Chinese only', () {
    expect(
      debugAppLocaleOverride(debugMode: true, localeName: 'zh-CN'),
      const Locale('zh'),
    );
    expect(
      debugAppLocaleOverride(debugMode: true, localeName: 'ja_JP'),
      const Locale('ja'),
    );
    expect(debugAppLocaleOverride(debugMode: true, localeName: 'en'), isNull);
  });

  test('release and profile modes always ignore locale override', () {
    expect(debugAppLocaleOverride(debugMode: false, localeName: 'zh'), isNull);
  });

  test('Japanese and Chinese resources are generated', () async {
    final ja = await AppLocalizations.delegate.load(const Locale('ja'));
    final zh = await AppLocalizations.delegate.load(const Locale('zh'));

    expect(ja.assetLibrary, '素材ライブラリ');
    expect(zh.assetLibrary, '素材库');
  });

  test('Android exposes Japanese and Chinese as per-app languages', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final localeConfig = File(
      'android/app/src/main/res/xml/locale_config.xml',
    ).readAsStringSync();

    expect(manifest, contains('android:localeConfig="@xml/locale_config"'));
    expect(localeConfig, contains('android:name="ja"'));
    expect(localeConfig, contains('android:name="zh"'));
  });

  test('iOS exposes Japanese and Simplified Chinese as app languages', () {
    final infoPlist = File('ios/Runner/Info.plist').readAsStringSync();
    final project = File(
      'ios/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();

    expect(infoPlist, contains('<key>CFBundleLocalizations</key>'));
    expect(infoPlist, contains('<string>ja</string>'));
    expect(infoPlist, contains('<string>zh-Hans</string>'));
    expect(project, contains('"zh-Hans",'));
  });
}
