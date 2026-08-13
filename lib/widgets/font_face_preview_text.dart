import 'package:flutter/material.dart';

import '../models/font_library_asset.dart';
import '../services/font_library_service.dart';
import '../services/open_type_font.dart';

class FontFacePreviewText extends StatefulWidget {
  final FontLibraryService library;
  final FontLibraryAsset asset;
  final OpenTypeFontFaceInfo face;
  final String? text;
  final TextStyle? style;

  const FontFacePreviewText({
    super.key,
    required this.library,
    required this.asset,
    required this.face,
    this.text,
    this.style,
  });

  @override
  State<FontFacePreviewText> createState() => _FontFacePreviewTextState();
}

class _FontFacePreviewTextState extends State<FontFacePreviewText> {
  late Future<String> _fontFamily;

  @override
  void initState() {
    super.initState();
    _loadFont();
  }

  @override
  void didUpdateWidget(FontFacePreviewText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.library != oldWidget.library ||
        widget.asset.path != oldWidget.asset.path ||
        widget.asset.fileSize != oldWidget.asset.fileSize ||
        widget.asset.lastModified != oldWidget.asset.lastModified ||
        widget.face.index != oldWidget.face.index) {
      _loadFont();
    }
  }

  void _loadFont() {
    _fontFamily = widget.library.loadPreviewFontFamily(
      asset: widget.asset,
      faceIndex: widget.face.index,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 30,
      child: Align(
        alignment: Alignment.centerLeft,
        child: FutureBuilder<String>(
          future: _fontFamily,
          builder: (context, snapshot) {
            final inherited = DefaultTextStyle.of(context).style;
            final style = inherited
                .merge(widget.style)
                .copyWith(fontFamily: snapshot.data, height: 1.2);
            return Text(
              widget.text ?? widget.face.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            );
          },
        ),
      ),
    );
  }
}
