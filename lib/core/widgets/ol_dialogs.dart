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
