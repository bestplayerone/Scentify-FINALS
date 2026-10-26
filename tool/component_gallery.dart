import 'package:flutter/material.dart';
import 'package:scentify/ui/scentify_design_system.dart';

void main() => runApp(const _ComponentGalleryApp());

class _ComponentGalleryApp extends StatelessWidget {
  const _ComponentGalleryApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ScentifyTheme.light(),
      home: const _ComponentGallery(),
    );
  }
}

class _ComponentGallery extends StatelessWidget {
  const _ComponentGallery();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(ScentifySpace.x4),
          children: [
            Text('Gallery Air', style: ScentifyTypography.display),
            const SizedBox(height: ScentifySpace.x1),
            Text('Component specimen', style: ScentifyTypography.overline),
            const SizedBox(height: ScentifySpace.x6),
            const ScentifySectionHeader(title: 'Buttons and chips'),
            const SizedBox(height: ScentifySpace.x3),
            const ScentifyPrimaryButton(
              label: 'Add to Cart  •  ₱0',
              icon: Icons.shopping_bag_outlined,
              onPressed: _noop,
            ),
            const SizedBox(height: ScentifySpace.x2),
            const ScentifySecondaryButton(
              label: 'View full details',
              onPressed: _noop,
            ),
            const SizedBox(height: ScentifySpace.x3),
            Wrap(
              spacing: ScentifySpace.x2,
              runSpacing: ScentifySpace.x2,
              children: const [
                ScentifySelectableChip(
                  label: 'All',
                  selected: true,
                  onTap: _noop,
                ),
                ScentifySelectableChip(
                  label: 'Women',
                  selected: false,
                  onTap: _noop,
                ),
                ScentifySelectableChip(
                  label: 'Unisex',
                  selected: false,
                  onTap: _noop,
                ),
              ],
            ),
            const SizedBox(height: ScentifySpace.x6),
            const ScentifySectionHeader(title: 'Product card'),
            const SizedBox(height: ScentifySpace.x3),
            Center(
              child: SizedBox(
                width: 248,
                child: ScentifyProductCard(
                  imageTint: ScentifyColors.sage,
                  image: const Icon(
                    Icons.local_florist_outlined,
                    size: 72,
                    color: ScentifyColors.ink,
                  ),
                  brand: 'Brand',
                  name: 'Product name',
                  price: 0,
                  size: '50ml',
                  genderLabel: 'UNISEX',
                  isFavorite: false,
                  onTap: _noop,
                  onFavorite: _noop,
                  onQuickAdd: _noop,
                ),
              ),
            ),
            const SizedBox(height: ScentifySpace.x6),
            const ScentifySectionHeader(title: 'Selectors and states'),
            const SizedBox(height: ScentifySpace.x3),
            const Row(
              children: [
                Expanded(
                  child: ScentifySizeSelectorCard(
                    label: '50ml',
                    price: 0,
                    stockLabel: 'Selected',
                    selected: true,
                    available: true,
                    onTap: _noop,
                  ),
                ),
                SizedBox(width: ScentifySpace.x2),
                Expanded(
                  child: ScentifySizeSelectorCard(
                    label: '100ml',
                    price: 0,
                    stockLabel: 'Available',
                    selected: false,
                    available: true,
                    onTap: _noop,
                  ),
                ),
              ],
            ),
            const SizedBox(height: ScentifySpace.x4),
            const Row(
              children: [
                ScentifyRatingRow(rating: 4.8, reviewCount: 120),
                SizedBox(width: ScentifySpace.x3),
                ScentifyPriceText(0),
              ],
            ),
            const SizedBox(height: ScentifySpace.x6),
            const ScentifyEmptyState(
              icon: Icons.favorite_border_rounded,
              title: 'Empty state',
              message: 'A calm, helpful space for missing content.',
              actionLabel: 'Explore',
              onAction: _noop,
            ),
          ],
        ),
      ),
    );
  }
}

void _noop() {}
