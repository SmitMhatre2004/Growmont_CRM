import 'package:flutter_test/flutter_test.dart';
import 'package:growmont_crm/core/updater/version_constants.dart';

void main() {
  group('Updater version constants & asset conventions', () {
    test('Android asset naming matches build_android_release.ps1 convention', () {
      expect(kAndroidAssetPrefix, 'growmont-');
      expect(kAndroidAssetExtension, '.apk');

      const sampleVersion = '1.0.0';
      final expectedApkName = '$kAndroidAssetPrefix$sampleVersion$kAndroidAssetExtension';
      expect(expectedApkName, 'growmont-1.0.0.apk');

      // Checksum sibling convention
      final expectedChecksumName = '$expectedApkName.sha256';
      expect(expectedChecksumName, 'growmont-1.0.0.apk.sha256');
    });

    test('Windows asset naming matches build_release.ps1 convention', () {
      expect(kInstallerAssetPrefix, 'Growmont-Setup-');
      expect(kInstallerAssetExtension, '.exe');

      const sampleVersion = '1.0.0';
      final expectedExeName = '$kInstallerAssetPrefix$sampleVersion$kInstallerAssetExtension';
      expect(expectedExeName, 'Growmont-Setup-1.0.0.exe');

      // Checksum sibling convention
      final expectedChecksumName = '$expectedExeName.sha256';
      expect(expectedChecksumName, 'Growmont-Setup-1.0.0.exe.sha256');
    });

    test('Android and Windows prefixes are distinct to avoid cross-platform collision', () {
      expect(kAndroidAssetPrefix.toLowerCase(), isNot(equals(kInstallerAssetPrefix.toLowerCase())));
      expect(kAndroidAssetExtension, isNot(equals(kInstallerAssetExtension)));
    });

    test('GitHub repository target points to dedicated release repository', () {
      expect(kGitHubRepoOwner, 'CruciaTos');
      expect(kGitHubRepoName, 'GrowmontCRM_Release');
      expect(
        kLatestReleaseApiUrl,
        'https://api.github.com/repos/CruciaTos/GrowmontCRM_Release/releases/latest',
      );
    });
  });
}
