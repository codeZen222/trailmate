package com.trailmate.trailmate

import io.flutter.embedding.android.FlutterActivity

// 之前这里有一段反射调用 com.amap.api.maps.MapsInitializer 的隐私合规初始化，
// 用于满足高德地图 SDK 的上架要求。足迹地图已改为纯 CustomPaint 自绘、
// 高德 SDK 已从 Gradle 移除，那段代码只剩每冷启动一次 ClassNotFound 的开销，故删除。
class MainActivity : FlutterActivity()
