import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:growmont_crm/core/firebase/cloud_callables.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

CloudCallables _callables(
  Future<http.Response> Function(http.Request) handler, {
  String? token = 'id-token',
}) {
  return CloudCallables(
    client: MockClient(handler),
    idToken: () async => token,
    projectId: 'demo-project',
  );
}

Future<String> _messageOf(Future<void> call) async {
  try {
    await call;
  } on BackendException catch (e) {
    return e.message;
  }
  fail('expected a BackendException');
}

void main() {
  test('posts the callable protocol and returns the result', () async {
    late http.Request sent;
    final callables = _callables((request) async {
      sent = request;
      return http.Response(jsonEncode({'result': {'uid': 'abc'}}), 200);
    });

    final result = await callables.call('createEmployee', {'name': 'Rohan'});

    expect(result, {'uid': 'abc'});
    expect(
      sent.url.toString(),
      'https://asia-south1-demo-project.cloudfunctions.net/createEmployee',
    );
    expect(sent.method, 'POST');
    expect(sent.headers['Authorization'], 'Bearer id-token');
    expect(jsonDecode(sent.body), {
      'data': {'name': 'Rohan'},
    });
  });

  test("surfaces the function's own error message", () async {
    final callables = _callables(
      (_) async => http.Response(
        jsonEncode({
          'error': {
            'status': 'PERMISSION_DENIED',
            'message': 'Only administrators can manage employee accounts.',
          },
        }),
        403,
      ),
    );

    expect(
      await _messageOf(callables.call('deleteEmployee')),
      'Only administrators can manage employee accounts.',
    );
  });

  test('hides a bare INTERNAL status behind a readable message', () async {
    final callables = _callables(
      (_) async => http.Response(
        jsonEncode({
          'error': {'status': 'INTERNAL', 'message': 'INTERNAL'},
        }),
        500,
      ),
    );

    expect(
      await _messageOf(callables.call('deleteEmployee')),
      'Something went wrong on the server. Please try again.',
    );
  });

  test('explains an undeployed function instead of showing HTML', () async {
    final callables = _callables(
      (_) async => http.Response('<html>Page not found</html>', 404),
    );

    expect(
      await _messageOf(callables.call('setEmployeePassword')),
      contains('not available on the server yet'),
    );
  });

  test('reports a network failure as such', () async {
    final callables = _callables(
      (_) async => throw http.ClientException('Connection refused'),
    );

    expect(
      await _messageOf(callables.call('setEmployeeAccess')),
      contains('Could not reach the server'),
    );
  });

  test('refuses to call without a signed-in user', () async {
    var called = false;
    final callables = _callables((_) async {
      called = true;
      return http.Response('{}', 200);
    }, token: null);

    expect(
      await _messageOf(callables.call('createEmployee')),
      'Your session has expired. Please sign in again.',
    );
    expect(called, isFalse);
  });
}
