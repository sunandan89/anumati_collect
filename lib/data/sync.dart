import 'dart:io';

import 'server.dart';
import 'store.dart';

class SyncResult {
  SyncResult({this.synced = 0, this.failed = 0, this.stoppedBy});
  int synced;
  int failed;
  Failure? stoppedBy;
}

/// Sends the outbox to the server, oldest first.
///
/// Every step is idempotent, so a sync cut off halfway is safe to repeat:
/// principals are upserted by reference, the guardian link is looked up
/// before it is created, uploaded evidence URLs are remembered in the row's
/// progress, and the server returns the original artefact when the same
/// event_uuid arrives twice. A record the server rejects is parked as
/// "failed" with the server's reason; a network or login problem stops the
/// run and leaves everything pending.
class Syncer {
  Syncer(this.store, this.server, this.tmpDir);

  final Store store;
  final Server server;
  final Directory tmpDir;

  bool _running = false;
  bool get running => _running;

  Future<SyncResult> run() async {
    final result = SyncResult();
    if (_running) return result;
    _running = true;
    try {
      for (final item in await store.pending()) {
        try {
          final code = await _send(item);
          await store.markSynced(item.id, shortCode: code);
          await _cleanup(item);
          result.synced++;
        } on ServerFailure catch (f) {
          if (f.kind == Failure.rejected) {
            await store.markFailed(item.id, f.message);
            result.failed++;
            continue;
          }
          result.stoppedBy = f.kind;
          break;
        }
      }
    } finally {
      _running = false;
    }
    return result;
  }

  Future<String?> _send(OutboxItem item) async {
    final payload = item.payload;
    switch (item.kind) {
      case 'consent':
        return _consent(item, payload);
      case 'withdraw':
        final art = await server.withdraw(Map<String, dynamic>.from(payload['args'] as Map));
        return art['short_code'] as String?;
      case 'request':
        await server.submitRequest(Map<String, dynamic>.from(payload['args'] as Map));
        return null;
      case 'guardian_needed':
        await server.guardianNeeded(payload['programme'] as String);
        return null;
    }
    throw ServerFailure(Failure.rejected, 'Unknown record type ${item.kind}');
  }

  Future<String?> _consent(OutboxItem item, Map<String, dynamic> payload) async {
    final progress = item.progress;
    Future<void> save() => store.saveProgress(item.id, progress);

    final principal = Map<String, dynamic>.from(payload['principal'] as Map);
    final ref = principal['principal_ref'] as String;
    if (progress['principal'] != true) {
      await server.upsertPrincipal(principal);
      progress['principal'] = true;
      await save();
    }
    final event = Map<String, dynamic>.from(payload['event'] as Map);

    final evidence = List<Map>.from(payload['evidence'] as List? ?? const []);
    final guardianEvidence = List<Map>.from(payload['guardian_evidence'] as List? ?? const []);
    String? principalName;
    if (evidence.isNotEmpty || guardianEvidence.isNotEmpty || payload['guardian'] != null) {
      principalName = await server.principalName(ref);
      if (principalName == null) {
        throw ServerFailure(Failure.rejected, 'Beneficiary $ref was not created');
      }
    }
    final files = Map<String, dynamic>.from(progress['files'] as Map? ?? {});
    Future<void> upload(Map e) async {
      final local = e['local'] as String;
      if (files[local] != null) return;
      final plain = await store.files!.reveal(local, tmpDir);
      try {
        files[local] = await server.uploadEvidence(
          plain,
          principalName!,
          '${event['event_uuid']}-${e['kind']}.${local.split('.').last}',
        );
      } finally {
        if (await plain.exists()) await plain.delete();
      }
      progress['files'] = files;
      await save();
    }

    for (final e in [...evidence, ...guardianEvidence]) {
      await upload(e);
    }

    final guardian = payload['guardian'] as Map?;
    if (guardian != null) {
      final gp = Map<String, dynamic>.from(guardian['principal'] as Map);
      if (progress['guardian_principal'] != true) {
        await server.upsertPrincipal(gp);
        progress['guardian_principal'] = true;
        await save();
      }
      if (progress['guardian_link'] == null) {
        final guardianName = await server.principalName(gp['principal_ref'] as String);
        if (guardianName == null) {
          throw ServerFailure(Failure.rejected, 'Guardian was not created');
        }
        final link = Map<String, dynamic>.from(guardian['link'] as Map)
          ..['principal'] = principalName
          ..['guardian'] = guardianName;
        // The order photo goes in 'evidence', the guardian's ID photo in 'id_document'.
        for (final e in guardianEvidence) {
          link[e['kind'] == 'guardian_document' ? 'id_document' : 'evidence'] ??= files[e['local']];
        }
        progress['guardian_link'] = await server.guardianLink(link);
        await save();
      }
      event['guardian_link'] = progress['guardian_link'];
    }

    if (evidence.isNotEmpty) {
      event['evidence'] = [
        for (final e in evidence) {'file': files[e['local']], 'kind': e['kind'], 'sha256': e['sha256']},
      ];
    }
    final art = await server.record(event);
    return art['short_code'] as String?;
  }

  Future<void> _cleanup(OutboxItem item) async {
    final still = await store.referencedEvidence();
    final payload = item.payload;
    for (final key in ['evidence', 'guardian_evidence']) {
      for (final e in (payload[key] as List? ?? const [])) {
        final id = (e as Map)['local'] as String;
        if (!still.contains(id)) await store.files?.remove(id);
      }
    }
  }
}
