class LibraryFilter {
  final String sort;
  final String order;
  final String status;
  final String query;
  final String? publisher;
  final String? genre;
  final String? writer;
  final String? penciller;
  final int? yearMin;
  final int? yearMax;

  const LibraryFilter({
    this.sort = 'name',
    this.order = 'asc',
    this.status = 'all',
    this.query = '',
    this.publisher,
    this.genre,
    this.writer,
    this.penciller,
    this.yearMin,
    this.yearMax,
  });

  LibraryFilter copyWith({
    String? sort,
    String? order,
    String? status,
    String? query,
    String? publisher,
    String? genre,
    String? writer,
    String? penciller,
    int? yearMin,
    int? yearMax,
    bool clearPublisher = false,
    bool clearGenre = false,
    bool clearWriter = false,
    bool clearPenciller = false,
    bool clearYearMin = false,
    bool clearYearMax = false,
  }) {
    return LibraryFilter(
      sort: sort ?? this.sort,
      order: order ?? this.order,
      status: status ?? this.status,
      query: query ?? this.query,
      publisher: clearPublisher ? null : (publisher ?? this.publisher),
      genre: clearGenre ? null : (genre ?? this.genre),
      writer: clearWriter ? null : (writer ?? this.writer),
      penciller: clearPenciller ? null : (penciller ?? this.penciller),
      yearMin: clearYearMin ? null : (yearMin ?? this.yearMin),
      yearMax: clearYearMax ? null : (yearMax ?? this.yearMax),
    );
  }

  bool get isDefault =>
      sort == 'name' &&
      order == 'asc' &&
      status == 'all' &&
      query.isEmpty &&
      publisher == null &&
      genre == null &&
      writer == null &&
      penciller == null &&
      yearMin == null &&
      yearMax == null;

  int get activeFilterCount {
    int count = 0;
    if (publisher != null) count++;
    if (genre != null) count++;
    if (writer != null) count++;
    if (penciller != null) count++;
    if (yearMin != null) count++;
    if (yearMax != null) count++;
    return count;
  }

  String get sortLabel {
    switch (sort) {
      case 'unread':
        return 'Unread';
      case 'recent':
        return 'Recently Added';
      case 'recently_read':
        return 'Recently Read';
      case 'publisher':
        return 'Publisher';
      case 'year':
        return 'Year';
      case 'issue_count':
        return 'Issue Count';
      case 'unread_count':
        return 'Unread Count';
      case 'progress':
        return 'Progress';
      default:
        return 'Name';
    }
  }
}
