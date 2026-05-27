import 'package:flutter/material.dart';

enum AssPagingMode { auto2Lines, emptyLineDelimited }

class AssExportSettings {
  final String fontName;
  final Color primaryColor;
  final int fontSize;
  final AssPagingMode pagingMode;
  final int interludeThresholdSeconds;

  AssExportSettings({
    required this.fontName,
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
  late TextEditingController _fontController;

  final List<Color> _presetColors = [
    const Color(0xFF0000EB), // Blue
    const Color(0xFFEB0000), // Red
    const Color(0xFFFF7031), // Orange
  ];

  @override
  void initState() {
    super.initState();
    _fontController = TextEditingController(text: 'Kosugi Maru');
  }

  @override
  void dispose() {
    _fontController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('导出 ASS'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('高亮色:'),
            const SizedBox(height: 8),
            Row(
              children: [
                ..._presetColors.map((color) {
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
                }),
                if (!_presetColors.contains(_selectedColor))
                  GestureDetector(
                    onTap: _showCustomColorDialog,
                    child: Container(
                      margin: const EdgeInsets.only(right: 12),
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: _selectedColor,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white,
                          width: 3,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: _selectedColor.withValues(alpha: 0.5),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: const Icon(Icons.edit, size: 16, color: Colors.white),
                    ),
                  )
                else
                  GestureDetector(
                    onTap: _showCustomColorDialog,
                    child: Container(
                      margin: const EdgeInsets.only(right: 12),
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(20),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.transparent,
                          width: 3,
                        ),
                      ),
                      child: const Icon(Icons.palette_outlined, size: 20, color: Colors.white70),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            const Text('字幕字体'),
            const SizedBox(height: 8),
            TextField(
              controller: _fontController,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                hintText: '输入字体名称',
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                ActionChip(
                  label: const Text('Kosugi Maru'),
                  onPressed: () {
                    setState(() {
                      _fontController.text = 'Kosugi Maru';
                    });
                  },
                ),
                ActionChip(
                  label: const Text('BIZ UDP明朝'),
                  onPressed: () {
                    setState(() {
                      _fontController.text = 'BIZ UDP明朝';
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text('基准字号: ${_fontSize.toInt()}'),
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
                  child: Text('以空行为分隔按段落排版'),
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
              fontName: _fontController.text.trim().isEmpty
                  ? 'Kosugi Maru'
                  : _fontController.text.trim(),
              primaryColor: _selectedColor,
              fontSize: _fontSize.toInt(),
              pagingMode: _pagingMode,
              interludeThresholdSeconds: _interludeThreshold.toInt(),
            );
            Navigator.of(context).pop(settings);
          },
          child: const Text('导出'),
        ),
      ],
    );
  }

  Future<void> _showCustomColorDialog() async {
    String hexInput = '#';
    Color previewColor = _selectedColor;

    final result = await showDialog<Color>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('自定义高亮色'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: double.infinity,
                    height: 60,
                    decoration: BoxDecoration(
                      color: previewColor,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white24),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'HEX 颜色代码',
                      hintText: '例如: #FF0000 或 FFAA00',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (val) {
                      hexInput = val.trim();
                      if (hexInput.startsWith('#')) {
                        hexInput = hexInput.substring(1);
                      }
                      if (hexInput.length == 6 || hexInput.length == 8) {
                        try {
                          final hex = hexInput.length == 6 ? 'FF$hexInput' : hexInput;
                          final color = Color(int.parse(hex, radix: 16));
                          setDialogState(() {
                            previewColor = color;
                          });
                        } catch (_) {}
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(previewColor),
                  child: const Text('确定'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != null) {
      setState(() {
        _selectedColor = result;
      });
    }
  }
}
