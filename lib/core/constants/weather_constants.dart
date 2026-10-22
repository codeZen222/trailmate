// 和风天气（QWeather）配置。
//
// 【Key 不在本文件】真实值在 secrets.dart（已被 .gitignore 排除）。
// 克隆仓库后请复制 secrets.example.dart 为 secrets.dart 并填入自己的 Key。
//
// 若留空，则回退读取「设置 → 天气服务」里用户自填的值；都没有时天气需手动选。
import 'secrets.dart';

const String weatherApiKeySettingKey = 'weather_api_key';
const String weatherApiHostSettingKey = 'weather_api_host';

/// 写死模式的天气凭据：App 开箱即用，用户无需进设置页。
const String hardcodedWeatherApiKey = weatherApiKeySecret;
const String hardcodedWeatherApiHost = weatherApiHostSecret;
