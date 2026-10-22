import 'package:flutter/material.dart';
import '../../pages/home/home_page.dart';
import '../../pages/trip/trip_create_page.dart';
import '../../pages/trip/trip_detail_page.dart';
import '../../pages/log/log_editor_page.dart';
import '../../pages/log/log_detail_page.dart';
import '../../pages/footprint/province_map_page.dart';
import '../../pages/footprint/footprint_list_page.dart';
import '../../pages/stats/stats_page.dart';
import '../../pages/stats/achievement_page.dart';
import '../../pages/stats/year_review_page.dart';
import '../../pages/settings/settings_page.dart';
import '../../pages/share/share_card_page.dart';
import '../../pages/share/log_share_page.dart';
import '../../pages/chat/ai_chat_page.dart';
import '../../pages/profile/profile_page.dart';

class AppRouter {
  static const String home = '/';
  static const String tripCreate = '/trip/create';
  static const String tripDetail = '/trip/detail';
  static const String logEditor = '/log/editor';
  static const String logDetail = '/log/detail';
  static const String footprintMap = '/footprint/map';
  static const String footprintList = '/footprint/list';
  static const String stats = '/stats';
  static const String achievement = '/stats/achievement';
  static const String yearReview = '/stats/year-review';
  static const String settings = '/settings';
  static const String shareCard = '/share/card';
  static const String logShare = '/share/log';
  static const String aiChat = '/chat/ai';
  static const String profile = '/profile';
  static const String provinceMap = '/footprint/province-map';

  static Route<dynamic> generateRoute(RouteSettings routeSettings) {
    switch (routeSettings.name) {
      case home:
        return MaterialPageRoute(builder: (_) => const HomePage());
      case provinceMap:
        return MaterialPageRoute(builder: (_) => const ProvinceMapPage());
      case tripCreate:
        final args = routeSettings.arguments as Map<String, dynamic>?;
        return MaterialPageRoute(
          builder: (_) => TripCreatePage(tripId: args?['tripId'] as int?),
        );
      case tripDetail:
        final args = routeSettings.arguments as Map<String, dynamic>;
        return MaterialPageRoute(
          builder: (_) => TripDetailPage(tripId: args['tripId'] as int),
        );
      case logEditor:
        final args = routeSettings.arguments as Map<String, dynamic>;
        return MaterialPageRoute(
          builder: (_) => LogEditorPage(
            tripId: args['tripId'] as int,
            logId: args['logId'] as int?,
            selectedDate: args['date'] as DateTime?,
          ),
        );
      case logDetail:
        final args = routeSettings.arguments as Map<String, dynamic>;
        return MaterialPageRoute(
          builder: (_) => LogDetailPage(
            logId: args['logId'] as int,
            tripId: args['tripId'] as int,
          ),
        );
      case footprintMap:
        return MaterialPageRoute(builder: (_) => const ProvinceMapPage());
      case footprintList:
        return MaterialPageRoute(builder: (_) => const FootprintListPage());
      case stats:
        return MaterialPageRoute(builder: (_) => const StatsPage());
      case achievement:
        return MaterialPageRoute(builder: (_) => const AchievementPage());
      case yearReview:
        final args = routeSettings.arguments as Map<String, dynamic>?;
        return MaterialPageRoute(
          builder: (_) => YearReviewPage(year: args?['year'] as int?),
        );
      case settings:
        return MaterialPageRoute(builder: (_) => const SettingsPage());
      case shareCard:
        final args = routeSettings.arguments as Map<String, dynamic>;
        return MaterialPageRoute(
          builder: (_) => ShareCardPage(tripId: args['tripId'] as int),
        );
      case logShare:
        final args = routeSettings.arguments as Map<String, dynamic>;
        return MaterialPageRoute(
          builder: (_) => LogSharePage(logId: args['logId'] as int),
        );
      case aiChat:
        return MaterialPageRoute(builder: (_) => const AiChatPage());
      case profile:
        return MaterialPageRoute(builder: (_) => const ProfilePage());
      default:
        return MaterialPageRoute(builder: (_) => const HomePage());
    }
  }
}