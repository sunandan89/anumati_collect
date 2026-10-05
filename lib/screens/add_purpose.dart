import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../capture/ask_plan.dart';
import '../capture/draft.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../data/store.dart';
import '../widgets/capture_tools.dart';
import '../widgets/common.dart';
import '../widgets/voice_haan.dart';

/// Add a use or rejoin, on a later visit (spec A2, A4, v0.4): shows what the person
/// already agreed to (not asked again), only the new purpose's part of the
/// notice, equal-weight Yes/No, and the same verification method as before.
/// A use they withdrew or refused can be asked again (they changed their mind),
/// and someone who left the programme can rejoin it (its essential use).
/// Someone who needs help reading also needs a witness, as at first consent.
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
  bool _online = true;
  bool _codeMatched = false;
  EvidenceRef? _voice;
  bool _saving = false;
  final _witness = TextEditingController();

  @override
  void dispose() {
    _witness.dispose();
    super.dispose();
  }

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
    final online = await s.online();
    setState(() {
      _p = p;
      _notice = n;
      _decided = decided;
      _online = online;
    });
  }

  /// A phone gets a code from the server after Save (later by SMS when offline); no phone: evidence only.
  String get _method {
    if ((_p?.phone ?? '').isEmpty) return 'evidence_only';
    final s = context.read<AppState>();
    // Server code (MSG91) when online, unless the programme always uses the worker's phone; a worker-phone
    // code needs the person's voice "haan" with it.
    return _online && !s.workerPhoneCodes && s.allowedVerification.contains('server_otp') && _notice!.serverCodes
        ? 'server_otp'
        : 'device_sms_otp';
  }

  AskPlan get _plan => AskPlan(
    purposes: _notice?.purposes ?? const [],
    decided: _decided,
    minor: _p!.flag('minor'),
    hasPhone: (_p!.phone ?? '').isNotEmpty,
  );

  List<NoticePurpose> get _new => _plan.toAsk;

  bool get _ready =>
      _plan.complete(_answer) &&
      (!_p!.flag('read') || _witness.text.trim().isNotEmpty) &&
      (_method != 'device_sms_otp' || (_codeMatched && _voice != null)) &&
      // No phone: their voice "haan" is the proof (rule A1).
      (_method != 'evidence_only' || _voice != null);

  void _answerOne(String code, bool yes) => setState(() {
    _answer[code] = yes;
    // No to rejoining: the other uses no longer apply, so drop their answers.
    if (!yes && _plan.rejoinCodes.contains(code)) {
      _answer.removeWhere((c, _) => !_plan.rejoinCodes.contains(c));
    }
  });

  void _answerAll(bool yes) => setState(() {
    for (final pu in _new) {
      _answer[pu.code] = yes;
    }
    if (!yes) _answer.removeWhere((c, _) => _plan.rejoinCodes.isNotEmpty && !_plan.rejoinCodes.contains(c));
  });

  Future<void> _save() async {
    final s = context.read<AppState>();
    setState(() => _saving = true);
    final method = _method;
    final saved = await s.saveAddedPurposes(
      principal: _p!,
      notice: _notice!,
      answers: Map.of(_answer),
      verifyMethod: method,
      witness: _p!.flag('read') ? _witness.text.trim() : null,
      voice: method == 'server_otp' ? null : _voice,
    );
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Saved on this phone')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Muted(tr('Consent code — write it on their slip')),
              const SizedBox(height: 8),
              SelectableText(
                saved.code,
                style: const TextStyle(fontSize: 28, letterSpacing: 2, fontFamily: 'monospace'),
              ),
              if (method == 'server_otp') ...[const SizedBox(height: 12), ServerCodePanel(eventUuid: saved.eventUuid)],
            ],
          ),
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
      'server_otp' => tr('Code from the server, after Save'),
      'device_sms_otp' => tr('Code from your phone, with their voice “haan”'),
      'evidence_only' => tr('Evidence only'),
      _ => tr('Confirm later'),
    };
    final guarded = p.flag('minor') || p.flag('pwd');
    return StepScaffold(
      bar: StepBar(title: tr('Add a use or rejoin'), subtitle: tr('Later visit · {0}', [p.fullName])),
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
        Muted(tr('Already agreed — not asked again')),
        for (final pu in _plan.agreed)
          Row(
            children: [
              Expanded(child: Text(pu.title, style: const TextStyle(fontSize: 13))),
              StatusChip(statusLabel(_decided[pu.code]), tone: statusTone(_decided[pu.code])),
            ],
          ),
        const Divider(color: AC.terra),
        if (guarded) Note(tr('A guardian must consent for this person. Take a new consent with the guardian.')),
        if (!guarded && _new.isEmpty) Note(tr('Nothing to ask: every use on this notice is already agreed.')),
        if (!guarded && _new.length > 1) ...[
          // Equal weight, as on the first consent; each part must still be read before it is answered.
          Row(
            children: [
              for (final yes in [true, false]) ...[
                Expanded(
                  child: OutlinedButton(
                    onPressed: _new.every((pu) => _read[pu.code] ?? false) ? () => _answerAll(yes) : null,
                    child: Text(trFor(l, yes ? 'Yes to all' : 'No to all')),
                  ),
                ),
                if (yes) const SizedBox(width: 8),
              ],
            ],
          ),
          if (!_new.every((pu) => _read[pu.code] ?? false)) Muted(tr('Read every part to them to answer all at once.')),
        ],
        if (!guarded && _plan.declinedRejoin(_answer))
          Note(tr('They do not want to rejoin, so the other uses do not apply. Nothing to save.')),
        if (!guarded)
          for (final pu in _new)
            PCard(
              borderColor: _plan.canAnswer(pu.code, _answer) ? AC.leaf : AC.line,
              color: _plan.canAnswer(pu.code, _answer) ? null : AC.surface.withValues(alpha: 0.5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${trFor(l, switch (_plan.kinds[pu.code]) {
                      AskKind.rejoin => 'Rejoin the programme',
                      AskKind.askAgain => 'Ask again',
                      _ => 'New use',
                    })}: '
                    '${pu.title}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (pu.description.isNotEmpty) Text(pu.description, style: const TextStyle(fontSize: 14)),
                  const SizedBox(height: 6),
                  Muted(tr('Read this part of the notice to them')),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _read[pu.code] ?? false,
                    onChanged: (v) => setState(() => _read[pu.code] = v ?? false),
                    title: Text(tr('I have read it to them'), style: const TextStyle(fontSize: 14)),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  if (!_plan.canAnswer(pu.code, _answer)) Muted(tr('Answer “Rejoin the programme” first.')),
                  Row(
                    children: [
                      for (final yes in [true, false]) ...[
                        Expanded(
                          child: _answer[pu.code] == yes
                              ? FilledButton(onPressed: () {}, child: Text(trFor(l, yes ? 'Yes' : 'No')))
                              : OutlinedButton(
                                  onPressed: (_read[pu.code] ?? false) && _plan.canAnswer(pu.code, _answer)
                                      ? () => _answerOne(pu.code, yes)
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
          Muted(tr('How this is confirmed: {0}.', [methodLabel])),
          if (_method == 'evidence_only')
            VoiceHaanTile(
              title: tr('Voice: their “haan”'),
              value: _voice,
              lang: l,
              onSaved: (r) => setState(() => _voice = r),
            ),
          if (_method == 'device_sms_otp') ...[
            OtpPanel(phone: p.phone!, lang: l, onConfirmed: () => setState(() => _codeMatched = true)),
            VoiceHaanTile(
              title: tr('Voice: their “haan”'),
              value: _voice,
              lang: l,
              onSaved: (r) => setState(() => _voice = r),
            ),
          ],
          if (p.flag('read'))
            TextField(
              controller: _witness,
              textCapitalization: TextCapitalization.words,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: tr('Witness name'),
                helperText: tr('Needed because the notice was read to them'),
              ),
            ),
        ],
      ],
    );
  }
}
