import 'package:flutter/widgets.dart';
import 'package:shad/shad.dart';

/// The visual foundation for the Dextero client.
///
/// Product widgets should read colors and type from [ShadTheme] and use these
/// layout constants instead of introducing one-off Material theme values.
abstract final class DexteroDesign {
  static const contentMaxWidth = 1040.0;
  static const messageMaxWidth = 720.0;
  static const compactBreakpoint = 760.0;

  static const pagePaddingCompact = EdgeInsets.fromLTRB(16, 16, 16, 12);
  static const pagePaddingRegular = EdgeInsets.fromLTRB(28, 24, 28, 20);

  static final lightTheme = ShadThemeData(
    brightness: Brightness.light,
    colorScheme: const ShadMistColorScheme.light(),
    style: ShadStyleTokens.rhea,
    radius: const BorderRadius.all(Radius.circular(12)),
  );

  static final darkTheme = ShadThemeData(
    brightness: Brightness.dark,
    colorScheme: const ShadMistColorScheme.dark(),
    style: ShadStyleTokens.rhea,
    radius: const BorderRadius.all(Radius.circular(12)),
  );

  static EdgeInsets pagePadding(double width) =>
      width < compactBreakpoint ? pagePaddingCompact : pagePaddingRegular;

  static Color success(Brightness brightness) => brightness == Brightness.dark
      ? const Color(0xff4ade80)
      : const Color(0xff15803d);

  static Color warning(Brightness brightness) => brightness == Brightness.dark
      ? const Color(0xfffbbf24)
      : const Color(0xffa16207);
}
