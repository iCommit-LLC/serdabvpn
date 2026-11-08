import 'package:flutter_test/flutter_test.dart';
import 'package:serdabvpn/server.dart';

void main() {
  test('Me reads serdabd /v1/me', () {
    final exp = DateTime.now().add(const Duration(days: 12));
    final me = Me.fromJson({
      'name': 'aunt-salma',
      'role': 'guest',
      'canShare': false,
      'expiresAt': exp.millisecondsSinceEpoch ~/ 1000,
      'monitored': false,
      'autoCloseMinutes': 120,
    })!;
    expect(me.isGuest, isTrue);
    expect(me.mayStayOpen, isFalse);
    expect(me.expired, isFalse);
    expect(me.monitored, isFalse);
  });

  test('an expired guest, and family may stay open', () {
    final past = DateTime.now().subtract(const Duration(minutes: 1));
    expect(
      Me.fromJson({
        'name': 'g',
        'role': 'guest',
        'expiresAt': past.millisecondsSinceEpoch ~/ 1000,
      })!.expired,
      isTrue,
    );
    final wife = Me.fromJson({
      'name': 'wife',
      'role': 'family',
      'canShare': true,
      'monitored': true,
    })!;
    expect(wife.mayStayOpen, isTrue);
    expect(wife.canShare, isTrue);
    expect(wife.autoCloseMinutes, 120);
  });

  test('garbage is not a device', () {
    expect(Me.fromJson(null), isNull);
    expect(Me.fromJson({'role': 'owner'}), isNull);
  });
}
