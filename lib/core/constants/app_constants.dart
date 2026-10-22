const String appName = 'TrailMate';

/// 当前版本号。
///
/// 【发新版时要改这里】并且要和 Cloudflare Worker 里 version.json 的 latest 一致，
/// 否则用户会一直收到"有新版本"提示。pubspec.yaml 的 version 也建议同步更新。
const String appVersion = '1.0.1';

/// 安装包下载地址（蓝奏云）。
///
/// 【建议分享"文件夹"链接而不是单个文件链接】
/// 蓝奏云的文件夹地址在你增删文件后保持不变，这样发新版只需替换里面的文件，
/// 这个常量和已发给朋友的地址都不用改。单文件链接每传一次就换一个。
///
/// 【为什么是跳转而不是自动检测版本】GitHub / workers.dev / jsDelivr
/// 在国内均实测不可达（workers.dev 的 DNS 会被污染到 Facebook 的 IP 段），
/// 自定义域名需付费加实名审核，对当前用户规模不划算。
const String kDownloadUrl = 'https://wwatw.lanzoub.com/b01gie2zyh';

/// 蓝奏云访问密码。免费版无法关闭密码校验，所以直接显示给用户省去沟通成本。
const String kDownloadPassword = 'lzl666';

/// 腾讯问卷地址（反馈问题 + 使用感受合并在同一份里）。
/// 用户想匿名填、或不方便加好友时走这条路。
const String kSurveyUrl = 'https://wj.qq.com/s2/28234154/czec/';

const double defaultCardRadius = 15.0;
const double defaultElevation = 2.0;
const Duration defaultAnimationDuration = Duration(milliseconds: 300);
