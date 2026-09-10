import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:growmont_crm/core/local/sync_engine.dart';
import 'package:growmont_crm/core/providers.dart';
import 'package:growmont_crm/features/auth/auth_provider.dart';
import 'package:growmont_crm/models/user.dart';

class _TestAuthNotifier extends AuthNotifier {
  _TestAuthNotifier(this._initialState);
  final AuthState _initialState;

  @override
  AuthState build() => _initialState;

  void setUser(AppUser? user) {
    state = state.copyWith(user: user, isLoading: false, clearUser: user == null);
  }
}

void main() {
  test('syncEngineProvider does not dispose SyncEngine.instance across auth transitions', () {
    final authNotifier = _TestAuthNotifier(const AuthState(isLoading: true));
    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith(() => authNotifier),
      ],
    );
    addTearDown(container.dispose);

    // Initial read
    final engine1 = container.read(syncEngineProvider);
    expect(identical(engine1, SyncEngine.instance), isTrue);

    // Simulate user sign in
    const testUser = AppUser(
      id: 'test_emp_123',
      name: 'Test User',
      email: 'test@example.com',
      role: UserRole.employee,
    );
    authNotifier.setUser(testUser);

    // Read again after auth change
    final engine2 = container.read(syncEngineProvider);
    expect(identical(engine2, SyncEngine.instance), isTrue);

    // Simulate user sign out
    authNotifier.setUser(null);

    final engine3 = container.read(syncEngineProvider);
    expect(identical(engine3, SyncEngine.instance), isTrue);

    // Container disposal must NOT dispose the SyncEngine.instance singleton
    container.dispose();

    // Verify SyncEngine.instance is still fully usable and not disposed
    expect(() {
      void listener() {}
      SyncEngine.instance.addListener(listener);
      SyncEngine.instance.removeListener(listener);
    }, returnsNormally);
  });
}
