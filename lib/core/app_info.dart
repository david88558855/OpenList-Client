/// 客户端版本信息。
///
/// 这里是唯一来源：pubspec.yaml 的 version 必须与之保持一致（CI 的
/// 「版本号一致性」步骤会校验，避免设置页与产物版本串出现偏差）。
class AppInfo {
  const AppInfo._();

  static const version = '1.0.11';
  static const build = 12;

  static const name = 'OpenList Client';

  /// 设置页 / 关于页展示用：1.0.11 (12)
  static String get versionLabel => '$version ($build)';

  /// 侧栏页脚：OpenList Client 1.0.11
  static String get shortLabel => '$name $version';

  /// 服务端版本串的短形式。
  ///
  /// OpenList 的 /api/public/settings 会返回形如
  /// `dev (Commit: unknown) - Frontend: rolling - Build at: unknown` 的长串，
  /// 直接塞进列表行会把标题挤成竖排（v2.3 修复）。这里只保留第一段，
  /// 并截到 18 个字符。
  static String shortVersion(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) return '—';
    // 先按换行 / 破折号 / 括号切断，只取「主版本」那一段。
    var head = value.split(RegExp(r'[\r\n]')).first;
    head = head.split(RegExp(r'\s+-\s+')).first;
    head = head.split(' (').first.trim();
    if (head.isEmpty) head = value;
    if (head.length > 18) head = '${head.substring(0, 17)}…';
    return head;
  }
}
