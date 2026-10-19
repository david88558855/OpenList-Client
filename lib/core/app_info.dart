/// 客户端版本信息。
///
/// 这里是唯一来源：pubspec.yaml 的 version 必须与之保持一致（CI 的
/// 「版本号一致性」步骤会校验，避免设置页与产物版本串出现偏差）。
class AppInfo {
  const AppInfo._();

  static const version = '1.0.8';
  static const build = 9;

  static const name = 'OpenList Client';

  /// 设置页 / 关于页展示用：1.0.8 (9)
  static String get versionLabel => '$version ($build)';

  /// 侧栏页脚：OpenList Client 1.0.8
  static String get shortLabel => '$name $version';
}
