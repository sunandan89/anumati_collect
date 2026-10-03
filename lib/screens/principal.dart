import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../capture/draft.dart';
import '../capture/flow.dart';
import '../core/receipt_code.dart';
import '../core/strings.dart';
import '../widgets/common.dart';

/// Step 1, who is giving consent: the person themself, a parent for a child under 18, or a guardian for
/// an adult who can't decide alone. Then only what that journey needs. The beneficiary ID is created
/// automatically; people already on the phone are found from Home.
class PrincipalScreen extends StatefulWidget {
  const PrincipalScreen({super.key, required this.draft});
  final CaptureDraft draft;
  @override
  State<PrincipalScreen> createState() => _PrincipalScreenState();
}

class _PrincipalScreenState extends State<PrincipalScreen> {
  CaptureDraft get d => widget.draft;
  late final _name = TextEditingController(text: d.fullName);
  late final _phone = TextEditingController(text: d.phone);
  late final _year = TextEditingController(text: d.birthYear);
  String? _error;
  bool _busy = false;

  Future<void> _continue() async {
    final digits = _phone.text.replaceAll(RegExp(r'\D'), '');
    String? error;
    if (_name.text.trim().isEmpty) error = tr('Enter the name');
    if (error == null && d.who == 'self' && !d.noPhone) {
      if (!(digits.length == 10 || (digits.length == 12 && digits.startsWith('91')))) {
        error = tr('Enter a 10-digit mobile number, or choose No');
      }
    }
    if (error == null && d.who == 'child') {
      final year = int.tryParse(_year.text.trim());
      final now = DateTime.now().year;
      if (year == null || year > now || year < now - 25) {
        error = tr("Enter the child's year of birth, e.g. {0}", [now - 10]);
      } else if (year < now - 18) {
        error = tr('Born in {0}: already 18. Choose “The person, for themself”.', [year]);
      }
    }
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    final s = context.read<AppState>();
    setState(() {
      _error = null;
      _busy = true;
    });
    if (d.principalRef.isEmpty) d.principalRef = newPrincipalRef();
    d.fullName = _name.text.trim();
    d.phone = d.who == 'self' && !d.noPhone ? digits : '';
    d.birthYear = d.who == 'child' ? _year.text.trim() : '';
    // The notice in the chosen language: its uses and extra questions shape the next screens.
    d.notice = await s.notice(d.lang);
    if (!mounted) return;
    setState(() => _busy = false);
    goNext(context, d, 'principal');
  }

  Widget _who(String value, String label) => Opt(
    value: value,
    group: d.who,
    onChanged: (v) => setState(() {
      d.who = v;
      _error = null;
    }),
    title: tr(label),
  );

  Widget _yesNo(
    String question,
    bool yes,
    ValueChanged<bool> onChanged, {
    String yesLabel = 'Yes',
    String noLabel = 'No',
  }) => Row(
    children: [
      Expanded(
        child: Text(tr(question), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      ),
      SegmentedButton<bool>(
        showSelectedIcon: false,
        segments: [
          ButtonSegment(value: true, label: Text(tr(yesLabel))),
          ButtonSegment(value: false, label: Text(tr(noLabel))),
        ],
        selected: {yes},
        onSelectionChanged: (v) => onChanged(v.first),
      ),
    ],
  );

  String? get _hint {
    if (d.who == 'child') {
      return tr(
        "No phone or reading questions for the child. The parent's mobile is asked on the next screen, where it is verified.",
      );
    }
    if (d.who == 'guardian') {
      return tr("The guardian's details, their appointment order and their mobile are asked on the next screen.");
    }
    if (d.needsHelp) {
      return d.noPhone
          ? tr(
              'No phone and needs help reading: at the end you record their “haan” or thumbprint and a witness\'s name. They get a paper slip with their code.',
            )
          : tr(
              'Needs help reading: at the end you record their “haan” or thumbprint and a witness\'s name, and check their phone by SMS code.',
            );
    }
    if (d.noPhone) {
      return tr(
        'No phone: at the end you record their “haan” or a photo of their signature or thumbprint. They get a paper slip with their code.',
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final self = d.who == 'self';
    return StepScaffold(
      bar: StepBar(title: tr('Who is giving consent?'), subtitle: stepLabel(d, 'principal')),
      footer: FilledButton(onPressed: _busy ? null : _continue, child: Text(tr('Continue'))),
      children: [
        _who('self', 'The person, for themself'),
        _who('child', 'A parent, for a child under 18'),
        _who('guardian', "A guardian, for an adult who can't decide alone"),
        TextField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: switch (d.who) {
              'child' => tr("Child's name"),
              'guardian' => tr("Person's name"),
              _ => tr('Name'),
            },
          ),
        ),
        if (d.who == 'child')
          TextField(
            controller: _year,
            keyboardType: TextInputType.number,
            maxLength: 4,
            decoration: InputDecoration(
              labelText: tr("Child's year of birth"),
              helperText: tr('Used only to ask for fresh consent when the child turns 18.'),
              counterText: '',
            ),
          ),
        if (self) ...[
          _yesNo(
            'Has a mobile phone?',
            !d.noPhone,
            (v) => setState(() {
              d.flags['nophone'] = !v;
              if (!v) {
                _phone.clear();
                d.flags['shared'] = false;
              }
            }),
          ),
          if (!d.noPhone)
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(labelText: tr('Mobile number')),
            ),
          _yesNo(
            'Can read the notice?',
            !d.needsHelp,
            (v) => setState(() => d.flags['read'] = !v),
            noLabel: 'Needs help',
          ),
        ],
        Row(
          children: [
            Expanded(
              child: Text(tr('Language'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            ),
            LangSeg(value: d.lang, onChanged: (v) => setState(() => d.lang = v)),
          ],
        ),
        if (self && !d.noPhone)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text(tr('More: phone shared in the household'), style: const TextStyle(fontSize: 14)),
            initiallyExpanded: d.flags['shared']!,
            children: [
              CheckCard(
                value: d.flags['shared']!,
                label: tr('Phone is shared in the household'),
                onChanged: (v) => setState(() => d.flags['shared'] = v),
              ),
            ],
          ),
        if (_hint != null) Note(_hint!),
        Muted(tr('The beneficiary ID is created automatically.')),
        if (_error != null) Note(_error!, danger: true),
      ],
    );
  }
}
