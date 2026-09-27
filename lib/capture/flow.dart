import 'package:flutter/material.dart';

import '../core/strings.dart';
import '../screens/evidence.dart';
import '../screens/guardian.dart';
import '../screens/notice.dart';
import '../screens/purposes.dart';
import '../screens/verify.dart';
import 'draft.dart';

/// The capture steps. The guardian step appears only for minors and people
/// with a lawful guardian (spec C1, C2).
List<String> flowSteps(CaptureDraft d) => [
  'principal',
  if (d.needsGuardian) 'guardian',
  'notice',
  'purposes',
  'evidence',
  'verify',
];

String stepLabel(CaptureDraft d, String step) {
  final steps = flowSteps(d);
  return tr('Step {0} of {1}', [steps.indexOf(step) + 1, steps.length]);
}

void goNext(BuildContext context, CaptureDraft d, String from) {
  final steps = flowSteps(d);
  final next = steps[steps.indexOf(from) + 1];
  final Widget screen = switch (next) {
    'guardian' => GuardianScreen(draft: d),
    'notice' => NoticeScreen(draft: d),
    'purposes' => PurposesScreen(draft: d),
    'evidence' => EvidenceScreen(draft: d),
    _ => VerifyScreen(draft: d),
  };
  Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
}
