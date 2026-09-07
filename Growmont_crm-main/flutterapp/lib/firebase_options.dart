import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for use with your Firebase apps.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        return linux;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const String _projectId = String.fromEnvironment(
    'FIREBASE_PROJECT_ID',
    defaultValue: 'growmont-crm',
  );
  static const String _apiKey = String.fromEnvironment(
    'FIREBASE_API_KEY',
    defaultValue: 'AIzaSyFakeKeyForGrowmontCRMDefaultOptions',
  );
  static const String _appId = String.fromEnvironment(
    'FIREBASE_APP_ID',
    defaultValue: '1:123456789012:web:abcdef1234567890',
  );
  static const String _messagingSenderId = String.fromEnvironment(
    'FIREBASE_MESSAGING_SENDER_ID',
    defaultValue: '123456789012',
  );

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyD_xH1bbBpaufJuhohFxaOouid1P0XE8AY',
    appId: '1:925465988303:web:df80d9d56e39b962107bba',
    messagingSenderId: '925465988303',
    projectId: 'growmontcrm',
    authDomain: 'growmontcrm.firebaseapp.com',
    storageBucket: 'growmontcrm.firebasestorage.app',
    measurementId: 'G-NZQEF9QVFL',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDLwvW82PSOM_02vWkZlclQjSWxjVttok4',
    appId: '1:925465988303:android:40c1e38e2ab2cdb9107bba',
    messagingSenderId: '925465988303',
    projectId: 'growmontcrm',
    storageBucket: 'growmontcrm.firebasestorage.app',
  );
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyAi1SNfgux7hn-naYcb-AVkegRpGh8cEsA',
    appId: '1:925465988303:ios:7ad95df9e75e8c05107bba',
    messagingSenderId: '925465988303',
    projectId: 'growmontcrm',
    storageBucket: 'growmontcrm.firebasestorage.app',
    iosBundleId: 'com.growmont.growmontCrm',
  );
  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyAi1SNfgux7hn-naYcb-AVkegRpGh8cEsA',
    appId: '1:925465988303:ios:7ad95df9e75e8c05107bba',
    messagingSenderId: '925465988303',
    projectId: 'growmontcrm',
    storageBucket: 'growmontcrm.firebasestorage.app',
    iosBundleId: 'com.growmont.growmontCrm',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyD_xH1bbBpaufJuhohFxaOouid1P0XE8AY',
    appId: '1:925465988303:web:75aa687f61ea8917107bba',
    messagingSenderId: '925465988303',
    projectId: 'growmontcrm',
    authDomain: 'growmontcrm.firebaseapp.com',
    storageBucket: 'growmontcrm.firebasestorage.app',
    measurementId: 'G-1NGRVWBNFG',
  );
  static const FirebaseOptions linux = FirebaseOptions(
    apiKey: _apiKey,
    appId: _appId,
    messagingSenderId: _messagingSenderId,
    projectId: _projectId,
    storageBucket: '$_projectId.appspot.com',
  );
}
