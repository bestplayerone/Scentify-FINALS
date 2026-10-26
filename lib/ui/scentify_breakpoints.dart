enum ScentifyWindowSizeClass { compact, medium, expanded }

abstract final class ScentifyBreakpoints {
  static const compactMaxWidth = 600.0;
  static const expandedMinWidth = 840.0;
  static const maxContentWidth = 1360.0;

  static const catalogHorizontalInset = 32.0;
  static const catalogCrossAxisSpacing = 12.0;
  static const catalogMinimumTileWidth = 200.0;
  static const catalogMaximumTileWidth = 280.0;
  static const catalogTileHeightOffset = 154.0;
  static const catalogMaximumColumns = 5;

  static ScentifyWindowSizeClass sizeClassForWidth(double width) {
    if (width < compactMaxWidth) {
      return ScentifyWindowSizeClass.compact;
    }
    if (width < expandedMinWidth) {
      return ScentifyWindowSizeClass.medium;
    }
    return ScentifyWindowSizeClass.expanded;
  }

  static int catalogColumnCount(double availableWidth) {
    final tileAreaWidth = availableWidth - catalogHorizontalInset;
    final fittingColumns =
        ((tileAreaWidth + catalogCrossAxisSpacing) /
                (catalogMinimumTileWidth + catalogCrossAxisSpacing))
            .floor();
    return fittingColumns.clamp(2, catalogMaximumColumns).toInt();
  }

  static double catalogGridWidth(double availableWidth, int columnCount) {
    final maximumTileAreaWidth =
        columnCount * catalogMaximumTileWidth +
        catalogCrossAxisSpacing * (columnCount - 1);
    final maximumGridWidth = catalogHorizontalInset + maximumTileAreaWidth;
    return availableWidth.clamp(0, maximumGridWidth).toDouble();
  }

  static double catalogTileWidth(double availableWidth, int columnCount) {
    final gaps = catalogCrossAxisSpacing * (columnCount - 1);
    final tileWidth =
        (availableWidth - catalogHorizontalInset - gaps) / columnCount;
    return tileWidth.clamp(0, catalogMaximumTileWidth).toDouble();
  }
}
