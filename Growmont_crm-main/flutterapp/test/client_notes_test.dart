import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:growmont_crm/core/firebase/firestore_service.dart';
import 'package:growmont_crm/core/providers.dart';
import 'package:growmont_crm/core/theme/app_theme.dart';
import 'package:growmont_crm/features/auth/auth_provider.dart';
import 'package:growmont_crm/features/clients/widgets/client_notes_section.dart';
import 'package:growmont_crm/models/client_note.dart';
import 'package:growmont_crm/models/user.dart';

class _FakeAuth extends AuthNotifier {
  _FakeAuth(this._user);
  final AppUser _user;

  @override
  AuthState build() => AuthState(user: _user, isLoading: false);
}

class _FakeNotesService implements FirestoreService {
  _FakeNotesService(List<ClientNote> seed) : _notes = [...seed];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  final List<ClientNote> _notes;
  final _changes = StreamController<void>.broadcast();

  List<ClientNote> _sorted() =>
      _notes.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  @override
  Stream<List<ClientNote>> streamClientNotes(String clientId) async* {
    yield _sorted();
    await for (final _ in _changes.stream) {
      yield _sorted();
    }
  }

  @override
  Future<ClientNote> createClientNote({
    required String clientId,
    required String clientOwnerId,
    required String text,
    required String authorId,
    required String authorName,
  }) async {
    final note = ClientNote(
      id: 'n${_notes.length + 1}',
      clientId: clientId,
      clientOwnerId: clientOwnerId,
      text: text,
      authorId: authorId,
      authorName: authorName,
      createdAt: DateTime(2026, 11, 16, 10),
    );
    _notes.add(note);
    _changes.add(null);
    return note;
  }

  @override
  Future<void> deleteClientNote(String id) async {
    _notes.removeWhere((n) => n.id == id);
    _changes.add(null);
  }
}

ClientNote _note(String id, String text, String authorId, String authorName) =>
    ClientNote(
      id: id,
      clientId: 'c1',
      clientOwnerId: 'emp1',
      text: text,
      authorId: authorId,
      authorName: authorName,
      createdAt: DateTime(2026, 11, 16, 9),
    );

Widget _subject(AppUser user, _FakeNotesService service) {
  return ProviderScope(
    overrides: [
      apiServiceProvider.overrideWithValue(service),
      authProvider.overrideWith(() => _FakeAuth(user)),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      home: const Scaffold(
        body: SingleChildScrollView(
          child: ClientNotesSection(clientId: 'c1', clientOwnerId: 'emp1'),
        ),
      ),
    ),
  );
}

const _emp = AppUser(
  id: 'emp1',
  name: 'Samir Joshi',
  email: 's@growmont.com',
  role: UserRole.employee,
);
const _admin = AppUser(
  id: 'adm1',
  name: 'Smit Mhatre',
  email: 'a@growmont.com',
  role: UserRole.admin,
);

void main() {
  group('ClientNote model', () {
    test('json round-trip', () {
      final n = ClientNote(
        id: 'x',
        clientId: 'c1',
        clientOwnerId: 'emp1',
        text: 'Prefers calls after 5pm',
        authorId: 'emp1',
        authorName: 'Samir Joshi',
        createdAt: DateTime.utc(2026, 11, 16, 8, 30),
      );
      final back = ClientNote.fromJson(n.toJson(), 'x');
      expect(back.id, 'x');
      expect(back.clientId, 'c1');
      expect(back.clientOwnerId, 'emp1');
      expect(back.text, 'Prefers calls after 5pm');
      expect(back.authorId, 'emp1');
      expect(back.authorName, 'Samir Joshi');
      expect(back.createdAt.toUtc(), DateTime.utc(2026, 11, 16, 8, 30));
    });

    test('validate trims and enforces 1-500 chars', () {
      expect(ClientNote.validate('  hi  '), 'hi');
      expect(ClientNote.validate('line1\nline2'), 'line1\nline2');
      expect(ClientNote.validate(''), isNull);
      expect(ClientNote.validate('   \n '), isNull);
      expect(ClientNote.validate(null), isNull);
      expect(ClientNote.validate('a' * 500), 'a' * 500);
      expect(ClientNote.validate('a' * 501), isNull);
      expect(ClientNote.validate('${' ' * 10}${'a' * 500}'), 'a' * 500);
    });

    test('fromJson tolerates missing fields', () {
      final n = ClientNote.fromJson({'id': 'z'});
      expect(n.id, 'z');
      expect(n.text, '');
    });
  });

  group('ClientNotesSection', () {
    testWidgets('add button is disabled for empty input and adds a bullet',
        (tester) async {
      final service = _FakeNotesService([]);
      await tester.pumpWidget(_subject(_emp, service));
      await tester.pumpAndSettle();

      expect(find.text('Notes'), findsOneWidget);
      IconButton button() =>
          tester.widget<IconButton>(find.byKey(const ValueKey('add-note')));
      expect(button().onPressed, isNull);

      await tester.enterText(find.byType(TextField), '   ');
      await tester.pump();
      expect(button().onPressed, isNull);

      await tester.enterText(find.byType(TextField), 'Likes mango jam');
      await tester.pump();
      expect(button().onPressed, isNotNull);

      await tester.tap(find.byKey(const ValueKey('add-note')));
      await tester.pumpAndSettle();

      expect(find.text('• Likes mango jam'), findsOneWidget);
      expect(find.text('Samir Joshi · 16 Nov 2026'), findsOneWidget);
      expect(find.text('Likes mango jam'), findsNothing);
      expect(button().onPressed, isNull);
    });

    testWidgets('Enter submits the note', (tester) async {
      final service = _FakeNotesService([]);
      await tester.pumpWidget(_subject(_emp, service));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Send brochure');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(find.text('• Send brochure'), findsOneWidget);
    });

    testWidgets('employee can delete only their own note, with confirmation',
        (tester) async {
      final service = _FakeNotesService([
        _note('n1', 'Mine', 'emp1', 'Samir Joshi'),
        _note('n2', 'Admin wrote this', 'adm1', 'Smit Mhatre'),
      ]);
      await tester.pumpWidget(_subject(_emp, service));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('delete-note-n1')), findsOneWidget);
      expect(find.byKey(const ValueKey('delete-note-n2')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('delete-note-n1')));
      await tester.pumpAndSettle();
      expect(find.text('Delete note?'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('• Mine'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('delete-note-n1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('• Mine'), findsNothing);
      expect(find.text('• Admin wrote this'), findsOneWidget);
    });

    testWidgets('admin can delete any note', (tester) async {
      final service = _FakeNotesService([
        _note('n1', 'Mine', 'emp1', 'Samir Joshi'),
        _note('n2', 'Other', 'emp9', 'Someone Else'),
      ]);
      await tester.pumpWidget(_subject(_admin, service));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('delete-note-n1')), findsOneWidget);
      expect(find.byKey(const ValueKey('delete-note-n2')), findsOneWidget);
    });

    testWidgets('empty list shows a single muted line', (tester) async {
      final service = _FakeNotesService([]);
      await tester.pumpWidget(_subject(_emp, service));
      await tester.pumpAndSettle();
      expect(find.text('No notes'), findsOneWidget);
    });
  });
}
