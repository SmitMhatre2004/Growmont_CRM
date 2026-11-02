import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// An avatar monogram: a 100-shade fill under 700-shade initials.
///
/// The colour is derived from the name, not from where the avatar happens to
/// appear, so a person keeps the same colour in the clients table, in their
/// detail header and in the sidebar. Circles are the one place a full radius
/// is allowed.
class Monogram extends StatelessWidget {
  const Monogram({
    super.key,
    required this.name,
    this.size = AppSizing.avatarMd,
    this.imageUrl,
    this.fallback = '?',
  });

  /// The name the initials and the colour are both taken from.
  final String name;

  /// Diameter. Initials scale with it so a 32 and a 56 read the same.
  final double size;

  /// A photo, when there is one. The monogram is what shows until it loads.
  final String? imageUrl;

  /// Shown when [name] has no usable letters.
  final String fallback;

  /// Up to two initials: the first letter of the first and last words.
  static String initialsOf(String name, {String fallback = '?'}) {
    final words = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return fallback;
    if (words.length == 1) return words.first[0].toUpperCase();
    return (words.first[0] + words.last[0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final (fill, ink) = AppChart.monogramFor(name);
    final image = imageUrl;

    return CircleAvatar(
      radius: size / 2,
      backgroundColor: fill,
      foregroundImage: (image != null && image.isNotEmpty)
          ? NetworkImage(image)
          : null,
      child: Text(
        initialsOf(name, fallback: fallback),
        style: TextStyle(
          fontFamily: AppTypography.text,
          // Initials hold their proportion at every avatar size.
          fontSize: size * 0.36,
          fontWeight: FontWeight.w700,
          color: ink,
          height: 1,
        ),
      ),
    );
  }
}
