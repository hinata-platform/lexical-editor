// The page's header, and the one part of this example that is only dressing.
//
// It exists because the example is also the published demo, and the first
// thing a visitor sees should say what they are looking at. Everything below
// it is the editor.
import 'package:flutter/material.dart';

/// The dark app bar with the project's mark, name and compatibility.
///
/// Sized like a normal [AppBar] so the page below it does not have to know
/// anything about it; the coloured hairline under it is the same one the
/// repository's banner ends with.
class BrandAppBar extends StatelessWidget implements PreferredSizeWidget {
  /// Creates the header, with [actions] on its right.
  const BrandAppBar({super.key, this.actions = const []});

  /// Buttons on the trailing edge.
  final List<Widget> actions;

  /// The ink the logo is drawn on.
  static const Color ink = Color(0xFF0B1220);

  /// The blue the caret in the logo is drawn in.
  static const Color accent = Color(0xFF4DA3FF);

  static const double _bar = 60;
  static const double _hairline = 3;

  @override
  Size get preferredSize => const Size.fromHeight(_bar + _hairline);

  @override
  Widget build(BuildContext context) {
    // Below this the subtitle and the badge are dropped rather than squeezed:
    // a header that wraps is worse than a header that says less.
    final wide = MediaQuery.sizeOf(context).width > 620;
    return AppBar(
      toolbarHeight: _bar,
      backgroundColor: ink,
      foregroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleSpacing: 16,
      flexibleSpace: const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [ink, Color(0xFF16233A)],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
        ),
      ),
      title: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: Image.asset(
              'assets/logo.png',
              width: 34,
              height: 34,
              filterQuality: FilterQuality.medium,
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'lexical_editor_flutter',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                    color: Colors.white,
                  ),
                ),
                if (wide)
                  Text(
                    'Lexical, portiert auf Dart und Flutter',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.3,
                      color: Colors.white.withValues(alpha: 0.66),
                    ),
                  ),
              ],
            ),
          ),
          if (wide) ...[const SizedBox(width: 14), const _CompatBadge()],
        ],
      ),
      actions: actions,
      bottom: const PreferredSize(
        preferredSize: Size.fromHeight(_hairline),
        child: _Hairline(),
      ),
    );
  }
}

/// The version of Lexical the wire format is verified against.
class _CompatBadge extends StatelessWidget {
  const _CompatBadge();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: BrandAppBar.accent.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: BrandAppBar.accent.withValues(alpha: 0.42)),
    ),
    child: const Text(
      'kompatibel mit Lexical 0.48',
      style: TextStyle(
        fontSize: 11,
        fontFamily: 'monospace',
        color: BrandAppBar.accent,
      ),
    ),
  );
}

/// The banner's colour strip, three pixels of it.
class _Hairline extends StatelessWidget {
  const _Hairline();

  @override
  Widget build(BuildContext context) => const SizedBox(
    height: 3,
    child: Row(
      children: [
        Expanded(flex: 4, child: ColoredBox(color: Color(0xFF4DA3FF))),
        Expanded(flex: 3, child: ColoredBox(color: Color(0xFF9B7DF7))),
        Expanded(flex: 3, child: ColoredBox(color: Color(0xFF4ED6A0))),
      ],
    ),
  );
}
