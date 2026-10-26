import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

abstract final class ScentifyColors {
  static const background = Color(0xFFF7F8FA);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceMuted = Color(0xFFF1F3F5);
  static const ink = Color(0xFF17202A);
  static const muted = Color(0xFF66717C);
  static const faint = Color(0xFF87919B);
  static const brassInk = Color(0xFFC9444B);
  static const border = Color(0xFFE4E8EC);
  static const champagne = Color(0xFFE85B63);
  static const champagneSoft = Color(0xFFFFE6E7);
  static const gold = Color(0xFFF27F7D);
  static const blush = Color(0xFFFFE9EC);
  static const sage = Color(0xFFE5F3EC);
  static const sand = Color(0xFFFFF0DD);
  static const smoke = Color(0xFFEAF1F7);
  static const plum = Color(0xFFF1EAF5);
  static const success = Color(0xFF27845D);
  static const successSoft = Color(0xFFE6F3EB);
  static const danger = Color(0xFFC5414E);
  static const dangerSoft = Color(0xFFFCE7EA);
}

abstract final class ScentifySpace {
  static const x1 = 4.0;
  static const x2 = 8.0;
  static const x3 = 12.0;
  static const x4 = 16.0;
  static const x5 = 20.0;
  static const x6 = 24.0;
  static const x8 = 32.0;
  static const x10 = 40.0;
  static const x12 = 48.0;
}

abstract final class ScentifyRadius {
  static const small = 10.0;
  static const medium = 14.0;
  static const large = 18.0;
  static const extraLarge = 24.0;
  static const pill = 999.0;
}

abstract final class ScentifyShadows {
  static const subtle = <BoxShadow>[
    BoxShadow(color: Color(0x0A111114), blurRadius: 12, offset: Offset(0, 4)),
  ];

  static const card = <BoxShadow>[
    BoxShadow(color: Color(0x0D111114), blurRadius: 18, offset: Offset(0, 7)),
  ];

  static const floating = <BoxShadow>[
    BoxShadow(color: Color(0x1A151512), blurRadius: 28, offset: Offset(0, 10)),
  ];
}

abstract final class ScentifyTypography {
  static const fontFamily = 'Montserrat';
  static const displayFontFamily = fontFamily;

  static const display = TextStyle(
    fontFamily: displayFontFamily,
    fontSize: 32,
    height: 1.1,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.8,
  );

  static const title = TextStyle(
    fontFamily: displayFontFamily,
    fontSize: 25,
    height: 1.16,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.4,
  );

  static const sectionTitle = TextStyle(
    fontFamily: displayFontFamily,
    fontSize: 20,
    height: 1.25,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.2,
  );

  static const body = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    height: 1.45,
    fontWeight: FontWeight.w400,
  );

  static const supporting = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    height: 1.4,
    fontWeight: FontWeight.w400,
  );

  static const caption = TextStyle(
    fontFamily: fontFamily,
    fontSize: 12,
    height: 1.35,
    fontWeight: FontWeight.w500,
  );

  static const label = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w600,
  );

  static const metadata = TextStyle(
    fontFamily: fontFamily,
    fontSize: 12,
    height: 1.35,
    fontWeight: FontWeight.w500,
  );

  static const overline = TextStyle(
    fontFamily: fontFamily,
    fontSize: 12,
    height: 1.2,
    letterSpacing: 0.8,
    fontWeight: FontWeight.w700,
  );
}

@immutable
class ScentifyThemeColors extends ThemeExtension<ScentifyThemeColors> {
  const ScentifyThemeColors({
    required this.canvas,
    required this.paper,
    required this.ink,
    required this.muted,
    required this.faint,
    required this.field,
    required this.placeholder,
    required this.placeholderLine,
    required this.border,
    required this.primaryAction,
    required this.darkSurface,
    required this.tobacco,
    required this.brassInk,
    required this.softGold,
    required this.olive,
    required this.success,
    required this.danger,
    required this.selected,
    required this.cartBackground,
    required this.cartSurface,
    required this.cartAccent,
  });

