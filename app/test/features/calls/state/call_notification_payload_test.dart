import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/calls/state/call_notifications.dart';

void main() {
  group('PendingCallAction.tryParse', () {
    test('returns null when raw is null', () {
      expect(PendingCallAction.tryParse(null), isNull);
    });

    test('reads call_id when it is a string', () {
      final result = PendingCallAction.tryParse({'call_id': 'abc'});
      expect(result?.callId, 'abc');
    });

    test('reads call_id when it is an int', () {
      final result = PendingCallAction.tryParse({'call_id': 123});
      expect(result?.callId, '123');
    });

    test('falls back to callId when call_id is missing', () {
      final result = PendingCallAction.tryParse({'callId': 'fallback'});
      expect(result?.callId, 'fallback');
    });

    test('returns object with null callId when keys missing', () {
      final result = PendingCallAction.tryParse(<String, Object?>{});
      expect(result, isNotNull);
      expect(result?.callId, isNull);
    });
  });

  group('PendingIncomingHint.tryParse', () {
    test('returns null when raw is null', () {
      expect(PendingIncomingHint.tryParse(null), isNull);
    });

    test('returns null when payload missing or invalid', () {
      expect(PendingIncomingHint.tryParse({}), isNull);
      expect(PendingIncomingHint.tryParse({'payload': 'not a map'}), isNull);
    });

    test('returns null when from missing or blank', () {
      expect(
        PendingIncomingHint.tryParse({
          'payload': {'display_name': 'no from'},
        }),
        isNull,
      );
      expect(
        PendingIncomingHint.tryParse({
          'payload': {'from': '   '},
        }),
        isNull,
      );
    });

    test('trims from and preserves call ids', () {
      final hint = PendingIncomingHint.tryParse({
        'payload': {
          'from': '  caller  ',
          'display_name': '  Display Name  ',
          'call_id': 11,
          'call_uuid': 22,
        },
      });

      expect(hint, isNotNull);
      expect(hint?.from, 'caller');
      expect(hint?.displayName, 'Display Name');
      expect(hint?.callId, '11');
      expect(hint?.callUuid, '22');
    });

    test('treats blank display_name as null', () {
      final hint = PendingIncomingHint.tryParse({
        'payload': {'from': 'caller', 'display_name': '   '},
      });

      expect(hint, isNotNull);
      expect(hint?.displayName, isNull);
    });
  });
}
