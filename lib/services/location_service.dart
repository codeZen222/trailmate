import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

class LocationService {
  Future<Position?> getCurrentPosition() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return null;
      }
      if (permission == LocationPermission.deniedForever) return null;

      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
    } catch (e) {
      return null;
    }
  }

  Future<String?> getCityName(double latitude, double longitude) async {
    try {
      final placemarks = await placemarkFromCoordinates(latitude, longitude);
      if (placemarks.isNotEmpty) {
        return placemarks.first.locality ?? placemarks.first.administrativeArea;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// 详细位置：优先 POI 名（如"月亮湾"），再街道，最后区县级。
  ///
  /// 【为什么要改】旧实现只返回 `street`，把 `name`（POI/景区名）和
  /// `subLocality`（区）全丢了 —— 所以在烟台芝罘区月亮湾定位，
  /// 只能拿到一条路名甚至空值，用户看到的就只有"烟台市"。
  Future<String?> getAddress(double latitude, double longitude) async {
    try {
      final placemarks = await placemarkFromCoordinates(latitude, longitude);
      if (placemarks.isEmpty) return null;
      final p = placemarks.first;

      // Placemark 各字段在不同平台上可能为可空，统一按可空处理
      String clean(String? s) => (s ?? '').trim();
      // 按信息量从高到低取第一个非空的；同级的拼起来更完整
      final poi = clean(p.name);
      final street = clean(p.street);
      final sub = clean(p.subLocality);
      final thoro = clean(p.thoroughfare);
      final subThoro = clean(p.subThoroughfare);

      // 门牌号单独拼在街道后，避免"月亮湾"被吞掉
      final streetLine = [
        if (street.isNotEmpty && street != poi) street,
        if (thoro.isNotEmpty && thoro != street) thoro,
      ].join(' ');
      final withNo = subThoro.isNotEmpty && streetLine.isNotEmpty
          ? '$streetLine$subThoro号'
          : streetLine;

      for (final cand in [poi, withNo, streetLine, sub]) {
        if (cand.trim().isNotEmpty) return cand.trim();
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// 省 / 市 / 区 三段行政归属，供日志与地图做更细的地点标注。
  Future<({String? province, String? city, String? district})>
      getAdminDivisions(double latitude, double longitude) async {
    try {
      final placemarks = await placemarkFromCoordinates(latitude, longitude);
      if (placemarks.isEmpty) {
        return (province: null, city: null, district: null);
      }
      final p = placemarks.first;
      String? nz(String? s) {
        final v = (s ?? '').trim();
        return v.isEmpty ? null : v;
      }
      return (
        province: nz(p.administrativeArea),
        city: nz(p.locality),
        district: nz(p.subLocality),
      );
    } catch (_) {
      return (province: null, city: null, district: null);
    }
  }
}

/// 共享的定位服务实例（此前只在日志编辑器里有个私有 provider，
/// 补坐标功能也要用，故提到服务文件里统一暴露）。
final locationServiceProvider =
    Provider<LocationService>((ref) => LocationService());
