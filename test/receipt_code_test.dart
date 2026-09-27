import 'package:anumati_collect/core/otp.dart';
import 'package:anumati_collect/core/receipt_code.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('receipt code matches the server formula (sha256(event_uuid), 30 bits, base32)', () {
    // Vectors computed with anumati.api.v1.consent.short_code on the server side.
    expect(receiptCode('c0a8f1e2-0000-4000-8000-000000000001'), 'AN-HX34BM');
    expect(receiptCode('test-uuid-1234'), 'AN-5NBFB6');
  });

  test('generated principal refs are prefixed and unique', () {
    final refs = {for (var i = 0; i < 200; i++) newPrincipalRef()};
    expect(refs.length, 200);
    expect(refs.every((r) => RegExp(r'^AC-[A-Z2-7]{8}$').hasMatch(r)), isTrue);
  });

  test('device OTP verifies the right code and locks after five wrong tries', () {
    final (otp, code) = DeviceOtp.generate();
    expect(code, matches(RegExp(r'^\d{6}$')));
    final wrong = code == '000000' ? '111111' : '000000';
    for (var i = 0; i < 4; i++) {
      expect(otp.verify(wrong), isFalse);
    }
    expect(otp.verify(code), isTrue);
    final (otp2, code2) = DeviceOtp.generate();
    for (var i = 0; i < DeviceOtp.maxTries; i++) {
      otp2.verify(code2 == '000000' ? '111111' : '000000');
    }
    expect(otp2.locked, isTrue);
    expect(otp2.verify(code2), isFalse, reason: 'locked after too many tries');
  });
}
