import 'package:flutter/material.dart';

import '../format.dart';
import '../models/api_types.dart';
import '../theme/tokens.dart';
import 'ol_icon.dart';

/// The tinted 29×29 (desktop) / 36×36 (mobile) file glyph tile.
class FileGlyph extends StatelessWidget {
  final FileItem? item;
  final String? name;
  final bool isDir;
  final double size;
  final double radius;
  final double iconSize;

  const FileGlyph({
    super.key,
    this.item,
    this.name,
    this.isDir = false,
    this.size = 29,
    this.radius = 8,
    this.iconSize = 15,
  });

  @override
  Widget build(BuildContext context) {
    final n = item?.name ?? name ?? '';
    final dir = item?.isDir ?? isDir;
    final kind = kindOf(n, dir);
    final tone = tileColors(toneOfKind(kind));
    final bg = context.ol.isDark ? _darkTone(kind) : tone.bg;
    final fg = context.ol.isDark ? _darkFg(kind) : tone.fg;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(radius)),
      child: Center(child: OlIcon(iconOfKind(kind), size: iconSize, color: fg, strokeWidth: 1.9)),
    );
  }

  Color _darkTone(FileKind k) {
    switch (k) {
      case FileKind.folder:
        return const Color(0xFF0E2C40);
      case FileKind.video:
        return const Color(0xFF211C3F);
      case FileKind.image:
        return const Color(0xFF3A1B27);
      case FileKind.audio:
        return const Color(0xFF0E2E2B);
      case FileKind.text:
        return const Color(0xFF33260F);
      default:
        return const Color(0xFF17293D);
    }
  }

  Color _darkFg(FileKind k) {
    switch (k) {
      case FileKind.folder:
        return const Color(0xFF7DD3FC);
      case FileKind.video:
        return const Color(0xFFB9A7FF);
      case FileKind.image:
        return const Color(0xFFFF9DB4);
      case FileKind.audio:
        return const Color(0xFF5EEAD4);
      case FileKind.text:
        return const Color(0xFFF7C873);
      default:
        return const Color(0xFF9FB3C7);
    }
  }
}

/// Placeholder "cover" used by the detail panel and mobile media rows.
/// Runtime thumbnails come from the server's `thumb` field when present.
class OlMediaThumb extends StatelessWidget {
  final double height;
  final String? title;
  final String? subtitle;
  final String? tag;
  final String? imageUrl;
  final Map<String, String>? headers;

  const OlMediaThumb({
    super.key,
    this.height = 112,
    this.title,
    this.subtitle,
    this.tag,
    this.imageUrl,
    this.headers,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(11),
      child: Container(
        height: height,
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment(-0.8, -1),
            end: Alignment(0.9, 1),
            colors: [Color(0xFF0A1526), Color(0xFF122B45), Color(0xFF0B2033)],
            stops: [0, 0.6, 1],
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (imageUrl != null)
              Image.network(
                imageUrl!,
                headers: headers,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              )
            else ...[
              Positioned(
                left: -20,
                top: -20,
                child: Container(
                  width: 130,
                  height: 130,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(colors: [Color(0x552B4C7E), Color(0x002B4C7E)]),
                  ),
                ),
              ),
              Positioned(
                right: -14,
                top: 6,
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(colors: [Color(0x4D7C5CFC), Color(0x007C5CFC)]),
                  ),
                ),
              ),
            ],
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, const Color(0xEB030A14)],
                    stops: const [0.45, 1],
                  ),
                ),
              ),
            ),
            if (tag != null)
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(color: const Color(0xFF7DD3FC), borderRadius: BorderRadius.circular(3)),
                  child: Text(tag!, style: const TextStyle(fontSize: 7.5, fontWeight: FontWeight.w900, color: Color(0xFF0B1220), letterSpacing: 0.5)),
                ),
              ),
            if (title != null)
              Positioned(
                left: 10,
                right: 10,
                bottom: 9,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (subtitle != null)
                      Text(
                        subtitle!.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 8.5, letterSpacing: 1.2, fontWeight: FontWeight.w700, color: Color(0xFFA9C2D8)),
                      ),
                    Text(
                      title!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11.5, letterSpacing: 0.2, fontWeight: FontWeight.w800, color: Colors.white),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Thin 6px usage bar with gradient fill — used by storage cards.
class OlUsageBar extends StatelessWidget {
  final double value;
  final bool dark;
  final double height;
  const OlUsageBar({super.key, required this.value, this.dark = false, this.height = 3});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: Container(
        height: height,
        color: dark ? const Color(0x38FFFFFF) : const Color(0xFFEAF0F6),
        child: FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: value.clamp(0.05, 1.0).toDouble(),
          child: Container(
            decoration: BoxDecoration(
              color: dark ? Colors.white : null,
              gradient: dark ? null : OlTokens.gradientPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
