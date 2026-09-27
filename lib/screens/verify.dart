import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../capture/draft.dart';
import '../capture/flow.dart';
import '../core/strings.dart';
import '../widgets/capture_tools.dart';
import '../widgets/common.dart';

/// M6 Verify (spec section 5, verification ladder): the methods that work
/// from the phone, limited to what the programme allows.
class VerifyScreen extends StatefulWidget {
  const VerifyScreen({super.key, required this.draft});
  final CaptureDraft draft;
  @override
  State<VerifyScreen> createState() => _VerifyScreenState();
}

class _VerifyScreenState extends State<VerifyScreen> {
  CaptureDraft get d => widget.draft;
  bool _saving = false;

  static const _labels = {
    'device_sms_otp': ('SMS code from this phone', 'Opens your SMS app with a code for her number. She reads it back.'),
    'deferred': ('Confirm later', 'SMS after sync: “Reply STOP to withdraw”.'),
    'evidence_only': ('No phone — evidence only', 'Uses the voice, thumbprint and witness.'),
  };

  List<String> _methods(AppState s) {
    final allowed = s.allowedVerification;
    if (d.noPhone) return allowed.where((m) => m == 'evidence_only').toList();
    return allowed;
  }

  bool get _canSave => d.verifyMethod != 'device_sms_otp' || d.otpConfirmed;

  Future<void> _save(AppState s) async {
    setState(() => _saving = true);
    await finishCapture(context, d);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final methods = _methods(s);
    if (methods.isNotEmpty && !methods.contains(d.verifyMethod)) d.verifyMethod = methods.first;
    return StepScaffold(
      bar: StepBar(title: tr('Verify the phone'), subtitle: stepLabel(d, 'verify')),
      footer: FilledButton(
        onPressed: methods.isEmpty || !_canSave || _saving ? null : () => _save(s),
        child: Text(d.verifyMethod == 'device_sms_otp' ? tr('Verify and save') : tr('Save')),
      ),
      children: [
        if (methods.isEmpty)
          Note(tr('This programme allows none of the methods available on the phone.'), danger: true),
        for (final m in methods) ...[
          Opt(
            value: m,
            group: d.verifyMethod,
            onChanged: (v) => setState(() => d.verifyMethod = v),
            title: tr(_labels[m]!.$1),
            subtitle: tr(_labels[m]!.$2),
            badge: m == methods.first ? tr('Best now') : null,
            enabled: !(m == 'evidence_only' && d.selfChosen && !d.noPhone),
          ),
          if (m == 'device_sms_otp' && d.verifyMethod == m && d.phone.isNotEmpty)
            OtpPanel(phone: d.phone, lang: d.lang, onConfirmed: () => setState(() => d.otpConfirmed = true)),
        ],
      ],
    );
  }
}
