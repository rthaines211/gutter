class FacetValue {
  final String value;
  final int count;

  const FacetValue({required this.value, required this.count});

  factory FacetValue.fromJson(Map<String, dynamic> json) {
    return FacetValue(
      value: json['value'] as String,
      count: json['count'] as int? ?? 0,
    );
  }
}
