import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Adds the SIL Open Font License texts of the bundled fonts to Flutter's
/// licence registry, so they appear on the standard licences page.
void registerFontLicenses() {
  const fonts = <String, String>{
    'Manrope': 'assets/fonts/OFL-Manrope.txt',
    'Schibsted Grotesk': 'assets/fonts/OFL-SchibstedGrotesk.txt',
    'Inter': 'assets/fonts/OFL-Inter.txt',
    'Plus Jakarta Sans': 'assets/fonts/OFL-PlusJakartaSans.txt',
  };
  LicenseRegistry.addLicense(() async* {
    for (final entry in fonts.entries) {
      try {
        final text = await rootBundle.loadString(entry.value);
        yield LicenseEntryWithLineBreaks([entry.key], text);
      } catch (_) {
        // A missing licence file must never break the licences page.
      }
    }
  });
}
