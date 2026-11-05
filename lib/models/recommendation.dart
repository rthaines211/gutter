class Recommendation {
  final String? seriesId;
  final String title;
  final String? creator;
  final String reasoning;
  final bool isInLibrary;

  const Recommendation({
    required this.seriesId,
    required this.title,
    required this.creator,
    required this.reasoning,
    required this.isInLibrary,
  });

  factory Recommendation.fromJson(Map<String, dynamic> json) {
    return Recommendation(
      seriesId: json['series_id'] as String?,
      title: json['title'] as String,
      creator: json['creator'] as String?,
      reasoning: json['reasoning'] as String,
      isInLibrary: json['is_in_library'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'series_id': seriesId,
        'title': title,
        'creator': creator,
        'reasoning': reasoning,
        'is_in_library': isInLibrary,
      };
}
