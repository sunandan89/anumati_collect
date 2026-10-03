import 'package:uuid/uuid.dart';

import '../core/receipt_code.dart';
import '../data/store.dart';

/// One purpose on the live notice, as served by notice.get_active. [label] is the reviewed translation
/// of its name and description in the notice's language, when the server has one.
class NoticePurpose {
  NoticePurpose(this.raw, [this.label]);
  final Map<String, dynamic> raw;
  final Map<String, dynamic>? label;

  String get code => raw['code'] as String;
  String get title => _text('purpose_title') ?? code;
  String get description => _text('description') ?? '';
  bool get essential => _b(raw['essential']);
  bool get childAllowed => raw['child_allowed'] == null || _b(raw['child_allowed']);

  /// Calls or SMS to the person: not offered to someone without a phone.
  bool get needsPhone => _b(raw['needs_phone']);

  String? _text(String key) {
    final t = label?[key] as String?;
    return (t != null && t.trim().isNotEmpty) ? t : raw[key] as String?;
  }

  static bool _b(Object? v) => v == 1 || v == true || v == '1';
}

/// An extra question about the person that the programme asks (off unless the programme switched it on).
class ProfileQuestion {
  ProfileQuestion(this.raw);
  final Map<String, dynamic> raw;

  String get code => raw['code'] as String;
  String get question => raw['question'] as String? ?? code;
  String get answerType => raw['answer_type'] as String? ?? 'text';
  bool get required => NoticePurpose._b(raw['required']);
  bool get sensitive => NoticePurpose._b(raw['sensitive']);

  /// (stored value, label in the notice's language). Stored values are always the English choice.
  List<(String, String)> get options => [
    for (final o in (raw['options'] as List? ?? const []))
      ((o as Map)['value'] as String, (o['label'] as String?) ?? o['value'] as String),
  ];
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
  String? get audioFile => (translation != null ? translation!['audio_file'] : raw['audio_file']) as String?;

  /// The recording above was made with Sarvam AI's voice: shown as a credit under the player.
  bool get audioByAi => audioFile != null && (translation ?? raw)['audio_machine_made'] == 1;
  String? get pictorialCard => (translation?['pictorial_card'] ?? raw['pictorial_card']) as String?;

  /// Rule 3 contents in the person's language when the translation has them, else the notice's own text.
  String _r3(String key) => (translation?[key] ?? raw[key] ?? '') as String;
  String? label(String key) => translation?[key] as String?;
  String get withdrawalMethods => _r3('withdrawal_methods');
  String get rightsText => _r3('rights_text');
  String get complaintRoute => _r3('board_complaint_route');
  String get dpoContact => _r3('dpo_contact');

  /// Servers from the field-app MVP release serve pictorial_card and accept notice_delivery.
  bool get supportsDelivery => raw.containsKey('pictorial_card');

  /// Servers that serve extra questions also accept birth_year, programme and profile on principal.upsert.
  bool get supportsProfile => raw.containsKey('profile_questions');
  String get crossBorder => raw['cross_border_transfers'] as String? ?? '';

  List<NoticePurpose> get purposes {
    final labels = {
      for (final l in (translation?['purposes'] as List? ?? const []))
        (l as Map)['code'] as String: Map<String, dynamic>.from(l),
    };
    return [
      for (final p in (raw['purposes'] as List? ?? const []))
        NoticePurpose(Map<String, dynamic>.from(p as Map), labels[(p)['code']]),
    ];
  }

