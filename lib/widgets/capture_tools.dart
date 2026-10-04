import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import '../capture/draft.dart';
import '../core/otp.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../data/store.dart';
import 'common.dart';

/// Take a photo and move it straight into encrypted storage.
Future<EvidenceRef?> capturePhoto(Store store, String kind) async {
  final shot = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 70, maxWidth: 1600);
  if (shot == null) return null;
  final (id, sha) = await store.files!.adopt(File(shot.path), 'jpg');
  return EvidenceRef(id, kind, sha);
}

/// Server-sent code (spec section 5, "Online" rung). After Save, the worker taps Send: this phone syncs the
/// consent, and the server texts a code straight to the person's phone (or their guardian's). This phone
/// never sees the code, so it can't be typed in without the person; they read it out and the worker enters
/// it. Offline, or before SMS is set up, the consent simply stays recorded (confirm later).
class ServerCodePanel extends StatefulWidget {
  const ServerCodePanel({super.key, required this.eventUuid, this.forGuardian = false});
  final String eventUuid;
  final bool forGuardian;

  @override
  State<ServerCodePanel> createState() => _ServerCodePanelState();
}

class _ServerCodePanelState extends State<ServerCodePanel> {
  final _code = TextEditingController();
  bool _busy = false;
  bool _done = false;
  String? _to;
  String? _note;
  bool _noteIsError = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final s = context.read<AppState>();
    setState(() {
      _busy = true;
      _note = null;
    });
    final out = await s.sendCode(widget.eventUuid);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (out['sent'] == true) {
        _to = out['to'] as String? ?? '';
        _note = null;
      } else {
        _noteIsError = out['reason'] != 'offline';
        _note = switch (out['reason']) {
          'offline' => tr('No internet now. The consent is saved and will be confirmed later.'),
          'not_set_up' => tr('SMS codes are not set up yet. The consent is saved and will be confirmed later.'),
          'failed' => tr('The server did not accept this record. See Sync issues on Home.'),
          _ => tr('Could not send the code. Try again in a minute.'),
        };
      }
    });
  }

  Future<void> _check() async {
    final s = context.read<AppState>();
    setState(() => _busy = true);
    final out = await s.checkCode(widget.eventUuid, _code.text.trim());
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (out['confirmed'] == true) {
        _done = true;
        _note = null;
      } else {
        _noteIsError = true;
        _note =
            out['message'] as String? ??
            (out['tries_left'] != null
                ? tr('That code does not match. {0} tries left.', [out['tries_left']])
                : tr('That code does not match. Try again.'));
        _code.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_done) {
      return Row(
        children: [
          const Icon(Icons.check_circle, color: AC.leaf),
          const SizedBox(width: 8),
          Expanded(child: Text(tr('Code matched · consent confirmed'))),
        ],
      );
    }
    return PCard(
      borderColor: AC.leaf,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.forGuardian
                ? tr("Confirm with a code to the guardian's phone")
                : tr('Confirm with a code to their phone'),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          Muted(tr('The code is sent by the server, not from this phone. They read it out to you.')),
          const SizedBox(height: 8),
          if (_to == null)
            FilledButton.icon(
              onPressed: _busy ? null : _send,
              icon: _busy
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.sms_outlined),
              label: Text(tr('Send code')),
            )
          else ...[
            Muted(tr('Code sent to {0}. Ask them to read it out.', [_to!])),
            const SizedBox(height: 6),
            TextField(
              controller: _code,
              keyboardType: TextInputType.number,
              maxLength: 6,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24, letterSpacing: 8),
              onChanged: (v) {
                if (v.length == 6 && !_busy) _check();
              },
            ),
            TextButton(onPressed: _busy ? null : _send, child: Text(tr('Send a new code'))),
          ],
          if (_note != null) Note(_note!, danger: _noteIsError),
        ],
      ),
    );
  }
}

/// Code from the worker's own phone (no internet needed, no SMS cost): opens the SMS app pre-filled to the
/// number (the Play build never sends SMS silently), then checks the code read back. The worker sees this
/// code, so it is always paired with the person's recorded voice "haan" and never counts as confirmed.
class OtpPanel extends StatefulWidget {
  const OtpPanel({super.key, required this.phone, required this.lang, required this.onConfirmed});
  final String phone;
  final String lang;
  final VoidCallback onConfirmed;

  @override
  State<OtpPanel> createState() => _OtpPanelState();
}

class _OtpPanelState extends State<OtpPanel> {
  DeviceOtp? _otp;
  final _code = TextEditingController();
  String? _error;
  bool _done = false;

  Future<void> _open() async {
    final (otp, code) = DeviceOtp.generate();
    setState(() {
      _otp = otp;
      _error = null;
    });
    final body = trFor(widget.lang, 'Your Anumati consent code is {0}. Read it back to the field worker.', [code]);
    final uri = Uri(scheme: 'sms', path: widget.phone, queryParameters: {'body': body});
    await launchUrl(uri);
  }

  void _check() {
    final otp = _otp;
    if (otp == null) return;
    if (otp.verify(_code.text)) {
      setState(() => _done = true);
      widget.onConfirmed();
    } else {
      setState(() {
        _error = otp.locked
            ? tr('Too many wrong codes. Choose another method.')
            : tr('That code does not match. Try again.');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_done) {
      return Row(
        children: [
          const Icon(Icons.check_circle, color: AC.leaf),
          const SizedBox(width: 8),
          Text(tr('Code matched')),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          onPressed: _open,
          icon: const Icon(Icons.sms_outlined),
          label: Text(tr('Open SMS app with code')),
        ),
        if (_otp != null) ...[
          const SizedBox(height: 10),
          Muted(tr('Code they read back')),
          const SizedBox(height: 6),
          TextField(
            controller: _code,
            keyboardType: TextInputType.number,
            maxLength: 6,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 24, letterSpacing: 8),
            onChanged: (v) {
              if (v.length == 6) _check();
            },
          ),
          if (_error != null) Note(_error!, danger: true),
        ],
      ],
    );
  }
}
