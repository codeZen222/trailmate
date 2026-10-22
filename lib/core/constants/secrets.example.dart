// 复制本文件为同目录下的 secrets.dart，然后填入你自己的 Key。
//
//   cp lib/core/constants/secrets.example.dart lib/core/constants/secrets.dart
//
// secrets.dart 已在 .gitignore 中排除，不会被提交。
// 之所以这样设计：三把第三方 Key 若写进源码推到公开仓库，任何人都能拿到并刷你的配额。

/// 阿里云百炼 API Key
/// 申请：https://bailian.console.aliyun.com/ → 右上角头像 → API-KEY 获取
const String apiKeySecret = '';

/// 高德 Web 服务 Key（地名转坐标用）
/// 申请：https://console.amap.com/dev/key/app → 创建「Web服务」类型的 Key
/// ⚠️ 必须选 Web 服务，Android SDK 类型的 Key 在这里会报 USERKEY_PLAT_NOMATCH
const String amapWebKeySecret = '';

/// 和风天气 Key 与专属 Host
/// 申请：https://dev.qweather.com/ → 项目管理 → 凭证 + 查看自己的 API Host
const String weatherApiKeySecret = '';
const String weatherApiHostSecret = '';