  final Color canvas;
  final Color paper;
  final Color ink;
  final Color muted;
  final Color faint;
  final Color field;
  final Color placeholder;
  final Color placeholderLine;
  final Color border;
  final Color primaryAction;
  final Color darkSurface;
  final Color tobacco;
  final Color brassInk;
  final Color softGold;
  final Color olive;
  final Color success;
  final Color danger;
  final Color selected;
  final Color cartBackground;
  final Color cartSurface;
  final Color cartAccent;

  static ScentifyThemeColors of(BuildContext context) =>
      Theme.of(context).extension<ScentifyThemeColors>() ??
      ScentifyTheme._lightColors;

  Color resolveLightColor(Color color) {
    if (color == ScentifyColors.background) return canvas;
    if (color == ScentifyColors.surface) return paper;
    if (color == ScentifyColors.surfaceMuted) return field;
    if (color == ScentifyColors.ink) return ink;
    if (color == ScentifyColors.muted) return muted;
    if (color == ScentifyColors.faint) return faint;
    if (color == ScentifyColors.brassInk) return brassInk;
    if (color == ScentifyColors.border) return border;
    if (color == ScentifyColors.champagne) return softGold;
    if (color == ScentifyColors.champagneSoft) return selected;
    if (color == ScentifyColors.gold) return softGold;
    if (color == ScentifyColors.success) return success;
    if (color == ScentifyColors.danger) return danger;
    if (color == ScentifyColors.blush ||
        color == ScentifyColors.sage ||
        color == ScentifyColors.sand ||
        color == ScentifyColors.smoke ||
        color == ScentifyColors.plum) {
      return canvas == ScentifyColors.background ? color : field;
    }
    if (color == const Color(0xFFE9E8E2)) return placeholder;
    if (color == const Color(0xFFD5D4CE)) return placeholderLine;
    if (color == const Color(0xFF202A33)) return darkSurface;
    if (color == ScentifyColors.successSoft ||
        color == ScentifyColors.dangerSoft) {
      return canvas == ScentifyColors.background ? color : field;
    }
    return color;
  }

  @override
  ScentifyThemeColors copyWith({
    Color? canvas,
    Color? paper,
    Color? ink,
    Color? muted,
    Color? faint,
    Color? field,
    Color? placeholder,
    Color? placeholderLine,
    Color? border,
    Color? primaryAction,
    Color? darkSurface,
    Color? tobacco,
    Color? brassInk,
    Color? softGold,
    Color? olive,
    Color? success,
    Color? danger,
    Color? selected,
    Color? cartBackground,
    Color? cartSurface,
    Color? cartAccent,
  }) => ScentifyThemeColors(
    canvas: canvas ?? this.canvas,
    paper: paper ?? this.paper,
    ink: ink ?? this.ink,
    muted: muted ?? this.muted,
    faint: faint ?? this.faint,
    field: field ?? this.field,
    placeholder: placeholder ?? this.placeholder,
    placeholderLine: placeholderLine ?? this.placeholderLine,
    border: border ?? this.border,
    primaryAction: primaryAction ?? this.primaryAction,
    darkSurface: darkSurface ?? this.darkSurface,
    tobacco: tobacco ?? this.tobacco,
    brassInk: brassInk ?? this.brassInk,
    softGold: softGold ?? this.softGold,
    olive: olive ?? this.olive,
    success: success ?? this.success,
    danger: danger ?? this.danger,
    selected: selected ?? this.selected,
    cartBackground: cartBackground ?? this.cartBackground,
    cartSurface: cartSurface ?? this.cartSurface,
    cartAccent: cartAccent ?? this.cartAccent,
  );

