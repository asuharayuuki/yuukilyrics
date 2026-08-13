import 'package:flutter/material.dart';

class PreviewColorValue {
  final Color color0;
  final Color color100;
  final bool isGradient;

  const PreviewColorValue({
    required this.color0,
    required this.color100,
    required this.isGradient,
  });
}

class DualColorPreview extends StatelessWidget {
  final PreviewColorValue sung;
  final PreviewColorValue unsung;

  const DualColorPreview({
    super.key,
    required this.sung,
    required this.unsung,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 28,
      child: Stack(
        children: [
          Positioned(
            right: 0,
            child: ColorPreviewCircle(value: unsung, size: 28, borderWidth: 2),
          ),
          Positioned(
            left: 0,
            child: ColorPreviewCircle(value: sung, size: 28, borderWidth: 2),
          ),
        ],
      ),
    );
  }
}

class ColorPreviewCircle extends StatelessWidget {
  final PreviewColorValue value;
  final double size;
  final double borderWidth;

  const ColorPreviewCircle({
    super.key,
    required this.value,
    this.size = 24,
    this.borderWidth = 1.5,
  });

  @override
  Widget build(BuildContext context) {
    final representative =
        Color.lerp(value.color0, value.color100, 0.5) ?? value.color0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: value.isGradient ? null : value.color0,
        gradient: value.isGradient
            ? LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [value.color0, value.color100],
              )
            : null,
        border: Border.all(color: Colors.white, width: borderWidth),
        boxShadow: [
          BoxShadow(
            color: representative.withValues(alpha: 0.5),
            blurRadius: 8,
          ),
        ],
      ),
    );
  }
}
