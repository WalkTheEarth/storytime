import 'package:storytime/sources/novel_master.dart';

void main() async {
  final s = NovelMasterSource();
  final r = await s.search('538822');
  final b = r.books.first;
  final chs = await s.chapters(b.id);
  print('chapters: ${chs.length} first=${chs.first.title}(id ${chs.first.id}) '
      'last=${chs.last.title}(id ${chs.last.id})');
  final c6 = await s.chapterContent(chs[5]);
  print('ch6: title=${c6.title} paras=${c6.paragraphs.length} '
      'head=${c6.paragraphs.first.substring(0, 40)}');
}
