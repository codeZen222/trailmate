class Tag {
  final int id;
  final String name;
  final String? icon;

  Tag({
    required this.id,
    required this.name,
    this.icon,
  });

  String get displayName => '$icon $name';
}