// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppLocalizationsJa extends AppLocalizations {
  AppLocalizationsJa([String locale = 'ja']) : super(locale);

  @override
  String get appTitle => 'yuukilyrics';

  @override
  String get cancel => 'キャンセル';

  @override
  String get apply => '適用';

  @override
  String get close => '閉じる';

  @override
  String get delete => '削除';

  @override
  String get refresh => '更新';

  @override
  String get share => '共有';

  @override
  String get confirm => '決定';

  @override
  String get openNavigationMenu => 'ナビゲーションメニューを開く';

  @override
  String get file => 'ファイル';

  @override
  String get preview => 'プレビュー';

  @override
  String get export => '出力';

  @override
  String get automatic => '自動';

  @override
  String automaticPixels(Object value) {
    return '自動（$value px）';
  }

  @override
  String waveformAnalysisFailed(Object error) {
    return '波形の解析に失敗しました：$error';
  }

  @override
  String get exportFile => 'ファイルを出力';

  @override
  String get fileName => 'ファイル名';

  @override
  String get saveToDevice => 'デバイスに保存';

  @override
  String get emptyLyricsCannotExport => '歌詞が空のため、出力できません。';

  @override
  String timedLyricsShareSubject(Object fileName) {
    return 'タイムタグ付き歌詞：$fileName';
  }

  @override
  String get chooseLyricsSaveLocation => '歌詞ファイルの保存先を選択';

  @override
  String lyricsFileSaved(Object path) {
    return '歌詞ファイルを保存しました：$path';
  }

  @override
  String lyricsExportFailed(Object error) {
    return '歌詞ファイルの出力に失敗しました：$error';
  }

  @override
  String assShareSubject(Object fileName) {
    return 'ASS 字幕：$fileName';
  }

  @override
  String get chooseAssSaveLocation => 'ASS 字幕の保存先を選択';

  @override
  String assSaved(Object path) {
    return 'ASS 字幕を保存しました：$path';
  }

  @override
  String assExportFailed(Object error) {
    return 'ASS 字幕の出力に失敗しました：$error';
  }

  @override
  String get chooseVideoSaveLocation => '動画の保存先を選択';

  @override
  String outputPreparationFailed(Object error) {
    return '出力先を準備できませんでした：$error';
  }

  @override
  String get detectingEncoder => 'エンコーダーを検出中…';

  @override
  String get encodingVideo => '動画をエンコード中…';

  @override
  String get burningSubtitles => '字幕を動画に焼き付けています。しばらくお待ちください。';

  @override
  String encoderName(Object codec) {
    return 'エンコーダー：$codec';
  }

  @override
  String videoSaved(Object path) {
    return '動画を保存しました：$path';
  }

  @override
  String hardsubVideoShareSubject(Object fileName) {
    return '字幕付き動画：$fileName';
  }

  @override
  String get encodingFailed => 'エンコードに失敗しました';

  @override
  String get openMediaFile => 'メディアファイルを開く';

  @override
  String get openMediaFileDescription => 'タイムタグを付ける音声または動画を読み込みます';

  @override
  String get openLyricsFile => '歌詞ファイルを開く';

  @override
  String get openLyricsFileDescription => 'LRC などの歌詞ファイルを読み込みます';

  @override
  String get exportTimedLyrics => 'タイムタグ付き歌詞を出力';

  @override
  String get exportTimedLyricsDescription => '編集中の歌詞を LRC 形式で保存します';

  @override
  String get license => 'ライセンス';

  @override
  String get timingEditor => 'タイムタグ編集';

  @override
  String get assExport => 'ASS 出力';

  @override
  String get assetLibrary => '素材ライブラリ';

  @override
  String get fontLibrary => 'フォントライブラリ';

  @override
  String get aboutApp => 'アプリ情報';

  @override
  String versionAndBuild(Object version, Object buildNumber) {
    return 'バージョン $version（ビルド $buildNumber）';
  }

  @override
  String get toggleTextEditMode => 'テキスト編集モードを切り替え';

  @override
  String previewLoadFailed(Object error) {
    return 'プレビューの読み込みに失敗しました：$error';
  }

  @override
  String get subtitleRenderWarnings => '字幕描画の警告・エラー';

  @override
  String get playingAtDoubleSpeed => '2 倍速で再生中';

  @override
  String warningErrorCount(Object count) {
    return '警告・エラー $count 件';
  }

  @override
  String get singerName => '歌手名';

  @override
  String get addSingerIcon => '歌手アイコンを追加';

  @override
  String get replaceExistingIcon => '既存のアイコンを置き換える';

  @override
  String replaceSingerIconQuestion(Object name) {
    return '「$name」には既にアイコンがあります。置き換えますか？';
  }

  @override
  String get replace => '置き換える';

  @override
  String get singerIconSaved => '歌手アイコンを保存しました';

  @override
  String get renameSinger => '歌手名を変更';

  @override
  String get singerRenamed => '歌手名を変更しました';

  @override
  String get deleteSingerIcon => '歌手アイコンを削除';

  @override
  String deleteSingerIconQuestion(Object name) {
    return '「$name」のアイコンを削除しますか？';
  }

  @override
  String get singerIconDeleted => '歌手アイコンを削除しました';

  @override
  String operationFailed(Object error) {
    return '操作に失敗しました：$error';
  }

  @override
  String get addImage => '画像を追加';

  @override
  String singerIconConflicts(Object count) {
    return '同名ファイルの競合が $count 件あります。歌手ごとに画像を1ファイルだけ残し、素材フォルダーを整理してから更新してください。';
  }

  @override
  String get noSingerIcons => '歌手アイコンはまだ登録されていません';

  @override
  String get renameSingerTooltip => '歌手名を変更';

  @override
  String get openMediaPrompt => 'メディアファイルを開いてください。';

  @override
  String get lyricsInputHint => '歌詞を入力してください';

  @override
  String get lyricsEmptyPrompt => '歌詞ファイルを開くか、テキスト編集モードで歌詞を入力してください。';

  @override
  String get playPause => '再生／一時停止';

  @override
  String get stopTagging => 'タグ打ちを終了';

  @override
  String get startTagging => 'タグ打ちを開始';

  @override
  String get addCheck => 'チェックを追加';

  @override
  String get removeCheck => 'チェックを削除';

  @override
  String get mergeNextCharacter => '次の文字と結合';

  @override
  String get splitCharacter => '文字を分割';

  @override
  String get toggleKeyUpCheck => 'キーアップチェックを追加／削除';

  @override
  String get autoRubyAndChecks => '自動ルビ・チェック付加';

  @override
  String get seekBackOnePointFiveSeconds => '1.5 秒戻る';

  @override
  String get seekForwardOneSecond => '1 秒進む';

  @override
  String get taggingOffset => 'タイムタグ入力オフセット';

  @override
  String get confirmBulkAdjustment => '一括調整を確定';

  @override
  String get bulkAdjustTimeTags => 'タイムタグ一括調整';

  @override
  String get playbackSpeed => '再生速度';

  @override
  String get rubyLabel => 'ルビ：';

  @override
  String get rubyInputHint => 'ルビを入力（例：こう）';

  @override
  String advanceInputTime(Object offset) {
    return '入力時刻を $offset ms早める';
  }

  @override
  String delayInputTime(Object offset) {
    return '入力時刻を $offset ms遅らせる';
  }

  @override
  String get offsetHelp => '操作時の反応遅延を補正します\n初期値：-230 ms';

  @override
  String get preparing => '準備中…';

  @override
  String fetchingRubyProgress(Object current, Object total) {
    return 'ルビを取得中…（$current／$total）';
  }

  @override
  String get updatingLyrics => '歌詞を更新中…';

  @override
  String get stop => '中止';

  @override
  String get autoRubyCancelled => 'ルビ振りを中止しました。完了済みの内容は保持されます。';

  @override
  String get autoRubyCompleted => '自動ルビ・チェック付加が完了しました。';

  @override
  String get colors => '配色';

  @override
  String get defaultColors => 'デフォルト配色';

  @override
  String get importAction => 'インポート';

  @override
  String get addSinger => '歌手を追加';

  @override
  String get textSettings => '文字';

  @override
  String get bold => '太字';

  @override
  String get textStyle => '文字スタイル';

  @override
  String textStyleSummary(
    Object fontSize,
    Object letterSpacing,
    Object decorationWidth,
  ) {
    return '$fontSize px · $letterSpacing · 飾り $decorationWidth px';
  }

  @override
  String get blur => 'ブラー';

  @override
  String get screenSettings => '画面';

  @override
  String get horizontalMargin => '左右余白';

  @override
  String get interludeCountdown => '間奏カウントダウン';

  @override
  String get showLinePrefix => '行頭文字を表示';

  @override
  String get font => 'フォント';

  @override
  String get resetBuiltInFont => '内蔵フォントに戻す';

  @override
  String get chooseFont => 'フォントを選択';

  @override
  String get importFont => 'フォントを追加';

  @override
  String get manageFonts => 'フォントを管理';

  @override
  String get replaceExistingFont => '既存のフォントを置き換える';

  @override
  String replaceFontQuestion(Object name) {
    return '「$name」は既に登録されています。置き換えますか？';
  }

  @override
  String get fontImported => 'フォントを追加しました';

  @override
  String get deleteFont => 'フォントを削除';

  @override
  String deleteFontQuestion(Object name) {
    return '「$name」をフォントライブラリから削除しますか？';
  }

  @override
  String get fontDeleted => 'フォントを削除しました';

  @override
  String get fontFaces => 'フォントフェイス';

  @override
  String invalidFontFiles(Object count) {
    return '読み込めないフォントファイルが $count 件あります。ファイルを確認してから更新してください。';
  }

  @override
  String get noImportedFonts => '追加済みのフォントはありません';

  @override
  String fontFileSummary(Object fileName, Object count, Object size) {
    return '$fileName ・ $count フェイス ・ $size';
  }

  @override
  String fontWithFaceCount(Object fileName, Object count) {
    return '$fileName ・ $count フェイス';
  }

  @override
  String get fontFace => 'フェイス';

  @override
  String get builtInFont => '内蔵フォント';

  @override
  String get subtitleLayout => '字幕配置';

  @override
  String get alternatingTwoLines => '2 行交互表示（左上／右下）';

  @override
  String get paragraphsByBlankLine => '空行ごとに段落分け';

  @override
  String get outputResolution => '出力解像度';

  @override
  String get heightPixels => '高さ (px)';

  @override
  String get widthPixels => '幅 (px)';

  @override
  String get resetSourceResolution => '元動画の解像度に戻す';

  @override
  String secondsValue(Object value) {
    return '$value 秒';
  }

  @override
  String singerColorsTitle(Object singer) {
    return '$singerの配色';
  }

  @override
  String get colorPreset => '配色プリセット';

  @override
  String get sample => 'サンプル';

  @override
  String get sungColors => '歌唱済みの配色';

  @override
  String get unsungColors => '未歌唱の配色';

  @override
  String get textColor => '文字色';

  @override
  String get outlineColor => '縁取り色';

  @override
  String get decorationColor => '飾り色';

  @override
  String chooseItem(Object item) {
    return '$itemを選択';
  }

  @override
  String get chooseColor => '色を選択';

  @override
  String previewFontPreparationFailed(Object error) {
    return 'プレビュー用フォントの準備に失敗しました：$error';
  }

  @override
  String get exportAssSubtitle => 'ASS 字幕を出力';

  @override
  String get exportAssSubtitleDescription => 'ASS 字幕ファイル（.ass）を保存します';

  @override
  String get exportHardsubVideo => '字幕付き動画を出力';

  @override
  String get exportHardsubVideoDescription => '字幕を動画に焼き付けて保存します';

  @override
  String get exportHardsubVideoUnavailable => '動画を読み込んだ場合のみ利用できます';

  @override
  String fontParseFailed(Object error) {
    return 'フォントの解析に失敗しました：$error';
  }

  @override
  String fontFaceLoadFailed(Object error) {
    return 'フォントフェイスの読み込みに失敗しました：$error';
  }

  @override
  String get linePrefix => '行頭文字';

  @override
  String get editColors => '配色を編集';

  @override
  String get singerColorImport => '歌手配色インポート';

  @override
  String get importN3Project => 'N3 プロジェクトを読み込む';

  @override
  String n3ColorImportLoaded(Object count) {
    return 'N3 配色 $count 件を読み込みました（縁取り 2 色は除外）';
  }

  @override
  String n3ColorImportFailed(Object error) {
    return 'N3 プロジェクトの読み込みに失敗しました：$error';
  }

  @override
  String singerColorImportCompleted(
    Object updated,
    Object added,
    Object skipped,
  ) {
    return 'インポート完了：更新 $updated 件、追加 $added 件、スキップ $skipped 行';
  }

  @override
  String singerColorImportCompletedWithDuplicates(
    Object updated,
    Object added,
    Object skipped,
    Object duplicates,
  ) {
    return 'インポート完了：更新 $updated 件、追加 $added 件、スキップ $skipped 行、テキスト内の同名データ $duplicates 行を後の内容で上書き';
  }

  @override
  String get singerColorImportHelp =>
      '1行に歌手名と6色を記述し、Tab（推奨）または | で区切ります。\n単色は #RRGGBB、グラデーションは #上側の色/#下側の色 で指定します。見出し行は省略できます。';

  @override
  String get singerColorExample =>
      '歌手名\t歌唱済み文字色\t歌唱済み縁取り色\t歌唱済み飾り色\t未歌唱文字色\t未歌唱縁取り色\t未歌唱飾り色\nラケナリア\t#0572A4/#052951\t#FFFFFF\t#E1E196\t#DCF0FC\t#43464A\t#E19696';

  @override
  String singerColorImportSplitError(Object line) {
    return '$line 行目：Tab または | で7列に区切ってください';
  }

  @override
  String singerColorImportColumnCountError(Object line, Object count) {
    return '$line 行目：7列必要ですが、$count列あります';
  }

  @override
  String singerColorImportSingerRequired(Object line) {
    return '$line 行目：歌手名を入力してください';
  }

  @override
  String singerColorImportInvalidColor(
    Object line,
    Object colorName,
    Object value,
  ) {
    return '$line 行目：$colorName「$value」の形式が正しくありません';
  }

  @override
  String get sungTextColor => '歌唱済み文字色';

  @override
  String get sungOutlineColor => '歌唱済み縁取り色';

  @override
  String get sungDecorationColor => '歌唱済み飾り色';

  @override
  String get unsungTextColor => '未歌唱文字色';

  @override
  String get unsungOutlineColor => '未歌唱縁取り色';

  @override
  String get unsungDecorationColor => '未歌唱飾り色';

  @override
  String get paste => '貼り付け';

  @override
  String get singerColorInputHint => 'ここに配色テキストを貼り付けます';

  @override
  String singerColorImportSummary(
    Object valid,
    Object singers,
    Object duplicates,
    Object skipped,
  ) {
    return '有効 $valid 行、歌手 $singers 名、同名上書き $duplicates 行、スキップ $skipped 行';
  }

  @override
  String get singerColorInputEmpty => '配色テキストが入力されていません';

  @override
  String get importValidRows => 'インポート';

  @override
  String get resetDefaults => 'デフォルトに戻す';

  @override
  String get showSingerIcon => '歌手アイコンを表示';

  @override
  String get fontSize => 'フォントサイズ';

  @override
  String get letterSpacing => '文字間隔';

  @override
  String get decorationWidth => '飾りの幅';

  @override
  String get textOutlineWidth => '文字の縁取り幅';

  @override
  String get furiganaSize => '振り仮名サイズ';

  @override
  String get furiganaOutlineWidth => '振り仮名の縁取り幅';

  @override
  String get furiganaTextGap => '振り仮名と本文の間隔';

  @override
  String get lineSpacing => '行間隔';

  @override
  String get subtitleBottomMargin => '字幕と画面下端の余白';

  @override
  String get singerIconSize => '歌手アイコンサイズ';

  @override
  String get lyricsIconGap => '歌詞とアイコンの間隔';

  @override
  String get solidColor => '単色';

  @override
  String get gradient => 'グラデーション';

  @override
  String get gradientTop => '上（0%）';

  @override
  String get gradientBottom => '下（100%）';

  @override
  String get hexColorCode => '16 進カラーコード';

  @override
  String get preset => 'プリセット';

  @override
  String get noPreset => 'プリセットなし';

  @override
  String get blueColors => '青配色';

  @override
  String get standardColors => '標準配色';

  @override
  String get chorusColors => 'コーラス配色';

  @override
  String get blueColors2 => '青配色2';

  @override
  String get purple => '紫';

  @override
  String get bluePurple => '青紫混';

  @override
  String get kusou => '空爽';

  @override
  String get fontFacesNotFound => 'フォントフェイスが見つかりません。';

  @override
  String get enableHapticFeedback => '振動フィードバックを有効にする';

  @override
  String get disableHapticFeedback => '振動フィードバックを無効にする';

  @override
  String get saveColorPreset => '現在の配色を保存';

  @override
  String get colorPresetName => 'プリセット名';

  @override
  String colorPresetSaved(Object name) {
    return '配色プリセット「$name」を保存しました';
  }

  @override
  String get savedColorPresets => '保存済み配色';

  @override
  String get noSavedColorPresetLibrary => '保存済みの配色はありません';

  @override
  String get addToCurrentSingerColors => '追加';

  @override
  String get moreActions => 'その他の操作';

  @override
  String get renameColorPreset => '配色名を変更';

  @override
  String get deleteColorPreset => '保存済み配色を削除';

  @override
  String deleteColorPresetQuestion(Object name) {
    return '保存済み配色「$name」を削除しますか？現在の ASS 設定に追加済みの歌手配色は削除されません。';
  }

  @override
  String colorPresetDeleted(Object name) {
    return '配色「$name」を削除しました';
  }

  @override
  String colorPresetRenamed(Object name) {
    return '配色名を「$name」に変更しました';
  }

  @override
  String get replaceCurrentSingerColorTitle => '現在の歌手配色を置換';

  @override
  String replaceCurrentSingerColorQuestion(Object name) {
    return '現在の歌手配色に「$name」が既にあります。保存済みの配色で置き換えますか？';
  }

  @override
  String colorPresetAddedToCurrent(Object name) {
    return '「$name」を現在の歌手配色に追加しました';
  }

  @override
  String currentSingerColorReplaced(Object name) {
    return '現在の歌手配色「$name」を置き換えました';
  }

  @override
  String get colorPresetNameRequired => 'プリセット名を入力してください';

  @override
  String get colorPresetNameInvalid => 'プリセット名に「|」や改行は使用できません';

  @override
  String get lineColoring => '行ごとの配色';

  @override
  String get closeLineColoring => '行ごとの配色を閉じる';

  @override
  String get noSavedColorPresets => 'ASS 出力画面に読み込まれた配色がありません';

  @override
  String applyLineColor(Object name) {
    return '選択位置の歌手マーカーを「$name」に切り替え';
  }

  @override
  String get selectLyricLineFirst => '先に歌詞の文字を選択してください';

  @override
  String get lineColoringFailed => '選択文字の前に行頭文字を挿入できませんでした';

  @override
  String get escapePod => 'エスケープポッド';

  @override
  String get escapePodDescription =>
      'フォント、歌手アイコン、配色を、他のプラットフォームでも復元できる ZIP にまとめます。';

  @override
  String get exportEscapePod => 'エスケープポッドを出力';

  @override
  String get exportEscapePodDescription => '現在のライブラリを ZIP ファイルに保存します';

  @override
  String get importEscapePod => 'エスケープポッドを読み込む';

  @override
  String get importEscapePodDescription => '同名の項目を更新し、それ以外の項目を追加します';

  @override
  String get preparingEscapePod => 'エスケープポッドを準備しています…';

  @override
  String get importingEscapePod => 'エスケープポッドを読み込んでいます…';

  @override
  String get chooseEscapePodSaveLocation => 'エスケープポッドの保存先を選択';

  @override
  String get chooseEscapePodFile => 'エスケープポッドを選択';

  @override
  String escapePodExported(Object fonts, Object avatars, Object colors) {
    return '出力完了：フォント $fonts 件、アイコン $avatars 件、配色 $colors 件';
  }

  @override
  String escapePodImported(
    Object fonts,
    Object avatars,
    Object colors,
    Object skipped,
  ) {
    return '読み込み完了：フォント $fonts 件、アイコン $avatars 件、配色 $colors 件、スキップ $skipped 件';
  }

  @override
  String escapePodExportFailed(Object error) {
    return 'エスケープポッドの出力に失敗しました：$error';
  }

  @override
  String escapePodImportFailed(Object error) {
    return 'エスケープポッドの読み込みに失敗しました：$error';
  }

  @override
  String get lineAlignmentSettings => '各行の配置';

  @override
  String get lineAlignmentSettingsDescription => '下寄せ 2～4 行の左右位置を設定します';

  @override
  String get lineAlignmentSettingsHelp => '行数ごとに、それぞれの行を左寄せ、中央寄せ、右寄せから選択できます。';

  @override
  String get bottomAlignedTwoLines => '下寄せ 2 行';

  @override
  String get bottomAlignedThreeLines => '下寄せ 3 行';

  @override
  String get bottomAlignedFourLines => '下寄せ 4 行';

  @override
  String lineNumber(Object line) {
    return '$line 行目';
  }

  @override
  String get alignLeft => '左';

  @override
  String get alignCenter => '中央';

  @override
  String get alignRight => '右';
}
