import '../models/chapter.dart';
import '../models/comic_info.dart';

class ReaderChapter {
  final int pageNum;
  final String title;
  final bool editable; // false = ComicInfo, true = user-placed
  final String? id; // user chapter id; null for ComicInfo

  const ReaderChapter({
    required this.pageNum,
    required this.title,
    required this.editable,
    this.id,
  });
}

/// Merge ComicInfo chapters (editable=false) and user chapters (editable=true),
/// sorted ascending by pageNum. On a page collision the user chapter wins.
List<ReaderChapter> mergeChapters({
  required List<ComicInfoChapter> comicInfo,
  required List<Chapter> user,
}) {
  final byPage = <int, ReaderChapter>{};
  for (final c in comicInfo) {
    byPage[c.page] = ReaderChapter(
      pageNum: c.page,
      title: c.title,
      editable: false,
    );
  }
  for (final c in user) {
    byPage[c.pageNum] = ReaderChapter(
      pageNum: c.pageNum,
      title: c.title,
      editable: true,
      id: c.id,
    );
  }
  final out = byPage.values.toList()
    ..sort((a, b) => a.pageNum.compareTo(b.pageNum));
  return out;
}

/// Title of the chapter [page] falls in: the last chapter starting at or
/// before it, else null. [chapters] must be sorted ascending, as
/// [mergeChapters] returns them.
String? chapterTitleAt(List<ReaderChapter> chapters, int page) {
  String? title;
  for (final c in chapters) {
    if (c.pageNum > page) break;
    title = c.title;
  }
  return title;
}
