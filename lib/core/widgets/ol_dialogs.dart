import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'ol_controls.dart';
import 'ol_icon.dart';

class OlMenuItem {
  final String label;
  final String icon;
  final VoidCallback? onTap;
  final bool danger;
  final bool divider;

  const OlMenuItem(this.label, this.icon, this.onTap, {this.danger = false, this.divider = false});
}

/// A7 · Android 长按操作面板。
///
/// 结构按设计稿：顶部拖拽条 → 「已选择 N 个项目 / 取消」→ 文件行 →
/// 四个高频动作（播放 / 下载 / 分享 / 收藏）→ 次级动作列表（含删除）。
/// 桌面端继续用 [showOlMenu] 的右键浮层，两端动作集合一致。
Future<void> showOlActionSheet(
  BuildContext context, {
  required int count,
  required String title,
  required String subtitle,
  required Widget leading,
  required List<OlMenuItem> quick,
  required List<OlMenuItem> items,
}) async {
  final p = context.ol;
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x5707111D),
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) {
      void run(OlMenuItem item) {
        Navigator.of(sheetContext).pop();
        item.onTap?.call();
      }

      final maxHeight = MediaQuery.sizeOf(sheetContext).height * 0.86;
      return Container(
        // v2.4：内容超过一屏（动作多 + 字体放大）时必须可滚动，
        // 否则溢出会裁掉下半部分，看起来像"点了没反应"。
        constraints: BoxConstraints(maxHeight: maxHeight),
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        ),
        padding: EdgeInsets.fromLTRB(14, 8, 14, 18 + MediaQuery.paddingOf(sheetContext).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(color: p.line, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(
                children: [
                  Text(
                    count > 1 ? '已选择 $count 个项目' : '已选择 1 个项目',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: p.ink),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.of(sheetContext).pop(),
                    child: Text('取消', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: OlTokens.sky700)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.fromLTRB(2, 4, 2, 12),
                      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.line2))),
                      child: Row(
                        children: [
                          leading,
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: p.ink),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: p.ink4),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        children: [
                          for (final item in quick)
                            Expanded(
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => run(item),
                                child: Column(
                                  children: [
                                    Container(
                                      width: 42,
                                      height: 42,
                                      decoration: BoxDecoration(
                                        color: item.danger ? const Color(0xFFFFF1F3) : const Color(0xFFF1F8FC),
                                        borderRadius: BorderRadius.circular(13),
                                      ),
                                      child: Center(
                                        child: OlIcon(
                                          item.icon,
                                          size: 17,
                                          color: item.danger ? const Color(0xFFD92D4B) : const Color(0xFF3D7E9E),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      item.label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: p.ink2),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    for (final item in items)
                      InkWell(
                        onTap: () => run(item),
                        child: Container(
                          height: 46,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(border: Border(top: BorderSide(color: p.line2))),
                          child: Row(
                            children: [
                              OlIcon(item.icon, size: 16, color: item.danger ? const Color(0xFFE06B82) : p.ink3),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  item.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: item.danger ? const Color(0xFFD92D4B) : p.ink2,
                                  ),
                                ),
                              ),
                              OlIcon('chev-r', size: 14, color: p.ink4),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

Future<void> showOlMenu(BuildContext context, {required Offset position, required List<OlMenuItem> items}) async {
  final p = context.ol;
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
  final selected = await showMenu<int>(
    context: context,
    color: p.card,
    elevation: 18,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: p.line)),
    position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx + 1, position.dy + 1),
    items: [
      for (var i = 0; i < items.length; i++)
        PopupMenuItem<int>(
          value: i,
          height: 34,
          padding: EdgeInsets.zero,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 5),
            child: Row(
              children: [
                OlIcon(items[i].icon, size: 13, color: items[i].danger ? const Color(0xFFD92D4B) : p.ink3),
                const SizedBox(width: 8),
                Text(
                  items[i].label,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: items[i].danger ? const Color(0xFFD92D4B) : p.ink2,
                  ),
                ),
              ],
            ),
          ),
        ),
    ],
  );
  if (selected != null && overlay != null) {
    final item = items[selected];
    item.onTap?.call();
  }
}

void olToast(BuildContext context, String message, {bool error = false}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: error ? const Color(0xFF3A1520) : const Color(0xFF0D1B2A),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      duration: Duration(seconds: error ? 4 : 2),
      content: Row(
        children: [
          OlIcon(error ? 'alert' : 'check', size: 14, color: error ? const Color(0xFFFDA4AF) : const Color(0xFF5EEAD4)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message, style: const TextStyle(fontSize: 11.5, color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    ),
  );
}

class _OlDialogShell extends StatelessWidget {
  final Widget child;
  const _OlDialogShell({required this.child});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        width: 380,
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: p.line),
          boxShadow: const [BoxShadow(color: Color(0x330B1622), blurRadius: 40, offset: Offset(0, 18))],
        ),
        child: child,
      ),
    );
  }
}

