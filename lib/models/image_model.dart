class ImageModel {
  final int id;
  final int logId;
  final String filePath;
  final String? aiDescription;
  final double? latitude;
  final double? longitude;
  final int orderIndex;
  final DateTime createdAt;

  ImageModel({
    required this.id,
    required this.logId,
    required this.filePath,
    this.aiDescription,
    this.latitude,
    this.longitude,
    this.orderIndex = 0,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'logId': logId,
    'filePath': filePath,
    'aiDescription': aiDescription,
    'latitude': latitude,
    'longitude': longitude,
    'orderIndex': orderIndex,
    'createdAt': createdAt.toIso8601String(),
  };

  factory ImageModel.fromJson(Map<String, dynamic> json) => ImageModel(
    id: json['id'] as int,
    logId: json['logId'] as int,
    filePath: json['filePath'] as String,
    aiDescription: json['aiDescription'] as String?,
    latitude: (json['latitude'] as num?)?.toDouble(),
    longitude: (json['longitude'] as num?)?.toDouble(),
    orderIndex: json['orderIndex'] as int? ?? 0,
    createdAt: DateTime.parse(json['createdAt'] as String),
  );
}