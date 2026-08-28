// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'yuukilyrics';

  @override
  String get cancel => '取消';

  @override
  String get apply => '应用';

  @override
  String get close => '关闭';

  @override
  String get delete => '删除';

  @override
  String get refresh => '刷新';

  @override
  String get share => '分享';

  @override
  String get confirm => '确定';

  @override
  String get openNavigationMenu => '打开导航菜单';

  @override
  String get file => '文件';

  @override
  String get preview => '预览';

  @override
  String get export => '导出';

  @override
  String get automatic => '自动';

  @override
  String automaticPixels(Object value) {
    return '自动（$value px）';
  }

  @override
  String mediaOpenFailed(Object error) {
    return '媒体文件打开失败：$error';
  }

  @override
  String waveformAnalysisFailed(Object error) {
    return '波形分析失败：$error';
  }

  @override
  String get exportFile => '导出文件';

  @override
  String get fileName => '文件名';

  @override
  String get saveToDevice => '保存到设备';

  @override
  String get emptyLyricsCannotExport => '歌词为空，无法导出。';

  @override
  String timedLyricsShareSubject(Object fileName) {
    return '带时间标签的歌词：$fileName';
  }

  @override
  String get chooseLyricsSaveLocation => '选择歌词文件保存位置';

  @override
  String lyricsFileSaved(Object path) {
    return '歌词文件已保存：$path';
  }

  @override
  String lyricsExportFailed(Object error) {
    return '歌词文件导出失败：$error';
  }

  @override
  String assShareSubject(Object fileName) {
    return 'ASS 字幕：$fileName';
  }

  @override
  String get chooseAssSaveLocation => '选择 ASS 字幕保存位置';

  @override
  String assSaved(Object path) {
    return 'ASS 字幕已保存：$path';
  }

  @override
  String assExportFailed(Object error) {
    return 'ASS 字幕导出失败：$error';
  }

  @override
  String get chooseVideoSaveLocation => '选择视频保存位置';

  @override
  String outputPreparationFailed(Object error) {
    return '无法准备输出位置：$error';
  }

  @override
  String get detectingEncoder => '正在检测编码器…';

  @override
  String get encodingVideo => '正在编码视频…';

  @override
  String get burningSubtitles => '正在将字幕烧录到视频中，请稍候。';

  @override
  String encoderName(Object codec) {
    return '编码器：$codec';
  }

  @override
  String videoSaved(Object path) {
    return '视频已保存：$path';
  }

  @override
  String hardsubVideoShareSubject(Object fileName) {
    return '带字幕视频：$fileName';
  }

  @override
  String get encodingFailed => '编码失败';

  @override
  String get openMediaFile => '打开媒体文件';

  @override
  String get openMediaFileDescription => '载入需要添加时间标签的音频或视频';

  @override
  String get openLyricsFile => '打开歌词文件';

  @override
  String get openLyricsFileDescription => '载入 LRC 等歌词文件';

  @override
  String get exportTimedLyrics => '导出带时间标签的歌词';

  @override
  String get exportTimedLyricsDescription => '将正在编辑的歌词保存为 LRC 格式';

  @override
  String get license => '许可证';

  @override
  String get timingEditor => '时间标签编辑';

  @override
  String get assExport => 'ASS 导出';

  @override
  String get assetLibrary => '素材库';

  @override
  String get fontLibrary => '字体库';

  @override
  String get aboutApp => '关于应用';

  @override
  String versionAndBuild(Object version, Object buildNumber) {
    return '版本 $version（构建号 $buildNumber）';
  }

  @override
  String get toggleTextEditMode => '切换文本编辑模式';

  @override
  String previewLoadFailed(Object error) {
    return '预览载入失败：$error';
  }

  @override
  String get subtitleRenderWarnings => '字幕渲染警告与错误';

  @override
  String get playingAtDoubleSpeed => '正在以 2 倍速播放';

  @override
  String warningErrorCount(Object count) {
    return '警告与错误 $count 条';
  }

  @override
  String get singerName => '歌手名';

  @override
  String get addSingerIcon => '添加歌手图标';

  @override
  String get replaceExistingIcon => '替换现有图标';

  @override
  String replaceSingerIconQuestion(Object name) {
    return '“$name”已有图标。要替换吗？';
  }

  @override
  String get replace => '替换';

  @override
  String get singerIconSaved => '歌手图标已保存';

  @override
  String get renameSinger => '修改歌手名';

  @override
  String get singerRenamed => '歌手名已修改';

  @override
  String get deleteSingerIcon => '删除歌手图标';

  @override
  String deleteSingerIconQuestion(Object name) {
    return '要删除“$name”的图标吗？';
  }

  @override
  String get singerIconDeleted => '歌手图标已删除';

  @override
  String operationFailed(Object error) {
    return '操作失败：$error';
  }

  @override
  String get addImage => '添加图片';

  @override
  String singerIconConflicts(Object count) {
    return '存在 $count 个同名文件冲突。请确保每位歌手只保留一个图片文件，整理素材文件夹后再刷新。';
  }

  @override
  String get noSingerIcons => '尚未添加歌手图标';

  @override
  String get renameSingerTooltip => '修改歌手名';

  @override
  String get openMediaPrompt => '请打开媒体文件。';

  @override
  String get lyricsInputHint => '请输入歌词';

  @override
  String get lyricsEmptyPrompt => '请打开歌词文件，或在文本编辑模式中输入歌词。';

  @override
  String get playPause => '播放/暂停';

  @override
  String get stopTagging => '结束打标签';

  @override
  String get startTagging => '开始打标签';

  @override
  String get addCheck => '添加检查点';

  @override
  String get removeCheck => '删除检查点';

  @override
  String get mergeNextCharacter => '与下一个字符合并';

  @override
  String get splitCharacter => '拆分字符';

  @override
  String get toggleKeyUpCheck => '添加/删除抬键检查点';

  @override
  String get autoRubyAndChecks => '自动添加注音与检查点';

  @override
  String get seekBackOnePointFiveSeconds => '后退 1.5 秒';

  @override
  String get seekForwardOneSecond => '前进 1 秒';

  @override
  String get taggingOffset => '时间标签输入偏移';

  @override
  String get confirmBulkAdjustment => '确认批量调整';

  @override
  String get bulkAdjustTimeTags => '批量调整时间标签';

  @override
  String get playbackSpeed => '播放速度';

  @override
  String get rubyLabel => '注音：';

  @override
  String get rubyInputHint => '输入注音（例：こう）';

  @override
  String advanceInputTime(Object offset) {
    return '输入时间提前 $offset ms';
  }

  @override
  String delayInputTime(Object offset) {
    return '输入时间延后 $offset ms';
  }

  @override
  String get offsetHelp => '用于补偿操作响应延迟\n默认值：-230 ms';

  @override
  String get preparing => '准备中…';

  @override
  String fetchingRubyProgress(Object current, Object total) {
    return '正在获取注音…（$current/$total）';
  }

  @override
  String get updatingLyrics => '正在更新歌词…';

  @override
  String get stop => '停止';

  @override
  String get autoRubyCancelled => '已停止添加注音；已完成的内容将保留。';

  @override
  String get autoRubyCompleted => '已完成自动添加注音与检查点。';

  @override
  String get colors => '配色';

  @override
  String get defaultColors => '默认配色';

  @override
  String get importAction => '导入';

  @override
  String get addSinger => '添加歌手';

  @override
  String get textSettings => '文字';

  @override
  String get bold => '粗体';

  @override
  String get textStyle => '文字样式';

  @override
  String textStyleSummary(
    Object fontSize,
    Object letterSpacing,
    Object decorationWidth,
  ) {
    return '$fontSize px · $letterSpacing · 装饰 $decorationWidth px';
  }

  @override
  String get blur => '模糊等级';

  @override
  String get screenSettings => '画面';

  @override
  String get horizontalMargin => '左右余白';

  @override
  String get interludeCountdown => '间奏倒计时';

  @override
  String get showLinePrefix => '显示行首字符';

  @override
  String get font => '字体';

  @override
  String get resetBuiltInFont => '恢复内置字体';

  @override
  String get chooseFont => '选择字体';

  @override
  String get importFont => '添加字体';

  @override
  String get manageFonts => '管理字体';

  @override
  String get replaceExistingFont => '替换现有字体';

  @override
  String replaceFontQuestion(Object name) {
    return '“$name”已经导入。要替换吗？';
  }

  @override
  String get fontImported => '字体已添加';

  @override
  String get deleteFont => '删除字体';

  @override
  String deleteFontQuestion(Object name) {
    return '要从字体库中删除“$name”吗？';
  }

  @override
  String get fontDeleted => '字体已删除';

  @override
  String get fontFaces => '字体样式';

  @override
  String invalidFontFiles(Object count) {
    return '存在 $count 个无法读取的字体文件。请检查文件后刷新。';
  }

  @override
  String get noImportedFonts => '尚未添加字体';

  @override
  String fontFileSummary(Object fileName, Object count, Object size) {
    return '$fileName · $count 个字体样式 · $size';
  }

  @override
  String fontWithFaceCount(Object fileName, Object count) {
    return '$fileName · $count 个字体样式';
  }

  @override
  String get fontFace => '字体样式';

  @override
  String get builtInFont => '内置字体';

  @override
  String get subtitleLayout => '字幕布局';

  @override
  String get alternatingTwoLines => '两行交替显示（左上/右下）';

  @override
  String get paragraphsByBlankLine => '按空行分段';

  @override
  String get outputResolution => '字幕分辨率';

  @override
  String get heightPixels => '高度 (px)';

  @override
  String get widthPixels => '宽度 (px)';

  @override
  String get resetSourceResolution => '将字幕分辨率设为原视频分辨率';

  @override
  String secondsValue(Object value) {
    return '$value 秒';
  }

  @override
  String singerColorsTitle(Object singer) {
    return '$singer的配色';
  }

  @override
  String get colorPreset => '配色预设';

  @override
  String get sample => '示例';

  @override
  String get sungColors => '已演唱部分配色';

  @override
  String get unsungColors => '未演唱部分配色';

  @override
  String get textColor => '文字颜色';

  @override
  String get outlineColor => '描边颜色';

  @override
  String get decorationColor => '装饰颜色';

  @override
  String chooseItem(Object item) {
    return '选择$item';
  }

  @override
  String get chooseColor => '选择颜色';

  @override
  String previewFontPreparationFailed(Object error) {
    return '准备预览字体失败：$error';
  }

  @override
  String get exportAssSubtitle => '导出 ASS 字幕';

  @override
  String get exportAssSubtitleDescription => '保存 ASS 字幕文件（.ass）';

  @override
  String get exportHardsubVideo => '导出带字幕视频';

  @override
  String get exportHardsubVideoDescription => '将字幕烧录到视频并保存';

  @override
  String get exportHardsubVideoUnavailable => '仅在载入视频后可用';

  @override
  String fontParseFailed(Object error) {
    return '字体解析失败：$error';
  }

  @override
  String fontFaceLoadFailed(Object error) {
    return '字体样式载入失败：$error';
  }

  @override
  String get linePrefix => '行首字符';

  @override
  String get editColors => '编辑配色';

  @override
  String get singerColorImport => '导入歌手配色';

  @override
  String get importN3Project => '导入 N3 工程';

  @override
  String get importN3ProjectDescription => '从 N3 工程读取配色样式';

  @override
  String get onlineColorEditor => '在线配色编辑器';

  @override
  String n3ColorImportLoaded(Object count) {
    return '已读取 $count 个 N3 配色方案（已忽略描边 2 色）';
  }

  @override
  String n3ColorImportFailed(Object error) {
    return 'N3 工程读取失败：$error';
  }

  @override
  String singerColorImportCompleted(
    Object updated,
    Object added,
    Object skipped,
  ) {
    return '导入完成：更新 $updated 项，新增 $added 项，跳过 $skipped 行';
  }

  @override
  String singerColorImportCompletedWithDuplicates(
    Object updated,
    Object added,
    Object skipped,
    Object duplicates,
  ) {
    return '导入完成：更新 $updated 项，新增 $added 项，跳过 $skipped 行；文本内 $duplicates 行同名数据已由后面的内容覆盖';
  }

  @override
  String get singerColorImportHelp =>
      '每行填写歌手名和 6 种颜色，并使用 Tab（推荐）或 | 分隔。\n纯色使用 #RRGGBB，渐变使用 #上方颜色/#下方颜色。标题行可以省略。';

  @override
  String get singerColorExample =>
      '歌手名称\t已演唱文字颜色\t已演唱描边颜色\t已演唱装饰颜色\t未演唱文字颜色\t未演唱描边颜色\t未演唱装饰颜色\nラケナリア\t#0572A4/#052951\t#FFFFFF\t#E1E196\t#DCF0FC\t#43464A\t#E19696';

  @override
  String singerColorImportSplitError(Object line) {
    return '第 $line 行：请使用 Tab 或 | 分隔为 7 列';
  }

  @override
  String singerColorImportColumnCountError(Object line, Object count) {
    return '第 $line 行：需要 7 列，实际为 $count 列';
  }

  @override
  String singerColorImportSingerRequired(Object line) {
    return '第 $line 行：请输入歌手名';
  }

  @override
  String singerColorImportInvalidColor(
    Object line,
    Object colorName,
    Object value,
  ) {
    return '第 $line 行：$colorName“$value”格式不正确';
  }

  @override
  String get sungTextColor => '已演唱文字颜色';

  @override
  String get sungOutlineColor => '已演唱描边颜色';

  @override
  String get sungDecorationColor => '已演唱装饰颜色';

  @override
  String get unsungTextColor => '未演唱文字颜色';

  @override
  String get unsungOutlineColor => '未演唱描边颜色';

  @override
  String get unsungDecorationColor => '未演唱装饰颜色';

  @override
  String get paste => '粘贴';

  @override
  String get singerColorInputHint => '在此粘贴配色文本';

  @override
  String singerColorImportSummary(
    Object valid,
    Object singers,
    Object duplicates,
    Object skipped,
  ) {
    return '有效 $valid 行，歌手 $singers 名，同名覆盖 $duplicates 行，跳过 $skipped 行';
  }

  @override
  String get singerColorInputEmpty => '尚未输入配色文本';

  @override
  String get importValidRows => '导入';

  @override
  String get resetDefaults => '恢复默认值';

  @override
  String get showSingerIcon => '显示歌手图标';

  @override
  String get fontSize => '字体大小';

  @override
  String get letterSpacing => '字符间距';

  @override
  String get decorationWidth => '装饰宽度';

  @override
  String get textOutlineWidth => '文字描边宽度';

  @override
  String get furiganaSize => '注音大小';

  @override
  String get furiganaOutlineWidth => '注音描边宽度';

  @override
  String get furiganaTextGap => '注音与正文间距';

  @override
  String get lineSpacing => '行间距';

  @override
  String get subtitleBottomMargin => '字幕与画面底部间距';

  @override
  String get singerIconSize => '歌手图标大小';

  @override
  String get lyricsIconGap => '歌词与图标间距';

  @override
  String get solidColor => '纯色';

  @override
  String get gradient => '渐变';

  @override
  String get gradientTop => '上方（0%）';

  @override
  String get gradientBottom => '下方（100%）';

  @override
  String get hexColorCode => '十六进制颜色代码';

  @override
  String get preset => '预设';

  @override
  String get noPreset => '无预设';

  @override
  String get blueColors => '蓝色配色';

  @override
  String get standardColors => '标准配色';

  @override
  String get chorusColors => '合唱配色';

  @override
  String get blueColors2 => '蓝色配色 2';

  @override
  String get purple => '紫色';

  @override
  String get bluePurple => '蓝紫混合';

  @override
  String get kusou => '空爽';

  @override
  String get fontFacesNotFound => '未找到字体样式。';

  @override
  String get enableHapticFeedback => '开启震动反馈';

  @override
  String get disableHapticFeedback => '关闭震动反馈';

  @override
  String get saveColorPreset => '保存当前配色';

  @override
  String get colorPresetName => '预设名称';

  @override
  String colorPresetSaved(Object name) {
    return '已保存配色预设“$name”';
  }

  @override
  String get savedColorPresets => '已保存配色';

  @override
  String get importSavedColorPresets => '导入配色样式';

  @override
  String get importSavedColorPresetsDescription => '从文本添加或更新已保存配色';

  @override
  String get noSavedColorPresetLibrary => '尚未保存配色';

  @override
  String get addToCurrentSingerColors => '添加';

  @override
  String get moreActions => '更多操作';

  @override
  String get renameColorPreset => '重命名配色';

  @override
  String get deleteColorPreset => '删除已保存配色';

  @override
  String deleteColorPresetQuestion(Object name) {
    return '确定删除已保存配色“$name”吗？当前 ASS 设置中已添加的歌手配色不会被删除。';
  }

  @override
  String colorPresetDeleted(Object name) {
    return '已删除配色“$name”';
  }

  @override
  String colorPresetRenamed(Object name) {
    return '已将配色重命名为“$name”';
  }

  @override
  String get replaceCurrentSingerColorTitle => '替换当前歌手配色';

  @override
  String replaceCurrentSingerColorQuestion(Object name) {
    return '当前歌手配色中已存在“$name”。是否用已保存的配色替换？';
  }

  @override
  String colorPresetAddedToCurrent(Object name) {
    return '已将“$name”添加到当前歌手配色';
  }

  @override
  String currentSingerColorReplaced(Object name) {
    return '已替换当前歌手配色“$name”';
  }

  @override
  String get colorPresetNameRequired => '请输入预设名称';

  @override
  String get colorPresetNameInvalid => '预设名称不能包含“|”或换行';

  @override
  String get lineColoring => '分色';

  @override
  String get closeLineColoring => '关闭分色';

  @override
  String get noSavedColorPresets => 'ASS 导出界面中没有已加载的配色';

  @override
  String applyLineColor(Object name) {
    return '将选中位置的歌手标记切换为“$name”';
  }

  @override
  String get selectLyricLineFirst => '请先选择歌词字符';

  @override
  String get lineColoringFailed => '无法在选中字符前插入行首文字';

  @override
  String get escapePod => '逃生舱';

  @override
  String get escapePodDescription => '将字体、歌手头像和配色方案打包为可在其他平台恢复的 ZIP。';

  @override
  String get exportEscapePod => '导出逃生舱';

  @override
  String get exportEscapePodDescription => '将当前素材库保存为 ZIP 文件';

  @override
  String get importEscapePod => '导入逃生舱';

  @override
  String get importEscapePodDescription => '更新同名项目，并追加其他项目';

  @override
  String get preparingEscapePod => '正在准备逃生舱…';

  @override
  String get importingEscapePod => '正在导入逃生舱…';

  @override
  String get chooseEscapePodSaveLocation => '选择逃生舱保存位置';

  @override
  String get chooseEscapePodFile => '选择逃生舱文件';

  @override
  String escapePodExported(Object fonts, Object avatars, Object colors) {
    return '导出完成：字体 $fonts 个，头像 $avatars 个，配色 $colors 个';
  }

  @override
  String escapePodImported(
    Object fonts,
    Object avatars,
    Object colors,
    Object skipped,
  ) {
    return '导入完成：字体 $fonts 个，头像 $avatars 个，配色 $colors 个，跳过 $skipped 个';
  }

  @override
  String escapePodExportFailed(Object error) {
    return '导出逃生舱失败：$error';
  }

  @override
  String escapePodImportFailed(Object error) {
    return '导入逃生舱失败：$error';
  }

  @override
  String get lineAlignmentSettings => '每行位置';

  @override
  String get lineAlignmentSettingsDescription => '设置下对齐 2～4 行中每一行的左右位置';

  @override
  String get lineAlignmentSettingsHelp => '可以分别为不同总行数中的每一行选择居左、居中或居右。';

  @override
  String get bottomAlignedTwoLines => '下对齐 2 行';

  @override
  String get bottomAlignedThreeLines => '下对齐 3 行';

  @override
  String get bottomAlignedFourLines => '下对齐 4 行';

  @override
  String lineNumber(Object line) {
    return '第 $line 行';
  }

  @override
  String get alignLeft => '居左';

  @override
  String get alignCenter => '居中';

  @override
  String get alignRight => '居右';
}
