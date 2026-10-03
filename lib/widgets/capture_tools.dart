import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

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

/// Device SMS OTP panel: opens the SMS app pre-filled to the number (the Play
/// build never sends SMS silently), then checks the code read back.
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
