// The handful of colours and shapes the demo is drawn from.
//
// Kept in one place because this example is also the published demo: the
// editor should look like a product someone would ship, and a product looks
// coherent when every surface, border and hover state comes from the same
// short list rather than from whatever each widget felt like.
import 'package:flutter/material.dart';

/// The demo's palette.
///
/// Named rather than inlined: an example that is also a demo gets read as a
/// starting point, and a wall of hex literals is not one.
abstract final class Palette {
  /// The page behind the cards.
  static const Color canvas = Color(0xFFF2F4F8);

  /// Cards, and the editor's writing surface.
  static const Color surface = Color(0xFFFFFFFF);

  /// The toolbar strip, a shade off the writing surface below it.
  static const Color bar = Color(0xFFFBFCFD);

  /// Hairlines: card edges, toolbar underline, group separators.
  static const Color line = Color(0xFFE3E7EF);

  /// A separator inside a group of buttons, lighter than a card edge.
  static const Color lineSoft = Color(0xFFECEFF5);

  /// Body text.
  static const Color text = Color(0xFF1B2333);

  /// Labels, icons at rest, secondary lines.
  static const Color muted = Color(0xFF5C6679);

  /// Placeholder text and disabled icons.
  static const Color faint = Color(0xFF9AA3B4);

  /// Links, the caret, an engaged button.
  static const Color accent = Color(0xFF2E7DE9);

  /// The dark the brand header is drawn on.
  static const Color brand = Color(0xFF0B1220);
}

/// Radii, so a card, a button and a popover agree with each other.
abstract final class Radii {
  static const BorderRadius card = BorderRadius.all(Radius.circular(14));
  static const BorderRadius control = BorderRadius.all(Radius.circular(8));
  static const BorderRadius pill = BorderRadius.all(Radius.circular(999));
}

/// The shadow a card sits on: two very soft layers rather than one dark one,
/// which is what keeps it from looking like a dialog.
const List<BoxShadow> cardShadow = [
  BoxShadow(color: Color(0x0A101828), blurRadius: 2, offset: Offset(0, 1)),
  BoxShadow(color: Color(0x0D101828), blurRadius: 18, offset: Offset(0, 6)),
];

/// The theme the demo runs on.
ThemeData demoTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: ColorScheme.fromSeed(
      seedColor: Palette.accent,
      surface: Palette.surface,
    ),
    scaffoldBackgroundColor: Palette.canvas,
  );

  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: Palette.text,
      displayColor: Palette.text,
    ),
    dividerTheme: const DividerThemeData(
      color: Palette.line,
      space: 1,
      thickness: 1,
    ),
    iconTheme: const IconThemeData(color: Palette.muted, size: 20),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: Palette.muted,
        minimumSize: const Size(34, 34),
        padding: EdgeInsets.zero,
        shape: const RoundedRectangleBorder(borderRadius: Radii.control),
      ),
    ),
    tooltipTheme: const TooltipThemeData(
      waitDuration: Duration(milliseconds: 400),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      isDense: true,
      border: OutlineInputBorder(borderRadius: Radii.control),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: Palette.surface,
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: Radii.card),
    ),
    popupMenuTheme: const PopupMenuThemeData(
      color: Palette.surface,
      elevation: 3,
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Palette.brand,
      contentTextStyle: TextStyle(color: Colors.white),
    ),
  );
}

/// The monospace stack the inspector and code blocks are set in.
const List<String> monoFallback = [
  'SF Mono',
  'Menlo',
  'Consolas',
  'DejaVu Sans Mono',
  'monospace',
];
