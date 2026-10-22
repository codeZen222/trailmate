import 'card_style.dart';
import 'mood_type.dart';

/// 个人旅行档案。单条记录，以 JSON 形式存于 settings 表的 `user_profile` 键。
class Profile {
  const Profile({
    required this.nickname,
    this.avatarPath,
    this.photoPath,
    this.homeCity,
    this.bio,
    this.travelStyles = const [],
    this.bucketList = const [],
    this.startDate,
    this.mood,
    this.cardStyle,
    this.issueAuthority,
    this.validUntil,
    this.updatedAt,
  });

  /// 昵称（唯一必填项）。
  final String nickname;
  /// 圆形头像：用于设置页列表等处。
  final String? avatarPath;
  /// 证件照：档案卡左侧的竖版照片，与头像独立上传。
  final String? photoPath;
  final String? homeCity;
  /// 一句话签名。
  final String? bio;
  /// 旅行风格，存标签名。
  final List<String> travelStyles;
  /// 心愿目的地。
  final List<String> bucketList;
  /// 旅行起点日期，用于计算「旅行第 N 天」。
  final DateTime? startDate;
  /// 卡片粒子特效心情。
  final MoodType? mood;
  /// 档案卡配色方案存 key；null 表示用默认配色。
  final String? cardStyle;
  /// 签发机关文字；留空用默认「旅行管理局」。
  final String? issueAuthority;
  /// 有效期至；null 表示「长期」。
  final DateTime? validUntil;
  final DateTime? updatedAt;

  /// 解析后的配色方案。
  CardStyle get style => CardStyle.fromKey(cardStyle);

  /// 卡面显示的签发机关（含默认值）。
  String get displayAuthority {
    final v = (issueAuthority ?? '').trim();
    return v.isEmpty ? '旅行管理局' : v;
  }

  /// 卡面显示的有效期限，格式 YYYY.MM.DD；未设置显示「长期」。
  String get displayValidity {
    final v = validUntil;
    if (v == null) return '长期';
    final m = v.month.toString().padLeft(2, '0');
    final d = v.day.toString().padLeft(2, '0');
    return '${v.year}.$m.$d';
  }

  bool get isEmpty => nickname.trim().isEmpty;

  /// 从旅行起点到今天的天数（含首日）；未设置起点返回 null。
  int? get travelDays {
    final s = startDate;
    if (s == null) return null;
    final now = DateTime.now();
    final days = DateTime(now.year, now.month, now.day)
        .difference(DateTime(s.year, s.month, s.day))
        .inDays;
    return days < 0 ? null : days + 1;
  }

  Profile copyWith({
    String? nickname,
    String? avatarPath,
    String? photoPath,
    String? homeCity,
    String? bio,
    List<String>? travelStyles,
    List<String>? bucketList,
    DateTime? startDate,
    MoodType? mood,
    String? cardStyle,
    String? issueAuthority,
    DateTime? validUntil,
    DateTime? updatedAt,
  }) {
    return Profile(
      nickname: nickname ?? this.nickname,
      avatarPath: avatarPath ?? this.avatarPath,
      photoPath: photoPath ?? this.photoPath,
      homeCity: homeCity ?? this.homeCity,
      bio: bio ?? this.bio,
      travelStyles: travelStyles ?? this.travelStyles,
      bucketList: bucketList ?? this.bucketList,
      startDate: startDate ?? this.startDate,
      mood: mood ?? this.mood,
      cardStyle: cardStyle ?? this.cardStyle,
      issueAuthority: issueAuthority ?? this.issueAuthority,
      validUntil: validUntil ?? this.validUntil,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'nickname': nickname,
        'avatarPath': avatarPath,
        'photoPath': photoPath,
        'homeCity': homeCity,
        'bio': bio,
        'travelStyles': travelStyles,
        'bucketList': bucketList,
        'startDate': startDate?.toIso8601String(),
        'mood': mood?.key,
        'cardStyle': cardStyle,
        'issueAuthority': issueAuthority,
        'validUntil': validUntil?.toIso8601String(),
        'updatedAt': updatedAt?.toIso8601String(),
      };

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        nickname: (j['nickname'] as String?) ?? '',
        avatarPath: j['avatarPath'] as String?,
        photoPath: j['photoPath'] as String?,
        homeCity: j['homeCity'] as String?,
        bio: j['bio'] as String?,
        travelStyles: _strList(j['travelStyles']),
        bucketList: _strList(j['bucketList']),
        startDate: DateTime.tryParse(j['startDate'] as String? ?? ''),
        mood: MoodType.fromKey(j['mood'] as String?),
        cardStyle: j['cardStyle'] as String?,
        issueAuthority: j['issueAuthority'] as String?,
        validUntil: DateTime.tryParse(j['validUntil'] as String? ?? ''),
        updatedAt: DateTime.tryParse(j['updatedAt'] as String? ?? ''),
      );

  static List<String> _strList(Object? v) {
    if (v is List) {
      return v.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
    }
    return const [];
  }
}

/// 从数据库自动汇总的旅行统计，供档案卡展示。
class ProfileStats {
  const ProfileStats({
    this.cities = 0,
    this.trips = 0,
    this.totalDays = 0,
    this.photos = 0,
    this.logs = 0,
    this.achievementsUnlocked = 0,
    this.achievementsTotal = 0,
  });

  final int cities;
  final int trips;
  final int totalDays;
  final int photos;
  final int logs;
  final int achievementsUnlocked;
  final int achievementsTotal;

  static const empty = ProfileStats();
}
