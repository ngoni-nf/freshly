import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/freshly_icons.dart';
import '../theme/freshly_theme.dart';

/// The small set of building blocks every Freshly screen is assembled from.
///
/// They exist so that "a section", "a status", "nothing here yet" and "the
/// button at the bottom" look the same on every screen of both apps. A screen
/// that hand-rolls its own version is how one app ends up with four greens.

/// A section title with an optional trailing action ("See all").
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    this.padding = const EdgeInsets.fromLTRB(
        FreshlySpacing.md, 0, FreshlySpacing.xs, FreshlySpacing.sm),
    super.key,
  });

  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(title, style: text.titleLarge),
                ),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(subtitle!, style: text.bodySmall),
                  ),
              ],
            ),
          ),
          if (actionLabel != null && onAction != null)
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ),
    );
  }
}

/// The tone a [StatusPill] or [IconBadge] carries. Each maps to a fill and a
/// text colour that clear 4.5:1 against each other.
enum FreshlyTone { neutral, brand, success, warning, danger, info, dark }

class _ToneColors {
  const _ToneColors(this.fill, this.ink);
  final Color fill;
  final Color ink;

  static _ToneColors of(FreshlyTone tone, bool isDark) {
    switch (tone) {
      case FreshlyTone.brand:
      case FreshlyTone.success:
        return isDark
            ? const _ToneColors(Color(0xFF0E3A2A), FreshlyColors.mint)
            : const _ToneColors(FreshlyColors.mintSoft, FreshlyColors.mintInk);
      case FreshlyTone.warning:
        return isDark
            ? const _ToneColors(Color(0xFF3A2410), FreshlyColors.loadShedding)
            : const _ToneColors(
                FreshlyColors.loadSheddingSoft, FreshlyColors.loadSheddingInk);
      case FreshlyTone.danger:
        return isDark
            ? const _ToneColors(Color(0xFF3A1416), Color(0xFFFF8A8D))
            : const _ToneColors(FreshlyColors.crimsonSoft, Color(0xFFB4232A));
      case FreshlyTone.info:
        return isDark
            ? const _ToneColors(Color(0xFF13274A), Color(0xFF8DB7FF))
            : const _ToneColors(Color(0xFFEAF2FF), Color(0xFF1D5BC4));
      case FreshlyTone.dark:
        return const _ToneColors(FreshlyColors.obsidian, Colors.white);
      case FreshlyTone.neutral:
        return isDark
            ? const _ToneColors(Color(0xFF1C2330), Color(0xFFC3CCD8))
            : const _ToneColors(FreshlyColors.field, FreshlyColors.inkSubtle);
    }
  }
}

/// A rounded label for a state: "Confirmed", "On the way", "Backup power".
class StatusPill extends StatelessWidget {
  const StatusPill({
    required this.label,
    this.tone = FreshlyTone.neutral,
    this.icon,
    this.dense = false,
    super.key,
  });

  final String label;
  final FreshlyTone tone;
  final IconData? icon;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final colors =
        _ToneColors.of(tone, Theme.of(context).brightness == Brightness.dark);
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: dense ? 8 : 10, vertical: dense ? 3 : 5),
      decoration: BoxDecoration(
        color: colors.fill,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: dense ? 12 : 14, color: colors.ink),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: FreshlyType.style(dense ? 11 : 12,
                weight: FontWeight.w700, color: colors.ink),
          ),
        ],
      ),
    );
  }
}

/// A tinted rounded square holding an icon: category tiles, list leading
/// icons, empty states.
class IconBadge extends StatelessWidget {
  const IconBadge({
    required this.icon,
    this.tone = FreshlyTone.brand,
    this.size = 44,
    super.key,
  });

  final IconData icon;
  final FreshlyTone tone;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors =
        _ToneColors.of(tone, Theme.of(context).brightness == Brightness.dark);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colors.fill,
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Icon(icon,
          size: size * 0.48,
          color: tone == FreshlyTone.dark ? FreshlyColors.mint : colors.ink),
    );
  }
}

