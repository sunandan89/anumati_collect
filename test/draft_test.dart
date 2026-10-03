import 'package:anumati_collect/capture/draft.dart';
import 'package:anumati_collect/capture/flow.dart';
import 'package:anumati_collect/core/receipt_code.dart';
import 'package:anumati_collect/core/strings.dart';
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
      ..who = 'child'
      ..guardianName = 'Sunita D. (fictional)'
      ..guardianPhone = '9000022222'
      ..guardianVerified = true
      ..settleVerification();
    final p = d.toPayload(DateTime(2026, 9, 27, 10, 5, 9));
    final e = p['event'] as Map;
    expect(e['event_uuid'], d.eventUuid);
    expect(d.shortCode, receiptCode(d.eventUuid));
    expect(e['device_time'], '2026-09-27 10:05:09');
    expect(e['verification_status'], 'confirmed');
    expect(e['notice'], 'MHU-v1.0.0');
    expect(e.containsKey('witness'), isFalse);
    final link = (p['guardian'] as Map)['link'] as Map;
    expect((p['guardian'] as Map)['principal']['principal_ref'], 'MHU-000001-G');
    expect(link['guardian_type'], 'parent');
    expect(link['relation'], 'Mother');
    expect(link.containsKey('authority_ref'), isFalse, reason: 'a parent needs no order');
    expect((p['principal'] as Map)['is_minor'], 1);
    expect((p['principal'] as Map).containsKey('phone'), isFalse, reason: "the child's own phone is not asked");
  });

  test('reads, has a phone: the SMS code (or confirm later) and the tick; no witness, no evidence', () {
    final d = draft()..noticeDone = true;
    expect(d.missing, ['SMS code', 'tick']);
    expect(d.evidenceNeeded, isFalse);
    expect(d.witnessNeeded, isFalse);
    d
      ..attested = true
      ..verifyMethod = 'deferred';
    expect(d.ready, isTrue);
    d.settleVerification();
    expect(d.verifyMethod, 'deferred');
    expect(d.captureMode, 'self_worker_device');
  });

  test('reads, no phone: a voice "haan" or a signature/thumbprint photo, no witness', () {
    final d = draft()
      ..flags['nophone'] = true
      ..noticeDone = true
      ..attested = true;
    expect(d.missing, ['proof']);
    d.thumb = EvidenceRef('1.jpg', 'signature', 'a' * 64);
    expect(d.ready, isTrue);
    d.settleVerification();
    expect(d.verifyMethod, 'evidence_only');
    expect((d.toPayload(DateTime(2026))['event'] as Map).containsKey('witness'), isFalse);
  });

  test('needs help reading: evidence plus a witness, and the SMS code when there is a phone', () {
    final d = draft()
      ..flags['read'] = true
      ..noticeDone = true
      ..attested = true;
    expect(d.missing, ['SMS code', 'proof', 'witness']);
    d
      ..otpConfirmed = true
      ..thumb = EvidenceRef('1.jpg', 'thumbprint', 'a' * 64)
      ..witness = 'Asha (fictional)';
    expect(d.ready, isTrue);
    expect(d.captureMode, 'assisted_thumbprint');
    d.settleVerification();
    expect(d.verificationStatus, 'confirmed');
    expect((d.toPayload(DateTime(2026))['event'] as Map)['witness'], 'Asha (fictional)');
  });

  test('a device OTP not yet confirmed is only recorded; evidence only is its own status', () {
    final d = draft()..verifyMethod = 'device_sms_otp';
    expect(d.verificationStatus, 'recorded');
    d.verifyMethod = 'evidence_only';
    expect(d.verificationStatus, 'evidence_only');
  });

  test('guardian journeys: three screens, verified by SMS or an ID photo, no witness or voice', () {
    final d = draft()
      ..who = 'child'
      ..guardianName = 'Meena K. (fictional)'
      ..guardianPhone = '9000033333';
    expect(d.guardianMissing, ['SMS code']);
    d.guardianPhone = '90000';
    expect(d.guardianMissing, ['mobile number', 'SMS code']);
    d.guardianPhone = '9000033333';
    d.guardianVerified = true;
    expect(d.guardianMissing, isEmpty);
    expect(flowSteps(d), ['principal', 'guardian', 'notice']);
    d
      ..noticeDone = true
      ..attested = true;
    expect(d.ready, isTrue, reason: 'no witness, voice or thumbprint for a verified guardian');
    final noPhone = draft()
      ..who = 'child'
      ..guardianName = 'Meena K. (fictional)';
    expect(noPhone.guardianMissing, ['ID photo (no phone)']);
    noPhone.guardianDoc = EvidenceRef('id.jpg', 'guardian_document', 'b' * 64);
    expect(noPhone.guardianMissing, isEmpty);
    noPhone.settleVerification();
    expect(noPhone.verifyMethod, 'evidence_only');
    expect(flowSteps(draft()), ['principal', 'notice', 'confirm']);
  });

  test('other guardian of a child, and every guardian of an adult, need the order number', () {
    final child = draft()
      ..who = 'child'
      ..guardianType = 'other'
      ..guardianName = 'Ravi S. (fictional)'
      ..guardianVerified = true;
    expect(child.guardianMissing, ['order number']);
    child.guardianAuthorityRef = 'GO-12/2026';
    child.guardianOrder = EvidenceRef('o.jpg', 'guardian_order', 'c' * 64);
    expect((child.toPayload(DateTime(2026))['guardian_evidence'] as List).length, 1);
    child.guardianType = 'mother';
    expect(child.toPayload(DateTime(2026))['guardian_evidence'], isEmpty, reason: 'no order photo on a parent link');
    child.guardianType = 'other';
    final link = (child.toPayload(DateTime(2026))['guardian'] as Map)['link'] as Map;
    expect(link['guardian_type'], 'legal_guardian');
    expect(link['authority_ref'], 'GO-12/2026');

    final adult = draft()
      ..who = 'guardian'
      ..guardianName = 'Suresh K. (fictional)'
      ..guardianVerified = true;
    expect(adult.guardianType, 'committee');
    expect(adult.guardianMissing, ['relation', 'order number']);
    adult
      ..guardianRelation = 'Brother / sister'
      ..guardianAuthorityRef = 'LLC/2026/0412';
    expect(adult.guardianMissing, isEmpty);
    final p = adult.toPayload(DateTime(2026));
    expect(((p['guardian'] as Map)['link'] as Map)['guardian_type'], 'committee');
    expect((p['principal'] as Map)['pwd_guarded'], 1);
    expect((p['event'] as Map)['capture_mode'], 'guardian_pwd');
    adult.guardianType = 'none';
    expect(adult.guardianStop, isTrue, reason: 'no order yet: consent cannot be taken');
  });

  test('uses that need a phone are hidden without one; names follow the notice language', () {
    final n = Notice({
      'notice': 'N',
      'purposes': [
        {'code': 'screen', 'purpose_title': 'Health screening', 'essential': 1},
        {'code': 'follow', 'purpose_title': 'Follow-up calls', 'essential': 0, 'needs_phone': 1},
      ],
      'translation': {
        'purposes': [
          {'code': 'follow', 'purpose_title': 'फ़ॉलो-अप कॉल', 'description': ''},
        ],
      },
    });
    final d = draft()..notice = n;
    expect(d.offered.map((p) => p.title), ['Health screening', 'फ़ॉलो-अप कॉल']);
    d.flags['nophone'] = true;
    d.phone = '';
    expect(d.offered.map((p) => p.code), ['screen']);
    expect(d.denied, isEmpty, reason: 'a use not offered is neither granted nor refused');
    expect(d.someHidden, isTrue);
  });

  test('extra questions add an About screen; required answers block Save; sent only to servers that know them', () {
    final n = Notice({
      'notice': 'N',
      'purposes': [],
      'profile_questions': [
        {'code': 'age', 'question': 'Age in years', 'answer_type': 'number', 'required': 1},
        {
          'code': 'gender',
          'question': 'Gender',
          'answer_type': 'choice',
          'required': 0,
          'options': [
            {'value': 'Female', 'label': 'महिला'},
          ],
        },
      ],
    });
    final d = draft()
      ..notice = n
      ..noticeDone = true
      ..attested = true
      ..otpConfirmed = true;
    expect(flowSteps(d), ['principal', 'notice', 'about', 'confirm']);
    expect(d.questions[1].options.first, ('Female', 'महिला'));
    expect(d.missing, ['answers']);
    d.profile['age'] = '34';
    expect(d.ready, isTrue);
    final principal = d.principalValues();
    expect(principal['profile'], {'age': '34'});
    expect(principal['programme'], 'MHU');
    final old = draft()..profile['age'] = '34';
    expect(old.principalValues().containsKey('profile'), isFalse, reason: 'older servers reject unknown fields');
  });

  test("a child's year of birth goes to servers that support renewal at 18", () {
    final d = draft()
      ..notice = Notice({'notice': 'N', 'purposes': [], 'profile_questions': []})
      ..who = 'child'
      ..birthYear = '2016';
    expect(d.principalValues()['birth_year'], 2016);
    expect((draft()..birthYear = '2016').principalValues().containsKey('birth_year'), isFalse);
  });

  test('approved audio: her language first, the base notice only when she hears the base text', () {
    expect(Notice({'notice': 'N', 'audio_file': '/private/files/base.mp3'}).audioFile, '/private/files/base.mp3');
    expect(
      Notice({
        'notice': 'N',
        'audio_file': '/private/files/base.mp3',
        'translation': {'audio_file': '/private/files/hi.mp3'},
      }).audioFile,
      '/private/files/hi.mp3',
    );
    expect(
      Notice({
        'notice': 'N',
        'audio_file': '/private/files/base.mp3',
        'translation': {'summary': 'x'},
      }).audioFile,
      isNull,
    );
  });

  test('Sarvam credit shows for English and Hindi machine-voiced recordings only', () {
    // English consent: the base notice's own recording.
    expect(Notice({'notice': 'N', 'audio_file': '/f/en.mp3', 'audio_machine_made': 1}).audioByAi, isTrue);
    expect(Notice({'notice': 'N', 'audio_file': '/f/en.mp3', 'audio_machine_made': 0}).audioByAi, isFalse);
    // Hindi consent: the translation's recording decides, not the base notice's.
    final hi = {'audio_file': '/f/hi.mp3', 'audio_machine_made': 1};
    expect(Notice({'notice': 'N', 'audio_file': '/f/en.mp3', 'translation': hi}).audioByAi, isTrue);
    expect(
      Notice({
        'notice': 'N',
        'audio_file': '/f/en.mp3',
        'audio_machine_made': 1,
        'translation': {'summary': 'x'},
      }).audioByAi,
      isFalse,
    );
    // Older server that doesn't send the flag: no credit.
    expect(Notice({'notice': 'N', 'audio_file': '/f/en.mp3'}).audioByAi, isFalse);
    expect(trFor('hi', 'Natural voice · Powered by Sarvam AI'), isNot('Natural voice · Powered by Sarvam AI'));
  });
}
