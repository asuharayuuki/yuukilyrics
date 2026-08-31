import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ja.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ja'),
    Locale('zh'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In ja, this message translates to:
  /// **'yuukilyrics'**
  String get appTitle;

  /// No description provided for @cancel.
  ///
  /// In ja, this message translates to:
  /// **'キャンセル'**
  String get cancel;

  /// No description provided for @apply.
  ///
  /// In ja, this message translates to:
  /// **'適用'**
  String get apply;

  /// No description provided for @close.
  ///
  /// In ja, this message translates to:
  /// **'閉じる'**
  String get close;

  /// No description provided for @delete.
  ///
  /// In ja, this message translates to:
  /// **'削除'**
  String get delete;

  /// No description provided for @refresh.
  ///
  /// In ja, this message translates to:
  /// **'更新'**
  String get refresh;

  /// No description provided for @share.
  ///
  /// In ja, this message translates to:
  /// **'共有'**
  String get share;

  /// No description provided for @confirm.
  ///
  /// In ja, this message translates to:
  /// **'決定'**
  String get confirm;

  /// No description provided for @openNavigationMenu.
  ///
  /// In ja, this message translates to:
  /// **'ナビゲーションメニューを開く'**
  String get openNavigationMenu;

  /// No description provided for @file.
  ///
  /// In ja, this message translates to:
  /// **'ファイル'**
  String get file;

  /// No description provided for @preview.
  ///
  /// In ja, this message translates to:
  /// **'プレビュー'**
  String get preview;

  /// No description provided for @export.
  ///
  /// In ja, this message translates to:
  /// **'出力'**
  String get export;

  /// No description provided for @automatic.
  ///
  /// In ja, this message translates to:
  /// **'自動'**
  String get automatic;

  /// No description provided for @automaticPixels.
  ///
  /// In ja, this message translates to:
  /// **'自動（{value} px）'**
  String automaticPixels(Object value);

  /// No description provided for @mediaOpenFailed.
  ///
  /// In ja, this message translates to:
  /// **'メディアファイルを開けませんでした：{error}'**
  String mediaOpenFailed(Object error);

  /// No description provided for @waveformAnalysisFailed.
  ///
  /// In ja, this message translates to:
  /// **'波形の解析に失敗しました：{error}'**
  String waveformAnalysisFailed(Object error);

  /// No description provided for @exportFile.
  ///
  /// In ja, this message translates to:
  /// **'ファイルを出力'**
  String get exportFile;

  /// No description provided for @fileName.
  ///
  /// In ja, this message translates to:
  /// **'ファイル名'**
  String get fileName;

  /// No description provided for @saveToDevice.
  ///
  /// In ja, this message translates to:
  /// **'デバイスに保存'**
  String get saveToDevice;

  /// No description provided for @emptyLyricsCannotExport.
  ///
  /// In ja, this message translates to:
  /// **'歌詞が空のため、出力できません。'**
  String get emptyLyricsCannotExport;

  /// No description provided for @timedLyricsShareSubject.
  ///
  /// In ja, this message translates to:
  /// **'タイムタグ付き歌詞：{fileName}'**
  String timedLyricsShareSubject(Object fileName);

  /// No description provided for @chooseLyricsSaveLocation.
  ///
  /// In ja, this message translates to:
  /// **'歌詞ファイルの保存先を選択'**
  String get chooseLyricsSaveLocation;

  /// No description provided for @lyricsFileSaved.
  ///
  /// In ja, this message translates to:
  /// **'歌詞ファイルを保存しました：{path}'**
  String lyricsFileSaved(Object path);

  /// No description provided for @lyricsExportFailed.
  ///
  /// In ja, this message translates to:
  /// **'歌詞ファイルの出力に失敗しました：{error}'**
  String lyricsExportFailed(Object error);

  /// No description provided for @assShareSubject.
  ///
  /// In ja, this message translates to:
  /// **'ASS 字幕：{fileName}'**
  String assShareSubject(Object fileName);

  /// No description provided for @chooseAssSaveLocation.
  ///
  /// In ja, this message translates to:
  /// **'ASS 字幕の保存先を選択'**
  String get chooseAssSaveLocation;

  /// No description provided for @assSaved.
  ///
  /// In ja, this message translates to:
  /// **'ASS 字幕を保存しました：{path}'**
  String assSaved(Object path);

  /// No description provided for @assExportFailed.
  ///
  /// In ja, this message translates to:
  /// **'ASS 字幕の出力に失敗しました：{error}'**
  String assExportFailed(Object error);

  /// No description provided for @chooseVideoSaveLocation.
  ///
  /// In ja, this message translates to:
  /// **'動画の保存先を選択'**
  String get chooseVideoSaveLocation;

  /// No description provided for @outputPreparationFailed.
  ///
  /// In ja, this message translates to:
  /// **'出力先を準備できませんでした：{error}'**
  String outputPreparationFailed(Object error);

  /// No description provided for @detectingEncoder.
  ///
  /// In ja, this message translates to:
  /// **'エンコーダーを検出中…'**
  String get detectingEncoder;

  /// No description provided for @encodingVideo.
  ///
  /// In ja, this message translates to:
  /// **'動画をエンコード中…'**
  String get encodingVideo;

  /// No description provided for @burningSubtitles.
  ///
  /// In ja, this message translates to:
  /// **'字幕を動画に焼き付けています。しばらくお待ちください。'**
  String get burningSubtitles;

  /// No description provided for @encoderName.
  ///
  /// In ja, this message translates to:
  /// **'エンコーダー：{codec}'**
  String encoderName(Object codec);

  /// No description provided for @videoSaved.
  ///
  /// In ja, this message translates to:
  /// **'動画を保存しました：{path}'**
  String videoSaved(Object path);

  /// No description provided for @hardsubVideoShareSubject.
  ///
  /// In ja, this message translates to:
  /// **'字幕付き動画：{fileName}'**
  String hardsubVideoShareSubject(Object fileName);

  /// No description provided for @encodingFailed.
  ///
  /// In ja, this message translates to:
  /// **'エンコードに失敗しました'**
  String get encodingFailed;

  /// No description provided for @openMediaFile.
  ///
  /// In ja, this message translates to:
  /// **'メディアファイルを開く'**
  String get openMediaFile;

  /// No description provided for @openMediaFileDescription.
  ///
  /// In ja, this message translates to:
  /// **'タイムタグを付ける音声または動画を読み込みます'**
  String get openMediaFileDescription;

  /// No description provided for @openLyricsFile.
  ///
  /// In ja, this message translates to:
  /// **'歌詞ファイルを開く'**
  String get openLyricsFile;

  /// No description provided for @openLyricsFileDescription.
  ///
  /// In ja, this message translates to:
  /// **'LRC などの歌詞ファイルを読み込みます'**
  String get openLyricsFileDescription;

  /// No description provided for @exportTimedLyrics.
  ///
  /// In ja, this message translates to:
  /// **'タイムタグ付き歌詞を出力'**
  String get exportTimedLyrics;

  /// No description provided for @exportTimedLyricsDescription.
  ///
  /// In ja, this message translates to:
  /// **'編集中の歌詞を LRC 形式で保存します'**
  String get exportTimedLyricsDescription;

  /// No description provided for @license.
  ///
  /// In ja, this message translates to:
  /// **'ライセンス'**
  String get license;

  /// No description provided for @timingEditor.
  ///
  /// In ja, this message translates to:
  /// **'タイムタグ編集'**
  String get timingEditor;

  /// No description provided for @assExport.
  ///
  /// In ja, this message translates to:
  /// **'ASS 出力'**
  String get assExport;

  /// No description provided for @assetLibrary.
  ///
  /// In ja, this message translates to:
  /// **'素材ライブラリ'**
  String get assetLibrary;

  /// No description provided for @fontLibrary.
  ///
  /// In ja, this message translates to:
  /// **'フォントライブラリ'**
  String get fontLibrary;

  /// No description provided for @aboutApp.
  ///
  /// In ja, this message translates to:
  /// **'アプリ情報'**
  String get aboutApp;

  /// No description provided for @versionAndBuild.
  ///
  /// In ja, this message translates to:
  /// **'バージョン {version}（ビルド {buildNumber}）'**
  String versionAndBuild(Object version, Object buildNumber);

  /// No description provided for @toggleTextEditMode.
  ///
  /// In ja, this message translates to:
  /// **'テキスト編集モードを切り替え'**
  String get toggleTextEditMode;

  /// No description provided for @previewLoadFailed.
  ///
  /// In ja, this message translates to:
  /// **'プレビューの読み込みに失敗しました：{error}'**
  String previewLoadFailed(Object error);

  /// No description provided for @subtitleRenderWarnings.
  ///
  /// In ja, this message translates to:
  /// **'字幕描画の警告・エラー'**
  String get subtitleRenderWarnings;

  /// No description provided for @playingAtDoubleSpeed.
  ///
  /// In ja, this message translates to:
  /// **'2 倍速で再生中'**
  String get playingAtDoubleSpeed;

  /// No description provided for @warningErrorCount.
  ///
  /// In ja, this message translates to:
  /// **'警告・エラー {count} 件'**
  String warningErrorCount(Object count);

  /// No description provided for @singerName.
  ///
  /// In ja, this message translates to:
  /// **'歌手名'**
  String get singerName;

  /// No description provided for @addSingerIcon.
  ///
  /// In ja, this message translates to:
  /// **'歌手アイコンを追加'**
  String get addSingerIcon;

  /// No description provided for @replaceExistingIcon.
  ///
  /// In ja, this message translates to:
  /// **'既存のアイコンを置き換える'**
  String get replaceExistingIcon;

  /// No description provided for @replaceSingerIconQuestion.
  ///
  /// In ja, this message translates to:
  /// **'「{name}」には既にアイコンがあります。置き換えますか？'**
  String replaceSingerIconQuestion(Object name);

  /// No description provided for @replace.
  ///
  /// In ja, this message translates to:
  /// **'置き換える'**
  String get replace;

  /// No description provided for @singerIconSaved.
  ///
  /// In ja, this message translates to:
  /// **'歌手アイコンを保存しました'**
  String get singerIconSaved;

  /// No description provided for @renameSinger.
  ///
  /// In ja, this message translates to:
  /// **'歌手名を変更'**
  String get renameSinger;

  /// No description provided for @singerRenamed.
  ///
  /// In ja, this message translates to:
  /// **'歌手名を変更しました'**
  String get singerRenamed;

  /// No description provided for @deleteSingerIcon.
  ///
  /// In ja, this message translates to:
  /// **'歌手アイコンを削除'**
  String get deleteSingerIcon;

  /// No description provided for @deleteSingerIconQuestion.
  ///
  /// In ja, this message translates to:
  /// **'「{name}」のアイコンを削除しますか？'**
  String deleteSingerIconQuestion(Object name);

  /// No description provided for @singerIconDeleted.
  ///
  /// In ja, this message translates to:
  /// **'歌手アイコンを削除しました'**
  String get singerIconDeleted;

  /// No description provided for @operationFailed.
  ///
  /// In ja, this message translates to:
  /// **'操作に失敗しました：{error}'**
  String operationFailed(Object error);

  /// No description provided for @addImage.
  ///
  /// In ja, this message translates to:
  /// **'画像を追加'**
  String get addImage;

  /// No description provided for @singerIconConflicts.
  ///
  /// In ja, this message translates to:
  /// **'同名ファイルの競合が {count} 件あります。歌手ごとに画像を1ファイルだけ残し、素材フォルダーを整理してから更新してください。'**
  String singerIconConflicts(Object count);

  /// No description provided for @noSingerIcons.
  ///
  /// In ja, this message translates to:
  /// **'歌手アイコンはまだ登録されていません'**
  String get noSingerIcons;

  /// No description provided for @renameSingerTooltip.
  ///
  /// In ja, this message translates to:
  /// **'歌手名を変更'**
  String get renameSingerTooltip;

  /// No description provided for @openMediaPrompt.
  ///
  /// In ja, this message translates to:
  /// **'メディアファイルを開いてください。'**
  String get openMediaPrompt;

  /// No description provided for @lyricsInputHint.
  ///
  /// In ja, this message translates to:
  /// **'歌詞を入力してください'**
  String get lyricsInputHint;

  /// No description provided for @lyricsEmptyPrompt.
  ///
  /// In ja, this message translates to:
  /// **'歌詞ファイルを開くか、テキスト編集モードで歌詞を入力してください。'**
  String get lyricsEmptyPrompt;

  /// No description provided for @playPause.
  ///
  /// In ja, this message translates to:
  /// **'再生／一時停止'**
  String get playPause;

  /// No description provided for @stopTagging.
  ///
  /// In ja, this message translates to:
  /// **'タグ打ちを終了'**
  String get stopTagging;

  /// No description provided for @startTagging.
  ///
  /// In ja, this message translates to:
  /// **'タグ打ちを開始'**
  String get startTagging;

  /// No description provided for @addCheck.
  ///
  /// In ja, this message translates to:
  /// **'チェックを追加'**
  String get addCheck;

  /// No description provided for @removeCheck.
  ///
  /// In ja, this message translates to:
  /// **'チェックを削除'**
  String get removeCheck;

  /// No description provided for @mergeNextCharacter.
  ///
  /// In ja, this message translates to:
  /// **'次の文字と結合'**
  String get mergeNextCharacter;

  /// No description provided for @splitCharacter.
  ///
  /// In ja, this message translates to:
  /// **'文字を分割'**
  String get splitCharacter;

  /// No description provided for @toggleKeyUpCheck.
  ///
  /// In ja, this message translates to:
  /// **'キーアップチェックを追加／削除'**
  String get toggleKeyUpCheck;

  /// No description provided for @autoRubyAndChecks.
  ///
  /// In ja, this message translates to:
  /// **'自動ルビ・チェック付加'**
  String get autoRubyAndChecks;

  /// No description provided for @seekBackOnePointFiveSeconds.
  ///
  /// In ja, this message translates to:
  /// **'1.5 秒戻る'**
  String get seekBackOnePointFiveSeconds;

  /// No description provided for @seekForwardOneSecond.
  ///
  /// In ja, this message translates to:
  /// **'1 秒進む'**
  String get seekForwardOneSecond;

  /// No description provided for @taggingOffset.
  ///
  /// In ja, this message translates to:
  /// **'タイムタグ入力オフセット'**
  String get taggingOffset;

  /// No description provided for @confirmBulkAdjustment.
  ///
  /// In ja, this message translates to:
  /// **'一括調整を確定'**
  String get confirmBulkAdjustment;

  /// No description provided for @bulkAdjustTimeTags.
  ///
  /// In ja, this message translates to:
  /// **'タイムタグ一括調整'**
  String get bulkAdjustTimeTags;

  /// No description provided for @playbackSpeed.
  ///
  /// In ja, this message translates to:
  /// **'再生速度'**
  String get playbackSpeed;

  /// No description provided for @rubyLabel.
  ///
  /// In ja, this message translates to:
  /// **'ルビ：'**
  String get rubyLabel;

  /// No description provided for @rubyInputHint.
  ///
  /// In ja, this message translates to:
  /// **'ルビを入力（例：こう）'**
  String get rubyInputHint;

  /// No description provided for @advanceInputTime.
  ///
  /// In ja, this message translates to:
  /// **'入力時刻を {offset} ms早める'**
  String advanceInputTime(Object offset);

  /// No description provided for @delayInputTime.
  ///
  /// In ja, this message translates to:
  /// **'入力時刻を {offset} ms遅らせる'**
  String delayInputTime(Object offset);

  /// No description provided for @offsetHelp.
  ///
  /// In ja, this message translates to:
  /// **'操作時の反応遅延を補正します\n初期値：-230 ms'**
  String get offsetHelp;

  /// No description provided for @preparing.
  ///
  /// In ja, this message translates to:
  /// **'準備中…'**
  String get preparing;

  /// No description provided for @fetchingRubyProgress.
  ///
  /// In ja, this message translates to:
  /// **'ルビを取得中…（{current}／{total}）'**
  String fetchingRubyProgress(Object current, Object total);

  /// No description provided for @updatingLyrics.
  ///
  /// In ja, this message translates to:
  /// **'歌詞を更新中…'**
  String get updatingLyrics;

  /// No description provided for @stop.
  ///
  /// In ja, this message translates to:
  /// **'中止'**
  String get stop;

  /// No description provided for @autoRubyCancelled.
  ///
  /// In ja, this message translates to:
  /// **'ルビ振りを中止しました。完了済みの内容は保持されます。'**
  String get autoRubyCancelled;

  /// No description provided for @autoRubyCompleted.
  ///
  /// In ja, this message translates to:
  /// **'自動ルビ・チェック付加が完了しました。'**
  String get autoRubyCompleted;

  /// No description provided for @colors.
  ///
  /// In ja, this message translates to:
  /// **'配色'**
  String get colors;

  /// No description provided for @defaultColors.
  ///
  /// In ja, this message translates to:
  /// **'デフォルト配色'**
  String get defaultColors;

  /// No description provided for @importAction.
  ///
  /// In ja, this message translates to:
  /// **'インポート'**
  String get importAction;

  /// No description provided for @addSinger.
  ///
  /// In ja, this message translates to:
  /// **'歌手を追加'**
  String get addSinger;

  /// No description provided for @textSettings.
  ///
  /// In ja, this message translates to:
  /// **'文字'**
  String get textSettings;

  /// No description provided for @bold.
  ///
  /// In ja, this message translates to:
  /// **'太字'**
  String get bold;

  /// No description provided for @textStyle.
  ///
  /// In ja, this message translates to:
  /// **'文字スタイル'**
  String get textStyle;

  /// No description provided for @textStyleSummary.
  ///
  /// In ja, this message translates to:
  /// **'{fontSize} px · {letterSpacing} · 飾り {decorationWidth} px'**
  String textStyleSummary(
    Object fontSize,
    Object letterSpacing,
    Object decorationWidth,
  );

  /// No description provided for @blur.
  ///
  /// In ja, this message translates to:
  /// **'ブラーレベル'**
  String get blur;

  /// No description provided for @screenSettings.
  ///
  /// In ja, this message translates to:
  /// **'画面'**
  String get screenSettings;

  /// No description provided for @horizontalMargin.
  ///
  /// In ja, this message translates to:
  /// **'左右余白'**
  String get horizontalMargin;

  /// No description provided for @interludeCountdown.
  ///
  /// In ja, this message translates to:
  /// **'間奏カウントダウン'**
  String get interludeCountdown;

  /// No description provided for @showLinePrefix.
  ///
  /// In ja, this message translates to:
  /// **'行頭文字を表示'**
  String get showLinePrefix;

  /// No description provided for @font.
  ///
  /// In ja, this message translates to:
  /// **'フォント'**
  String get font;

  /// No description provided for @resetBuiltInFont.
  ///
  /// In ja, this message translates to:
  /// **'内蔵フォントに戻す'**
  String get resetBuiltInFont;

  /// No description provided for @chooseFont.
  ///
  /// In ja, this message translates to:
  /// **'フォントを選択'**
  String get chooseFont;

  /// No description provided for @importFont.
  ///
  /// In ja, this message translates to:
  /// **'フォントを追加'**
  String get importFont;

  /// No description provided for @manageFonts.
  ///
  /// In ja, this message translates to:
  /// **'フォントを管理'**
  String get manageFonts;

  /// No description provided for @replaceExistingFont.
  ///
  /// In ja, this message translates to:
  /// **'既存のフォントを置き換える'**
  String get replaceExistingFont;

  /// No description provided for @replaceFontQuestion.
  ///
  /// In ja, this message translates to:
  /// **'「{name}」は既に登録されています。置き換えますか？'**
  String replaceFontQuestion(Object name);

  /// No description provided for @fontImported.
  ///
  /// In ja, this message translates to:
  /// **'フォントを追加しました'**
  String get fontImported;

  /// No description provided for @deleteFont.
  ///
  /// In ja, this message translates to:
  /// **'フォントを削除'**
  String get deleteFont;

  /// No description provided for @deleteFontQuestion.
  ///
  /// In ja, this message translates to:
  /// **'「{name}」をフォントライブラリから削除しますか？'**
  String deleteFontQuestion(Object name);

  /// No description provided for @fontDeleted.
  ///
  /// In ja, this message translates to:
  /// **'フォントを削除しました'**
  String get fontDeleted;

  /// No description provided for @fontFaces.
  ///
  /// In ja, this message translates to:
  /// **'フォントフェイス'**
  String get fontFaces;

  /// No description provided for @invalidFontFiles.
  ///
  /// In ja, this message translates to:
  /// **'読み込めないフォントファイルが {count} 件あります。ファイルを確認してから更新してください。'**
  String invalidFontFiles(Object count);

  /// No description provided for @noImportedFonts.
  ///
  /// In ja, this message translates to:
  /// **'追加済みのフォントはありません'**
  String get noImportedFonts;

  /// No description provided for @fontFileSummary.
  ///
  /// In ja, this message translates to:
  /// **'{fileName} ・ {count} フェイス ・ {size}'**
  String fontFileSummary(Object fileName, Object count, Object size);

  /// No description provided for @fontWithFaceCount.
  ///
  /// In ja, this message translates to:
  /// **'{fileName} ・ {count} フェイス'**
  String fontWithFaceCount(Object fileName, Object count);

  /// No description provided for @fontFace.
  ///
  /// In ja, this message translates to:
  /// **'フェイス'**
  String get fontFace;

  /// No description provided for @builtInFont.
  ///
  /// In ja, this message translates to:
  /// **'内蔵フォント'**
  String get builtInFont;

  /// No description provided for @subtitleLayout.
  ///
  /// In ja, this message translates to:
  /// **'字幕配置'**
  String get subtitleLayout;

  /// No description provided for @alternatingTwoLines.
  ///
  /// In ja, this message translates to:
  /// **'2 行交互表示（左上／右下）'**
  String get alternatingTwoLines;

  /// No description provided for @paragraphsByBlankLine.
  ///
  /// In ja, this message translates to:
  /// **'空行ごとに段落分け'**
  String get paragraphsByBlankLine;

  /// No description provided for @outputResolution.
  ///
  /// In ja, this message translates to:
  /// **'字幕解像度'**
  String get outputResolution;

  /// No description provided for @heightPixels.
  ///
  /// In ja, this message translates to:
  /// **'高さ (px)'**
  String get heightPixels;

  /// No description provided for @widthPixels.
  ///
  /// In ja, this message translates to:
  /// **'幅 (px)'**
  String get widthPixels;

  /// No description provided for @resetSourceResolution.
  ///
  /// In ja, this message translates to:
  /// **'字幕解像度を元動画に合わせる'**
  String get resetSourceResolution;

  /// No description provided for @secondsValue.
  ///
  /// In ja, this message translates to:
  /// **'{value} 秒'**
  String secondsValue(Object value);

  /// No description provided for @singerColorsTitle.
  ///
  /// In ja, this message translates to:
  /// **'{singer}の配色'**
  String singerColorsTitle(Object singer);

  /// No description provided for @colorPreset.
  ///
  /// In ja, this message translates to:
  /// **'配色プリセット'**
  String get colorPreset;

  /// No description provided for @sample.
  ///
  /// In ja, this message translates to:
  /// **'サンプル'**
  String get sample;

  /// No description provided for @sungColors.
  ///
  /// In ja, this message translates to:
  /// **'歌唱済みの配色'**
  String get sungColors;

  /// No description provided for @unsungColors.
  ///
  /// In ja, this message translates to:
  /// **'未歌唱の配色'**
  String get unsungColors;

  /// No description provided for @textColor.
  ///
  /// In ja, this message translates to:
  /// **'文字色'**
  String get textColor;

  /// No description provided for @outlineColor.
  ///
  /// In ja, this message translates to:
  /// **'縁取り色'**
  String get outlineColor;

  /// No description provided for @decorationColor.
  ///
  /// In ja, this message translates to:
  /// **'飾り色'**
  String get decorationColor;

  /// No description provided for @chooseItem.
  ///
  /// In ja, this message translates to:
  /// **'{item}を選択'**
  String chooseItem(Object item);

  /// No description provided for @chooseColor.
  ///
  /// In ja, this message translates to:
  /// **'色を選択'**
  String get chooseColor;

  /// No description provided for @previewFontPreparationFailed.
  ///
  /// In ja, this message translates to:
  /// **'プレビュー用フォントの準備に失敗しました：{error}'**
  String previewFontPreparationFailed(Object error);

  /// No description provided for @exportAssSubtitle.
  ///
  /// In ja, this message translates to:
  /// **'ASS 字幕を出力'**
  String get exportAssSubtitle;

  /// No description provided for @exportAssSubtitleDescription.
  ///
  /// In ja, this message translates to:
  /// **'ASS 字幕ファイル（.ass）を保存します'**
  String get exportAssSubtitleDescription;

  /// No description provided for @exportHardsubVideo.
  ///
  /// In ja, this message translates to:
  /// **'字幕付き動画を出力'**
  String get exportHardsubVideo;

  /// No description provided for @exportHardsubVideoDescription.
  ///
  /// In ja, this message translates to:
  /// **'字幕を動画に焼き付けて保存します'**
  String get exportHardsubVideoDescription;

  /// No description provided for @exportHardsubVideoUnavailable.
  ///
  /// In ja, this message translates to:
  /// **'動画を読み込んだ場合のみ利用できます'**
  String get exportHardsubVideoUnavailable;

  /// No description provided for @fontParseFailed.
  ///
  /// In ja, this message translates to:
  /// **'フォントの解析に失敗しました：{error}'**
  String fontParseFailed(Object error);

  /// No description provided for @fontFaceLoadFailed.
  ///
  /// In ja, this message translates to:
  /// **'フォントフェイスの読み込みに失敗しました：{error}'**
  String fontFaceLoadFailed(Object error);

  /// No description provided for @linePrefix.
  ///
  /// In ja, this message translates to:
  /// **'行頭文字'**
  String get linePrefix;

  /// No description provided for @editColors.
  ///
  /// In ja, this message translates to:
  /// **'配色を編集'**
  String get editColors;

  /// No description provided for @singerColorImport.
  ///
  /// In ja, this message translates to:
  /// **'歌手配色インポート'**
  String get singerColorImport;

  /// No description provided for @currentSingerColorMarkdown.
  ///
  /// In ja, this message translates to:
  /// **'現在の歌手配色 Markdown ソース'**
  String get currentSingerColorMarkdown;

  /// No description provided for @sourceCode.
  ///
  /// In ja, this message translates to:
  /// **'ソース'**
  String get sourceCode;

  /// No description provided for @currentSingerColorMarkdownApplied.
  ///
  /// In ja, this message translates to:
  /// **'{count} 名の歌手に Markdown 配色を適用しました'**
  String currentSingerColorMarkdownApplied(Object count);

  /// No description provided for @importN3Project.
  ///
  /// In ja, this message translates to:
  /// **'N3 プロジェクトを読み込む'**
  String get importN3Project;

  /// No description provided for @importN3ProjectDescription.
  ///
  /// In ja, this message translates to:
  /// **'N3 プロジェクトから配色スタイルを読み込みます'**
  String get importN3ProjectDescription;

  /// No description provided for @onlineColorEditor.
  ///
  /// In ja, this message translates to:
  /// **'オンライン配色エディター'**
  String get onlineColorEditor;

  /// No description provided for @n3ColorImportLoaded.
  ///
  /// In ja, this message translates to:
  /// **'N3 配色 {count} 件を読み込みました（縁取り 2 色は除外）'**
  String n3ColorImportLoaded(Object count);

  /// No description provided for @n3ColorImportFailed.
  ///
  /// In ja, this message translates to:
  /// **'N3 プロジェクトの読み込みに失敗しました：{error}'**
  String n3ColorImportFailed(Object error);

  /// No description provided for @singerColorImportCompleted.
  ///
  /// In ja, this message translates to:
  /// **'インポート完了：更新 {updated} 件、追加 {added} 件、スキップ {skipped} 行'**
  String singerColorImportCompleted(
    Object updated,
    Object added,
    Object skipped,
  );

  /// No description provided for @singerColorImportCompletedWithDuplicates.
  ///
  /// In ja, this message translates to:
  /// **'インポート完了：更新 {updated} 件、追加 {added} 件、スキップ {skipped} 行、テキスト内の同名データ {duplicates} 行を後の内容で上書き'**
  String singerColorImportCompletedWithDuplicates(
    Object updated,
    Object added,
    Object skipped,
    Object duplicates,
  );

  /// No description provided for @singerColorImportHelp.
  ///
  /// In ja, this message translates to:
  /// **'1行に歌手名と6色を記述し、Tab（推奨）または | で区切ります。\n単色は #RRGGBB、グラデーションは #上側の色/#下側の色 で指定します。見出し行は省略できます。'**
  String get singerColorImportHelp;

  /// No description provided for @singerColorExample.
  ///
  /// In ja, this message translates to:
  /// **'歌手名\t歌唱済み文字色\t歌唱済み縁取り色\t歌唱済み飾り色\t未歌唱文字色\t未歌唱縁取り色\t未歌唱飾り色\nラケナリア\t#0572A4/#052951\t#FFFFFF\t#E1E196\t#DCF0FC\t#43464A\t#E19696'**
  String get singerColorExample;

  /// No description provided for @singerColorImportSplitError.
  ///
  /// In ja, this message translates to:
  /// **'{line} 行目：Tab または | で7列に区切ってください'**
  String singerColorImportSplitError(Object line);

  /// No description provided for @singerColorImportColumnCountError.
  ///
  /// In ja, this message translates to:
  /// **'{line} 行目：7列必要ですが、{count}列あります'**
  String singerColorImportColumnCountError(Object line, Object count);

  /// No description provided for @singerColorImportSingerRequired.
  ///
  /// In ja, this message translates to:
  /// **'{line} 行目：歌手名を入力してください'**
  String singerColorImportSingerRequired(Object line);

  /// No description provided for @singerColorImportInvalidColor.
  ///
  /// In ja, this message translates to:
  /// **'{line} 行目：{colorName}「{value}」の形式が正しくありません'**
  String singerColorImportInvalidColor(
    Object line,
    Object colorName,
    Object value,
  );

  /// No description provided for @sungTextColor.
  ///
  /// In ja, this message translates to:
  /// **'歌唱済み文字色'**
  String get sungTextColor;

  /// No description provided for @sungOutlineColor.
  ///
  /// In ja, this message translates to:
  /// **'歌唱済み縁取り色'**
  String get sungOutlineColor;

  /// No description provided for @sungDecorationColor.
  ///
  /// In ja, this message translates to:
  /// **'歌唱済み飾り色'**
  String get sungDecorationColor;

  /// No description provided for @unsungTextColor.
  ///
  /// In ja, this message translates to:
  /// **'未歌唱文字色'**
  String get unsungTextColor;

  /// No description provided for @unsungOutlineColor.
  ///
  /// In ja, this message translates to:
  /// **'未歌唱縁取り色'**
  String get unsungOutlineColor;

  /// No description provided for @unsungDecorationColor.
  ///
  /// In ja, this message translates to:
  /// **'未歌唱飾り色'**
  String get unsungDecorationColor;

  /// No description provided for @copy.
  ///
  /// In ja, this message translates to:
  /// **'コピー'**
  String get copy;

  /// No description provided for @copiedToClipboard.
  ///
  /// In ja, this message translates to:
  /// **'クリップボードにコピーしました'**
  String get copiedToClipboard;

  /// No description provided for @paste.
  ///
  /// In ja, this message translates to:
  /// **'貼り付け'**
  String get paste;

  /// No description provided for @singerColorInputHint.
  ///
  /// In ja, this message translates to:
  /// **'ここに配色テキストを貼り付けます'**
  String get singerColorInputHint;

  /// No description provided for @singerColorImportSummary.
  ///
  /// In ja, this message translates to:
  /// **'有効 {valid} 行、歌手 {singers} 名、同名上書き {duplicates} 行、スキップ {skipped} 行'**
  String singerColorImportSummary(
    Object valid,
    Object singers,
    Object duplicates,
    Object skipped,
  );

  /// No description provided for @singerColorInputEmpty.
  ///
  /// In ja, this message translates to:
  /// **'配色テキストが入力されていません'**
  String get singerColorInputEmpty;

  /// No description provided for @importValidRows.
  ///
  /// In ja, this message translates to:
  /// **'インポート'**
  String get importValidRows;

  /// No description provided for @resetDefaults.
  ///
  /// In ja, this message translates to:
  /// **'デフォルトに戻す'**
  String get resetDefaults;

  /// No description provided for @showSingerIcon.
  ///
  /// In ja, this message translates to:
  /// **'歌手アイコンを表示'**
  String get showSingerIcon;

  /// No description provided for @fontSize.
  ///
  /// In ja, this message translates to:
  /// **'フォントサイズ'**
  String get fontSize;

  /// No description provided for @letterSpacing.
  ///
  /// In ja, this message translates to:
  /// **'文字間隔'**
  String get letterSpacing;

  /// No description provided for @decorationWidth.
  ///
  /// In ja, this message translates to:
  /// **'飾りの幅'**
  String get decorationWidth;

  /// No description provided for @textOutlineWidth.
  ///
  /// In ja, this message translates to:
  /// **'文字の縁取り幅'**
  String get textOutlineWidth;

  /// No description provided for @furiganaSize.
  ///
  /// In ja, this message translates to:
  /// **'振り仮名サイズ'**
  String get furiganaSize;

  /// No description provided for @furiganaOutlineWidth.
  ///
  /// In ja, this message translates to:
  /// **'振り仮名の縁取り幅'**
  String get furiganaOutlineWidth;

  /// No description provided for @furiganaTextGap.
  ///
  /// In ja, this message translates to:
  /// **'振り仮名と本文の間隔'**
  String get furiganaTextGap;

  /// No description provided for @lineSpacing.
  ///
  /// In ja, this message translates to:
  /// **'行間隔'**
  String get lineSpacing;

  /// No description provided for @subtitleBottomMargin.
  ///
  /// In ja, this message translates to:
  /// **'字幕と画面下端の余白'**
  String get subtitleBottomMargin;

  /// No description provided for @singerIconSize.
  ///
  /// In ja, this message translates to:
  /// **'歌手アイコンサイズ'**
  String get singerIconSize;

  /// No description provided for @lyricsIconGap.
  ///
  /// In ja, this message translates to:
  /// **'歌詞とアイコンの間隔'**
  String get lyricsIconGap;

  /// No description provided for @solidColor.
  ///
  /// In ja, this message translates to:
  /// **'単色'**
  String get solidColor;

  /// No description provided for @gradient.
  ///
  /// In ja, this message translates to:
  /// **'グラデーション'**
  String get gradient;

  /// No description provided for @gradientTop.
  ///
  /// In ja, this message translates to:
  /// **'上（0%）'**
  String get gradientTop;

  /// No description provided for @gradientBottom.
  ///
  /// In ja, this message translates to:
  /// **'下（100%）'**
  String get gradientBottom;

  /// No description provided for @hexColorCode.
  ///
  /// In ja, this message translates to:
  /// **'16 進カラーコード'**
  String get hexColorCode;

  /// No description provided for @preset.
  ///
  /// In ja, this message translates to:
  /// **'プリセット'**
  String get preset;

  /// No description provided for @noPreset.
  ///
  /// In ja, this message translates to:
  /// **'プリセットなし'**
  String get noPreset;

  /// No description provided for @blueColors.
  ///
  /// In ja, this message translates to:
  /// **'青配色'**
  String get blueColors;

  /// No description provided for @standardColors.
  ///
  /// In ja, this message translates to:
  /// **'標準配色'**
  String get standardColors;

  /// No description provided for @chorusColors.
  ///
  /// In ja, this message translates to:
  /// **'コーラス配色'**
  String get chorusColors;

  /// No description provided for @blueColors2.
  ///
  /// In ja, this message translates to:
  /// **'青配色2'**
  String get blueColors2;

  /// No description provided for @purple.
  ///
  /// In ja, this message translates to:
  /// **'紫'**
  String get purple;

  /// No description provided for @bluePurple.
  ///
  /// In ja, this message translates to:
  /// **'青紫混'**
  String get bluePurple;

  /// No description provided for @kusou.
  ///
  /// In ja, this message translates to:
  /// **'空爽'**
  String get kusou;

  /// No description provided for @fontFacesNotFound.
  ///
  /// In ja, this message translates to:
  /// **'フォントフェイスが見つかりません。'**
  String get fontFacesNotFound;

  /// No description provided for @enableHapticFeedback.
  ///
  /// In ja, this message translates to:
  /// **'振動フィードバックを有効にする'**
  String get enableHapticFeedback;

  /// No description provided for @disableHapticFeedback.
  ///
  /// In ja, this message translates to:
  /// **'振動フィードバックを無効にする'**
  String get disableHapticFeedback;

  /// No description provided for @saveColorPreset.
  ///
  /// In ja, this message translates to:
  /// **'現在の配色を保存'**
  String get saveColorPreset;

  /// No description provided for @colorPresetName.
  ///
  /// In ja, this message translates to:
  /// **'プリセット名'**
  String get colorPresetName;

  /// No description provided for @colorPresetSaved.
  ///
  /// In ja, this message translates to:
  /// **'配色プリセット「{name}」を保存しました'**
  String colorPresetSaved(Object name);

  /// No description provided for @savedColorPresets.
  ///
  /// In ja, this message translates to:
  /// **'保存済み配色'**
  String get savedColorPresets;

  /// No description provided for @importSavedColorPresets.
  ///
  /// In ja, this message translates to:
  /// **'配色スタイルをインポート'**
  String get importSavedColorPresets;

  /// No description provided for @importSavedColorPresetsDescription.
  ///
  /// In ja, this message translates to:
  /// **'テキストから保存済み配色を追加・更新します'**
  String get importSavedColorPresetsDescription;

  /// No description provided for @noSavedColorPresetLibrary.
  ///
  /// In ja, this message translates to:
  /// **'保存済みの配色はありません'**
  String get noSavedColorPresetLibrary;

  /// No description provided for @addToCurrentSingerColors.
  ///
  /// In ja, this message translates to:
  /// **'追加'**
  String get addToCurrentSingerColors;

  /// No description provided for @moreActions.
  ///
  /// In ja, this message translates to:
  /// **'その他の操作'**
  String get moreActions;

  /// No description provided for @renameColorPreset.
  ///
  /// In ja, this message translates to:
  /// **'配色名を変更'**
  String get renameColorPreset;

  /// No description provided for @deleteColorPreset.
  ///
  /// In ja, this message translates to:
  /// **'保存済み配色を削除'**
  String get deleteColorPreset;

  /// No description provided for @deleteColorPresetQuestion.
  ///
  /// In ja, this message translates to:
  /// **'保存済み配色「{name}」を削除しますか？現在の ASS 設定に追加済みの歌手配色は削除されません。'**
  String deleteColorPresetQuestion(Object name);

  /// No description provided for @colorPresetDeleted.
  ///
  /// In ja, this message translates to:
  /// **'配色「{name}」を削除しました'**
  String colorPresetDeleted(Object name);

  /// No description provided for @colorPresetRenamed.
  ///
  /// In ja, this message translates to:
  /// **'配色名を「{name}」に変更しました'**
  String colorPresetRenamed(Object name);

  /// No description provided for @replaceCurrentSingerColorTitle.
  ///
  /// In ja, this message translates to:
  /// **'現在の歌手配色を置換'**
  String get replaceCurrentSingerColorTitle;

  /// No description provided for @replaceCurrentSingerColorQuestion.
  ///
  /// In ja, this message translates to:
  /// **'現在の歌手配色に「{name}」が既にあります。保存済みの配色で置き換えますか？'**
  String replaceCurrentSingerColorQuestion(Object name);

  /// No description provided for @colorPresetAddedToCurrent.
  ///
  /// In ja, this message translates to:
  /// **'「{name}」を現在の歌手配色に追加しました'**
  String colorPresetAddedToCurrent(Object name);

  /// No description provided for @currentSingerColorReplaced.
  ///
  /// In ja, this message translates to:
  /// **'現在の歌手配色「{name}」を置き換えました'**
  String currentSingerColorReplaced(Object name);

  /// No description provided for @colorPresetNameRequired.
  ///
  /// In ja, this message translates to:
  /// **'プリセット名を入力してください'**
  String get colorPresetNameRequired;

  /// No description provided for @colorPresetNameInvalid.
  ///
  /// In ja, this message translates to:
  /// **'プリセット名に「|」や改行は使用できません'**
  String get colorPresetNameInvalid;

  /// No description provided for @lineColoring.
  ///
  /// In ja, this message translates to:
  /// **'行ごとの配色'**
  String get lineColoring;

  /// No description provided for @closeLineColoring.
  ///
  /// In ja, this message translates to:
  /// **'行ごとの配色を閉じる'**
  String get closeLineColoring;

  /// No description provided for @noSavedColorPresets.
  ///
  /// In ja, this message translates to:
  /// **'ASS 出力画面に読み込まれた配色がありません'**
  String get noSavedColorPresets;

  /// No description provided for @applyLineColor.
  ///
  /// In ja, this message translates to:
  /// **'選択位置の歌手マーカーを「{name}」に切り替え'**
  String applyLineColor(Object name);

  /// No description provided for @selectLyricLineFirst.
  ///
  /// In ja, this message translates to:
  /// **'先に歌詞の文字を選択してください'**
  String get selectLyricLineFirst;

  /// No description provided for @lineColoringFailed.
  ///
  /// In ja, this message translates to:
  /// **'選択文字の前に行頭文字を挿入できませんでした'**
  String get lineColoringFailed;

  /// No description provided for @escapePod.
  ///
  /// In ja, this message translates to:
  /// **'エスケープポッド'**
  String get escapePod;

  /// No description provided for @escapePodDescription.
  ///
  /// In ja, this message translates to:
  /// **'フォント、歌手アイコン、配色を、他のプラットフォームでも復元できる ZIP にまとめます。'**
  String get escapePodDescription;

  /// No description provided for @exportEscapePod.
  ///
  /// In ja, this message translates to:
  /// **'エスケープポッドを出力'**
  String get exportEscapePod;

  /// No description provided for @exportEscapePodDescription.
  ///
  /// In ja, this message translates to:
  /// **'現在のライブラリを ZIP ファイルに保存します'**
  String get exportEscapePodDescription;

  /// No description provided for @importEscapePod.
  ///
  /// In ja, this message translates to:
  /// **'エスケープポッドを読み込む'**
  String get importEscapePod;

  /// No description provided for @importEscapePodDescription.
  ///
  /// In ja, this message translates to:
  /// **'同名の項目を更新し、それ以外の項目を追加します'**
  String get importEscapePodDescription;

  /// No description provided for @preparingEscapePod.
  ///
  /// In ja, this message translates to:
  /// **'エスケープポッドを準備しています…'**
  String get preparingEscapePod;

  /// No description provided for @importingEscapePod.
  ///
  /// In ja, this message translates to:
  /// **'エスケープポッドを読み込んでいます…'**
  String get importingEscapePod;

  /// No description provided for @chooseEscapePodSaveLocation.
  ///
  /// In ja, this message translates to:
  /// **'エスケープポッドの保存先を選択'**
  String get chooseEscapePodSaveLocation;

  /// No description provided for @chooseEscapePodFile.
  ///
  /// In ja, this message translates to:
  /// **'エスケープポッドを選択'**
  String get chooseEscapePodFile;

  /// No description provided for @escapePodExported.
  ///
  /// In ja, this message translates to:
  /// **'出力完了：フォント {fonts} 件、アイコン {avatars} 件、配色 {colors} 件'**
  String escapePodExported(Object fonts, Object avatars, Object colors);

  /// No description provided for @escapePodImported.
  ///
  /// In ja, this message translates to:
  /// **'読み込み完了：フォント {fonts} 件、アイコン {avatars} 件、配色 {colors} 件、スキップ {skipped} 件'**
  String escapePodImported(
    Object fonts,
    Object avatars,
    Object colors,
    Object skipped,
  );

  /// No description provided for @escapePodExportFailed.
  ///
  /// In ja, this message translates to:
  /// **'エスケープポッドの出力に失敗しました：{error}'**
  String escapePodExportFailed(Object error);

  /// No description provided for @escapePodImportFailed.
  ///
  /// In ja, this message translates to:
  /// **'エスケープポッドの読み込みに失敗しました：{error}'**
  String escapePodImportFailed(Object error);

  /// No description provided for @lineAlignmentSettings.
  ///
  /// In ja, this message translates to:
  /// **'各行の配置'**
  String get lineAlignmentSettings;

  /// No description provided for @lineAlignmentSettingsDescription.
  ///
  /// In ja, this message translates to:
  /// **'下寄せ 2～4 行の左右位置を設定します'**
  String get lineAlignmentSettingsDescription;

  /// No description provided for @lineAlignmentSettingsHelp.
  ///
  /// In ja, this message translates to:
  /// **'行数ごとに、それぞれの行を左寄せ、中央寄せ、右寄せから選択できます。'**
  String get lineAlignmentSettingsHelp;

  /// No description provided for @bottomAlignedTwoLines.
  ///
  /// In ja, this message translates to:
  /// **'下寄せ 2 行'**
  String get bottomAlignedTwoLines;

  /// No description provided for @bottomAlignedThreeLines.
  ///
  /// In ja, this message translates to:
  /// **'下寄せ 3 行'**
  String get bottomAlignedThreeLines;

  /// No description provided for @bottomAlignedFourLines.
  ///
  /// In ja, this message translates to:
  /// **'下寄せ 4 行'**
  String get bottomAlignedFourLines;

  /// No description provided for @lineNumber.
  ///
  /// In ja, this message translates to:
  /// **'{line} 行目'**
  String lineNumber(Object line);

  /// No description provided for @alignLeft.
  ///
  /// In ja, this message translates to:
  /// **'左'**
  String get alignLeft;

  /// No description provided for @alignCenter.
  ///
  /// In ja, this message translates to:
  /// **'中央'**
  String get alignCenter;

  /// No description provided for @alignRight.
  ///
  /// In ja, this message translates to:
  /// **'右'**
  String get alignRight;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ja', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ja':
      return AppLocalizationsJa();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