/// Star, score and count, at the weight a rating deserves.
class RatingLabel extends StatelessWidget {
  const RatingLabel({
    required this.rating,
    this.count,
    this.size = 13,
    this.onDark = false,
    super.key,
  });

  final double rating;
  final int? count;
  final double size;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final muted = onDark
        ? FreshlyColors.inkMuted
        : Theme.of(context).colorScheme.onSurfaceVariant;
    final ink = onDark ? Colors.white : Theme.of(context).colorScheme.onSurface;
    // A provider with no reviews yet has a rating of zero, and "0.0" reads as
    // terrible rather than new.
    final isNew = count == 0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(FreshlyIcons.star, size: size + 2, color: FreshlyColors.gold),
        const SizedBox(width: 3),
        Text(isNew ? 'New' : rating.toStringAsFixed(1),
            style:
                FreshlyType.style(size, weight: FontWeight.w700, color: ink)),
        if (count != null && !isNew)
          Text(' ($count)', style: FreshlyType.style(size, color: muted)),
      ],
    );
  }
}

/// What a provider looks like before they have uploaded a photo: their
/// initial over the brand gradient, not a grey box.
class MonogramArt extends StatelessWidget {
  const MonogramArt({
    required this.name,
    this.borderRadius = BorderRadius.zero,
    this.fontSize,
    super.key,
  });

  final String name;
  final BorderRadius borderRadius;
  final double? fontSize;

  // A handful of deep grounds, chosen by name so a provider keeps the same
  // one everywhere and a rail of new providers is not a row of clones.
  static const _grounds = [
    [Color(0xFF0B0F19), Color(0xFF1B2A3A)],
    [Color(0xFF0B0F19), Color(0xFF12342A)],
    [Color(0xFF111827), Color(0xFF2B2140)],
    [Color(0xFF0B0F19), Color(0xFF3A2A16)],
  ];

  @override
  Widget build(BuildContext context) {
    final trimmed = name.trim();
    final initial =
        trimmed.isEmpty ? 'F' : trimmed.characters.first.toUpperCase();
    final ground = _grounds[trimmed.hashCode.abs() % _grounds.length];
    return LayoutBuilder(builder: (context, box) {
      final side =
          box.biggest.shortestSide.isFinite ? box.biggest.shortestSide : 80.0;
      return DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: ground,
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              right: -side * 0.25,
              top: -side * 0.25,
              child: Container(
                width: side * 0.8,
                height: side * 0.8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: FreshlyColors.mint.withValues(alpha: 0.22),
                      width: side * 0.1),
                ),
              ),
            ),
            Center(
              child: Text(
                initial,
                style: FreshlyType.style(fontSize ?? side * 0.42,
                    weight: FontWeight.w800, color: FreshlyColors.mint),
              ),
            ),
          ],
        ),
      );
    });
  }
}

/// A round avatar: photo when there is one, otherwise the monogram.
class FreshlyAvatar extends StatelessWidget {
  const FreshlyAvatar({
    required this.name,
    this.image,
    this.size = 44,
    this.online = false,
    super.key,
  });

  final String name;

  /// The photo, already built by the caller (the apps own image caching).
  final Widget? image;
  final double size;
  final bool online;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipOval(
            child: SizedBox.expand(
              child: image ?? MonogramArt(name: name, fontSize: size * 0.42),
            ),
          ),
          if (online)
            Positioned(
              right: 0,
              bottom: 0,
              child: OnlineDot(size: size * 0.28),
            ),
        ],
      ),
    );
  }
}

class OnlineDot extends StatelessWidget {
  const OnlineDot({this.size = 12, super.key});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Available now',
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: FreshlyColors.mint,
          shape: BoxShape.circle,
          border: Border.all(
              color: Theme.of(context).colorScheme.surface,
              width: size >= 12 ? 2.5 : 2),
        ),
      ),
    );
  }
}

