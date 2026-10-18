import 'package:flutter/widgets.dart';
import 'package:freshly_core/freshly_core.dart';

/// The same icon for a category here as on the client's category grid, so a
/// provider building their menu sees what their customers will browse.
IconData categoryIcon(ServiceCategory category) => switch (category) {
      ServiceCategory.barber => FreshlyIcons.barber,
      ServiceCategory.beard => FreshlyIcons.beard,
      ServiceCategory.scalp => FreshlyIcons.scalp,
      ServiceCategory.hair => FreshlyIcons.hair,
      ServiceCategory.braiding => FreshlyIcons.braiding,
      ServiceCategory.locs => FreshlyIcons.locs,
      ServiceCategory.extensions => FreshlyIcons.extensions,
      ServiceCategory.color => FreshlyIcons.colour,
      ServiceCategory.nails => FreshlyIcons.nails,
      ServiceCategory.makeup => FreshlyIcons.makeup,
      ServiceCategory.lashes => FreshlyIcons.lashes,
      ServiceCategory.brows => FreshlyIcons.brows,
      ServiceCategory.aesthetics => FreshlyIcons.aesthetics,
      ServiceCategory.bodyGrooming => FreshlyIcons.bodyGrooming,
      ServiceCategory.massage => FreshlyIcons.massage,
    };