  @override
  ScentifyThemeColors lerp(covariant ScentifyThemeColors? other, double t) {
    if (other == null) {
      return this;
    }

    return ScentifyThemeColors(
      canvas: Color.lerp(canvas, other.canvas, t)!,
      paper: Color.lerp(paper, other.paper, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      faint: Color.lerp(faint, other.faint, t)!,
      field: Color.lerp(field, other.field, t)!,
      placeholder: Color.lerp(placeholder, other.placeholder, t)!,
      placeholderLine: Color.lerp(placeholderLine, other.placeholderLine, t)!,
      border: Color.lerp(border, other.border, t)!,
      primaryAction: Color.lerp(primaryAction, other.primaryAction, t)!,
      darkSurface: Color.lerp(darkSurface, other.darkSurface, t)!,
      tobacco: Color.lerp(tobacco, other.tobacco, t)!,
      brassInk: Color.lerp(brassInk, other.brassInk, t)!,
      softGold: Color.lerp(softGold, other.softGold, t)!,
      olive: Color.lerp(olive, other.olive, t)!,
      success: Color.lerp(success, other.success, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      selected: Color.lerp(selected, other.selected, t)!,
      cartBackground: Color.lerp(cartBackground, other.cartBackground, t)!,
      cartSurface: Color.lerp(cartSurface, other.cartSurface, t)!,
      cartAccent: Color.lerp(cartAccent, other.cartAccent, t)!,
    );
  }
}

abstract final class ScentifyTheme {
  static const _lightColors = ScentifyThemeColors(
    canvas: ScentifyColors.background,
    paper: ScentifyColors.surface,
    ink: ScentifyColors.ink,
    muted: ScentifyColors.muted,
    faint: ScentifyColors.faint,
    field: ScentifyColors.surfaceMuted,
    placeholder: Color(0xFFE9E8E2),
    placeholderLine: Color(0xFFD5D4CE),
    border: ScentifyColors.border,
    primaryAction: Color(0xFFC9444B),
    darkSurface: Color(0xFF202A33),
    tobacco: ScentifyColors.brassInk,
    brassInk: ScentifyColors.brassInk,
    softGold: ScentifyColors.champagneSoft,
    olive: Color(0xFF367B5D),
    success: ScentifyColors.success,
    danger: ScentifyColors.danger,
    selected: ScentifyColors.champagneSoft,
    cartBackground: ScentifyColors.background,
    cartSurface: ScentifyColors.surface,
    cartAccent: ScentifyColors.ink,
  );

  static const _darkColors = ScentifyThemeColors(
    canvas: Color(0xFF111820),
    paper: Color(0xFF1C2630),
    ink: Color(0xFFF2F5F7),
    muted: Color(0xFFB6C0C9),
    faint: Color(0xFF95A0AB),
    field: Color(0xFF25313B),
    placeholder: Color(0xFF202A34),
    placeholderLine: Color(0xFF45525E),
    border: Color(0xFF394753),
    primaryAction: Color(0xFFF07178),
    darkSurface: Color(0xFF0B1118),
    tobacco: Color(0xFFFFA0A3),
    brassInk: Color(0xFFFF858C),
    softGold: Color(0xFF512D34),
    olive: Color(0xFF83C99F),
    success: Color(0xFF8BD9AA),
    danger: Color(0xFFFF9CA5),
    selected: Color(0xFF48272E),
    cartBackground: Color(0xFF111820),
    cartSurface: Color(0xFF1C2630),
    cartAccent: Color(0xFFF07178),
  );

  static ThemeData light() => _build(_lightColors, Brightness.light);

  static ThemeData dark() => _build(_darkColors, Brightness.dark);

  static ThemeData _build(ScentifyThemeColors colors, Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: ScentifyColors.champagne,
          brightness: brightness,
          surface: colors.paper,
        ).copyWith(
          primary: colors.primaryAction,
          onPrimary: isDark ? colors.canvas : colors.paper,
          secondary: colors.softGold,
          onSecondary: isDark ? colors.canvas : colors.ink,
          tertiary: colors.olive,
          onTertiary: isDark ? colors.canvas : colors.paper,
          error: colors.danger,
          onError: isDark ? colors.canvas : colors.paper,
          surface: colors.paper,
          onSurface: colors.ink,
          surfaceContainerLowest: colors.canvas,
          surfaceContainerLow: colors.canvas,
          surfaceContainer: colors.paper,
          surfaceContainerHigh: colors.field,
          surfaceContainerHighest: colors.field,
          outline: colors.border,
          outlineVariant: colors.placeholderLine,
        );
    final textTheme = const TextTheme().copyWith(
      displayLarge: ScentifyTypography.display.copyWith(color: colors.ink),
      headlineSmall: ScentifyTypography.title.copyWith(color: colors.ink),
      titleLarge: ScentifyTypography.sectionTitle.copyWith(color: colors.ink),
      titleMedium: ScentifyTypography.label.copyWith(color: colors.ink),
      bodyLarge: ScentifyTypography.body.copyWith(color: colors.ink),
      bodyMedium: ScentifyTypography.supporting.copyWith(color: colors.muted),
      bodySmall: ScentifyTypography.metadata.copyWith(color: colors.muted),
      labelLarge: ScentifyTypography.label.copyWith(color: colors.ink),
      labelMedium: ScentifyTypography.metadata.copyWith(color: colors.muted),
      labelSmall: ScentifyTypography.overline.copyWith(color: colors.brassInk),
    );

    return ThemeData(
      useMaterial3: true,
      fontFamily: ScentifyTypography.fontFamily,
      fontFamilyFallback: const ['sans-serif'],
      brightness: brightness,
      canvasColor: colors.canvas,
      cardColor: colors.paper,
      dialogTheme: DialogThemeData(backgroundColor: colors.paper),
      scaffoldBackgroundColor: colors.canvas,
      colorScheme: scheme,
      textTheme: textTheme,
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        backgroundColor: colors.paper,
        elevation: 0,
        indicatorColor: colors.selected,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ScentifyRadius.small),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 23,
            color: states.contains(WidgetState.selected)
                ? (isDark ? colors.primaryAction : ScentifyColors.champagne)
                : colors.muted,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => ScentifyTypography.caption.copyWith(
            color: states.contains(WidgetState.selected)
                ? colors.brassInk
                : colors.muted,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
          ),
        ),
      ),
      dividerColor: colors.border,
      splashFactory: InkSparkle.splashFactory,
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,
      extensions: <ThemeExtension<dynamic>>[colors],
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.paper,
        hintStyle: ScentifyTypography.body.copyWith(color: colors.muted),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: ScentifySpace.x4,
          vertical: ScentifySpace.x3,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ScentifyRadius.medium),
          borderSide: BorderSide(color: colors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ScentifyRadius.medium),
          borderSide: BorderSide(color: colors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ScentifyRadius.medium),
          borderSide: BorderSide(color: colors.primaryAction, width: 1.4),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(48, 52),
          backgroundColor: colors.primaryAction,
          foregroundColor: isDark ? colors.canvas : colors.paper,
          disabledBackgroundColor: colors.border,
          disabledForegroundColor: colors.faint,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ScentifyRadius.medium),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 52),
          foregroundColor: colors.ink,
          side: BorderSide(color: colors.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ScentifyRadius.medium),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: colors.primaryAction,
        inactiveTrackColor: colors.border,
        thumbColor: colors.primaryAction,
        overlayColor: colors.primaryAction.withValues(alpha: 0.12),
        showValueIndicator: ShowValueIndicator.onDrag,
      ),
    );
  }
}

