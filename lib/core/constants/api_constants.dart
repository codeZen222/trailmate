// AI 接口默认配置（阿里云百炼 OpenAI 兼容模式）。
//
// 【Key 不在本文件】真实密钥在 secrets.dart —— 它被 .gitignore 排除，
// 不会进入版本库。克隆本仓库后请复制 secrets.example.dart 为 secrets.dart
// 并填入自己的 Key，否则编译会因找不到常量而失败。
import 'secrets.dart';

const String defaultApiBaseUrl =
    'https://ws-fqns0gni8kjy6u4t.cn-beijing.maas.aliyuncs.com/compatible-mode/v1';

/// 文本模型：写作润色 / 智能标签 / 每日总结 / 对话助手
const String defaultModel = 'qwen-flash';

/// 视觉模型：图片描述（多模态）。
/// 该端点没有 qwen3-vl-flash（会 404 Model not exist），实测可用的是 qwen3-vl-plus；
/// AiService.describeImage 里还配了自动回退列表。
const String defaultVisionModel = 'qwen3-vl-plus';

/// 写死模式的 API Key：App 开箱即用，用户无需进设置页。
/// 留空时回退读取「设置 → AI 设置」里用户自填的值。
const String hardcodedApiKey = apiKeySecret;
