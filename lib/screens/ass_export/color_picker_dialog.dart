part of '../ass_export_screen.dart';

// Solid, gradient and visual (HSV) color pickers.

Future<AssColorValue?> showAssColorPickerDialog(
  BuildContext context, {
  required AssColorValue initialValue,
  required List<Color> suggestedPresets,
  required String title,
}) {
  return showDialog<AssColorValue>(
    context: context,
    builder: (context) => _ColorPickerDialog(
      initialValue: initialValue,
      suggestedPresets: suggestedPresets,
      title: title,
    ),
  );
}

class _ColorPickerDialog extends StatefulWidget {
  final AssColorValue initialValue;
  final List<Color> suggestedPresets;
  final String title;

  const _ColorPickerDialog({
    required this.initialValue,
    required this.suggestedPresets,
    required this.title,
  });

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late AssColorMode _mode;
  late Color _color0;
  late Color _color100;
  int _activeEndpoint = 0;
  late List<AssColorStop> _stops;
  late TextEditingController _hexController;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialValue.mode;
    _color0 = widget.initialValue.color0;
    _color100 = widget.initialValue.color100;
    _stops = widget.initialValue.effectiveStops.toList();
    _hexController = TextEditingController(text: _colorToHex(_activeColor()));
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  Color _activeColor() {
    return _mode == AssColorMode.solid
        ? _color0
        : _stops[_activeEndpoint].color;
  }

  String _colorToHex(Color color) {
    final r = (color.r * 255).round().toRadixString(16).padLeft(2, '0');
    final g = (color.g * 255).round().toRadixString(16).padLeft(2, '0');
    final b = (color.b * 255).round().toRadixString(16).padLeft(2, '0');
    return '${r.toUpperCase()}${g.toUpperCase()}${b.toUpperCase()}';
  }

  Color? _tryParseHexColor(String input) {
    final hex = input.trim().replaceFirst('#', '');
    if (hex.length != 6) return null;
    final value = int.tryParse(hex, radix: 16);
    return value == null ? null : Color(0xFF000000 | value);
  }

  void _onColorChanged(Color color) {
    setState(() {
      if (_mode == AssColorMode.solid) {
        _color0 = color;
        _color100 = color;
      } else {
        _stops[_activeEndpoint] = AssColorStop(
          position: _stops[_activeEndpoint].position,
          color: color,
        );
        _syncEndpointColors();
      }
      _hexController.text = _colorToHex(color);
    });
  }

  void _onHexChanged(String text) {
    final parsed = _tryParseHexColor(text);
    if (parsed != null) {
      setState(() {
        if (_mode == AssColorMode.solid) {
          _color0 = parsed;
          _color100 = parsed;
        } else {
          _stops[_activeEndpoint] = AssColorStop(
            position: _stops[_activeEndpoint].position,
            color: parsed,
          );
          _syncEndpointColors();
        }
      });
    }
  }

  Future<void> _showVisualColorPicker() async {
    final selected = await showDialog<Color>(
      context: context,
      builder: (context) =>
          _VisualColorPickerDialog(initialColor: _activeColor()),
    );
    if (selected != null && mounted) _onColorChanged(selected);
  }

  void _syncEndpointColors() {
    _stops.sort((a, b) => a.position.compareTo(b.position));
    _color0 = _stops.first.color;
    _color100 = _stops.last.color;
  }

  void _addStop() {
    final selected = _stops[_activeEndpoint];
    final nextPosition = _activeEndpoint + 1 < _stops.length
        ? _stops[_activeEndpoint + 1].position
        : 1.0;
    final position = (selected.position + nextPosition) / 2;
    setState(() {
      _stops.add(AssColorStop(position: position, color: selected.color));
      _stops.sort((a, b) => a.position.compareTo(b.position));
      _activeEndpoint = _stops.indexWhere((stop) => stop.position == position);
      _syncEndpointColors();
      _hexController.text = _colorToHex(_activeColor());
    });
  }

  void _removeActiveStop() {
    if (_stops.length <= 2) return;
    setState(() {
      _stops.removeAt(_activeEndpoint);
      _activeEndpoint = _activeEndpoint.clamp(0, _stops.length - 1);
      _syncEndpointColors();
      _hexController.text = _colorToHex(_activeColor());
    });
  }

