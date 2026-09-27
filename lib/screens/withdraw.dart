import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../capture/draft.dart';
import '../core/strings.dart';
import '../data/store.dart';
import '../widgets/common.dart';

/// M8 Log a withdrawal (spec B4, B5): any worker can log a withdrawal or a
/// rights request offline. A withdrawal takes effect on the phone at once and
/// is signed on the server at sync. Someone not on this phone goes to the
/// office inbox with the code she gave.
class WithdrawScreen extends StatefulWidget {
  const WithdrawScreen({super.key, this.principalRef});
  final String? principalRef;
  @override
  State<WithdrawScreen> createState() => _WithdrawScreenState();
}

class _WithdrawScreenState extends State<WithdrawScreen> {
  String _source = 'person';
  final _query = TextEditingController();
  final _paper = TextEditingController();
  List<LocalPrincipal> _matches = [];
  LocalPrincipal? _who;
  Map<String, String> _decided = {};
  List<NoticePurpose> _purposes = [];
  String _want = 'all';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadPurposes();
    if (widget.principalRef != null) {
      _query.text = widget.principalRef!;
      _search();
    }
  }

  Future<void> _loadPurposes() async {
    final n = await context.read<AppState>().notice('en');
    setState(() => _purposes = n?.purposes ?? []);
  }

  Future<void> _search() async {
    final s = context.read<AppState>();
    final q = _query.text.trim();
    final found = q.length < 2 ? <LocalPrincipal>[] : await s.store!.search(q, programme: s.programme);
    setState(() {
      _matches = found;
      if (found.length == 1) _pick(found.first);
      if (found.isEmpty) _who = null;
    });
  }

  Future<void> _pick(LocalPrincipal p) async {
    final s = context.read<AppState>();
    final decided = await s.store!.decisions(p.ref, s.programme!);
    setState(() {
      _who = p;
      _decided = decided;
    });
  }

  String get _channel => _source == 'person' ? 'field_worker' : 'slip';

  Future<void> _save() async {
    final s = context.read<AppState>();
    setState(() => _saving = true);
    final who = _who;
    final code = _query.text.trim();
    if (_want == 'all' || _want.startsWith('stop:')) {
      if (who != null) {
        await s.saveWithdrawal(
          principalRef: who.ref,
          channel: _channel,
          purposes: _want == 'all' ? null : [_want.substring(5)],
        );
      } else {
        await s.saveRequest(
          requestType: 'withdrawal',
          channel: _channel,
          note: 'Code or ID given: $code${_want == 'all' ? '' : ' · purpose: ${_want.substring(5)}'}',
          paperTrail: _paper.text.trim(),
        );
      }
    } else {
      await s.saveRequest(
        requestType: _want,
        channel: _channel,
        principalRef: who?.ref,
        note: who == null ? 'Code or ID given: $code' : null,
        paperTrail: _paper.text.trim(),
      );
    }
    if (!mounted) return;
    toast(context, tr('Saved on this phone. It takes effect now and reaches the office on sync.'));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final granted = [
      for (final p in _purposes)
        if (!p.essential && _decided[p.code] == 'granted') p,
    ];
    final options = <String, String>{
      'all': tr('Stop all optional uses'),
      if (_who != null)
        for (final p in granted) 'stop:${p.code}': tr('Stop only: {0}', [p.title]),
      'erasure': tr('Delete my data'),
      'access': tr('See or correct my data'),
      'grievance': tr('Complaint'),
    };
    if (!options.containsKey(_want)) _want = 'all';
    final hasQuery = _query.text.trim().length >= 2;
    return StepScaffold(
      bar: StepBar(title: tr('Log what she asked for'), subtitle: tr('Withdrawal or request')),
      footer: FilledButton(onPressed: _saving || (!hasQuery && _who == null) ? null : _save, child: Text(tr('Save'))),
      children: [
        Muted(tr('How did it reach you?')),
        SegmentedButton<String>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(value: 'person', label: Text(tr('In person'))),
            ButtonSegment(value: 'slip', label: Text(tr('Paper slip'))),
            ButtonSegment(value: 'letter', label: Text(tr('Letter'))),
          ],
          selected: {_source},
          onSelectionChanged: (v) => setState(() => _source = v.first),
        ),
        TextField(
          controller: _query,
          textCapitalization: TextCapitalization.characters,
          onChanged: (_) => _search(),
          decoration: InputDecoration(labelText: tr('Consent code, name or ID'), prefixIcon: const Icon(Icons.search)),
        ),
        if (_source != 'person')
          TextField(
            controller: _paper,
            decoration: InputDecoration(labelText: tr('Paper slip number (optional)')),
          ),
        for (final m in _matches)
          PCard(
            borderColor: _who?.ref == m.ref ? Theme.of(context).colorScheme.primary : null,
            onTap: () => _pick(m),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(m.fullName, style: const TextStyle(fontWeight: FontWeight.w600)),
                      Muted('${m.ref}${m.lastCode != null ? ' · ${m.lastCode}' : ''} · ${tr('Found on this phone')}'),
                    ],
                  ),
                ),
                if (_who?.ref == m.ref) const Icon(Icons.check),
              ],
            ),
          ),
        if (hasQuery && _matches.isEmpty) Note(tr('Not on this phone. It goes to the office inbox with the code.')),
        Muted(tr('What does she want?')),
        for (final e in options.entries)
          Opt(value: e.key, group: _want, onChanged: (v) => setState(() => _want = v), title: e.value),
      ],
    );
  }
}
