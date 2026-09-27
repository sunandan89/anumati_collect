import 'package:anumati_collect/capture/draft.dart';
import 'package:anumati_collect/core/receipt_code.dart';
import 'package:flutter_test/flutter_test.dart';

Notice notice() => Notice({
  'notice': 'MHU-v1.0.0',
  'version': '1.0.0',
  'summary': 'We screen your health.',
  'purposes': [
    {'code': 'screen', 'purpose_title': 'Health screening', 'essential': 1, 'child_allowed': 1},
    {'code': 'follow', 'purpose_title': 'Follow-up calls', 'essential': 0, 'child_allowed': 1},
    {'code': 'research', 'purpose_title': 'Anonymised research', 'essential': 0, 'child_allowed': 0},
  ],
  'translation': null,
});

CaptureDraft draft() => CaptureDraft(programme: 'MHU', deviceId: 'dev-1')
  ..principalRef = 'MHU-000001'
  ..fullName = 'Meena K. (fictional)'
  ..phone = '9000011111'
  ..notice = notice();

void main() {
  test('optional purposes start off; essential is always granted', () {
    final d = draft();
    expect(d.granted, ['screen']);
    expect(d.denied, ['follow', 'research']);
    d.choices['follow'] = true;
    expect(d.granted, ['screen', 'follow']);
  });

  test('purposes not allowed for minors are not offered at all', () {
    final d = draft()..flags['minor'] = true;
    d.choices['research'] = true;
    expect(d.offered.map((p) => p.code), ['screen', 'follow']);
    expect(d.granted, isNot(contains('research')));
    expect(d.denied, isNot(contains('research')));
    expect(d.captureMode, 'guardian_minor');
  });

  test('payload carries the receipt code inputs, no evidence paths, and a guardian for minors', () {
    final d = draft()
      ..flags['minor'] = true
      ..guardianName = 'Sunita D. (fictional)'
      ..guardianVerify = 'sms'
      ..guardianVerified = true
      ..verifyMethod = 'device_sms_otp'
      ..otpConfirmed = true;
    final p = d.toPayload(DateTime(2026, 9, 27, 10, 5, 9));
    final e = p['event'] as Map;
    expect(e['event_uuid'], d.eventUuid);
    expect(d.shortCode, receiptCode(d.eventUuid));
    expect(e['device_time'], '2026-09-27 10:05:09');
    expect(e['verification_status'], 'confirmed');
    expect(e['notice'], 'MHU-v1.0.0');
    expect((p['guardian'] as Map)['principal']['principal_ref'], 'MHU-000001-G');
    expect((p['guardian'] as Map)['link']['guardian_type'], 'parent');
    expect((p['principal'] as Map)['is_minor'], 1);
  });

  test('evidence rules: assisted needs evidence plus witness; always an attestation', () {
    final d = draft();
    expect(d.evidenceReady, isFalse);
    d.attested = true;
    expect(d.evidenceReady, isFalse);
    d.thumb = EvidenceRef('1.jpg', 'thumbprint', 'a' * 64);
    expect(d.evidenceReady, isFalse, reason: 'witness missing');
    d.witness = 'Asha (fictional)';
    expect(d.evidenceReady, isTrue);
    expect(d.captureMode, 'assisted_thumbprint');
    final self = draft()
      ..selfChosen = true
      ..attested = true;
    expect(self.evidenceReady, isTrue);
    expect(self.captureMode, 'self_worker_device');
  });

  test('a device OTP not yet confirmed is only recorded; evidence only is its own status', () {
    final d = draft()..verifyMethod = 'device_sms_otp';
    expect(d.verificationStatus, 'recorded');
    d.verifyMethod = 'evidence_only';
    expect(d.verificationStatus, 'evidence_only');
  });
}
