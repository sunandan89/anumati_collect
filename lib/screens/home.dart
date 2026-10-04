import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../capture/draft.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import 'add_purpose.dart';
import 'find.dart';
import 'issues.dart';
import 'principal.dart';
import 'withdraw.dart';

/// M1 Home & sync: what is waiting on the phone, the programme, and the
/// four field tasks.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) context.read<AppState>().sync(quiet: true);
  }

  void _showMessage(AppState s) {
    final m = s.takeMessage();
    if (m != null) WidgetsBinding.instance.addPostFrameCallback((_) => toast(context, m));
  }

  Future<void> _pickProgramme(AppState s) async {
    await s.refreshReference();
    if (!mounted) return;
    final chosen = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: Text(tr('Choose a programme'), style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            if (s.programmes.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(tr('No programmes yet. Ask your admin to give you access to a programme.')),
              ),
            for (final p in s.programmes)
              ListTile(
                title: Text(p['programme_name'] as String? ?? p['name'] as String),
                subtitle: Text(p['name'] as String),
                trailing: p['name'] == s.programme ? const Icon(Icons.check, color: AC.leaf) : null,
                onTap: () => Navigator.pop(ctx, p['name'] as String),
              ),
          ],
        ),
      ),
    );
    if (chosen != null) await s.selectProgramme(chosen);
  }

  Future<bool> _requireNotice(AppState s) async {
    if (s.programme == null) {
      await _pickProgramme(s);
      if (s.programme == null) return false;
    }
    if (await s.notice('en') == null) {
      if (mounted) toast(context, tr('This programme has no published notice yet.'));
      return false;
    }
    return true;
  }

  Future<void> _signOut(AppState s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Sign out')),
        content: Text(
          [
            tr('Sign out and remove all data from this phone?'),
            if (s.pending + s.failed > 0)
              tr('{0} records are not synced yet and will be lost.', [s.pending + s.failed]),
          ].join('\n\n'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Sign out'))),
        ],
      ),
    );
    if (ok == true) await s.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    _showMessage(s);
    final waiting = s.pending;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Container(
              color: AC.leaf,
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(s.programmeName, style: const TextStyle(fontSize: 12, color: AC.leafInk)),
                            Text(
                              tr('Namaste, {0}', [s.userName.split(' ').first]),
                              style: const TextStyle(fontSize: 24, color: AC.leafInk, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert, color: AC.leafInk),
                        onSelected: (v) {
                          if (v == 'out') _signOut(s);
                          if (v == 'en' || v == 'hi') s.setUiLang(v);
                        },
                        itemBuilder: (_) => [
                          for (final e in Strings.languages.entries)
                            CheckedPopupMenuItem(value: e.key, checked: Strings.uiLang == e.key, child: Text(e.value)),
                          const PopupMenuDivider(),
                          PopupMenuItem(value: 'out', child: Text(tr('Sign out'))),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                tr('{0} records on this phone', [waiting]),
                                style: const TextStyle(color: AC.leafInk, fontWeight: FontWeight.w600),
                              ),
                              Text(
                                waiting > 0 ? tr('Sync when you have data') : tr('Everything is signed on the server'),
                                style: const TextStyle(color: AC.leafInk, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFF4F8EF),
                            foregroundColor: AC.leaf,
                            minimumSize: const Size(0, 40),
                          ),
                          onPressed: s.syncing ? null : () => s.sync(),
                          icon: s.syncing
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.sync, size: 18),
                          label: Text(s.syncing ? tr('Syncing…') : tr('Sync')),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  await s.refreshReference();
                  await s.sync();
                },
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (s.failed > 0) ...[
                      PCard(
                        color: AC.dangerSoft,
                        borderColor: AC.danger,
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const IssuesScreen())),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline, color: AC.danger),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                tr('{0} records could not be saved on the server. Open to see why.', [s.failed]),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    Muted(tr('Programme')),
                    const SizedBox(height: 6),
                    PCard(
                      onTap: () => _pickProgramme(s),
                      child: Row(
                        children: [
                          Expanded(child: Text(s.programme == null ? tr('Choose a programme') : s.programmeName)),
                          Text(tr('Change'), style: const TextStyle(color: AC.terra, fontSize: 13)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Tile(
                      icon: Icons.add,
                      title: tr('Take new consent'),
                      subtitle: tr('Self, assisted or guardian'),
                      onTap: () async {
                        if (!await _requireNotice(s) || !context.mounted) return;
                        final draft = CaptureDraft(programme: s.programme!, deviceId: s.deviceId)
                          ..allowedMethods = s.allowedVerification
                          ..codesFromWorkerPhone = s.workerPhoneCodes
                          ..online = await s.online();
                        draft.lang = Strings.uiLang;
                        draft.notice = await s.notice(draft.lang);
                        if (!context.mounted) return;
                        Navigator.push(context, MaterialPageRoute(builder: (_) => PrincipalScreen(draft: draft)));
                      },
                    ),
                    const SizedBox(height: 10),
                    Tile(
                      icon: Icons.close,
                      title: tr('Stop or change consent'),
                      subtitle: tr('Told in person, slip or letter'),
                      onTap: () async {
                        if (!await _requireNotice(s) || !context.mounted) return;
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const WithdrawScreen()));
                      },
                    ),
                    const SizedBox(height: 10),
                    Tile(
                      icon: Icons.playlist_add,
                      title: tr('Ask for one more purpose'),
                      subtitle: tr('Existing beneficiary, new use'),
                      onTap: () async {
                        if (!await _requireNotice(s) || !context.mounted) return;
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const FindScreen(pickForAddPurpose: true)),
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                    Tile(
                      icon: Icons.search,
                      title: tr('Find beneficiary'),
                      subtitle: tr('See consent status offline'),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FindScreen())),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Opens the add-purpose flow for a picked principal.
void openAddPurpose(BuildContext context, String ref) {
  Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AddPurposeScreen(principalRef: ref)));
}
