import 'package:flutter/material.dart';

enum AssPagingMode { auto2Lines, emptyLineDelimited }

class AssExportSettings {
  final Color primaryColor;
  final int fontSize;
  final AssPagingMode pagingMode;
  final int interludeThresholdSeconds;

  AssExportSettings({
    required this.primaryColor,
    required this.fontSize,
    required this.pagingMode,
    required this.interludeThresholdSeconds,
  });
}

class AssExportDialog extends StatefulWidget {
  const AssExportDialog({super.key});

  @override
  State<AssExportDialog> createState() => _AssExportDialogState();
}

class _AssExportDialogState extends State<AssExportDialog> {
  Color _selectedColor = const Color(0xFF0000EB);
  double _fontSize = 75.0;
  AssPagingMode _pagingMode = AssPagingMode.auto2Lines;
  double _interludeThreshold = 10.0;

  final List<Color> _presetColors = [
    const Color(0xFF0000EB), // Blue
    const Color(0xFFEB0000), // Red
    const Color(0xFFFF7031), // Orange
  ];

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('导出高级 ASS 卡拉OK字幕'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('主题颜色 (高亮色):'),
            const SizedBox(height: 8),
            Row(
              children: _presetColors.map((color) {
                final isSelected = _selectedColor == color;
                return GestureDetector(
                  onTap: () => setState(() => _selectedColor = color),
                  child: Container(
                    margin: const EdgeInsets.only(right: 12),
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected ? Colors.white : Colors.transparent,
                        width: 3,
                      ),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: color.withValues(alpha: 0.5),
                                blurRadius: 8,
                              ),
                            ]
                          : [],
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
            Text('基准字号 (默认75): ${_fontSize.toInt()}'),
            Slider(
              value: _fontSize,
              min: 20,
              max: 200,
              divisions: 180,
              label: _fontSize.toInt().toString(),
              onChanged: (val) => setState(() => _fontSize = val),
            ),
            const SizedBox(height: 16),
            const Text('分页排版方式:'),
            DropdownButton<AssPagingMode>(
              value: _pagingMode,
              isExpanded: true,
              items: const [
                DropdownMenuItem(
                  value: AssPagingMode.auto2Lines,
                  child: Text('自动 2 行交错 (左上/右下)'),
                ),
                DropdownMenuItem(
                  value: AssPagingMode.emptyLineDelimited,
                  child: Text('以空行为分隔按段落排版 (1-4行)'),
                ),
              ],
              onChanged: (val) {
                if (val != null) setState(() => _pagingMode = val);
              },
            ),
            const SizedBox(height: 24),
            Text('间奏提示阈值: ${_interludeThreshold.toInt()} 秒'),
            const Text(
              '当上下句间隔超过此时间时，将显示间奏倒计时',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            Slider(
              value: _interludeThreshold,
              min: 5,
              max: 60,
              divisions: 55,
              label: '${_interludeThreshold.toInt()}s',
              onChanged: (val) => setState(() => _interludeThreshold = val),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final settings = AssExportSettings(
              primaryColor: _selectedColor,
              fontSize: _fontSize.toInt(),
              pagingMode: _pagingMode,
              interludeThresholdSeconds: _interludeThreshold.toInt(),
            );
            Navigator.of(context).pop(settings);
          },
          child: const Text('导出 ASS'),
        ),
      ],
    );
  }
}