String formatPeso(int value) {
  final negative = value < 0;
  final digits = value.abs().toString();
  final result = StringBuffer();
  for (var index = 0; index < digits.length; index++) {
    if (index > 0 && (digits.length - index) % 3 == 0) {
      result.write(',');
    }
    result.write(digits[index]);
  }
  return '${negative ? '-' : ''}₱$result';
}

String pluralized(int count, String singular, [String? plural]) =>
    '$count ${count == 1 ? singular : (plural ?? '${singular}s')}';

String shortOrderNumber(String id) {
  final normalized = id.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
  if (normalized.length <= 6) {
    return normalized.toUpperCase();
  }
  return normalized.substring(normalized.length - 6).toUpperCase();
}

class ScentifyCard extends StatelessWidget {
  const ScentifyCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(ScentifySpace.x4),
    this.color,
    this.radius = ScentifyRadius.large,
    this.shadow = false,
    this.border = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final double radius;
  final bool shadow;
  final bool border;

  @override
  Widget build(BuildContext context) {
    final colors = ScentifyThemeColors.of(context);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color == null ? colors.paper : colors.resolveLightColor(color!),
        borderRadius: BorderRadius.circular(radius),
        border: border ? Border.all(color: colors.border) : null,
        boxShadow: shadow ? ScentifyShadows.card : null,
      ),
      child: child,
    );
  }
}

class ScentifySectionHeader extends StatelessWidget {
  const ScentifySectionHeader({
    super.key,
    required this.title,
    this.onSeeAll,
    this.seeAllLabel = 'See all',
  });

  final String title;
  final VoidCallback? onSeeAll;
  final String seeAllLabel;

