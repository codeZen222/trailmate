class Trip {
  final int id;
  final String destination;
  final String? coverPath;
  final DateTime startDate;
  final DateTime endDate;
  final int rating;
  final String? notes;
  final bool isCompleted;
  final DateTime createdAt;
  final DateTime updatedAt;

  Trip({
    required this.id,
    required this.destination,
    this.coverPath,
    required this.startDate,
    required this.endDate,
    this.rating = 0,
    this.notes,
    this.isCompleted = false,
    required this.createdAt,
    required this.updatedAt,
  });

  int get durationDays => endDate.difference(startDate).inDays + 1;

  /// 「进行中」的唯一判据。
  ///
  /// 【规则来自用户明确要求】设置了结束日期、且结束日期 >= 开始日期 → 已结束。
  /// 反过来，只有"根本没填结束日期"才算进行中。
  ///
  /// 我之前在这里犯过两次错，记下来免得重犯：
  ///   ① 用 `endDate == startDate` 判"没填" —— 把所有当天往返的一日行程
  ///      （济南 08-17 → 08-17）误标成进行中；
  ///   ② 用 `!isCompleted` 但创建时不写这个位 —— 老数据大量默认 false，
  ///      明明填了结束日期仍显示进行中。
  /// isCompleted 由创建/编辑页根据"用户是否真的选了结束日期"显式写入，
  /// 因此它是唯一可靠的依据。endDate 保持真实值（未填时等于出发日），
  /// 这样天数统计、成就判定、PDF 导出都不受影响。
  bool get endDateUnset => !isCompleted;

  /// 展示用的行程天数文案。
  String get daysLabel => endDateUnset ? '进行中' : '$durationDays 天';

  Trip copyWith({
    int? id,
    String? destination,
    String? coverPath,
    DateTime? startDate,
    DateTime? endDate,
    int? rating,
    String? notes,
    bool? isCompleted,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Trip(
      id: id ?? this.id,
      destination: destination ?? this.destination,
      coverPath: coverPath ?? this.coverPath,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      rating: rating ?? this.rating,
      notes: notes ?? this.notes,
      isCompleted: isCompleted ?? this.isCompleted,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'destination': destination,
    'coverPath': coverPath,
    'startDate': startDate.toIso8601String(),
    'endDate': endDate.toIso8601String(),
    'rating': rating,
    'notes': notes,
    'isCompleted': isCompleted,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory Trip.fromJson(Map<String, dynamic> json) => Trip(
    id: json['id'] as int,
    destination: json['destination'] as String,
    coverPath: json['coverPath'] as String?,
    startDate: DateTime.parse(json['startDate'] as String),
    endDate: DateTime.parse(json['endDate'] as String),
    rating: json['rating'] as int? ?? 0,
    notes: json['notes'] as String?,
    isCompleted: json['isCompleted'] as bool? ?? false,
    createdAt: DateTime.parse(json['createdAt'] as String),
    updatedAt: DateTime.parse(json['updatedAt'] as String),
  );
}