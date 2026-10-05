import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../capture/draft.dart';
import '../core/strings.dart';
import '../data/store.dart';
import '../widgets/common.dart';
import 'add_purpose.dart';
import 'home.dart';
import 'withdraw.dart';

/// Find beneficiary: offline search over people captured on this phone, with
/// each purpose's current status. Also used to pick someone for "Ask for one
/// more purpose".
class FindScreen extends StatefulWidget {
  const FindScreen({super.key, this.pickForAddPurpose = false});
  final bool pickForAddPurpose;
  @override
  State<FindScreen> createState() => _FindScreenState();
}

class _FindScreenState extends State<FindScreen> {
  final _q = TextEditingController();
  List<LocalPrincipal> _rows = [];
  final Map<String, Map<String, String>> _status = {};
  List<NoticePurpose> _purposes = [];

  @override
  void initState() {
    super.initState();
    _load('');
  }

  Future<void> _load(String q) async {
    final s = context.read<AppState>();
    _purposes = (await s.notice('en'))?.purposes ?? [];
    final rows = await s.store!.search(q, programme: s.programme);
    for (final r in rows) {
      _status[r.ref] = await s.store!.decisions(r.ref, r.programme);
    }
    setState(() => _rows = rows);
  }

  /// Tapping a person offers both ways to change their consent; the list above already shows its status.
  Future<void> _actions(LocalPrincipal r) => showModalBottomSheet<void>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(r.fullName, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          ListTile(
            leading: const Icon(Icons.close),
            title: Text(tr('Stop a use or leave')),
            onTap: () {
              Navigator.pop(ctx);
              Navigator.push(context, MaterialPageRoute(builder: (_) => WithdrawScreen(principalRef: r.ref)));
            },
          ),
          ListTile(
            leading: const Icon(Icons.playlist_add),
            title: Text(tr('Add a use or rejoin')),
            onTap: () {
              Navigator.pop(ctx);
              Navigator.push(context, MaterialPageRoute(builder: (_) => AddPurposeScreen(principalRef: r.ref)));
            },
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return StepScaffold(
      bar: StepBar(title: widget.pickForAddPurpose ? tr('Pick a beneficiary on this phone') : tr('Find beneficiary')),
      children: [
        TextField(
          controller: _q,
          autofocus: true,
          onChanged: _load,
          decoration: InputDecoration(
            labelText: tr('Search by name, ID, code or phone'),
            prefixIcon: const Icon(Icons.search),
          ),
        ),
        if (_rows.isEmpty) Muted(tr('No one on this phone matches.')),
        for (final r in _rows)
          PCard(
            onTap: widget.pickForAddPurpose ? () => openAddPurpose(context, r.ref) : () => _actions(r),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.fullName, style: const TextStyle(fontWeight: FontWeight.w600)),
                Muted([r.ref, ?r.lastCode, Strings.languages[r.lang] ?? r.lang].join(' · ')),
                if (phoneMatchLabel(r, _q.text) case final m?) Muted(m),
                const SizedBox(height: 6),
                for (final p in _purposes)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Expanded(child: Text(p.title, style: const TextStyle(fontSize: 13))),
                        StatusChip(statusLabel(_status[r.ref]?[p.code]), tone: statusTone(_status[r.ref]?[p.code])),
                      ],
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