  @override
  Widget build(BuildContext context) {
    final colors = ScentifyThemeColors.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: ScentifyTypography.sectionTitle.copyWith(color: colors.ink),
          ),
        ),
        if (onSeeAll != null)
          TextButton(
            onPressed: onSeeAll,
            style: TextButton.styleFrom(
              minimumSize: const Size(48, 48),
              padding: const EdgeInsets.symmetric(horizontal: ScentifySpace.x2),
              foregroundColor: colors.ink,
            ),
            child: Text(seeAllLabel),
          ),
      ],
    );
  }
}

class ScentifySelectableChip extends StatelessWidget {
  const ScentifySelectableChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.leading,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final colors = ScentifyThemeColors.of(context);
    return Semantics(
      button: true,
      selected: selected,
      child: ScentifyPressScale(
        child: Material(
          color: selected ? colors.selected : colors.paper,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ScentifyRadius.small),
            side: BorderSide(
              color: selected
                  ? (Theme.of(context).brightness == Brightness.dark
                        ? colors.primaryAction
                        : ScentifyColors.brassInk)
                  : colors.border,
            ),
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(ScentifyRadius.small),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: ScentifySpace.x4,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (leading != null) ...[
                      leading!,
                      const SizedBox(width: ScentifySpace.x2),
                    ],
                    Text(
                      label,
                      style: ScentifyTypography.caption.copyWith(
                        color: colors.ink,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ScentifyPrimaryButton extends StatelessWidget {
  const ScentifyPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.trailing,
    this.haptic = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Widget? trailing;
  final bool haptic;

  @override
  Widget build(BuildContext context) {
    return ScentifyPressScale(
      enabled: onPressed != null,
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: onPressed == null
              ? null
              : () {
                  if (haptic) {
                    HapticFeedback.lightImpact();
                  }
                  onPressed!();
                },
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18),
                const SizedBox(width: ScentifySpace.x2),
              ],
              Flexible(child: Text(label, textAlign: TextAlign.center)),
              if (trailing != null) ...[
                const SizedBox(width: ScentifySpace.x2),
                trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class ScentifySecondaryButton extends StatelessWidget {
  const ScentifySecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: icon == null ? const SizedBox.shrink() : Icon(icon, size: 18),
        label: Text(label),
      ),
    );
  }
}

class ScentifyRatingRow extends StatelessWidget {
  const ScentifyRatingRow({
    super.key,
    required this.rating,
    required this.reviewCount,
    this.compact = false,
  });

  final double rating;
  final int reviewCount;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = ScentifyThemeColors.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.star_rounded,
          size: compact ? 14 : 17,
          color: colors.brassInk,
        ),
        const SizedBox(width: ScentifySpace.x1),
        Text(
          rating.toStringAsFixed(1),
          style: ScentifyTypography.caption.copyWith(
            color: colors.ink,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: ScentifySpace.x1),
        Text('($reviewCount)', style: ScentifyTypography.caption),
      ],
    );
  }
}

class ScentifyPriceText extends StatelessWidget {
  const ScentifyPriceText(this.value, {super.key, this.style, this.textAlign});

  final int value;
  final TextStyle? style;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    return Text(
      formatPeso(value),
      textAlign: textAlign,
      style:
          style ??
          ScentifyTypography.body.copyWith(
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
    );
  }
}

/// A data-agnostic product-card shell. Screens supply existing catalog data
/// and image widgets; the component does not create product data of its own.
class ScentifyProductCard extends StatelessWidget {
  const ScentifyProductCard({
    super.key,
    required this.image,
    required this.brand,
    required this.name,
    required this.price,
    required this.size,
    required this.genderLabel,
    required this.isFavorite,
    required this.onTap,
    required this.onFavorite,
    this.rating,
    this.reviewCount,
    this.onQuickAdd,
    this.imageTint = ScentifyColors.surfaceMuted,
  });

  final Widget image;
  final String brand;
  final String name;
  final int price;
  final String size;
  final String genderLabel;
  final bool isFavorite;
  final VoidCallback onTap;
  final VoidCallback onFavorite;
  final double? rating;
  final int? reviewCount;
  final VoidCallback? onQuickAdd;
  final Color imageTint;

