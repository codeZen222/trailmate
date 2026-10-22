/// 路径上的一个点（来自日志的 GPS 定位记录）。
class RoutePoint {
  const RoutePoint(this.latitude, this.longitude, this.city);

  final double latitude;
  final double longitude;
  final String city;

  /// 同城不同点仍要保留，所以用坐标做去重键而不是城市名。
  String get key => '$latitude,$longitude';
}

/// 一次旅程的真实移动路径（按日志日期顺序）。
///
/// 【为什么按旅程分段而不是一条大线】
/// 把所有城市按"首次到访时间"串起来毫无意义——「洛阳→泰安→济阳」
/// 是三次独立出行，不是一条路线。分段着色才能看出"每次怎么走的"。
class TripRoute {
  const TripRoute({
    required this.tripId,
    required this.destination,
    required this.startDate,
    required this.points,
  });

  final int tripId;
  final String destination;
  final DateTime startDate;
  final List<RoutePoint> points;

  bool get drawable => points.length >= 2;
  int get year => startDate.year;
}
