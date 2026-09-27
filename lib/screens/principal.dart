import 'package:flutter/material.dart';

import '../capture/draft.dart';
import '../capture/flow.dart';
import '../core/receipt_code.dart';
import '../core/strings.dart';
import '../widgets/common.dart';

/// M2 Beneficiary: who is consenting, segment flags, language.
class PrincipalScreen extends StatefulWidget {
  const PrincipalScreen({super.key, required this.draft});
  final CaptureDraft draft;
  @override
  State<PrincipalScreen> createState() => _PrincipalScreenState();
}

class _PrincipalScreenState extends State<PrincipalScreen> {
  CaptureDraft get d => widget.draft;
  late final _id = TextEditingController(text: d.principalRef);
  late final _name = TextEditingController(text: d.fullName);
  late final _phone = TextEditingController(text: d.phone);
  String? _error;

  static final _flagLabels = {
    'read': 'Needs help reading the notice',
    'shared': 'Phone is shared in the household',
    'nophone': 'No phone',
    'minor': 'Under 18 — guardian will consent',
    'pwd': 'Has a lawful guardian (disability)',
  };

  void _continue() {
    final digits = _phone.text.replaceAll(RegExp(r'\D'), '');
    if (_name.text.trim().isEmpty) {
      setState(() => _error = tr('Enter a name'));
      return;
    }
    if (!d.noPhone && digits.isEmpty) d.flags['nophone'] = true;
    if (!d.noPhone && !(digits.length == 10 || (digits.length == 12 && digits.startsWith('91')))) {
      setState(() => _error = tr('Enter a 10-digit mobile number, or tick No phone'));
      return;
    }
    d.principalRef = _id.text.trim().isEmpty ? newPrincipalRef() : _id.text.trim();
    _id.text = d.principalRef;
    d.fullName = _name.text.trim();
    d.phone = d.noPhone ? '' : digits;
    d.verifyMethod = d.noPhone ? 'evidence_only' : 'device_sms_otp';
    setState(() => _error = null);
    goNext(context, d, 'principal');
  }

  @override
  Widget build(BuildContext context) {
    return StepScaffold(
      bar: StepBar(title: tr('Who is giving consent?'), subtitle: stepLabel(d, 'principal')),
      footer: FilledButton(onPressed: _continue, child: Text(tr('Continue'))),
      children: [
        TextField(
          controller: _id,
          decoration: InputDecoration(labelText: tr('Beneficiary ID'), helperText: tr('Leave blank to create one')),
        ),
        TextField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(labelText: tr('Name')),
        ),
        TextField(
          controller: _phone,
          enabled: !d.noPhone,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(labelText: tr('Mobile (optional)')),
        ),
        Muted(tr('Tick all that apply')),
        for (final e in _flagLabels.entries)
          CheckCard(
            value: d.flags[e.key]!,
            label: tr(e.value),
            onChanged: (v) => setState(() {
              d.flags[e.key] = v;
              if (e.key == 'minor' && v) d.flags['pwd'] = false;
              if (e.key == 'pwd' && v) d.flags['minor'] = false;
              if (e.key == 'nophone' && v) _phone.clear();
            }),
          ),
        Muted(tr('Language for notice, SMS and calls')),
        Align(
          alignment: Alignment.centerLeft,
          child: LangSeg(value: d.lang, onChanged: (v) => setState(() => d.lang = v)),
        ),
        if (_error != null) Note(_error!, danger: true),
      ],
    );
  }
}
