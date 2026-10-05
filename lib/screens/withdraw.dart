import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import '../capture/draft.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../data/store.dart';
import '../widgets/common.dart';

/// M8 Stop a use or leave (spec B4, B5, section 6): as easy as giving it. Find the person, switch off
/// the uses they no longer agree to (or leave the programme), and it takes effect on the phone at once;
/// it is signed on the server at sync. Other requests go to the office inbox. Someone not on this phone
/// goes to the inbox with the code they gave.
class WithdrawScreen extends StatefulWidget {
  const WithdrawScreen({super.key, this.principalRef});
  final String? principalRef;
  @override
  State<WithdrawScreen> createState() => _WithdrawScreenState();
}

class _WithdrawScreenState extends State<WithdrawScreen> {
  final _query = TextEditingController();
  final _paper = TextEditingController();
  bool _slip = false;
  List<LocalPrincipal> _matches = [];
  LocalPrincipal? _who;
  Map<String, String> _decided = {};
  List<NoticePurpose> _purposes = [];

  /// Uses the worker switched off, leaving the programme, or another request: one of the three.
  final Set<String> _off = {};
  bool _leave = false;
  String? _request;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadPurposes('en');
    if (widget.principalRef != null) {
      _query.text = widget.principalRef!;
      _search();
    }
  }

  @override
  void dispose() {
    _query.dispose();
    _paper.dispose();
    super.dispose();
  }

  Future<void> _loadPurposes(String lang) async {
    final n = await context.read<AppState>().notice(lang);
    if (mounted) setState(() => _purposes = n?.purposes ?? []);
  }

  Future<void> _search() async {
    final s = context.read<AppState>();
    final q = _query.text.trim();
    final found = q.length < 2 ? <LocalPrincipal>[] : await s.store!.search(q, programme: s.programme);
    setState(() {
      _matches = found;
      if (found.isEmpty) _clearPerson();
    });
    if (found.length == 1) await _pick(found.first);
  }

  void _clearPerson() {
    _who = null;
    _decided = {};
    _off.clear();
    _leave = false;
  }

  Future<void> _pick(LocalPrincipal p) async {
    final s = context.read<AppState>();
    final decided = await s.store!.decisions(p.ref, s.programme!);
    await _loadPurposes(p.lang);
    setState(() {
      _clearPerson();
      _who = p;
      _decided = decided;
      _request = null;
    });
  }

  String get _channel => _slip ? 'slip' : 'field_worker';

  /// What was typed, if it looks like a receipt code (AN-7K2Q9C or 7K2Q9C): the office uses it to find them.
  String? get _code {
    final q = _query.text.trim().toUpperCase();
    return RegExp(r'^(AN-)?[A-Z2-7]{6}$').hasMatch(q) ? (q.startsWith('AN-') ? q : 'AN-$q') : null;
  }

  List<NoticePurpose> get _on => [
    for (final p in _purposes)
      if (_decided[p.code] == 'granted') p,
  ];

  void _toggle(String code, bool keepOn) => setState(() {
    keepOn ? _off.remove(code) : _off.add(code);
    _leave = false;
    _request = null;
  });

  void _choose(String request) => setState(() {
    _request = request;
    _off.clear();
    _leave = false;
  });

  Future<void> _askLeave() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Leave the programme?')),
        content: Text(
          tr(
            'This stops every use of their data in this programme, essential ones too. '
            'The programme stops serving them. Do they still want this?',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Yes, leave'))),
        ],
      ),
    );
    if (yes == true) {
      setState(() {
        _leave = true;
        _off.clear();
        _request = null;
      });
    }
  }

  Future<void> _save() async {
    final s = context.read<AppState>();
    setState(() => _saving = true);
    final who = _who;
    final paper = _slip ? _paper.text.trim() : '';
    if (who != null && (_off.isNotEmpty || _leave)) {
      final stopped = _leave ? _on : _on.where((p) => _off.contains(p.code)).toList();
      final code = await s.saveWithdrawal(
        principalRef: who.ref,
        channel: _channel,
        purposes: _leave ? null : _off.toList(),
        leave: _leave,
        paperTrail: paper,
      );
      if (!mounted) return;
      await _noted(who, stopped, code);
    } else if (_request != null) {
      final leave = _request == 'leave';
      await s.saveRequest(
        requestType: leave ? 'withdrawal' : _request!,
        channel: _channel,
        principalRef: who?.ref,
        note: [
          if (who == null) 'Code or ID given: ${_query.text.trim()}',
          if (leave) 'Leave the programme',
        ].join(' · '),
        paperTrail: paper,
        consentCode: who == null ? _code : null,
      );
      if (!mounted) return;
      toast(context, tr('Saved on this phone. It reaches the office inbox on sync.'));
    }
    if (mounted) Navigator.pop(context);
  }

  /// What was stopped and the withdrawal code for their slip, with an SMS from the worker's phone to them
  /// (or, for a child or an adult with a guardian, to the guardian).
  Future<void> _noted(LocalPrincipal who, List<NoticePurpose> stopped, String code) async {
    final names = stopped.map((p) => p.title).join(', ');
    final to = who.contactPhone;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Withdrawal noted')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_leave ? tr('They have left the programme.') : tr('Stopped: {0}', [names])),
            const SizedBox(height: 12),
            Muted(tr('Withdrawal code — write it on their slip')),
            SelectableText(code, style: const TextStyle(fontSize: 26, letterSpacing: 2, fontFamily: 'monospace')),
            const SizedBox(height: 8),
            Muted(tr('It takes effect on this phone now and reaches the office on sync.')),
          ],
        ),
        actions: [
          if (to != null)
            TextButton(
              onPressed: () => launchUrl(
                Uri(
                  scheme: 'sms',
                  path: to,
                  queryParameters: {
                    'body': _leave
                        ? trFor(who.lang, 'Anumati {0}: you have left the programme. Your data will not be used.', [
                            code,
                          ])
                        : trFor(who.lang, 'Anumati {0}: you have stopped {1}. To agree again, tell any worker.', [
                            code,
                            names,
                          ]),
                  },
                ),
              ),
              child: Text(tr('Send by SMS')),
            ),
          FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
  }

  String get _saveLabel {
    final who = _who;
    if (who != null && _off.isNotEmpty) {
      return _off.length == 1
          ? tr('Stop 1 use for {0}', [who.fullName])
          : tr('Stop {0} uses for {1}', [_off.length, who.fullName]);
    }
    if (_leave) return tr('Leave the programme');
    if (_request != null) return tr('Save request');
    return tr('Save');
  }

  @override
  Widget build(BuildContext context) {
    final who = _who;
    final hasQuery = _query.text.trim().length >= 2;
    final notFound = who == null && hasQuery && _matches.isEmpty;
    final optionalOn = _on.where((p) => !p.essential).toList();
    final essentialOn = _on.where((p) => p.essential).toList();
    final off = [
      for (final p in _purposes)
        if (_decided[p.code] == 'withdrawn' || _decided[p.code] == 'refused') p,
    ];
    final allOff = optionalOn.isNotEmpty && optionalOn.every((p) => _off.contains(p.code));
    final ready = (who != null && (_off.isNotEmpty || _leave)) || (_request != null && (who != null || notFound));
    return StepScaffold(
      bar: StepBar(title: tr('Stop a use or leave'), subtitle: tr('Withdrawal or request')),
      footer: FilledButton(
        style: _leave ? FilledButton.styleFrom(backgroundColor: AC.danger) : null,
        onPressed: _saving || !ready ? null : _save,
        child: Text(_saveLabel),
      ),
      children: [
        TextField(
          controller: _query,
          textCapitalization: TextCapitalization.characters,
          onChanged: (_) => _search(),
          decoration: InputDecoration(
            labelText: tr('Receipt code, name, ID or phone'),
            prefixIcon: const Icon(Icons.search),
          ),
        ),
        if (_matches.length > 1)
          for (final m in _matches)
            PCard(
              borderColor: who?.ref == m.ref ? Theme.of(context).colorScheme.primary : null,
              onTap: () => _pick(m),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(m.fullName, style: const TextStyle(fontWeight: FontWeight.w600)),
                        Muted('${m.ref}${m.lastCode != null ? ' · ${m.lastCode}' : ''}'),
                        if (phoneMatchLabel(m, _query.text) case final label?) Muted(label),
                      ],
                    ),
                  ),
                  if (who?.ref == m.ref) const Icon(Icons.check),
                ],
              ),
            ),
        if (notFound) Note(tr('Not on this phone. It goes to the office inbox with the code.')),
        if (who != null) ...[
          PCard(
            borderColor: AC.terra,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(who.fullName, style: const TextStyle(fontWeight: FontWeight.w600)),
                Muted([who.ref, ?who.lastCode].join(' · ')),
                if (phoneMatchLabel(who, _query.text) case final label?) Muted(label),
              ],
            ),
          ),
          if (_on.isEmpty) Note(tr('Nothing is on for this person, so there is nothing to stop.')),
          if (optionalOn.isNotEmpty) ...[
            Row(
              children: [
                Expanded(child: Muted(tr('Switch off what they no longer agree to'))),
                if (!_leave)
                  TextButton(
                    onPressed: () => setState(() {
                      allOff ? _off.clear() : _off.addAll(optionalOn.map((p) => p.code));
                      _request = null;
                    }),
                    child: Text(allOff ? tr('Keep all') : tr('Stop all')),
                  ),
              ],
            ),
            for (final p in optionalOn)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: !_leave && !_off.contains(p.code),
                onChanged: _leave ? null : (v) => _toggle(p.code, v),
                title: Text(p.title),
                subtitle: Text(
                  _leave || _off.contains(p.code) ? tr('Will stop') : tr('On'),
                  style: TextStyle(fontSize: 12, color: _leave || _off.contains(p.code) ? AC.danger : AC.ink3),
                ),
              ),
          ],
          for (final p in essentialOn)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.lock_outline),
              title: Text(p.title),
              subtitle: Text(
                _leave ? tr('Will stop') : tr('Needed for the programme. To stop it, they leave the programme.'),
                style: TextStyle(fontSize: 12, color: _leave ? AC.danger : null),
              ),
            ),
          if (off.isNotEmpty) Muted(tr('Already off: {0}', [off.map((p) => p.title).join(', ')])),
          if (essentialOn.isNotEmpty)
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AC.danger,
                side: BorderSide(color: AC.danger, width: _leave ? 2 : 1),
              ),
              onPressed: _leave ? () => setState(() => _leave = false) : _askLeave,
              icon: Icon(_leave ? Icons.undo : Icons.logout),
              label: Text(_leave ? tr('Don\'t leave') : tr('Leave the programme')),
            ),
          if (_leave) Note(tr('Every use above will stop, and the programme stops serving them.'), danger: true),
        ],
        if (notFound) ...[
          Muted(tr('What do they want?')),
          Opt<String?>(
            value: 'withdrawal',
            group: _request,
            onChanged: (v) => _choose(v!),
            title: tr('Stop all optional uses'),
          ),
          Opt<String?>(
            value: 'leave',
            group: _request,
            onChanged: (v) => _choose(v!),
            title: tr('Leave the programme'),
          ),
        ],
        if (who != null || notFound) ...[
          const Divider(),
          Muted(tr('Other requests')),
          Opt<String?>(
            value: 'access',
            group: _request,
            onChanged: (v) => _choose(v!),
            title: tr('See or correct my data'),
          ),
          Opt<String?>(
            value: 'erasure',
            group: _request,
            onChanged: (v) => _choose(v!),
            title: tr('Delete my data'),
            subtitle: tr(
              'The office keeps only what the law needs and erases the rest. '
              'This may stop the programme\'s services to them.',
            ),
          ),
          Opt<String?>(value: 'grievance', group: _request, onChanged: (v) => _choose(v!), title: tr('Complaint')),
          const Divider(),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _slip,
            onChanged: (v) => setState(() => _slip = v ?? false),
            title: Text(tr('They gave a paper slip or letter')),
            controlAffinity: ListTileControlAffinity.leading,
          ),
          if (_slip)
            TextField(
              controller: _paper,
              decoration: InputDecoration(labelText: tr('Paper slip number (optional)')),
            ),
        ],
      ],
    );
  }
}
