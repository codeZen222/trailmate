class Location {
  final int id;
  final int logId;
  final double latitude;
  final double longitude;
  final String? cityName;
  final String? placeName;
  final String? address;

  Location({
    required this.id,
    required this.logId,
    required this.latitude,
    required this.longitude,
    this.cityName,
    this.placeName,
    this.address,
  });
}