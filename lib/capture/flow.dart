import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import '../app_state.dart';
import '../core/strings.dart';
import '../screens/about.dart';
import '../screens/confirm.dart';
import '../screens/guardian.dart';
import '../screens/notice.dart';
import '../screens/receipt.dart';
import 'draft.dart';

/// The capture steps: three screens for every journey.
/// - the person: who, notice and choices, confirm (proof, witness when needed);
/// - a parent or guardian: who, the guardian (verified there), notice and choices with Save.
/// "About the person" comes after the choices only when the programme asks extra questions.
List<String> flowSteps(CaptureDraft d) => [
  'principal',
  if (d.needsGuardian) 'guardian',
  'notice',
  if (d.questions.isNotEmpty) 'about',
  if (!d.needsGuardian) 'confirm',
];

bool isLastStep(CaptureDraft d, String step) => flowSteps(d).last == step;

/// Save the consent to the phone's outbox and show the receipt.
Future<void> finishCapture(BuildContext context, CaptureDraft d) async {
  d.settleVerification();
  await context.read<AppState>().saveConsent(d);
  if (!context.mounted) return;
  Navigator.of(
    context,
  ).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => ReceiptScreen(draft: d)), (r) => r.isFirst);
}

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
    'about' => AboutScreen(draft: d),
    _ => ConfirmScreen(draft: d),
  };
  Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
}

/// What Save still needs, in the worker's words ("To save: …"), or null when ready.
String? missingText(List<String> missing) {
  if (missing.isEmpty) return null;
  final words = {
    'notice': tr('play the whole notice'),
    'answers': tr('answer the required questions'),
    'SMS code': tr('the SMS code'),
    'proof': tr('a voice “haan” or a photo'),
    'witness': tr("the witness's name"),
    'tick': tr('tick the declaration'),
    'relation': tr('the relation'),
    'order number': tr('the order number'),
    'name': tr('the name'),
    'mobile number': tr('a 10-digit mobile number'),
    'ID photo (no phone)': tr("a photo of the guardian's ID (no phone)"),
  };
  return tr('To save: {0}', [missing.map((m) => words[m] ?? m).join(', ')]);
}

/// The declaration the worker ticks before saving, in every journey.
String attestationText(CaptureDraft d) => d.needsGuardian
    ? tr(
        'I played the full notice to the guardian, answered their questions, and they chose freely. Nothing was pre-selected.',
      )
    : tr(
        "I played the full notice in the person's language, answered their questions, and they chose freely. Nothing was pre-selected.",
      );
