# TrailMate · 旅行手账

> 走过的路，都算数。

一个**纯本地**的旅行记录 Android 应用：记下每次出发、每张照片、每笔开销，去过的地方会在自绘的中国地图上自动点亮。数据全部保存在手机 SQLite 里，不上传服务器、不用注册账号。

## 功能一览

- 🗺️ **足迹地图** — 省份按到访次数渐进点亮，可回溯飞机航线般的移动轨迹（纯 `CustomPaint` 自绘，无地图 SDK）
- 📷 **旅程与日志** — 时间线式日记，12 种心情特效，AI 辅助写图注/润色
- 💰 **旅行消费** — 按旅程记账（金额以「分」存储，求和永远精确），对悬浮小精灵说一句「午餐45」即可入账
- 🏅 **成就与年度报告** — 37 个成就，一年走的路攒成可滑动的卡片
- 🔒 **隐私优先** — 数据不出手机；匿名使用心跳可选，不含任何内容信息

## 技术栈

| 层 | 选型 |
|---|---|
| 框架 | Flutter (Dart 3) |
| 状态管理 | Riverpod |
| 数据库 | Drift (SQLite)，schema 迁移见 `lib/database/app_database.dart` |
| 地图 | 自绘（阿里 DataV.GeoAtlas 省界 GeoJSON + `china_map_painter.dart`） |
| 地理编码 | 高德 Web 服务 REST（仅地名→坐标，与渲染无关） |
| PDF / 分享海报 | pdf、printing、自绘模板三套 |

## 快速开始

```bash
# 1. 配置密钥（必需，否则无法编译——代码 import 了该文件）
cp lib/core/constants/secrets.example.dart lib/core/constants/secrets.dart
#    编辑 secrets.dart，填入你自己的 Key：
#    - apiKeySecret        阿里云百炼（OpenAI 兼容模式），AI 功能用
#    - amapWebKeySecret    高德「Web服务」类型 Key，地名转坐标用
#    - weatherApiKeySecret 和风天气 Key + Host

# 2. 拉依赖、跑起来
flutter pub get
flutter run

# 3. 打 release APK
flutter build apk --release
#    产物在 build/app/outputs/flutter-apk/app-release.apk
```

> `secrets.dart` 已被 `.gitignore` 排除，真实 Key 永远不会进版本库。
> 三个服务都有免费额度，申请入口见 `secrets.example.dart` 内注释。

## 目录结构

```
lib/
├── database/     # Drift 表定义、DAO、schema 迁移
├── models/       # 领域模型（Trip / Log / Expense / Footprint ...）
├── providers/    # Riverpod 状态层（每个业务域一个文件）
├── pages/        # 界面：首页 / 旅程 / 日志 / 足迹 / 统计 / 档案 ...
├── services/     # AI、地理编码、天气、导出、成就引擎、图片持久化
├── widgets/      # 精灵、图表、海报模板、地图画笔等复用组件
└── utils/        # 城市提取、离线坐标词表、日期格式化
test/             # 单元测试（真·内存 SQLite 验证删除级联与日期约束）
release_page/     # 下载引导页（APK 本体走 GitHub Releases，不进仓库）
```

## 安装正式版

从 [Releases](../../releases) 下载最新 `TrailMate-vX.Y.Z.apk`，手机上打开并允许「未知来源」即可。未上架应用商店，属正常提示。

## License

个人项目，暂保留所有权利（All rights reserved）。想引用或合作请开 Issue 联系。