/// Nothing here yet — said kindly, with the one thing to do about it.
class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
    this.compact = false,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// For use inside a scrolling page rather than as the whole screen.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final body = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconBadge(
            icon: icon, size: compact ? 52 : 72, tone: FreshlyTone.neutral),
        SizedBox(height: compact ? 12 : 20),
        Text(title,
            textAlign: TextAlign.center,
            style: compact ? text.titleMedium : text.headlineSmall),
        if (message != null) ...[
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300),
            child: Text(message!,
                textAlign: TextAlign.center,
                style: text.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
        ],
        if (actionLabel != null && onAction != null) ...[
          SizedBox(height: compact ? 12 : 24),
          compact
              ? OutlinedButton(
                  style:
                      OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                  onPressed: onAction,
                  child: Text(actionLabel!),
                )
              : FilledButton(
                  style: FilledButton.styleFrom(
                      minimumSize:
                          const Size(200, FreshlySpacing.buttonHeight)),
                  onPressed: onAction,
                  child: Text(actionLabel!),
                ),
        ],
      ],
    );
    return Padding(
      padding: EdgeInsets.symmetric(
          horizontal: FreshlySpacing.lg,
          vertical: compact ? FreshlySpacing.md : FreshlySpacing.xxl),
      child: Center(child: body),
    );
  }
}

/// A shimmering placeholder in the shape of the content that is loading.
/// Holds still for anyone who has asked the OS to reduce motion.
class Skeleton extends StatefulWidget {
  const Skeleton({
    this.width,
    this.height = 16,
    this.radius = FreshlySpacing.radiusSmall,
    super.key,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? const Color(0xFF1C2330) : FreshlyColors.field;
    final glint = isDark ? const Color(0xFF263042) : const Color(0xFFF8FAFC);
    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = _controller.value * 3 - 1;
          return Container(
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.radius),
              gradient: LinearGradient(
                begin: Alignment(t - 1, 0),
                end: Alignment(t + 1, 0),
                colors: [base, glint, base],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The bar pinned to the bottom of a screen that ends in a decision: a
/// summary on the left, the action on the right (or full width).
class StickyActionBar extends StatelessWidget {
  const StickyActionBar({
    required this.child,
    this.leading,
    super.key,
  });

  /// Usually the primary button.
  final Widget child;

  /// Optional summary shown beside the action, e.g. the total.
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outline)),
        boxShadow: FreshlyShadows.floating,
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              FreshlySpacing.md, 12, FreshlySpacing.md, FreshlySpacing.md),
          child: leading == null
              ? child
              : Row(
                  children: [
                    Expanded(child: leading!),
                    const SizedBox(width: FreshlySpacing.md),
                    Flexible(child: child),
                  ],
                ),
        ),
      ),
    );
  }
}

/// The big title block that opens onboarding and form screens.
class ScreenIntro extends StatelessWidget {
  const ScreenIntro({
    required this.title,
    this.subtitle,
    this.eyebrow,
    super.key,
  });

  final String title;
  final String? subtitle;

  /// A short label above the title, e.g. "Step 2 of 4".
  final String? eyebrow;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (eyebrow != null) ...[
          Text(eyebrow!.toUpperCase(),
              style: FreshlyType.style(12,
                      weight: FontWeight.w700,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? FreshlyColors.mint
                          : FreshlyColors.mintDark)
                  .copyWith(letterSpacing: 1.2)),
          const SizedBox(height: 8),
        ],
        Semantics(
          header: true,
          child: Text(title, style: text.headlineLarge),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 8),
          Text(subtitle!, style: text.bodyLarge?.copyWith(color: muted)),
        ],
      ],
    );
  }
}

/// A grouped settings-style list inside one rounded card, with hairlines
/// between rows.
class GroupedList extends StatelessWidget {
  const GroupedList({required this.children, this.title, super.key});

  final List<Widget> children;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        rows.add(Divider(indent: 64, color: scheme.outline));
      }
      rows.add(children[i]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Text(title!.toUpperCase(),
                style: FreshlyType.style(12,
                        weight: FontWeight.w700, color: scheme.onSurfaceVariant)
                    .copyWith(letterSpacing: 1)),
          ),
        Card(child: Column(children: rows)),
      ],
    );
  }
}