class _DialogHeader extends StatelessWidget {
  final String title;
  final String? message;
  final String icon;

  const _DialogHeader({required this.title, required this.icon, this.message});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(color: p.isDark ? const Color(0xFF12202F) : const Color(0xFFEAF8FE), borderRadius: BorderRadius.circular(9)),
              child: Center(child: OlIcon(icon, size: 14, color: OlTokens.sky700)),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: p.ink)),
            ),
          ],
        ),
        if (message != null) ...[
          const SizedBox(height: 10),
          Text(message!, style: TextStyle(fontSize: 11.5, height: 1.65, color: p.ink3)),
        ],
      ],
    );
  }
}

/// Single-line (or multiline) prompt. Returns the entered string or null.
Future<String?> olPrompt(
  BuildContext context, {
  required String title,
  String? message,
  String hint = '',
  String initial = '',
  String confirm = '确定',
  String icon = 'edit',
  bool obscure = false,
  int maxLines = 1,
}) async {
  final controller = TextEditingController(text: initial);
  final result = await showDialog<String>(
    context: context,
    barrierColor: const Color(0x59091424),
    builder: (dialogContext) {
      final p = dialogContext.ol;
      return _OlDialogShell(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DialogHeader(title: title, icon: icon, message: message),
            const SizedBox(height: 14),
            OlField(
              controller: controller,
              icon: icon,
              hint: hint,
              obscure: obscure,
              autofocus: true,
              maxLines: maxLines,
              onSubmitted: (v) => Navigator.of(dialogContext).pop(v),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                GestureDetector(
                  onTap: () => Navigator.of(dialogContext).pop(),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    child: Text('取消', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: p.ink3)),
                  ),
                ),
                const SizedBox(width: 6),
                OlPrimaryButton(label: confirm, onTap: () => Navigator.of(dialogContext).pop(controller.text)),
              ],
            ),
          ],
        ),
      );
    },
  );
  controller.dispose();
  return result;
}

Future<bool> olConfirm(
  BuildContext context, {
  required String title,
  required String message,
  String confirm = '确定',
  bool danger = false,
  String icon = 'alert',
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierColor: const Color(0x59091424),
    builder: (dialogContext) {
      final p = dialogContext.ol;
      return _OlDialogShell(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DialogHeader(title: title, icon: icon, message: message),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                GestureDetector(
                  onTap: () => Navigator.of(dialogContext).pop(false),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    child: Text('取消', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: p.ink3)),
                  ),
                ),
                const SizedBox(width: 6),
                if (danger)
                  OlDangerButton(label: confirm, icon: 'trash', onTap: () => Navigator.of(dialogContext).pop(true))
                else
                  OlPrimaryButton(label: confirm, onTap: () => Navigator.of(dialogContext).pop(true)),
              ],
            ),
          ],
        ),
      );
    },
  );
  return result ?? false;
}

/// Rounded 26px top sheet used by the Android action panel (A7).
Future<T?> olSheet<T>(
  BuildContext context, {
  required Widget child,
  bool isScrollControlled = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x57071117),
    builder: (sheetContext) {
      final p = sheetContext.ol;
      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheetContext).bottom),
        child: Container(
          decoration: BoxDecoration(
            color: p.card,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
            boxShadow: const [BoxShadow(color: Color(0x33071117), blurRadius: 48, offset: Offset(0, -18))],
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(color: p.isDark ? const Color(0xFF243A52) : const Color(0xFFE3EBF3), borderRadius: BorderRadius.circular(99)),
                ),
                Flexible(child: child),
              ],
            ),
          ),
        ),
      );
    },
  );
}
