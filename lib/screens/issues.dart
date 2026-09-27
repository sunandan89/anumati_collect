import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../core/strings.dart';
import '../data/store.dart';
import '../widgets/common.dart';

/// Records the server refused, with its reason. The worker can retry (for
/// example after the office fixes the programme) or discard.
class IssuesScreen extends StatefulWidget {
  const IssuesScreen({super.key});
  @override
  State<IssuesScreen> createState() => _IssuesScreenState();
}

class _IssuesScreenState extends State<IssuesScreen> {
  List<OutboxItem> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await context.read<AppState>().store!.failed();
    setState(() => _items = items);
  }

  Future<void> _retry(OutboxItem i) async {
    final s = context.read<AppState>();
    await s.store!.retry(i.id);
    await s.refreshCounts();
    await s.sync();
    await _load();
  }

  Future<void> _discard(OutboxItem i) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(tr('Discard this record? It was never saved on the server.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Discard'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final s = context.read<AppState>();
    await s.store!.discard(i.id);
    await s.countsChanged();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return StepScaffold(
      bar: StepBar(title: tr('Records that need attention')),
      children: [
        for (final i in _items)
          PCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${i.kind} · ${i.principalRef ?? ''} · ${i.shortCode ?? ''}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Muted(i.createdAt.replaceFirst('T', ' ').split('.').first),
                const SizedBox(height: 4),
                Note(i.error ?? '', danger: true),
                const SizedBox(height: 6),
                Row(
                  children: [
                    TextButton(onPressed: () => _retry(i), child: Text(tr('Try again'))),
                    TextButton(onPressed: () => _discard(i), child: Text(tr('Discard'))),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}
