import 'package:uuid/uuid.dart';

import '../core/receipt_code.dart';
import '../data/store.dart';

/// One purpose on the live notice, as served by notice.get_active.
class NoticePurpose {
  NoticePurpose(this.raw);
  final Map<String, dynamic> raw;

  String get code => raw['code'] as String;
  String get title => raw['purpose_title'] as String? ?? code;
  String get description => raw['description'] as String? ?? '';
  bool get essential => _b(raw['essential']);
  bool get childAllowed => raw['child_allowed'] == null || _b(raw['child_allowed']);

  static bool _b(Object? v) => v == 1 || v == true || v == '1';
}

/// The live notice for the chosen programme, in one language.
class Notice {
  Notice(this.raw);
  final Map<String, dynamic> raw;

  String get name => raw['notice'] as String;
  String get version => raw['version'] as String? ?? '';
  Map<String, dynamic>? get translation => raw['translation'] as Map<String, dynamic>?;
  String get summary => (translation?['summary'] ?? raw['summary'] ?? '') as String;
  String get fullText => (translation?['full_text'] ?? raw['full_text'] ?? '') as String;
  String? get audioFile => translation?['audio_file'] as String?;
  String? get pictorialCard => (translation?['pictorial_card'] ?? raw['pictorial_card']) as String?;

  /// Rule 3 contents in her language when the translation has them, else the notice's own text.
  String _r3(String key) => (translation?[key] ?? raw[key] ?? '') as String;
  String? label(String key) => translation?[key] as String?;
  String get withdrawalMethods => _r3('withdrawal_methods');
  String get rightsText => _r3('rights_text');
  String get complaintRoute => _r3('board_complaint_route');
  String get dpoContact => _r3('dpo_contact');

  /// Servers from the field-app MVP release serve pictorial_card and accept notice_delivery.
  bool get supportsDelivery => raw.containsKey('pictorial_card');
  String get crossBorder => raw['cross_border_transfers'] as String? ?? '';
  List<NoticePurpose> get purposes => [
    for (final p in (raw['purposes'] as List? ?? const [])) NoticePurpose(Map<String, dynamic>.from(p as Map)),
  ];
}

class EvidenceRef {
  EvidenceRef(this.local, this.kind, this.sha256);
  final String local;
  final String kind;
  final String sha256;
  Map<String, String> toJson() => {'local': local, 'kind': kind, 'sha256': sha256};
}

/// Everything collected while taking one consent. Nothing is written to the
/// outbox until the worker taps "Verify and save".
class CaptureDraft {
  CaptureDraft({required this.programme, required this.deviceId});

  final String programme;
  final String deviceId;
  final String eventUuid = const Uuid().v4();

  String principalRef = '';
  String fullName = '';
  String phone = '';
  String lang = 'en';
  final Map<String, bool> flags = {'read': false, 'shared': false, 'nophone': false, 'minor': false, 'pwd': false};

  // guardian
  String guardianType = 'parent';
  String guardianName = '';
  String guardianRelation = '';
  String guardianPhone = '';
  String guardianAuthorityRef = '';
  String guardianVerify = 'sms';
  bool guardianVerified = false;
  EvidenceRef? guardianDoc;

  // notice and choices
  Notice? notice;
  bool noticeDone = false;

  /// How the notice was given (coaching data sent with the consent, not signed):
  /// recording, phone_voice, read_aloud or read_on_screen.
  String noticeDelivery = '';
  final Map<String, bool> choices = {};

  // evidence
  bool selfChosen = false;
  EvidenceRef? voice;
  EvidenceRef? thumb;
  String witness = '';
  String witnessRelation = '';
  bool attested = false;

  // verification
  String verifyMethod = 'device_sms_otp';
  bool otpConfirmed = false;

  bool get needsGuardian => flags['minor']! || flags['pwd']!;
  bool get noPhone => flags['nophone']!;
  String get shortCode => receiptCode(eventUuid);

  List<NoticePurpose> get offered => [
    for (final p in notice?.purposes ?? const <NoticePurpose>[])
      if (!(flags['minor']! && !p.childAllowed)) p,
  ];

  List<String> get granted => [
    for (final p in offered)
      if (p.essential || (choices[p.code] ?? false)) p.code,
  ];

  List<String> get denied => [
    for (final p in offered)
      if (!p.essential && !(choices[p.code] ?? false)) p.code,
  ];