  List<ProfileQuestion> get questions => [
    for (final q in (raw['profile_questions'] as List? ?? const []))
      ProfileQuestion(Map<String, dynamic>.from(q as Map)),
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
/// outbox until the worker taps Save.
///
/// Who may consent and what proves it (design rules A1-A4):
/// - the person, reads, has a phone: SMS code (or confirm later by SMS). No witness.
/// - the person, reads, no phone: a voice "haan" or a photo of their signature or thumbprint.
/// - the person, needs help reading: voice or thumbprint, plus a witness (and the SMS code if they have
///   a phone), because someone else read the notice to them.
/// - a parent for a child, or a guardian for an adult who can't decide alone: the guardian's SMS code,
///   or a photo of their ID when they have no phone. No witness, voice or thumbprint.
/// A guardian other than a parent, and every guardian of an adult, gives the order number.
class CaptureDraft {
  CaptureDraft({required this.programme, required this.deviceId});

  final String programme;
  final String deviceId;
  final String eventUuid = const Uuid().v4();

  /// Verification methods the programme allows (set when the capture starts).
  List<String> allowedMethods = const ['device_sms_otp', 'deferred', 'evidence_only'];

  String principalRef = '';
  String fullName = '';
  String phone = '';
  String lang = 'en';
  String birthYear = '';
  final Map<String, bool> flags = {'read': false, 'shared': false, 'nophone': false, 'minor': false, 'pwd': false};

  // guardian
  /// Child: mother, father or other. Adult who can't decide alone: committee, court, other or none.
  String guardianType = 'mother';
  String guardianName = '';
  String guardianRelation = '';
  String guardianPhone = '';
  String guardianAuthorityRef = '';
  bool guardianVerified = false;
  EvidenceRef? guardianDoc;
  EvidenceRef? guardianOrder;

  // notice and choices
  Notice? notice;
  bool noticeDone = false;

  /// How the notice was given (coaching data sent with the consent, not signed):
  /// recording, phone_voice, read_aloud or read_on_screen.
  String noticeDelivery = '';
  final Map<String, bool> choices = {};

  /// Answers to the programme's extra questions, by question code.
  final Map<String, String> profile = {};

  // proof
  EvidenceRef? voice;
  EvidenceRef? thumb;
  String witness = '';
  String witnessRelation = '';
  bool attested = false;

  // verification
  String verifyMethod = 'device_sms_otp';
  bool otpConfirmed = false;

  /// Who is consenting: self, child (a parent for a child under 18) or guardian (for an adult who
  /// can't decide alone).
  String get who => flags['minor']! ? 'child' : (flags['pwd']! ? 'guardian' : 'self');
  set who(String w) {
    flags['minor'] = w == 'child';
    flags['pwd'] = w == 'guardian';
    if (w != 'self') {
      // No phone or reading questions for the person: the guardian is the one who reads and is verified.
      flags['read'] = false;
      flags['nophone'] = false;
      flags['shared'] = false;
      phone = '';
    }
    if (w == 'child' && !const ['mother', 'father', 'other'].contains(guardianType)) guardianType = 'mother';
    if (w == 'guardian' && !const ['committee', 'court', 'other', 'none'].contains(guardianType)) {
      guardianType = 'committee';
    }
  }

  bool get needsGuardian => flags['minor']! || flags['pwd']!;
  bool get noPhone => flags['nophone']!;
  bool get needsHelp => flags['read']!;
  String get shortCode => receiptCode(eventUuid);

  /// A phone the programme can call or text about this consent: the person's own, or the guardian's.
  bool get hasPhoneForUses => needsGuardian ? guardianPhone.trim().isNotEmpty : !noPhone && phone.trim().isNotEmpty;

  List<NoticePurpose> get offered => [
    for (final p in notice?.purposes ?? const <NoticePurpose>[])
      if (!(flags['minor']! && !p.childAllowed) && !(p.needsPhone && !p.essential && !hasPhoneForUses)) p,
  ];

  /// Some uses were left out: not for children, or they need a phone.
  bool get someHidden => (notice?.purposes.length ?? 0) != offered.length;

  List<String> get granted => [
    for (final p in offered)
      if (p.essential || (choices[p.code] ?? false)) p.code,
  ];

  List<String> get denied => [
    for (final p in offered)
      if (!p.essential && !(choices[p.code] ?? false)) p.code,
  ];

  List<ProfileQuestion> get questions => notice?.questions ?? const [];

  // ---------------------------------------------------------------- guardian

  bool get guardianNeedsOrder => flags['pwd']! || guardianType == 'other';

  /// Adult who can't decide alone with no appointed guardian: consent can't be taken (A4).
  bool get guardianStop => flags['pwd']! && guardianType == 'none';

  /// What is still missing on the guardian screen, in the worker's words (empty when ready).
  List<String> get guardianMissing => [
    if (flags['pwd']! && guardianRelation.isEmpty) 'relation',
    if (guardianNeedsOrder && guardianAuthorityRef.trim().isEmpty) 'order number',
    if (guardianName.trim().isEmpty) 'name',
    if (guardianPhone.isNotEmpty && !_validMobile(guardianPhone)) 'mobile number',
    if (!guardianVerified && guardianDoc == null) guardianPhone.trim().isEmpty ? 'ID photo (no phone)' : 'SMS code',
  ];

  static bool _validMobile(String digits) => digits.length == 10 || (digits.length == 12 && digits.startsWith('91'));

  String get _linkType => switch (guardianType) {
    'mother' || 'father' => 'parent',
    'committee' => 'committee',
    'court' => 'court',
    _ => 'legal_guardian',
  };

  String get _linkRelation => switch (guardianType) {
    'mother' => 'Mother',
    'father' => 'Father',
    'other' when flags['minor']! => 'Other guardian',
    _ => guardianRelation,
  };

  // ---------------------------------------------------------------- proof

  /// The person's own phone is checked by SMS code (or later by SMS) when the programme allows it.
  bool get phoneCheck =>
      !needsGuardian && !noPhone && (allowedMethods.contains('device_sms_otp') || allowedMethods.contains('deferred'));

  /// A voice "haan" or a photo is needed: no phone to check, or someone else read the notice.
  bool get evidenceNeeded => !needsGuardian && (noPhone || needsHelp || !phoneCheck);
  bool get witnessNeeded => !needsGuardian && needsHelp;
  bool get phoneChecked => otpConfirmed || verifyMethod == 'deferred';

  /// What is still missing before Save, in the worker's words (empty when ready).
  List<String> get missing => [
    if (!noticeDone) 'notice',
    if (questions.any((q) => q.required && (profile[q.code] ?? '').trim().isEmpty)) 'answers',
    if (phoneCheck && !phoneChecked) 'SMS code',
    if (evidenceNeeded && voice == null && thumb == null) 'proof',
    if (witnessNeeded && witness.trim().isEmpty) 'witness',
    if (!attested) 'tick',
  ];

  bool get ready => missing.isEmpty;

  String get captureMode {
    if (flags['minor']!) return 'guardian_minor';
    if (flags['pwd']!) return 'guardian_pwd';
    if (!needsHelp) return 'self_worker_device';
    if (voice != null) return 'assisted_verbal';
    if (thumb != null) return 'assisted_thumbprint';
    return 'assisted_witnessed';
  }

  /// The method recorded with the consent, worked out from the journey just before saving.
  void settleVerification() {
    if (needsGuardian) {
      verifyMethod = guardianVerified ? 'device_sms_otp' : 'evidence_only';
      otpConfirmed = guardianVerified;
    } else if (!phoneCheck) {
      verifyMethod = 'evidence_only';
    } else if (!otpConfirmed) {
      verifyMethod = 'deferred';
    } else {
      verifyMethod = 'device_sms_otp';
    }
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

  Map<String, dynamic> principalValues() {
    final answers = {
      for (final e in profile.entries)
        if (e.value.trim().isNotEmpty && questions.any((q) => q.code == e.key)) e.key: e.value.trim(),
    };
    final year = int.tryParse(birthYear.trim());
    return {
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
      // Only servers that know these fields get them (older ones reject unknown fields).
      if (notice?.supportsProfile ?? false) ...{
        if (flags['minor']! && year != null) 'birth_year': year,
        if (answers.isNotEmpty) ...{'programme': programme, 'profile': answers},
      },
    };
  }

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
          'guardian_type': _linkType,
          if (_linkRelation.isNotEmpty) 'relation': _linkRelation,
          if (guardianNeedsOrder && guardianAuthorityRef.trim().isNotEmpty)
            'authority_ref': guardianAuthorityRef.trim(),
          'verification_method': guardianVerified ? 'device_sms_otp' : 'document',
          if (guardianVerified) 'verified_on': deviceTime(now),
        },
      },
    // The order photo first: it is the one attached to the guardian link.
    'guardian_evidence': [if (guardianNeedsOrder) ?guardianOrder?.toJson(), ?guardianDoc?.toJson()],
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
      if (notice?.supportsDelivery ?? false) ...{
        if (noticeDelivery.isNotEmpty) 'notice_delivery': noticeDelivery,
        'notice_completed': noticeDone ? 1 : 0,
      },
      if (witnessNeeded && witness.trim().isNotEmpty)
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