  LinearGradient _previewGradient() {
    if (_mode == AssColorMode.gradient) {
      return LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: _stops.map((stop) => stop.color).toList(),
        stops: _stops.map((stop) => stop.position).toList(),
      );
    }
    final colors = <Color>[];
    final positions = <double>[];
    for (var index = 0; index < _stops.length; index++) {
      final start = _stops[index].position;
      final end = index + 1 < _stops.length ? _stops[index + 1].position : 1.0;
      colors.addAll([_stops[index].color, _stops[index].color]);
      positions.addAll([start, end]);
    }
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: colors,
      stops: positions,
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeColor = _activeColor();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    widget.title,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(null),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Container(
                height: 90,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: _mode == AssColorMode.solid ? _color0 : null,
                  gradient: _mode == AssColorMode.solid
                      ? null
                      : _previewGradient(),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.15),
                    width: 1.5,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: SegmentedButton<AssColorMode>(
                style: SegmentedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                segments: [
                  ButtonSegment(
                    value: AssColorMode.solid,
                    label: Text(context.l10n.solidColor),
                  ),
                  ButtonSegment(
                    value: AssColorMode.gradient,
                    label: Text(context.l10n.gradient),
                  ),
                  const ButtonSegment(
                    value: AssColorMode.millefeuille,
                    label: Text('ミルフィーユ'),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: (selection) {
                  setState(() {
                    final previousMode = _mode;
                    _mode = selection.first;
                    if (_mode == AssColorMode.solid) {
                      _color100 = _color0;
                      _activeEndpoint = 0;
                    } else if (_stops.length < 2) {
                      _stops = [
                        AssColorStop(position: 0, color: _color0),
                        AssColorStop(position: 1, color: _color100),
                      ];
                    }
                    if (_mode == AssColorMode.millefeuille &&
                        previousMode != AssColorMode.millefeuille &&
                        _stops.length == 2 &&
                        _stops.first.position == 0 &&
                        _stops.last.position == 1) {
                      _stops[1] = AssColorStop(
                        position: 0.5,
                        color: _stops[1].color,
                      );
                      _syncEndpointColors();
                    }
                    _hexController.text = _colorToHex(_activeColor());
                  });
                },
              ),
            ),
            const SizedBox(height: 16),
            if (_mode != AssColorMode.solid)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Slider(
                            value: _stops[_activeEndpoint].position,
                            onChanged: (value) => setState(() {
                              final active = _stops[_activeEndpoint];
                              final updated = AssColorStop(
                                position: value,
                                color: active.color,
                              );
                              _stops[_activeEndpoint] = updated;
                              _syncEndpointColors();
                              _activeEndpoint = _stops.indexOf(updated);
                            }),
                          ),
                        ),
                        SizedBox(
                          width: 54,
                          child: Text(
                            '${(_stops[_activeEndpoint].position * 100).round()}%',
                          ),
                        ),
                      ],
                    ),
                    SizedBox(
                      height: 68,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _stops.length + 2,
                        separatorBuilder: (_, _) => const SizedBox(width: 6),
                        itemBuilder: (context, index) {
                          if (index < _stops.length) {
                            final stop = _stops[index];
                            return _buildCompactStop(
                              position: stop.position,
                              color: stop.color,
                              isActive: _activeEndpoint == index,
                              onTap: () => setState(() {
                                _activeEndpoint = index;
                                _hexController.text = _colorToHex(
                                  _activeColor(),
                                );
                              }),
                            );
                          }
                          if (index == _stops.length) {
                            return _buildStopAction(
                              icon: Icons.add,
                              onPressed: _addStop,
                            );
                          }
                          return _buildStopAction(
                            icon: Icons.remove,
                            onPressed: _stops.length > 2
                                ? _removeActiveStop
                                : null,
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            if (_mode != AssColorMode.solid) const SizedBox(height: 20),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.hexColorCode,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _hexController,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'[0-9a-fA-F]'),
                        ),
                        LengthLimitingTextInputFormatter(6),
                      ],
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.tag),
                        suffixIcon: Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: IconButton(
                            onPressed: _showVisualColorPicker,
                            icon: const Icon(Icons.palette_outlined),
                            tooltip: context.l10n.chooseColor,
                          ),
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                      ),
                      onChanged: _onHexChanged,
                    ),
                    const SizedBox(height: 24),
                    if (widget.suggestedPresets.isNotEmpty) ...[
                      Text(
                        context.l10n.preset,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: widget.suggestedPresets
                            .map(
                              (preset) => _buildColorCircle(
                                preset,
                                activeColor == preset,
                              ),
                            )
                            .toList(),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(null),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                    child: Text(context.l10n.cancel),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: () {
                      Navigator.of(context).pop(
                        _mode == AssColorMode.solid
                            ? AssColorValue.solid(_color0)
                            : AssColorValue.withStops(
                                mode: _mode,
                                stops: _stops,
                              ),
                      );
                    },
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 12,
                      ),
                    ),
                    child: Text(context.l10n.apply),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactStop({
    required double position,
    required Color color,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 48,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: isActive ? theme.colorScheme.primaryContainer : null,
          border: Border.all(
            color: isActive ? theme.colorScheme.primary : Colors.transparent,
            width: 2,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: Colors.white54),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${(position * 100).round()}%',
              style: TextStyle(
                fontSize: 11,
                height: 1,
                fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                color: isActive ? theme.colorScheme.onPrimaryContainer : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStopAction({
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      width: 42,
      child: IconButton.filledTonal(
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
      ),
    );
  }

  Widget _buildColorCircle(Color color, bool isActive) {
    return GestureDetector(
      onTap: () => _onColorChanged(color),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 48,
        height: 48,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: isActive ? Colors.white : Colors.transparent,
            width: 2,
          ),
          boxShadow: [
            if (isActive)
              BoxShadow(
                color: color.withValues(alpha: 0.6),
                blurRadius: 12,
                spreadRadius: 2,
              ),
          ],
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white24),
          ),
          child: isActive
              ? Icon(
                  Icons.check,
                  color: color.computeLuminance() > 0.5
                      ? Colors.black87
                      : Colors.white,
                )
              : null,
        ),
      ),
    );
  }
}

