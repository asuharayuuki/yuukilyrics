import 'package:flutter_test/flutter_test.dart';
import 'package:yuukilyrics/models/lyric_ast.dart';
import 'package:yuukilyrics/parser/lrc_parser.dart';

void main() {
  test('Parses extended LRC string correctly', () {
    String input = '{思|[1|00:03:53]し}{考|[2|00:03:74]こ[00:03:93]う}[1|00:04:13]も';
    LyricLine line = LrcParser.parseLine(input);

    expect(line.nodes.length, 4);
    
    // First node: {思|[1|00:03:53]し}
    expect(line.nodes[0] is LyricRuby, true);
    var node1 = line.nodes[0] as LyricRuby;
    expect(node1.baseText, '思');
    expect(node1.rubyNodes.length, 2);
    expect((node1.rubyNodes[0] as LyricTimeTag).type, 1);
    expect((node1.rubyNodes[0] as LyricTimeTag).time, '00:03:53');
    expect((node1.rubyNodes[1] as LyricText).text, 'し');

    // Second node: {考|[2|00:03:74]こ[00:03:93]う}
    expect(line.nodes[1] is LyricRuby, true);
    var node2 = line.nodes[1] as LyricRuby;
    expect(node2.baseText, '考');
    expect(node2.rubyNodes.length, 4);
    expect((node2.rubyNodes[0] as LyricTimeTag).type, 2);
    expect((node2.rubyNodes[0] as LyricTimeTag).time, '00:03:74');
    expect((node2.rubyNodes[1] as LyricText).text, 'こ');
    expect((node2.rubyNodes[2] as LyricTimeTag).type, null);
    expect((node2.rubyNodes[2] as LyricTimeTag).time, '00:03:93');
    expect((node2.rubyNodes[3] as LyricText).text, 'う');

    // Third node: [1|00:04:13]
    expect(line.nodes[2] is LyricTimeTag, true);
    expect((line.nodes[2] as LyricTimeTag).type, 1);
    expect((line.nodes[2] as LyricTimeTag).time, '00:04:13');

    // Fourth node: も
    expect(line.nodes[3] is LyricText, true);
    expect((line.nodes[3] as LyricText).text, 'も');
  });

  test('Top level parsing splits correctly', () {
    String input = '[1|00:04:13]も';
    LyricLine line = LrcParser.parseLine(input);
    expect(line.nodes.length, 2);
    expect(line.nodes[0] is LyricTimeTag, true);
    expect(line.nodes[1] is LyricText, true);
    expect((line.nodes[1] as LyricText).text, 'も');
  });

  test('Reconstructs LRC string correctly', () {
    String input = '{思|[1|00:03:53]し}{考|[2|00:03:74]こ[00:03:93]う}[1|00:04:13]も';
    LyricLine line = LrcParser.parseLine(input);
    expect(line.toLrcString(), input);
  });
}