/// One key–value line in a receipt or breakdown.
class LineItem extends StatelessWidget {
  const LineItem({
    required this.label,
    required this.value,
    this.emphasis = false,
    this.muted = false,
    super.key,
  });

  final String label;
  final String value;
  final bool emphasis;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = muted ? scheme.onSurfaceVariant : scheme.onSurface;
    final style = emphasis
        ? FreshlyType.style(18, weight: FontWeight.w800, color: color)
        : FreshlyType.style(15,
            weight: muted ? FontWeight.w400 : FontWeight.w500, color: color);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label, style: style)),
          const SizedBox(width: 12),
          Text(value, style: style),
        ],
      ),
    );
  }
}

/// The pill colour for a booking's state, so "Completed" is the same green
/// and "Cancelled" the same grey on every list in both apps.
FreshlyTone toneForBooking(BookingStatus status) => switch (status) {
      BookingStatus.completed => FreshlyTone.success,
      BookingStatus.cancelled ||
      BookingStatus.expired ||
      BookingStatus.draft =>
        FreshlyTone.neutral,
      BookingStatus.disputed => FreshlyTone.danger,
      BookingStatus.pendingAuth => FreshlyTone.warning,
      _ => FreshlyTone.info,
    };

/// The steps of a live booking as a row of segments: done, current, to come.
class BookingProgress extends StatelessWidget {
  const BookingProgress({required this.status, super.key});
  final BookingStatus status;

  static const _steps = [
    (BookingStatus.accepted, 'Confirmed'),
    (BookingStatus.enRoute, 'On the way'),
    (BookingStatus.arrived, 'Arrived'),
    (BookingStatus.inProgress, 'In progress'),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final current = _steps.indexWhere((s) => s.$1 == status);
    final reached = status == BookingStatus.completed ? _steps.length : current;
    return Semantics(
      label: 'Booking progress: ${status.clientLabel}',
      child: ExcludeSemantics(
        child: Column(
          children: [
            Row(
              children: [
                for (var i = 0; i < _steps.length; i++) ...[
                  if (i > 0) const SizedBox(width: 4),
                  Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      height: 6,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(3),
                        color: i <= reached
                            ? FreshlyColors.mint
                            : scheme.surfaceContainerHighest,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                for (var i = 0; i < _steps.length; i++)
                  Expanded(
                    child: Text(
                      _steps[i].$2,
                      textAlign: i == 0
                          ? TextAlign.left
                          : i == _steps.length - 1
                              ? TextAlign.right
                              : TextAlign.center,
                      style: FreshlyType.style(11,
                          weight:
                              i == current ? FontWeight.w800 : FontWeight.w500,
                          color: i == current
                              ? scheme.onSurface
                              : scheme.onSurfaceVariant),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The brand lockup in type: a mint tile holding the F, then the name. Drawn
/// rather than loaded so it is crisp at any size and needs no SVG package.
class FreshlyWordmark extends StatelessWidget {
  const FreshlyWordmark({this.size = 32, this.onDark = true, super.key});

  /// Cap height of the name, roughly.
  final double size;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final tile = size * 1.15;
    return Semantics(
      label: 'Freshly',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: tile,
              height: tile,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(tile * 0.3),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [FreshlyColors.mint, Color(0xFF00B87A)],
                ),
              ),
              child: Text('F',
                  style: FreshlyType.style(size * 0.8,
                      weight: FontWeight.w800, color: FreshlyColors.obsidian)),
            ),
            SizedBox(width: size * 0.3),
            Text('Freshly',
                style: FreshlyType.style(size,
                    weight: FontWeight.w800,
                    color: onDark ? Colors.white : FreshlyColors.ink)),
          ],
        ),
      ),
    );
  }
}

/// A market's code in a small rounded tile, in place of a flag emoji: flags
/// render inconsistently across Android skins and some show only letters.
class CountryBadge extends StatelessWidget {
  const CountryBadge({required this.code, this.size = 40, super.key});
  final String code;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: FreshlyColors.obsidian,
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Text(code.toUpperCase(),
          style: FreshlyType.style(size * 0.34,
              weight: FontWeight.w800, color: FreshlyColors.mint)),
    );
  }
}