class _VisualColorPickerDialog extends StatefulWidget {
  final Color initialColor;

  const _VisualColorPickerDialog({required this.initialColor});

  @override
  State<_VisualColorPickerDialog> createState() =>
      _VisualColorPickerDialogState();
}

class _VisualColorPickerDialogState extends State<_VisualColorPickerDialog> {
  late HSVColor _hsvColor;

  @override
  void initState() {
    super.initState();
    _hsvColor = HSVColor.fromColor(widget.initialColor);
  }

  void _updateHueSaturation(Offset position, double size) {
    setState(() {
      _hsvColor = _hsvColor.withHue(
        (position.dx / size * 360).clamp(0.0, 360.0),
      );
      _hsvColor = _hsvColor.withSaturation(
        (1 - position.dy / size).clamp(0.0, 1.0),
      );
    });
  }

  void _updateValue(Offset position, double width) {
    setState(() {
      _hsvColor = _hsvColor.withValue((position.dx / width).clamp(0.0, 1.0));
    });
  }

  String _hexValue(Color color) {
    final r = (color.r * 255).round().toRadixString(16).padLeft(2, '0');
    final g = (color.g * 255).round().toRadixString(16).padLeft(2, '0');
    final b = (color.b * 255).round().toRadixString(16).padLeft(2, '0');
    return '${r.toUpperCase()}${g.toUpperCase()}${b.toUpperCase()}';
  }

  @override
  Widget build(BuildContext context) {
    final dialogWidth = min(360.0, MediaQuery.sizeOf(context).width - 48);
    final pickerSize = dialogWidth - 48;
    final color = _hsvColor.toColor();

    return Dialog(
      child: SizedBox(
        width: dialogWidth,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                context.l10n.chooseColor,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 20),
              GestureDetector(
                onTapDown: (details) =>
                    _updateHueSaturation(details.localPosition, pickerSize),
                onPanStart: (details) =>
                    _updateHueSaturation(details.localPosition, pickerSize),
                onPanUpdate: (details) =>
                    _updateHueSaturation(details.localPosition, pickerSize),
                child: CustomPaint(
                  size: Size.square(pickerSize),
                  painter: _HueSaturationPainter(_hsvColor),
                ),
              ),
              const SizedBox(height: 18),
              GestureDetector(
                onTapDown: (details) =>
                    _updateValue(details.localPosition, pickerSize),
                onPanStart: (details) =>
                    _updateValue(details.localPosition, pickerSize),
                onPanUpdate: (details) =>
                    _updateValue(details.localPosition, pickerSize),
                child: CustomPaint(
                  size: Size(pickerSize, 28),
                  painter: _ValuePainter(_hsvColor),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '#${_hexValue(color)}',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(context.l10n.cancel),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(color),
                    child: Text(context.l10n.apply),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HueSaturationPainter extends CustomPainter {
  final HSVColor color;

  const _HueSaturationPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          colors: [
            Color(0xFFFF0000),
            Color(0xFFFFFF00),
            Color(0xFF00FF00),
            Color(0xFF00FFFF),
            Color(0xFF0000FF),
            Color(0xFFFF00FF),
            Color(0xFFFF0000),
          ],
        ).createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.white],
        ).createShader(rect),
    );

    final marker = Offset(
      color.hue / 360 * size.width,
      (1 - color.saturation) * size.height,
    );
    canvas.drawCircle(marker, 8, Paint()..color = Colors.black54);
    canvas.drawCircle(
      marker,
      6,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_HueSaturationPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _ValuePainter extends CustomPainter {
  final HSVColor color;

  const _ValuePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final fullValueColor = color.withValue(1).toColor();
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(6)),
      Paint()
        ..shader = LinearGradient(
          colors: [Colors.black, fullValueColor],
        ).createShader(rect),
    );

    final markerX = color.value * size.width;
    final markerRect = Rect.fromCenter(
      center: Offset(markerX, size.height / 2),
      width: 6,
      height: size.height + 4,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(markerRect, const Radius.circular(3)),
      Paint()..color = Colors.black54,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(markerRect.deflate(1), const Radius.circular(2)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_ValuePainter oldDelegate) => oldDelegate.color != color;
}