  /// A verified guardian (SMS code or ID/order photo) already proves who consented, so guardian flows
  /// need no separate witness; assisted adult consent needs evidence plus a witness (spec section 5).
  bool get evidenceReady {
    if (!attested) return false;
    if (selfChosen) return true;
    if (needsGuardian) return guardianVerified || guardianDoc != null || voice != null || thumb != null;
    return (voice != null || thumb != null) && witness.trim().isNotEmpty;
  }

  /// The guardian's SMS code already verified the phone: don't ask again on the Verify step.
  bool get verifiedByGuardian => needsGuardian && guardianVerify == 'sms' && guardianVerified;

  String get captureMode {
    if (flags['minor']!) return 'guardian_minor';
    if (flags['pwd']!) return 'guardian_pwd';
    if (selfChosen) return 'self_worker_device';
    if (voice != null) return 'assisted_verbal';
    if (thumb != null) return 'assisted_thumbprint';
    return 'assisted_witnessed';
  }

  String get verificationStatus => switch (verifyMethod) {
    'device_sms_otp' => otpConfirmed ? 'confirmed' : 'recorded',
    'evidence_only' => 'evidence_only',
    _ => 'recorded',
  };

  static String deviceTime(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  Map<String, dynamic> principalValues() => {
    'principal_ref': principalRef,
    if (fullName.trim().isNotEmpty) 'full_name': fullName.trim(),
    if (phone.trim().isNotEmpty && !noPhone) 'phone': phone.trim(),
    'preferred_language': lang,
    'is_minor': flags['minor']! ? 1 : 0,
    'pwd_guarded': flags['pwd']! ? 1 : 0,
    'needs_assistance': flags['read']! ? 1 : 0,
    'shared_phone': flags['shared']! ? 1 : 0,
    'no_phone': noPhone ? 1 : 0,
    'age_band': flags['minor']! ? 'under_18' : '18_plus',
  };

  String get _guardianRef => '$principalRef-G';

  /// The outbox payload. Evidence is referenced by its encrypted local id.
  Map<String, dynamic> toPayload(DateTime now) => {
    'principal': principalValues(),
    if (needsGuardian)
      'guardian': {
        'principal': {
          'principal_ref': _guardianRef,
          if (guardianName.trim().isNotEmpty) 'full_name': guardianName.trim(),
          if (guardianPhone.trim().isNotEmpty) 'phone': guardianPhone.trim(),
          'preferred_language': lang,
        },
        'link': {
          'guardian_type': switch (guardianType) {
            'legal' => 'legal_guardian',
            'family' => 'family_pwd',
            'court' => 'court',
            _ => 'parent',
          },
          if (guardianRelation.trim().isNotEmpty) 'relation': guardianRelation.trim(),
          if (guardianAuthorityRef.trim().isNotEmpty) 'authority_ref': guardianAuthorityRef.trim(),
          'verification_method': guardianVerify == 'sms' ? 'device_sms_otp' : 'document',
          if (guardianVerified) 'verified_on': deviceTime(now),
        },
      },
    'guardian_evidence': [?guardianDoc?.toJson()],
    'evidence': [?voice?.toJson(), ?thumb?.toJson()],
    'event': {
      'event_uuid': eventUuid,
      'principal_ref': principalRef,
      'programme': programme,
      'action': 'grant',
      'purposes_granted': granted,
      'purposes_denied': denied,
      'notice': ?notice?.name,
      'language': lang,
      'capture_mode': captureMode,
      'channel': 'app',
      'device_id': deviceId,
      'device_time': deviceTime(now),
      'verification_method': verifyMethod,
      'verification_status': verificationStatus,
      // Only servers that know these fields get them (older ones reject unknown fields).
      if (notice?.supportsDelivery ?? false) ...{
        if (noticeDelivery.isNotEmpty) 'notice_delivery': noticeDelivery,
        'notice_completed': noticeDone ? 1 : 0,
      },
      if (!selfChosen && witness.trim().isNotEmpty)
        'witness': [witness.trim(), witnessRelation.trim()].where((s) => s.isNotEmpty).join(', '),
    },
  };

  LocalPrincipal toLocal() => LocalPrincipal(
    ref: principalRef,
    programme: programme,
    fullName: fullName.trim(),
    phone: noPhone ? null : phone.trim(),
    lang: lang,
    flags: Map.of(flags),
    lastCode: shortCode,
    verificationMethod: verifyMethod,
  );
}
