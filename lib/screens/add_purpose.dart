import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../capture/draft.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../data/store.dart';
import '../widgets/capture_tools.dart';
import '../widgets/common.dart';

/// Ask for one more purpose, later (spec A2, A4, v0.4): shows what she has
/// already decided (not asked again), only the new purpose's part of the
/// notice, equal-weight Yes/No, and the same verification method as before.
class AddPurposeScreen extends StatefulWidget {
  const AddPurposeScreen({super.key, required this.principalRef});
  final String principalRef;
  @override
  State<AddPurposeScreen> createState() => _AddPurposeScreenState();
}

class _AddPurposeScreenState extends State<AddPurposeScreen> {
  LocalPrincipal? _p;
  Notice? _notice;
  Map<String, String> _decided = {};
  final Map<String, bool> _read = {};
  final Map<String, bool> _answer = {};
  bool _confirmed = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = context.read<AppState>();
    final p = await s.store!.principal(widget.principalRef);
    if (p == null) return;
    final n = await s.notice(p.lang);
    final decided = await s.store!.decisions(p.ref, s.programme!);
    setState(() {
      _p = p;
      _notice = n;
      _decided = decided;
    });
  }

  String get _method => _p?.verificationMethod ?? ((_p?.phone ?? '').isEmpty ? 'evidence_only' : 'device_sms_otp');

  List<NoticePurpose> get _new => [
    for (final pu in _notice?.purposes ?? const <NoticePurpose>[])
      if (!pu.essential && !_decided.containsKey(pu.code) && !(_p!.flag('minor') && !pu.childAllowed)) pu,
  ];

  bool get _ready =>
      _new.isNotEmpty &&
      _new.every((pu) => _answer.containsKey(pu.code)) &&
      (_method != 'device_sms_otp' || _confirmed);

  Future<void> _save() async {
    final s = context.read<AppState>();
    setState(() => _saving = true);
    final code = await s.saveAddedPurposes(
      principal: _p!,
      notice: _notice!,
      answers: Map.of(_answer),
      verifyMethod: _method,
      confirmed: _confirmed,
    );
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Saved on this phone')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Muted(tr('Consent code — write it on her slip')),
            const SizedBox(height: 8),
            SelectableText(code, style: const TextStyle(fontSize: 28, letterSpacing: 2, fontFamily: 'monospace')),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
      ),
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    final n = _notice;
    if (p == null || n == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final l = p.lang;
    final methodLabel = switch (_method) {
      'device_sms_otp' => tr('SMS code from this phone'),
      'evidence_only' => tr('Evidence only'),
      _ => tr('Confirm later'),
    };
    final guarded = p.flag('minor') || p.flag('pwd');
    return StepScaffold(
      bar: StepBar(title: tr('Ask for one more purpose'), subtitle: tr('Later visit · {0}', [p.fullName])),
      footer: FilledButton(onPressed: _ready && !_saving && !guarded ? _save : null, child: Text(tr('Save'))),
      children: [
        PCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(p.fullName, style: const TextStyle(fontWeight: FontWeight.w600)),
              Muted([p.ref, ?p.lastCode, Strings.languages[l] ?? l].join(' · ')),
            ],
          ),
        ),
        Muted(tr('Already decided — not asked again')),
        for (final pu in n.purposes.where((pu) => _decided.containsKey(pu.code)))
          Row(
            children: [
              Expanded(child: Text(pu.title, style: const TextStyle(fontSize: 13))),
              StatusChip(statusLabel(_decided[pu.code]), tone: statusTone(_decided[pu.code])),
            ],
          ),
        const Divider(color: AC.terra),
        if (guarded) Note(tr('A guardian must consent for this person. Take a new consent with the guardian.')),
        if (!guarded && _new.isEmpty) Note(tr('Nothing new to ask on this notice.')),
        if (!guarded)
          for (final pu in _new)
            PCard(
              borderColor: AC.leaf,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('${trFor(l, 'New use')}: ${pu.title}', style: const TextStyle(fontWeight: FontWeight.w600)),
                  if (pu.description.isNotEmpty) Text(pu.description, style: const TextStyle(fontSize: 14)),
                  const SizedBox(height: 6),
                  Muted(tr('Read this part of the notice to her')),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _read[pu.code] ?? false,
                    onChanged: (v) => setState(() => _read[pu.code] = v ?? false),
                    title: Text(tr('I have read it to her'), style: const TextStyle(fontSize: 14)),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  Row(
                    children: [
                      for (final yes in [true, false]) ...[
                        Expanded(
                          child: _answer[pu.code] == yes
                              ? FilledButton(onPressed: () {}, child: Text(trFor(l, yes ? 'Yes' : 'No')))
                              : OutlinedButton(
                                  onPressed: (_read[pu.code] ?? false)
                                      ? () => setState(() => _answer[pu.code] = yes)
                                      : null,
                                  child: Text(trFor(l, yes ? 'Yes' : 'No')),
                                ),
                        ),
                        if (yes) const SizedBox(width: 8),
                      ],
                    ],
                  ),
                ],
              ),
            ),
        if (!guarded && _new.isNotEmpty) ...[
          Muted(tr('Verified with the same method as last time: {0}.', [methodLabel])),
          if (_method == 'device_sms_otp' && (p.phone ?? '').isNotEmpty)
            OtpPanel(phone: p.phone!, lang: l, onConfirmed: () => setState(() => _confirmed = true)),
        ],
      ],
    );
  }
}