  @override
  Widget build(BuildContext context) {
    final showRating = rating != null && reviewCount != null;
    return ScentifyPressScale(
      child: Material(
        color: ScentifyThemeColors.of(context).canvas,
        borderRadius: BorderRadius.circular(ScentifyRadius.small),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(ScentifyRadius.small),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(ScentifyRadius.small),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AspectRatio(
                  aspectRatio: 1,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Container(
                          padding: const EdgeInsets.all(ScentifySpace.x2),
                          decoration: BoxDecoration(
                            color: ScentifyThemeColors.of(context)
                                .resolveLightColor(imageTint),
                            borderRadius: BorderRadius.circular(
                              ScentifyRadius.small,
                            ),
                          ),
                          child: Center(child: image),
                        ),
                      ),
                      Positioned(
                        top: ScentifySpace.x2,
                        right: ScentifySpace.x2,
                        child: ScentifyIconButton(
                          icon: isFavorite
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          tooltip: isFavorite
                              ? 'Remove $name from wishlist'
                              : 'Add $name to wishlist',
                          selected: isFavorite,
                          filled: false,
                          onPressed: onFavorite,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        brand,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ScentifyTypography.caption.copyWith(
                          color: ScentifyThemeColors.of(context).muted,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: ScentifyTypography.label.copyWith(
                          fontSize: 15,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: ScentifySpace.x2,
                        runSpacing: ScentifySpace.x2,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: ScentifyThemeColors.of(context).field,
                              borderRadius: BorderRadius.circular(
                                ScentifyRadius.pill,
                              ),
                            ),
                            child: Text(
                              genderLabel,
                              style: ScentifyTypography.caption.copyWith(
                                fontSize: 12,
                                color: ScentifyThemeColors.of(context).muted,
                              ),
                            ),
                          ),
                          Text(size, style: ScentifyTypography.caption),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: ScentifyPriceText(
                              price,
                              style: ScentifyTypography.body.copyWith(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (showRating)
                            ScentifyRatingRow(
                              rating: rating!,
                              reviewCount: reviewCount!,
                              compact: true,
                            ),
                        ],
                      ),
                      if (onQuickAdd != null) ...[
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 48,
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: onQuickAdd,
                            icon: const Icon(
                              Icons.shopping_bag_outlined,
                              size: 17,
                            ),
                            label: const Text('Add to Cart'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ScentifyEmptyState extends StatelessWidget {
  const ScentifyEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colors = ScentifyThemeColors.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Padding(
          padding: const EdgeInsets.all(ScentifySpace.x6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: colors.selected,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: colors.primaryAction, size: 30),
              ),
              const SizedBox(height: ScentifySpace.x4),
              Text(
                title,
                textAlign: TextAlign.center,
                style: ScentifyTypography.title.copyWith(color: colors.ink),
              ),
              const SizedBox(height: ScentifySpace.x2),
              Text(
                message,
                textAlign: TextAlign.center,
                style: ScentifyTypography.body.copyWith(color: colors.muted),
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: ScentifySpace.x5),
                SizedBox(
                  width: 220,
                  child: ScentifyPrimaryButton(
                    label: actionLabel!,
                    onPressed: onAction,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class ScentifySkeleton extends StatelessWidget {
  const ScentifySkeleton({
    super.key,
    required this.width,
    required this.height,
    this.radius = ScentifyRadius.medium,
  });

  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: ScentifyThemeColors.of(context).field,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

class ScentifySizeSelectorCard extends StatelessWidget {
  const ScentifySizeSelectorCard({
    super.key,
    required this.label,
    required this.price,
    required this.stockLabel,
    required this.selected,
    required this.available,
    required this.onTap,
  });

  final String label;
  final int price;
  final String stockLabel;
  final bool selected;
  final bool available;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = ScentifyThemeColors.of(context);
    return Semantics(
      button: true,
      selected: selected,
      enabled: available,
      child: AnimatedContainer(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: selected ? colors.selected : colors.paper,
          borderRadius: BorderRadius.circular(ScentifyRadius.medium),
          border: Border.all(
            color: selected ? colors.primaryAction : colors.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(ScentifyRadius.medium),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 78),
            child: Padding(
              padding: const EdgeInsets.all(ScentifySpace.x2),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    style: ScentifyTypography.caption.copyWith(
                      color: available ? colors.ink : colors.faint,
                    ),
                  ),
                  const SizedBox(height: 2),
                  ScentifyPriceText(
                    price,
                    style: ScentifyTypography.body.copyWith(
                      fontWeight: FontWeight.w700,
                      color: available ? colors.ink : colors.faint,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    stockLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ScentifyTypography.caption.copyWith(
                      fontSize: 12,
                      color: available ? colors.muted : colors.danger,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ScentifyIconButton extends StatelessWidget {
  const ScentifyIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.filled = true,
    this.badgeCount = 0,
    this.selected = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool filled;
  final int badgeCount;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = ScentifyThemeColors.of(context);
    return SizedBox(
      width: 48,
      height: 48,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: IconButton(
              onPressed: onPressed,
              tooltip: tooltip,
              style: IconButton.styleFrom(
                backgroundColor: filled ? colors.paper : null,
                foregroundColor: selected ? colors.primaryAction : colors.ink,
                side: filled ? BorderSide(color: colors.border) : null,
              ),
              icon: Icon(icon, size: 21),
            ),
          ),
          if (badgeCount > 0)
            Positioned(
              right: -1,
              top: -1,
              child: AnimatedSwitcher(
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 220),
                transitionBuilder: (child, animation) => ScaleTransition(
                  scale: CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutBack,
                  ),
                  child: child,
                ),
                child: Container(
                  key: ValueKey(badgeCount),
                  constraints: const BoxConstraints(
                    minWidth: 20,
                    minHeight: 20,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.softGold,
                    borderRadius: BorderRadius.circular(ScentifyRadius.pill),
                    border: Border.all(color: colors.paper, width: 1.5),
                  ),
                  child: Text(
                    badgeCount > 99 ? '99+' : '$badgeCount',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ).copyWith(color: colors.ink),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class ScentifyPressScale extends StatefulWidget {
  const ScentifyPressScale({
    super.key,
    required this.child,
    this.enabled = true,
  });

  final Widget child;
  final bool enabled;

  @override
  State<ScentifyPressScale> createState() => _ScentifyPressScaleState();
}

class _ScentifyPressScaleState extends State<ScentifyPressScale>
    with SingleTickerProviderStateMixin {
  late final _scale = AnimationController.unbounded(vsync: this, value: 1);
  static const _spring = SpringDescription(
    mass: 1,
    stiffness: 400,
    damping: 40,
  );
  var _pressed = false;
  int? _pointer;

  void _setPressed(bool pressed) {
    if (_pressed == pressed) return;
    setState(() => _pressed = pressed);
    _retarget();
  }

  void _retarget() {
    if (MediaQuery.disableAnimationsOf(context)) {
      _scale.stop();
      _scale.value = 1;
      return;
    }
    final target = _pressed ? 0.97 : 1.0;
    if ((_scale.value - target).abs() < 0.0001) {
      _scale.stop();
      _scale.value = target;
      return;
    }
    // Retarget from the presentation value and preserve velocity on reversal.
    _scale.animateWith(
      SpringSimulation(_spring, _scale.value, target, _scale.velocity),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _retarget();
  }

  @override
  void didUpdateWidget(covariant ScentifyPressScale oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) {
      _pointer = null;
      _pressed = false;
      _retarget();
    }
  }

  @override
  void dispose() {
    _scale.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: widget.enabled
          ? (event) {
              if (_pointer != null) return;
              _pointer = event.pointer;
              _setPressed(true);
            }
          : null,
      onPointerMove: widget.enabled
          ? (event) {
              if (event.pointer != _pointer) return;
              final box = context.findRenderObject()! as RenderBox;
              _setPressed(
                (Offset.zero & box.size)
                    .inflate(10)
                    .contains(box.globalToLocal(event.position)),
              );
            }
          : null,
      onPointerUp: widget.enabled
          ? (event) {
              if (event.pointer != _pointer) return;
              _pointer = null;
              _setPressed(false);
            }
          : null,
      onPointerCancel: widget.enabled
          ? (event) {
              if (event.pointer != _pointer) return;
              _pointer = null;
              _setPressed(false);
            }
          : null,
      child: AnimatedBuilder(
        animation: _scale,
        builder: (context, child) => Transform.scale(
          scale: _scale.value,
          child: Opacity(opacity: _pressed ? 0.86 : 1, child: child),
        ),
        child: widget.child,
      ),
    );
  }
}
