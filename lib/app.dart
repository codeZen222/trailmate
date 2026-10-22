import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/app_background.dart';
import 'core/theme/theme_provider.dart';
import 'providers/settings_provider.dart';
import 'core/router/app_router.dart';
import 'core/constants/app_constants.dart';
import 'providers/database_provider.dart';
import 'providers/footprint_provider.dart';
import 'services/amap_geocoding_service.dart';
import 'services/analytics_service.dart';
import 'services/footprint_geo_refresh.dart';
import 'services/trip_flags_repair.dart';
import 'services/orphan_data_repair.dart';
import 'services/footprint_normalizer.dart';
import 'providers/sprite_provider.dart';
import 'widgets/sprite/sprite_overlay.dart';

/// 启动初始化只做一次（回填坐标 + 重算成就 + 心跳 + 检查更新）。
bool _bootstrapped = false;

class TrailMateApp extends ConsumerWidget {
  const TrailMateApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final appTheme = ref.watch(appThemeProvider);
    final spriteObserver = ref.watch(spriteRouteObserverProvider);

    if (!_bootstrapped) {
      _bootstrapped = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final db = ref.read(databaseProvider);
        // 0) 回填老旅程的 isCompleted（早期从未写入，全默认 false）
        await repairTripCompletionFlags(db);
        // 0.5) 清理旧版本删除旅程留下的孤儿日志/消费/图片（外键此前未生效）
        await repairOrphanData(db);
        // 1) 先用离线词表回填（免费、即时）
        await db.backfillFootprintCoords();
        // 2) 区县级足迹并入所属地级市（"济阳"->"济南"），去掉重复城市点
        await normalizeFootprintCities(db);
        // 3) 坐标一律以高德 Web 服务为准重查覆盖：既补 (0,0)，
        //    也修"泰山→台湾"这类看起来有值其实错到上千公里的脏数据。
        //    内部串行限速 + 结果持久缓存，第二次运行几乎零请求。
        unawaited(FootprintGeoRefresh(
          db,
          ref.read(amapGeocodingProvider),
        ).run().then((_) => ref.invalidate(footprintListProvider)));
        await db.checkAchievements();
        // 4) 匿名使用心跳：每天最多一次，失败静默，不阻塞启动
        unawaited(AnalyticsService(db).pingToday());
        // 【已移除】启动时静默检查更新 —— 版本接口在国内不可达，
        // 每次冷启只会白白超时一次。改为设置页手动跳转下载页。
      });
    }

    return MaterialApp(
      title: appName,
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: buildLightTheme(appTheme),
      darkTheme: buildDarkTheme(appTheme),
      onGenerateRoute: AppRouter.generateRoute,
      navigatorObservers: [spriteObserver],
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, contextChild) {
        final brightness = themeMode == ThemeMode.system
            ? MediaQuery.platformBrightnessOf(context)
            : (themeMode == ThemeMode.dark ? Brightness.dark : Brightness.light);
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness:
                themeMode == ThemeMode.dark ? Brightness.light : Brightness.dark,
          ),
          // 层次：插画背景 → SpriteOverlay(页面) → 精灵
          child: AppBackground(
            theme: appTheme,
            brightness: brightness,
            style: ref.watch(backgroundProvider),
            child: SpriteOverlay(child: contextChild!),
          ),
        );
      },
    );
  }
}
