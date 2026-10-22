class Footprint {
  final int id;
  final String cityName;
  final String country;
  final double latitude;
  final double longitude;
  final DateTime firstVisitedAt;
  final int visitCount;
  final DateTime latestVisitedAt;

  Footprint({
    required this.id,
    required this.cityName,
    required this.country,
    required this.latitude,
    required this.longitude,
    required this.firstVisitedAt,
    this.visitCount = 1,
    required this.latestVisitedAt,
  });
}